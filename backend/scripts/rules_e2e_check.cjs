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
  // 1) Criar usuário no emulador de Auth (tenta rota com projeto; fallback
  //    rota legada sem prefixo de projeto).
  const signUpBody = JSON.stringify({
    email: 'probe@example.com',
    password: 'secret123',
    returnSecureToken: true,
  });
  const signUpOpts = { method: 'POST', headers: { 'content-type': 'application/json' } };
  let signUp = await req(
    `http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:signUp?key=fake-key`,
    signUpOpts,
    signUpBody,
  );
  if (signUp.status === 404) {
    signUp = await req(
      'http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key',
      signUpOpts,
      signUpBody,
    );
  }
  const parsed = JSON.parse(signUp.body);
  const idToken = parsed.idToken;
  if (!idToken) throw new Error(`signUp failed: ${signUp.status} ${signUp.body.slice(0, 200)}`);
  const uid = parsed.localId || 'emulator-user';

  // 2) CREATE withdrawalIntent — caso VÁLIDO deve ALLOW; inválidos devem DENY.
  const base = `http://localhost:8080/v1/projects/${PROJECT}/databases/(default)/documents/withdrawalIntents`;
  const headers = { 'content-type': 'application/json', authorization: `Bearer ${idToken}` };
  const mk = (over) => ({
    fields: {
      uid: { stringValue: uid },
      asset: { stringValue: 'LTC' },
      amountUnits: { integerValue: '20000000' },
      destinationEmail: { stringValue: 'rules.probe@example.com' },
      destinationMasked: { stringValue: 'ru***@example.com' },
      clientRequestId: { stringValue: 'emulatorprobe01' },
      createdAt: { timestampValue: new Date().toISOString() },
      clientVersion: { stringValue: 'rules-probe-1' },
      ...over,
    },
  });
  const cases = [
    { name: 'valido', expect: 200, fields: mk({}) },
    {
      name: 'email_invalido',
      expect: 403,
      fields: mk({ destinationEmail: { stringValue: 'sem-arroba' } }),
    },
    {
      name: 'mask_sem_***',
      expect: 403,
      fields: mk({ destinationMasked: { stringValue: 'ru@@example.com' } }),
    },
    {
      name: 'uid_alheio',
      expect: 403,
      fields: mk({ uid: { stringValue: 'outra-pessoa' } }),
    },
  ];
  let failed = 0;
  for (const c of cases) {
    const id = `emu-${c.name}-0001`;
    const res = await req(`${base}/${id}`, { method: 'PATCH', headers }, JSON.stringify(c.fields));
    const ok = res.status === c.expect;
    if (!ok) failed += 1;
    console.log(
      `[rules-e2e] ${ok ? 'PASS' : 'FAIL'} ${c.name}: status=${res.status} esperado=${c.expect}`,
    );
    if (!ok && res.status !== c.expect) console.log(`[rules-e2e] body=${res.body.slice(0, 300)}`);
  }
  console.log(failed === 0 ? '[rules-e2e] RESULT=ALL_PASS' : `[rules-e2e] RESULT=${failed} FAILURES`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(`[rules-e2e] fatal=${e.message}`);
  process.exit(2);
});
