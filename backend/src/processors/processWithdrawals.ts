/**
 * Processador de SAQUES (withdrawalIntents → withdrawals) — doc 05 §26/§51.
 *
 * O cliente SÓ cria a intenção (rules: campos exatos). Toda a validação,
 * reserva, pagamento e estorno acontecem AQUI (runner = autoridade econômica):
 *   1. Validações antifraude (ativas habilitada, mínimo, saldo, cooldown 24h,
 *      maxPerDay, idade da conta, ≥1 gameSession finished, sem flag review,
 *      formato de endereço por rede);
 *   2. Transação de RESERVA: availableBalance −= amount, pendingBalance +=
 *      amount, withdrawals/{clientRequestId} status='processing',
 *      transactions WITHDRAWAL_RESERVE;
 *   3. Payout via PayoutProvider (PAYOUT_MODE: test|live):
 *      completed → status completed + providerReference + pendingBalance −=
 *      amount + auditoria WITHDRAWAL_COMPLETED;
 *      failed    → ESTORNO (available += amount, pending −= amount,
 *      transactions REVERSAL) + auditoria WITHDRAWAL_FAILED/REWARD_REVERSED.
 *
 * IDEMPOTÊNCIA: o doc de saque usa o clientRequestId como ID ⇒ reserva é
 * única; crash entre reserva e payout retoma na próxima run SEM duplicar
 * (withdrawal 'processing' existente segue direto para o passo de payout).
 *
 * ANTIFRAUDE §36: tentativas inválidas são auditadas com código seguro;
 * 3+ falhas de ELEGIBILIDADE no dia ⇒ users/{uid}.status='review'
 * (bloqueia saques até análise) + auditoria ACCOUNT_ECONOMIC_LOCK.
 *
 * PRIVACIDADE: endereço completo NUNCA vai para logs/auditoria — apenas
 * addressMasked. Credenciais nunca são logadas.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { ProcessingSummary } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { writeAudit, auditEventId } from '../core/audit';
import { counterKey, utcDayKey } from '../core/ratelimit';
import {
  PayoutProvider,
  PayoutRequest,
} from '../providers/payout_provider';
import { TestProvider } from '../providers/test_provider';
import { FaucetPayProvider } from '../providers/faucetpay_provider';

// ---------------------------------------------------------------------------
// Config de payouts (config/payouts)
// ---------------------------------------------------------------------------

export interface PayoutAssetConfig {
  id: string;
  network: string;
  enabled: boolean;
  minWithdrawUnits: bigint;
  feeUnits: bigint;
}

export interface PayoutsConfig {
  assets: PayoutAssetConfig[];
  cooldownHours: number;
  maxPerDay: number;
  minAccountAgeHours: number;
  requireFinishedGames: number;
  coinPrecision: number;
  version: number;
}

const DEFAULT_PAYOUTS: PayoutsConfig = {
  assets: [],
  cooldownHours: 24,
  maxPerDay: 3,
  minAccountAgeHours: 24,
  requireFinishedGames: 1,
  coinPrecision: 1_000_000,
  version: 1,
};

/** Lê config/payouts; doc ausente ⇒ config vazia (nenhum ativo habilitado). */
export async function getPayoutsConfig(db: Firestore): Promise<PayoutsConfig> {
  const snap = await db.doc('config/payouts').get();
  if (!snap.exists) return DEFAULT_PAYOUTS;
  const data = snap.data() ?? {};
  const rawAssets = Array.isArray(data.assets) ? data.assets : [];
  const assets: PayoutAssetConfig[] = rawAssets
    .map((a) => a as Record<string, unknown>)
    .filter((a) => typeof a.id === 'string' && typeof a.network === 'string')
    .map((a) => ({
      id: String(a.id),
      network: String(a.network),
      enabled: a.enabled === true,
      minWithdrawUnits: toInt((a.minWithdrawUnits ?? 0) as number | string),
      feeUnits: toInt((a.feeUnits ?? 0) as number | string),
    }));
  return {
    assets,
    cooldownHours: Number(data.cooldownHours ?? DEFAULT_PAYOUTS.cooldownHours),
    maxPerDay: Number(data.maxPerDay ?? DEFAULT_PAYOUTS.maxPerDay),
    minAccountAgeHours: Number(
      data.minAccountAgeHours ?? DEFAULT_PAYOUTS.minAccountAgeHours,
    ),
    requireFinishedGames: Number(
      data.requireFinishedGames ?? DEFAULT_PAYOUTS.requireFinishedGames,
    ),
    coinPrecision: Number(data.coinPrecision ?? DEFAULT_PAYOUTS.coinPrecision),
    version: Number(data.version ?? 1),
  };
}

