/**
 * Testes da TEMPORADA (PURO, sem Firestore): XP de partida, XP de claim,
 * nível derivado (linear, só sobe) e validação de claims das trilhas
 * free/premium (ativação, nível, duplicidade, PREMIUM_REQUIRED).
 */
import {
  levelFromXp,
  xpForClaim,
  xpForScore,
  xpInLevel,
} from '../processors/season_progress';
import {
  validateSeasonClaim,
  type SeasonDocInput,
  type SeasonProgressInput,
} from '../processors/processClaims';

const XP_CFG = { matchScoreDivisor: 10, missionClaimXp: 50, achievementXp: 100 };

describe('xpForScore (partida = floor(score / divisor))', () => {
  it('converte score em XP com divisor 10', () => {
    expect(xpForScore(0, 10)).toBe(0);
    expect(xpForScore(9, 10)).toBe(0);
    expect(xpForScore(10, 10)).toBe(1);
    expect(xpForScore(2_450, 10)).toBe(245);
    expect(xpForScore(30_000, 10)).toBe(3_000);
  });

  it('entradas inválidas ⇒ 0 (nunca XP negativo/inflado)', () => {
    expect(xpForScore(-5, 10)).toBe(0);
    expect(xpForScore(1.5, 10)).toBe(0);
    expect(xpForScore(100, 0)).toBe(0);
    expect(xpForScore(100, -1)).toBe(0);
  });
});

describe('xpForClaim (bônus fixo por concessão)', () => {
  it('missão = missionClaimXp; conquista = achievementXp', () => {
    expect(xpForClaim('mission', XP_CFG)).toBe(50);
    expect(xpForClaim('achievement', XP_CFG)).toBe(100);
  });
});

describe('levelFromXp / xpInLevel (nível derivado, linear 1200)', () => {
  it('nível 1 começa em 0 XP', () => {
    expect(levelFromXp(0, 1200)).toBe(1);
    expect(levelFromXp(1199, 1200)).toBe(1);
    expect(xpInLevel(840, 1200)).toBe(840);
  });

  it('cada 1200 XP sobe um nível', () => {
    expect(levelFromXp(1200, 1200)).toBe(2);
    expect(levelFromXp(2_400, 1200)).toBe(3);
    expect(levelFromXp(13_200, 1200)).toBe(12);
    expect(xpInLevel(2_040, 1200)).toBe(840);
  });

  it('entradas inválidas ⇒ nível 1 / xp 0', () => {
    expect(levelFromXp(-10, 1200)).toBe(1);
    expect(levelFromXp(100, 0)).toBe(1);
    expect(xpInLevel(-1, 1200)).toBe(0);
  });
});

// ---------------------------------------------------------------------------

const SEASON: SeasonDocInput = {
  id: 'season-01',
  startAtMs: Date.UTC(2026, 7, 20),
  endAtMs: Date.UTC(2026, 8, 19),
  freeRewards: new Map([
    [1, 100_000_000n],
    [3, 200_000_000n],
  ]),
  premiumRewards: new Map([[1, 500_000_000n]]),
};

const PROGRESS: SeasonProgressInput = {
  level: 3,
  claimedFree: {},
  claimedPremium: {},
  premiumActive: false,
};

const NOW = Date.UTC(2026, 7, 24);

function codeOf(result: ReturnType<typeof validateSeasonClaim>): string {
  if (result.ok) throw new Error('expected rejection but got ok');
  return result.code;
}

describe('validateSeasonClaim (trilha GRATUITA)', () => {
  it('claim válido retorna a recompensa EXATA da trilha free', () => {
    expect(
      validateSeasonClaim({
        kind: 'seasonFree',
        seasonId: 'season-01',
        level: 1,
        season: SEASON,
        progress: PROGRESS,
        nowMs: NOW,
      }),
    ).toEqual({ ok: true, rewardUnits: 100_000_000n });
  });

  it('temporada inexistente / id divergente / fora da janela ⇒ rejeita', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 1,
        season: null, progress: PROGRESS, nowMs: NOW,
      })),
    ).toBe('SEASON_NOT_FOUND');
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-02', level: 1,
        season: SEASON, progress: PROGRESS, nowMs: NOW,
      })),
    ).toBe('SEASON_MISMATCH');
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 1,
        season: SEASON, progress: PROGRESS, nowMs: SEASON.endAtMs + 1,
      })),
    ).toBe('SEASON_NOT_ACTIVE');
  });

  it('nível do usuário abaixo do nível da recompensa ⇒ SEASON_LEVEL_TOO_LOW', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 3,
        season: SEASON,
        progress: { ...PROGRESS, level: 2 },
        nowMs: NOW,
      })),
    ).toBe('SEASON_LEVEL_TOO_LOW');
  });

  it('nível sem recompensa na trilha ⇒ SEASON_REWARD_INVALID', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 2,
        season: SEASON, progress: PROGRESS, nowMs: NOW,
      })),
    ).toBe('SEASON_REWARD_INVALID');
  });

  it('duplicado (já resgatado) ⇒ CLAIM_ALREADY_CLAIMED', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 1,
        season: SEASON,
        progress: { ...PROGRESS, claimedFree: { '1': true } },
        nowMs: NOW,
      })),
    ).toBe('CLAIM_ALREADY_CLAIMED');
  });

  it('progresso ausente ⇒ SEASON_PROGRESS_MISSING', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonFree', seasonId: 'season-01', level: 1,
        season: SEASON, progress: null, nowMs: NOW,
      })),
    ).toBe('SEASON_PROGRESS_MISSING');
  });
});

describe('validateSeasonClaim (trilha PREMIUM — travada sem Play Billing)', () => {
  it('sem premiumActive ⇒ PREMIUM_REQUIRED (falha segura e esperada)', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonPremium', seasonId: 'season-01', level: 1,
        season: SEASON, progress: PROGRESS, nowMs: NOW,
      })),
    ).toBe('PREMIUM_REQUIRED');
  });

  it('com premiumActive=true a trilha premium é válida (futuro Play Billing)', () => {
    expect(
      validateSeasonClaim({
        kind: 'seasonPremium', seasonId: 'season-01', level: 1,
        season: SEASON,
        progress: { ...PROGRESS, premiumActive: true },
        nowMs: NOW,
      }),
    ).toEqual({ ok: true, rewardUnits: 500_000_000n });
  });

  it('premium duplicado também é rejeitado', () => {
    expect(
      codeOf(validateSeasonClaim({
        kind: 'seasonPremium', seasonId: 'season-01', level: 1,
        season: SEASON,
        progress: { ...PROGRESS, premiumActive: true, claimedPremium: { '1': true } },
        nowMs: NOW,
      })),
    ).toBe('CLAIM_ALREADY_CLAIMED');
  });
});
