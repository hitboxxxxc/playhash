/**
 * LEAGUE SWEEP — atribuição de liga por PODER + leaderboard + recompensa diária.
 *
 * Autoridade 100% do backend (docs 03/05): o cliente NUNCA decide liga,
 * nível nem recompensa. A cada execução do runner:
 *  1. Lê power/{uid} (totalPower > 0) e leagues/* (limiares em units BASE);
 *  2. liga = maior tier com minPowerUnits ≤ totalPower (PURE resolveLeagueId);
 *  3. Mudou ⇒ userLeagues/{uid} {leagueId, promotedAt, history[]} + auditoria
 *     LEAGUE_PROMOTED; leaderboards/{leagueId}/entries/{uid} mantido com
 *     maskedName (2 primeiros chars + '***' — NUNCA dados pessoais) e entry
 *     removida da liga anterior;
 *  4. Recompensa diária: se userLeagues.lastDailyGrant != hoje (servidor),
 *     credita dailyRewardUnits da liga (transação idempotente por data),
 *     espelho rewards/{uid}/items e auditoria LEAGUE_REWARD_GRANTED.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { getEconomyConfig } from '../core/config';
import { toInt } from '../core/precision';
import { writeAudit, auditEventId } from '../core/audit';
import { utcDayKey } from '../core/ratelimit';

// ---------------------------------------------------------------------------
// PURE (unit-testável sem Firestore)
// ---------------------------------------------------------------------------

export interface LeagueThreshold {
  id: string;
  name: string;
  tier: number;
  /** Limiar de totalPower em units BASE (H/s × powerBasePerHs). */
  minPowerUnits: bigint;
  /** Recompensa diária em units de coin. */
  dailyRewardUnits: bigint;
}

/**
 * Liga do usuário = MAIOR tier com minPowerUnits ≤ totalPower.
 * Retorna null quando o poder não alcança nenhuma liga (sem liga ainda).
 */
export function resolveLeagueId(
  leagues: LeagueThreshold[],
  totalPowerUnits: bigint,
): string | null {
  let best: LeagueThreshold | null = null;
  for (const l of leagues) {
    if (l.minPowerUnits <= 0n) continue; // limiar inválido nunca atribui
    if (totalPowerUnits >= l.minPowerUnits) {
      if (best === null || l.tier > best.tier) best = l;
    }
  }
  return best?.id ?? null;
}

/**
 * Máscara SEGURA para o leaderboard: 2 primeiros caracteres + '***'.
 * Sem nome ⇒ '??***' (nunca expõe uid/e-mail).
 */
export function maskedName(displayName: string | null | undefined): string {
  const trimmed = (displayName ?? '').trim();
  if (trimmed.length === 0) return '??***';
  return `${trimmed.slice(0, 2).toUpperCase()}***`;
}

/** Chave de auditoria da promoção (determinística por uid+liga). */
export function promotionEventId(uid: string, leagueId: string): string {
  return auditEventId('LEAGUE_PROMOTED', `${uid}:${leagueId}`);
}

/** Chave de auditoria da diária (determinística por uid+dia ⇒ idempotente). */
export function dailyGrantEventId(uid: string, dayKey: string): string {
  return auditEventId('LEAGUE_REWARD_GRANTED', `${uid}:${dayKey}`);
}

// ---------------------------------------------------------------------------
// Sweep (Firestore/admin)
// ---------------------------------------------------------------------------

interface LoadedLeague extends LeagueThreshold {
  color: string;
}

async function loadLeagues(db: Firestore): Promise<LoadedLeague[]> {
  const snap = await db.collection('leagues').get();
  const out: LoadedLeague[] = [];
  for (const doc of snap.docs) {
    const min = Number(doc.get('minPowerUnits'));
    const reward = Number(doc.get('dailyRewardUnits'));
    const tier = Number(doc.get('tier'));
    if (!Number.isSafeInteger(min) || min <= 0) continue;
    if (!Number.isSafeInteger(reward) || reward <= 0) continue;
    out.push({
      id: doc.id,
      name: String(doc.get('name') ?? doc.id),
      tier: Number.isSafeInteger(tier) ? tier : 0,
      minPowerUnits: BigInt(min),
      dailyRewardUnits: BigInt(reward),
      color: String(doc.get('color') ?? ''),
    });
  }
  out.sort((a, b) => a.tier - b.tier);
  return out;
}

