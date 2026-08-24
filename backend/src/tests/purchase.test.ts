/**
 * Testes de compra de máquinas (pura, sem Firestore).
 * Cobre saldo insuficiente, preço inválido, compra válida e as regras de
 * idempotência por clientRequestId.
 */
import { validatePurchase } from '../processors/processPurchaseIntents';
import { computeTotalPower, isGrantActive } from '../core/power';
import { GrantRecord } from '../core/types';

describe('validatePurchase', () => {
  it('compra válida quando saldo >= preço', () => {
    expect(validatePurchase(10_000_000n, 10_000_000n)).toEqual({ ok: true });
    expect(validatePurchase(20_000_000n, 10_000_000n)).toEqual({ ok: true });
  });

  it('saldo insuficiente', () => {
    expect(validatePurchase(9_999_999n, 10_000_000n)).toEqual({
      ok: false,
      failureCode: 'INSUFFICIENT_BALANCE',
    });
    expect(validatePurchase(0n, 1n)).toEqual({
      ok: false,
      failureCode: 'INSUFFICIENT_BALANCE',
    });
  });

  it('preço inválido (zero/negativo)', () => {
    expect(validatePurchase(100n, 0n)).toEqual({ ok: false, failureCode: 'INVALID_PRICE' });
    expect(validatePurchase(100n, -5n)).toEqual({ ok: false, failureCode: 'INVALID_PRICE' });
  });
});

describe('idempotência de compra (clientRequestId)', () => {
  /**
   * Réplica PURA da decisão do processador — mesma semântica de
   * handleIntent: dedupe por clientRequestId antes da transação.
   */
  function decideIntentAction(input: {
    status: string;
    duplicateDoneExists: boolean;
  }): 'process' | 'mark-duplicate' | 'skip' {
    if (input.status !== 'pending') return 'skip'; // transação re-checa pending
    if (input.duplicateDoneExists) return 'mark-duplicate';
    return 'process';
  }

  it('intent pendente sem duplicata é processada', () => {
    expect(decideIntentAction({ status: 'pending', duplicateDoneExists: false })).toBe('process');
  });

  it('intent pendente COM duplicata done é marcada como duplicata', () => {
    expect(decideIntentAction({ status: 'pending', duplicateDoneExists: true })).toBe(
      'mark-duplicate',
    );
  });

  it('intent já resolvida é ignorada (idempotência na re-execução)', () => {
    expect(decideIntentAction({ status: 'done', duplicateDoneExists: true })).toBe('skip');
    expect(decideIntentAction({ status: 'failed', duplicateDoneExists: false })).toBe('skip');
  });
});

describe('power permanente vs temporário (24h)', () => {
  const NOW = 1_700_000_000_000;

  function grant(powerAmount: bigint, expiresAtMs: number, expired = false): GrantRecord {
    return {
      grantId: `g-${expiresAtMs}-${expired}`,
      uid: 'u1',
      powerAmount,
      source: 'game',
      acquiredAtMs: NOW - 1_000,
      expiresAtMs,
      economicRuleVersion: 1,
      expired,
    };
  }

  it('totalPower = permanentPower + Σ grants não expirados (tempo do servidor)', () => {
    const active = grant(300n, NOW + 60_000);
    const expiredTime = grant(300n, NOW - 1); // expirado por tempo
    const expiredFlag = grant(300n, NOW + 60_000, true); // marcado expired

    expect(isGrantActive(active, NOW)).toBe(true);
    expect(isGrantActive(expiredTime, NOW)).toBe(false);
    expect(isGrantActive(expiredFlag, NOW)).toBe(false);

    expect(computeTotalPower(1_000n, [active, expiredTime, expiredFlag], NOW)).toBe(1_300n);
  });

  it('grant ativo agora expira exatamente após 24h', () => {
    const acquiredAt = NOW;
    const expiresAt = acquiredAt + 86_400_000;
    const g = grant(100n, expiresAt);
    expect(isGrantActive(g, expiresAt - 1)).toBe(true);
    expect(isGrantActive(g, expiresAt)).toBe(false); // borda: <= now expira
  });

  it('compra soma permanentPower e total reflete a soma', () => {
    // Antes da compra: permanent 500 + grant 200
    expect(computeTotalPower(500n, [grant(200n, NOW + 1)], NOW)).toBe(700n);
    // Após comprar máquina de 3.000: permanent 3.500 (+ grant ainda ativo)
    expect(computeTotalPower(3_500n, [grant(200n, NOW + 1)], NOW)).toBe(3_700n);
    // 24h depois (grant expirado): só o permanente
    expect(computeTotalPower(3_500n, [grant(200n, NOW + 1)], NOW + 86_400_001)).toBe(3_500n);
  });
});
