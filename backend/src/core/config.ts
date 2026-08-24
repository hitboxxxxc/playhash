/**
 * PlayHash — configuração econômica (config/economy).
 * Cache curto em memória (30s). Config ausente/inválida => ERRO
 * (processadores falham seguro — nunca inventam parâmetros).
 */
import { Firestore } from 'firebase-admin/firestore';
import { EconomyConfig, EconomyLimits } from './types';
import { toInt } from './precision';

const CONFIG_DOC = 'config/economy';
const CACHE_TTL_MS = 30_000;

let cache: { value: EconomyConfig; loadedAt: number } | null = null;

/** Visível para testes/injeção. */
export function invalidateConfigCache(): void {
  cache = null;
}

function num(raw: unknown, fallback: number, min: number, name: string): number {
  if (raw === undefined || raw === null) return fallback;
  const v = Number(raw);
  if (!Number.isSafeInteger(v) || v < min) {
    throw new Error(`ECONOMY_CONFIG_INVALID_FIELD:${name}`);
  }
  return v;
}

function parseLimits(raw: unknown): EconomyLimits {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    maxSessionsPerDay: num(r.maxSessionsPerDay, 50, 1, 'maxSessionsPerDay'),
    maxPurchaseIntentsPerDay: num(r.maxPurchaseIntentsPerDay, 20, 1, 'maxPurchaseIntentsPerDay'),
    minSessionDurationMs: num(r.minSessionDurationMs, 5_000, 0, 'minSessionDurationMs'),
    maxSessionDurationMs: num(r.maxSessionDurationMs, 3_600_000, 1, 'maxSessionDurationMs'),
    maxScorePerSecond: num(r.maxScorePerSecond, 100, 1, 'maxScorePerSecond'),
    tempGrantDurationMs: num(r.tempGrantDurationMs, 86_400_000, 1, 'tempGrantDurationMs'),
    maxBatchSize: num(r.maxBatchSize, 100, 1, 'maxBatchSize'),
    maxUsersPerBlock: num(r.maxUsersPerBlock, 2_000, 1, 'maxUsersPerBlock'),
  };
}

export async function getEconomyConfig(db: Firestore): Promise<EconomyConfig> {
  if (cache && Date.now() - cache.loadedAt < CACHE_TTL_MS) return cache.value;

  const snap = await db.doc(CONFIG_DOC).get();
  if (!snap.exists) throw new Error('ECONOMY_CONFIG_MISSING');

  const data = snap.data() ?? {};
  const blockRewardRaw = data.blockRewardUnits;
  if (blockRewardRaw === undefined || blockRewardRaw === null) {
    throw new Error('ECONOMY_CONFIG_INVALID_FIELD:blockRewardUnits');
  }

  const value: EconomyConfig = {
    blockRewardUnits: toInt(blockRewardRaw as number | string),
    blockIntervalMs: num(data.blockIntervalMs, 300_000, 1, 'blockIntervalMs'),
    coinPrecision: num(data.coinPrecision, 1_000_000, 1, 'coinPrecision'),
    powerBasePerHs: num(data.powerBasePerHs, 1_000, 1, 'powerBasePerHs'),
    residueUnits: toInt((data.residueUnits ?? 0) as number | string),
    economicRuleVersion: num(data.economicRuleVersion, 1, 1, 'economicRuleVersion'),
    limits: parseLimits(data.limits),
  };

  cache = { value, loadedAt: Date.now() };
  return value;
}
