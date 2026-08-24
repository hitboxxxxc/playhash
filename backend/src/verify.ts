/**
 * Verificação SOMENTE LEITURA do Firestore.
 *
 * Conecta com o Admin SDK (mesma resolução de chave de admin.ts) e imprime
 * EXISTÊNCIA/contagem das coleções-chave. NUNCA imprime conteúdo de documentos
 * nem dados sensíveis — apenas nomes, existência e contagens.
 */
import { initAdmin } from './admin';

async function countCollection(
  db: ReturnType<typeof initAdmin>['db'],
  collectionPath: string,
): Promise<number> {
  const snap = await db.collection(collectionPath).count().get();
  return snap.data().count;
}

async function main(): Promise<void> {
  const { db, projectId } = initAdmin();
  console.log(`[verify] project=${projectId} (somente leitura)`);

  const econSnap = await db.doc('config/economy').get();
  console.log(`[verify] config/economy: ${econSnap.exists ? 'EXISTE' : 'AUSENTE'}`);

  const machines = await countCollection(db, 'config/catalog/machines');
  console.log(`[verify] config/catalog/machines: ${machines} documento(s)`);

  const games = await countCollection(db, 'games');
  console.log(`[verify] games: ${games} documento(s)`);

  const blocks = await countCollection(db, 'blocks');
  console.log(`[verify] blocks: ${blocks} documento(s)`);

  const seeded = econSnap.exists && machines > 0 && games > 0;
  console.log(seeded ? '[verify] OK' : '[verify] INCOMPLETO — rode o seed (npm run seed)');
  if (!seeded) process.exitCode = 1;
}

main().catch((err: unknown) => {
  console.error(`[verify] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
