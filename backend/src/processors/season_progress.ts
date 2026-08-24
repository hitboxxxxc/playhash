/**
 * SEASON PROGRESS — XP real da temporada, calculado SOMENTE no backend.
 *
 * Fontes de XP (doc da season = autoridade):
 *  - Partida concedida (gameSessions com serverResult.status='granted'):
 *      xp += floor(score / xpConfig.matchScoreDivisor)
 *  - Claim concedido (mission): xp += xpConfig.missionClaimXp
 *  - Claim concedido (achievement): xp += xpConfig.achievementXp
 *
 * Idempotência: os processadores de origem marcam `seasonXpApplied=false`
 * ao consolidar o evento; este processador consome esses eventos e marca
 * `seasonXpApplied=true` (reexecução nunca re-aplica XP).
 *
 * seasonProgress/{uid}: {seasonId, xp, level, updatedAt} — nível DERIVADO
 * (linear: levelXp por nível) e SOMENTE SOBE (nunca por decisão do cliente).
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { getEconomyConfig } from '../core/config';
import { writeAudit, auditEventId } from '../core/audit';

// ---------------------------------------------------------------------------
// PURE (unit-testável sem Firestore)
// ---------------------------------------------------------------------------

export interface SeasonXpConfig {
  matchScoreDivisor: number;
  missionClaimXp: number;
  achievementXp: number;
}

/** XP de partida: floor(score / divisor); score/divisor inválidos ⇒ 0. */
export function xpForScore(score: number, divisor: number): number {
  if (!Number.isSafeInteger(score) || score <= 0) return 0;
  if (!Number.isSafeInteger(divisor) || divisor <= 0) return 0;
  return Math.floor(score / divisor);
}

/** Nível derivado (linear): floor(xpTotal / levelXp) + 1; mínimo 1. */
export function levelFromXp(totalXp: number, levelXp: number): number {
  if (!Number.isSafeInteger(totalXp) || totalXp <= 0) return 1;
  if (!Number.isSafeInteger(levelXp) || levelXp <= 0) return 1;
  return Math.floor(totalXp / levelXp) + 1;
}

/** XP dentro do nível atual (0..levelXp-1) para a barra de progresso. */
export function xpInLevel(totalXp: number, levelXp: number): number {
  if (!Number.isSafeInteger(totalXp) || totalXp <= 0) return 0;
  if (!Number.isSafeInteger(levelXp) || levelXp <= 0) return 0;
  return totalXp % levelXp;
}

/** XP de claim: missão = missionClaimXp; conquista = achievementXp. */
export function xpForClaim(kind: string, cfg: SeasonXpConfig): number {
  return kind === 'achievement' ? cfg.achievementXp : cfg.missionClaimXp;
}

// ---------------------------------------------------------------------------
// Temporada ativa (cache curto — leitura admin)
// ---------------------------------------------------------------------------

export interface ActiveSeason {
  id: string;
  name: string;
  startAtMs: number;
  endAtMs: number;
  levelXp: number;
  xpConfig: SeasonXpConfig;
}

const SEASON_TTL_MS = 60_000;
let seasonCache: { value: ActiveSeason | null; loadedAt: number } | null = null;

/** Visível para testes/injeção. */
export function invalidateSeasonCache(): void {
  seasonCache = null;
}

function toMs(v: unknown): number {
  if (v == null) return NaN;
  if (typeof v === 'number') return v;
  const t = v as { toMillis?: () => number };
  return typeof t.toMillis === 'function' ? t.toMillis() : NaN;
}

export async function loadActiveSeason(
  db: Firestore,
  nowMs: number,
): Promise<ActiveSeason | null> {
  if (seasonCache && Date.now() - seasonCache.loadedAt < SEASON_TTL_MS) {
    const c = seasonCache.value;
    if (c && nowMs >= c.startAtMs && nowMs <= c.endAtMs) return c;
    if (c === null) return null;
  }
  const snap = await db.collection('seasons').get();
  let found: ActiveSeason | null = null;
  for (const doc of snap.docs) {
    const startAtMs = toMs(doc.get('startAt'));
    const endAtMs = toMs(doc.get('endAt'));
    if (!Number.isFinite(startAtMs) || !Number.isFinite(endAtMs)) continue;
    if (nowMs < startAtMs || nowMs > endAtMs) continue;
    const rawCfg = (doc.get('xpConfig') ?? {}) as Record<string, unknown>;
    const divisor = Number(rawCfg.matchScoreDivisor ?? 0);
    const missionXp = Number(rawCfg.missionClaimXp ?? 0);
    const achievementXp = Number(rawCfg.achievementXp ?? 0);
    const levelXp = Number(doc.get('levelXp') ?? 0);
    if (divisor <= 0 || levelXp <= 0) continue;
    found = {
      id: doc.id,
      name: String(doc.get('name') ?? doc.id),
      startAtMs,
      endAtMs,
      levelXp,
      xpConfig: {
        matchScoreDivisor: divisor,
        missionClaimXp: Number.isSafeInteger(missionXp) ? missionXp : 0,
        achievementXp: Number.isSafeInteger(achievementXp) ? achievementXp : 0,
      },
    };
    break;
  }
  seasonCache = { value: found, loadedAt: Date.now() };
  return found;
}

