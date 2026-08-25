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
import {
  buildPayoutsV4Doc,
  normalizePayoutsDoc,
} from '../core/payoutsUpgrade';
import { coinToAsset, coinsToLitoshi, floorDiv, toInt } from '../core/precision';
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
  /** Mínimo de saque em UNITS de coin (v1). */
  minWithdrawUnits: bigint;
  /** Taxa da PLATAFORMA em units de coin (v1; descontada do saldo). */
  feeUnits: bigint;
  // ---- v2: conversão explícita COIN→ativo (autoridade backend) ----------
  /** Casas decimais do ativo (BTC/LTC/DOGE=8, USDT=6). */
  assetDecimals: number;
  /** Menores unidades do ativo que 1 COIN compra (escala inteira). */
  assetUnitPerCoinScaled: bigint;
  /** Mínimo REAL aceito pelo provedor em menores unidades do ativo. */
  providerMinAssetUnits: bigint;
  /** Taxa do PROVEDOR em menores unidades do ativo. */
  providerFeeAssetUnits: bigint;
  // ---- v3: saque por E-MAIL FaucetPay com conversão FIXA ----------------
  /** 'fixed' (atual); futuro 'usd_auto' é DOCUMENTAL (sem feed). */
  rateSource?: string;
  /** 1 COIN = N litoshi (100 ⇒ 1 COIN = 0,000001 LTC). */
  litoshiPerCoin: bigint;
  /** Mínimo REAL do envio interno em litoshi (null até o probe confirmar). */
  providerMinLitoshi: bigint | null;
  /** Rótulo de exibição (ex.: '1 COIN = 0,000001 LTC'). Nunca autoridade. */
  displayRate?: string;
}

/** Resultado da conversão explícita COIN→ativo (pura, determinística). */
export interface CoinToAssetConversion {
  /** Bruto convertido: coins × assetUnitPerCoin (floor). */
  grossAssetUnits: bigint;
  /** Recebido pelo usuário: gross − providerFee. */
  receivedAssetUnits: bigint;
}

/**
 * ÚNICO ponto de conversão COIN→ativo do sistema.
 * Regra: receivedAsset = coins × assetUnitPerCoin − providerFee (floor).
 * Retorna null quando o ativo não tem conversão configurada (v1 legado).
 */
export function convertCoinToAsset(
  amountUnits: bigint,
  cfg: PayoutAssetConfig,
): CoinToAssetConversion | null {
  if (!cfg.assetUnitPerCoinScaled) return null;
  const gross = coinToAsset(amountUnits, cfg.assetUnitPerCoinScaled, COIN_PRECISION_UNITS);
  const received = gross - cfg.providerFeeAssetUnits;
  return { grossAssetUnits: gross, receivedAssetUnits: received < 0n ? 0n : received };
}

/**
 * Validação v2 contra a realidade do PROVEDOR: o bruto convertido precisa
 * cobrir mínimo real + taxa do provedor. Código seguro BELOW_PROVIDER_MIN
 * (NÃO conta como falha de elegibilidade p/ lock 'review').
 */
export function validateProviderMinimum(
  conversion: CoinToAssetConversion,
  cfg: PayoutAssetConfig,
): WithdrawalValidation {
  const required = cfg.providerMinAssetUnits + cfg.providerFeeAssetUnits;
  if (conversion.grossAssetUnits < required) {
    // Código canônico 12.9 (antes BELOW_PROVIDER_MIN).
    return { ok: false, failureCode: 'BELOW_MIN' };
  }
  return { ok: true };
}

export interface PayoutsConfig {
  /** Mapa CANÔNICO v4 keyed por id UPPERCASE. */
  assets: Record<string, PayoutAssetConfig>;
  /** Acessor ÚNICO normalizado (aceita qualquer caixa/espaços). */
  getAsset(id: string): PayoutAssetConfig | undefined;
  cooldownHours: number;
  maxPerDay: number;
  minAccountAgeHours: number;
  requireFinishedGames: number;
  coinPrecision: number;
  version: number;
}

