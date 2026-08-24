/**
 * PlayHash — rate limit diário (rateLimits/{uid}).
 * Contadores por dia UTC, incrementados SOMENTE pelo backend (admin).
 * As security rules consultam estes contadores na criação de intents.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';

/** Chave de dia UTC: yyyy-MM-dd. */
export function utcDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

export function counterKey(prefix: string, nowMs: number): string {
  return `${prefix}_${utcDayKey(nowMs)}`;
}

async function readCounter(
  db: Firestore,
  uid: string,
  key: string,
): Promise<number> {
  const snap = await db.doc(`rateLimits/${uid}`).get();
  return Number(snap.get(key) ?? 0);
}

/** Lê o contador do dia sem incrementar (para checagem prévia). */
export async function readDailyCounter(
  db: Firestore,
  uid: string,
  prefix: string,
  nowMs: number,
): Promise<number> {
  return readCounter(db, uid, counterKey(prefix, nowMs));
}

/**
 * Incrementa atomicamente o contador diário e retorna o novo valor.
 * Executada pelo runner APÓS processar cada item com sucesso.
 */
export async function incrementDailyCounter(
  db: Firestore,
  uid: string,
  prefix: string,
  nowMs: number,
): Promise<number> {
  const key = counterKey(prefix, nowMs);
  const ref = db.doc(`rateLimits/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = Number(snap.get(key) ?? 0);
    const next = current + 1;
    tx.set(ref, { [key]: next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return next;
  });
}
