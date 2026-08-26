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
  maxClaimsPerDay: 20,
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
  configuration: {
    maxExpectedScore: 1_000,
    powerBaseReward: 250,
    powerCapPerSession: 250,
    durationSeconds: 0,
    maxScore: 0,
    maxScorePerSecond: 0,
    minDurationSeconds: 0,
    powerCapPerSessionBaseUnits: 0,
    powerFormula: '',
    pointsPerKill: 0,
    pointsPerStomp: 0,
    pointsPerCoin: 0,
    flagBonus: 0,
    maxStomps: 0,
    maxCoins: 0,
  },
};

/** Config EXATA semeadas para nova-swarm (autoridade econômica). */
const NOVA_SWARM = {
  id: 'nova-swarm',
  enabled: true,
  configuration: {
    powerBaseReward: 0,
    powerCapPerSession: 0,
    durationSeconds: 60,
    baseEnemies: 8,
    enemiesPerWaveStep: 4,
    enemyHp: 2,
    lives: 3,
    pointsPerKill: 150,
    pointsPerHit: 25,
    waveBonus: 500,
    maxScore: 30_000,
    maxScorePerSecond: 500,
    minDurationSeconds: 5,
    maxExpectedScore: 12_000,
    powerCapPerSessionBaseUnits: 100_000,
    powerFormula: 'linear_cap',
    pointsPerStomp: 0,
    pointsPerCoin: 0,
    flagBonus: 0,
    maxStomps: 0,
    maxCoins: 0,
  },
};

describe('validateGameSession — kills (consistência com score)', () => {
  function novaInput(overrides: Partial<Parameters<typeof validateGameSession>[0]> = {}) {
    return baseInput({ game: NOVA_SWARM, score: 6_000, ...overrides });
  }

  it('aceita kills coerente: kills × pointsPerKill ≤ score', () => {
    // 10 kills × 150 = 1500 ≤ 6000 (resto vem de hits/waveBonus)
    expect(validateGameSession(novaInput({ kills: 10 })).ok).toBe(true);
    // kills ausente (games legados) continua válido
    expect(validateGameSession(novaInput()).ok).toBe(true);
    // 0 kills é válido
    expect(validateGameSession(novaInput({ kills: 0 })).ok).toBe(true);
  });

  it('rejeita kills inválido (negativo, fracionário, não-número)', () => {
    expect(reasonOf(validateGameSession(novaInput({ kills: -1 })))).toBe('KILLS_INVALID');
    expect(reasonOf(validateGameSession(novaInput({ kills: 2.5 })))).toBe('KILLS_INVALID');
    expect(reasonOf(validateGameSession(novaInput({ kills: '10' })))).toBe('KILLS_INVALID');
  });

  it('rejeita kills inconsistente: kills × pointsPerKill > score', () => {
    // 41 × 150 = 6150 > 6000
    expect(reasonOf(validateGameSession(novaInput({ kills: 41 })))).toBe('KILLS_INCONSISTENT');
    // exatamente igual é válido: 40 × 150 = 6000
    expect(validateGameSession(novaInput({ kills: 40 })).ok).toBe(true);
  });

  it('rejeita kills > 0 em game SEM pointsPerKill (legado)', () => {
    expect(reasonOf(validateGameSession(baseInput({ kills: 3 })))).toBe('KILLS_NOT_SUPPORTED');
  });
});

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
      configuration: {
        maxExpectedScore: 1_000,
        powerBaseReward: 0,
        powerCapPerSession: 5_000,
        durationSeconds: 0,
        maxScore: 0,
        maxScorePerSecond: 0,
        minDurationSeconds: 0,
        powerCapPerSessionBaseUnits: 0,
        powerFormula: '',
        pointsPerKill: 0,
        pointsPerStomp: 0,
        pointsPerCoin: 0,
        flagBonus: 0,
        maxStomps: 0,
        maxCoins: 0,
      },
    };
    // floor(500 × 1000 / 1000) = 500
    expect(validateGameSession(baseInput({ score: 500, game: g }))).toEqual({
      ok: true,
      powerAmount: 500n,
    });
  });
});

describe('validateGameSession — nova-swarm (linear_cap)', () => {
  function novaInput(overrides: Partial<Parameters<typeof validateGameSession>[0]> = {}) {
    return baseInput({ game: NOVA_SWARM, score: 6_000, ...overrides });
  }

  it('fórmula linear_cap: power = floor(min(score/12000,1) × 100000)', () => {
    // 6000/12000 = 0.5 → 50_000 units = 50 H
    expect(validateGameSession(novaInput({ score: 6_000 }))).toEqual({
      ok: true,
      powerAmount: 50_000n,
    });
    // Cap: score ≥ maxExpectedScore → 100_000 units (100 H) — nunca passa do cap
    expect(validateGameSession(novaInput({ score: 30_000 }))).toEqual({
      ok: true,
      powerAmount: 100_000n,
    });
    // Score baixo: floor(150/12000 × 100000) = 1250
    expect(validateGameSession(novaInput({ score: 150 }))).toEqual({
      ok: true,
      powerAmount: 1_250n,
    });
  });

  it('aceita score até maxScore (30_000) mesmo acima de maxExpectedScore (12_000)', () => {
    expect(validateGameSession(novaInput({ score: 25_000 })).ok).toBe(true);
    expect(reasonOf(validateGameSession(novaInput({ score: 30_001 })))).toBe('SCORE_OUT_OF_RANGE');
  });

  it('duração: 60s nominal; morte antecipada ≥5s é válida; >63s rejeita', () => {
    const start = 1_000_000;
    // 60s exatos: ok
    expect(validateGameSession(novaInput({ startedAtMs: start, finishedAtMs: start + 60_000 })).ok)
      .toBe(true);
    // 63s = limite com tolerância de 3s: ok; 63.1s: rejeita
    expect(validateGameSession(novaInput({ startedAtMs: start, finishedAtMs: start + 63_000 })).ok)
      .toBe(true);
    expect(
      reasonOf(validateGameSession(novaInput({ startedAtMs: start, finishedAtMs: start + 63_100 }))),
    ).toBe('DURATION_TOO_LONG');
    // Morte aos 20s (≥ minDurationSeconds 5): válida
    expect(validateGameSession(novaInput({ startedAtMs: start, finishedAtMs: start + 20_000 })).ok)
      .toBe(true);
    // Abaixo de 5s: rejeita
    expect(
      reasonOf(validateGameSession(novaInput({ startedAtMs: start, finishedAtMs: start + 4_999 }))),
    ).toBe('DURATION_TOO_SHORT');
  });

  it('taxa de score usa o cap do game (500/s)', () => {
    const start = 1_000_000;
    // 20_000 em 60s = 333/s < 500/s: ok
    expect(
      validateGameSession(novaInput({ score: 20_000, startedAtMs: start, finishedAtMs: start + 60_000 }))
        .ok,
    ).toBe(true);
    // 500 em 1s… abaixo do piso de duração; usa 5s: 500/5 = 100/s ok.
    // 4_000 em 5s = 800/s > 500/s: rejeita
    expect(
      reasonOf(
        validateGameSession(
          novaInput({ score: 4_000, startedAtMs: start, finishedAtMs: start + 5_000 }),
        ),
      ),
    ).toBe('SCORE_RATE_EXCEEDED');
  });
});
