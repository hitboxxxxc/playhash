/**
 * 12.10 — FINGERPRINT do ruleset PUBLICADO em produção (somente leitura de
 * comportamento; cria docs de teste e os remove ao final).
 * Cria (como usuário real, via custom token ⇒ ID token ⇒ Firestore REST):
 *   - users/{uid}            (existe desde o início das rules)
 *   - gameSessions/{id}      (existe desde o início; exige games/{id} habilitado)
 *   - adRewardIntents/{id}   (era dos anúncios)
 *   - claims/{id}            (era missões/conquistas)
 *   - withdrawalIntents/{id} (v3 saques por e-mail)
 * O padrão OK/DENIED por coleção identifica QUAL versão está publicada.
 * Uso: node backend/scripts/rules_fingerprint.cjs   (usa backend/.secrets)
 */
const path = require('path');
const fs = require('fs');
const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));

const PROJECT = 'playhash-70742';
const KEY_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(__dirname, '..', '.secrets', 'serviceAccount.json');

async function main() {
  const serviceAccount = JSON.parse(fs.readFileSync(KEY_PATH, 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId: PROJECT });
  const db = admin.firestore();
  const auth = admin.auth();

  const uid = `fingerprint${Date.now().toString(36)}`;
  const id0 = `fp${Date.now().toString(36)}a`;
  const now = new Date().toISOString();

  // gameId real e habilitado p/ gameSessions.
  const gamesSnap = await db.collection('games').where('enabled', '==', true).limit(1).get();
  const gameId = gamesSnap.empty ? null : gamesSnap.docs[0].id;

  const customToken = await auth.createCustomToken(uid);
  const webKey = 'AIzaSyBvCZihaRu6Zrwf9BdZheadQw1Bsdto1JE';
  const exRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webKey}`,
    { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: customToken, returnSecureToken: true }) },
  );
  const idToken = (await exRes.json()).idToken;
  if (!idToken) throw new Error(`token exchange failed: ${exRes.status}`);

  const base = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
  const headers = { 'content-type': 'application/json', authorization: `Bearer ${idToken}` };

  const attempts = [
    {
      name: 'users',
      url: `${base}/users/${uid}`,
      fields: {
        displayName: { stringValue: 'Fingerprint Probe' },
        createdAt: { timestampValue: now },
        status: { stringValue: 'active' },
      },
    },
    {
      name: 'gameSessions',
      url: `${base}/gameSessions/${id0}`,
      fields: gameId
        ? {
            uid: { stringValue: uid },
            gameId: { stringValue: gameId },
            startedAt: { timestampValue: now },
            clientVersion: { stringValue: 'fingerprint-1' },
            status: { stringValue: 'open' },
          }
        : null,
    },
    {
      name: 'adRewardIntents',
      url: `${base}/adRewardIntents/${id0}`,
      fields: {
        uid: { stringValue: uid },
        type: { stringValue: 'rewarded' },
        adUnitId: { stringValue: 'fingerprint-probe' },
        clientRequestId: { stringValue: id0 },
        createdAt: { timestampValue: now },
        clientVersion: { stringValue: 'fingerprint-1' },
      },
    },
    {
      name: 'claims',
      url: `${base}/claims/${id0}`,
      fields: {
        uid: { stringValue: uid },
        kind: { stringValue: 'mission' },
        refId: { stringValue: 'fingerprint-probe' },
        clientRequestId: { stringValue: id0 },
        createdAt: { timestampValue: now },
        status: { stringValue: 'pending' },
      },
    },
    {
      name: 'withdrawalIntents',
      url: `${base}/withdrawalIntents/${id0}`,
      fields: {
        uid: { stringValue: uid },
        asset: { stringValue: 'LTC' },
        amountUnits: { integerValue: '20000000' },
        destinationEmail: { stringValue: 'rules.probe@example.com' },
        destinationMasked: { stringValue: 'ru***@example.com' },
        clientRequestId: { stringValue: id0 },
        createdAt: { timestampValue: now },
        clientVersion: { stringValue: 'fingerprint-1' },
      },
    },
  ];

  const results = {};
  for (const a of attempts) {
    if (!a.fields) {
      results[a.name] = 'SKIPPED(no enabled game)';
      continue;
    }
    const res = await fetch(a.url, { method: 'PATCH', headers, body: JSON.stringify({ fields: a.fields }) });
    results[a.name] = res.status === 200 ? 'OK' : `DENIED(HTTP_${res.status})`;
  }

  console.log(`[fingerprint] results=${JSON.stringify(results)}`);
  console.log(
    '[fingerprint] leitura: withdrawalIntents DENIED com claims/adRewardIntents OK ⇒ ruleset publicado é ANTERIOR ao bloco v3 de saques.',
  );

  // Limpeza (admin).
  await Promise.all(
    [
      db.doc(`users/${uid}`).delete(),
      db.doc(`gameSessions/${id0}`).delete(),
      db.doc(`adRewardIntents/${id0}`).delete(),
      db.doc(`claims/${id0}`).delete(),
      db.doc(`withdrawalIntents/${id0}`).delete(),
    ].map((p) => p.catch(() => undefined)),
  );
  await auth.deleteUser(uid).catch(() => undefined);
  process.exit(0);
}

main().catch((e) => {
  console.error(`[fingerprint] fatal=${e.message}`);
  process.exit(1);
});
