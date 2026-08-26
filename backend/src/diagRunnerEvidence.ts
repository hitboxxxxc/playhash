/**
 * DIAGNÓSTICO (12.x) — EVIDÊNCIA CRUA SOMENTE LEITURA do runner.
 * Imprime (mascarado): últimas gameSessions (qualquer status), power/{uid},
 * últimos blocks, wallets, userMissions e profiles stats.
 * NENHUM segredo; uids mascarados (4 primeiros + ***).
 */
import { initAdmin } from './admin';

function maskId(id: string): string {
  return id.length <= 4 ? '****' : `${id.slice(0, 4)}***`;
}

function maskDeep(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(maskDeep);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = /email|address/i.test(k) && typeof v === 'string'
        ? `${v.slice(0, 2)}***`
        : maskDeep(v);
    }
    return out;
  }
  return value;
}

function ts(v: unknown): string {
  const t = v as { toMillis?: () => number } | undefined;
  if (t && typeof t.toMillis === 'function') return new Date(t.toMillis()).toISOString();
  if (typeof v === 'number') return new Date(v).toISOString();
  return String(v ?? 'null');
}

async function main(): Promise<void> {
  const { db, projectId } = initAdmin();
  console.log(`[diag] project=${projectId} (somente leitura)`);

  // 1) Últimas 8 gameSessions (QUALQUER status/processed) — desc order finishedAt.
  let sessions;
  try {
    sessions = await db
      .collection('gameSessions')
      .orderBy('finishedAt', 'desc')
      .limit(8)
      .get();
  } catch {
    sessions = await db.collection('gameSessions').limit(8).get();
  }
  console.log(`[diag] gameSessions total(last8)=${sessions.size}`);
  for (const d of sessions.docs) {
    const x = d.data();
    console.log(
      `[diag] session id=${maskId(d.id)} uid=${maskId(String(x.uid ?? ''))} ` +
        `game=${String(x.gameId ?? '')} status=${String(x.status ?? '')} ` +
        `processed=${String(x.processed ?? '')} score=${String(x.score ?? '')} ` +
        `startedAt=${ts(x.startedAt)} finishedAt=${ts(x.finishedAt)} ` +
        `serverResult=${JSON.stringify(maskDeep(x.serverResult ?? null))}`,
    );
  }

  // Contagem por status/processed (queries separadas — sem índice composto).
  for (const status of ['open', 'finished']) {
    const q = await db.collection('gameSessions').where('status', '==', status).get();
    const unprocessed = q.docs.filter((d) => d.get('processed') === false).length;
    console.log(`[diag] gameSessions status=${status} count=${q.size} unprocessed=${unprocessed}`);
  }

  // 2) power/{uid} — todos (coleção pequena em dev).
  const powers = await db.collection('power').limit(10).get();
  console.log(`[diag] power docs=${powers.size}`);
  for (const d of powers.docs) {
    const x = d.data();
    console.log(
      `[diag] power uid=${maskId(d.id)} totalPower=${String(x.totalPower ?? '')} ` +
        `temporaryPower=${String(x.temporaryPower ?? '')} expiresAt=${ts(x.expiresAt)} ` +
        `updatedAt=${ts(x.updatedAt)}`,
    );
  }

  // 3) Últimos 5 blocks.
  const blocks = await db
    .collection('blocks')
    .orderBy('periodKey', 'desc')
    .limit(5)
    .get();
  console.log(`[diag] blocks last5=${blocks.size}`);
  for (const d of blocks.docs) {
    const x = d.data();
    console.log(
      `[diag] block periodKey=${d.id} processed=${String(x.processed ?? '')} ` +
        `totalPower=${String(x.totalPowerSnapshot ?? x.totalPower ?? '')} ` +
        `serverTimestamp=${ts(x.serverTimestamp ?? x.closedAt ?? x.createdAt)}`,
    );
  }

  // 4) Wallets dos uids com sessões (ou todos, até 10).
  const wallets = await db.collection('wallets').limit(10).get();
  console.log(`[diag] wallets docs=${wallets.size}`);
  for (const d of wallets.docs) {
    const x = d.data();
    console.log(
      `[diag] wallet uid=${maskId(d.id)} availableBalance=${String(x.availableBalance ?? '')} ` +
        `lifetimeEarned=${String(x.lifetimeEarned ?? '')}`,
    );
  }

  // 5) userMissions de um uid com partidas (primeiro uid de session/power).
  let targetUid: string | null = null;
  if (sessions.size > 0) targetUid = String(sessions.docs[0].get('uid') ?? '') || null;
  if (!targetUid && powers.size > 0) targetUid = powers.docs[0].id;
  if (targetUid) {
    const um = await db.collection(`userMissions/${targetUid}/missions`).limit(20).get().catch(
      () => null,
    );
    if (um) {
      console.log(`[diag] userMissions uid=${maskId(targetUid)} docs=${um.size}`);
      for (const d of um.docs) {
        const x = d.data();
        console.log(
          `[diag] mission ${d.id} progress=${String(x.progress ?? '')} ` +
            `goal=${String(x.goal ?? x.target ?? '')} claimed=${String(x.claimed ?? '')}`,
        );
      }
    } else {
      console.log(`[diag] userMissions uid=${maskId(targetUid)} COLEÇÃO AUSENTE/ERRO`);
    }

    // 6) Profile stats do mesmo uid.
    const prof = await db.doc(`profiles/${targetUid}`).get();
    console.log(
      `[diag] profile uid=${maskId(targetUid)} exists=${prof.exists} ` +
        `RAW=${prof.exists ? JSON.stringify(maskDeep(prof.data())) : '-'}`,
    );

    // 7) tempGrants do uid.
    const tg = await db
      .collection(`power/${targetUid}/grants`)
      .orderBy('expiresAt', 'desc')
      .limit(5)
      .get()
      .catch(() => null);
    if (tg) {
      console.log(`[diag] grants uid=${maskId(targetUid)} docs=${tg.size}`);
      for (const d of tg.docs) {
        const x = d.data();
        console.log(
          `[diag] grant ${maskId(d.id)} powerAmount=${String(x.powerAmount ?? '')} ` +
            `acquiredAt=${ts(x.acquiredAt)} expiresAt=${ts(x.expiresAt)} expired=${String(x.expired ?? '')}`,
        );
      }
    }
  } else {
    console.log('[diag] nenhum uid alvo para missions/profile/grants');
  }

  console.log('[diag] done');
}

main().catch((err: unknown) => {
  console.error(`[diag] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
