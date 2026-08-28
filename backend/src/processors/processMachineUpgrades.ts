/**
 * Processador de intenções de upgrade de máquinas (machineUpgradeIntents).
 *
 * Para cada intent pendente: transação admin que lê preço/poder/limites
 * SOMENTE da config (config/catalog/machines/{machineId} — catálogo v2), valida saldo
 * em wallets/{uid}, nível atual < maxLevel, debita availableBalance,
 * incrementa level em machines/{uid}/items/{itemId}, recalcula power,
 * soma ao totalPower, marca intent done/failed.
 * Idempotência por clientRequestId.
 * Auditoria MACHINE_UPGRADED.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { EconomyConfig, ProcessingSummary } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { recalcPower } from '../core/power';
import { writeAudit, auditEventId } from '../core/audit';
import { findDoneIntentByClientRequestId } from '../core/idempotency';

interface PendingIntent {
  id: string;
  uid: string;
  machineId: string;
  clientRequestId: string;
}

async function failIntent(
  db: Firestore,
  intent: PendingIntent,
  failureCode: string,
  ruleVersion: number,
): Promise<'rejected'> {
  await db.doc(`machineUpgradeIntents/${intent.id}`).update({
    status: 'failed',
    failureCode,
    processedAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, {
    eventId: auditEventId('MACHINE_UPGRADE_FAILED', intent.id),
    userId: intent.uid,
    type: 'MACHINE_UPGRADE_FAILED',
    referenceId: intent.id,
    origin: 'runner.processMachineUpgrades',
    ruleVersion,
    status: 'REJECTED',
    detail: { failureCode, machineId: intent.machineId },
  });
  return 'rejected';
}

async function handleIntent(
  db: Firestore,
  economy: EconomyConfig,
  intentSnap: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const intentId = intentSnap.id;
  const data = intentSnap.data();
  const ruleVersion = economy.economicRuleVersion;

  const intent: PendingIntent = {
    id: intentId,
    uid: String(data.uid ?? ''),
    machineId: String(data.machineId ?? ''),
    clientRequestId: String(data.clientRequestId ?? ''),
  };

  try {
    if (!intent.uid || !intent.machineId || intent.clientRequestId.length < 8) {
      return await failIntent(db, intent, 'INVALID_INTENT_FIELDS', ruleVersion);
    }

    const doneRef = await findDoneIntentByClientRequestId(
      db,
      intent.uid,
      intent.clientRequestId,
    );
    if (doneRef !== null) {
      return await failIntent(db, intent, 'DUPLICATE_CLIENT_REQUEST_ID', ruleVersion);
    }

    const machineConfigSnap = await db.doc(`config/catalog/machines/${intent.machineId}`).get();
    if (!machineConfigSnap.exists) {
      return await failIntent(db, intent, 'INVALID_MACHINE', ruleVersion);
    }
    const machineConfig = machineConfigSnap.data()!;
    const maxLevel = machineConfig.maxLevel ?? 1;
    const basePower = toInt(machineConfig.powerUnits ?? 0);
    const priceUnits = toInt(machineConfig.priceUnits ?? 0);
    const priceCoins = Number(priceUnits) / 1_000_000; // price in coins

    type TxOutcome =
      | { kind: 'ok'; newLevel: number }
      | { kind: 'fail'; code: string }
      | { kind: 'skip' };

    const outcome: TxOutcome = await db.runTransaction(async (tx): Promise<TxOutcome> => {
      const fresh = await tx.get(intentSnap.ref);
      if (!fresh.exists || fresh.get('status') !== 'pending') {
        return { kind: 'skip' };
      }

      // Encontrar a máquina do usuário
      const ownedQuery = db
        .collection(`machines/${intent.uid}/items`)
        .where('machineId', '==', intent.machineId)
        .limit(1);
      const ownedSnap = await tx.get(ownedQuery);
      if (ownedSnap.empty) {
        return { kind: 'fail', code: 'MACHINE_NOT_OWNED' };
      }
      const itemRef = ownedSnap.docs[0].ref;
      const itemData = ownedSnap.docs[0].data();
      const currentLevel = Number(itemData.level ?? 1);

      if (currentLevel >= maxLevel) {
        return { kind: 'fail', code: 'MAX_LEVEL_REACHED' };
      }

      const nextLevel = currentLevel + 1;
      // Fórmula UPGRADE v2 (14.10): custo = 60% × preçoCoins × 1.6^(n-1)
      const upgradeCostCoins = Math.round(priceCoins * Math.pow(1.6, currentLevel - 1) * 0.6);
      const upgradeCost = BigInt(upgradeCostCoins * 1_000_000);

      const walletRef = db.doc(`wallets/${intent.uid}`);
      const walletSnap = await tx.get(walletRef);
      const balance = walletSnap.exists
        ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
        : 0n;

      if (balance < upgradeCost) {
        return { kind: 'fail', code: 'INSUFFICIENT_BALANCE' };
      }

      // Fórmula UPGRADE v2 (14.10): power = basePower × (9 + level) / 10
      const newPower = BigInt(Math.floor(Number(basePower) * (9 + nextLevel) / 10));
      const oldPower = BigInt(itemData.powerAmount ?? 0);
      const powerDiff = newPower - oldPower;

      tx.update(itemRef, {
        level: nextLevel,
        powerAmount: newPower.toString(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      tx.update(walletRef, {
        availableBalance: (balance - upgradeCost).toString(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const powerRef = db.doc(`power/${intent.uid}`);
      const powerSnap = await tx.get(powerRef);
      const permanent = powerSnap.exists
        ? toInt((powerSnap.get('permanentPower') ?? 0) as number | string)
        : 0n;
      tx.set(
        powerRef,
        {
          permanentPower: (permanent + powerDiff).toString(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.update(intentSnap.ref, {
        status: 'done',
        newLevel: nextLevel,
        costPaidUnits: upgradeCost.toString(),
        processedAt: FieldValue.serverTimestamp(),
      });

      return { kind: 'ok', newLevel: nextLevel };
    });

    if (outcome.kind === 'skip') return 'rejected';
    if (outcome.kind === 'fail') {
      return await failIntent(db, intent, outcome.code, ruleVersion);
    }

    await recalcPower(db, intent.uid, nowMs, {
      ruleVersion,
      origin: 'runner.processMachineUpgrades',
    });
    await writeAudit(db, {
      eventId: auditEventId('MACHINE_UPGRADED', intentId),
      userId: intent.uid,
      type: 'MACHINE_UPGRADED',
      referenceId: intentId,
      origin: 'runner.processMachineUpgrades',
      ruleVersion,
      status: 'SUCCESS',
      detail: { machineId: intent.machineId, newLevel: outcome.newLevel },
    });
    return 'granted';
  } catch (err) {
    console.error(
      `[processMachineUpgrades] intent=${intentId} failed: ${String(err).slice(0, 300)}`,
    );
    return 'failed';
  }
}

export async function processMachineUpgrades(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now();

  const snap = await db
    .collection('machineUpgradeIntents')
    .where('status', '==', 'pending')
    .orderBy('createdAt', 'asc')
    .limit(economy.limits.maxBatchSize)
    .get();

  const summary: ProcessingSummary = { scanned: snap.size, granted: 0, rejected: 0, failed: 0 };
  for (const doc of snap.docs) {
    const outcome = await handleIntent(db, economy, doc, nowMs);
    summary[outcome] += 1;
  }
  return summary;
}
