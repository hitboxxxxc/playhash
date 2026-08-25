/**
 * Processador de RECOMPENSAS POR ANÚNCIO (adRewardIntents) — doc 04/05 §31.
 *
 * O cliente SÓ registra a intenção: após `onUserEarnedReward` do SDK AdMob,
 * cria `adRewardIntents/{clientRequestId}` (campos exatos nas rules). Este
 * processador, para cada intent pendente:
 *  1. lê a config ATIVA (config/ads — dailyLimit/cooldown/reward/xpBonus);
 *  2. valida: type=='rewarded', conta ativa (antifraude), limite diário por
 *     uid (contador PRÓPRIO em rateLimits/{uid}, prefixo 'adRewards') e
 *     cooldown desde a ÚLTIMA concessão do dia;
 *  3. EM TRANSAÇÃO: credita reward.amountUnits em wallets/{uid}
 *     (availableBalance), aplica xpBonus em seasonProgress/{uid} (xp/level,
 *     nível só sobe) e grava adRewards/{intentId} {uid,type,rewards,status,
 *     processedAt,periodKey};
 *  4. audita AD_REWARD_GRANTED (eventId determinístico ⇒ idempotente) e
 *     grava espelho rewards/{uid}/items/AD_REWARD_{id} (type AD_REWARD);
 *  5. incrementa o contador diário APÓS conceder.
 *
 * Idempotência: doc id = clientRequestId; transação re-lê status='pending'
 * (concorrência entre runs é segura). Falhas viram failed com código SEGURO
 * (DAILY_LIMIT_REACHED / COOLDOWN_ACTIVE / ACCOUNT_BLOCKED / ADS_DISABLED).
 *
 * validateAdReward é PURA e unit-testável sem Firestore.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { EconomyConfig, ProcessingSummary } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { writeAudit, auditEventId } from '../core/audit';
import { readDailyCounter, incrementDailyCounter, utcDayKey } from '../core/ratelimit';

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável)
// ---------------------------------------------------------------------------

export interface AdsRewardedConfig {
  enabled: boolean;
  dailyLimit: number;
  cooldownMinutes: number;
  /** Recompensa em units (BigInt). */
  rewardUnits: bigint;
  xpBonus: number;
}

export interface AdRewardValidationInput {
  uid: string;
  type: string;
  clientRequestId: string;
  config: AdsRewardedConfig | null;
  /** Concessões já feitas HOJE para este uid (contador próprio). */
  todayCount: number;
  /** Timestamp (ms) da última concessão do dia (null se nenhuma). */
  lastGrantedAtMs: number | null;
  nowMs: number;
  /** Status da conta ('active' esperado; 'review'/'blocked' ⇒ bloqueado). */
  accountStatus: string;
}

export type AdRewardValidation =
  | { ok: true; rewardUnits: bigint; xpBonus: number }
  | { ok: false; code: string };

export function validateAdReward(input: AdRewardValidationInput): AdRewardValidation {
  if (!input.uid || input.type !== 'rewarded' || input.clientRequestId.length < 8) {
    return { ok: false, code: 'INVALID_FIELDS' };
  }
  if (!input.config || !input.config.enabled) {
    return { ok: false, code: 'ADS_DISABLED' };
  }
  if (input.config.rewardUnits <= 0n) {
    return { ok: false, code: 'ADS_DISABLED' };
  }
  // Antifraude: contas em revisão/bloqueadas NÃO recebem recompensa.
  const status = input.accountStatus || 'active';
  if (status !== 'active') {
    return { ok: false, code: 'ACCOUNT_BLOCKED' };
  }
  if (input.todayCount >= input.config.dailyLimit) {
    return { ok: false, code: 'DAILY_LIMIT_REACHED' };
  }
  if (
    input.lastGrantedAtMs !== null &&
    input.nowMs - input.lastGrantedAtMs < input.config.cooldownMinutes * 60_000
  ) {
    return { ok: false, code: 'COOLDOWN_ACTIVE' };
  }
  return { ok: true, rewardUnits: input.config.rewardUnits, xpBonus: input.config.xpBonus };
}

