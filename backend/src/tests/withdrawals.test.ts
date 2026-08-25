/**
 * Testes de SAQUES (puros, sem Firestore) — mesma estratégia dos demais
 * testes do runner: validação PURA + réplicas determinísticas das decisões.
 * Cobre: regras de validação (a→h), máscara de endereço, regex por rede,
 * reserva+estorno (réplica), idempotência de retomada e TestProvider SIM.
 */
import {
  ELIGIBILITY_FAILURE_CODES,
  PayoutAssetConfig,
  WithdrawalValidationInput,
  convertCoinToAsset,
  convertCoinsToLitoshi,
  isValidAddressForNetwork,
  isValidDestinationEmail,
  maskAddress,
  maskEmail,
  normalizeAssetId,
  resolvePayoutMode,
  validateProviderLitoshiMinimum,
  validateProviderMinForMode,
  validateProviderMinimum,
  validateWithdrawal,
} from '../processors/processWithdrawals';
import { getPayoutProvider } from '../processors/processWithdrawals';
import { PayoutProvider } from '../providers/payout_provider';

const BASE: WithdrawalValidationInput = {
  assetEnabled: true,
  amountUnits: 25_000_000n, // 25 coins
  minWithdrawUnits: 20_000_000n, // 20 coins
  availableBalanceUnits: 100_000_000n,
  lastNonFailedWithdrawalAtMs: null,
  cooldownHours: 24,
  withdrawalsToday: 0,
  maxPerDay: 3,
  accountCreatedAtMs: Date.now() - 48 * 3_600_000, // 48h
  minAccountAgeHours: 24,
  finishedGames: 1,
  requireFinishedGames: 1,
  userStatus: 'active',
  destinationValid: true,
};

function input(overrides: Partial<WithdrawalValidationInput>): WithdrawalValidationInput {
  return { ...BASE, ...overrides };
}

describe('validateWithdrawal (a→h)', () => {
  it('saque válido passa em todas as regras', () => {
    expect(validateWithdrawal(BASE)).toEqual({ ok: true });
  });

  it('(a) ativo desabilitado na config', () => {
    expect(validateWithdrawal(input({ assetEnabled: false }))).toEqual({
      ok: false,
      failureCode: 'ASSET_DISABLED',
    });
  });

  it('(b) abaixo do mínimo (20 coins) ⇒ BELOW_MIN (canônico 12.9)', () => {
    expect(validateWithdrawal(input({ amountUnits: 19_999_999n }))).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
    expect(validateWithdrawal(input({ amountUnits: 20_000_000n }))).toEqual({
      ok: true,
    });
  });

  it('(c) saldo disponível insuficiente', () => {
    expect(
      validateWithdrawal(input({ availableBalanceUnits: 10_000_000n })),
    ).toEqual({ ok: false, failureCode: 'INSUFFICIENT_BALANCE' });
  });

  it('(d) cooldown de 24h desde o último saque não-failed', () => {
    const now = Date.now();
    expect(
      validateWithdrawal(
        input({ lastNonFailedWithdrawalAtMs: now - 23 * 3_600_000 }),
      ),
    ).toEqual({ ok: false, failureCode: 'COOLDOWN_ACTIVE' });
    expect(
      validateWithdrawal(
        input({ lastNonFailedWithdrawalAtMs: now - 25 * 3_600_000 }),
      ),
    ).toEqual({ ok: true });
  });

  it('(e/f/g) antifraude (cota diária/idade/partidas/review) ⇒ ANTIFRAUD', () => {
    expect(validateWithdrawal(input({ withdrawalsToday: 3 }))).toEqual({
      ok: false,
      failureCode: 'ANTIFRAUD',
    });
    expect(validateWithdrawal(input({ withdrawalsToday: 2 }))).toEqual({
      ok: true,
    });
    expect(
      validateWithdrawal(
        input({ accountCreatedAtMs: Date.now() - 2 * 3_600_000 }),
      ),
    ).toEqual({ ok: false, failureCode: 'ANTIFRAUD' });
    expect(validateWithdrawal(input({ finishedGames: 0 }))).toEqual({
      ok: false,
      failureCode: 'ANTIFRAUD',
    });
    expect(validateWithdrawal(input({ userStatus: 'review' }))).toEqual({
      ok: false,
      failureCode: 'ANTIFRAUD',
    });
  });

  it('(h) destino inválido ⇒ EMAIL_INVALID (canônico 12.9)', () => {
    expect(
      validateWithdrawal(input({ destinationValid: false, destinationEmail: 'x@y' })),
    ).toEqual({ ok: false, failureCode: 'EMAIL_INVALID' });
    expect(validateWithdrawal(input({ destinationValid: false }))).toEqual({
      ok: false,
      failureCode: 'EMAIL_INVALID',
    });
  });

  it('ordem a→h: ativo desabilitado vence as demais falhas', () => {
    expect(
      validateWithdrawal(
        input({ assetEnabled: false, destinationValid: false, finishedGames: 0 }),
      ),
    ).toEqual({ ok: false, failureCode: 'ASSET_DISABLED' });
  });
});

