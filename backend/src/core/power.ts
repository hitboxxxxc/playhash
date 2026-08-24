/**
 * PlayHash — poder (power/{uid} + tempGrants/{grantId}).
 *
 * totalPower = permanentPower + Σ grants NÃO expirados (tempo do SERVIDOR).
 * Grants expirados são marcados (expired=true) e auditados
 * (GAME_POWER_EXPIRED). Todos os valores BigInt são persistidos como string.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { GrantRecord, TempGrantData } from './types';
import { toInt } from './precision';
import { writeAudit, auditEventId } from './audit';

function toMillis(v: unknown): number {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return Number(v) || 0;
  const t = v as { toMillis?: () => number; seconds?: string };
  if (typeof t.toMillis === 'function') return t.toMillis();
  if (t.seconds != null) return Number(t.seconds) * 1000;
  return 0;
}

export function isGrantActive(g: GrantRecord, nowMs: number): boolean {
  return !g.expired && g.expiresAtMs > nowMs && g.powerAmount > 0n;
}

export function computeTotalPower(
  permanentPower: bigint,
  grants: GrantRecord[],
  nowMs: number,
): bigint {
  let total = permanentPower > 0n ? permanentPower : 0n;
  for (const g of grants) {
    if (isGrantActive(g, nowMs)) total += g.powerAmount;
  }
  return total;
}

/** Carrega tempGrants do usuário (limite de segurança: 200 docs). */
export async function loadGrants(db: Firestore, uid: string): Promise<GrantRecord[]> {
  const snap = await db
    .collection('tempGrants')
    .where('uid', '==', uid)
    .limit(200)
    .get();
  return snap.docs.map((d) => ({
    grantId: d.id,
    uid: String(d.get('uid') ?? uid),
    powerAmount: toInt((d.get('powerAmount') ?? 0) as number | string),
    source: 'game' as const,
    acquiredAtMs: toMillis(d.get('acquiredAt')),
    expiresAtMs: toMillis(d.get('expiresAt')),
    gameId: d.get('gameId') ?? undefined,
    gameSessionId: d.get('gameSessionId') ?? undefined,
    economicRuleVersion: Number(d.get('economicRuleVersion') ?? 1),
    expired: d.get('expired') === true,
  }));
}

/**
 * Cria o grant temporário. Idempotente: usa doc id determinístico
 * (por padrão o próprio gameSessionId) — create() falha se já existe.
 * Retorna false quando o grant já existia.
 */
export async function createTempGrant(
  db: Firestore,
  grant: TempGrantData & { grantId: string },
): Promise<boolean> {
  try {
    await db.doc(`tempGrants/${grant.grantId}`).create({
      uid: grant.uid,
      powerAmount: grant.powerAmount.toString(),
      source: grant.source,
      acquiredAt: new Date(grant.acquiredAtMs),
      expiresAt: new Date(grant.expiresAtMs),
      ...(grant.gameId ? { gameId: grant.gameId } : {}),
      ...(grant.gameSessionId ? { gameSessionId: grant.gameSessionId } : {}),
      economicRuleVersion: grant.economicRuleVersion,
      expired: false,
    });
    return true;
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === '6' || code === 'already-exists') return false;
    throw err;
  }
}

/**
 * Recalcula e persiste power/{uid}:
 * 1. marca grants expirados (expired=true) + auditoria GAME_POWER_EXPIRED;
 * 2. totalPower = permanentPower + Σ grants ativos (tempo do servidor);
 * 3. grava power/{uid} {permanentPower, totalPower, updatedAt, ruleVersion}.
 */
export async function recalcPower(
  db: Firestore,
  uid: string,
  nowMs: number,
  ctx: { ruleVersion: number; origin: string },
): Promise<bigint> {
  const [grants, powerSnap] = await Promise.all([
    loadGrants(db, uid),
    db.doc(`power/${uid}`).get(),
  ]);

  let permanentPower = 0n;
  if (powerSnap.exists) {
    permanentPower = toInt((powerSnap.get('permanentPower') ?? 0) as number | string);
  }

  // Expira grants vencidos (marcação lazy pelo servidor).
  const stale = grants.filter((g) => !g.expired && g.expiresAtMs <= nowMs);
  for (const g of stale) {
    await db.doc(`tempGrants/${g.grantId}`).update({ expired: true });
    await writeAudit(db, {
      eventId: auditEventId('GAME_POWER_EXPIRED', g.grantId),
      userId: uid,
      type: 'GAME_POWER_EXPIRED',
      valueUnits: g.powerAmount,
      referenceId: g.grantId,
      origin: ctx.origin,
      ruleVersion: ctx.ruleVersion,
      status: 'SUCCESS',
      detail: { gameSessionId: g.gameSessionId ?? '' },
    });
  }

  const total = computeTotalPower(permanentPower, grants, nowMs);
  await db.doc(`power/${uid}`).set(
    {
      uid,
      permanentPower: permanentPower.toString(),
      totalPower: total.toString(),
      economicRuleVersion: ctx.ruleVersion,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return total;
}
