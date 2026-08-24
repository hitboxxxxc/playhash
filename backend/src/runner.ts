/**
 * Runner econômico — ÚNICA autoridade econômica do PlayHash.
 * Executa os 3 processadores em ordem, com isolamento de erro entre eles
 * (falha em um não impede os outros) e log SEM dados sensíveis.
 *
 * Executado por GitHub Actions (cron a cada 5 min + workflow_dispatch).
 *
 * Ação especial `devTopUp` (workflow_dispatch): credita saldo de teste no uid
 * informado SOMENTE quando a repo variable ENV == "dev" (env APP_ENV).
 * Em ENV != dev é no-op com log claro — nunca roda em produção.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { initAdmin } from './admin';
import { processGameSessions } from './processors/processGameSessions';
import { processPurchaseIntents } from './processors/processPurchaseIntents';
import { processClaims } from './processors/processClaims';
import { closeBlocks } from './processors/closeBlocks';
import { leagueSweep } from './processors/league_sweep';
import { processSeasonProgress } from './processors/season_progress';
import { getEconomyConfig } from './core/config';
import { toInt } from './core/precision';
import { writeAudit, auditEventId } from './core/audit';
import { utcDayKey } from './core/ratelimit';

type Processor = { name: string; run: (db: Firestore) => Promise<unknown> };

function sanitize(err: unknown): string {
  // Apenas a mensagem, truncada — sem stack (pode conter paths/dados).
  return String((err as Error)?.message ?? err).slice(0, 300);
}

/**
 * Serialização segura para log: converte BigInt para string em vez de
 * lançar "Do not know how to serialize a BigInt" (que marcava o
 * processador como FAILED mesmo após sucesso econômico).
 */
export function serializeForLog(value: unknown): string {
  return JSON.stringify(value, (_key, v: unknown) =>
    typeof v === 'bigint' ? v.toString() : v,
  );
}

/** Lê a ação do workflow: env RUNNER_ACTION ou argv --action=... */
export function readAction(argv: string[] = process.argv): string {
  const fromArg = argv.find((a) => a.startsWith('--action='))?.split('=')[1];
  return String(process.env.RUNNER_ACTION ?? fromArg ?? 'run').trim();
}

export interface DevTopUpOptions {
  uid: string;
  amountCoins: bigint;
  env: string;
}

/**
 * Crédito de saldo de DESENVOLVIMENTO.
 * Gate: SOMENTE executa com env === 'dev' (repo variable ENV). Auditoria
 * DEV_TOPUP com eventId determinístico (uid+dia+valor) ⇒ reexecução no mesmo
 * dia com o mesmo valor é no-op (idempotente).
 */
export async function runDevTopUp(
  db: Firestore,
  opts: DevTopUpOptions,
): Promise<{ credited: boolean; amountUnits: bigint }> {
  if (opts.env !== 'dev') {
    console.log(
      `[runner] devTopUp SKIP: requer repo variable ENV=dev (atual='${opts.env}'). Nada foi alterado.`,
    );
    return { credited: false, amountUnits: 0n };
  }
  if (!opts.uid) throw new Error('DEV_TOPUP_UID_MISSING');

  const economy = await getEconomyConfig(db);
  const amountUnits = opts.amountCoins * BigInt(economy.coinPrecision);
  const eventId = auditEventId(
    'DEV_TOPUP',
    `${opts.uid}:${utcDayKey(Date.now())}:${opts.amountCoins}`,
  );

  await db.runTransaction(async (tx) => {
    const walletRef = db.doc(`wallets/${opts.uid}`);
    const snap = await tx.get(walletRef);
    const balance = snap.exists
      ? toInt((snap.get('availableBalance') ?? 0) as number | string)
      : 0n;
    tx.set(
      walletRef,
      {
        uid: opts.uid,
        availableBalance: (balance + amountUnits).toString(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  await writeAudit(db, {
    eventId,
    userId: opts.uid,
    type: 'DEV_TOPUP',
    valueUnits: amountUnits,
    currencyId: 'coins',
    referenceId: eventId.split(':')[1] ?? opts.uid,
    origin: 'runner.devTopUp',
    ruleVersion: economy.economicRuleVersion,
    status: 'SUCCESS',
    detail: { amountCoins: opts.amountCoins.toString(), env: opts.env },
  });
  console.log(
    `[runner] devTopUp ok uid=<redacted> coins=${opts.amountCoins} (auditoria determinística)`,
  );
  return { credited: true, amountUnits };
}

async function main(): Promise<void> {
  const startedAt = Date.now();
  const { db, projectId } = initAdmin();
  const action = readAction();
  console.log(`[runner] start project=${projectId} action=${action}`);

  if (action === 'devTopUp') {
    const amountRaw = process.env.DEV_TOPUP_COINS ?? '5000';
    const amountCoins = BigInt(/^\d+$/.test(amountRaw) ? amountRaw : '5000');
    try {
      await runDevTopUp(db, {
        uid: String(process.env.DEV_TOPUP_UID ?? '').trim(),
        amountCoins,
        env: String(process.env.APP_ENV ?? '').trim().toLowerCase(),
      });
      console.log(`[runner] done in ${Date.now() - startedAt}ms`);
      process.exitCode = 0;
    } catch (err) {
      console.error(`[runner] devTopUp FAILED=${sanitize(err)}`);
      process.exitCode = 1;
    }
    return;
  }

  // Ordem: eventos de origem (sessões → compras) ANTES de claims (o claim
  // valida o progresso mais recente); em seguida o XP da temporada (consome
  // os flags seasonXpApplied de sessões/claims), o fechamento de blocos
  // (sweep de poder usa o totalPower já recalculado) e por fim o sweep de
  // LIGAS (atribuição + leaderboard + diária com o poder consolidado).
  const processors: Processor[] = [
    { name: 'gameSessions', run: processGameSessions },
    { name: 'purchaseIntents', run: processPurchaseIntents },
    { name: 'claims', run: processClaims },
    { name: 'seasonProgress', run: processSeasonProgress },
    { name: 'closeBlocks', run: closeBlocks },
    { name: 'leagueSweep', run: leagueSweep },
  ];

  let failures = 0;
  for (const p of processors) {
    try {
      const result = await p.run(db);
      console.log(`[runner] ${p.name} ok=${serializeForLog(result)}`);
    } catch (err) {
      failures += 1;
      console.error(`[runner] ${p.name} FAILED=${sanitize(err)}`);
    }
  }

  console.log(`[runner] done in ${Date.now() - startedAt}ms failures=${failures}`);
  process.exitCode = failures > 0 ? 1 : 0;
}

// Executa apenas quando invocado diretamente (não em imports de teste).
if (require.main === module) {
  main().catch((err) => {
    console.error(`[runner] fatal=${sanitize(err)}`);
    process.exitCode = 1;
  });
}