describe('destino v3: validação e máscara de E-MAIL FaucetPay', () => {
  it('isValidDestinationEmail aceita e-mails comuns e rejeita inválidos', () => {
    expect(isValidDestinationEmail('owner@example.com')).toBe(true);
    expect(isValidDestinationEmail('joao.silva+fp@sub.dominio.io')).toBe(true);
    expect(isValidDestinationEmail('sem-arroba')).toBe(false);
    expect(isValidDestinationEmail('a@b')).toBe(false); // domínio curto demais
    expect(isValidDestinationEmail('dois @@espacos.com')).toBe(false);
    expect(isValidDestinationEmail('')).toBe(false);
    expect(isValidDestinationEmail(`a${'x'.repeat(300)}@example.com`)).toBe(false); // >254
  });

  it('maskEmail: 2 primeiros chars + ***@ + domínio (nunca expõe o completo)', () => {
    const masked = maskEmail('owner@example.com');
    expect(masked).toBe('ow***@example.com');
    expect(masked).not.toContain('owner@example.com');
    expect(maskEmail('a@example.com')).toBe('a***@example.com'); // local curto
    expect(maskEmail('invalido-sem-arroba')).not.toContain('invalido-sem-arroba');
  });

  it('e-mail inválido é bloqueado na validação (a→h) — EMAIL_INVALID', () => {
    expect(
      validateWithdrawal(input({ destinationValid: false, destinationEmail: 'quebra-regex' })),
    ).toEqual({ ok: false, failureCode: 'EMAIL_INVALID' });
  });
});

describe('conversão v3 integrada à validação de saques (e-mail FaucetPay)', () => {
  /** Réplica EXATA do LTC seedado em config/payouts v3. */
  const LTC_V3: PayoutAssetConfig = {
    id: 'LTC',
    network: 'FaucetPayEmail',
    enabled: true,
    minWithdrawUnits: 20_000_000n,
    feeUnits: 2_000_000n,
    assetDecimals: 8,
    assetUnitPerCoinScaled: 100n,
    providerMinAssetUnits: 0n,
    providerFeeAssetUnits: 0n,
    rateSource: 'fixed',
    litoshiPerCoin: 100n,
    providerMinLitoshi: null,
    displayRate: '1 COIN = 0,000001 LTC',
  };

  it('saque no mínimo passa: líquido 1800 litoshi ≥ providerMin (null)', () => {
    const conv = convertCoinsToLitoshi(LTC_V3.minWithdrawUnits, LTC_V3)!;
    expect(conv.receivedLitoshi).toBe(1800n);
    expect(validateProviderLitoshiMinimum(conv, LTC_V3)).toEqual({ ok: true });
  });

  it('providerMin real acima do líquido ⇒ BELOW_MIN (canônico 12.9)', () => {
    const conv = convertCoinsToLitoshi(20_000_000n, LTC_V3)!;
    const cfg: PayoutAssetConfig = { ...LTC_V3, providerMinLitoshi: 10_000n };
    expect(validateProviderLitoshiMinimum(conv, cfg)).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
  });

  it('estorno íntegro em COIN mesmo com conversão v3 (aritmética BigInt)', () => {
    const amount = 30_000_000n;
    let available = 100_000_000n;
    let pending = 0n;
    available -= amount;
    pending += amount;
    // provider failed ⇒ estorno EXATO em COIN (nunca em litoshi)
    available += amount;
    pending -= amount;
    expect(available).toBe(100_000_000n);
    expect(pending).toBe(0n);
  });
});

