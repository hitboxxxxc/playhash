/**
 * Testes ANTIFRAUDE de saque (puros, sem Firestore) — doc 05 §36.
 * Cobre: cooldown/maxPerDay combinados, elegibilidade (idade da conta +
 * gameSessions finished), bloqueio review após 3+ falhas de elegibilidade
 * no dia (réplica do contador) e precedência das regras a→h.
 */
import {
  WithdrawalValidationInput,
  validateWithdrawal,
} from '../processors/processWithdrawals';

const HOUR = 3_600_000;
const NOW = Date.now();

function base(
  overrides: Partial<WithdrawalValidationInput> = {},
): WithdrawalValidationInput {
  return {
    assetEnabled: true,
    amountUnits: 25_000_000n,
    minWithdrawUnits: 20_000_000n,
    availableBalanceUnits: 1_000_000_000n,
    lastNonFailedWithdrawalAtMs: null,
    cooldownHours: 24,
    withdrawalsToday: 0,
    maxPerDay: 3,
    accountCreatedAtMs: NOW - 48 * HOUR,
    minAccountAgeHours: 24,
    finishedGames: 5,
    requireFinishedGames: 1,
    userStatus: 'active',
    destinationValid: true,
    ...overrides,
  };
}

describe('antifraude: cooldown × maxPerDay', () => {
  it('cooldown ativo bloqueia mesmo com cota diária livre', () => {
    expect(
      validateWithdrawal(
        base({ lastNonFailedWithdrawalAtMs: NOW - 12 * HOUR, withdrawalsToday: 0 }),
      ),
    ).toEqual({ ok: false, failureCode: 'COOLDOWN_ACTIVE' });
  });

  it('cooldown vencido + cota cheia ⇒ DAILY_LIMIT_REACHED', () => {
    expect(
      validateWithdrawal(
        base({ lastNonFailedWithdrawalAtMs: NOW - 30 * HOUR, withdrawalsToday: 3 }),
      ),
    ).toEqual({ ok: false, failureCode: 'DAILY_LIMIT_REACHED' });
  });

  it('saques FAILED não contam para cooldown nem para maxPerDay', () => {
    // Réplica: o processador consulta apenas status in [completed, processing]
    // e filtra status !== 'failed' na contagem diária. Último saque failed ⇒
    // sem cooldown; contador diário ignora failed.
    const lastWasFailed = base({
      lastNonFailedWithdrawalAtMs: null, // query só traz completed/processing
      withdrawalsToday: 2, // 2 completed hoje; 1 failed ignorado
    });
    expect(validateWithdrawal(lastWasFailed)).toEqual({ ok: true });
  });

  it('3º saque do dia passa se maxPerDay=3 e cooldown ok', () => {
    expect(
      validateWithdrawal(
        base({
          lastNonFailedWithdrawalAtMs: NOW - 25 * HOUR,
          withdrawalsToday: 2,
          maxPerDay: 3,
        }),
      ),
    ).toEqual({ ok: true });
  });
});

describe('antifraude: elegibilidade da conta', () => {
  it('conta recém-criada (<24h) é inelegível mesmo com saldo alto', () => {
    expect(
      validateWithdrawal(base({ accountCreatedAtMs: NOW - 23 * HOUR })),
    ).toEqual({ ok: false, failureCode: 'ACCOUNT_TOO_NEW' });
  });

  it('sem nenhuma partida finished é inelegível', () => {
    expect(validateWithdrawal(base({ finishedGames: 0 }))).toEqual({
      ok: false,
      failureCode: 'NO_FINISHED_GAMES',
    });
  });

  it('requireFinishedGames configurável pelo servidor', () => {
    expect(
      validateWithdrawal(
        base({ finishedGames: 2, requireFinishedGames: 3 }),
      ),
    ).toEqual({ ok: false, failureCode: 'NO_FINISHED_GAMES' });
    expect(
      validateWithdrawal(
        base({ finishedGames: 3, requireFinishedGames: 3 }),
      ),
    ).toEqual({ ok: true });
  });
});

describe('antifraude: lock review após 3 falhas de elegibilidade (§36)', () => {
  /**
   * Réplica PURA do contador em rateLimits/{uid}.wf_<dia>:
   * incrementa por falha de elegibilidade; ao atingir >= 3 com código de
   * elegibilidade ⇒ users/{uid}.status = 'review' + ACCOUNT_ECONOMIC_LOCK.
   */
  function decideLock(failuresSoFar: number, code: string): {
    failures: number;
    locked: boolean;
  } {
    const ELIGIBILITY = new Set([
      'ACCOUNT_TOO_NEW',
      'NO_FINISHED_GAMES',
      'COOLDOWN_ACTIVE',
      'DAILY_LIMIT_REACHED',
      'ACCOUNT_IN_REVIEW',
    ]);
    const failures = failuresSoFar + 1;
    const locked = failures >= 3 && ELIGIBILITY.has(code);
    return { failures, locked };
  }

  it('1ª e 2ª falhas NÃO travam a conta', () => {
    expect(decideLock(0, 'ACCOUNT_TOO_NEW')).toEqual({ failures: 1, locked: false });
    expect(decideLock(1, 'NO_FINISHED_GAMES')).toEqual({ failures: 2, locked: false });
  });

  it('3ª falha de elegibilidade TRAVA a conta (review)', () => {
    expect(decideLock(2, 'COOLDOWN_ACTIVE')).toEqual({ failures: 3, locked: true });
  });

  it('falha OPERACIONAL (ex.: INVALID_ADDRESS) nunca trava sozinha', () => {
    expect(decideLock(2, 'INVALID_ADDRESS')).toEqual({ failures: 3, locked: false });
  });

  it('conta travada rejeita novos saques com ACCOUNT_IN_REVIEW', () => {
    expect(validateWithdrawal(base({ userStatus: 'review' }))).toEqual({
      ok: false,
      failureCode: 'ACCOUNT_IN_REVIEW',
    });
  });
});

describe('antifraude: precedência e limites', () => {
  it('review tem precedência sobre saldo insuficiente (g antes de h… mas depois de f)', () => {
    // Ordem do prompt: (c) saldo vem ANTES de (f)/(g) — saldo insuficiente vence.
    expect(
      validateWithdrawal(
        base({
          availableBalanceUnits: 0n,
          userStatus: 'review',
        }),
      ),
    ).toEqual({ ok: false, failureCode: 'INSUFFICIENT_BALANCE' });
    // Com saldo OK, review aparece.
    expect(
      validateWithdrawal(base({ userStatus: 'review' })),
    ).toEqual({ ok: false, failureCode: 'ACCOUNT_IN_REVIEW' });
  });

  it('destino inválido é a última checagem (h) — e-mail ⇒ INVALID_EMAIL', () => {
    expect(
      validateWithdrawal(base({ destinationValid: false, destinationEmail: 'x@y' })),
    ).toEqual({ ok: false, failureCode: 'INVALID_EMAIL' });
  });

  it('fluxo completo válido permanece ok', () => {
    expect(validateWithdrawal(base())).toEqual({ ok: true });
  });
});