/** 1 coin = 1e6 units (coinPrecision da config/economy). */
const COIN_PRECISION_UNITS = 1_000_000;

/** Converte um ativo canônico v4 p/ a forma interna do processador. */
function assetFromV4(id: string, a: {
  enabled: boolean;
  litoshiPerCoin: number;
  minWithdrawCoins: number;
  feeCoins: number;
  providerMinLitoshi: number | null;
  displayRate: string;
}): PayoutAssetConfig {
  const litoshi = BigInt(Math.max(a.litoshiPerCoin, 0));
  return {
    id,
    network: 'FaucetPayEmail',
    enabled: a.enabled,
    minWithdrawUnits: BigInt(Math.max(a.minWithdrawCoins, 0)) * BigInt(COIN_PRECISION_UNITS),
    feeUnits: BigInt(Math.max(a.feeCoins, 0)) * BigInt(COIN_PRECISION_UNITS),
    assetDecimals: 8,
    assetUnitPerCoinScaled: litoshi,
    providerMinAssetUnits: 0n,
    providerFeeAssetUnits: 0n,
    rateSource: 'fixed',
    litoshiPerCoin: litoshi,
    providerMinLitoshi:
      a.providerMinLitoshi === null ? null : BigInt(Math.max(a.providerMinLitoshi, 0)),
    displayRate: a.displayRate || undefined,
  };
}

function makePayoutsConfig(
  n: ReturnType<typeof normalizePayoutsDoc>,
  healedFromVersion: number,
): PayoutsConfig {
  const assets: Record<string, PayoutAssetConfig> = {};
  for (const [id, a] of Object.entries(n.assets)) {
    assets[id] = assetFromV4(id, a);
  }
  return {
    assets,
    getAsset(id: string): PayoutAssetConfig | undefined {
      return assets[normalizeAssetId(id)];
    },
    cooldownHours: n.cooldownHours,
    maxPerDay: n.maxPerDay,
    minAccountAgeHours: n.minAccountAgeHours,
    requireFinishedGames: n.requireFinishedGames,
    coinPrecision: n.coinPrecision,
    // O processador SEMPRE trabalha na semântica canônica v4.
    version: Math.max(n.version, healedFromVersion >= 4 ? 4 : 0) || 4,
  };
}

/**
 * Lê config/payouts com NORMALIZAÇÃO de legado + AUTO-HEAL (12.9):
 * aceita QUALQUER forma anterior (array/mapa, ids lower/upper, campos antigos)
 * e, se o doc estiver ausente ou em version<4, PERSISTE o schema canônico v4
 * (merge seguro) ANTES de processar — log "config healed".
 */
export async function getPayoutsConfig(db: Firestore): Promise<PayoutsConfig> {
  const ref = db.doc('config/payouts');
  const snap = await ref.get();
  const data = (snap.data() ?? null) as Record<string, unknown> | null;
  const normalized = normalizePayoutsDoc(data);
  const needsHeal =
    !snap.exists || normalized.version < 4 || !Array.isArray(data?.assets);
  if (needsHeal) {
    await ref.set(buildPayoutsV4Doc(data), { merge: true });
    console.log(
      `[processWithdrawals] config healed version=${snap.exists ? normalized.version : 'absent'}→4`,
    );
    return makePayoutsConfig(normalized, 4);
  }
  return makePayoutsConfig(normalized, normalized.version);
}

/**
 * Resolve o modo de payout (env PAYOUT_MODE; padrão test). CORREÇÃO 12.8:
 * extraído p/ ser reutilizável pelo gate de providerMinLitoshi em live.
 */
export function resolvePayoutMode(mode?: string): 'test' | 'live' {
  const resolved = String(mode ?? process.env.PAYOUT_MODE ?? 'test')
    .trim()
    .toLowerCase();
  return resolved === 'live' ? 'live' : 'test';
}

/** Seleciona o provider pelo modo de payout (env PAYOUT_MODE; padrão test). */
export function getPayoutProvider(mode?: string): PayoutProvider {
  return resolvePayoutMode(mode) === 'live'
    ? new FaucetPayProvider()
    : new TestProvider();
}

