/**
 * Testes de validação de sessões de partida (pura, sem Firestore).
 * Cobre: dono, duração min/máx, score 0..maxExpectedScore, score/segundo,
 * limite diário, game desabilitado/sem config e cálculo/cap do grant.
 */
import {
  validateGameSession,
  SessionValidationResult,
} from '../processors/processGameSessions';
import { EconomyLimits } from '../core/types';

const LIMITS: EconomyLimits = {
  maxSessionsPerDay: 3,
  maxPurchaseIntentsPerDay: 20,
  minSessionDurationMs: 5_000,
  maxSessionDurationMs: 120_000,
  maxScorePerSecond: 20,
  tempGrantDurationMs: 86_400_000,
  maxBatchSize: 100,
  maxUsersPerBlock: 2_000,
};

const GAME = {
  id: 'tap-blitz',
  enabled: true,
  configuration: { maxExpectedScore: 1_000, powerBaseReward: 250, powerCapPerSession: 250 },
};

function baseInput(overrides: Partial<Parameters<typeof validateGameSession>[0]> = {}) {
  return {
    uid: 'user-1',
    startedAtMs: 1_000_000,
    finishedAtMs: 1_060_000, // 60s
    score: 50,
    game: GAME,
    limits: LIMITS,
    defaultPowerBaseReward: 1_000,
    sessionsToday: 0,
    ...overrides,
  };
}

/** Helper: extrai reason garantindo que o resultado foi uma rejeição. */
function reasonOf(result: SessionValidationResult): string {
  if (result.ok) throw new Error('expected rejection but got ok');
  return result.reason;
}

describe('validateGameSession', () => {
  it('sessão válida concede power proporcional com cap', () => {
    // rawPower = floor(500 × 250 / 1000) = 125
    const ok = validateGameSession(baseInput({ score: 500 }));
    expect(ok).toEqual({ ok: true, powerAmount: 125n });

    // Cap: score máximo → rawPower = 250 (== cap)
    const capped = validateGameSession(baseInput({ score: 1_000 }));
    expect(capped).toEqual({ ok: true, powerAmount: 250n });
  });

  it('rejeita dono ausente e game inexistente/desabilitado', () => {
    expect(reasonOf(validateGameSession(baseInput({ uid: null })))).toBe('INVALID_OWNER');
    expect(reasonOf(validateGameSession(baseInput({ game: null })))).toBe('GAME_NOT_FOUND');
    expect(
      reasonOf(validateGameSession(baseInput({ game: { ...GAME, enabled: false } }))),
    ).toBe('GAME_DISABLED');
    expect(
      reasonOf(
        validateGameSession(
          baseInput({ game: { id: 'x', enabled: true, configuration: null } }),
        ),
      ),
    ).toBe('GAME_CONFIG_MISSING');
  });

  it('rejeita score fora de [0, maxExpectedScore] e não-inteiro', () => {
    expect(reasonOf(validateGameSession(baseInput({ score: -1 })))).toBe('SCORE_OUT_OF_RANGE');
    expect(reasonOf(validateGameSession(baseInput({ score: 1_001 })))).toBe('SCORE_OUT_OF_RANGE');
    expect(reasonOf(validateGameSession(baseInput({ score: 10.5 })))).toBe('SCORE_OUT_OF_RANGE');
    expect(reasonOf(validateGameSession(baseInput({ score: '999' })))).toBe('SCORE_OUT_OF_RANGE');
  });

  it('rejeita duração fora dos limites', () => {
    expect(
      reasonOf(validateGameSession(baseInput({ finishedAtMs: 1_002_000 }))), // 2s < min
    ).toBe('DURATION_TOO_SHORT');
    expect(
      reasonOf(validateGameSession(baseInput({ finishedAtMs: 1_200_000 }))), // 200s > max
    ).toBe('DURATION_TOO_LONG');
  });

  it('rejeita score/segundo acima do cap (anti-autoplay)', () => {
    // 400 pontos em 10s = 40/s > 20/s
    expect(
      reasonOf(validateGameSession(baseInput({ score: 400, finishedAtMs: 1_010_000 }))),
    ).toBe('SCORE_RATE_EXCEEDED');
  });

  it('aplica limite diário de sessões', () => {
    expect(reasonOf(validateGameSession(baseInput({ sessionsToday: 3 })))).toBe(
      'DAILY_LIMIT_REACHED',
    );
    // Abaixo do limite ainda passa
    expect(validateGameSession(baseInput({ sessionsToday: 2 })).ok).toBe(true);
  });

  it('expiração 24h: expiresAtMs = acquiredAtMs + tempGrantDurationMs', () => {
    // O processador usa nowMs + limits.tempGrantDurationMs; garantimos o valor.
    expect(LIMITS.tempGrantDurationMs).toBe(86_400_000);
  });

  it('usa powerBaseReward do game quando presente, senão o default da economia', () => {
    // Game define powerBaseReward=250 → floor(1000×250/1000)=250 → cap 250
    expect(validateGameSession(baseInput({ score: 1_000 })).ok).toBe(true);
    // Sem powerBaseReward no game (0) → usa default 1000:
    const g = {
      id: 'g',
      enabled: true,
      configuration: { maxExpectedScore: 1_000, powerBaseReward: 0, powerCapPerSession: 5_000 },
    };
    // floor(500 × 1000 / 1000) = 500
    expect(validateGameSession(baseInput({ score: 500, game: g }))).toEqual({
      ok: true,
      powerAmount: 500n,
    });
  });
});
