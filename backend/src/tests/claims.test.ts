/**
 * Testes da validação de CLAIMS (PURO, sem Firestore): campos, catálogo,
 * enabled, período (missões), progresso/claimed e rate limit diário.
 * A recompensa é 100% decidida pelo catálogo — nunca pelo cliente.
 */
import { validateClaim } from '../processors/processClaims';

const BASE = {
  uid: 'user-1',
  kind: 'mission' as const,
  refId: 'm_daily_play3',
  clientRequestId: '0f2c6a1e-1111-4222-8333-444455556666',
  catalog: {
    enabled: true,
    target: 3,
    rewardUnits: 100_000_000n,
    kind: 'daily',
    periodKey: '',
  },
  userItem: { progress: 3, claimed: false, periodKey: '2026-08-24' },
  currentPeriodKey: '2026-08-24',
  claimsToday: 0,
  maxClaimsPerDay: 20,
};

/** Helper: extrai o código de falha garantindo que o resultado foi rejeição. */
function codeOf(result: ReturnType<typeof validateClaim>): string {
  if (result.ok) throw new Error('expected rejection but got ok');
  return result.code;
}

describe('validateClaim', () => {
  it('claim válido retorna a recompensa EXATA do catálogo', () => {
    expect(validateClaim(BASE)).toEqual({ ok: true, rewardUnits: 100_000_000n });
  });

  it('rejeita campos inválidos (uid/refId vazios, clientRequestId curto)', () => {
    expect(codeOf(validateClaim({ ...BASE, uid: '' }))).toBe('INVALID_CLAIM_FIELDS');
    expect(codeOf(validateClaim({ ...BASE, refId: '' }))).toBe('INVALID_CLAIM_FIELDS');
    expect(codeOf(validateClaim({ ...BASE, clientRequestId: 'curto' }))).toBe(
      'INVALID_CLAIM_FIELDS',
    );
  });

  it('rejeita catálogo ausente/desabilitado/recompensa inválida', () => {
    expect(codeOf(validateClaim({ ...BASE, catalog: null }))).toBe('CLAIM_CATALOG_MISSING');
    expect(
      codeOf(validateClaim({ ...BASE, catalog: { ...BASE.catalog, enabled: false } })),
    ).toBe('CLAIM_DISABLED');
    expect(
      codeOf(validateClaim({ ...BASE, catalog: { ...BASE.catalog, rewardUnits: 0n } })),
    ).toBe('CLAIM_REWARD_INVALID');
  });

  it('rejeita progresso insuficiente e item inexistente', () => {
    expect(
      codeOf(validateClaim({ ...BASE, userItem: { ...BASE.userItem, progress: 2 } })),
    ).toBe('CLAIM_PROGRESS_INSUFFICIENT');
    expect(codeOf(validateClaim({ ...BASE, userItem: null }))).toBe(
      'CLAIM_PROGRESS_INSUFFICIENT',
    );
  });

  it('rejeita já resgatado (claimed) — idempotência econômica', () => {
    expect(
      codeOf(validateClaim({ ...BASE, userItem: { ...BASE.userItem, claimed: true } })),
    ).toBe('CLAIM_ALREADY_CLAIMED');
  });

  it('missão fora do período é rejeitada (progresso de outro dia/semana)', () => {
    expect(
      codeOf(
        validateClaim({
          ...BASE,
          userItem: { ...BASE.userItem, periodKey: '2026-08-23' },
        }),
      ),
    ).toBe('CLAIM_PERIOD_MISMATCH');
  });

  it('conquista NÃO valida período (sem reset)', () => {
    const achievement = {
      ...BASE,
      kind: 'achievement' as const,
      refId: 'a_first_match',
      catalog: { enabled: true, target: 1, rewardUnits: 50_000_000n, kind: '', periodKey: '' },
      userItem: { progress: 1, claimed: false, periodKey: '' },
      currentPeriodKey: '',
    };
    expect(validateClaim(achievement)).toEqual({ ok: true, rewardUnits: 50_000_000n });
  });

  it('aplica rate limit diário de claims via config', () => {
    expect(codeOf(validateClaim({ ...BASE, claimsToday: 20 }))).toBe('DAILY_LIMIT_REACHED');
    expect(validateClaim({ ...BASE, claimsToday: 19 }).ok).toBe(true);
  });
});