describe('endereços: máscara e regex por rede', () => {
  it('maskAddress nunca expõe o endereço completo', () => {
    const full = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080';
    const masked = maskAddress(full);
    expect(masked).not.toBe(full);
    expect(masked).toContain('…');
    expect(masked.length).toBeLessThan(full.length);
    // Endereço curto => totalmente mascarado.
    expect(maskAddress('short')).toBe('*****');
  });

  it('Bitcoin: legacy, bech32 e inválido', () => {
    expect(isValidAddressForNetwork('Bitcoin', '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')).toBe(true);
    expect(isValidAddressForNetwork('Bitcoin', 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080')).toBe(true);
    expect(isValidAddressForNetwork('Bitcoin', 'D8vFzY7xQ1mZ9kP2L4nR6tU8wXyZ0aB3cDe')).toBe(false);
  });

  it('Litecoin: ltc1/M/L e inválido', () => {
    expect(isValidAddressForNetwork('Litecoin', 'ltc1qdp3p2rezaw3u2c8pq7z9kr5zk2mcqsxyv9qzxe')).toBe(true);
    expect(isValidAddressForNetwork('Litecoin', 'M8vFzY7xQ1mZ9kP2L4nR6tU8wXyZaB3cd')).toBe(true);
    expect(isValidAddressForNetwork('Litecoin', 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080')).toBe(false);
  });

  it('Dogecoin: D… e inválido', () => {
    expect(isValidAddressForNetwork('Dogecoin', 'DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L')).toBe(true);
    expect(isValidAddressForNetwork('Dogecoin', 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080')).toBe(false);
  });

  it('TRC20: T + base58 33 chars e inválido', () => {
    expect(isValidAddressForNetwork('TRC20', 'TXYZsYbSfpBCBZ6CbwPpkbvQyzEB9XcuK8')).toBe(true);
    expect(isValidAddressForNetwork('TRC20', '0xd91714bd4921b35995d213a4492eede14b8b3e8d')).toBe(false);
  });

  it('rede desconhecida ⇒ sempre inválida', () => {
    expect(isValidAddressForNetwork('Solana', 'qualquer-coisa-longa-aqui-123456')).toBe(false);
  });
});

describe('idempotência de retomada (réplica da decisão)', () => {
  function decide(existingStatus: string | null): string {
    if (existingStatus === null) return 'reserve-and-pay';
    if (existingStatus === 'completed') return 'mark-done-no-repay';
    if (existingStatus === 'processing') return 'resume-payout-only';
    return 'fail-already-processed';
  }

  it('sem withdrawal existente ⇒ reserva + payout', () => {
    expect(decide(null)).toBe('reserve-and-pay');
  });

  it('withdrawal completed ⇒ NUNCA repaga', () => {
    expect(decide('completed')).toBe('mark-done-no-repay');
  });

  it('withdrawal processing (crash pós-reserva) ⇒ retoma SEM duplicar', () => {
    expect(decide('processing')).toBe('resume-payout-only');
  });

  it('withdrawal failed anterior ⇒ não refaz', () => {
    expect(decide('failed')).toBe('fail-already-processed');
  });
});

describe('reserva + estorno (réplica aritmética BigInt)', () => {
  const amount = 30_000_000n; // 30 coins
  const fee = 2_000_000n;

  it('reserva: available −= amount; pending += amount; received = amount − fee', () => {
    let available = 100_000_000n;
    let pending = 0n;
    available -= amount;
    pending += amount;
    expect(available).toBe(70_000_000n);
    expect(pending).toBe(30_000_000n);
    expect(amount - fee).toBe(28_000_000n); // receivedUnits
  });

  it('estorno restaura EXATAMENTE o saldo anterior', () => {
    let available = 70_000_000n;
    let pending = 30_000_000n;
    // provider failed ⇒ REVERSAL
    available += amount;
    pending -= amount;
    expect(available).toBe(100_000_000n);
    expect(pending).toBe(0n);
  });

  it('completed: pending sai da carteira; saldo total cai só do valor bruto', () => {
    let available = 100_000_000n;
    let pending = 0n;
    available -= amount;
    pending += amount;
    pending -= amount; // WITHDRAWAL_COMPLETED
    expect(available).toBe(70_000_000n);
    expect(pending).toBe(0n);
  });
});

describe('TestProvider (PAYOUT_MODE=test)', () => {
  it('getPayoutProvider padrão/dev usa TestProvider', () => {
    delete process.env.PAYOUT_MODE;
    expect(getPayoutProvider().id).toBe('test');
    expect(getPayoutProvider('test').id).toBe('test');
  });

  it('SIM: sempre completed com providerReference SIM-<uuid> e flag payoutSimulated', async () => {
    delete process.env.PAYOUT_MODE;
    const provider: PayoutProvider = getPayoutProvider();
    const result = await provider.sendPayout({
      asset: 'BTC',
      network: 'Bitcoin',
      address: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
      amountUnits: 25_000_000n,
    });
    expect(result.status).toBe('completed');
    expect(result.providerReference?.startsWith('SIM-')).toBe(true);
    expect(result.payoutSimulated).toBe(true);
  });

  it('duas chamadas geram referências distintas (uuid)', async () => {
    delete process.env.PAYOUT_MODE;
    const provider = getPayoutProvider();
    const a = await provider.sendPayout({
      asset: 'DOGE',
      network: 'Dogecoin',
      address: 'DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L',
      amountUnits: 20_000_000n,
    });
    const b = await provider.sendPayout({
      asset: 'DOGE',
      network: 'Dogecoin',
      address: 'DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L',
      amountUnits: 20_000_000n,
    });
    expect(a.providerReference).not.toBe(b.providerReference);
  });
});

describe('antifraude: códigos de elegibilidade (§36, canônico 12.9)', () => {
  it('ANTIFRAUD e COOLDOWN_ACTIVE contam para o lock review', () => {
    expect(ELIGIBILITY_FAILURE_CODES.has('ANTIFRAUD')).toBe(true);
    expect(ELIGIBILITY_FAILURE_CODES.has('COOLDOWN_ACTIVE')).toBe(true);
    // Falhas operacionais NÃO contam:
    expect(ELIGIBILITY_FAILURE_CODES.has('EMAIL_INVALID')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('BELOW_MIN')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('ASSET_DISABLED')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('INSUFFICIENT_BALANCE')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('PROVIDER_ERROR')).toBe(false);
  });
});

describe('CORREÇÃO 12.8: normalização de ids + gate de modo + fluxo LTC v3', () => {
  /** Réplica EXATA do LTC seedado em config/payouts v3. */
  const LTC_V3: PayoutAssetConfig = {
    id: 'LTC',
    network: 'FaucetPayEmail',
    enabled: true,
    minWithdrawUnits: 20_000_000n,
    feeUnits: 2_000_000n,
    assetDecimals: 8,
    assetUnitPerCoinScaled: 100n,
    providerMinAssetUnits: 0n,
    providerFeeAssetUnits: 0n,
    rateSource: 'fixed',
    litoshiPerCoin: 100n,
    providerMinLitoshi: null,
    displayRate: '1 COIN = 0,000001 LTC',
  };

  it('normalizeAssetId: caixa/espaços normalizados p/ lookup da config', () => {
    expect(normalizeAssetId('ltc')).toBe('LTC');
    expect(normalizeAssetId(' Ltc ')).toBe('LTC');
    expect(normalizeAssetId('LTC')).toBe('LTC');
    expect(normalizeAssetId('')).toBe('');
  });

  it('resolvePayoutMode: default/test ⇒ test; live ⇒ live', () => {
    delete process.env.PAYOUT_MODE;
    expect(resolvePayoutMode()).toBe('test');
    expect(resolvePayoutMode('test')).toBe('test');
    expect(resolvePayoutMode('LIVE')).toBe('live');
    expect(resolvePayoutMode('lixo')).toBe('test'); // inválido ⇒ seguro
  });

  it('providerMinLitoshi null em TEST ⇒ passa (default seguro documentado)', () => {
    expect(validateProviderMinForMode('test', LTC_V3)).toEqual({ ok: true });
  });

  it('providerMinLitoshi null em LIVE ⇒ BELOW_MIN até o probe', () => {
    expect(validateProviderMinForMode('live', LTC_V3)).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
    // Com mínimo real confirmado, live valida normalmente:
    const cfg: PayoutAssetConfig = { ...LTC_V3, providerMinLitoshi: 1000n };
    expect(validateProviderMinForMode('live', cfg)).toEqual({ ok: true });
  });

  it('fluxo ponta-a-ponta (réplica): saque LTC válido, test mode ⇒ SIM completed', async () => {
    delete process.env.PAYOUT_MODE;
    // 1) intent com id em caixa baixa é aceito após normalização:
    const assetCfg =
      [LTC_V3].find((a) => a.id === normalizeAssetId('ltc')) ?? null;
    expect(assetCfg).not.toBeNull();
    // 2) validação econômica (a→h) passa no mínimo (20 coins):
    const validation = validateWithdrawal({
      ...BASE,
      amountUnits: 20_000_000n,
      minWithdrawUnits: assetCfg!.minWithdrawUnits,
      destinationEmail: 'owner@example.com',
    });
    expect(validation).toEqual({ ok: true });
    // 3) conversão v3 inteira: (20 − 2) × 100 = 1800 litoshi:
    const conv = convertCoinsToLitoshi(20_000_000n, assetCfg!)!;
    expect(conv.amountCoins).toBe(20n);
    expect(conv.feeCoins).toBe(2n);
    expect(conv.receivedLitoshi).toBe(1800n);
    // 4) gate do modo (test, null) passa e o TestProvider paga SIM:
    expect(validateProviderMinForMode('test', assetCfg!)).toEqual({ ok: true });
    const result = await getPayoutProvider().sendPayout({
      asset: 'LTC',
      network: 'FaucetPayEmail',
      address: '',
      destinationEmail: 'owner@example.com',
      amountUnits: conv.receivedLitoshi,
    });
    expect(result.status).toBe('completed');
    expect(result.payoutSimulated).toBe(true);
    expect(result.providerReference?.startsWith('SIM-')).toBe(true);
  });

  it('recusas seguras permanecem: mínimo/saldo/cooldown não mudaram', () => {
    expect(
      validateWithdrawal({ ...BASE, amountUnits: 19_999_999n }),
    ).toEqual({ ok: false, failureCode: 'BELOW_MIN' });
    expect(
      validateWithdrawal({ ...BASE, availableBalanceUnits: 1n }),
    ).toEqual({ ok: false, failureCode: 'INSUFFICIENT_BALANCE' });
    expect(
      validateWithdrawal({
        ...BASE,
        lastNonFailedWithdrawalAtMs: Date.now() - 3_600_000,
      }),
    ).toEqual({ ok: false, failureCode: 'COOLDOWN_ACTIVE' });
  });
});

describe('conversão v2 integrada à validação de saques', () => {
  const DOGE_CFG: PayoutAssetConfig = {
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

  it('BELOW_PROVIDER_MIN é código operacional: NÃO conta p/ lock review', () => {
    expect(ELIGIBILITY_FAILURE_CODES.has('BELOW_PROVIDER_MIN')).toBe(false);
  });

  it('saque no mínimo da plataforma passa na validação do provedor', () => {
    const conv = convertCoinToAsset(DOGE_CFG.minWithdrawUnits, DOGE_CFG)!;
    expect(validateProviderMinimum(conv, DOGE_CFG)).toEqual({ ok: true });
    // Estorno íntegro: nada foi debitado quando a validação falha ANTES da reserva.
    expect(conv.grossAssetUnits).toBe(600_000_000n);
    expect(conv.receivedAssetUnits).toBe(550_000_000n);
  });

  it('BELOW_PROVIDER_MIN virou BELOW_MIN no esquema canônico (12.9)', () => {
    const conv = convertCoinToAsset(DOGE_CFG.minWithdrawUnits / 2n, DOGE_CFG)!;
    expect(validateProviderMinimum(conv, DOGE_CFG)).toEqual({
      ok: false,
      failureCode: 'BELOW_MIN',
    });
  });
});
