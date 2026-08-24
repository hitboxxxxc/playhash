/**
 * Processador de CLAIMS (missões/conquistas) — recompensa 100% no backend.
 *
 * O cliente só CRIA `claims/{clientRequestId}` (intenção, campos exatos nas
 * rules). Este processador, para cada claim pendente:
 *  1. valida campos, catálogo, enabled, período (missões) e progresso;
 *  2. aplica rate limit diário (config/economy.limits.maxClaimsPerDay);
 *  3. EM TRANSAÇÃO: credita a wallet, marca claimed no item do usuário e
 *     status='claimed' no claim;
 *  4. audita MISSION_REWARD_GRANTED / ACHIEVEMENT_REWARD_GRANTED (ou
 *     CLAIM_REJECTED) e grava espelho em rewards/{uid}/items;
 *  5. bump de conquistas 'claims' (a_claims_10) ao conceder.
 *
 * Idempotência: doc id = clientRequestId (criado 1× pelas rules — update é
 * negado); transação re-lê status='pending' (concorrência entre runs é
 * segura). Falhas viram status='failed' com código SEGURO.
 *
 * validateClaim é PURA e unit-testável sem Firestore.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { EconomyConfig, ProcessingSummary } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { writeAudit, auditEventId } from '../core/audit';
import { readDailyCounter, incrementDailyCounter } from '../core/ratelimit';
import { periodKeyFor, bumpAchievementProgress } from './mission_progress';

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável)
// ---------------------------------------------------------------------------

export type ClaimKind = 'mission' | 'achievement' | 'seasonFree' | 'seasonPremium';

/** refId de claims de temporada: `seasonId:level` (ex.: 'season-01:3'). */
export function parseSeasonRefId(refId: string): { seasonId: string; level: number } | null {
  const idx = refId.indexOf(':');
  if (idx <= 0 || idx === refId.length - 1) return null;
  const seasonId = refId.slice(0, idx);
  const level = Number(refId.slice(idx + 1));
  if (seasonId.length === 0 || seasonId.length > 64) return null;
  if (!Number.isSafeInteger(level) || level < 1 || level > 1000) return null;
  return { seasonId, level };
}

export interface ClaimCatalogItem {
  enabled: boolean;
  target: number;
  /** Recompensa em units (BigInt). */
  rewardUnits: bigint;
  /** Para missões: 'daily' | 'weekly' | 'season'. '' = conquista. */
  kind: string;
  /** periodKey fixo (missões de temporada); '' para os demais. */
  periodKey: string;
}

export interface ClaimUserItem {
  progress: number;
  claimed: boolean;
  /** periodKey do progresso ('' para conquistas — sem período). */
  periodKey: string;
}

export interface ClaimValidationInput {
  uid: string;
  kind: ClaimKind;
  refId: string;
  clientRequestId: string;
  catalog: ClaimCatalogItem | null;
  userItem: ClaimUserItem | null;
  /** periodKey esperado para missões ('' para conquistas). */
  currentPeriodKey: string;
  claimsToday: number;
  maxClaimsPerDay: number;
}

export type ClaimValidation =
  | { ok: true; rewardUnits: bigint }
  | { ok: false; code: string };

export function validateClaim(input: ClaimValidationInput): ClaimValidation {
  if (!input.uid || !input.refId || input.clientRequestId.length < 8) {
    return { ok: false, code: 'INVALID_CLAIM_FIELDS' };
  }
  if (input.claimsToday >= input.maxClaimsPerDay) {
    return { ok: false, code: 'DAILY_LIMIT_REACHED' };
  }
  if (!input.catalog) return { ok: false, code: 'CLAIM_CATALOG_MISSING' };
  if (!input.catalog.enabled) return { ok: false, code: 'CLAIM_DISABLED' };
  if (input.catalog.rewardUnits <= 0n) {
    return { ok: false, code: 'CLAIM_REWARD_INVALID' };
  }
  if (!input.userItem) return { ok: false, code: 'CLAIM_PROGRESS_INSUFFICIENT' };
  if (input.userItem.claimed) return { ok: false, code: 'CLAIM_ALREADY_CLAIMED' };
  if (input.kind === 'mission' && input.userItem.periodKey !== input.currentPeriodKey) {
    return { ok: false, code: 'CLAIM_PERIOD_MISMATCH' };
  }
  if (input.userItem.progress < input.catalog.target) {
    return { ok: false, code: 'CLAIM_PROGRESS_INSUFFICIENT' };
  }
  return { ok: true, rewardUnits: input.catalog.rewardUnits };
}

