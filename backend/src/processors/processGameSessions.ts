/**
 * Processador de sessões de partida (gameSessions).
 *
 * Consulta status='finished' AND processed=false; valida (TUDO no servidor):
 * dono, duração min/máx, score inteiro 0..maxExpectedScore, score/segundo ≤ cap,
 * limite diário; normaliza pela configuração do game; concede grant de 24h;
 * recalcula totalPower; marca processed=true + serverResult. Idempotente.
 *
 * A função PURA validateGameSession é testável sem Firestore.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import {
  EconomyConfig,
  GameConfiguration,
  GameDoc,
  ProcessingSummary,
} from '../core/types';
import { getEconomyConfig } from '../core/config';
import { createTempGrant, recalcPower } from '../core/power';
import { writeAudit, auditEventId } from '../core/audit';
import { incrementDailyCounter, readDailyCounter } from '../core/ratelimit';
import {
  bumpAchievementProgress,
  bumpMissionProgress,
  validateKillsConsistency,
} from './mission_progress';

// ---------------------------------------------------------------------------
// Validação PURA (unit-testável)
// ---------------------------------------------------------------------------

export interface SessionValidationInput {
  uid: string | null;
  startedAtMs: number;
  finishedAtMs: number;
  score: unknown;
  /** Abates reportados pelo cliente (opcional; validado contra score). */
  kills?: unknown;
  /**
   * Breakdown de gameplay (neon-hopper em diante): {stomps, coins, flagReached}.
   * O score OFICIAL é recalculado no servidor a partir dele (doc 05 §12/§51).
   */
  breakdown?: unknown;
  game: GameDoc | null;
  limits: EconomyConfig['limits'];
  defaultPowerBaseReward: number;
  sessionsToday: number;
}

export type SessionValidationResult =
  | { ok: true; powerAmount: bigint }
  | { ok: false; reason: string };

/** Tolerância de relógio aplicada à duração nominal do game (±3s). */
export const GAME_DURATION_TOLERANCE_S = 3;

/** Tetos padrão de breakdown quando o game não os define (espelho das rules). */
export const DEFAULT_MAX_STOMPS = 60;
export const DEFAULT_MAX_COINS = 40;

export type BreakdownValidationResult =
  | { ok: true; officialScore: number }
  | { ok: false; reason: string };

/**
 * Score OFICIAL por breakdown (PURO — neon-hopper em diante).
 *
 * Games com pointsPerStomp > 0 EXIGEM breakdown {stomps, coins, flagReached}:
 *   oficial = stomps×pointsPerStomp + coins×pointsPerCoin + flagReached×flagBonus
 * Rejeita: ausente, campos extras/ausentes, tipos errados, tetos
 * (maxStomps/maxCoins) e score do cliente ≠ oficial.
 *
 * Games sem pointsPerStomp (legado/nova-swarm): breakdown ignorado se enviado.
 */
export function validateBreakdownScore(
  breakdown: unknown,
  clientScore: number,
  cfg: GameConfiguration,
): BreakdownValidationResult {
  if (cfg.pointsPerStomp <= 0) {
    return { ok: true, officialScore: clientScore }; // game sem breakdown
  }
  if (breakdown === null || typeof breakdown !== 'object' || Array.isArray(breakdown)) {
    return { ok: false, reason: 'BREAKDOWN_REQUIRED' };
  }
  const b = breakdown as Record<string, unknown>;
  const keys = Object.keys(b);
  if (
    keys.length !== 3 ||
    !keys.includes('stomps') ||
    !keys.includes('coins') ||
    !keys.includes('flagReached')
  ) {
    return { ok: false, reason: 'BREAKDOWN_INVALID' };
  }
  const maxStomps = cfg.maxStomps > 0 ? cfg.maxStomps : DEFAULT_MAX_STOMPS;
  const maxCoins = cfg.maxCoins > 0 ? cfg.maxCoins : DEFAULT_MAX_COINS;
  const stomps = b.stomps;
  const coins = b.coins;
  const flagReached = b.flagReached;
  if (typeof stomps !== 'number' || !Number.isSafeInteger(stomps) || stomps < 0 || stomps > maxStomps) {
    return { ok: false, reason: 'BREAKDOWN_INVALID' };
  }
  if (typeof coins !== 'number' || !Number.isSafeInteger(coins) || coins < 0 || coins > maxCoins) {
    return { ok: false, reason: 'BREAKDOWN_INVALID' };
  }
  if (typeof flagReached !== 'boolean') {
    return { ok: false, reason: 'BREAKDOWN_INVALID' };
  }
  const official =
    stomps * cfg.pointsPerStomp +
    coins * cfg.pointsPerCoin +
    (flagReached ? cfg.flagBonus : 0);
  if (official !== clientScore) {
    return { ok: false, reason: 'SCORE_MISMATCH' };
  }
  return { ok: true, officialScore: official };
}

