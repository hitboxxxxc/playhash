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

export type ClaimKind = 'mission' | 'achievement';

export interface ClaimCatalogItem {
  enabled: boolean;
  target: number;
  /** Recompensa em units (BigInt). */
  rewardUnits: bigint;
  /** Para missões: 'daily' | 'weekly' (define o período válido). '' = conquista. */
  kind: string;
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
  if (kindRaw !== 'mission' && kindRaw !== 'achievement') return null;
  if (typeof refId !== 'string' || refId.length === 0 || refId.length > 64) return null;
  if (typeof clientRequestId !== 'string' || clientRequestId.length < 8) return null;
  return { id, uid, kind: kindRaw, refId, clientRequestId };
}

function catalogPath(kind: ClaimKind, refId: string): string {
  return kind === 'mission' ? `missions/${refId}` : `achievements/${refId}`;
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
  return {
    enabled: snap.get('enabled') === true,
    target: Number(snap.get('target') ?? 0),
    rewardUnits: Number.isSafeInteger(amount) && amount > 0 ? BigInt(amount) : 0n,
    kind: kind === 'mission' ? (snap.get('kind') === 'weekly' ? 'weekly' : 'daily') : '',
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
        ? periodKeyFor(catalog?.kind === 'weekly' ? 'weekly' : 'daily', nowMs)
        : '';

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
