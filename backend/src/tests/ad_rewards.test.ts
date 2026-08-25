/**
 * Testes do processador de recompensas por anúncio (doc 04/05 §31).
 * validateAdReward é PURA — sem Firestore. Cobre: limite diário, cooldown,
 * idempotência de campos, crédito (1 COIN + xpBonus) e antifraude.
 */
import { validateAdReward, AdsRewardedConfig } from '../processors/processAdRewards';

const CONFIG: AdsRewardedConfig = {
  enabled: true,
  dailyLimit: 10,
  cooldownMinutes: 5,
  rewardUnits: 1_000_000n, // 1 COIN
  xpBonus: 25,
};

const BASE = {
  uid: 'user-1',
  type: 'rewarded',
  clientRequestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  config: CONFIG,
  todayCount: 0,
  lastGrantedAtMs: null as number | null,
  nowMs: 1_800_000_000_000,
  accountStatus: 'active',
};

describe('validateAdReward — campos e config', () => {
  it('recompensa válida retorna EXATAMENTE 1 COIN + xpBonus da config', () => {
    const v = validateAdReward(BASE);
    expect(v.ok).toBe(true);
    if (v.ok) {
      expect(v.rewardUnits).toBe(1_000_000n);
      expect(v.xpBonus).toBe(25);
    }
  });

  it('rejeita uid vazio / type != rewarded / clientRequestId curto', () => {
    expect(validateAdReward({ ...BASE, uid: '' })).toEqual({ ok: false, code: 'INVALID_FIELDS' });
    expect(validateAdReward({ ...BASE, type: 'interstitial' })).toEqual({
      ok: false,
      code: 'INVALID_FIELDS',
    });
    expect(validateAdReward({ ...BASE, clientRequestId: 'curto' })).toEqual({
      ok: false,
      code: 'INVALID_FIELDS',
    });
  });

  it('config ausente/desabilitada/recompensa inválida ⇒ ADS_DISABLED', () => {
    expect(validateAdReward({ ...BASE, config: null })).toEqual({ ok: false, code: 'ADS_DISABLED' });
    expect(
      validateAdReward({ ...BASE, config: { ...CONFIG, enabled: false } }),
    ).toEqual({ ok: false, code: 'ADS_DISABLED' });
    expect(
      validateAdReward({ ...BASE, config: { ...CONFIG, rewardUnits: 0n } }),
    ).toEqual({ ok: false, code: 'ADS_DISABLED' });
  });
});

describe('validateAdReward — limite diário e cooldown', () => {
  it('dailyLimit atingido ⇒ DAILY_LIMIT_REACHED', () => {
    const v = validateAdReward({ ...BASE, todayCount: 10 });
    expect(v).toEqual({ ok: false, code: 'DAILY_LIMIT_REACHED' });
  });

  it('9 de 10 ainda passa; o 11º não', () => {
    expect(validateAdReward({ ...BASE, todayCount: 9 }).ok).toBe(true);
    expect(validateAdReward({ ...BASE, todayCount: 10 }).ok).toBe(false);
  });

  it('cooldown ativo bloqueia mesmo com cota livre ⇒ COOLDOWN_ACTIVE', () => {
    const v = validateAdReward({
      ...BASE,
      lastGrantedAtMs: BASE.nowMs - 4 * 60_000, // 4 min < 5 min
    });
    expect(v).toEqual({ ok: false, code: 'COOLDOWN_ACTIVE' });
  });

  it('cooldown vencido (>= 5 min) passa', () => {
    const v = validateAdReward({
      ...BASE,
      lastGrantedAtMs: BASE.nowMs - 5 * 60_000,
    });
    expect(v.ok).toBe(true);
  });

  it('cooldown de outra data (ontem) NÃO bloqueia hoje', () => {
    // lastGrantedAtMs muito antigo ⇒ diferença >> cooldown ⇒ ok.
    const v = validateAdReward({
      ...BASE,
      lastGrantedAtMs: BASE.nowMs - 86_400_000,
    });
    expect(v.ok).toBe(true);
  });
});

describe('validateAdReward — antifraude', () => {
  it('conta em review/blocked/banned ⇒ ACCOUNT_BLOCKED (código seguro)', () => {
    for (const status of ['review', 'blocked', 'banned']) {
      expect(validateAdReward({ ...BASE, accountStatus: status })).toEqual({
        ok: false,
        code: 'ACCOUNT_BLOCKED',
      });
    }
  });

  it('status ausente/vazio é tratado como active (default seguro p/ contas novas)', () => {
    expect(validateAdReward({ ...BASE, accountStatus: '' }).ok).toBe(true);
  });

  it('ACCOUNT_BLOCKED tem precedência sobre limite diário', () => {
    const v = validateAdReward({ ...BASE, accountStatus: 'blocked', todayCount: 99 });
    expect(v).toEqual({ ok: false, code: 'ACCOUNT_BLOCKED' });
  });
});
