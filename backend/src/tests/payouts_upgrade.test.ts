/**
 * Testes do UPGRADE IDEMPOTENTE de config/payouts (prompt 12.8).
 * Cobre: v1→v3 e v2→v3 (MERGE seguro, nunca destrói), idempotência
 * (aplicar 2× = mesmo resultado) e doc ausente ⇒ cria já em v3.
 */
import {
  PAYOUTS_ASSET_V2,
  PAYOUTS_V1,
  applyPayoutsAssetV3,
  buildPayoutsV3Doc,
  buildPayoutsV4Doc,
  normalizePayoutsDoc,
} from '../core/payoutsUpgrade';

function assetById(
  assets: Record<string, unknown>[],
  id: string,
): Record<string, unknown> {
  const found = assets.find((a) => a.id === id);
  if (!found) throw new Error(`asset ${id} não encontrado`);
  return found;
}

describe('buildPayoutsV3Doc — doc AUSENTE', () => {
  it('cria já em v3: base v1 + v2 + campos v3, version=3', () => {
    const doc = buildPayoutsV3Doc(null);
    expect(doc.version).toBe(3);
    expect(doc.destinationType).toBe('faucetpay_email');
    expect(doc.futureRateSource).toBe('usd_auto');
    const ltc = assetById(doc.assets as Record<string, unknown>[], 'LTC');
    // Campos v3 exigidos:
    expect(ltc.enabled).toBe(true);
    expect(ltc.network).toBe('FaucetPayEmail');
    expect(ltc.litoshiPerCoin).toBe(100);
    expect(ltc.minWithdrawCoins).toBe(20);
    expect(ltc.feeCoins).toBe(2);
    expect(ltc.providerMinLitoshi).toBeNull();
    // Compat numérica em sincronia:
    expect(ltc.minWithdrawUnits).toBe(20_000_000);
    expect(ltc.feeUnits).toBe(2_000_000);
    // Demais ativos desabilitados:
    for (const id of ['BTC', 'DOGE', 'USDT']) {
      expect(assetById(doc.assets as Record<string, unknown>[], id).enabled).toBe(false);
    }
  });
});

describe('upgrade v1 → v3', () => {
  it('payload v3 = MERGE por ativos; escalares v1 ficam no doc via set(merge)', () => {
    const v1Doc = { ...PAYOUTS_V1 };
    const doc = buildPayoutsV3Doc(v1Doc);
    expect(doc.version).toBe(3);
    // O payload contém APENAS o delta v3 (metadados + ativos + version).
    // Os escalares v1 (cooldownHours etc.) NUNCA são removidos do doc:
    // o seed grava com set(payload, {merge:true}), que os preserva.
    expect(doc.cooldownHours).toBeUndefined();
    const ltc = assetById(doc.assets as Record<string, unknown>[], 'LTC');
    // Campo legado v1 preservado no ATIVO + campo v3 adicionado:
    expect(ltc.id).toBe('LTC');
    expect(ltc.litoshiPerCoin).toBe(100);
    expect(ltc.enabled).toBe(true);
  });

  it('simulação de MERGE no doc: escalares v1 sobrevivem ao upgrade', () => {
    // Réplica do efeito de ref.set(buildPayoutsV3Doc(doc), {merge:true}):
    const stored = { ...PAYOUTS_V1 };
    const patched = { ...stored, ...buildPayoutsV3Doc(stored) };
    expect(patched.version).toBe(3);
    expect(patched.cooldownHours).toBe(24);
    expect(patched.maxPerDay).toBe(3);
    expect(patched.minAccountAgeHours).toBe(24);
    expect(patched.requireFinishedGames).toBe(1);
    expect(patched.coinPrecision).toBe(1_000_000);
    expect(assetById(patched.assets as Record<string, unknown>[], 'LTC').litoshiPerCoin).toBe(100);
  });
});

describe('upgrade v2 → v3', () => {
  it('preserva campos v2 e sobrepõe apenas os campos v3', () => {
    const v2Assets = (PAYOUTS_V1.assets as Record<string, unknown>[]).map(
      (a) => ({
        ...a,
        ...(typeof a.id === 'string' ? PAYOUTS_ASSET_V2[a.id] : undefined),
      }),
    );
    const v2Doc = { ...PAYOUTS_V1, assets: v2Assets, version: 2 };
    const doc = buildPayoutsV3Doc(v2Doc as Record<string, unknown>);
    expect(doc.version).toBe(3);
    const ltc = assetById(doc.assets as Record<string, unknown>[], 'LTC');
    // Campos v2 preservados quando o v3 não os redefine:
    expect(ltc.assetDecimals).toBe(8);
    // Campos v3 SOBREPÕEM a conversão v2 (taxa fixa autoritativa):
    expect(ltc.assetUnitPerCoinScaled).toBe(100); // v2 tinha 2000
    expect(ltc.minWithdrawUnits).toBe(20_000_000); // v2 tinha 60_000_000
    expect(ltc.providerMinAssetUnits).toBe(0); // v2 tinha 100_000
    expect(ltc.providerFeeAssetUnits).toBe(0); // v2 tinha 5_000
    expect(ltc.providerMinLitoshi).toBeNull();
    expect(ltc.rateSource).toBe('fixed');
  });
});