// ---------------------------------------------------------------------------
// Validação de claims de TEMPORADA (PURE, unit-testável)
// ---------------------------------------------------------------------------

export interface SeasonDocInput {
  id: string;
  startAtMs: number;
  endAtMs: number;
  /** Recompensas da trilha GRATUITA por nível (units BigInt). */
  freeRewards: Map<number, bigint>;
  /** Recompensas da trilha PREMIUM por nível (units BigInt). */
  premiumRewards: Map<number, bigint>;
}

export interface SeasonProgressInput {
  /** Nível ATUAL da temporada (derivado pelo backend — seasonProgress). */
  level: number;
  claimedFree: Record<string, boolean>;
  claimedPremium: Record<string, boolean>;
  /** Passe premium ativo (virá com Play Billing — sempre false por agora). */
  premiumActive: boolean;
}

export interface SeasonClaimValidationInput {
  kind: 'seasonFree' | 'seasonPremium';
  seasonId: string;
  level: number;
  season: SeasonDocInput | null;
  progress: SeasonProgressInput | null;
  nowMs: number;
}

export type SeasonClaimValidation =
  | { ok: true; rewardUnits: bigint }
  | { ok: false; code: string };

/**
 * Validação de recompensa de temporada (TUDO no servidor):
 *  - temporada existe, confere com o refId e está ativa (startAt ≤ now ≤ endAt);
 *  - nível do usuário (derivado pelo backend) ≥ nível da recompensa;
 *  - trilha free: não resgatada; trilha premium: exige premiumActive
 *    (sem Play Billing ⇒ PREMIUM_REQUIRED — falha SEGURA e esperada).
 */
