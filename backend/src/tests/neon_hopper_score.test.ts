/**
 * Testes do NEON HOPPER — score OFICIAL por breakdown (pura, sem Firestore).
 *
 * Doc 05 §12/§51: o cliente envia o breakdown {stomps, coins, flagReached};
 * o BACKEND recalcula o score oficial e rejeita qualquer divergência.
 * Espelho das security rules (breakdownValid com get() na config do game).
 */
import {
  validateGameSession,
  validateBreakdownScore,
  SessionValidationResult,
} from '../processors/processGameSessions';
import { EconomyLimits } from '../core/types';

const LIMITS: EconomyLimits = {
  maxSessionsPerDay: 50,
  maxPurchaseIntentsPerDay: 20,
  maxClaimsPerDay: 20,
  minSessionDurationMs: 5_000,
  maxSessionDurationMs: 3_600_000,
  maxScorePerSecond: 100,
  tempGrantDurationMs: 86_400_000,
  maxBatchSize: 100,
  maxUsersPerBlock: 2_000,
};

/** Config EXATA semeada para neon-hopper (games/neon-hopper v1). */
const NEON_HOPPER = {
  id: 'neon-hopper',
  enabled: true,
  configuration: {
    powerBaseReward: 0,
    powerCapPerSession: 0,
    durationSeconds: 45,
    lives: 3,
    pointsPerStomp: 100,
    pointsPerCoin: 50,
    flagBonus: 500,
    maxStomps: 60,
    maxCoins: 40,
    maxScore: 20_000,
    maxScorePerSecond: 300,
    minDurationSeconds: 0,
    maxExpectedScore: 6_000,
    powerCapPerSessionBaseUnits: 150_000,
    powerFormula: 'linear_cap',
    pointsPerKill: 0,
  },
};

function baseInput(overrides: Partial<Parameters<typeof validateGameSession>[0]> = {}) {
  return {
    uid: 'user-1',
    startedAtMs: 1_000_000,
    finishedAtMs: 1_045_000, // 45s (nominal)
    score: 0,
    game: NEON_HOPPER,
    limits: LIMITS,
    defaultPowerBaseReward: 1_000,
    sessionsToday: 0,
    ...overrides,
  };
}

function reasonOf(result: SessionValidationResult): string {
  if (result.ok) throw new Error('expected rejection but got ok');
  return result.reason;
}

describe('validateBreakdownScore — fórmula oficial', () => {
  const cfg = NEON_HOPPER.configuration;

  it('score = stomps×100 + coins×50 + flag×500', () => {
    expect(validateBreakdownScore({ stomps: 10, coins: 4, flagReached: false }, 1_200, cfg)).toEqual({
      ok: true,
      officialScore: 1_200,
    });
    expect(validateBreakdownScore({ stomps: 20, coins: 10, flagReached: true }, 3_000, cfg)).toEqual({
      ok: true,
      officialScore: 3_000,
    });
    expect(validateBreakdownScore({ stomps: 0, coins: 0, flagReached: true }, 500, cfg)).toEqual({
      ok: true,
      officialScore: 500,
    });
  });

  it('rejeita score do cliente ≠ oficial (SCORE_MISMATCH)', () => {
    expect(
      reasonOfBreakdown({ stomps: 10, coins: 4, flagReached: false }, 1_300),
    ).toBe('SCORE_MISMATCH');
    // inflado acima do teto de stomps×pontos também cai no mismatch
    expect(reasonOfBreakdown({ stomps: 5, coins: 0, flagReached: false }, 9_999)).toBe(
      'SCORE_MISMATCH',
    );
  });

  it('rejeita breakdown ausente/malformado', () => {
    expect(reasonOfBreakdown(undefined, 0)).toBe('BREAKDOWN_REQUIRED');
    expect(reasonOfBreakdown(null, 0)).toBe('BREAKDOWN_REQUIRED');
    expect(reasonOfBreakdown('x', 0)).toBe('BREAKDOWN_REQUIRED');
    expect(reasonOfBreakdown([1, 2, 3], 0)).toBe('BREAKDOWN_REQUIRED');
    expect(reasonOfBreakdown({}, 0)).toBe('BREAKDOWN_INVALID');
    expect(reasonOfBreakdown({ stomps: 1 }, 0)).toBe('BREAKDOWN_INVALID');
    // campo extra não permitido
    expect(
      reasonOfBreakdown({ stomps: 1, coins: 0, flagReached: false, extra: 1 }, 100),
    ).toBe('BREAKDOWN_INVALID');
  });

  it('rejeita tipos errados e valores fora dos tetos', () => {
    expect(reasonOfBreakdown({ stomps: -1, coins: 0, flagReached: false }, 0)).toBe(
      'BREAKDOWN_INVALID',
    );
    expect(reasonOfBreakdown({ stomps: 2.5, coins: 0, flagReached: false }, 0)).toBe(
      'BREAKDOWN_INVALID',
    );
    expect(reasonOfBreakdown({ stomps: '10', coins: 0, flagReached: false }, 0)).toBe(
      'BREAKDOWN_INVALID',
    );
    // tetos: maxStomps=60 / maxCoins=40
    expect(
      reasonOfBreakdown({ stomps: 61, coins: 0, flagReached: false }, 6_100),
    ).toBe('BREAKDOWN_INVALID');
    expect(
      reasonOfBreakdown({ stomps: 0, coins: 41, flagReached: false }, 2_050),
    ).toBe('BREAKDOWN_INVALID');
    expect(reasonOfBreakdown({ stomps: 0, coins: 0, flagReached: 'yes' }, 0)).toBe(
      'BREAKDOWN_INVALID',
    );
  });

  it('games SEM breakdown (pointsPerStomp=0) ignoram o campo', () => {
    const legacy = { ...cfg, pointsPerStomp: 0 };
    expect(validateBreakdownScore(undefined, 777, legacy)).toEqual({
      ok: true,
      officialScore: 777,
    });
  });

  function reasonOfBreakdown(bd: unknown, score: number): string {
    const r = validateBreakdownScore(bd, score, cfg);
    if (r.ok) throw new Error('expected rejection but got ok');
    return r.reason;
  }
});

