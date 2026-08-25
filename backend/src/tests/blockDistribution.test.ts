/**
 * Testes de distribuição de blocos com carry de resíduo (doc 05 §21/§39 —
 * propriedades: conservação, carry determinístico, fechamento em cadeia).
 */
import { distributeBlockReward } from '../core/precision';

const BASE_REWARD = 1_000_000n; // 1 coin por bloco

describe('carry de resíduo entre blocos', () => {
  it('resíduo do bloco N entra no reward efetivo do bloco N+1', () => {
    // Bloco 1: 3 miners iguais → resíduo 1
    const b1 = distributeBlockReward(BASE_REWARD, [
      { uid: 'a', power: 100n },
      { uid: 'b', power: 100n },
      { uid: 'c', power: 100n },
    ]);
    expect(b1.residueUnits).toBe(1n);

    // Bloco 2: reward efetivo = base + resíduo = 1.000.001
    // floor(1.000.001 × 100 / 300) = 333.333 para cada; resíduo acumula 2.
    const effective2 = BASE_REWARD + b1.residueUnits;
    const b2 = distributeBlockReward(effective2, [
      { uid: 'a', power: 100n },
      { uid: 'b', power: 100n },
      { uid: 'c', power: 100n },
    ]);
    expect(b2.rewards.get('a')).toBe(333_333n);
    expect(b2.residueUnits).toBe(2n);
    expect(b2.distributedTotal + b2.residueUnits).toBe(effective2);
  });

  it('cadeia de 5 blocos conserva o total emitido (+/- resíduo final)', () => {
    let residue = 0n;
    let totalDistributed = 0n;
    const blocks = 5;
    for (let n = 0; n < blocks; n++) {
      const result = distributeBlockReward(BASE_REWARD + residue, [
        { uid: 'm1', power: 1_234n },
        { uid: 'm2', power: 567n },
        { uid: 'm3', power: 89n },
        { uid: 'm4', power: 42_000n },
      ]);
      expect(result.distributedTotal + result.residueUnits).toBe(BASE_REWARD + residue);
      totalDistributed += result.distributedTotal;
      residue = result.residueUnits;
    }
    // Total emitido = blocos × base; sobra apenas o resíduo não-distribuído.
    expect(totalDistributed + residue).toBe(BigInt(blocks) * BASE_REWARD);
    expect(residue).toBeLessThan(10n); // resíduo permanece ínfimo
  });

  it('bloco com rede vazia carrega 100% para o próximo', () => {
    const empty = distributeBlockReward(BASE_REWARD, []);
    expect(empty.residueUnits).toBe(BASE_REWARD);

    const next = distributeBlockReward(BASE_REWARD + empty.residueUnits, [
      { uid: 'solo', power: 5_000n },
    ]);
    expect(next.rewards.get('solo')).toBe(2_000_000n);
    expect(next.residueUnits).toBe(0n);
  });

  it('reward nunca excede o reward efetivo do bloco', () => {
    const result = distributeBlockReward(BASE_REWARD, [
      { uid: 'whale', power: 9_999_999n },
      { uid: 'shrimp', power: 1n },
    ]);
    expect(result.distributedTotal).toBeLessThanOrEqual(BASE_REWARD);
    expect(result.rewards.get('whale')!).toBeLessThanOrEqual(BASE_REWARD);
  });
});

/**
 * 12.23 — BLOCK_REWARD = 5 COIN (5.000.000 units, coinPrecision = 1.000.000).
 * Decisão do dono: 1 jogador elegível recebe TUDO; múltiplos dividem por
 * USER_POWER/NETWORK_POWER (BigInt floor) com resíduo carregado.
 */
const REWARD_5_COIN = 5_000_000n;

describe('BLOCK_REWARD = 5 COIN (12.23)', () => {
  it('único jogador elegível recebe EXATAMENTE 5.000.000 units (5 COIN cheios)', () => {
    const result = distributeBlockReward(REWARD_5_COIN, [
      { uid: 'solo', power: 42_000n },
    ]);
    expect(result.rewards.size).toBe(1);
    expect(result.rewards.get('solo')).toBe(5_000_000n);
    expect(result.distributedTotal).toBe(5_000_000n);
    expect(result.residueUnits).toBe(0n);
  });

  it('dois jogadores 100/300 PH/s dividem 1.250.000 / 3.750.000', () => {
    // NETWORK_POWER = 400; floor(5.000.000 × 100/400) = 1.250.000;
    // floor(5.000.000 × 300/400) = 3.750.000; resíduo zero.
    const result = distributeBlockReward(REWARD_5_COIN, [
      { uid: 'small', power: 100n },
      { uid: 'big', power: 300n },
    ]);
    expect(result.rewards.get('small')).toBe(1_250_000n);
    expect(result.rewards.get('big')).toBe(3_750_000n);
    expect(result.distributedTotal).toBe(5_000_000n);
    expect(result.residueUnits).toBe(0n);
  });

  it('caso indivisível: resíduo é carregado para o próximo bloco', () => {
    // 3 miners de poder igual: floor(5.000.000/3) = 1.666.666 cada;
    // distribuído = 4.999.998; resíduo = 2 → entra no bloco seguinte.
    const powers = [
      { uid: 'a', power: 7n },
      { uid: 'b', power: 7n },
      { uid: 'c', power: 7n },
    ];
    const blockN = distributeBlockReward(REWARD_5_COIN, powers);
    expect(blockN.rewards.get('a')).toBe(1_666_666n);
    expect(blockN.rewards.get('b')).toBe(1_666_666n);
    expect(blockN.rewards.get('c')).toBe(1_666_666n);
    expect(blockN.residueUnits).toBe(2n);

    // Bloco N+1: reward efetivo = 5.000.002 → conserva o total emitido.
    const blockN1 = distributeBlockReward(REWARD_5_COIN + blockN.residueUnits, powers);
    expect(blockN1.distributedTotal + blockN1.residueUnits).toBe(REWARD_5_COIN + 2n);
  });

  it('rede vazia carrega os 5 COIN inteiros para o próximo bloco', () => {
    const empty = distributeBlockReward(REWARD_5_COIN, []);
    expect(empty.distributedTotal).toBe(0n);
    expect(empty.residueUnits).toBe(5_000_000n);

    const next = distributeBlockReward(REWARD_5_COIN + empty.residueUnits, [
      { uid: 'late', power: 1n },
    ]);
    expect(next.rewards.get('late')).toBe(10_000_000n); // 2 blocos acumulados
  });
});