/** Seleciona o provider pelo modo de payout (env PAYOUT_MODE; padrão test). */
export function getPayoutProvider(mode?: string): PayoutProvider {
  const resolved = String(mode ?? process.env.PAYOUT_MODE ?? 'test')
    .trim()
    .toLowerCase();
  if (resolved === 'live') return new FaucetPayProvider();
  return new TestProvider();
}

// ---------------------------------------------------------------------------
// Endereços: máscara + validação por rede (regex básico)
// ---------------------------------------------------------------------------

/** Máscara segura p/ UI/logs: primeiros 6 + '…' + últimos 4 caracteres. */
export function maskAddress(address: string): string {
  if (address.length <= 10) return '*'.repeat(address.length);
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/** Regex básico por rede — falha = failed com código seguro. */
export function isValidAddressForNetwork(
  network: string,
  address: string,
): boolean {
  switch (network.toUpperCase()) {
    case 'BITCOIN':
      // Legacy (1/3) ou SegWit bech32/bech32m (bc1…).
      return /^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{11,71})$/.test(address);
    case 'LITECOIN':
      return /^(?:[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}|ltc1[a-z0-9]{11,71})$/.test(address);
    case 'DOGECOIN':
      return /^D[a-km-zA-HJ-NP-Z1-9]{25,34}$/.test(address);
    case 'TRC20':
      return /^T[1-9A-HJ-NP-Za-km-z]{33}$/.test(address);
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável sem Firestore)
// ---------------------------------------------------------------------------

export type WithdrawalValidation =
  | { ok: true }
  | { ok: false; failureCode: string };

/** Códigos que contam como FALHA DE ELEGIBILIDADE p/ o lock 'review' (§36). */
export const ELIGIBILITY_FAILURE_CODES = new Set([
  'ACCOUNT_TOO_NEW',
  'NO_FINISHED_GAMES',
  'COOLDOWN_ACTIVE',
  'DAILY_LIMIT_REACHED',
  'ACCOUNT_IN_REVIEW',
]);

export interface WithdrawalValidationInput {
  assetEnabled: boolean;
  amountUnits: bigint;
  minWithdrawUnits: bigint;
  availableBalanceUnits: bigint;
  /** Último saque não-failed do usuário (ms epoch) ou null se nunca sacou. */
  lastNonFailedWithdrawalAtMs: number | null;
  cooldownHours: number;
  withdrawalsToday: number;
  maxPerDay: number;
  accountCreatedAtMs: number;
  minAccountAgeHours: number;
  finishedGames: number;
  requireFinishedGames: number;
  userStatus: string;
  addressValid: boolean;
}

/**
 * Ordem EXATA do prompt 10 B.1 (a→h). Retorna UM código por falha
 * (primeira que ocorre) — códigos seguros, sem dados sensíveis.
 */
export function validateWithdrawal(
  input: WithdrawalValidationInput,
): WithdrawalValidation {
  // (a) config ativa p/ ativo
  if (!input.assetEnabled) return { ok: false, failureCode: 'ASSET_DISABLED' };
  // (b) amount ≥ mínimo
  if (input.amountUnits < input.minWithdrawUnits) {
    return { ok: false, failureCode: 'BELOW_MINIMUM' };
  }
  // (c) saldo disponível ≥ amount
  if (input.availableBalanceUnits < input.amountUnits) {
    return { ok: false, failureCode: 'INSUFFICIENT_BALANCE' };
  }
  // (d) cooldown desde o último saque não-failed
  if (
    input.lastNonFailedWithdrawalAtMs != null &&
    Date.now() - input.lastNonFailedWithdrawalAtMs <
      input.cooldownHours * 3_600_000
  ) {
    return { ok: false, failureCode: 'COOLDOWN_ACTIVE' };
  }
  // (e) máximo de saques por dia
  if (input.withdrawalsToday >= input.maxPerDay) {
    return { ok: false, failureCode: 'DAILY_LIMIT_REACHED' };
  }
  // (f) elegibilidade: idade da conta + gameSessions finished na vida
  if (
    Date.now() - input.accountCreatedAtMs <
    input.minAccountAgeHours * 3_600_000
  ) {
    return { ok: false, failureCode: 'ACCOUNT_TOO_NEW' };
  }
  if (input.finishedGames < input.requireFinishedGames) {
    return { ok: false, failureCode: 'NO_FINISHED_GAMES' };
  }
  // (g) sem flag antifraude em users/{uid}.status
  if (input.userStatus === 'review') {
    return { ok: false, failureCode: 'ACCOUNT_IN_REVIEW' };
  }
  // (h) formato de endereço por rede
  if (!input.addressValid) return { ok: false, failureCode: 'INVALID_ADDRESS' };
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

interface WithdrawalIntent {
  id: string;
  uid: string;
  asset: string;
  network: string;
  amountUnits: bigint;
  address: string;
  addressMasked: string;
  clientRequestId: string;
}

function sanitize(err: unknown): string {
  return String((err as Error)?.message ?? err).slice(0, 300);
}

function parseIntent(id: string, data: FirebaseFirestore.DocumentData): WithdrawalIntent | null {
  const uid = String(data.uid ?? '');
  const asset = String(data.asset ?? '');
  const network = String(data.network ?? '');
  const amountUnits = toInt((data.amountUnits ?? -1) as number | string);
  const address = String(data.address ?? '');
  const clientRequestId = String(data.clientRequestId ?? '');
  if (!uid || !asset || !network || amountUnits <= 0n || !address || !clientRequestId) {
    return null;
  }
  return {
    id,
    uid,
    asset,
    network,
    amountUnits,
    address,
    addressMasked: String(data.addressMasked ?? maskAddress(address)),
    clientRequestId,
  };
}

async function getUserDoc(db: Firestore, uid: string) {
  const snap = await db.doc(`users/${uid}`).get();
  return {
    status: String(snap.get('status') ?? 'active'),
    createdAtMs: snap.get('createdAt')?.toMillis?.() ?? 0,
  };
}

async function countFinishedGames(db: Firestore, uid: string): Promise<number> {
  const snap = await db
    .collection('gameSessions')
    .where('uid', '==', uid)
    .where('status', '==', 'finished')
    .limit(1)
    .get();
  return snap.size;
}

/** Último saque não-failed (completed OU processing) — p/ cooldown. */
async function getLastNonFailedWithdrawalAtMs(
  db: Firestore,
  uid: string,
): Promise<number | null> {
  const snap = await db
    .collection('withdrawals')
    .where('uid', '==', uid)
    .where('status', 'in', ['completed', 'processing'])
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get();
  if (snap.empty) return null;
  return snap.docs[0]!.get('createdAt')?.toMillis?.() ?? null;
}

/** Saques do dia UTC que contam p/ maxPerDay (não-failed). */
async function countWithdrawalsToday(
  db: Firestore,
  uid: string,
  nowMs: number,
): Promise<number> {
  const dayStartMs = Date.parse(`${utcDayKey(nowMs)}T00:00:00.000Z`);
  const snap = await db
    .collection('withdrawals')
    .where('uid', '==', uid)
    .where('createdAt', '>=', new Date(dayStartMs))
    .get();
  return snap.docs.filter((d) => d.get('status') !== 'failed').length;
}

/** Marca o intent como encerrado (done|failed) — nunca relança erro. */
async function closeIntent(
  db: Firestore,
  intentId: string,
  status: 'done' | 'failed',
  extra: Record<string, unknown> = {},
): Promise<void> {
  await db
    .doc(`withdrawalIntents/${intentId}`)
    .set({ status, processedAt: FieldValue.serverTimestamp(), ...extra }, { merge: true });
}

/**
 * Antifraude §36: registra a falha e, ao acumular 3+ falhas de elegibilidade
 * no dia, coloca a conta em 'review' (bloqueia saques até análise humana).
 */
async function recordEligibilityFailure(
  db: Firestore,
  uid: string,
  failureCode: string,
  ruleVersion: number,
  nowMs: number,
): Promise<void> {
  const key = counterKey('wf', nowMs);
  const ref = db.doc(`rateLimits/${uid}`);
  const failures = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = Number(snap.get(key) ?? 0);
    const next = current + 1;
    tx.set(ref, { [key]: next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return next;
  });

  await writeAudit(db, {
    eventId: auditEventId('WITHDRAWAL_FAILED', `${uid}:${utcDayKey(nowMs)}:${failures}`),
    userId: uid,
    type: 'WITHDRAWAL_FAILED',
    referenceId: failureCode,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'REJECTED',
    detail: { failureCode },
  });

  if (failures >= 3 && ELIGIBILITY_FAILURE_CODES.has(failureCode)) {
    await db.doc(`users/${uid}`).set(
      { status: 'review', updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    await writeAudit(db, {
      eventId: auditEventId('ACCOUNT_ECONOMIC_LOCK', uid),
      userId: uid,
      type: 'ACCOUNT_ECONOMIC_LOCK',
      referenceId: uid,
      origin: 'runner.processWithdrawals',
      ruleVersion,
      status: 'SUCCESS',
      detail: { reason: 'WITHDRAWAL_ELIGIBILITY_FAILURES', failures },
    });
  }
}

/** Falha PRÉ-reserva: intent failed + auditoria + contador antifraude. */
async function failBeforeReserve(
  db: Firestore,
  intent: WithdrawalIntent,
  failureCode: string,
  ruleVersion: number,
  nowMs: number,
): Promise<'rejected'> {
  await closeIntent(db, intent.id, 'failed', { failureCode });
  if (ELIGIBILITY_FAILURE_CODES.has(failureCode)) {
    await recordEligibilityFailure(db, intent.uid, failureCode, ruleVersion, nowMs);
  } else {
    await writeAudit(db, {
      eventId: auditEventId('WITHDRAWAL_FAILED', intent.clientRequestId),
      userId: intent.uid,
      type: 'WITHDRAWAL_FAILED',
      referenceId: intent.clientRequestId,
      origin: 'runner.processWithdrawals',
      ruleVersion,
      status: 'REJECTED',
      detail: { failureCode },
    });
  }
  return 'rejected';
}

/**
 * RESERVA em transação: valida saldo ATÔMICAMENTE, debita available, soma
 * pending, cria withdrawals/{clientRequestId} (ID determinístico ⇒ reserva
 * única mesmo sob retry/concorrência) e grava WITHDRAWAL_RESERVE.
 * Retorna 'reserved' | 'insufficient'.
 */
async function reserveWithdrawal(
  db: Firestore,
  intent: WithdrawalIntent,
  feeUnits: bigint,
  ruleVersion: number,
): Promise<'reserved' | 'insufficient'> {
  const withdrawalRef = db.doc(`withdrawals/${intent.clientRequestId}`);
  const outcome = await db.runTransaction(async (tx) => {
    const withdrawalSnap = await tx.get(withdrawalRef);
    if (withdrawalSnap.exists) return 'skip'; // já reservado (retomada)

    const walletRef = db.doc(`wallets/${intent.uid}`);
    const walletSnap = await tx.get(walletRef);
    const available = walletSnap.exists
      ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
      : 0n;
    const pending = walletSnap.exists
      ? toInt((walletSnap.get('pendingBalance') ?? 0) as number | string)
      : 0n;
    if (available < intent.amountUnits) return 'insufficient';

    tx.set(walletRef, {
      uid: intent.uid,
      availableBalance: (available - intent.amountUnits).toString(),
      pendingBalance: (pending + intent.amountUnits).toString(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(withdrawalRef, {
      uid: intent.uid,
      asset: intent.asset,
      network: intent.network,
      amountUnits: intent.amountUnits.toString(),
      feeUnits: feeUnits.toString(),
      receivedUnits: (intent.amountUnits - feeUnits).toString(),
      address: intent.address, // SOMENTE leitura owner (rules); nunca em logs
      addressMasked: intent.addressMasked,
      status: 'processing',
      clientRequestId: intent.clientRequestId,
      createdAt: FieldValue.serverTimestamp(),
      ruleVersion,
    });

    tx.create(db.doc(`transactions/WD_RESERVE_${intent.clientRequestId}`), {
      userId: intent.uid,
      type: 'WITHDRAWAL_RESERVE',
      valueUnits: (-intent.amountUnits).toString(),
      currencyId: 'coins',
      referenceId: intent.clientRequestId,
      createdAt: FieldValue.serverTimestamp(),
      ruleVersion,
    });
    return 'reserved';
  });

  if (outcome === 'skip') return 'reserved';
  if (outcome === 'insufficient') return 'insufficient';

  await writeAudit(db, {
    eventId: auditEventId('WITHDRAWAL_REQUESTED', intent.clientRequestId),
    userId: intent.uid,
    type: 'WITHDRAWAL_REQUESTED',
    valueUnits: intent.amountUnits,
    currencyId: 'coins',
    referenceId: intent.clientRequestId,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'SUCCESS',
    detail: { asset: intent.asset, network: intent.network, addressMasked: intent.addressMasked },
  });
  await writeAudit(db, {
    eventId: auditEventId('WITHDRAWAL_RESERVED', intent.clientRequestId),
    userId: intent.uid,
    type: 'WITHDRAWAL_RESERVED',
    valueUnits: intent.amountUnits,
    currencyId: 'coins',
    referenceId: intent.clientRequestId,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'SUCCESS',
    detail: { asset: intent.asset },
  });
  return 'reserved';
}

/** Payout concluído: providerReference ANTES de considerar pago; pending −=. */
async function completeWithdrawal(
  db: Firestore,
  intent: WithdrawalIntent,
  providerReference: string,
  payoutSimulated: boolean,
  ruleVersion: number,
): Promise<void> {
  // 1) Persiste referência/status primeiro (crash-safe: nunca repaga).
  await db.doc(`withdrawals/${intent.clientRequestId}`).set(
    {
      status: 'completed',
      providerReference,
      payoutSimulated,
      processedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // 2) Move pending → fora da carteira.
  await db.runTransaction(async (tx) => {
    const walletRef = db.doc(`wallets/${intent.uid}`);
    const snap = await tx.get(walletRef);
    const pending = snap.exists
      ? toInt((snap.get('pendingBalance') ?? 0) as number | string)
      : 0n;
    tx.set(walletRef, {
      uid: intent.uid,
      pendingBalance: (pending - intent.amountUnits).toString(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    // Idempotente: só cria a transação se ainda não existir.
    const txRef = db.doc(`transactions/WD_${intent.clientRequestId}`);
    if (!(await tx.get(txRef)).exists) {
      tx.create(txRef, {
        userId: intent.uid,
        type: 'WITHDRAWAL',
        valueUnits: (-intent.amountUnits).toString(),
        currencyId: 'coins',
        referenceId: intent.clientRequestId,
        providerReference,
        createdAt: FieldValue.serverTimestamp(),
        ruleVersion,
      });
    }
  });
  await writeAudit(db, {
    eventId: auditEventId('WITHDRAWAL_COMPLETED', intent.clientRequestId),
    userId: intent.uid,
    type: 'WITHDRAWAL_COMPLETED',
    valueUnits: intent.amountUnits,
    currencyId: 'coins',
    referenceId: intent.clientRequestId,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'SUCCESS',
    detail: { providerReference, payoutSimulated, addressMasked: intent.addressMasked },
  });
  // Espelho de histórico (mesmo padrão dos demais espelhos).
  await db
    .doc(`rewards/${intent.uid}/items/WITHDRAWAL_${intent.clientRequestId}`)
    .create({
      type: 'WITHDRAWAL',
      amount: (-intent.amountUnits).toString(),
      currencyId: 'coins',
      createdAt: FieldValue.serverTimestamp(),
      referenceId: intent.clientRequestId,
      status: 'completed',
    })
    .catch(() => undefined); // já existe ⇒ idempotente
}

/** Payout falhou: ESTORNO total (available += amount, pending −= amount). */
async function reverseWithdrawal(
  db: Firestore,
  intent: WithdrawalIntent,
  errorCode: string,
  ruleVersion: number,
): Promise<void> {
  await db.doc(`withdrawals/${intent.clientRequestId}`).set(
    { status: 'failed', errorCode, processedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await db.runTransaction(async (tx) => {
    const walletRef = db.doc(`wallets/${intent.uid}`);
    const snap = await tx.get(walletRef);
    const available = snap.exists
      ? toInt((snap.get('availableBalance') ?? 0) as number | string)
      : 0n;
    const pending = snap.exists
      ? toInt((snap.get('pendingBalance') ?? 0) as number | string)
      : 0n;
    tx.set(walletRef, {
      uid: intent.uid,
      availableBalance: (available + intent.amountUnits).toString(),
      pendingBalance: (pending - intent.amountUnits).toString(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    // Idempotente: só cria o REVERSAL se ainda não existir.
    const txRef = db.doc(`transactions/WD_REV_${intent.clientRequestId}`);
    if (!(await tx.get(txRef)).exists) {
      tx.create(txRef, {
        userId: intent.uid,
        type: 'REVERSAL',
        valueUnits: intent.amountUnits.toString(),
        currencyId: 'coins',
        referenceId: intent.clientRequestId,
        errorCode,
        createdAt: FieldValue.serverTimestamp(),
        ruleVersion,
      });
    }
  });
  await writeAudit(db, {
    eventId: auditEventId('WITHDRAWAL_FAILED', intent.clientRequestId),
    userId: intent.uid,
    type: 'WITHDRAWAL_FAILED',
    referenceId: intent.clientRequestId,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'FAILED',
    detail: { errorCode, addressMasked: intent.addressMasked },
  });
  await writeAudit(db, {
    eventId: auditEventId('REWARD_REVERSED', intent.clientRequestId),
    userId: intent.uid,
    type: 'REWARD_REVERSED',
    valueUnits: intent.amountUnits,
    currencyId: 'coins',
    referenceId: intent.clientRequestId,
    origin: 'runner.processWithdrawals',
    ruleVersion,
    status: 'SUCCESS',
    detail: { reason: 'WITHDRAWAL_FAILED', errorCode },
  });
  // Espelho de histórico do estorno.
  await db
    .doc(`rewards/${intent.uid}/items/WITHDRAWAL_${intent.clientRequestId}`)
    .create({
      type: 'WITHDRAWAL',
      amount: '0',
      currencyId: 'coins',
      createdAt: FieldValue.serverTimestamp(),
      referenceId: intent.clientRequestId,
      status: 'failed',
    })
    .catch(() => undefined);
}

async function handleIntent(
  db: Firestore,
  payouts: PayoutsConfig,
  provider: PayoutProvider,
  intentSnap: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const intentId = intentSnap.id;
  try {
    const intent = parseIntent(intentId, intentSnap.data());
    if (!intent) {
      await closeIntent(db, intentId, 'failed', { failureCode: 'MALFORMED_INTENT' });
      return 'rejected';
    }
    const ruleVersion = payouts.version;

    // ---- Idempotência: withdrawal já existe para este clientRequestId? ----
    const existing = await db.doc(`withdrawals/${intent.clientRequestId}`).get();
    if (existing.exists) {
      const status = String(existing.get('status') ?? '');
      if (status === 'completed') {
        await closeIntent(db, intentId, 'done'); // já pago — NUNCA repaga
        return 'rejected';
      }
      if (status === 'processing') {
        // Retomada após crash entre reserva e payout: pula direto ao payout.
        return await runPayout(db, intent, provider, ruleVersion, intentId);
      }
      // failed anterior com o MESMO clientRequestId ⇒ não refaz.
      await closeIntent(db, intentId, 'failed', { failureCode: 'ALREADY_PROCESSED' });
      return 'rejected';
    }

    // ---- Validações antifraude (a→h) -------------------------------------
    const assetCfg = payouts.assets.find((a) => a.id === intent.asset);
    const user = await getUserDoc(db, intent.uid);
    const [finishedGames, lastAt, todayCount] = await Promise.all([
      countFinishedGames(db, intent.uid),
      getLastNonFailedWithdrawalAtMs(db, intent.uid),
      countWithdrawalsToday(db, intent.uid, nowMs),
    ]);
    const validation = validateWithdrawal({
      assetEnabled: assetCfg?.enabled === true,
      amountUnits: intent.amountUnits,
      minWithdrawUnits: assetCfg?.minWithdrawUnits ?? 0n,
      availableBalanceUnits: 0n, // checado de novo ATOMICAMENTE na reserva
      lastNonFailedWithdrawalAtMs: lastAt,
      cooldownHours: payouts.cooldownHours,
      withdrawalsToday: todayCount,
      maxPerDay: payouts.maxPerDay,
      accountCreatedAtMs: user.createdAtMs,
      minAccountAgeHours: payouts.minAccountAgeHours,
      finishedGames,
      requireFinishedGames: payouts.requireFinishedGames,
      userStatus: user.status,
      addressValid: isValidAddressForNetwork(intent.network, intent.address),
    });
    if (!validation.ok) {
      return await failBeforeReserve(db, intent, validation.failureCode, ruleVersion, nowMs);
    }

    // ---- RESERVA ----------------------------------------------------------
    const reserved = await reserveWithdrawal(
      db,
      intent,
      assetCfg?.feeUnits ?? 0n,
      ruleVersion,
    );
    if (reserved === 'insufficient') {
      return await failBeforeReserve(db, intent, 'INSUFFICIENT_BALANCE', ruleVersion, nowMs);
    }

    // ---- PAYOUT -----------------------------------------------------------
    return await runPayout(db, intent, provider, ruleVersion, intentId);
  } catch (err) {
    console.error(`[processWithdrawals] intent=${intentId} failed: ${sanitize(err)}`);
    return 'failed';
  }
}

/** Executa o payout e resolve completed/estorno; marca intent done/failed. */
async function runPayout(
  db: Firestore,
  intent: WithdrawalIntent,
  provider: PayoutProvider,
  ruleVersion: number,
  intentId: string,
): Promise<'granted' | 'rejected' | 'failed'> {
  const request: PayoutRequest = {
    asset: intent.asset,
    network: intent.network,
    address: intent.address,
    amountUnits: intent.amountUnits,
  };
  let result;
  try {
    result = await provider.sendPayout(request);
  } catch (err) {
    console.error(`[processWithdrawals] provider error intent=${intentId}: ${sanitize(err)}`);
    result = { status: 'failed', errorCode: 'PROVIDER_ERROR' };
  }

  if (result.status === 'completed' && result.providerReference) {
    await completeWithdrawal(
      db,
      intent,
      result.providerReference,
      result.payoutSimulated === true,
      ruleVersion,
    );
    await closeIntent(db, intentId, 'done');
    console.log(
      `[processWithdrawals] withdrawal completed uid=<redacted> asset=${intent.asset} ref=<masked>`,
    );
    return 'granted';
  }

  await reverseWithdrawal(db, intent, result.errorCode ?? 'PROVIDER_ERROR', ruleVersion);
  await closeIntent(db, intentId, 'failed', { failureCode: result.errorCode ?? 'PROVIDER_ERROR' });
  return 'rejected';
}

/** Ponto de entrada do runner. */
export async function processWithdrawals(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const payouts = await getPayoutsConfig(db);
  const provider = getPayoutProvider();
  const nowMs = Date.now();

  // Pendentes NOVOS + intents 'processing' (retomada pós-crash).
  const snap = await db
    .collection('withdrawalIntents')
    .where('status', 'in', ['pending', 'processing'])
    .limit(economy.limits.maxBatchSize)
    .get();

  const summary: ProcessingSummary = { scanned: snap.size, granted: 0, rejected: 0, failed: 0 };
  for (const doc of snap.docs) {
    const outcome = await handleIntent(db, payouts, provider, doc, nowMs);
    summary[outcome] += 1;
  }
  return summary;
}