/**
 * Valida a sessão contra a config do game (TUDO no servidor).
 *
 * Duração:
 *  - mínima: cfg.minDurationSeconds (se definido) senão limits.minSessionDurationMs;
 *  - máxima: cfg.durationSeconds + 3s (se definido) senão limits.maxSessionDurationMs.
 *    Morte antes do timer zerar é vitória legítima ⇒ só o piso baixo se aplica.
 * Score: teto = cfg.maxScore (se definido) senão cfg.maxExpectedScore.
 * Taxa: cfg.maxScorePerSecond (se definido) senão limits.maxScorePerSecond.
 *
 * Fórmula do poder:
 *  - linear_cap (nova-swarm em diante):
 *      power = floor(min(score / maxExpectedScore, 1) × powerCapPerSessionBaseUnits)
 *  - legado (doc 05):
 *      rawPower = floor(score × powerBaseReward / maxExpectedScore)
 *      power    = clamp(rawPower, 0, powerCapPerSession)
 */
export function validateGameSession(input: SessionValidationInput): SessionValidationResult {
  const { limits } = input;

  if (!input.uid || input.uid.length === 0) return { ok: false, reason: 'INVALID_OWNER' };
  if (!input.game) return { ok: false, reason: 'GAME_NOT_FOUND' };
  if (!input.game.enabled) return { ok: false, reason: 'GAME_DISABLED' };
  if (!input.game.configuration) return { ok: false, reason: 'GAME_CONFIG_MISSING' };

  const cfg = input.game.configuration;
  const scoreCap = cfg.maxScore > 0 ? cfg.maxScore : cfg.maxExpectedScore;
  if (
    typeof input.score !== 'number' ||
    !Number.isSafeInteger(input.score) ||
    input.score < 0 ||
    input.score > scoreCap
  ) {
    return { ok: false, reason: 'SCORE_OUT_OF_RANGE' };
  }

  const durationMs = input.finishedAtMs - input.startedAtMs;
  const minDurationMs =
    cfg.minDurationSeconds > 0 ? cfg.minDurationSeconds * 1000 : limits.minSessionDurationMs;
  const maxDurationMs =
    cfg.durationSeconds > 0
      ? (cfg.durationSeconds + GAME_DURATION_TOLERANCE_S) * 1000
      : limits.maxSessionDurationMs;
  if (!Number.isFinite(durationMs) || durationMs < minDurationMs) {
    return { ok: false, reason: 'DURATION_TOO_SHORT' };
  }
  if (durationMs > maxDurationMs) {
    return { ok: false, reason: 'DURATION_TOO_LONG' };
  }

  const durationSec = durationMs / 1000;
  const rateCap = cfg.maxScorePerSecond > 0 ? cfg.maxScorePerSecond : limits.maxScorePerSecond;
  if (input.score / durationSec > rateCap) {
    return { ok: false, reason: 'SCORE_RATE_EXCEEDED' };
  }

  // kills (opcional): inteiro ≥ 0 e kills × pointsPerKill ≤ score — cada
  // abate vale PELO MENOS pointsPerKill (bônus só somam). Espelho da regra
  // nas security rules (get() na config do game).
  const killsError = validateKillsConsistency(input.kills, input.score, cfg.pointsPerKill);
  if (killsError) return { ok: false, reason: killsError };

  // Breakdown (neon-hopper em diante): score OFICIAL recalculado no servidor;
  // score do cliente ≠ oficial ⇒ rejeita (SCORE_MISMATCH). Espelho EXATO da
  // validação nas security rules (get() na config do game).
  const breakdown = validateBreakdownScore(input.breakdown, input.score as number, cfg);
  if (!breakdown.ok) return { ok: false, reason: breakdown.reason };

  if (input.sessionsToday >= limits.maxSessionsPerDay) {
    return { ok: false, reason: 'DAILY_LIMIT_REACHED' };
  }

  if (cfg.powerFormula === 'linear_cap' && cfg.powerCapPerSessionBaseUnits > 0) {
    const ratio = Math.min(input.score / cfg.maxExpectedScore, 1);
    return { ok: true, powerAmount: BigInt(Math.floor(ratio * cfg.powerCapPerSessionBaseUnits)) };
  }

  const powerBaseReward =
    cfg.powerBaseReward > 0 ? cfg.powerBaseReward : input.defaultPowerBaseReward;
  const rawPower = Math.floor((input.score * powerBaseReward) / cfg.maxExpectedScore);
  const power = Math.max(0, Math.min(cfg.powerCapPerSession, rawPower));
  return { ok: true, powerAmount: BigInt(power) };
}

