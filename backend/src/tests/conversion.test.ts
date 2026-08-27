/**
 * Testes de CONVERSÃO COIN→ativo (config/payouts v2/v3) — puros, sem Firestore.
 * Cobre: coinToAsset/coinsToLitoshi (aritmética inteira determinística),
 * convertCoinToAsset (v2), convertCoinsToLitoshi + validateProviderLitoshiMinimum
 * (v3 e-mail FaucetPay), validateProviderMinimum e o probe read-only.
 */
import { coinToAsset, coinsToLitoshi } from '../core/precision';
import {
  convertCoinToAsset,
  convertCoinsToLitoshi,
  validateProviderLitoshiMinimum,
  validateProviderMinimum,
  PayoutAssetConfig,
} from '../processors/processWithdrawals';
import {
  decimalToUnits,
  mapEmailSendError,
  unitsToDecimalString,
} from '../providers/faucetpay_provider';
import { runPayoutProbe } from '../runner';

/** Réplica EXATA dos valores seedados em config/payouts v2. */
const BTC: PayoutAssetConfig = {
  id: 'BTC',
  network: 'Bitcoin',
  enabled: true,
  minWithdrawUnits: 450_000_000n,
  feeUnits: 2_000_000n,
  assetDecimals: 8,
  assetUnitPerCoinScaled: 25n, // 1 coin = 25 sat
  providerMinAssetUnits: 10_000n, // 0.0001 BTC
  providerFeeAssetUnits: 500n,
  litoshiPerCoin: 0n,
  providerMinLitoshi: null,
};

const DOGE: PayoutAssetConfig = {
  id: 'DOGE',
  network: 'Dogecoin',
  enabled: true,
  minWithdrawUnits: 300_000_000n,
  feeUnits: 2_000_000n,
  assetDecimals: 8,
  assetUnitPerCoinScaled: 2_000_000n, // 1 coin = 0.02 DOGE
  providerMinAssetUnits: 500_000_000n, // 5 DOGE
  providerFeeAssetUnits: 50_000_000n, // 0.5 DOGE
  litoshiPerCoin: 0n,
  providerMinLitoshi: null,
};

/**
 * Réplica EXATA do LTC seedado em config/payouts v3:
 * destino = e-mail FaucetPay; conversão FIXA 1 COIN = 100 litoshi
 * (= 0,000001 LTC); mínimo 50 coins; taxa 25 coins; providerMinLitoshi null
 * até o probe confirmar o mínimo real do envio interno.
 */
const LTC_V3: PayoutAssetConfig = {
  id: 'LTC',
  network: 'FaucetPayEmail',
  enabled: true,
  minWithdrawUnits: 50_000_000n, // 50 coins
  feeUnits: 25_000_000n, // 25 coins
  assetDecimals: 8,
  assetUnitPerCoinScaled: 100n,
  providerMinAssetUnits: 0n,
  providerFeeAssetUnits: 0n,
  rateSource: 'fixed',
  litoshiPerCoin: 100n,
  providerMinLitoshi: null,
  displayRate: '1 COIN = 0,000001 LTC',
};

describe('coinToAsset (precision)', () => {
  it('conversão exata quando a divisão é exata', () => {
    expect(coinToAsset(300_000_000n, 2_000_000n, 1_000_000)).toBe(600_000_000n); // 6 DOGE
    expect(coinToAsset(450_000_000n, 25n, 1_000_000)).toBe(11_250n); // sat
  });

  it('arredondamento DETERMINÍSTICO para baixo (floor)', () => {
    // 1 coin = 25 sat ⇒ 1 unit de coin = 0.000025 sat ⇒ floor = 0
    expect(coinToAsset(1n, 25n, 1_000_000)).toBe(0n);
    // 399_999 units de coin × 25 / 1e6 = 9.999975 sat ⇒ 9
    expect(coinToAsset(399_999n, 25n, 1_000_000)).toBe(9n);
  });

  it('NUNCA cria valor: resultado ≤ conversão matemática exata', () => {
    for (const coins of [1n, 7n, 123_456n, 999_999n]) {
      const out = coinToAsset(coins * 1_000_000n, 25n, 1_000_000);
      expect(out).toBeLessThanOrEqual((coins * 1_000_000n * 25n) / 1_000_000n);
      // E nunca supera o bruto em units de coin escalado:
      expect(out * 1_000_000n).toBeLessThanOrEqual(coins * 1_000_000n * 25n);
    }
  });

  it('rejeita entradas inválidas (falha segura, sem inventar valor)', () => {
    expect(() => coinToAsset(-1n, 25n, 1_000_000)).toThrow('NEGATIVE_COIN_AMOUNT');
    expect(() => coinToAsset(100n, 0n, 1_000_000)).toThrow('INVALID_ASSET_RATE');
    expect(() => coinToAsset(100n, 25n, 0)).toThrow('INVALID_COIN_PRECISION');
  });
});

