/**
 * Testes das LIGAS (PURO, sem Firestore): atribuição por limiares
 * (maior tier com minPower ≤ totalPower), máscara segura do leaderboard
 * e chaves de auditoria determinísticas (promoção e diária idempotente).
 */
import {
  dailyGrantEventId,
  maskedName,
  promotionEventId,
  resolveLeagueId,
  type LeagueThreshold,
} from '../processors/league_sweep';

// Limiares do seed (units BASE, powerBasePerHs = 1.000):
// BRONZE 100 H/s · PRATA 500 · OURO 1.500 · PLATINA 10.000 · DIAMANTE 100.000.
const LEAGUES: LeagueThreshold[] = [
  { id: 'bronze', name: 'BRONZE', tier: 1, minPowerUnits: 100_000n, dailyRewardUnits: 50_000_000n },
  { id: 'prata', name: 'PRATA', tier: 2, minPowerUnits: 500_000n, dailyRewardUnits: 100_000_000n },
  { id: 'ouro', name: 'OURO', tier: 3, minPowerUnits: 1_500_000n, dailyRewardUnits: 250_000_000n },
  { id: 'platina', name: 'PLATINA', tier: 4, minPowerUnits: 10_000_000n, dailyRewardUnits: 500_000_000n },
  { id: 'diamante', name: 'DIAMANTE', tier: 5, minPowerUnits: 100_000_000n, dailyRewardUnits: 1_000_000_000n },
];

describe('resolveLeagueId (atribuição por limiares)', () => {
  it('abaixo do menor limiar ⇒ sem liga (null)', () => {
    expect(resolveLeagueId(LEAGUES, 0n)).toBeNull();
    expect(resolveLeagueId(LEAGUES, 99_999n)).toBeNull();
  });

  it('limiares exatos atribuem a liga correspondente', () => {
    expect(resolveLeagueId(LEAGUES, 100_000n)).toBe('bronze');
    expect(resolveLeagueId(LEAGUES, 500_000n)).toBe('prata');
    expect(resolveLeagueId(LEAGUES, 1_500_000n)).toBe('ouro');
    expect(resolveLeagueId(LEAGUES, 10_000_000n)).toBe('platina');
    expect(resolveLeagueId(LEAGUES, 100_000_000n)).toBe('diamante');
  });

  it('um abaixo do limiar cai para a liga anterior', () => {
    expect(resolveLeagueId(LEAGUES, 499_999n)).toBe('bronze');
    expect(resolveLeagueId(LEAGUES, 1_499_999n)).toBe('prata');
    expect(resolveLeagueId(LEAGUES, 99_999_999n)).toBe('platina');
  });

  it('poder muito alto permanece na liga máxima', () => {
    expect(resolveLeagueId(LEAGUES, 999_999_999_999n)).toBe('diamante');
  });

  it('lista fora de ordem ainda escolhe o MAIOR tier elegível', () => {
    const shuffled = [LEAGUES[3]!, LEAGUES[0]!, LEAGUES[4]!, LEAGUES[2]!, LEAGUES[1]!];
    expect(resolveLeagueId(shuffled, 2_000_000n)).toBe('ouro');
  });

  it('limiar inválido (≤ 0) nunca atribui liga', () => {
    const broken: LeagueThreshold[] = [
      { id: 'x', name: 'X', tier: 9, minPowerUnits: 0n, dailyRewardUnits: 1n },
    ];
    expect(resolveLeagueId(broken, 5n)).toBeNull();
  });
});

describe('maskedName (leaderboard sem dados pessoais)', () => {
  it('2 primeiros caracteres + *** (maiúsculas)', () => {
    expect(maskedName('PlayerX')).toBe('PL***');
    expect(maskedName('cryptofox')).toBe('CR***');
  });

  it('nome curto (1 char) ainda mascara', () => {
    expect(maskedName('A')).toBe('A***');
  });

  it('sem nome ⇒ máscara total (nunca expõe uid/e-mail)', () => {
    expect(maskedName(null)).toBe('??***');
    expect(maskedName('')).toBe('??***');
    expect(maskedName('   ')).toBe('??***');
    expect(maskedName(undefined)).toBe('??***');
  });
});

describe('auditoria determinística (idempotência)', () => {
  it('promoção: mesma chave para o mesmo uid+liga', () => {
    expect(promotionEventId('u1', 'ouro')).toBe(promotionEventId('u1', 'ouro'));
    expect(promotionEventId('u1', 'ouro')).toBe('LEAGUE_PROMOTED:u1:ouro');
    expect(promotionEventId('u1', 'prata')).not.toBe(promotionEventId('u1', 'ouro'));
  });

  it('diária: chave por uid+DIA ⇒ reexecução no mesmo dia é no-op', () => {
    expect(dailyGrantEventId('u1', '2026-08-24')).toBe('LEAGUE_REWARD_GRANTED:u1:2026-08-24');
    expect(dailyGrantEventId('u1', '2026-08-24')).toBe(dailyGrantEventId('u1', '2026-08-24'));
    expect(dailyGrantEventId('u1', '2026-08-25')).not.toBe(dailyGrantEventId('u1', '2026-08-24'));
  });
});
