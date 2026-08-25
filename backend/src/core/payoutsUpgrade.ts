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

// ---------------------------------------------------------------------------
// SCHEMA CANÔNICO v4 (12.9) — assets como MAPA keyed por id UPPERCASE.
// Aceita QUALQUER legado (v1 array, v2/v3 array com campos antigos,
// ids em qualquer caixa) e produz a forma canônica idempotente.
// ---------------------------------------------------------------------------

/** Ativo canônico v4 (forma EXATA gravada/lida do Firestore). */
export interface PayoutAssetV4 {
  enabled: boolean;
  litoshiPerCoin: number;
  minWithdrawCoins: number;
  feeCoins: number;
  /** Mínimo REAL do provedor em litoshi; null até o probe confirmar. */
  providerMinLitoshi: number | null;
  displayRate: string;
  destinationType: 'faucetpay_email';
}

export const PAYOUTS_V4_META: Record<string, unknown> = {
  destinationType: 'faucetpay_email',
  futureRateSource: 'usd_auto', // documental — sem feed implementado
};

/**
 * Fallback CONSERVADOR do mínimo REAL do envio interno FaucetPay (12.10).
 * A API não expõe o mínimo do envio por e-mail (/fees traz só taxas de
 * carteira externa) ⇒ o probe grava 1800 litoshi = LÍQUIDO EXATO do saque
 * mínimo da plataforma (20 COIN − 2 COIN) × 100 litoshi/coin. Garantias:
 *  - desbloqueia o gate LIVE (providerMinLitoshi null ⇒ BELOW_MIN);
 *  - a plataforma nunca enviaria abaixo disso de qualquer forma (mínimo);
 *  - se o provedor rejeitar de verdade ⇒ erro tipado BELOW_MIN + estorno.
 */
export const FALLBACK_PROVIDER_MIN_LITOSHI = 1800;

/**
 * MERGE SEGURO do mínimo confirmado pelo payoutProbe (12.10): parte do doc
 * canônico v4 e GRAVA EM LTC.providerMinLitoshi SOMENTE valor MAIOR OU IGUAL
 * ao existente (nunca ABAIXA a barreira já confirmada). Idempotente: aplicar
 * 2× com o mesmo valor produz exatamente o mesmo doc. Marca a proveniência
 * em `providerMinSource` (nível doc; ignorado pelo normalizador).
 */
export function applyProbeMinimum(
  raw: Record<string, unknown> | null | undefined,
  minLitoshi: number,
): Record<string, unknown> {
  const doc = buildPayoutsV4Doc(raw);
  const assets = doc.assets as Record<string, PayoutAssetV4>;
  const ltc = assets.LTC ?? { ...PAYOUTS_ASSET_V4.LTC };
  const current =
    typeof ltc.providerMinLitoshi === 'number' ? ltc.providerMinLitoshi : null;
  const next = current === null ? minLitoshi : Math.max(current, minLitoshi);
  return {
    ...doc,
    assets: { ...assets, LTC: { ...ltc, providerMinLitoshi: next } },
    providerMinSource: 'payoutProbe',
  };
}

/** Destino canônico v4 — LTC único habilitado (taxa fixa 100 litoshi/coin). */
export const PAYOUTS_ASSET_V4: Record<string, PayoutAssetV4> = {
  LTC: {
    enabled: true,
    litoshiPerCoin: 100,
    minWithdrawCoins: 20,
    feeCoins: 2,
    providerMinLitoshi: null,
    displayRate: '1 COIN = 0,000001 LTC',
    destinationType: 'faucetpay_email',
  },
  BTC: {
    enabled: false,
    litoshiPerCoin: 0,
    minWithdrawCoins: 0,
    feeCoins: 0,
    providerMinLitoshi: null,
    displayRate: '',
    destinationType: 'faucetpay_email',
  },
  DOGE: {
    enabled: false,
    litoshiPerCoin: 0,
    minWithdrawCoins: 0,
    feeCoins: 0,
    providerMinLitoshi: null,
    displayRate: '',
    destinationType: 'faucetpay_email',
  },
  USDT: {
    enabled: false,
    litoshiPerCoin: 0,
    minWithdrawCoins: 0,
    feeCoins: 0,
    providerMinLitoshi: null,
    displayRate: '',
    destinationType: 'faucetpay_email',
  },
};