describe('convertCoinToAsset (helper único do processador)', () => {
  it('receivedAsset = gross − providerFee (DOGE)', () => {
    const conv = convertCoinToAsset(300_000_000n, DOGE)!;
    expect(conv.grossAssetUnits).toBe(600_000_000n); // 6 DOGE
    expect(conv.receivedAssetUnits).toBe(550_000_000n); // 5.5 DOGE
  });

  it('received nunca fica negativo (clamp em 0)', () => {
    const tiny: PayoutAssetConfig = { ...DOGE, providerFeeAssetUnits: 10n ** 18n };
    const conv = convertCoinToAsset(1_000_000n, tiny)!;
    expect(conv.receivedAssetUnits).toBe(0n);
  });

  it('ativo sem conversão configurada (v1 legado) ⇒ null (não inventa)', () => {
    const legacy: PayoutAssetConfig = { ...BTC, assetUnitPerCoinScaled: 0n };
    expect(convertCoinToAsset(1n, legacy)).toBeNull();
  });

  it('determinismo: mesma entrada ⇒ mesma saída (BigInt puro, sem float)', () => {
    const a = convertCoinToAsset(137_000_000n, BTC)!;
    const b = convertCoinToAsset(137_000_000n, BTC)!;
    expect(a.grossAssetUnits).toBe(b.grossAssetUnits);
    expect(a.grossAssetUnits).toBe(3_425n); // 137 coins × 25 sat
  });
});

describe('validateProviderMinimum (mínimo/taxa reais da FaucetPay)', () => {
  it('bruto ≥ providerMin + providerFee passa', () => {
    const conv = convertCoinToAsset(DOGE.minWithdrawUnits, DOGE)!; // 6 DOGE ≥ 5.5
    expect(validateProviderMinimum(conv, DOGE)).toEqual({ ok: true });
  });

  it('abaixo do necessário ⇒ BELOW_MIN (canônico 12.9)', () => {
    const conv = convertCoinToAsset(200_000_000n, DOGE)!; // 4 DOGE < 5.5
    expect(validateProviderMinimum(conv, DOGE)).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
  });

  it('limite exato (gross == min + fee) passa', () => {
    const conv = convertCoinToAsset(275_000_000n, DOGE)!; // 5.5 DOGE == 5 + 0.5
    expect(conv.grossAssetUnits).toBe(550_000_000n);
    expect(validateProviderMinimum(conv, DOGE)).toEqual({ ok: true });
  });
});

describe('coinsToLitoshi (v3 — conversão FIXA inteira)', () => {
  it('1 COIN = 100 litoshi; 58 coins = 5800 litoshi', () => {
    expect(coinsToLitoshi(1n, 100n)).toBe(100n);
    expect(coinsToLitoshi(58n, 100n)).toBe(5800n);
    expect(coinsToLitoshi(20n, 100n)).toBe(2000n);
  });

  it('NUNCA produz fração (entrada em coins inteiras, BigInt puro)', () => {
    for (let c = 0; c <= 250; c += 7) {
      const out = coinsToLitoshi(BigInt(c), 100n);
      expect(out % 1n).toBe(0n);
      expect(out).toBe(BigInt(c) * 100n);
    }
  });

  it('rejeita entradas inválidas (falha segura)', () => {
    expect(() => coinsToLitoshi(-1n, 100n)).toThrow('NEGATIVE_COIN_AMOUNT');
    expect(() => coinsToLitoshi(1n, 0n)).toThrow('INVALID_ASSET_RATE');
  });
});

