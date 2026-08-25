/**
 * Fechamento de blocos de 5 minutos (blocks/{periodKey}).
 *
 * periodKey = floor(serverNow / blockIntervalMs). Fecha TODOS os períodos
 * atrasados não finalizados (auto-recuperação de cron atrasado), na ordem.
 * O doc blocks/{periodKey} com status 'finalized' impede reprocessamento.
 *
 * NETWORK_POWER = Σ totalPower (usuários com totalPower > 0).
 * Distribuição via core/precision (BigInt + resíduo determinístico que é
 * carregado para o próximo bloco através de config/economy.residueUnits).
 * Grava transactions/{txId} determinístico e atualiza wallets em batches.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { EconomyConfig } from '../core/types';
import { getEconomyConfig } from '../core/config';
import { toInt, distributeBlockReward, PowerEntry } from '../core/precision';
import { writeAudit, auditEventId } from '../core/audit';
import { txIdFor } from '../core/idempotency';
import { sweepPowerAchievements } from './mission_progress';

interface BlockTotals {
  networkPower: bigint;
  distributedTotal: bigint;
  residueUnits: bigint;
  userCount: number;
}

async function loadUserPowers(
  db: Firestore,
  maxUsers: number,
): Promise<PowerEntry[]> {
  const entries: PowerEntry[] = [];
  let query = db.collection('power').where('totalPower', '>', '0').limit(maxUsers);
  for (;;) {
    const snap = await query.get();
    for (const d of snap.docs) {
      const total = toInt((d.get('totalPower') ?? 0) as number | string);
      if (total > 0n) entries.push({ uid: d.id, power: total });
    }
    if (snap.empty || snap.size < maxUsers || entries.length >= maxUsers) break;
    query = db
      .collection('power')
      .where('totalPower', '>', '0')
      .startAfter(snap.docs[snap.docs.length - 1])
      .limit(maxUsers);
  }
  return entries;
}

/**
 * Credita rewards de um usuário. Idempotente: transactions/{txId} tem ID
 * determinístico — se já existe, o usuário é pulado.
 */
async function creditUsers(
  db: Firestore,
  periodKey: string,
  rewards: Map<string, bigint>,
  currencyId: string,
  ruleVersion: number,
): Promise<number> {
  const uids = [...rewards.keys()];
  const alreadyCredited = new Set<string>();
  // Verifica transações já gravadas para este bloco (crash-recovery).
  for (let i = 0; i < uids.length; i += 100) {
    const chunk = uids.slice(i, i + 100);
    const snap = await db.getAll(
      ...chunk.map((uid) => db.doc(`transactions/${txIdFor(periodKey, uid)}`)),
    );
    for (const d of snap) if (d.exists) alreadyCredited.add(d.id);
  }

  let credited = 0;
  const serverTs = FieldValue.serverTimestamp();
  let batch = db.batch();
  let ops = 0;

  const flush = async () => {
    if (ops > 0) await batch.commit();
    batch = db.batch();
    ops = 0;
  };

  for (const [uid, reward] of [...rewards.entries()].sort()) {
    const txRef = db.doc(`transactions/${txIdFor(periodKey, uid)}`);
    if (alreadyCredited.has(txRef.id)) continue;

    batch.create(txRef, {
      userId: uid,
      type: 'REWARD_BLOCK',
      amount: reward.toString(),
      currencyId,
      source: 'block',
      timestamp: serverTs,
      referenceId: periodKey,
      ruleVersion,
      status: 'COMPLETED',
    });
    ops += 1;

    batch.set(
      db.doc(`wallets/${uid}`),
      {
        uid,
        availableBalance: reward.toString(),
        lifetimeEarned: reward.toString(),
        updatedAt: serverTs,
      },
      { merge: true },
    );
    ops += 1;

    // Auditoria por crédito usa FieldValue direto no doc (append-only).
    batch.create(db.collection('auditLogs').doc(auditEventId('REWARD_CREDITED', `${periodKey}:${uid}`)), {
      eventId: auditEventId('REWARD_CREDITED', `${periodKey}:${uid}`),
      userId: uid,
      type: 'REWARD_CREDITED',
      valueUnits: reward.toString(),
      currencyId,
      referenceId: periodKey,
      origin: 'runner.closeBlocks',
      ruleVersion,
      status: 'SUCCESS',
      timestamp: serverTs,
    });

    // Espelho do histórico no app (rewards/{uid}/items/BLOCK_{periodKey}):
    // leitura owner nas rules; escrita exclusiva do Admin SDK. Id
    // determinístico ⇒ reexecução do bloco não duplica entrada visível.
    batch.set(db.doc(`rewards/${uid}/items/BLOCK_${periodKey}`), {
      type: 'REWARD_BLOCK',
      amount: reward.toString(),
      currencyId,
      createdAt: serverTs,
      referenceId: periodKey,
    });
    ops += 5;

    credited += 1;
    if (ops >= 480) await flush(); // limite de 500 ops/batch
  }
  await flush();
  return credited;
}