function toInt(v: unknown): number {
  const n = typeof v === 'string' ? Number(v) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

/**
 * Normalizador IDEMPOTENTE: aceita QUALQUER legado e devolve a forma v4.
 *  - assets como ARRAY (v1–v3) ou MAPA/OBJETO (v4);
 *  - ids em qualquer caixa/com espaços ⇒ UPPERCASE trim;
 *  - aliases de campo: assetUnitPerCoinScaled→litoshiPerCoin,
 *    minWithdrawUnits→minWithdrawCoins (÷1e6), feeUnits→feeCoins (÷1e6);
 *  - doc ausente/corrompido ⇒ defaults canônicos (LTC habilitado).
 */
export function normalizePayoutsDoc(
  raw: Record<string, unknown> | null | undefined,
): {
  version: number;
  cooldownHours: number;
  maxPerDay: number;
  minAccountAgeHours: number;
  requireFinishedGames: number;
  coinPrecision: number;
  assets: Record<string, PayoutAssetV4>;
} {
  const data = raw ?? {};
  const rawAssets: unknown = data.assets;
  const entries: [string, Record<string, unknown>][] = [];
  if (Array.isArray(rawAssets)) {
    for (const item of rawAssets as Record<string, unknown>[]) {
      if (item && typeof item === 'object' && typeof item.id === 'string') {
        entries.push([item.id.trim().toUpperCase(), item]);
      }
    }
  } else if (rawAssets && typeof rawAssets === 'object') {
    for (const [key, value] of Object.entries(rawAssets as Record<string, unknown>)) {
      if (value && typeof value === 'object') {
        entries.push([key.trim().toUpperCase(), value as Record<string, unknown>]);
      }
    }
  }

  const assets: Record<string, PayoutAssetV4> = {};
  for (const [id, a] of entries) {
    const canonical = PAYOUTS_ASSET_V4[id];
    const enabled = a.enabled === true;
    const litoshiPerCoin = toInt(a.litoshiPerCoin ?? a.assetUnitPerCoinScaled ?? 0);
    const minWithdrawCoins = toInt(a.minWithdrawCoins ?? Math.floor(toInt(a.minWithdrawUnits ?? 0) / 1_000_000));
    const feeCoins = toInt(a.feeCoins ?? Math.floor(toInt(a.feeUnits ?? 0) / 1_000_000));
    const rawMin = a.providerMinLitoshi;
    assets[id] = {
      enabled,
      // Ativo desabilitado sem números ⇒ herda o canônico (zeros); habilitado
      // sem conversão definida ⇒ mantém o que veio (processador recusa se 0).
      litoshiPerCoin: litoshiPerCoin || canonical?.litoshiPerCoin || 0,
      minWithdrawCoins:
        minWithdrawCoins || (enabled ? canonical?.minWithdrawCoins ?? 0 : 0),
      feeCoins: feeCoins || (enabled ? canonical?.feeCoins ?? 0 : 0),
      providerMinLitoshi:
        rawMin === null || rawMin === undefined
          ? null
          : toInt(rawMin),
      displayRate:
        typeof a.displayRate === 'string'
          ? a.displayRate
          : canonical?.displayRate ?? '',
      destinationType: 'faucetpay_email',
    };
  }
  // Garantia de COMPLETUDE canônica: todo id canônico ausente no legado é
  // adicionado com o default v4 (auto-heal; idempotente).
  for (const [id, a] of Object.entries(PAYOUTS_ASSET_V4)) {
    if (!assets[id]) assets[id] = { ...a };
  }

  return {
    version: toInt(data.version ?? 1) || 1,
    cooldownHours: toInt(data.cooldownHours ?? 24) || 24,
    maxPerDay: toInt(data.maxPerDay ?? 3) || 3,
    minAccountAgeHours: toInt(data.minAccountAgeHours ?? 24) || 24,
    requireFinishedGames: toInt(data.requireFinishedGames ?? 1),
    coinPrecision: toInt(data.coinPrecision ?? 1_000_000) || 1_000_000,
    assets,
  };
}

/**
 * Doc canônico v4 a partir de QUALQUER estado (null = doc ausente).
 * Escalares antifraude preservados do raw quando presentes.
 */
export function buildPayoutsV4Doc(
  raw: Record<string, unknown> | null | undefined,
): Record<string, unknown> {
  const n = normalizePayoutsDoc(raw);
  return {
    ...PAYOUTS_V4_META,
    cooldownHours: n.cooldownHours,
    maxPerDay: n.maxPerDay,
    minAccountAgeHours: n.minAccountAgeHours,
    requireFinishedGames: n.requireFinishedGames,
    coinPrecision: n.coinPrecision,
    assets: n.assets,
    version: 4,
  };
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