describe('convertCoinsToLitoshi (helper único v3 do processador)', () => {
  it('mínimo (50 coins): líquido = (50 − 25) × 100 = 2500 litoshi', () => {
    const conv = convertCoinsToLitoshi(LTC_V3.minWithdrawUnits, LTC_V3)!;
    expect(conv.amountCoins).toBe(50n);
    expect(conv.feeCoins).toBe(25n);
    expect(conv.receivedLitoshi).toBe(2500n); // 0,000025 LTC
  });

  it('58 coins ⇒ recebe 3300 litoshi (0,000033 LTC)', () => {
    const conv = convertCoinsToLitoshi(58_000_000n, LTC_V3)!;
    expect(conv.receivedLitoshi).toBe(3300n);
  });

  it('valor abaixo da taxa ⇒ 0 litoshi (nunca negativo)', () => {
    const conv = convertCoinsToLitoshi(1_000_000n, LTC_V3)!; // 1 coin < fee 25
    expect(conv.receivedLitoshi).toBe(0n);
  });

  it('ativo sem litoshiPerCoin configurado ⇒ null (não inventa)', () => {
    expect(convertCoinsToLitoshi(1n, BTC)).toBeNull();
  });

  it('validateProviderLitoshiMinimum: null ⇒ passa; real > recebido ⇒ BELOW_MIN', () => {
    const conv = convertCoinsToLitoshi(50_000_000n, LTC_V3)!;
    expect(validateProviderLitoshiMinimum(conv, LTC_V3)).toEqual({ ok: true });
    const withMin: PayoutAssetConfig = { ...LTC_V3, providerMinLitoshi: 5000n };
    expect(validateProviderLitoshiMinimum(conv, withMin)).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
    const okMin: PayoutAssetConfig = { ...LTC_V3, providerMinLitoshi: 2500n };
    expect(validateProviderLitoshiMinimum(conv, okMin)).toEqual({ ok: true });
  });
});

describe('unitsToDecimalString / mapEmailSendError (envio interno por e-mail)', () => {
  it('litoshi → decimal exato sem float', () => {
    expect(unitsToDecimalString(100n)).toBe('0.000001');
    expect(unitsToDecimalString(5800n)).toBe('0.000058');
    expect(unitsToDecimalString(0n)).toBe('0');
    expect(unitsToDecimalString(200_000_000n)).toBe('2');
  });

  it('erros da API mapeados para códigos TIPADOS seguros', () => {
    expect(mapEmailSendError('Invalid or missing username/email')).toBe('EMAIL_NOT_FOUND');
    expect(mapEmailSendError('USER_NOT_FOUND')).toBe('EMAIL_NOT_FOUND');
    expect(mapEmailSendError('Amount too low')).toBe('BELOW_MIN');
    expect(mapEmailSendError('Insufficient balance')).toBe('INSUFFICIENT_PROVIDER_BALANCE');
    expect(mapEmailSendError('Rate limit exceeded')).toBe('RATE_LIMIT');
    expect(mapEmailSendError('whatever else')).toBe('API_ERROR');
  });
});

describe('decimalToUnits (resposta do provedor → BigInt)', () => {
  it('converte decimal string sem float', () => {
    expect(decimalToUnits('0.00012345')).toBe(12_345n);
    expect(decimalToUnits('2')).toBe(200_000_000n); // 2 BTC = 200M sat
    expect(decimalToUnits('0.5', 6)).toBe(500_000n);
  });

  it('entrada inesperada ⇒ null (nunca inventa saldo)', () => {
    expect(decimalToUnits('abc')).toBeNull();
    expect(decimalToUnits('')).toBeNull();
    expect(decimalToUnits('-1.5')).toBeNull();
  });
});

