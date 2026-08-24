/**
 * PlayHash — idempotência de operações econômicas.
 * Dedupe por referenceId/eventId: documentos com IDs determinísticos +
 * verificação de estado anterior antes de qualquer escrita econômica.
 */
import { Firestore } from 'firebase-admin/firestore';

/**
 * Procura uma intenção de compra JÁ concluída para o mesmo
 * (uid, clientRequestId). Retorna o id do intent original ou null.
 */
export async function findDoneIntentByClientRequestId(
  db: Firestore,
  uid: string,
  clientRequestId: string,
): Promise<string | null> {
  const snap = await db
    .collection('purchaseIntents')
    .where('uid', '==', uid)
    .where('clientRequestId', '==', clientRequestId)
    .where('status', '==', 'done')
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0]!.id;
}

/** ID determinístico da transação de reward: um por (bloco, usuário). */
export function txIdFor(periodKey: string, uid: string): string {
  return `${periodKey}_${uid}`;
}