/** periodKey UTC do dia (mesma chave usada pelo espelho/cliente). */
function periodKeyOf(nowMs: number): string {
  return utcDayKey(nowMs);
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

interface PendingIntent {
  id: string;
  uid: string;
  type: string;
  clientRequestId: string;
}

function parseIntent(id: string, data: FirebaseFirestore.DocumentData): PendingIntent | null {
  const uid = data.uid;
  const type = data.type;
  const clientRequestId = data.clientRequestId;
  if (typeof uid !== 'string' || uid.length === 0) return null;
  if (type !== 'rewarded') return null;
  if (typeof clientRequestId !== 'string' || clientRequestId.length < 8) return null;
  return { id, uid, type, clientRequestId };
}

function parseAdsConfig(snap: FirebaseFirestore.DocumentSnapshot): AdsRewardedConfig | null {
  if (!snap.exists) return null;
  const rewarded = snap.get('rewarded') as Record<string, unknown> | undefined;
  if (rewarded == null) return null;
  const amount = Number((rewarded.reward as Record<string, unknown> | undefined)?.amountUnits);
  const limit = Number(rewarded.dailyLimit);
  const cooldown = Number(rewarded.cooldownMinutes);
  const xpBonus = Number(rewarded.xpBonus ?? 0);
  return {
    enabled: snap.get('enabled') !== false && Number.isSafeInteger(limit) && limit > 0,
    dailyLimit: Number.isSafeInteger(limit) ? limit : 0,
    cooldownMinutes: Number.isSafeInteger(cooldown) && cooldown >= 0 ? cooldown : 0,
    rewardUnits: Number.isSafeInteger(amount) && amount > 0 ? BigInt(amount) : 0n,
    xpBonus: Number.isSafeInteger(xpBonus) && xpBonus > 0 ? xpBonus : 0,
  };
}

async function failIntent(
  db: Firestore,
  intent: PendingIntent,
  code: string,
  ruleVersion: number,
): Promise<'rejected'> {
  await db.doc(`adRewardIntents/${intent.id}`).update({
    status: 'failed',
    failureCode: code,
    processedAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, {
    eventId: auditEventId('AD_REWARD_REJECTED', intent.id),
    userId: intent.uid,
    type: 'AD_REWARD_REJECTED',
    referenceId: intent.id,
    origin: 'runner.processAdRewards',
    ruleVersion,
    status: 'REJECTED',
    detail: { failureCode: code },
  });
  return 'rejected';
}

async function handleIntent(
  db: Firestore,
  economy: EconomyConfig,
  intentSnap: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const intent = parseIntent(intentSnap.id, intentSnap.data());
  const ruleVersion = economy.economicRuleVersion;
  if (!intent) {
    await intentSnap.ref.update({
      status: 'failed',
      failureCode: 'INVALID_FIELDS',
      processedAt: FieldValue.serverTimestamp(),
    });
    return 'rejected';
  }

  try {
    // Config ativa (autoridade econômica — nunca valores do cliente).
    const adsSnap = await db.doc('config/ads').get();
    const config = parseAdsConfig(adsSnap);

    // Conta (antifraude simples: status != active bloqueia).
    const userSnap = await db.doc(`users/${intent.uid}`).get();
    const accountStatus = String(userSnap.get('status') ?? 'active');

    // Contador diário PRÓPRIO (prefixo adRewards) + cooldown via última
    // concessão do dia. Janela de corrida entre runs aceitável (documentada):
    // o pior caso concede 1 coin extra em corrida — risco ínfimo e auditado.
    const todayCount = await readDailyCounter(db, intent.uid, 'adRewards', nowMs);
    const periodKey = periodKeyOf(nowMs);
    const lastSnap = await db
      .collection('adRewards')
      .where('uid', '==', intent.uid)
      .where('periodKey', '==', periodKey)
      .orderBy('processedAt', 'desc')
      .limit(1)
      .get();
    const lastDoc = lastSnap.docs[0];
    const lastGrantedAtMs: number | null = lastDoc
      ? (lastDoc.get('processedAt')?.toMillis?.() ?? null)
      : null;

    const validation = validateAdReward({
      uid: intent.uid,
      type: intent.type,
      clientRequestId: intent.clientRequestId,
      config,
      todayCount,
      lastGrantedAtMs,
      nowMs,
      accountStatus,
    });
    if (!validation.ok) {
      return await failIntent(db, intent, validation.code, ruleVersion);
    }

    // levelXp da temporada ativa (para derivar nível ao aplicar xpBonus).
    const seasonSnap = await db.collection('seasons').orderBy('startAt', 'desc').limit(1).get();
    const seasonDoc = seasonSnap.docs[0];
    const seasonId = seasonDoc ? String(seasonDoc.id) : '';
    const levelXp = seasonDoc ? Number(seasonDoc.get('levelXp') ?? 1200) : 1200;

    type TxOutcome = { kind: 'ok' } | { kind: 'fail'; code: string } | { kind: 'skip' };
    const outcome: TxOutcome = await db.runTransaction(async (tx): Promise<TxOutcome> => {
      const fresh = await tx.get(intentSnap.ref);
      if (!fresh.exists || fresh.get('status') !== 'pending') {
        return { kind: 'skip' }; // já processada por outra execução
      }

      // Crédito de 1 COIN na wallet (valor 100% da config — nunca do cliente).
      const walletRef = db.doc(`wallets/${intent.uid}`);
      const walletSnap = await tx.get(walletRef);
      const balance = walletSnap.exists
        ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
        : 0n;
      tx.set(
        walletRef,
        {
          uid: intent.uid,
          availableBalance: (balance + validation.rewardUnits).toString(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // xpBonus em seasonProgress (nível só sobe; sem temporada ativa ⇒ só xp).
      if (validation.xpBonus > 0) {
        const progressRef = db.doc(`seasonProgress/${intent.uid}`);
        const progressSnap = await tx.get(progressRef);
        const currentXp = Number(progressSnap.get('xp') ?? 0);
        const currentLevel = Number(progressSnap.get('level') ?? 1);
        const nextXp =
          (Number.isSafeInteger(currentXp) ? currentXp : 0) + validation.xpBonus;
        const nextLevel = Math.max(
          Math.floor(nextXp / (Number.isSafeInteger(levelXp) && levelXp > 0 ? levelXp : 1200)) + 1,
          Number.isSafeInteger(currentLevel) ? currentLevel : 1,
        );
        tx.set(
          progressRef,
          {
            uid: intent.uid,
            ...(seasonId ? { seasonId } : {}),
            xp: nextXp,
            level: nextLevel,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      // Registro da recompensa CONCEDIDA (doc id = intentId ⇒ idempotente).
      tx.set(
        db.doc(`adRewards/${intent.id}`),
        {
          uid: intent.uid,
          type: 'rewarded',
          rewards: { type: 'coins', amountUnits: validation.rewardUnits.toString() },
          xpBonus: validation.xpBonus,
          status: 'granted',
          processedAt: FieldValue.serverTimestamp(),
          periodKey,
        },
        { merge: false },
      );

      tx.update(intentSnap.ref, {
        status: 'done',
        rewardUnits: validation.rewardUnits.toString(),
        processedAt: FieldValue.serverTimestamp(),
      });
      return { kind: 'ok' };
    });

    if (outcome.kind === 'skip') return 'rejected';
    if (outcome.kind === 'fail') {
      return await failIntent(db, intent, outcome.code, ruleVersion);
    }

    await writeAudit(db, {
      eventId: auditEventId('AD_REWARD_GRANTED', intent.id),
      userId: intent.uid,
      type: 'AD_REWARD_GRANTED',
      valueUnits: validation.rewardUnits,
      currencyId: 'coins',
      referenceId: intent.id,
      origin: 'runner.processAdRewards',
      ruleVersion,
      status: 'SUCCESS',
      detail: { xpBonus: validation.xpBonus, periodKey },
    });

    // Espelho de histórico (id determinístico ⇒ idempotente).
    await db
      .doc(`rewards/${intent.uid}/items/AD_REWARD_${intent.id}`)
      .create({
        type: 'AD_REWARD',
        amount: validation.rewardUnits.toString(),
        currencyId: 'coins',
        createdAt: FieldValue.serverTimestamp(),
        referenceId: intent.id,
      });

    // Contador diário APÓS conceder (limite diário por uid/data).
    await incrementDailyCounter(db, intent.uid, 'adRewards', nowMs);
    return 'granted';
  } catch (err) {
    console.error(
      `[processAdRewards] intent=${intent.id} failed: ${String((err as Error)?.message ?? err).slice(0, 300)}`,
    );
    return 'failed';
  }
}

/** Ponto de entrada do runner. */
export async function processAdRewards(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor

  const snap = await db
    .collection('adRewardIntents')
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
