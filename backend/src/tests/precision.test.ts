/**
 * Testes de precisão BigInt (doc 05 §7 — exemplos adaptados; os docs 01–05
 * não estão presentes no workspace, os casos cobrem as propriedades §21:
 * piso, resíduo determinístico, conservação do reward).
 */
import { toInt, floorDiv, distributeBlockReward } from '../core/precision';

describe('toInt', () => {
  it('converte number seguro', () => {
    expect(toInt(1_000_000)).toBe(1_000_000n);
    expect(toInt(0)).toBe(0n);
  });

  it('converte string decimal', () => {
    expect(toInt('123456789012345678')).toBe(123456789012345678n);
  });

  it('rejeita float não-seguro e string inválida', () => {
    expect(() => toInt(1.5)).toThrow();
    expect(() => toInt(Number.MAX_SAFE_INTEGER + 1)).toThrow();
    expect(() => toInt('12a3')).toThrow();
  });
});

describe('floorDiv', () => {
  it('piso para positivos', () => {
    expect(floorDiv(10n, 3n)).toBe(3n);
    expect(floorDiv(9n, 3n)).toBe(3n);
  });

  it('piso para negativos (floor, não truncamento)', () => {
    expect(floorDiv(-10n, 3n)).toBe(-4n);
  });

  it('rejeita divisor zero/negativo', () => {
    expect(() => floorDiv(1n, 0n)).toThrow();
  });
});

describe('distributeBlockReward — exemplos estilo doc 05 §7', () => {
  it('divisão exata: 1 coin entre 60/40', () => {
    const r = distributeBlockReward(1_000_000n, [
      { uid: 'alice', power: 60_000n },
      { uid: 'bob', power: 40_000n },
    ]);
    expect(r.rewards.get('alice')).toBe(600_000n);
    expect(r.rewards.get('bob')).toBe(400_000n);
    expect(r.residueUnits).toBe(0n);
    expect(r.distributedTotal).toBe(1_000_000n);
  });

  it('piso com resíduo: 1 coin dividido por 3', () => {
    const r = distributeBlockReward(1_000_000n, [
      { uid: 'a', power: 1n },
      { uid: 'b', power: 1n },
      { uid: 'c', power: 1n },
    ]);
    expect(r.rewards.get('a')).toBe(333_333n);
    expect(r.rewards.get('b')).toBe(333_333n);
    expect(r.rewards.get('c')).toBe(333_333n);
    expect(r.residueUnits).toBe(1n);
    // Conservação: distribuído + resíduo == reward total
    expect(r.distributedTotal + r.residueUnits).toBe(1_000_000n);
  });

  it('usuário com power 0 não recebe nada', () => {
    const r = distributeBlockReward(1_000_000n, [
      { uid: 'miner', power: 10_000n },
      { uid: 'ghost', power: 0n },
    ]);
    expect(r.rewards.has('ghost')).toBe(false);
    expect(r.rewards.get('miner')).toBe(1_000_000n);
  });

  it('rede sem poder: reward inteiro vira resíduo', () => {
    const r = distributeBlockReward(500_000n, [{ uid: 'x', power: 0n }]);
    expect(r.rewards.size).toBe(0);
    expect(r.distributedTotal).toBe(0n);
    expect(r.residueUnits).toBe(500_000n);
  });

  it('é determinístico independente da ordem de entrada', () => {
    const users = [
      { uid: 'u1', power: 7_777n },
      { uid: 'u2', power: 123n },
      { uid: 'u3', power: 55_555n },
      { uid: 'u4', power: 9n },
      { uid: 'u5', power: 4_444n },
    ];
    const forward = distributeBlockReward(987_654n, users);
    const backward = distributeBlockReward(987_654n, [...users].reverse());
    expect([...forward.rewards.entries()].sort()).toEqual(
      [...backward.rewards.entries()].sort(),
    );
    expect(forward.residueUnits).toBe(backward.residueUnits);
  });

  it('proporção grande mantém precisão inteira (sem float)', () => {
    // power desigual extremo: 1 vs 999.999 (networkPower = 1.000.000)
    const r = distributeBlockReward(1_000_000n, [
      { uid: 'small', power: 1n },
      { uid: 'big', power: 999_999n },
    ]);
    expect(r.rewards.get('big')).toBe(999_999n); // floor(1e6 × 999999 / 1e6)
    expect(r.rewards.get('small')).toBe(1n);
    expect(r.residueUnits).toBe(0n);
    expect(r.distributedTotal + r.residueUnits).toBe(1_000_000n);
  });
});
