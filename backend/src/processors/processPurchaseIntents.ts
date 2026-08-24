/**
 * Processador de intenções de compra (purchaseIntents).
 *
 * Para cada intent pendente: transação admin que lê preço/poder/limites
 * SOMENTE da config (config/machines/{machineId} — catálogo v2), valida saldo
 * em wallets/{uid}, maxPerUser e enabled, debita availableBalance, cria
 * machines/{uid}/items/{itemId}, soma permanentPower, marca intent
 * done/failed. Idempotência por clientRequestId.
 * Auditoria MACHINE_PURCHASED / PURCHASE_FAILED + espelho de histórico em
 * rewards/{uid}/items (mesmo padrão do espelho de blocos).
 *
 * validatePurchase é PURA e unit-testável sem Firestore.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { EconomyConfig, MachineDoc, ProcessingSummary } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { recalcPower } from '../core/power';
import { writeAudit, auditEventId } from '../core/audit';
import { findDoneIntentByClientRequestId } from '../core/idempotency';
import { incrementDailyCounter, readDailyCounter } from '../core/ratelimit';
import { bumpAchievementProgress, bumpMissionProgress } from './mission_progress';

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável)
// ---------------------------------------------------------------------------

export type PurchaseValidation = { ok: true } | { ok: false; failureCode: string };

export function validatePurchase(
  balanceUnits: bigint,
  priceUnits: bigint,
  ownedCount = 0,
  maxPerUser = 0,
): PurchaseValidation {
  if (priceUnits <= 0n) return { ok: false, failureCode: 'INVALID_PRICE' };
  if (maxPerUser > 0 && ownedCount >= maxPerUser) {
    return { ok: false, failureCode: 'MAX_PER_USER_REACHED' };
  }
  if (balanceUnits < priceUnits) return { ok: false, failureCode: 'INSUFFICIENT_BALANCE' };
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

interface PendingIntent {
  id: string;
  uid: string;
  machineId: string;
  clientRequestId: string;
}

function parseMachine(id: string, snap: FirebaseFirestore.DocumentSnapshot): MachineDoc | null {
  if (!snap.exists) return null;
  if (snap.get('enabled') !== true) return null;
  const price = toInt((snap.get('priceUnits') ?? -1) as number | string);
  // v2 usa powerUnits (H/s); legado usava powerAmount.
  const powerRaw = snap.get('powerUnits') ?? snap.get('powerAmount') ?? -1;
  const power = toInt(powerRaw as number | string);
  if (price <= 0n || power <= 0n) return null;
  const maxPerUserRaw = snap.get('maxPerUser');
  return {
    id,
    name: String(snap.get('name') ?? id),
    priceUnits: price,
    powerAmount: power,
    currencyId: String(snap.get('currencyId') ?? 'coins'),
    enabled: true,
    rarity: String(snap.get('rarity') ?? '').toLowerCase(),
    maxPerUser:
      typeof maxPerUserRaw === 'number' && Number.isSafeInteger(maxPerUserRaw) && maxPerUserRaw > 0
        ? maxPerUserRaw
        : 0,
  };
}

async function failIntent(
  db: Firestore,
  intent: PendingIntent,
  failureCode: string,
  ruleVersion: number,
): Promise<'rejected'> {
  await db.doc(`purchaseIntents/${intent.id}`).update({
    status: 'failed',
    failureCode,
    processedAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, {
    eventId: auditEventId('PURCHASE_FAILED', intent.id),
    userId: intent.uid,
    type: 'PURCHASE_FAILED',
    referenceId: intent.id,
    origin: 'runner.processPurchaseIntents',
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

    // Idempotência por clientRequestId (dedupe fora da transação).
    const doneRef = await findDoneIntentByClientRequestId(
      db,
      intent.uid,
      intent.clientRequestId,
    );
    if (doneRef !== null) {
      return await failIntent(db, intent, 'DUPLICATE_CLIENT_REQUEST_ID', ruleVersion);
    }

    const intentsToday = await readDailyCounter(db, intent.uid, 'intents', nowMs);
    if (intentsToday >= economy.limits.maxPurchaseIntentsPerDay) {
      return await failIntent(db, intent, 'DAILY_LIMIT_REACHED', ruleVersion);
    }

    // Preço/poder/limites lidos SOMENTE da config (nunca do cliente).
    // Catálogo em config/catalog/machines (4 segmentos — par obrigatório).
    const machineSnap = await db.doc(`config/catalog/machines/${intent.machineId}`).get();
    const machine = parseMachine(intent.machineId, machineSnap);
    if (!machine) {
      return await failIntent(db, intent, 'INVALID_MACHINE', ruleVersion);
    }

    type TxOutcome =
      | { kind: 'ok'; itemId: string }
      | { kind: 'fail'; code: string }
      | { kind: 'skip' };

    const outcome: TxOutcome = await db.runTransaction(async (tx): Promise<TxOutcome> => {
      const fresh = await tx.get(intentSnap.ref);
      if (!fresh.exists || fresh.get('status') !== 'pending') {
        return { kind: 'skip' }; // já processada por outra execução
      }
      const walletRef = db.doc(`wallets/${intent.uid}`);
      const walletSnap = await tx.get(walletRef);
      const balance = walletSnap.exists
        ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
        : 0n;

      const check = validatePurchase(balance, machine.priceUnits);
      if (!check.ok) return { kind: 'fail', code: check.failureCode };

      // maxPerUser: contagem de itens do MESMO machineId já owned (dentro da
      // transação — sem janela de corrida).
      if (machine.maxPerUser > 0) {
        const ownedSnap = await tx.get(
          db
            .collection(`machines/${intent.uid}/items`)
            .where('machineId', '==', machine.id)
            .limit(machine.maxPerUser + 1),
        );
        const check = validatePurchase(1n, 1n, ownedSnap.size, machine.maxPerUser);
        if (!check.ok) return { kind: 'fail', code: check.failureCode };
      }

      const itemRef = db.collection(`machines/${intent.uid}/items`).doc();
      tx.create(itemRef, {
        machineId: machine.id,
        name: machine.name,
        rarity: machine.rarity,
        level: 1,
        active: true,
        powerAmount: machine.powerAmount.toString(),
        currencyId: machine.currencyId,
        pricePaidUnits: machine.priceUnits.toString(),
        purchaseIntentId: intentId,
        acquiredAt: FieldValue.serverTimestamp(),
        economicRuleVersion: ruleVersion,
      });

      tx.update(walletRef, {
        availableBalance: (balance - machine.priceUnits).toString(),
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
          uid: intent.uid,
          permanentPower: (permanent + machine.powerAmount).toString(),
          economicRuleVersion: ruleVersion,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.update(intentSnap.ref, {
        status: 'done',
        machineItemId: itemRef.id,
        pricePaidUnits: machine.priceUnits.toString(),
        processedAt: FieldValue.serverTimestamp(),
      });
      return { kind: 'ok', itemId: itemRef.id };
    });

    if (outcome.kind === 'skip') return 'rejected'; // já processado anteriormente
    if (outcome.kind === 'fail') {
      return await failIntent(db, intent, outcome.code, ruleVersion);
    }

    // Recalcula totalPower (permanentPower mudou) e audita.
    await recalcPower(db, intent.uid, nowMs, {
      ruleVersion,
      origin: 'runner.processPurchaseIntents',
    });
    await writeAudit(db, {
      eventId: auditEventId('MACHINE_PURCHASED', intentId),
      userId: intent.uid,
      type: 'MACHINE_PURCHASED',
      valueUnits: machine.priceUnits,
      currencyId: machine.currencyId,
      referenceId: intentId,
      origin: 'runner.processPurchaseIntents',
      ruleVersion,
      status: 'SUCCESS',
      detail: { machineId: machine.id, machineItemId: outcome.itemId },
    });
    // Espelho de histórico (rewards/{uid}/items) — mesmo padrão do espelho
    // de blocos: id determinístico ⇒ reexecução não duplica a entrada.
    await db
      .doc(`rewards/${intent.uid}/items/MACHINE_PURCHASE_${intentId}`)
      .create({
        type: 'MACHINE_PURCHASE',
        amount: (-machine.priceUnits).toString(),
        currencyId: machine.currencyId,
        createdAt: FieldValue.serverTimestamp(),
        referenceId: intentId,
      });
    // Progresso de missões/conquistas a partir da compra REAL concluída
    // (transação done ⇒ idempotente; reexecução cai no 'skip'/'rejected').
    await bumpMissionProgress(db, intent.uid, 'buys', 'add', 1, nowMs);
    // Máquinas owned recalculadas (conquistas a_machines_1/a_machines_5).
    const ownedSnap = await db
      .collection(`machines/${intent.uid}/items`)
      .limit(1000)
      .get();
    await bumpAchievementProgress(db, intent.uid, 'machines', 'max', ownedSnap.size);
    await incrementDailyCounter(db, intent.uid, 'intents', nowMs);
    return 'granted';
  } catch (err) {
    console.error(
      `[processPurchaseIntents] intent=${intentId} failed: ${sanitize(err)}`,
    );
    return 'failed';
  }
}

function sanitize(err: unknown): string {
  return String((err as Error)?.message ?? err).slice(0, 300);
}

/** Ponto de entrada do runner. */
export async function processPurchaseIntents(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor

  const snap = await db
    .collection('purchaseIntents')
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