describe('idempotência do upgrade', () => {
  it('aplicar 2× produz EXATAMENTE o mesmo resultado', () => {
    const once = buildPayoutsV3Doc({ ...PAYOUTS_V1 });
    const twice = buildPayoutsV3Doc({ ...once });
    expect(twice).toEqual(once);
  });

  it('applyPayoutsAssetV3 é PURA (não muta a entrada) e é no-op em v3', () => {
    const input = [{ id: 'LTC', network: 'Litecoin', enabled: true }];
    const snapshot = JSON.stringify(input);
    const out = applyPayoutsAssetV3(input);
    expect(JSON.stringify(input)).toBe(snapshot); // entrada intacta
    expect(out[0]!.litoshiPerCoin).toBe(100);
    // Já-v3 permanece idêntico:
    const v3 = applyPayoutsAssetV3(out);
    expect(v3).toEqual(out);
  });

  it('ativos sem entry v3 passam intocados; ids não-string ignorados', () => {
    const out = applyPayoutsAssetV3([
      { id: 'SOL', enabled: true },
      { enabled: true },
    ]);
    expect(out[0]).toEqual({ id: 'SOL', enabled: true });
    expect(out[1]).toEqual({ enabled: true });
  });
});

describe('SCHEMA CANÔNICO v4 (12.9): normalização de legado', () => {
  it('doc AUSENTE ⇒ defaults canônicos (LTC habilitado, taxa fixa)', () => {
    const n = normalizePayoutsDoc(null);
    expect(n.version).toBe(1);
    expect(n.assets.LTC).toBeDefined();
    expect(n.assets.LTC!.enabled).toBe(true);
    expect(n.assets.LTC!.litoshiPerCoin).toBe(100);
    expect(n.assets.LTC!.minWithdrawCoins).toBe(20);
    expect(n.assets.LTC!.feeCoins).toBe(2);
    expect(n.assets.LTC!.providerMinLitoshi).toBeNull();
    expect(n.assets.BTC!.enabled).toBe(false);
  });

  it('legado ARRAY com ids lower/upper e campos antigos ⇒ mapa UPPER canônico', () => {
    const legacy = {
      version: 3,
      cooldownHours: 24,
      assets: [
        {
          id: 'ltc',
          network: 'FaucetPayEmail',
          enabled: true,
          // Campos ANTIGOS (v2) em vez dos v4:
          assetUnitPerCoinScaled: 100, // alias de litoshiPerCoin
          minWithdrawUnits: 20_000_000, // 20 coins (÷1e6)
          feeUnits: 2_000_000, // 2 coins
          providerMinLitoshi: null,
        },
        { id: 'BTC', enabled: false },
      ],
    };
    const n = normalizePayoutsDoc(legacy as Record<string, unknown>);
    // LTC/BTC do legado + completude canônica (DOGE/USDT adicionados):
    expect(Object.keys(n.assets)).toEqual(['LTC', 'BTC', 'DOGE', 'USDT']);
    expect(n.assets.LTC!.litoshiPerCoin).toBe(100);
    expect(n.assets.LTC!.minWithdrawCoins).toBe(20);
    expect(n.assets.LTC!.feeCoins).toBe(2);
    expect(n.assets.BTC!.enabled).toBe(false);
  });

  it('v4 MAPA keyed por id passa direto (idempotente)', () => {
    const doc = buildPayoutsV4Doc(null);
    const again = normalizePayoutsDoc(doc);
    expect(again.version).toBe(4);
    expect(again.assets).toEqual(doc.assets);
    // buildPayoutsV4Doc(normalize(build)) == build — idempotência total:
    expect(buildPayoutsV4Doc(doc)).toEqual(doc);
  });

  it('escalares antifraude do legado são preservados no doc v4', () => {
    const doc = buildPayoutsV4Doc({
      ...PAYOUTS_V1,
      version: 2,
      assets: [{ id: 'LTC', network: 'Litecoin', enabled: true }],
    } as Record<string, unknown>);
    expect(doc.version).toBe(4);
    expect(doc.cooldownHours).toBe(24);
    expect(doc.maxPerDay).toBe(3);
    expect(doc.minAccountAgeHours).toBe(24);
    expect(doc.requireFinishedGames).toBe(1);
    expect(doc.coinPrecision).toBe(1_000_000);
    expect(doc.destinationType).toBe('faucetpay_email');
    const assets = doc.assets as Record<string, Record<string, unknown>>;
    expect(assets.LTC!.enabled).toBe(true);
    expect(assets.LTC!.minWithdrawCoins).toBe(20); // default canônico
    expect(assets.BTC!.enabled).toBe(false); // sem entry legada ⇒ canônico
  });

  it('processor aceita saque LTC válido com config NORMALIZADA (test ⇒ SIM)', async () => {
    // Réplica: getPayoutsConfig → makePayoutsConfig(normalized) alimenta o
    // processador; aqui validamos a cadeia pura equivalente.
    const n = normalizePayoutsDoc(null);
    const ltc = n.assets.LTC!;
    expect(ltc.enabled).toBe(true);
    expect(ltc.minWithdrawCoins * 1_000_000).toBe(20_000_000);
    expect((ltc.minWithdrawCoins - ltc.feeCoins) * ltc.litoshiPerCoin).toBe(
      1800,
    );
  });
});
