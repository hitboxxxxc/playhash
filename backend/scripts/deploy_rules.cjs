/**
 * Deploy de firestore.rules via API Firebaserules usando a service account
 * local (backend/.secrets/serviceAccount.json ou GOOGLE_APPLICATION_CREDENTIALS).
 * Uso: node scripts/deploy_rules.cjs [caminho-do-firestore.rules]
 * NUNCA loga credenciais.
 */
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

function resolveKeyPath() {
  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (fromEnv && fromEnv.trim().length > 0) return fromEnv;
  return path.join(__dirname, '..', '.secrets', 'serviceAccount.json');
}

async function main() {
  const keyPath = resolveKeyPath();
  if (!fs.existsSync(keyPath)) {
    console.error('SERVICE_ACCOUNT_KEY_NOT_FOUND');
    process.exitCode = 1;
    return;
  }
  const sa = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  const projectId = sa.project_id;
  const rulesPath =
    process.argv[2] || path.join(__dirname, '..', '..', 'firestore.rules');
  const source = fs.readFileSync(rulesPath, 'utf8');

  const auth = new GoogleAuth({
    keyFile: keyPath,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const base = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;

  // 1) Cria o ruleset
  const createRes = await client.request({
    url: `${base}/rulesets`,
    method: 'POST',
    data: {
      source: { files: [{ name: 'firestore.rules', content: source }] },
    },
  });
  const rulesetName = createRes.data.name;
  console.log(`[deploy-rules] ruleset created: ${rulesetName.split('/').pop()}`);

  // 2) Atualiza a release "cloud.firestore" para apontar ao novo ruleset
  const releaseRes = await client.request({
    url: `${base}/releases/cloud.firestore`,
    method: 'PATCH',
    data: { rulesetName },
  });
  console.log(
    `[deploy-rules] release updated: ${releaseRes.data.name} -> ${releaseRes.data.rulesetName.split('/').pop()}`,
  );
  console.log('[deploy-rules] OK');
}

main().catch((err) => {
  const msg = String(err?.response?.data?.error?.message ?? err?.message ?? err);
  console.error(`[deploy-rules] FAILED=${msg.slice(0, 300)}`);
  process.exitCode = 1;
});
