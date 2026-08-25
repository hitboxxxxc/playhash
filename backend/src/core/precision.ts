/**
 * PlayHash — precisão inteira (doc 05 §21).
 * Toda aritmética econômica usa BigInt. Proibido float.
 */

/** Converte valor vindo do Firestore (number|string|bigint) em BigInt validado. */
export function toInt(value: number | string | bigint): bigint {
  if (typeof value === 'bigint') return value;
  if (typeof value === 'string') {
    if (!/^-?\d+$/.test(value)) throw new Error(`INVALID_INT_STRING:${value}`);
    return BigInt(value);
  }
  if (!Number.isSafeInteger(value)) throw new Error('INT_NOT_SAFE_INTEGER');
  return BigInt(value);
}

/** Divisão inteira com PISO (floor), inclusive para negativos. */
export function floorDiv(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new Error('DIVISION_BY_ZERO');
  const q = a / b;
  const r = a % b;
  if (r !== 0n && r < 0n !== b < 0n) return q - 1n;
  return q;
}

export interface PowerEntry {
  uid: string;
  power: bigint;
}

/**
 * Conversão COIN → ativo de payout (config/payouts v2) — AUTORIDADE BACKEND.
 *
 * assetUnitPerCoinScaled = quantos MENORES UNIDADES do ativo 1 COIN compra
 * (ex.: BTC decimals=8 e scaled=25 ⇒ 1 coin = 25 satoshi).
 *
 * Regra determinística: ARREDONDAMENTO PARA BAIXO (floor) — a conversão
 * NUNCA cria valor (o resíduo fica no backend, nunca a favor do usuário).
 * Aritmética 100% BigInt (proibido float).
 */
export function coinToAsset(
  coinUnits: bigint,
  assetUnitPerCoinScaled: bigint,
  coinPrecision: number,
): bigint {
  if (coinUnits < 0n) throw new Error('NEGATIVE_COIN_AMOUNT');
  if (assetUnitPerCoinScaled <= 0n) throw new Error('INVALID_ASSET_RATE');
  if (!Number.isSafeInteger(coinPrecision) || coinPrecision <= 0) {
    throw new Error('INVALID_COIN_PRECISION');
  }
  return floorDiv(coinUnits * assetUnitPerCoinScaled, BigInt(coinPrecision));
}

/**
 * Conversão FIXA COIN→LTC em ARITMÉTICA INTEIRA de COINS (config/payouts v3):
 *   litoshi = amountCoins × litoshiPerCoin
 * Padrão atual: litoshiPerCoin = 100 ⇒ 1 COIN = 100 litoshi = 0,000001 LTC.
 * Entrada em COINS INTEIRAS — nunca fração de coin (resíduo fica no backend).
 * 100% BigInt (proibido float); determinístico e sem perda.
 */
export function coinsToLitoshi(amountCoins: bigint, litoshiPerCoin: bigint): bigint {
  if (amountCoins < 0n) throw new Error('NEGATIVE_COIN_AMOUNT');
  if (litoshiPerCoin <= 0n) throw new Error('INVALID_ASSET_RATE');
  return amountCoins * litoshiPerCoin;
}

export interface DistributionResult {
  /** reward_i por uid (apenas usuários com reward > 0). */
  rewards: Map<string, bigint>;
  distributedTotal: bigint;
  /** Resíduo determinístico: blockReward − Σ rewards (carregado p/ próximo bloco). */
  residueUnits: bigint;
}

/**
 * Distribui o reward do bloco de forma DETERMINÍSTICA:
 *   reward_i = floor(BLOCK_REWARD × power_i / NETWORK_POWER)
 *   resíduo  = BLOCK_REWARD − Σ reward_i   (vai para o próximo bloco)
 *
 * A ordem de processamento é irrelevante para o resultado: a soma é
 * comutativa e cada parcela depende apenas de power_i/networkPower.
 * Entradas são ordenadas por uid apenas para estabilidade de iteração.
 *
 * Se NETWORK_POWER <= 0, nada é distribuído e o bloco inteiro vira resíduo.
 */
export function distributeBlockReward(
  blockRewardUnits: bigint,
  entries: PowerEntry[],
): DistributionResult {
  if (blockRewardUnits < 0n) throw new Error('NEGATIVE_BLOCK_REWARD');
  const rewards = new Map<string, bigint>();
  let networkPower = 0n;
  for (const e of entries) {
    if (e.power < 0n) throw new Error(`NEGATIVE_POWER:${e.uid}`);
    networkPower += e.power;
  }
  if (entries.length === 0 || networkPower <= 0n) {
    return { rewards, distributedTotal: 0n, residueUnits: blockRewardUnits };
  }
  let distributedTotal = 0n;
  for (const e of [...entries].sort((a, b) => (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0))) {
    if (e.power <= 0n) continue;
    const reward = floorDiv(blockRewardUnits * e.power, networkPower);
    if (reward > 0n) {
      rewards.set(e.uid, reward);
      distributedTotal += reward;
    }
  }
  const residueUnits = blockRewardUnits - distributedTotal;
  return { rewards, distributedTotal, residueUnits };
}
