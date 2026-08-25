/**
 * Testes de CONVERSÃO COIN→ativo (config/payouts v2) — puros, sem Firestore.
 * Cobre: coinToAsset (arredondamento determinístico, nunca cria valor),
 * convertCoinToAsset (helper ÚNICO do processador), validateProviderMinimum
 * (mínimo real + taxa do provedor) e o probe read-only (NUNCA envia payout).
 */
import { coinToAsset } from '../core/precision';
import {
  convertCoinToAsset,
  validateProviderMinimum,
  PayoutAssetConfig,
} from '../processors/processWithdrawals';
import { decimalToUnits } from '../providers/faucetpay_provider';
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

  it('abaixo do necessário ⇒ BELOW_PROVIDER_MIN (código seguro)', () => {
    const conv = convertCoinToAsset(200_000_000n, DOGE)!; // 4 DOGE < 5.5
    expect(validateProviderMinimum(conv, DOGE)).toEqual({
      ok: false,
      failureCode: 'BELOW_PROVIDER_MIN',
    });
  });

  it('limite exato (gross == min + fee) passa', () => {
    const conv = convertCoinToAsset(275_000_000n, DOGE)!; // 5.5 DOGE == 5 + 0.5
    expect(conv.grossAssetUnits).toBe(550_000_000n);
    expect(validateProviderMinimum(conv, DOGE)).toEqual({ ok: true });
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

  it('fora de ENV=dev é no-op e não chama NENHUM endpoint', async () => {
    const fetchMock = fakeFetch([], []);
    global.fetch = fetchMock as typeof fetch;
    const result = await runPayoutProbe({} as never, { env: 'prod' });
    expect(result.executed).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('chama SOMENTE endpoints balance/fees — jamais o send', async () => {
    process.env.FAUCETPAY_API_KEY = 'test-key-never-log';
    const urls: string[] = [];
    global.fetch = fakeFetch(urls, [
      { success: true, balances: { BTC: '0.0001', DOGE: '12.5' } },
      { success: true, fees: { BTC: '0.000005' } },
    ]) as typeof fetch;

    const result = await runPayoutProbe({} as never, { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(true);
    expect(urls.length).toBe(2);
    for (const u of urls) {
      expect(u).toMatch(/^https:\/\/faucetpay\.io\/api\/v1\/(balance|fees)$/);
      expect(u).not.toContain('send');
    }
  });

  it('chave inválida ⇒ erro seguro INVALID_CREDENTIALS, sem crash', async () => {
    process.env.FAUCETPAY_API_KEY = 'bad-key';
    global.fetch = jest.fn(async () =>
      new Response(JSON.stringify({ success: false, message: 'INVALID_API_KEY' }), {
        status: 200,
      }),
    ) as unknown as typeof fetch;
    const result = await runPayoutProbe({} as never, { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(false);
  });

  it('secret ausente ⇒ falha segura FAUCETPAY_API_KEY_MISSING', async () => {
    delete process.env.FAUCETPAY_API_KEY;
    const result = await runPayoutProbe({} as never, { env: 'dev' });
    expect(result.executed).toBe(true);
    expect(result.keyValid).toBe(false);
  });
});