/**
 * Normaliza o id do ativo ('ltc', ' Ltc ' ⇒ 'LTC'). CORREÇÃO 12.8: evita
 * ASSET_DISABLED falso por mismatch de caixa/espaços entre cliente e config.
 */
export function normalizeAssetId(asset: string): string {
  return String(asset ?? '').trim().toUpperCase();
}

/**
 * Gate v3 do mínimo REAL do provedor por MODO (CORREÇÃO 12.8):
 *  - test: providerMinLitoshi null ⇒ PASSA (default seguro documentado —
 *    a barreira é o mínimo da plataforma minWithdrawUnits);
 *  - live: providerMinLitoshi null ⇒ BLOQUEIA (BELOW_PROVIDER_MIN) até o
 *    probe payoutProbe confirmar/gravar o mínimo real na config.
 */
export function validateProviderMinForMode(
  payoutMode: 'test' | 'live',
  cfg: PayoutAssetConfig,
): WithdrawalValidation {
  if (payoutMode === 'live' && cfg.providerMinLitoshi === null) {
    // Código canônico 12.9 (antes BELOW_PROVIDER_MIN).
    return { ok: false, failureCode: 'BELOW_MIN' };
  }
  return { ok: true };
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
// Destino v3: E-MAIL da conta FaucetPay (transferência INTERNA)
// ---------------------------------------------------------------------------

/** Regex de e-mail (formato básico simplificado) — destino v3. */
export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Validação LOCAL do runner (o cliente também valida; aqui é autoridade). */
export function isValidDestinationEmail(email: string): boolean {
  return email.length >= 6 && email.length <= 254 && EMAIL_REGEX.test(email);
}

/**
 * Máscara segura de e-mail p/ UI/logs/auditoria: 2 primeiros caracteres do
 * local + '***@' + domínio (ex.: 'jo***@example.com'). Local curto mantém
 * apenas o 1º caractere. O e-mail COMPLETO nunca aparece em logs.
 */
export function maskEmail(email: string): string {
  const at = email.indexOf('@');
  if (at <= 0) return '*'.repeat(Math.min(email.length, 8));
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const prefix = local.slice(0, Math.min(2, local.length));
  return `${prefix}***@${domain}`;
}

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável sem Firestore)
// ---------------------------------------------------------------------------

export type WithdrawalValidation =
  | { ok: true }
  | { ok: false; failureCode: string };

/**
 * Códigos CANÔNICOS de recusa (12.9): ASSET_DISABLED, BELOW_MIN,
 * INSUFFICIENT_BALANCE, COOLDOWN_ACTIVE, ANTIFRAUD, EMAIL_INVALID,
 * PROVIDER_ERROR (+ BELOW_PROVIDER_MIN operacional pré-reserva).
 * Códigos que contam como FALHA DE ELEGIBILIDADE p/ o lock 'review' (§36):
 * antifraude e cooldown — mesmo comportamento do esquema anterior
 * (ACCOUNT_TOO_NEW/NO_FINISHED_GAMES/DAILY_LIMIT_REACHED/ACCOUNT_IN_REVIEW
 * agora convergem p/ ANTIFRAUD).
 */
export const ELIGIBILITY_FAILURE_CODES = new Set(['COOLDOWN_ACTIVE', 'ANTIFRAUD']);

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
  /** Destino válido: e-mail FaucetPay (v3) OU endereço por rede (legado). */
  destinationValid: boolean;
  /** Presente no fluxo v3 — diferencia o código de falha (INVALID_EMAIL). */
  destinationEmail?: string | null;
}

// ---------------------------------------------------------------------------
// Conversão v3 INTEIRA COIN→litoshi (1 COIN = litoshiPerCoin litoshi)
// ---------------------------------------------------------------------------

