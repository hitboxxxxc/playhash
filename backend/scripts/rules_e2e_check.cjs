/**
 * 12.10 — Verificação E2E das Security Rules NO EMULADOR local (auth+firestore).
 * Reproduz o fluxo real do cliente: signUp no emulador de Auth ⇒ ID token ⇒
 * CREATE withdrawalIntents/{id} com os campos EXATOS das rules.
 * Uso: npx firebase emulators:exec --only auth,firestore --project playhash-70742 "node backend/scripts/rules_e2e_check.cjs"
 */
const http = require('http');

function req(url, options, body) {
  return new Promise((resolve, reject) => {
    const r = http.request(url, options, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}

async function main() {
  const PROJECT = 'playhash-70742';
  // 1) Criar usuário no emulador de Auth.
  const signUp = await req(
    `http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:signUp?key=fake-key`,
    { method: 'POST', headers: { 'content-type': 'application/json' } },
    JSON.stringify({ email: 'probe@example.com', password: 'secret123', returnSecureToken: true }),
  );
  const idToken = JSON.parse(signUp.body).idToken;
  if (!idToken) throw new Error(`signUp failed: ${signUp.status} ${signUp.body.slice(0, 200)}`);
  const uid = JSON.parse(signUp.body).localId;

  // 2) CREATE withdrawalIntent com payload EXATO do rulesProbe.
  const fields = {
    fields: {
      uid: { stringValue: uid },
      asset: { stringValue: 'LTC' },
      amountUnits: { integerValue: '20000000' },
      destinationEmail: { stringValue: 'rules.probe@example.com' },
      destinationMasked: { stringValue: 'ru***@example.com' },
      clientRequestId: { stringValue: 'emulatorprobe01' },
      createdAt: { timestampValue: new Date().toISOString() },
      clientVersion: { stringValue: 'rules-probe-1' },
    },
  };
  const create = await req(
    `http://localhost:8080/v1/projects/${PROJECT}/databases/(default)/documents/withdrawalIntents/emulatorprobe01`,
    {
      method: 'PATCH',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${idToken}` },
    },
    JSON.stringify(fields),
  );
  console.log(`[rules-e2e] withdrawalIntents create status=${create.status}`);
  if (create.status !== 200) console.log(`[rules-e2e] body=${create.body.slice(0, 300)}`);
  console.log(create.status === 200 ? '[rules-e2e] RESULT=ALLOW' : '[rules-e2e] RESULT=DENY');
  process.exit(create.status === 200 ? 0 : 1);
}

main().catch((e) => {
  console.error(`[rules-e2e] fatal=${e.message}`);
  process.exit(2);
});