// ---------------------------------------------------------------------------
// Aplicação de XP (Firestore/admin)
// ---------------------------------------------------------------------------

/** Aplica delta de XP (nível só sobe — derivado do xp total). */
export async function applySeasonXp(
  db: Firestore,
  season: ActiveSeason,
  uid: string,
  delta: number,
): Promise<void> {
  if (delta <= 0) return;
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`seasonProgress/${uid}`);
    const snap = await tx.get(ref);
    const currentXp = Number(snap.get('xp') ?? 0);
    const currentLevel = Number(snap.get('level') ?? 1);
    const nextXp = (Number.isSafeInteger(currentXp) ? currentXp : 0) + delta;
    const nextLevel = Math.max(
      levelFromXp(nextXp, season.levelXp),
      Number.isSafeInteger(currentLevel) ? currentLevel : 1, // nível SÓ sobe
    );
    tx.set(
      ref,
      {
        uid,
        seasonId: season.id,
        xp: nextXp,
        level: nextLevel,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

export interface SeasonProgressSummary {
  sessionsScanned: number;
  claimsScanned: number;
  xpGranted: number;
  failed: number;
}

/** Ponto de entrada do runner. */
export async function processSeasonProgress(
  db: Firestore,
): Promise<SeasonProgressSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor
  const summary: SeasonProgressSummary = {
    sessionsScanned: 0,
    claimsScanned: 0,
    xpGranted: 0,
    failed: 0,
  };

  const season = await loadActiveSeason(db, nowMs);
  if (season === null) return summary; // sem temporada ativa ⇒ no-op seguro

  // --- Partidas concedidas ainda não contabilizadas ------------------------
  const sessions = await db
    .collection('gameSessions')
    .where('seasonXpApplied', '==', false)
    .limit(economy.limits.maxBatchSize)
    .get();

  for (const doc of sessions.docs) {
    summary.sessionsScanned += 1;
    try {
      const data = doc.data();
      const uid = typeof data.uid === 'string' ? data.uid : '';
      const status = String(
        (data.serverResult as Record<string, unknown> | null)?.status ?? '',
      );
      const score = Number(data.score);
      if (uid.length === 0 || status !== 'granted') {
        await doc.ref.update({ seasonXpApplied: true });
        continue;
      }
      const delta = xpForScore(score, season.xpConfig.matchScoreDivisor);
      if (delta > 0) {
        await applySeasonXp(db, season, uid, delta);
        summary.xpGranted += 1;
        await writeAudit(db, {
          eventId: auditEventId('SEASON_XP_GRANTED', `${season.id}:${doc.id}`),
          userId: uid,
          type: 'SEASON_XP_GRANTED',
          valueUnits: BigInt(delta),
          currencyId: 'season_xp',
          referenceId: doc.id,
          origin: 'runner.seasonProgress',
          ruleVersion: economy.economicRuleVersion,
          status: 'SUCCESS',
          detail: { seasonId: season.id, source: 'game_session' },
        });
      }
      await doc.ref.update({ seasonXpApplied: true });
    } catch (err) {
      summary.failed += 1;
      console.error(
        `[seasonProgress] session=${doc.id} failed: ${String((err as Error)?.message ?? err).slice(0, 200)}`,
      );
    }
  }

  // --- Claims concedidos (mission/achievement) ainda não contabilizados ----
  const claims = await db
    .collection('claims')
    .where('seasonXpApplied', '==', false)
    .limit(economy.limits.maxBatchSize)
    .get();

  for (const doc of claims.docs) {
    summary.claimsScanned += 1;
    try {
      const data = doc.data();
      const uid = typeof data.uid === 'string' ? data.uid : '';
      const kind = String(data.kind ?? '');
      if (uid.length === 0 || (kind !== 'mission' && kind !== 'achievement')) {
        await doc.ref.update({ seasonXpApplied: true });
        continue;
      }
      const delta = xpForClaim(kind, season.xpConfig);
      if (delta > 0) {
        await applySeasonXp(db, season, uid, delta);
        summary.xpGranted += 1;
        await writeAudit(db, {
          eventId: auditEventId('SEASON_XP_GRANTED', `${season.id}:${doc.id}`),
          userId: uid,
          type: 'SEASON_XP_GRANTED',
          valueUnits: BigInt(delta),
          currencyId: 'season_xp',
          referenceId: doc.id,
          origin: 'runner.seasonProgress',
          ruleVersion: economy.economicRuleVersion,
          status: 'SUCCESS',
          detail: { seasonId: season.id, source: `claim_${kind}` },
        });
      }
      await doc.ref.update({ seasonXpApplied: true });
    } catch (err) {
      summary.failed += 1;
      console.error(
        `[seasonProgress] claim=${doc.id} failed: ${String((err as Error)?.message ?? err).slice(0, 200)}`,
      );
    }
  }

  return summary;
}