// ---------------------------------------------------------------------------
// Processador (Firestore/admin)
// ---------------------------------------------------------------------------

async function loadGame(db: Firestore, gameId: unknown): Promise<GameDoc | null> {
  if (typeof gameId !== 'string' || gameId.length === 0) return null;
  const snap = await db.doc(`games/${gameId}`).get();
  if (!snap.exists) return null;
  const rawCfg = snap.get('configuration') as Record<string, unknown> | undefined;
  const configuration = rawCfg
    ? {
        maxExpectedScore: Number(rawCfg.maxExpectedScore ?? 0),
        powerBaseReward: Number(rawCfg.powerBaseReward ?? 0),
        powerCapPerSession: Number(rawCfg.powerCapPerSession ?? 0),
        durationSeconds: Number(rawCfg.durationSeconds ?? 0),
        maxScore: Number(rawCfg.maxScore ?? 0),
        maxScorePerSecond: Number(rawCfg.maxScorePerSecond ?? 0),
        minDurationSeconds: Number(rawCfg.minDurationSeconds ?? 0),
        powerCapPerSessionBaseUnits: Number(rawCfg.powerCapPerSessionBaseUnits ?? 0),
        powerFormula: typeof rawCfg.powerFormula === 'string' ? rawCfg.powerFormula : '',
        pointsPerKill: Number(rawCfg.pointsPerKill ?? 0),
        pointsPerStomp: Number(rawCfg.pointsPerStomp ?? 0),
        pointsPerCoin: Number(rawCfg.pointsPerCoin ?? 0),
        flagBonus: Number(rawCfg.flagBonus ?? 0),
        maxStomps: Number(rawCfg.maxStomps ?? 0),
        maxCoins: Number(rawCfg.maxCoins ?? 0),
      }
    : null;
  if (configuration && configuration.maxExpectedScore <= 0) return {
    id: gameId,
    enabled: snap.get('enabled') === true,
    configuration: null,
  };
  return { id: gameId, enabled: snap.get('enabled') === true, configuration };
}