/**
 * AUDITORIA DE FONTE (12.23): BLOCK_REWARD vem EXCLUSIVAMENTE de
 * config/economy via getEconomyConfig (closeBlocks → economy.blockRewardUnits).
 * NÃO EXISTE valor de recompensa hardcoded neste processador: o único literal
 * é o currencyId 'coins'. Elegibilidade = totalPower > 0 (loadUserPowers);
 * NETWORK_POWER = Σ totalPower; divisão BigInt floor com resíduo carregado
 * para o próximo bloco; idempotência por periodKey (blocks/{periodKey}
 * 'finalized' + transactions/{txId} determinístico — mesmo bloco nunca 2×).
 */

/**
 * Espelho PÚBLICO do último bloco finalizado (blocks/current) — única fonte
 * da UI de MINERAÇÃO (doc 05 §47/§48): recompensa-base da CONFIG,
 * NETWORK_POWER do bloco e nextBlockAt alinhado ao múltiplo exato de
 * blockIntervalMs do relógio do SERVIDOR (periodKey é epoch-based). O cliente
 * usa estes campos apenas para APRESENTAÇÃO/estimativa — nunca decide valor.
 */
function publicBlockMirror(
  economy: EconomyConfig,
  period: number,
  totals: BlockTotals,
): Record<string, unknown> {
  return {
    periodKey: String(period),
    status: 'finalized',
    // Recompensa-BASE da config (sem resíduo) — "RECOMPENSA DO BLOCO" na UI.
    totalBlockRewardMinimalUnits: economy.blockRewardUnits.toString(),
    networkPower: totals.networkPower.toString(),
    userCount: totals.userCount,
    // Próximo múltiplo do intervalo no tempo do servidor (display apenas).
    nextBlockAt: new Date((period + 1) * economy.blockIntervalMs),
    ruleVersion: economy.economicRuleVersion,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Finaliza UM período. Retorna false se o bloco já estava finalizado. */
export async function finalizePeriod(
  db: Firestore,
  economy: EconomyConfig,
  period: number,
): Promise<boolean> {
  const periodKey = String(period);
  const blockRef = db.doc(`blocks/${periodKey}`);
  const currencyId = 'coins';
  const ruleVersion = economy.economicRuleVersion;

  // 1. Abre/marca o bloco como em processamento (guarda de concorrência).
  const openSnap = await blockRef.get();
  if (openSnap.exists && openSnap.get('status') === 'finalized') return false;

  if (!openSnap.exists) {
    try {
      await blockRef.create({
        periodKey,
        status: 'open',
        baseRewardUnits: economy.blockRewardUnits.toString(),
        carriedResidueUnits: economy.residueUnits.toString(),
        openedAt: FieldValue.serverTimestamp(),
        ruleVersion,
      });
      await writeAudit(db, {
        eventId: auditEventId('BLOCK_CREATED', periodKey),
        userId: null,
        type: 'BLOCK_CREATED',
        valueUnits: economy.blockRewardUnits + economy.residueUnits,
        currencyId,
        referenceId: periodKey,
        origin: 'runner.closeBlocks',
        ruleVersion,
        status: 'SUCCESS',
      });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code !== '6' && code !== 'already-exists') throw err;
    }
  }

  // 2. Coleta poderes e distribui (BigInt, tempo do servidor).
  const users = await loadUserPowers(db, economy.limits.maxUsersPerBlock);
  const effectiveReward = economy.blockRewardUnits + economy.residueUnits;
  const distribution = distributeBlockReward(effectiveReward, users);

  // 2b. Sweep de conquistas de PODER (a_power_100/a_power_1k) a partir do
  // totalPower REAL consolidado. Falha aqui NUNCA impede o fechamento.
  try {
    await sweepPowerAchievements(
      db,
      users.map((u) => ({ uid: u.uid, powerUnits: u.power })),
      economy.powerBasePerHs,
    );
  } catch (err) {
    console.error(`[closeBlocks] powerAchievements sweep failed: ${String((err as Error)?.message ?? err).slice(0, 200)}`);
  }

  // 3. Credita usuários (batches, idempotente por txId).
  await creditUsers(db, periodKey, distribution.rewards, currencyId, ruleVersion);

  // 4. Finaliza o bloco e carrega o resíduo para o próximo (transação).
  const totals: BlockTotals = {
    networkPower: users.reduce((acc, u) => acc + u.power, 0n),
    distributedTotal: distribution.distributedTotal,
    residueUnits: distribution.residueUnits,
    userCount: distribution.rewards.size,
  };
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(blockRef);
    if (fresh.exists && fresh.get('status') === 'finalized') return; // reprocessado por outro runner
    tx.update(blockRef, {
      status: 'finalized',
      networkPower: totals.networkPower.toString(),
      effectiveRewardUnits: effectiveReward.toString(),
      distributedTotalUnits: totals.distributedTotal.toString(),
      residueUnits: totals.residueUnits.toString(),
      userCount: totals.userCount,
      finalizedAt: FieldValue.serverTimestamp(),
      ruleVersion,
    });
    // Resíduo determinístico → próximo bloco + ponteiro de recuperação.
    tx.update(db.doc('config/economy'), {
      residueUnits: totals.residueUnits.toString(),
      lastFinalizedPeriodKey: period,
      updatedAt: FieldValue.serverTimestamp(),
    });
    // Espelho público p/ MINERAÇÃO (leitura autenticada nas rules; escrita
    // SOMENTE Admin SDK). Id fixo 'current' ⇒ sempre reflete o ÚLTIMO bloco.
    tx.set(db.doc('blocks/current'), publicBlockMirror(economy, period, totals));
  });

  await writeAudit(db, {
    eventId: auditEventId('BLOCK_FINALIZED', periodKey),
    userId: null,
    type: 'BLOCK_FINALIZED',
    valueUnits: totals.distributedTotal,
    currencyId,
    referenceId: periodKey,
    origin: 'runner.closeBlocks',
    ruleVersion,
    status: 'SUCCESS',
    detail: {
      userCount: totals.userCount,
      residueUnits: totals.residueUnits.toString(),
    },
  });
  return true;
}

