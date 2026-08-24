/**
 * Seed DEV — cria config/economy, config/catalog/machines/* e games/*
 * SOMENTE se não existirem. Nunca sobrescreve dados existentes.
 * Bloqueado em produção (NODE_ENV=production).
 *
 * NOTA: caminhos de DOCUMENTO no Firestore precisam de nº PAR de segmentos;
 * por isso o catálogo vive em config/catalog/machines/{id} (4 segmentos).
 */
import { initAdmin } from './admin';

const ECONOMY = {
  blockRewardUnits: 1_000_000, // 1 coin por bloco (coinPrecision = 6 casas)
  blockIntervalMs: 300_000, // 5 minutos
  coinPrecision: 1_000_000,
  powerBasePerHs: 1_000,
  residueUnits: 0,
  economicRuleVersion: 1,
  limits: {
    maxSessionsPerDay: 50,
    maxPurchaseIntentsPerDay: 20,
    minSessionDurationMs: 5_000,
    maxSessionDurationMs: 3_600_000,
    maxScorePerSecond: 100,
    tempGrantDurationMs: 86_400_000, // 24h
    maxBatchSize: 100,
    maxUsersPerBlock: 2_000,
  },
};

const MACHINES: Record<string, Record<string, unknown>> = {
  'asic-mini': {
    name: 'ASIC Mini',
    priceUnits: 10_000_000, // 10 coins
    powerAmount: 500,
    currencyId: 'coins',
    enabled: true,
  },
  'asic-pro': {
    name: 'ASIC Pro',
    priceUnits: 50_000_000, // 50 coins
    powerAmount: 3_000,
    currencyId: 'coins',
    enabled: true,
  },
  'asic-hyper': {
    name: 'ASIC Hyper',
    priceUnits: 200_000_000, // 200 coins
    powerAmount: 15_000,
    currencyId: 'coins',
    enabled: true,
  },
};

const GAMES: Record<string, Record<string, unknown>> = {
  'tap-blitz': {
    name: 'Tap Blitz',
    enabled: true,
    configuration: {
      maxExpectedScore: 1_000,
      powerBaseReward: 250,
      powerCapPerSession: 250,
    },
  },
  'reflex-rush': {
    name: 'Reflex Rush',
    enabled: true,
    configuration: {
      maxExpectedScore: 2_000,
      powerBaseReward: 400,
      powerCapPerSession: 400,
    },
  },
};

async function createIfMissing(
  db: ReturnType<typeof initAdmin>['db'],
  docPath: string,
  data: Record<string, unknown>,
): Promise<'created' | 'exists'> {
  const ref = db.doc(docPath);
  const snap = await ref.get();
  if (snap.exists) return 'exists';
  await ref.set(data);
  return 'created';
}

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('SEED_BLOCKED_IN_PRODUCTION');
  }
  const { db, projectId } = initAdmin();
  console.log(`[seed] start project=${projectId} (somente docs ausentes)`);

  console.log(`[seed] config/economy: ${await createIfMissing(db, 'config/economy', ECONOMY)}`);
  for (const [id, data] of Object.entries(MACHINES)) {
    console.log(`[seed] config/catalog/machines/${id}: ${await createIfMissing(db, `config/catalog/machines/${id}`, data)}`);
  }
  for (const [id, data] of Object.entries(GAMES)) {
    console.log(`[seed] games/${id}: ${await createIfMissing(db, `games/${id}`, data)}`);
  }
  console.log('[seed] done');
}

main().catch((err) => {
  console.error(`[seed] fatal=${String(err?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