export function validateSeasonClaim(
  input: SeasonClaimValidationInput,
): SeasonClaimValidation {
  if (!input.season) return { ok: false, code: 'SEASON_NOT_FOUND' };
  if (input.season.id !== input.seasonId) {
    return { ok: false, code: 'SEASON_MISMATCH' };
  }
  if (
    !Number.isFinite(input.nowMs) ||
    input.nowMs < input.season.startAtMs ||
    input.nowMs > input.season.endAtMs
  ) {
    return { ok: false, code: 'SEASON_NOT_ACTIVE' };
  }
  if (!input.progress) return { ok: false, code: 'SEASON_PROGRESS_MISSING' };
  const rewards =
    input.kind === 'seasonFree' ? input.season.freeRewards : input.season.premiumRewards;
  const rewardUnits = rewards.get(input.level);
  if (rewardUnits === undefined || rewardUnits <= 0n) {
    return { ok: false, code: 'SEASON_REWARD_INVALID' };
  }
  if (input.progress.level < input.level) {
    return { ok: false, code: 'SEASON_LEVEL_TOO_LOW' };
  }
  const claimedMap =
    input.kind === 'seasonFree' ? input.progress.claimedFree : input.progress.claimedPremium;
  if (claimedMap[String(input.level)] === true) {
    return { ok: false, code: 'CLAIM_ALREADY_CLAIMED' };
  }
  if (input.kind === 'seasonPremium' && !input.progress.premiumActive) {
    return { ok: false, code: 'PREMIUM_REQUIRED' };
  }
  return { ok: true, rewardUnits };
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

interface PendingClaim {
  id: string;
  uid: string;
  kind: ClaimKind;
  refId: string;
  clientRequestId: string;
}

function parseClaim(id: string, data: FirebaseFirestore.DocumentData): PendingClaim | null {
  const uid = data.uid;
  const kindRaw = data.kind;
  const refId = data.refId;
  const clientRequestId = data.clientRequestId;
  if (typeof uid !== 'string' || uid.length === 0) return null;
  if (
    kindRaw !== 'mission' &&
    kindRaw !== 'achievement' &&
    kindRaw !== 'seasonFree' &&
    kindRaw !== 'seasonPremium'
  ) {
    return null;
  }
  if (typeof refId !== 'string' || refId.length === 0 || refId.length > 64) return null;
  if (typeof clientRequestId !== 'string' || clientRequestId.length < 8) return null;
  return { id, uid, kind: kindRaw, refId, clientRequestId };
}

function catalogPath(kind: ClaimKind, refId: string): string {
  return kind === 'achievement' ? `achievements/${refId}` : `missions/${refId}`;
}

function userItemPath(kind: ClaimKind, uid: string, refId: string): string {
  return kind === 'mission'
    ? `userMissions/${uid}/items/${refId}`
    : `userAchievements/${uid}/items/${refId}`;
}

async function loadCatalogItem(
  db: Firestore,
  kind: ClaimKind,
  refId: string,
): Promise<ClaimCatalogItem | null> {
  const snap = await db.doc(catalogPath(kind, refId)).get();
  if (!snap.exists) return null;
  const rewardCfg = snap.get('rewardConfig') as Record<string, unknown> | undefined;
  const amount = rewardCfg == null ? NaN : Number(rewardCfg.amountUnits);
  const rawKind = kind === 'mission' ? String(snap.get('kind') ?? 'daily') : '';
  return {
    enabled: snap.get('enabled') === true,
    target: Number(snap.get('target') ?? 0),
    rewardUnits: Number.isSafeInteger(amount) && amount > 0 ? BigInt(amount) : 0n,
    kind: rawKind === 'weekly' ? 'weekly' : rawKind === 'season' ? 'season' : rawKind === 'daily' ? 'daily' : '',
    // Temporada: periodKey fixo do catálogo; '' para os demais.
    periodKey: rawKind === 'season' ? String(snap.get('periodKey') ?? '') : '',
  };
}

async function failClaim(
  db: Firestore,
  claim: PendingClaim,
  code: string,
  ruleVersion: number,
): Promise<'rejected'> {
  await db.doc(`claims/${claim.id}`).update({
    status: 'failed',
    failureCode: code,
    processedAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, {
    eventId: auditEventId('CLAIM_REJECTED', claim.id),
    userId: claim.uid,
    type: 'CLAIM_REJECTED',
    referenceId: claim.id,
    origin: 'runner.processClaims',
    ruleVersion,
    status: 'REJECTED',
    detail: { failureCode: code, kind: claim.kind, refId: claim.refId },
  });
  return 'rejected';
}

/**
 * Fluxo de claims de TEMPORADA (seasonFree/seasonPremium). A recompensa vem
 * SEMPRE da trilha do doc seasons/{id} — nunca do cliente. Idempotente:
 * transação re-lê o mapa claimedFree/claimedPremium.
 */
async function handleSeasonClaim(
  db: Firestore,
  economy: EconomyConfig,
  claim: PendingClaim,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const ruleVersion = economy.economicRuleVersion;
  try {
    const parsed = parseSeasonRefId(claim.refId);
    if (!parsed) {
      return await failClaim(db, claim, 'INVALID_CLAIM_FIELDS', ruleVersion);
    }
    const seasonSnap = await db.doc(`seasons/${parsed.seasonId}`).get();
    let season: SeasonDocInput | null = null;
    if (seasonSnap.exists) {
      const toMs = (v: unknown): number => {
        if (v == null) return NaN;
        if (typeof v === 'number') return v;
        const t = v as { toMillis?: () => number };
        return typeof t.toMillis === 'function' ? t.toMillis() : NaN;
      };
      const tracks = (seasonSnap.get('tracks') ?? {}) as Record<string, unknown>;
      const toRewardMap = (raw: unknown): Map<number, bigint> => {
        const map = new Map<number, bigint>();
        if (!Array.isArray(raw)) return map;
        for (const entry of raw as Record<string, unknown>[]) {
          const lvl = Number(entry?.level);
          const reward = (entry?.reward ?? {}) as Record<string, unknown>;
          const amount = Number(reward?.amountUnits);
          if (Number.isSafeInteger(lvl) && lvl >= 1 && Number.isSafeInteger(amount) && amount > 0) {
            map.set(lvl, BigInt(amount));
          }
        }
        return map;
      };
      season = {
        id: seasonSnap.id,
        startAtMs: toMs(seasonSnap.get('startAt')),
        endAtMs: toMs(seasonSnap.get('endAt')),
        freeRewards: toRewardMap(tracks.free),
        premiumRewards: toRewardMap(tracks.premium),
      };
    }

    const progressSnap = await db.doc(`seasonProgress/${claim.uid}`).get();
    const progress: SeasonProgressInput | null = progressSnap.exists
      ? {
          level: Number(progressSnap.get('level') ?? 1),
          claimedFree:
            (progressSnap.get('claimedFree') as Record<string, boolean> | null) ?? {},
          claimedPremium:
            (progressSnap.get('claimedPremium') as Record<string, boolean> | null) ?? {},
          premiumActive: progressSnap.get('premiumActive') === true,
        }
      : null;

    const validation = validateSeasonClaim({
      kind: claim.kind as 'seasonFree' | 'seasonPremium',
      seasonId: parsed.seasonId,
      level: parsed.level,
      season,
      progress,
      nowMs,
    });
    if (!validation.ok) {
      return await failClaim(db, claim, validation.code, ruleVersion);
    }

    const claimedField = claim.kind === 'seasonFree' ? 'claimedFree' : 'claimedPremium';
    const rewardKey = String(parsed.level);
    const rewardId = `${claim.kind === 'seasonFree' ? 'SEASON_FREE' : 'SEASON_PREMIUM'}_${parsed.seasonId}_L${parsed.level}`;

    type TxOutcome = { kind: 'ok' } | { kind: 'fail'; code: string } | { kind: 'skip' };
    const outcome: TxOutcome = await db.runTransaction(async (tx): Promise<TxOutcome> => {
      const freshClaim = await tx.get(db.doc(`claims/${claim.id}`));
      if (!freshClaim.exists || freshClaim.get('status') !== 'pending') {
        return { kind: 'skip' };
      }
      const freshProgress = await tx.get(db.doc(`seasonProgress/${claim.uid}`));
      const claimedMap =
        (freshProgress.get(claimedField) as Record<string, boolean> | null) ?? {};
      if (claimedMap[rewardKey] === true) return { kind: 'fail', code: 'CLAIM_ALREADY_CLAIMED' };

      const walletRef = db.doc(`wallets/${claim.uid}`);
      const walletSnap = await tx.get(walletRef);
      const balance = walletSnap.exists
        ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
        : 0n;
      tx.set(
        walletRef,
        {
          uid: claim.uid,
          availableBalance: (balance + validation.rewardUnits).toString(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.set(
        db.doc(`seasonProgress/${claim.uid}`),
        { [claimedField]: { ...claimedMap, [rewardKey]: true } },
        { merge: true },
      );
      tx.update(db.doc(`claims/${claim.id}`), {
        status: 'claimed',
        rewardUnits: validation.rewardUnits.toString(),
        processedAt: FieldValue.serverTimestamp(),
      });
      return { kind: 'ok' };
    });

    if (outcome.kind === 'skip') return 'rejected';
    if (outcome.kind === 'fail') {
      return await failClaim(db, claim, outcome.code, ruleVersion);
    }

    await writeAudit(db, {
      eventId: auditEventId('SEASON_REWARD_GRANTED', claim.id),
      userId: claim.uid,
      type: 'SEASON_REWARD_GRANTED',
      valueUnits: validation.rewardUnits,
      currencyId: 'coins',
      referenceId: claim.id,
      origin: 'runner.processClaims',
      ruleVersion,
      status: 'SUCCESS',
      detail: { seasonId: parsed.seasonId, level: parsed.level, track: claim.kind },
    });

    // Espelho de histórico (id determinístico ⇒ idempotente).
    await db
      .doc(`rewards/${claim.uid}/items/${rewardId}`)
      .create({
        type: claim.kind === 'seasonFree' ? 'SEASON_FREE_REWARD' : 'SEASON_PREMIUM_REWARD',
        amount: validation.rewardUnits.toString(),
        currencyId: 'coins',
        createdAt: FieldValue.serverTimestamp(),
        referenceId: claim.id,
      });
    return 'granted';
  } catch (err) {
    console.error(`[processClaims] seasonClaim=${claim.id} failed: ${sanitize(err)}`);
    return 'failed';
  }
}

async function handleClaim(
  db: Firestore,
  economy: EconomyConfig,
  claimSnap: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const claim = parseClaim(claimSnap.id, claimSnap.data());
  const ruleVersion = economy.economicRuleVersion;
  if (!claim) {
    // Campos inválidos: marca failed direto (sem uid não há auditoria de user).
    await claimSnap.ref.update({
      status: 'failed',
      failureCode: 'INVALID_CLAIM_FIELDS',
      processedAt: FieldValue.serverTimestamp(),
    });
    return 'rejected';
  }

  try {
    const claimsToday = await readDailyCounter(db, claim.uid, 'claims', nowMs);
    const catalog = await loadCatalogItem(db, claim.kind, claim.refId);
    const itemSnap = await db.doc(userItemPath(claim.kind, claim.uid, claim.refId)).get();
    const userItem: ClaimUserItem | null = itemSnap.exists
      ? {
          progress: Number(itemSnap.get('progress') ?? 0),
          claimed: itemSnap.get('claimed') === true,
          periodKey: String(itemSnap.get('periodKey') ?? ''),
        }
      : null;
    const currentPeriodKey =
      claim.kind === 'mission'
        ? catalog?.kind === 'season'
          ? catalog.periodKey // temporada: periodKey FIXO do catálogo
          : periodKeyFor(catalog?.kind === 'weekly' ? 'weekly' : 'daily', nowMs)
        : '';

    // Claims de TEMPORADA seguem fluxo próprio (trilhas free/premium).
    if (claim.kind === 'seasonFree' || claim.kind === 'seasonPremium') {
      return await handleSeasonClaim(db, economy, claim, nowMs);
    }

    const validation = validateClaim({
      uid: claim.uid,
      kind: claim.kind,
      refId: claim.refId,
      clientRequestId: claim.clientRequestId,
      catalog,
      userItem,
      currentPeriodKey,
      claimsToday,
      maxClaimsPerDay: economy.limits.maxClaimsPerDay,
    });
    if (!validation.ok) {
      return await failClaim(db, claim, validation.code, ruleVersion);
    }

    type TxOutcome = { kind: 'ok' } | { kind: 'fail'; code: string } | { kind: 'skip' };
    const outcome: TxOutcome = await db.runTransaction(async (tx): Promise<TxOutcome> => {
      const freshClaim = await tx.get(claimSnap.ref);
      if (!freshClaim.exists || freshClaim.get('status') !== 'pending') {
        return { kind: 'skip' }; // já processado por outra execução
      }
      const freshItem = await tx.get(db.doc(userItemPath(claim.kind, claim.uid, claim.refId)));
      const freshUserItem: ClaimUserItem | null = freshItem.exists
        ? {
            progress: Number(freshItem.get('progress') ?? 0),
            claimed: freshItem.get('claimed') === true,
            periodKey: String(freshItem.get('periodKey') ?? ''),
          }
        : null;
      const recheck = validateClaim({
        uid: claim.uid,
        kind: claim.kind,
        refId: claim.refId,
        clientRequestId: claim.clientRequestId,
        catalog: catalog!,
        userItem: freshUserItem,
        currentPeriodKey,
        claimsToday,
        maxClaimsPerDay: economy.limits.maxClaimsPerDay,
      });
      if (!recheck.ok) return { kind: 'fail', code: recheck.code };

      // Crédito na wallet (valor 100% do catálogo — nunca do cliente).
      const walletRef = db.doc(`wallets/${claim.uid}`);
      const walletSnap = await tx.get(walletRef);
      const balance = walletSnap.exists
        ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
        : 0n;
      tx.set(
        walletRef,
        {
          uid: claim.uid,
          availableBalance: (balance + recheck.rewardUnits).toString(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // Marca claimed no item do usuário (idempotência econômica).
      tx.set(
        db.doc(userItemPath(claim.kind, claim.uid, claim.refId)),
        { claimed: true, claimedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );

      tx.update(claimSnap.ref, {
        status: 'claimed',
        // Consumido pelo processador de temporada (XP de claim).
        seasonXpApplied: false,
        rewardUnits: recheck.rewardUnits.toString(),
        processedAt: FieldValue.serverTimestamp(),
      });
      return { kind: 'ok' };
    });

    if (outcome.kind === 'skip') return 'rejected';
    if (outcome.kind === 'fail') {
      return await failClaim(db, claim, outcome.code, ruleVersion);
    }

    const auditType = claim.kind === 'mission' ? 'MISSION_REWARD_GRANTED' : 'ACHIEVEMENT_REWARD_GRANTED';
    await writeAudit(db, {
      eventId: auditEventId(auditType, claim.id),
      userId: claim.uid,
      type: auditType,
      valueUnits: validation.rewardUnits,
      currencyId: 'coins',
      referenceId: claim.id,
      origin: 'runner.processClaims',
      ruleVersion,
      status: 'SUCCESS',
      detail: { refId: claim.refId, kind: claim.kind },
    });

    // Espelho de histórico (rewards/{uid}/items) — id determinístico.
    await db
      .doc(`rewards/${claim.uid}/items/CLAIM_${claim.id}`)
      .create({
        type: claim.kind === 'mission' ? 'MISSION_REWARD' : 'ACHIEVEMENT_REWARD',
        amount: validation.rewardUnits.toString(),
        currencyId: 'coins',
        createdAt: FieldValue.serverTimestamp(),
        referenceId: claim.id,
      });

    // Conquista de claims (a_claims_10) + rate limit do dia.
    await bumpAchievementProgress(db, claim.uid, 'claims', 'add', 1);
    await incrementDailyCounter(db, claim.uid, 'claims', nowMs);
    return 'granted';
  } catch (err) {
    console.error(`[processClaims] claim=${claim.id} failed: ${sanitize(err)}`);
    return 'failed';
  }
}

function sanitize(err: unknown): string {
  return String((err as Error)?.message ?? err).slice(0, 300);
}

/** Ponto de entrada do runner. */
export async function processClaims(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor

  const snap = await db
    .collection('claims')
    .where('status', '==', 'pending')
    .orderBy('createdAt', 'asc')
    .limit(economy.limits.maxBatchSize)
    .get();

  const summary: ProcessingSummary = { scanned: snap.size, granted: 0, rejected: 0, failed: 0 };
  for (const doc of snap.docs) {
    const outcome = await handleClaim(db, economy, doc, nowMs);
    summary[outcome] += 1;
  }
  return summary;
}