/** Resultado da conversão v3 (pura, determinística, 100% BigInt). */
export interface EmailConversion {
  /** Coins inteiras solicitadas (floor de amountUnits / 1e6). */
  amountCoins: bigint;
  /** Taxa da PLATAFORMA em coins inteiras (feeUnits / 1e6). */
  feeCoins: bigint;
  /** litoshi = (amountCoins − feeCoins) × litoshiPerCoin. */
  receivedLitoshi: bigint;
}

/**
 * ÚNICO ponto de conversão v3 COIN→litoshi. Entrada em units de coin;
 * converte para COINS INTEIRAS (floor) e aplica a taxa fixa por coin.
 * Nunca fração de coin — resíduo permanece no backend. Aritmética BigInt.
 */
export function convertCoinsToLitoshi(
  amountUnits: bigint,
  cfg: PayoutAssetConfig,
): EmailConversion | null {
  if (!cfg.litoshiPerCoin || cfg.litoshiPerCoin <= 0n) return null;
  const amountCoins = floorDiv(amountUnits, BigInt(COIN_PRECISION_UNITS));
  const feeCoins = floorDiv(cfg.feeUnits, BigInt(COIN_PRECISION_UNITS));
  const netCoins = amountCoins - feeCoins;
  return {
    amountCoins,
    feeCoins,
    receivedLitoshi:
      netCoins > 0n ? coinsToLitoshi(netCoins, cfg.litoshiPerCoin) : 0n,
  };
}

/**
 * Validação v3 contra o mínimo REAL do envio interno (providerMinLitoshi).
 * null = mínimo ainda não confirmado pelo probe ⇒ passa (o mínimo da
 * plataforma minWithdrawUnits é a única barreira). Código canônico
 * BELOW_MIN (NÃO conta p/ lock 'review').
 */
export function validateProviderLitoshiMinimum(
  conversion: EmailConversion,
  cfg: PayoutAssetConfig,
): WithdrawalValidation {
  if (cfg.providerMinLitoshi !== null && conversion.receivedLitoshi < cfg.providerMinLitoshi) {
    // Código canônico 12.9 (antes BELOW_PROVIDER_MIN).
    return { ok: false, failureCode: 'BELOW_MIN' };
  }
  return { ok: true };
}

/**
 * Ordem a→h com CÓDIGOS CANÔNICOS (12.9). Retorna UM código por falha
 * (primeira que ocorre) — códigos próprios e seguros, sem dados sensíveis:
 * ASSET_DISABLED · BELOW_MIN · INSUFFICIENT_BALANCE · COOLDOWN_ACTIVE ·
 * ANTIFRAUD (idade da conta/sem partidas/cota diária/review) · EMAIL_INVALID.
 */