/** Ponto de entrada do runner: fecha todos os períodos atrasados. */
export async function closeBlocks(db: Firestore): Promise<{
  currentPeriod: number;
  closedPeriods: string[];
}> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor
  const currentPeriod = Math.floor(nowMs / economy.blockIntervalMs);

  // Só fecha períodos COMPLETOS (o período corrente ainda está "aberto").
  const stateSnap = await db.doc('config/economy').get();
  const rawLast = stateSnap.get('lastFinalizedPeriodKey');

  // BOOTSTRAP (12.23): ponteiro AUSENTE ⇒ nenhum bloco foi finalizado ainda.
  // O fallback antigo (`?? currentPeriod - 1`) criava um DEADLOCK: o loop
  // partia de currentPeriod e nunca executava, o ponteiro nunca era gravado
  // e NENHUM bloco fechava (observado em produção: closedPeriods=[] sempre).
  // Fix: grava o ponteiro inicial SEM distribuir (evita cunhagem retroativa
  // de horas de blocos acumulados); a partir da próxima fronteira de 5 min
  // os blocos passam a fechar normalmente com o BLOCK_REWARD da config.
  if (rawLast === undefined || rawLast === null) {
    await db.doc('config/economy').set(
      {
        lastFinalizedPeriodKey: currentPeriod - 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    console.log(
      `[closeBlocks] bootstrap lastFinalizedPeriodKey=${currentPeriod - 1} (sem distribuicao retroativa)`,
    );
    return { currentPeriod, closedPeriods: [] };
  }

  const lastFinalized = Number(rawLast);

  const closedPeriods: string[] = [];
  for (let p = lastFinalized + 1; p <= currentPeriod - 1; p++) {
    const ok = await finalizePeriod(db, economy, p);
    if (ok) closedPeriods.push(String(p));
  }
  return { currentPeriod, closedPeriods };
}
