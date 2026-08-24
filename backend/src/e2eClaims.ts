/**
 * E2E DEV (one-off) — valida o fluxo completo de missões/claims contra o
 * Firestore real do projeto dev: sessão finished (com kills) → progresso de
 * missões/conquistas → claim válido (crédito auditado) → claim inválido
 * (falha segura) → idempotência (re-execução não duplica).
 * NÃO usar em produção. Log sem dados sensíveis (uids truncados).
 */
import { FieldValue } from 'firebase-admin/firestore';
import { initAdmin } from './admin';
import { processGameSessions } from './processors/processGameSessions';
import { processClaims } from './processors/processClaims';

function short(v: string | null | undefined): string {
  return v ? `${v.slice(0, 6)}…` : 'null';
}

async function main(): Promise<void> {
  const { db } = initAdmin();

  // 1. Usuário real (dev): users → gameSessions → power → wallets.
  let uid: string | null = null;
  for (const col of ['users', 'gameSessions', 'power', 'wallets'] as const) {
    const snap = await db.collection(col).limit(1).get();
    if (!snap.empty) {
      const candidate = col === 'gameSessions' ? snap.docs[0]!.get('uid') : snap.docs[0]!.id;
      if (typeof candidate === 'string' && candidate.length > 0) {
        uid = candidate;
        break;
      }
    }
  }
  if (!uid) throw new Error('E2E_NO_USER');
  console.log(`[e2e] uid=${short(uid)}`);

  const walletRef = db.doc(`wallets/${uid}`);
  const before = (await walletRef.get()).get('availableBalance') ?? '0';
  console.log(`[e2e] wallet antes=${before}`);

  // 2. Sessão finished REAL (60s, score 3000, 15 kills — 15×150=2250 ≤ 3000).
  const now = Date.now();
  const sessionRef = db.collection('gameSessions').doc();
  await sessionRef.set({
    uid,
    gameId: 'nova-swarm',
    startedAt: new Date(now - 60_000),
    finishedAt: new Date(now),
    status: 'finished',
    processed: false,
    score: 3000,
    kills: 15,
    clientVersion: 'e2e-claims',
  });
  console.log(`[e2e] session=${sessionRef.id} criada (score=3000 kills=15)`);

  // 3. Runner: processa a sessão → progresso.
  const s = await processGameSessions(db);
  console.log(`[e2e] processGameSessions=${JSON.stringify(s)}`);

  const items = await db.collection(`userMissions/${uid}/items`).get();
  const progress = (id: string): string =>
    items.docs.find((d) => d.id === id)?.get('progress')?.toString() ?? 'ausente';
  console.log(`[e2e] m_daily_play3.progress=${progress('m_daily_play3')} (esperado 1)`);
  console.log(`[e2e] m_daily_points2k.progress=${progress('m_daily_points2k')} (esperado 3000)`);
  console.log(`[e2e] m_daily_kills30.progress=${progress('m_daily_kills30')} (esperado 15)`);
  const ach = await db.collection(`userAchievements/${uid}/items`).get();
  const aProgress = (id: string): string =>
    ach.docs.find((d) => d.id === id)?.get('progress')?.toString() ?? 'ausente';
  console.log(`[e2e] a_first_match.progress=${aProgress('a_first_match')} (esperado 1)`);
  console.log(`[e2e] a_kills_100.progress=${aProgress('a_kills_100')} (esperado 15)`);

  // 4. Claim VÁLIDO (m_daily_points2k: 3000 ≥ 2000) → +150 coins.
  const claimOk = db.collection('claims').doc('e2e-claim-ok-12345678');
  await claimOk.set({
    uid,
    kind: 'mission',
    refId: 'm_daily_points2k',
    clientRequestId: 'e2e-claim-ok-12345678',
    createdAt: FieldValue.serverTimestamp(),
    status: 'pending',
  });
  // 5. Claim INVÁLIDO (m_daily_play3: progresso 1 < 3) → falha segura.
  const claimBad = db.collection('claims').doc('e2e-claim-bad-12345678');
  await claimBad.set({
    uid,
    kind: 'mission',
    refId: 'm_daily_play3',
    clientRequestId: 'e2e-claim-bad-12345678',
    createdAt: FieldValue.serverTimestamp(),
    status: 'pending',
  });

  const c1 = await processClaims(db);
  console.log(`[e2e] processClaims #1=${JSON.stringify(c1)} (esperado granted=1 rejected=1)`);

  const after1 = (await walletRef.get()).get('availableBalance') ?? '0';
  console.log(`[e2e] wallet depois=${after1} (esperado antes + 150000000)`);
  console.log(`[e2e] claimOk.status=${(await claimOk.get()).get('status')} (esperado claimed)`);
  console.log(
    `[e2e] claimBad.status=${(await claimBad.get()).get('failureCode')} (esperado CLAIM_PROGRESS_INSUFFICIENT)`,
  );
  const mirror = await db.doc(`rewards/${uid}/items/CLAIM_e2e-claim-ok-12345678`).get();
  console.log(`[e2e] espelho rewards existe=${mirror.exists} amount=${mirror.get('amount')}`);

  // 6. Idempotência: re-execução NÃO duplica crédito.
  const c2 = await processClaims(db);
  const after2 = (await walletRef.get()).get('availableBalance') ?? '0';
  console.log(`[e2e] processClaims #2=${JSON.stringify(c2)} (esperado sem granted)`);
  console.log(`[e2e] wallet inalterada=${after1 === after2}`);

  const audit = await db.collection('auditLogs')
    .where('type', '==', 'MISSION_REWARD_GRANTED')
    .limit(5).get();
  console.log(`[e2e] auditoria MISSION_REWARD_GRANTED docs=${audit.size}`);

  console.log('[e2e] done');
}

main().catch((err) => {
  console.error(`[e2e] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
