/**
 * FASE 1 (12.9) — EVIDÊNCIA CRUA SOMENTE LEITURA.
 * Imprime o doc config/payouts COMO ESTÁ no Firestore (JSON completo) e os
 * últimos withdrawalIntents/withdrawals crus (e-mail mascarado; nenhum segredo).
 */
import { initAdmin } from './admin';

function maskEmail(email: string): string {
  const at = email.indexOf('@');
  if (at <= 0) return '*'.repeat(Math.min(email.length, 8));
  return `${email.slice(0, Math.min(2, at))}***@${email.slice(at + 1)}`;
}

function maskDeep(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(maskDeep);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = /email/i.test(k) && typeof v === 'string' ? maskEmail(v) : maskDeep(v);
    }
    return out;
  }
  return value;
}

async function main(): Promise<void> {
  const { db, projectId } = initAdmin();
  console.log(`[evidence] project=${projectId} (somente leitura)`);

  const payoutsSnap = await db.doc('config/payouts').get();
  console.log(
    `[evidence] config/payouts RAW=${payoutsSnap.exists ? JSON.stringify(maskDeep(payoutsSnap.data())) : 'AUSENTE'}`,
  );

  const intents = await db
    .collection('withdrawalIntents')
    .orderBy('createdAt', 'desc')
    .limit(5)
    .get();
  console.log(`[evidence] withdrawalIntents count=${intents.size}`);
  for (const doc of intents.docs) {
    console.log(`[evidence] intent ${doc.id} RAW=${JSON.stringify(maskDeep(doc.data()))}`);
  }

  const withdrawals = await db
    .collection('withdrawals')
    .orderBy('createdAt', 'desc')
    .limit(5)
    .get();
  console.log(`[evidence] withdrawals count=${withdrawals.size}`);
  for (const doc of withdrawals.docs) {
    console.log(`[evidence] withdrawal ${doc.id} RAW=${JSON.stringify(maskDeep(doc.data()))}`);
  }

  console.log('[evidence] done');
}

main().catch((err: unknown) => {
  console.error(`[evidence] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
