/**
 * Runner econômico — ÚNICA autoridade econômica do PlayHash.
 * Executa os 3 processadores em ordem, com isolamento de erro entre eles
 * (falha em um não impede os outros) e log SEM dados sensíveis.
 *
 * Executado por GitHub Actions (cron a cada 5 min + workflow_dispatch).
 */
import { initAdmin } from './admin';
import { processGameSessions } from './processors/processGameSessions';
import { processPurchaseIntents } from './processors/processPurchaseIntents';
import { closeBlocks } from './processors/closeBlocks';
import { Firestore } from 'firebase-admin/firestore';

type Processor = { name: string; run: (db: Firestore) => Promise<unknown> };

function sanitize(err: unknown): string {
  // Apenas a mensagem, truncada — sem stack (pode conter paths/dados).
  return String((err as Error)?.message ?? err).slice(0, 300);
}

async function main(): Promise<void> {
  const startedAt = Date.now();
  const { db, projectId } = initAdmin();
  console.log(`[runner] start project=${projectId}`);

  const processors: Processor[] = [
    { name: 'gameSessions', run: processGameSessions },
    { name: 'purchaseIntents', run: processPurchaseIntents },
    { name: 'closeBlocks', run: closeBlocks },
  ];

  let failures = 0;
  for (const p of processors) {
    try {
      const result = await p.run(db);
      console.log(`[runner] ${p.name} ok=${JSON.stringify(result)}`);
    } catch (err) {
      failures += 1;
      console.error(`[runner] ${p.name} FAILED=${sanitize(err)}`);
    }
  }

  console.log(`[runner] done in ${Date.now() - startedAt}ms failures=${failures}`);
  process.exitCode = failures > 0 ? 1 : 0;
}

main().catch((err) => {
  console.error(`[runner] fatal=${sanitize(err)}`);
  process.exitCode = 1;
});
