/**
 * PlayHash — UPGRADE IDEMPOTENTE de config/payouts (v1/v2 ⇒ v3).
 *
 * Lógica PURA (sem Firestore) extraída do seed p/ ser unit-testável:
 *  - PAYOUTS_V1 / PAYOUTS_ASSET_V2 / PAYOUTS_V3_META / PAYOUTS_ASSET_V3:
 *    dados canônicos de cada versão;
 *  - applyPayoutsAssetV3(assets): MERGE dos campos v3 por id em QUALQUER
 *    lista de ativos (v1, v2 ou já-v3) — NUNCA remove campos anteriores;
 *  - buildPayoutsV3Doc(existing): monta o payload final v3 a partir de um
 *    doc existente (qualquer versão) ou de nada (doc ausente).
 * Idempotência: aplicar 2× produz exatamente o mesmo resultado.
 */

/** Config v1 (base histórica; campos numéricos legados em units). */
export const PAYOUTS_V1: Record<string, unknown> = {
  assets: [
    { id: 'BTC', network: 'Bitcoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'LTC', network: 'Litecoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'DOGE', network: 'Dogecoin', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
    { id: 'USDT', network: 'TRC20', enabled: true, minWithdrawUnits: 20_000_000, feeUnits: 2_000_000 },
  ],
  cooldownHours: 24,
  maxPerDay: 3,
  minAccountAgeHours: 24,
  requireFinishedGames: 1,
  coinPrecision: 1_000_000,
  version: 1,
};

/** Campos v2 de conversão explícita COIN→ativo por id. */
export const PAYOUTS_ASSET_V2: Record<string, Record<string, unknown>> = {
  BTC: {
    assetDecimals: 8,
    assetUnitPerCoinScaled: 25, // 1 coin = 25 sat (premissa conservadora)
    providerMinAssetUnits: 10_000, // 0.0001 BTC
    providerFeeAssetUnits: 500,
    minWithdrawUnits: 450_000_000, // 450 coins ⇒ 11_250 sat bruto
  },
  LTC: {
    assetDecimals: 8,
    assetUnitPerCoinScaled: 2_000, // 1 coin = 0.00002 LTC
    providerMinAssetUnits: 100_000, // 0.001 LTC
    providerFeeAssetUnits: 5_000,
    minWithdrawUnits: 60_000_000, // 60 coins ⇒ 120_000 litoshi bruto
  },
  DOGE: {
    assetDecimals: 8,
    assetUnitPerCoinScaled: 2_000_000, // 1 coin = 0.02 DOGE
    providerMinAssetUnits: 500_000_000, // 5 DOGE
    providerFeeAssetUnits: 50_000_000, // 0.5 DOGE
    minWithdrawUnits: 300_000_000, // 300 coins ⇒ 6 DOGE bruto
  },
  USDT: {
    assetDecimals: 6,
    assetUnitPerCoinScaled: 5_000, // 1 coin = 0.005 USDT
    providerMinAssetUnits: 5_000_000, // 5 USDT (TRC20)
    providerFeeAssetUnits: 1_000_000, // 1 USDT
    minWithdrawUnits: 1_300_000_000, // 1300 coins ⇒ 6.5 USDT bruto
  },
};

/** Metadados v3 do doc (destino = e-mail FaucetPay). */
export const PAYOUTS_V3_META: Record<string, unknown> = {
  destinationType: 'faucetpay_email',
  futureRateSource: 'usd_auto', // documental — sem feed implementado
};

/**
 * Campos v3 por ativo — LTC único habilitado com conversão FIXA
 * (litoshiPerCoin = 100 ⇒ 1 COIN = 0,000001 LTC); demais desabilitados.
 * providerMinLitoshi = null até o probe payoutProbe confirmar o mínimo real.
 */
export const PAYOUTS_ASSET_V3: Record<string, Record<string, unknown>> = {
  LTC: {
    network: 'FaucetPayEmail',
    enabled: true,
    rateSource: 'fixed',
    litoshiPerCoin: 100,
    displayRate: '1 COIN = 0,000001 LTC',
    minWithdrawCoins: 20,
    feeCoins: 2,
    providerMinLitoshi: null, // preencher via payoutProbe (mínimo real)
    // Compat numérica (units de coin; 1 coin = 1e6 units):
    minWithdrawUnits: 20_000_000, // 20 coins
    feeUnits: 2_000_000, // 2 coins
    assetDecimals: 8,
    assetUnitPerCoinScaled: 100, // 1 coin = 100 litoshi (mesma taxa fixa)
    providerMinAssetUnits: 0, // v3 usa providerMinLitoshi
    providerFeeAssetUnits: 0, // v3 desconta feeCoins ANTES da conversão
  },
  BTC: { enabled: false, note: 'conversão em definição' },
  DOGE: { enabled: false, note: 'conversão em definição' },
  USDT: { enabled: false, note: 'conversão em definição' },
};

/**
 * MERGE dos campos v3 em cada ativo (por id). Preserva TODOS os campos
 * v1/v2 existentes (spread primeiro, v3 depois) e não altera ativos sem
 * entry v3. Função PURA — nunca muta a entrada.
 */
export function applyPayoutsAssetV3(
  assets: Record<string, unknown>[],
): Record<string, unknown>[] {
  return assets.map((a) => ({
    ...a,
    ...(typeof a.id === 'string' ? PAYOUTS_ASSET_V3[a.id] : undefined),
  }));
}

/**
 * Payload FINAL v3 a partir de QUALQUER estado anterior:
 *  - existing == null (doc ausente) ⇒ base v1 + v2 + v3, version=3;
 *  - doc v1/v2 existente ⇒ ativos existentes com MERGE v3 + metadados +
 *    version=3 (nunca remove campos; merge no doc é responsabilidade do
 *    chamador via set(..., {merge:true})).
 */
export function buildPayoutsV3Doc(
  existing: Record<string, unknown> | null,
): Record<string, unknown> {
  if (!existing) {
    const v1Assets = PAYOUTS_V1.assets as Record<string, unknown>[];
    const withV2 = v1Assets.map((a) => ({
      ...a,
      ...(typeof a.id === 'string' ? PAYOUTS_ASSET_V2[a.id] : undefined),
    }));
    return {
      ...PAYOUTS_V1,
      ...PAYOUTS_V3_META,
      assets: applyPayoutsAssetV3(withV2),
      version: 3,
    };
  }
  const existingAssets = Array.isArray(existing.assets)
    ? (existing.assets as Record<string, unknown>[])
    : (PAYOUTS_V1.assets as Record<string, unknown>[]);
  return {
    ...PAYOUTS_V3_META,
    assets: applyPayoutsAssetV3(existingAssets),
    version: 3,
  };
}