async function handleSession(
  db: Firestore,
  economy: EconomyConfig,
  sessionSnap: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<'granted' | 'rejected' | 'failed'> {
  const sessionId = sessionSnap.id;
  const data = sessionSnap.data();
  const uid = typeof data.uid === 'string' ? data.uid : null;
  const ruleVersion = economy.economicRuleVersion;

  try {
    const game = await loadGame(db, data.gameId);
    const sessionsToday = uid
      ? await readDailyCounter(db, uid, 'sessions', nowMs)
      : 0;

    const result = validateGameSession({
      uid,
      startedAtMs: toMillisSafe(data.startedAt),
      finishedAtMs: toMillisSafe(data.finishedAt),
      score: data.score,
      kills: data.kills,
      breakdown: data.breakdown,
      game,
      limits: economy.limits,
      defaultPowerBaseReward: economy.powerBasePerHs,
      sessionsToday,
    });

    if (!result.ok || uid === null) {
      const reason = result.ok ? 'INVALID_OWNER' : result.reason;
      await sessionSnap.ref.update({
        processed: true,
        serverResult: { status: 'rejected', reason, at: FieldValue.serverTimestamp() },
      });
      await writeAudit(db, {
        eventId: auditEventId('GAME_SESSION_REJECTED', sessionId),
        userId: uid,
        type: 'GAME_SESSION_REJECTED',
        referenceId: sessionId,
        origin: 'runner.processGameSessions',
        ruleVersion,
        status: 'REJECTED',
        detail: { reason },
      });
      return 'rejected';
    }

    // Grant 24h — doc id determinístico (= sessionId) ⇒ idempotente.
    const created = await createTempGrant(db, {
      grantId: sessionId,
      uid,
      powerAmount: result.powerAmount,
      source: 'game',
      acquiredAtMs: nowMs,
      expiresAtMs: nowMs + economy.limits.tempGrantDurationMs,
      gameId: typeof data.gameId === 'string' ? data.gameId : undefined,
      gameSessionId: sessionId,
      economicRuleVersion: ruleVersion,
      expired: false,
    });

    const totalPower = await recalcPower(db, uid, nowMs, {
      ruleVersion,
      origin: 'runner.processGameSessions',
    });

    await sessionSnap.ref.update({
      processed: true,
      // Consumido pelo processador de temporada (XP da partida).
      seasonXpApplied: false,
      serverResult: {
        status: created ? 'granted' : 'already_granted',
        powerAmount: result.powerAmount.toString(),
        totalPower: totalPower.toString(),
        expiresAt: new Date(nowMs + economy.limits.tempGrantDurationMs),
        at: FieldValue.serverTimestamp(),
      },
    });

    await writeAudit(db, {
      eventId: auditEventId('GAME_POWER_GRANTED', sessionId),
      userId: uid,
      type: 'GAME_POWER_GRANTED',
      valueUnits: result.powerAmount,
      currencyId: 'power',
      referenceId: sessionId,
      origin: 'runner.processGameSessions',
      ruleVersion,
      status: 'SUCCESS',
      detail: { gameId: typeof data.gameId === 'string' ? data.gameId : '' },
    });

    // Espelho para o histórico do app (rewards/{uid}/items/{sessionId}).
    // Doc id determinístico (= sessionId) ⇒ idempotente; as rules permitem
    // apenas READ owner — escrita é exclusiva do Admin SDK.
    if (created) {
      await db.doc(`rewards/${uid}/items/${sessionId}`).set({
        type: 'GAME_REWARD',
        amount: result.powerAmount.toString(),
        currencyId: 'power',
        createdAt: FieldValue.serverTimestamp(),
        referenceId: sessionId,
      });
    }

    // Progresso de missões/conquistas a partir do evento REAL consolidado
    // (somente quando o grant foi criado — idempotente por sessionId).
    if (created) {
      // neon-hopper: stomps do breakdown alimentam o metric 'kills' (mesmo
      // domínio "inimigos derrotados") quando kills não é enviado direto.
      const breakdownStomps =
        data.breakdown !== null &&
        typeof data.breakdown === 'object' &&
        typeof (data.breakdown as Record<string, unknown>).stomps === 'number'
          ? Number((data.breakdown as Record<string, unknown>).stomps)
          : 0;
      const rawKills =
        typeof data.kills === 'number' && Number.isSafeInteger(data.kills)
          ? data.kills
          : breakdownStomps;
      const kills = Number.isSafeInteger(rawKills) && rawKills > 0 ? rawKills : 0;
      const finalScore = typeof data.score === 'number' ? data.score : 0;
      await bumpMissionProgress(db, uid, 'plays', 'add', 1, nowMs);
      await bumpMissionProgress(db, uid, 'max_score', 'max', finalScore, nowMs);
      if (kills > 0) await bumpMissionProgress(db, uid, 'kills', 'add', kills, nowMs);
      await bumpAchievementProgress(db, uid, 'plays', 'add', 1);
      await bumpAchievementProgress(db, uid, 'max_score', 'max', finalScore);
      if (kills > 0) await bumpAchievementProgress(db, uid, 'kills', 'add', kills);
      await incrementDailyCounter(db, uid, 'sessions', nowMs);
    }
    return 'granted';
  } catch (err) {
    // Falha operacional: NÃO marca processed (retry na próxima execução).
    console.error(
      `[processGameSessions] session=${sessionId} failed: ${sanitize(err)}`,
    );
    return 'failed';
  }
}

function toMillisSafe(v: unknown): number {
  if (v == null) return NaN;
  if (typeof v === 'number') return v;
  const t = v as { toMillis?: () => number };
  return typeof t.toMillis === 'function' ? t.toMillis() : NaN;
}

function sanitize(err: unknown): string {
  return String((err as Error)?.message ?? err).slice(0, 300);
}

/** Ponto de entrada do runner. */
export async function processGameSessions(db: Firestore): Promise<ProcessingSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor

  const snap = await db
    .collection('gameSessions')
    .where('status', '==', 'finished')
    .where('processed', '==', false)
    .orderBy('finishedAt', 'asc')
    .limit(economy.limits.maxBatchSize)
    .get();

  const summary: ProcessingSummary = { scanned: snap.size, granted: 0, rejected: 0, failed: 0 };
  for (const doc of snap.docs) {
    const outcome = await handleSession(db, economy, doc, nowMs);
    summary[outcome] += 1;
  }
  return summary;
}
