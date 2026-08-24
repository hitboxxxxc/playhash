/**
 * Garante que os índices compostos exigidos pelos processadores existam no
 * Firestore ANTES do runner executar (doc backend.md §índices).
 *
 * - Idempotente: índice já existente (409 ALREADY_EXISTS) = sucesso.
 * - Aguarda o estado READY das operações de criação (timeout limitado).
 * - Usa GOOGLE_APPLICATION_CREDENTIALS (service account do workflow).
 * - Nenhum segredo é impresso no log.
 *
 * Executado pelo GitHub Actions antes de `node dist/runner.js`.
 */
import { credential } from 'firebase-admin';

const BASE =
  'https://firestore.googleapis.com/v1/projects';

interface IndexField {
  fieldPath: string;
  order: 'ASCENDING' | 'DESCENDING';
}

interface IndexSpec {
  collectionGroup: string;
  fields: IndexField[];
}

/** Espelho declarativo de firestore.indexes.json (fonte da verdade dupla). */
export const INDEX_SPECS: readonly IndexSpec[] = [
  {
    collectionGroup: 'gameSessions',
    fields: [
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'processed', order: 'ASCENDING' },
      { fieldPath: 'finishedAt', order: 'ASCENDING' },
    ],
  },
  {
    collectionGroup: 'purchaseIntents',
    fields: [
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'createdAt', order: 'ASCENDING' },
    ],
  },
] as const;

const CREATE_TIMEOUT_MS = 180_000;
const POLL_INTERVAL_MS = 3_000;

function projectId(): string {
  const id =
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCLOUD_PROJECT ??
    process.env.GCP_PROJECT;
  if (!id) throw new Error('ENSURE_INDEXES_NO_PROJECT_ID');
  return id;
}

async function accessToken(): Promise<string> {
  const c = credential.applicationDefault();
  const tok = await c.getAccessToken();
  if (!tok.access_token) throw new Error('ENSURE_INDEXES_NO_TOKEN');
  return tok.access_token;
}

async function sleep(ms: number): Promise<void> {
  await new Promise((r) => setTimeout(r, ms));
}

/** Cria UM índice se não existir. Retorna 'created' | 'exists'. */
export async function ensureIndex(
  authHeader: string,
  project: string,
  spec: IndexSpec,
): Promise<'created' | 'exists'> {
  const url =
    `${BASE}/${project}/databases/(default)/collectionGroups/` +
    `${spec.collectionGroup}/indexes`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: authHeader,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      queryScope: 'COLLECTION',
      fields: spec.fields,
    }),
  });

  if (res.status === 409) return 'exists'; // ALREADY_EXISTS — idempotente
  if (!res.ok) {
    const body = await res.text();
    throw new Error(
      `ENSURE_INDEXES_CREATE_FAILED:${spec.collectionGroup}:${res.status}:${body.slice(0, 200)}`,
    );
  }

  // Operação assíncrona → aguarda até READY/done.
  const op = (await res.json()) as { name?: string; done?: boolean };
  const deadline = Date.now() + CREATE_TIMEOUT_MS;
  let operation = op;
  while (!operation.done && Date.now() < deadline) {
    await sleep(POLL_INTERVAL_MS);
    const opRes = await fetch(`${BASE}/${operation.name}`, {
      headers: { Authorization: authHeader },
    });
    if (!opRes.ok) {
      throw new Error(
        `ENSURE_INDEXES_POLL_FAILED:${spec.collectionGroup}:${opRes.status}`,
      );
    }
    operation = (await opRes.json()) as typeof op;
  }
  if (!operation.done) {
    throw new Error(`ENSURE_INDEXES_TIMEOUT:${spec.collectionGroup}`);
  }

  // Erro dentro da operação concluída (ex.: permissão)?
  const err = (operation as { error?: { message?: string } }).error;
  if (err) {
    // Conflito tardio = outro processo criou o mesmo índice.
    if (res.status === 409 || /ALREADY_EXISTS/i.test(err.message ?? '')) {
      return 'exists';
    }
    throw new Error(
      `ENSURE_INDEXES_OP_ERROR:${spec.collectionGroup}:${String(err.message).slice(0, 200)}`,
    );
  }
  return 'created';
}

async function main(): Promise<void> {
  const project = projectId();
  const token = await accessToken();
  const authHeader = `Bearer ${token}`;
  console.log(`[ensureIndexes] start project=${project}`);

  let created = 0;
  let existing = 0;
  for (const spec of INDEX_SPECS) {
    const outcome = await ensureIndex(authHeader, project, spec);
    console.log(
      `[ensureIndexes] ${spec.collectionGroup} (${spec.fields.map((f) => f.fieldPath).join(',')}) -> ${outcome}`,
    );
    if (outcome === 'created') created += 1;
    else existing += 1;
  }
  console.log(`[ensureIndexes] done created=${created} existing=${existing}`);
}

// Executa apenas quando invocado diretamente (não em imports de teste).
if (require.main === module) {
  main().catch((err) => {
    console.error(`[ensureIndexes] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
    process.exitCode = 1;
  });
}