describe('validateGameSession — neon-hopper (fluxo completo)', () => {
  it('aceita sessão consistente e concede power linear_cap', () => {
    // 12 stomps × 100 + 6 coins × 50 = 1500
    const ok = validateGameSession(
      baseInput({
        score: 1_500,
        breakdown: { stomps: 12, coins: 6, flagReached: false },
      }),
    );
    expect(ok.ok).toBe(true);
    if (ok.ok) {
      // floor(min(1500/6000, 1) × 150000) = 37.500 units = 37 H/s
      expect(ok.powerAmount).toBe(37_500n);
    }
  });

  it('cap linear em 150 H/s quando score ≥ maxExpectedScore', () => {
    // 40×100 + 40×50 + 500 = 6500 > maxScore? Não: maxScore=20000; mas
    // maxExpectedScore=6000 ⇒ ratio=1 ⇒ power = 150000 units.
    const ok = validateGameSession(
      baseInput({
        score: 6_500,
        breakdown: { stomps: 40, coins: 40, flagReached: true },
      }),
    );
    expect(ok.ok).toBe(true);
    if (ok.ok) expect(ok.powerAmount).toBe(150_000n);
  });

  it('rejeita score client ≠ oficial', () => {
    expect(
      reasonOf(
        validateGameSession(
          baseInput({
            score: 2_000,
            breakdown: { stomps: 10, coins: 4, flagReached: false },
          }),
        ),
      ),
    ).toBe('SCORE_MISMATCH');
  });

  it('rejeita breakdown ausente em game com pointsPerStomp', () => {
    expect(reasonOf(validateGameSession(baseInput({ score: 100 })))).toBe(
      'BREAKDOWN_REQUIRED',
    );
  });

  it('rejeita duração fora da janela 45±3s', () => {
    const bd = { stomps: 1, coins: 0, flagReached: false };
    expect(
      reasonOf(
        validateGameSession(
          baseInput({ score: 100, breakdown: bd, finishedAtMs: 1_049_000 }), // 49s
        ),
      ),
    ).toBe('DURATION_TOO_LONG');
    expect(
      reasonOf(
        validateGameSession(baseInput({ score: 100, breakdown: bd, finishedAtMs: 1_004_000 })), // 4s
      ),
    ).toBe('DURATION_TOO_SHORT');
  });

  it('rejeita score/segundo acima do cap do game (300/s)', () => {
    // 45s × 300 = 13.500 < 14.000 ⇒ rejeita ANTES do breakdown (ordem de caps)
    expect(
      reasonOf(
        validateGameSession(
          baseInput({
            score: 14_000,
            breakdown: { stomps: 60, coins: 40, flagReached: true },
          }),
        ),
      ),
    ).toBe('SCORE_RATE_EXCEEDED');
  });

  it('score no limite da taxa (13.500 em 45s) passa na taxa e cai no mismatch', () => {
    expect(
      reasonOf(
        validateGameSession(
          baseInput({
            score: 13_500,
            breakdown: { stomps: 60, coins: 40, flagReached: true }, // oficial 8.500
          }),
        ),
      ),
    ).toBe('SCORE_MISMATCH');
  });

  it('rejeita score acima do teto absoluto do game (maxScore=20000)', () => {
    expect(
      reasonOf(validateGameSession(baseInput({ score: 20_001 }))),
    ).toBe('SCORE_OUT_OF_RANGE');
  });

  it('kills legado continua validando mesmo com breakdown presente', () => {
    expect(
      reasonOf(
        validateGameSession(
          baseInput({
            score: 100,
            breakdown: { stomps: 1, coins: 0, flagReached: false },
            kills: 3, // game sem pointsPerKill ⇒ KILLS_NOT_SUPPORTED
          }),
        ),
      ),
    ).toBe('KILLS_NOT_SUPPORTED');
  });
});
