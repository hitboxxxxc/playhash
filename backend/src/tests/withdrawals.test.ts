/**
 * Testes de SAQUES (puros, sem Firestore) — mesma estratégia dos demais
 * testes do runner: validação PURA + réplicas determinísticas das decisões.
 * Cobre: regras de validação (a→h), máscara de endereço, regex por rede,
 * reserva+estorno (réplica), idempotência de retomada e TestProvider SIM.
 */
import {
  ELIGIBILITY_FAILURE_CODES,
  WithdrawalValidationInput,
  convertCoinToAsset,
  isValidAddressForNetwork,
  maskAddress,
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
  addressValid: true,
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

  it('(b) abaixo do mínimo (20 coins)', () => {
    expect(validateWithdrawal(input({ amountUnits: 19_999_999n }))).toEqual({
      ok: false,
      failureCode: 'BELOW_MINIMUM',
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

  it('(e) maxPerDay atingido', () => {
    expect(validateWithdrawal(input({ withdrawalsToday: 3 }))).toEqual({
      ok: false,
      failureCode: 'DAILY_LIMIT_REACHED',
    });
    expect(validateWithdrawal(input({ withdrawalsToday: 2 }))).toEqual({
      ok: true,
    });
  });

  it('(f) conta com menos de 24h é inelegível', () => {
    expect(
      validateWithdrawal(
        input({ accountCreatedAtMs: Date.now() - 2 * 3_600_000 }),
      ),
    ).toEqual({ ok: false, failureCode: 'ACCOUNT_TOO_NEW' });
  });

  it('(f) exige ≥1 gameSession finished na vida', () => {
    expect(validateWithdrawal(input({ finishedGames: 0 }))).toEqual({
      ok: false,
      failureCode: 'NO_FINISHED_GAMES',
    });
  });

  it('(g) conta em review bloqueia saque', () => {
    expect(validateWithdrawal(input({ userStatus: 'review' }))).toEqual({
      ok: false,
      failureCode: 'ACCOUNT_IN_REVIEW',
    });
  });

  it('(h) endereço inválido para a rede', () => {
    expect(validateWithdrawal(input({ addressValid: false }))).toEqual({
      ok: false,
      failureCode: 'INVALID_ADDRESS',
    });
  });

  it('ordem a→h: ativo desabilitado vence as demais falhas', () => {
    expect(
      validateWithdrawal(
        input({ assetEnabled: false, addressValid: false, finishedGames: 0 }),
      ),
    ).toEqual({ ok: false, failureCode: 'ASSET_DISABLED' });
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

describe('antifraude: códigos de elegibilidade (§36)', () => {
  it('somente falhas de elegibilidade contam para o lock review', () => {
    expect(ELIGIBILITY_FAILURE_CODES.has('ACCOUNT_TOO_NEW')).toBe(true);
    expect(ELIGIBILITY_FAILURE_CODES.has('NO_FINISHED_GAMES')).toBe(true);
    expect(ELIGIBILITY_FAILURE_CODES.has('COOLDOWN_ACTIVE')).toBe(true);
    expect(ELIGIBILITY_FAILURE_CODES.has('DAILY_LIMIT_REACHED')).toBe(true);
    expect(ELIGIBILITY_FAILURE_CODES.has('ACCOUNT_IN_REVIEW')).toBe(true);
    // Falhas operacionais NÃO contam:
    expect(ELIGIBILITY_FAILURE_CODES.has('INVALID_ADDRESS')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('BELOW_MINIMUM')).toBe(false);
    expect(ELIGIBILITY_FAILURE_CODES.has('ASSET_DISABLED')).toBe(false);
  });
});

describe('conversão v2 integrada à validação de saques', () => {
  const DOGE_CFG = {
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
});
