/**
 * PlayHash — auditoria append-only (auditLogs).
 * eventId determinístico (`${type}:${referenceId}`) ⇒ doc.id único:
 * re-execuções NÃO duplicam eventos (create falha se já existe).
 * timestamp SEMPRE do servidor (FieldValue.serverTimestamp).
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { AuditEntry } from './types';

const AUDIT_COLLECTION = 'auditLogs';

/** Chaves sensíveis nunca vão para o audit/detail. */
const FORBIDDEN_DETAIL_KEYS = /token|secret|password|key|credential|jwt/i;

function sanitizeDetail(detail: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(detail)) {
    if (FORBIDDEN_DETAIL_KEYS.test(k)) continue;
    out[k] =
      typeof v === 'bigint' ? v.toString()
      : typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean' ? v
      : String(v);
  }
  return out;
}

export function auditEventId(type: string, referenceId: string): string {
  return `${type}:${referenceId}`;
}

/** Append-only; ignora ALREADY_EXISTS (idempotência). */
export async function writeAudit(db: Firestore, entry: AuditEntry): Promise<void> {
  const data: Record<string, unknown> = {
    eventId: entry.eventId,
    userId: entry.userId,
    type: entry.type,
    referenceId: entry.referenceId,
    origin: entry.origin,
    ruleVersion: entry.ruleVersion,
    status: entry.status,
    timestamp: FieldValue.serverTimestamp(),
  };
  if (entry.valueUnits != null) data.valueUnits = entry.valueUnits.toString();
  if (entry.currencyId != null) data.currencyId = entry.currencyId;
  if (entry.detail && Object.keys(entry.detail).length > 0) {
    data.detail = sanitizeDetail(entry.detail);
  }
  try {
    await db.collection(AUDIT_COLLECTION).doc(entry.eventId).create(data);
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === '6' || code === 'already-exists') return; // já auditado
    throw err;
  }
}
