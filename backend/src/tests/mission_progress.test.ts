/**
 * Testes do progresso de missões/conquistas (PURO, sem Firestore):
 * periodKey (daily/weekly ISO), reset de período, modos add/max e
 * consistência de kills.
 */
import {
  computeProgress,
  isoWeekKey,
  periodKeyFor,
  validateKillsConsistency,
} from '../processors/mission_progress';

// UTC: 2026-08-24 é uma SEGUNDA-FEIRA → semana ISO 2026-W35.
const MON_2026_08_24 = Date.UTC(2026, 7, 24, 12, 0, 0);
// Domingo 2026-08-23 pertence à semana ISO que TERMINA nesse domingo (W34).
const SUN_2026_08_23 = Date.UTC(2026, 7, 23, 23, 30, 0);
// Fim de ano: 2027-01-01 é sexta → semana ISO 2026-W53.
const FRI_2027_01_01 = Date.UTC(2027, 0, 1, 12, 0, 0);
// 2026-01-01 é quinta → semana ISO 2026-W01.
const THU_2026_01_01 = Date.UTC(2026, 0, 1, 12, 0, 0);

describe('periodKeyFor / isoWeekKey', () => {
  it('daily = YYYY-MM-DD UTC', () => {
    expect(periodKeyFor('daily', MON_2026_08_24)).toBe('2026-08-24');
    // Borda de fuso: 23h30 UTC ainda é o mesmo dia UTC.
    expect(periodKeyFor('daily', SUN_2026_08_23)).toBe('2026-08-23');
  });

  it('weekly = YYYY-Www ISO (semana começa na segunda)', () => {
    expect(periodKeyFor('weekly', MON_2026_08_24)).toBe('2026-W35');
    expect(periodKeyFor('weekly', SUN_2026_08_23)).toBe('2026-W34');
  });

  it('bordas de ano ISO', () => {
    expect(isoWeekKey(new Date(FRI_2027_01_01))).toBe('2026-W53');
    expect(isoWeekKey(new Date(THU_2026_01_01))).toBe('2026-W01');
  });
});

describe('computeProgress', () => {
  it('add acumula dentro do período', () => {
    expect(
      computeProgress({
        currentProgress: 2,
        currentPeriodKey: '2026-08-24',
        expectedPeriodKey: '2026-08-24',
        mode: 'add',
        value: 1,
      }),
    ).toBe(3);
  });

  it('add reinicia de 0 quando o período mudou (reset diário/semanal)', () => {
    expect(
      computeProgress({
        currentProgress: 2,
        currentPeriodKey: '2026-08-23',
        expectedPeriodKey: '2026-08-24',
        mode: 'add',
        value: 1,
      }),
    ).toBe(1);
  });

  it('max retém o maior valor do período', () => {
    expect(
      computeProgress({
        currentProgress: 7_250,
        currentPeriodKey: '2026-W35',
        expectedPeriodKey: '2026-W35',
        mode: 'max',
        value: 5_000,
      }),
    ).toBe(7_250);
    expect(
      computeProgress({
        currentProgress: 7_250,
        currentPeriodKey: '2026-W35',
        expectedPeriodKey: '2026-W35',
        mode: 'max',
        value: 9_000,
      }),
    ).toBe(9_000);
  });

  it('max também reinicia quando o período mudou', () => {
    expect(
      computeProgress({
        currentProgress: 7_250,
        currentPeriodKey: '2026-W34',
        expectedPeriodKey: '2026-W35',
        mode: 'max',
        value: 3_000,
      }),
    ).toBe(3_000);
  });

  it('conquistas (periodKey fixo "") nunca reiniciam', () => {
    expect(
      computeProgress({
        currentProgress: 99,
        currentPeriodKey: '',
        expectedPeriodKey: '',
        mode: 'add',
        value: 1,
      }),
    ).toBe(100);
  });
});

describe('validateKillsConsistency', () => {
  it('aceita ausente/null (games legados) e 0', () => {
    expect(validateKillsConsistency(undefined, 100, 150)).toBeNull();
    expect(validateKillsConsistency(null, 100, 150)).toBeNull();
    expect(validateKillsConsistency(0, 0, 150)).toBeNull();
  });

  it('rejeita não-inteiro/negativo/não-número', () => {
    expect(validateKillsConsistency(-1, 100, 150)).toBe('KILLS_INVALID');
    expect(validateKillsConsistency(1.5, 100, 150)).toBe('KILLS_INVALID');
    expect(validateKillsConsistency('5', 100, 150)).toBe('KILLS_INVALID');
  });

  it('kills × pointsPerKill ≤ score (cada abate vale PELO MENOS pointsPerKill)', () => {
    expect(validateKillsConsistency(10, 1_500, 150)).toBeNull(); // exato
    expect(validateKillsConsistency(10, 2_000, 150)).toBeNull(); // com bônus
    expect(validateKillsConsistency(11, 1_500, 150)).toBe('KILLS_INCONSISTENT');
  });

  it('kills > 0 sem pointsPerKill no game é rejeitado', () => {
    expect(validateKillsConsistency(3, 1_000, 0)).toBe('KILLS_NOT_SUPPORTED');
  });
});