describe('payoutProbe (read-only; NUNCA envia payout)', () => {
  afterEach(() => {
    delete process.env.FAUCETPAY_API_KEY;
    jest.restoreAllMocks();
  });

  function fakeFetch(urls: string[], responses: unknown[]) {
    return jest.fn(async (input: Parameters<typeof fetch>[0]) => {
      urls.push(String(input));
      return new Response(JSON.stringify(responses[urls.length - 1]), { status: 200 });
    }) as unknown as typeof fetch;
  }

  /**
   * Stub mínimo de Firestore p/ getPayoutsConfig — JÁ em v4 canônico
   * (assets como MAPA keyed por id) ⇒ auto-heal NÃO dispara.
   */
  function fakeDb(assets: unknown[]) {
    const map: Record<string, unknown> = {};
    for (const a of assets as Record<string, unknown>[]) {
      map[String(a.id)] = { ...a };
    }
    const doc = { assets: map, version: 4 };
    const snap = {
      exists: true,
      data: () => doc,
      get: (field: string) =>
        field === 'assets' ? map : field === 'version' ? 4 : undefined,
    };
    return {
      doc: () => ({
        get: async () => snap,
        set: async () => undefined,
      }),
    } as never;
  }

  // LTC/USDT presentes e DESABILITADOS (a normalização v4 garante completude
  // canônica; sem entry explícita o default de LTC seria habilitado).
  const CONFIG_ASSETS = [
    { id: 'BTC', network: 'Bitcoin', enabled: true, assetDecimals: 8 },
    { id: 'DOGE', network: 'Dogecoin', enabled: true, assetDecimals: 8 },
    { id: 'LTC', network: 'FaucetPayEmail', enabled: false },
    { id: 'USDT', network: 'TRC20', enabled: false },
  ];

  it('fora de ENV=dev é no-op e não chama NENHUM endpoint', async () => {
    const fetchMock = fakeFetch([], []);
    global.fetch = fetchMock as typeof fetch;
    const result = await runPayoutProbe(fakeDb([]), { env: 'prod' });
    expect(result.executed).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('chama SOMENTE endpoints balance/fees (1 por ativo) — jamais o send', async () => {
    process.env.FAUCETPAY_API_KEY = 'test-key-never-log';
    const urls: string[] = [];
    global.fetch = fakeFetch(urls, [
      // Resposta POR MOEDA da FaucetPay (uma chamada por ativo habilitado).
      { success: true, currency: 'BTC', balance: '0.00010000', balance_satoshi: 10_000 },
      { success: true, currency: 'DOGE', balance: '12.5', balance_satoshi: 1_250_000_000 },
      { success: true, fees: { BTC: '0.000005' } },
    ]) as typeof fetch;

    const result = await runPayoutProbe(fakeDb(CONFIG_ASSETS), { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(true);
    expect(urls.length).toBe(3); // 2 saldos + 1 fees
    for (const u of urls) {
      expect(u).toMatch(/^https:\/\/faucetpay\.io\/api\/v1\/(balance|fees)$/);
      expect(u).not.toContain('send');
    }
  });

  it('saldo usa o campo inteiro do provedor quando presente', async () => {
    process.env.FAUCETPAY_API_KEY = 'test-key-never-log';
    global.fetch = fakeFetch([], [
      { success: true, currency: 'BTC', balance: '0.00010000', balance_satoshi: 10_000 },
      { success: true, fees: {} },
    ]) as typeof fetch;
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    await runPayoutProbe(fakeDb([CONFIG_ASSETS[0]]), { env: 'dev' });
    const balanceLine = logSpy.mock.calls
      .map((c) => String(c[0]))
      .find((l) => l.includes('payoutProbe balance asset=BTC'));
    // Saldo SEMPRE mascarado (primeiro/último dígito; '10000' ⇒ '1****0').
    expect(balanceLine).toContain('unitsMasked=1****0');
    expect(balanceLine).not.toContain('units=10000');
    logSpy.mockRestore();
  });

  it('chave inválida ⇒ erro seguro INVALID_CREDENTIALS, sem crash', async () => {
    process.env.FAUCETPAY_API_KEY = 'bad-key';
    global.fetch = jest.fn(async () =>
      new Response(JSON.stringify({ success: false, message: 'INVALID_API_KEY' }), {
        status: 200,
      }),
    ) as unknown as typeof fetch;
    const result = await runPayoutProbe(fakeDb(CONFIG_ASSETS), { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(false);
  });

  it('secret ausente ⇒ falha segura FAUCETPAY_API_KEY_MISSING', async () => {
    delete process.env.FAUCETPAY_API_KEY;
    const result = await runPayoutProbe(fakeDb(CONFIG_ASSETS), { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(false);
  });
});