export function validateWithdrawal(
  input: WithdrawalValidationInput,
): WithdrawalValidation {
  // (a) config ativa p/ ativo — SOMENTE se explicitamente disabled/ausente
  if (!input.assetEnabled) return { ok: false, failureCode: 'ASSET_DISABLED' };
  // (b) amount ≥ mínimo
  if (input.amountUnits < input.minWithdrawUnits) {
    return { ok: false, failureCode: 'BELOW_MIN' };
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
  // (e/f/g) antifraude: cota diária, idade da conta, partidas finished, review
  if (input.withdrawalsToday >= input.maxPerDay) {
    return { ok: false, failureCode: 'ANTIFRAUD', };
  }
  if (
    Date.now() - input.accountCreatedAtMs <
    input.minAccountAgeHours * 3_600_000
  ) {
    return { ok: false, failureCode: 'ANTIFRAUD' };
  }
  if (input.finishedGames < input.requireFinishedGames) {
    return { ok: false, failureCode: 'ANTIFRAUD' };
  }
  if (input.userStatus === 'review') {
    return { ok: false, failureCode: 'ANTIFRAUD' };
  }
  // (h) destino válido: e-mail FaucetPay (v3) ou endereço por rede (legado)
  if (!input.destinationValid) {
    return { ok: false, failureCode: 'EMAIL_INVALID' };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

interface WithdrawalIntent {
  id: string;
  uid: string;
  asset: string;
  /** 'faucetpay_email' (v3) ou rede legado (Bitcoin/Litecoin/…). */
  network: string;
  amountUnits: bigint;
  /** Fluxo v3: e-mail FaucetPay do destinatário (SÓ em memória). */
  destinationEmail: string | null;
  /** Sempre preenchido (máscara) — é o que vai para logs/auditoria/UI. */
  destinationMasked: string;
  /** Fluxo LEGADO apenas (null no fluxo v3; SÓ em memória). */
  address: string | null;
  clientRequestId: string;
}

function sanitize(err: unknown): string {
  return String((err as Error)?.message ?? err).slice(0, 300);
}

function parseIntent(id: string, data: FirebaseFirestore.DocumentData): WithdrawalIntent | null {
  const uid = String(data.uid ?? '');
  // CORREÇÃO 12.8: id do ativo NORMALIZADO (caixa/espaços) — evita
  // ASSET_DISABLED falso por mismatch 'ltc' vs 'LTC' entre cliente e config.
  const asset = normalizeAssetId(String(data.asset ?? ''));
  const network = String(data.network ?? '');
  const amountUnits = toInt((data.amountUnits ?? -1) as number | string);
  const clientRequestId = String(data.clientRequestId ?? '');
  // Fluxo v3: destinationEmail presente ⇒ e-mail é o destino (transferência
  // INTERNA FaucetPay). Fluxo legado: address ⇒ endereço externo (compat).
  const rawEmail = typeof data.destinationEmail === 'string' ? data.destinationEmail.trim() : '';
  const rawAddress =
    data.address != null && typeof data.address === 'string' ? data.address.trim() : '';
  if (!uid || !asset || !network || amountUnits <= 0n || !clientRequestId) return null;
  if (!rawEmail && !rawAddress) return null; // nenhum destino válido
  const destinationMasked = rawEmail
    ? String(data.destinationMasked ?? maskEmail(rawEmail))
    : String(data.addressMasked ?? maskAddress(rawAddress));
  return {
    id,
    uid,
    asset,
    network,
    amountUnits,
    destinationEmail: rawEmail || null,
    destinationMasked,
    address: rawAddress || null,
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
  conversion?: CoinToAssetConversion,
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
      // Conversão explícita COIN→ativo (v2/v3): bruto e recebido no ativo.
      ...(conversion
        ? {
            grossAssetUnits: conversion.grossAssetUnits.toString(),
            receivedAssetUnits: conversion.receivedAssetUnits.toString(),
          }
        : {}),
      // Destino: e-mail FaucetPay (v3) OU endereço legado. SOMENTE leitura
      // owner (rules); NUNCA vai para logs — apenas a máscara.
      ...(intent.destinationEmail
        ? {
            destinationEmail: intent.destinationEmail,
            destinationMasked: intent.destinationMasked,
          }
        : { address: intent.address ?? '', addressMasked: intent.destinationMasked }),
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
    detail: {
      asset: intent.asset,
      network: intent.network,
      destinationMasked: intent.destinationMasked,
    },
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
    detail: { providerReference, payoutSimulated, destinationMasked: intent.destinationMasked },
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
    detail: { errorCode, destinationMasked: intent.destinationMasked },
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
  payoutMode: 'test' | 'live' = resolvePayoutMode(),
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
        // Valor do payout = líquido convertido (v3/v2) quando persistido;
        // fallback: valor bruto (legado v1).
        const storedReceived = existing.get('receivedAssetUnits');
        const payoutAmount =
          storedReceived != null
            ? toInt(storedReceived as number | string)
            : intent.amountUnits;
        return await runPayout(db, intent, provider, ruleVersion, intentId, payoutAmount);
      }
      // failed anterior com o MESMO clientRequestId ⇒ não refaz.
      await closeIntent(db, intentId, 'failed', { failureCode: 'ALREADY_PROCESSED' });
      return 'rejected';
    }

    // ---- Validações antifraude (a→h) -------------------------------------
    // Acessor ÚNICO normalizado (12.9): aceita qualquer caixa/espaços.
    const assetCfg = payouts.getAsset(intent.asset);
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
      destinationValid: intent.destinationEmail
        ? isValidDestinationEmail(intent.destinationEmail)
        : isValidAddressForNetwork(intent.network, intent.address ?? ''),
      destinationEmail: intent.destinationEmail,
    });
    if (!validation.ok) {
      return await failBeforeReserve(db, intent, validation.failureCode, ruleVersion, nowMs);
    }

    // ---- Conversão explícita COIN→ativo (v3 e-mail / v2 legado) -----------
    // Helpers ÚNICOS; validam contra o mínimo real ANTES de reservar (falha
    // aqui = estorno desnecessário — nada foi debitado).
    let conversion: CoinToAssetConversion | undefined;
    let payoutAmountUnits: bigint = intent.amountUnits;
    if (assetCfg && intent.destinationEmail && assetCfg.litoshiPerCoin > 0n) {
      // v3: litoshi = (amountCoins − feeCoins) × litoshiPerCoin (BigInt).
      const emailConv = convertCoinsToLitoshi(intent.amountUnits, assetCfg);
      if (emailConv) {
        if (emailConv.receivedLitoshi <= 0n) {
          return await failBeforeReserve(db, intent, 'BELOW_MIN', ruleVersion, nowMs);
        }
        // CORREÇÃO 12.8: em LIVE exige mínimo REAL confirmado pelo probe
        // (providerMinLitoshi); em TEST null ⇒ default seguro documentado.
        const modeCheck = validateProviderMinForMode(payoutMode, assetCfg);
        if (!modeCheck.ok) {
          return await failBeforeReserve(db, intent, modeCheck.failureCode, ruleVersion, nowMs);
        }
        const minCheck = validateProviderLitoshiMinimum(emailConv, assetCfg);
        if (!minCheck.ok) {
          return await failBeforeReserve(db, intent, minCheck.failureCode, ruleVersion, nowMs);
        }
        conversion = {
          grossAssetUnits: coinsToLitoshi(emailConv.amountCoins, assetCfg.litoshiPerCoin),
          receivedAssetUnits: emailConv.receivedLitoshi,
        };
        payoutAmountUnits = emailConv.receivedLitoshi; // paga o LÍQUIDO
      }
    } else if (assetCfg) {
      const conv = convertCoinToAsset(intent.amountUnits, assetCfg);
      if (conv) {
        const providerCheck = validateProviderMinimum(conv, assetCfg);
        if (!providerCheck.ok) {
          return await failBeforeReserve(db, intent, providerCheck.failureCode, ruleVersion, nowMs);
        }
        // Legado paga o valor BRUTO em units de coin (comportamento v1/v2
        // preservado — regressão intacta).
        conversion = conv;
      }
    }

    // ---- RESERVA ----------------------------------------------------------
    const reserved = await reserveWithdrawal(
      db,
      intent,
      assetCfg?.feeUnits ?? 0n,
      ruleVersion,
      conversion,
    );
    if (reserved === 'insufficient') {
      return await failBeforeReserve(db, intent, 'INSUFFICIENT_BALANCE', ruleVersion, nowMs);
    }

    // ---- PAYOUT -----------------------------------------------------------
    return await runPayout(db, intent, provider, ruleVersion, intentId, payoutAmountUnits);
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
  /** Valor a pagar em menores unidades do ativo (líquido v3/v2). */
  payoutAmountUnits: bigint,
): Promise<'granted' | 'rejected' | 'failed'> {
  const request: PayoutRequest = {
    asset: intent.asset,
    network: intent.network,
    address: intent.address ?? '',
    destinationEmail: intent.destinationEmail ?? undefined,
    amountUnits: payoutAmountUnits,
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

  const payoutMode = resolvePayoutMode();
  const summary: ProcessingSummary = { scanned: snap.size, granted: 0, rejected: 0, failed: 0 };
  for (const doc of snap.docs) {
    const outcome = await handleIntent(db, payouts, provider, doc, nowMs, payoutMode);
    summary[outcome] += 1;
  }
  return summary;
}
