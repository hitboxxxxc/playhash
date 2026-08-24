/**
 * Inicialização do Firebase Admin SDK.
 *
 * Credenciais (NUNCA no repositório):
 *  1. GOOGLE_APPLICATION_CREDENTIALS (GitHub Actions / CI) — caminho do JSON;
 *  2. backend/.secrets/serviceAccount.json (local, gitignored).
 */
import * as fs from 'fs';
import * as path from 'path';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Firestore } from 'firebase-admin/firestore';

export interface AdminContext {
  db: Firestore;
  projectId: string;
}

function resolveKeyPath(): string {
  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (fromEnv && fromEnv.trim().length > 0) return fromEnv;
  // dist/admin.js -> ../.secrets => backend/.secrets
  return path.join(__dirname, '..', '.secrets', 'serviceAccount.json');
}

export function initAdmin(): AdminContext {
  const existing = getApps();
  if (existing.length > 0) {
    const app = existing[0]!;
    return { db: getFirestore(app), projectId: app.options.projectId ?? '' };
  }

  const keyPath = resolveKeyPath();
  if (!fs.existsSync(keyPath)) {
    throw new Error(
      'SERVICE_ACCOUNT_KEY_NOT_FOUND: defina GOOGLE_APPLICATION_CREDENTIALS ' +
        'ou coloque a chave em backend/.secrets/serviceAccount.json (gitignored)',
    );
  }

  const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8')) as {
    project_id: string;
    client_email: string;
    private_key: string;
  };

  const app = initializeApp({
    credential: cert({
      projectId: serviceAccount.project_id,
      clientEmail: serviceAccount.client_email,
      privateKey: serviceAccount.private_key,
    }),
    projectId: serviceAccount.project_id,
  });

  return { db: getFirestore(app), projectId: serviceAccount.project_id };
}