/** Paginação idêntica ao closeBlocks (proteção de cota Spark). */
async function loadUserPowers(
  db: Firestore,
  maxUsers: number,
): Promise<{ uid: string; totalPower: bigint }[]> {
  const entries: { uid: string; totalPower: bigint }[] = [];
  let query = db.collection('power').where('totalPower', '>', '0').limit(maxUsers);
  for (;;) {
    const snap = await query.get();
    for (const d of snap.docs) {
      const total = toInt((d.get('totalPower') ?? 0) as number | string);
      if (total > 0n) entries.push({ uid: d.id, totalPower: total });
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

async function loadDisplayNames(
  db: Firestore,
  uids: string[],
): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  for (let i = 0; i < uids.length; i += 100) {
    const chunk = uids.slice(i, i + 100);
    const snaps = await db.getAll(...chunk.map((uid) => db.doc(`users/${uid}`)));
    for (const s of snaps) {
      const name = s.get('displayName');
      if (typeof name === 'string' && name.trim().length > 0) map.set(s.id, name);
    }
  }
  return map;
}

export interface LeagueSweepSummary {
  scanned: number;
  assigned: number;
  promoted: number;
  leaderboardUpdated: number;
  dailyGranted: number;
  failed: number;
}

async function sweepUser(
  db: Firestore,
  leagues: LoadedLeague[],
  uid: string,
  totalPower: bigint,
  displayName: string | undefined,
  dayKey: string,
  ruleVersion: number,
  summary: LeagueSweepSummary,
): Promise<void> {
  const leagueId = resolveLeagueId(leagues, totalPower);
  if (leagueId === null) return; // abaixo do menor limiar ⇒ sem liga ainda
  const league = leagues.find((l) => l.id === leagueId)!;

  const userLeagueRef = db.doc(`userLeagues/${uid}`);
  const before = await userLeagueRef.get();
  const previousLeagueId =
    before.exists && typeof before.get('leagueId') === 'string'
      ? String(before.get('leagueId'))
      : '';

  if (previousLeagueId !== leagueId) {
    // Atribuição/promoção: history append-only (arrayUnion ⇒ idempotente na
    // reexecução do MESMO par uid+liga porque a auditoria é determinística e
    // o estado final converge — history pode repetir em re-promoções reais).
    await userLeagueRef.set(
      {
        uid,
        leagueId,
        leagueName: league.name,
        previousLeagueId: previousLeagueId || FieldValue.delete(),
        promotedAt: FieldValue.serverTimestamp(),
        history: FieldValue.arrayUnion({
          leagueId,
          at: new Date().toISOString().slice(0, 10),
        }),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeAudit(db, {
      eventId: promotionEventId(uid, leagueId),
      userId: uid,
      type: 'LEAGUE_PROMOTED',
      valueUnits: totalPower,
      currencyId: 'power',
      referenceId: leagueId,
      origin: 'runner.leagueSweep',
      ruleVersion,
      status: 'SUCCESS',
      detail: { previousLeagueId },
    });
    summary.assigned += 1;
    if (previousLeagueId.length > 0) summary.promoted += 1;
  }

  // Leaderboard da liga atual (maskedName — nunca dados pessoais).
  await db
    .doc(`leaderboards/${leagueId}/entries/${uid}`)
    .set({
      uid,
      maskedName: maskedName(displayName),
      totalPower: totalPower.toString(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  summary.leaderboardUpdated += 1;

  // Entry da liga ANTIGA sai do ranking anterior.
  if (previousLeagueId.length > 0 && previousLeagueId !== leagueId) {
    await db.doc(`leaderboards/${previousLeagueId}/entries/${uid}`).delete();
  }

  // Recompensa diária — idempotente por data do SERVIDOR (transação).
  const already = before.exists ? before.get('lastDailyGrant') : undefined;
  if (already === dayKey) return;
  const walletRef = db.doc(`wallets/${uid}`);
  const granted = await db.runTransaction(async (tx): Promise<boolean> => {
    const fresh = await tx.get(userLeagueRef);
    if (fresh.exists && fresh.get('lastDailyGrant') === dayKey) return false;
    const walletSnap = await tx.get(walletRef);
    const balance = walletSnap.exists
      ? toInt((walletSnap.get('availableBalance') ?? 0) as number | string)
      : 0n;
    tx.set(
      walletRef,
      {
        uid,
        availableBalance: (balance + league.dailyRewardUnits).toString(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      userLeagueRef,
      { lastDailyGrant: dayKey, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return true;
  });
  if (!granted) return;

  await writeAudit(db, {
    eventId: dailyGrantEventId(uid, dayKey),
    userId: uid,
    type: 'LEAGUE_REWARD_GRANTED',
    valueUnits: league.dailyRewardUnits,
    currencyId: 'coins',
    referenceId: dayKey,
    origin: 'runner.leagueSweep',
    ruleVersion,
    status: 'SUCCESS',
    detail: { leagueId },
  });
  await db
    .doc(`rewards/${uid}/items/LEAGUE_DAILY_${dayKey}`)
    .create({
      type: 'LEAGUE_REWARD',
      amount: league.dailyRewardUnits.toString(),
      currencyId: 'coins',
      createdAt: FieldValue.serverTimestamp(),
      referenceId: dayKey,
    });
  summary.dailyGranted += 1;
}

/** Ponto de entrada do runner. */
export async function leagueSweep(db: Firestore): Promise<LeagueSweepSummary> {
  const economy = await getEconomyConfig(db);
  const nowMs = Date.now(); // tempo SOMENTE do servidor
  const dayKey = utcDayKey(nowMs);
  const ruleVersion = economy.economicRuleVersion;

  const summary: LeagueSweepSummary = {
    scanned: 0,
    assigned: 0,
    promoted: 0,
    leaderboardUpdated: 0,
    dailyGranted: 0,
    failed: 0,
  };

  const leagues = await loadLeagues(db);
  if (leagues.length === 0) return summary; // catálogo ausente ⇒ no-op seguro

  const users = await loadUserPowers(db, economy.limits.maxUsersPerBlock);
  summary.scanned = users.length;
  const names = await loadDisplayNames(
    db,
    users.map((u) => u.uid),
  );

  for (const u of users) {
    try {
      await sweepUser(
        db,
        leagues,
        u.uid,
        u.totalPower,
        names.get(u.uid),
        dayKey,
        ruleVersion,
        summary,
      );
    } catch (err) {
      summary.failed += 1;
      console.error(
        `[leagueSweep] uid=<redacted> failed: ${String((err as Error)?.message ?? err).slice(0, 200)}`,
      );
    }
  }
  return summary;
}
