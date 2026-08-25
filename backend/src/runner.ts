/**
 * Runner econômico — ÚNICA autoridade econômica do PlayHash.
 * Executa os 3 processadores em ordem, com isolamento de erro entre eles
 * (falha em um não impede os outros) e log SEM dados sensíveis.
 *
 * Executado por GitHub Actions (cron a cada 5 min + workflow_dispatch).
 *
 * Ação especial `devTopUp` (workflow_dispatch): credita saldo de teste no uid
 * informado SOMENTE quando a repo variable ENV == "dev" (env APP_ENV).
 * Em ENV != dev é no-op com log claro — nunca roda em produção.
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { initAdmin } from './admin';
import { processGameSessions } from './processors/processGameSessions';
import { processPurchaseIntents } from './processors/processPurchaseIntents';
import { processAdRewards } from './processors/processAdRewards';
import { processClaims } from './processors/processClaims';
import { closeBlocks } from './processors/closeBlocks';
import { leagueSweep } from './processors/league_sweep';
import { processSeasonProgress } from './processors/season_progress';
import {
  processWithdrawals,
  getPayoutsConfig,
  maskAddress,
  PayoutAssetConfig,
} from './processors/processWithdrawals';
import { getEconomyConfig } from './core/config';
import { toInt } from './core/precision';
import { writeAudit, auditEventId } from './core/audit';
import { utcDayKey } from './core/ratelimit';
import {
  applyProbeMinimum,
  FALLBACK_PROVIDER_MIN_LITOSHI,
} from './core/payoutsUpgrade';
import { FaucetPayProvider, decimalToUnits } from './providers/faucetpay_provider';

/** Web API key PÚBLICA do Firebase (vai no APK/google-services.json; não é segredo). */
const FIREBASE_WEB_API_KEY_DEFAULT = 'AIzaSyBvCZihaRu6Zrwf9BdZheadQw1Bsdto1JE';

type Processor = { name: string; run: (db: Firestore) => Promise<unknown> };

function sanitize(err: unknown): string {
  // Apenas a mensagem, truncada — sem stack (pode conter paths/dados).
  return String((err as Error)?.message ?? err).slice(0, 300);
}

/**
 * Serialização segura para log: converte BigInt para string em vez de
 * lançar "Do not know how to serialize a BigInt" (que marcava o
 * processador como FAILED mesmo após sucesso econômico).
 */
export function serializeForLog(value: unknown): string {
  return JSON.stringify(value, (_key, v: unknown) =>
    typeof v === 'bigint' ? v.toString() : v,
  );
}

/** Lê a ação do workflow: env RUNNER_ACTION ou argv --action=... */
export function readAction(argv: string[] = process.argv): string {
  const fromArg = argv.find((a) => a.startsWith('--action='))?.split('=')[1];
  return String(process.env.RUNNER_ACTION ?? fromArg ?? 'run').trim();
}

export interface DevTopUpOptions {
  uid: string;
  amountCoins: bigint;
  env: string;
}

/**
 * Crédito de saldo de DESENVOLVIMENTO.
 * Gate: SOMENTE executa com env === 'dev' (repo variable ENV). Auditoria
 * DEV_TOPUP com eventId determinístico (uid+dia+valor) ⇒ reexecução no mesmo
 * dia com o mesmo valor é no-op (idempotente).
 */
export async function runDevTopUp(
  db: Firestore,
  opts: DevTopUpOptions,
): Promise<{ credited: boolean; amountUnits: bigint }> {
  if (opts.env !== 'dev') {
    console.log(
      `[runner] devTopUp SKIP: requer repo variable ENV=dev (atual='${opts.env}'). Nada foi alterado.`,
    );
    return { credited: false, amountUnits: 0n };
  }
  if (!opts.uid) throw new Error('DEV_TOPUP_UID_MISSING');

  const economy = await getEconomyConfig(db);
  const amountUnits = opts.amountCoins * BigInt(economy.coinPrecision);
  const eventId = auditEventId(
    'DEV_TOPUP',
    `${opts.uid}:${utcDayKey(Date.now())}:${opts.amountCoins}`,
  );

  await db.runTransaction(async (tx) => {
    const walletRef = db.doc(`wallets/${opts.uid}`);
    const snap = await tx.get(walletRef);
    const balance = snap.exists
      ? toInt((snap.get('availableBalance') ?? 0) as number | string)
      : 0n;
    tx.set(
      walletRef,
      {
        uid: opts.uid,
        availableBalance: (balance + amountUnits).toString(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  await writeAudit(db, {
    eventId,
    userId: opts.uid,
    type: 'DEV_TOPUP',
    valueUnits: amountUnits,
    currencyId: 'coins',
    referenceId: eventId.split(':')[1] ?? opts.uid,
    origin: 'runner.devTopUp',
    ruleVersion: economy.economicRuleVersion,
    status: 'SUCCESS',
    detail: { amountCoins: opts.amountCoins.toString(), env: opts.env },
  });
  console.log(
    `[runner] devTopUp ok uid=<redacted> coins=${opts.amountCoins} (auditoria determinística)`,
  );
  return { credited: true, amountUnits };
}

/**
 * payoutProbe — VALIDAÇÃO READ-ONLY da integração FaucetPay.
 * Chama SOMENTE endpoints de leitura (balance/fees) com o secret; NUNCA
 * envia payout e NUNCA loga a chave. Gate: exige ENV=dev (repo variable);
 * qualquer PAYOUT_MODE é aceito (probe não depende do modo).
 */
export async function runPayoutProbe(
  db: Firestore,
  opts: { env: string },
): Promise<{
  executed: boolean;
  keyValid?: boolean;
  providerMinLitoshi?: number;
  wroteProviderMin?: boolean;
}> {
  if (opts.env !== 'dev') {
    console.log(
      `[runner] payoutProbe SKIP: requer repo variable ENV=dev (atual='${opts.env}'). Nada foi executado.`,
    );
    return { executed: false };
  }
  let provider: FaucetPayProvider;
  try {
    provider = new FaucetPayProvider();
  } catch (err) {
    console.error(`[runner] payoutProbe FAILED=${sanitize(err)}`);
    return { executed: true, keyValid: false };
  }

  // Ativos habilitados + decimais vêm da config/payouts (autoridade backend).
  const payouts = await getPayoutsConfig(db);
  const queries = Object.values(payouts.assets)
    .filter((a) => a.enabled)
    .map((a) => ({ id: a.id, decimals: a.assetDecimals }));

  const balances = await provider.getBalances(queries);
  if (!balances.ok) {
    // detailMsg = mensagem do provedor sanitizada (tokens longos redigidos).
    console.error(
      `[runner] payoutProbe balance FAILED=${balances.errorCode}` +
        (balances.detailMsg ? ` msg="${balances.detailMsg}"` : ''),
    );
    return { executed: true, keyValid: balances.errorCode !== 'INVALID_CREDENTIALS' };
  }
  console.log('[runner] payoutProbe key=VALID');
  for (const b of balances.data) {
    console.log(`[runner] payoutProbe balance asset=${b.asset} units=${b.balanceUnits}`);
  }

  const fees = await provider.getFees();
  if (!fees.ok) {
    // Taxas são best-effort: saldo já provou a chave; não falha o probe.
    console.log(`[runner] payoutProbe fees UNAVAILABLE=${fees.errorCode}`);
  } else {
    for (const f of fees.data) {
      const min = f.minUnits !== undefined ? ` min=${f.minUnits}` : '';
      console.log(`[runner] payoutProbe fee asset=${f.asset} feeUnits=${f.feeUnits}${min}`);
    }
  }

  // v3/12.10: mínimo REAL do envio INTERNO por e-mail (LTC/litoshi). Quando a
  // API expõe o mínimo, usa-o; caso contrário grava o fallback conservador
  // (FALLBACK_PROVIDER_MIN_LITOSHI = líquido do saque mínimo da plataforma).
  // Escrita SEMPRE via MERGE SEGURO (applyProbeMinimum): nunca ABAIXA um
  // mínimo já confirmado e nunca envia payout.
  const ltcCfg = payouts.getAsset('LTC');
  if (!ltcCfg) return { executed: true, keyValid: true };

  const cfgMin = ltcCfg.providerMinLitoshi;
  console.log(
    `[runner] payoutProbe ltc providerMinLitoshi(config)=${cfgMin ?? 'null'}` +
      ` minWithdrawCoins=${ltcCfg.minWithdrawUnits / 1_000_000n}`,
  );
  const ltcBalance = balances.data.find((b) => b.asset.toUpperCase() === 'LTC');
  if (ltcBalance) {
    const s = ltcBalance.balanceUnits.toString();
    const masked = s.length <= 2 ? '*'.repeat(s.length) : `${s[0]}*${'*'.repeat(Math.max(s.length - 2, 1))}${s[s.length - 1]}`;
    console.log(`[runner] payoutProbe ltc saldoDisponivelMasked=${masked} units`);
  }
  const ltcFee = fees.ok
    ? fees.data.find((f) => f.asset.toUpperCase() === 'LTC')
    : undefined;
  if (fees.ok && ltcFee) {
    const min = ltcFee.minUnits !== undefined ? ` min=${ltcFee.minUnits}` : '';
    console.log(`[runner] payoutProbe ltc taxaEnvioInterno feeUnits=${ltcFee.feeUnits}${min}`);
  } else {
    console.log('[runner] payoutProbe fees UNAVAILABLE (taxas best-effort; saldo já provou a chave)');
  }

  const apiMinRaw = ltcFee?.minUnits;
  const apiMin = apiMinRaw === undefined ? undefined : Number(apiMinRaw);
  const candidate = apiMin ?? FALLBACK_PROVIDER_MIN_LITOSHI;
  const source = apiMin !== undefined ? 'api' : 'fallback_plataforma';
  console.log(
    `[runner] payoutProbe ltc providerMinLitoshi(real)=${candidate} source=${source}`,
  );
  const cfgMinNum = cfgMin === null ? null : Number(cfgMin);
  if (cfgMinNum !== null && candidate <= cfgMinNum) {
    console.log('[runner] payoutProbe WRITE SKIP: config já possui mínimo >= candidato');
    return {
      executed: true,
      keyValid: true,
      providerMinLitoshi: cfgMinNum,
      wroteProviderMin: false,
    };
  }
  const payoutsRef = db.doc('config/payouts');
  const rawSnap = await payoutsRef.get();
  await payoutsRef.set(applyProbeMinimum(rawSnap.data() ?? null, candidate), { merge: true });
  console.log(
    `[runner] payoutProbe WRITE OK providerMinLitoshi=${candidate} source=${source} (merge seguro em config/payouts v4)`,
  );
  return { executed: true, keyValid: true, providerMinLitoshi: candidate, wroteProviderMin: true };
}

/**
 * rulesProbe (12.10) — VERIFICAÇÃO das Security Rules publicadas.
 * Simula EXATAMENTE o cliente: cria custom token admin ⇒ troca por ID token
 * real (Identity Toolkit REST) ⇒ tenta CRIAR uma withdrawalIntents válida via
 * Firestore REST com credenciais DE USUÁRIO (Admin SDK bypassaria as rules).
 *  - 200 ⇒ rules publicadas e gate de saque operante;
 *  - 403 ⇒ PERMISSION_DENIED — rules ainda não publicadas corretamente.
 * Limpeza: intent de teste removida + usuário probe excluído (admin).
 */
export async function runRulesProbe(
  db: Firestore,
  opts: { env: string },
): Promise<{ executed: boolean; ok?: boolean }> {
  if (opts.env !== 'dev') {
    console.log(
      `[runner] rulesProbe SKIP: requer repo variable ENV=dev (atual='${opts.env}'). Nada foi executado.`,
    );
    return { executed: false };
  }
  const { projectId } = initAdmin();
  const auth = getAuth();
  const uid = `rulesprobe${Date.now().toString(36)}`;
  const requestId = `probe${Date.now().toString(36)}ok`;
  try {
    const customToken = await auth.createCustomToken(uid);
    const webKey =
      String(process.env.FIREBASE_WEB_API_KEY ?? '').trim() || FIREBASE_WEB_API_KEY_DEFAULT;

    // 1) Custom token ⇒ ID token de USUÁRIO real (como o app faz).
    const exRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webKey}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token: customToken, returnSecureToken: true }),
      },
    );
    const exBody = (await exRes.json().catch(() => null)) as { idToken?: string } | null;
    const idToken = exBody?.idToken;
    if (!idToken) throw new Error('CUSTOM_TOKEN_EXCHANGE_FAILED');

    // 2) CREATE withdrawalIntent com campos EXATOS exigidos pelas rules.
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      `/databases/(default)/documents/withdrawalIntents/${requestId}`;
    const createRes = await fetch(url, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${idToken}` },
      body: JSON.stringify({
        fields: {
          uid: { stringValue: uid },
          asset: { stringValue: 'LTC' },
          amountUnits: { integerValue: '20000000' }, // 20 COIN (mínimo)
          destinationEmail: { stringValue: 'rules.probe@example.com' },
          destinationMasked: { stringValue: 'ru***@example.com' },
          clientRequestId: { stringValue: requestId },
          createdAt: { timestampValue: new Date().toISOString() },
          clientVersion: { stringValue: 'rules-probe-1' },
        },
      }),
    });
    if (createRes.ok) {
      console.log(
        `[runner] rulesProbe OK: withdrawalIntent criada como CLIENTE (rules publicadas) intentId=${requestId}`,
      );
    } else {
      const status = createRes.status;
      const code = status === 403 ? 'PERMISSION_DENIED' : `HTTP_${status}`;
      // Diagnóstico diferencial com o MESMO token de usuário:
      //  a) leitura config/economy — OK ⇒ autenticação/rules ATIVAS;
      //  b) CREATE claims/{id} — existe em rulesets desde cedo; OK +
      //     withdrawalIntents NEGADA ⇒ ruleset publicado é ANTERIOR ao bloco
      //     v3 de saques (precisa republicar firestore.rules atual).
      let diagRead = 'SKIPPED';
      let diagClaim = 'SKIPPED';
      try {
        const diagRes = await fetch(
          `https://firestore.googleapis.com/v1/projects/${projectId}` +
            `/databases/(default)/documents/config/economy`,
          { headers: { authorization: `Bearer ${idToken!}` } },
        );
        diagRead = diagRes.ok ? 'OK' : `HTTP_${diagRes.status}`;
      } catch {
        diagRead = 'NETWORK_ERROR';
      }
      try {
        const claimRes = await fetch(
          `https://firestore.googleapis.com/v1/projects/${projectId}` +
            `/databases/(default)/documents/claims/${requestId}`,
          {
            method: 'PATCH',
            headers: { 'content-type': 'application/json', authorization: `Bearer ${idToken!}` },
            body: JSON.stringify({
              fields: {
                uid: { stringValue: uid },
                kind: { stringValue: 'mission' },
                refId: { stringValue: 'rules-probe' },
                clientRequestId: { stringValue: requestId },
                createdAt: { timestampValue: new Date().toISOString() },
                status: { stringValue: 'pending' },
              },
            }),
          },
        );
        diagClaim = claimRes.ok ? 'OK' : `HTTP_${claimRes.status}`;
      } catch {
        diagClaim = 'NETWORK_ERROR';
      }
      console.error(
        `[runner] rulesProbe FAILED=${code} diagReadConfigEconomy=${diagRead}` +
          ` diagCreateClaim=${diagClaim} — ` +
          (diagRead !== 'OK'
            ? 'rules ainda não publicadas corretamente'
            : diagClaim === 'OK'
              ? 'rules ATIVAS mas SEM o bloco withdrawalIntents v3 (republicar firestore.rules)'
              : 'rules ATIVAS mas regra de withdrawalIntents nega (comparar versão publicada vs firestore.rules)'),
      );
      return { executed: true, ok: false };
    }
    return { executed: true, ok: true };
  } catch (err) {
    console.error(`[runner] rulesProbe FAILED=${sanitize(err)}`);
    return { executed: true, ok: false };
  } finally {
    // 3) Limpeza (admin): intent de teste + usuário probe. Nunca crasha.
    await db.doc(`withdrawalIntents/${requestId}`).delete().catch(() => undefined);
    await db.doc(`claims/${requestId}`).delete().catch(() => undefined);
    await auth.deleteUser(uid).catch(() => undefined);
  }
}

export interface PayoutLiveTestOptions {
  payoutMode: string;
  asset: string;
  address: string;
  /** Valor DECIMAL em unidades inteiras do ativo (ex.: "0.0001"). Vazio ⇒ usa providerMin da config. */
  amountDecimal: string;
}

/**
 * payoutLiveTest — MICRO-TESTE REAL (OPCIONAL, default NÃO executa).
 * Exige PAYOUT_MODE=live + inputs explícitos (asset/endereço do DONO/amount).
 * NÃO reserva saldo de usuário (usa a conta do provedor); auditoria
 * WITHDRAWAL_TEST; falha ⇒ log seguro, sem crash, sem estorno.
 */
export async function runPayoutLiveTest(
  db: Firestore,
  opts: PayoutLiveTestOptions,
): Promise<{ executed: boolean; status?: string; providerReference?: string }> {
  const mode = opts.payoutMode.trim().toLowerCase();
  if (mode !== 'live') {
    console.log(
      `[runner] payoutLiveTest SKIP: requer repo variable PAYOUT_MODE=live (atual='${mode || 'test'}'). Nada foi enviado.`,
    );
    return { executed: false };
  }
  if (!opts.asset || !opts.address) {
    console.error('[runner] payoutLiveTest FAILED=PAYOUT_TEST_INPUTS_MISSING');
    return { executed: false };
  }

  // Decimais + mínimo real vêm da config/payouts v2 (autoridade backend).
  const payouts = await getPayoutsConfig(db);
  const cfg: PayoutAssetConfig | undefined = payouts.getAsset(opts.asset);
  const decimals = cfg?.assetDecimals ?? 8;
  let amountUnits: bigint | null;
  if (opts.amountDecimal.trim()) {
    amountUnits = decimalToUnits(opts.amountDecimal, decimals);
  } else {
    amountUnits = cfg && cfg.providerMinAssetUnits > 0n ? cfg.providerMinAssetUnits : null;
  }
  if (amountUnits === null || amountUnits <= 0n) {
    console.error('[runner] payoutLiveTest FAILED=INVALID_AMOUNT');
    return { executed: false };
  }

  let provider: FaucetPayProvider;
  try {
    provider = new FaucetPayProvider();
  } catch (err) {
    console.error(`[runner] payoutLiveTest FAILED=${sanitize(err)}`);
    return { executed: false };
  }

  const referenceId = `livetest-${Date.now()}`;
  try {
    const result = await provider.sendPayout({
      asset: opts.asset,
      network: cfg?.network ?? '',
      address: opts.address,
      amountUnits,
    });
    await writeAudit(db, {
      eventId: auditEventId('WITHDRAWAL_TEST', referenceId),
      userId: 'owner',
      type: 'WITHDRAWAL_TEST',
      referenceId,
      origin: 'runner.payoutLiveTest',
      ruleVersion: payouts.version,
      status: result.status === 'completed' ? 'SUCCESS' : 'FAILED',
      detail: {
        asset: opts.asset,
        amountUnits: amountUnits.toString(),
        errorCode: result.errorCode,
        providerReference: result.providerReference,
        addressMasked: maskAddress(opts.address),
        payoutSimulated: false,
      },
    });
    if (result.status === 'completed') {
      console.log(
        `[runner] payoutLiveTest completed ref=${result.providerReference} addr=<masked>`,
      );
      return { executed: true, status: 'completed', providerReference: result.providerReference };
    }
    console.error(`[runner] payoutLiveTest failed code=${result.errorCode ?? 'PROVIDER_ERROR'}`);
    return { executed: true, status: 'failed' };
  } catch (err) {
    // Nunca crasha: log seguro e saída controlada.
    console.error(`[runner] payoutLiveTest FAILED=${sanitize(err)}`);
    return { executed: true, status: 'failed' };
  }
}

async function main(): Promise<void> {
  const startedAt = Date.now();
  const { db, projectId } = initAdmin();
  const action = readAction();
  console.log(`[runner] start project=${projectId} action=${action}`);

  if (action === 'devTopUp') {
    const amountRaw = process.env.DEV_TOPUP_COINS ?? '5000';
    const amountCoins = BigInt(/^\d+$/.test(amountRaw) ? amountRaw : '5000');
    try {
      await runDevTopUp(db, {
        uid: String(process.env.DEV_TOPUP_UID ?? '').trim(),
        amountCoins,
        env: String(process.env.APP_ENV ?? '').trim().toLowerCase(),
      });
      console.log(`[runner] done in ${Date.now() - startedAt}ms`);
      process.exitCode = 0;
    } catch (err) {
      console.error(`[runner] devTopUp FAILED=${sanitize(err)}`);
      process.exitCode = 1;
    }
    return;
  }

  if (action === 'payoutProbe') {
    try {
      await runPayoutProbe(db, {
        env: String(process.env.APP_ENV ?? '').trim().toLowerCase(),
      });
      console.log(`[runner] done in ${Date.now() - startedAt}ms`);
      process.exitCode = 0;
    } catch (err) {
      console.error(`[runner] payoutProbe FAILED=${sanitize(err)}`);
      process.exitCode = 1;
    }
    return;
  }

  if (action === 'rulesProbe') {
    try {
      await runRulesProbe(db, {
        env: String(process.env.APP_ENV ?? '').trim().toLowerCase(),
      });
      console.log(`[runner] done in ${Date.now() - startedAt}ms`);
      process.exitCode = 0;
    } catch (err) {
      console.error(`[runner] rulesProbe FAILED=${sanitize(err)}`);
      process.exitCode = 1;
    }
    return;
  }

  if (action === 'payoutLiveTest') {
    try {
      await runPayoutLiveTest(db, {
        payoutMode: String(process.env.PAYOUT_MODE ?? 'test'),
        asset: String(process.env.PAYOUT_TEST_ASSET ?? '').trim().toUpperCase(),
        address: String(process.env.PAYOUT_TEST_ADDRESS ?? '').trim(),
        amountDecimal: String(process.env.PAYOUT_TEST_AMOUNT ?? '').trim(),
      });
      // Falha do micro-teste NÃO derruba o job (sem crash); auditoria registra.
      process.exitCode = 0;
    } catch (err) {
      console.error(`[runner] payoutLiveTest FAILED=${sanitize(err)}`);
      process.exitCode = 1;
    }
    console.log(`[runner] done in ${Date.now() - startedAt}ms`);
    return;
  }

  // Ordem: eventos de origem (sessões → compras) ANTES de claims (o claim
  // valida o progresso mais recente); em seguida o XP da temporada (consome
  // os flags seasonXpApplied de sessões/claims), o fechamento de blocos
  // (sweep de poder usa o totalPower já recalculado) e por fim o sweep de
  // LIGAS (atribuição + leaderboard + diária com o poder consolidado).
  const processors: Processor[] = [
    { name: 'gameSessions', run: processGameSessions },
    { name: 'purchaseIntents', run: processPurchaseIntents },
    // Recompensas por anúncio ANTES de claims/seasonProgress: o xpBonus do
    // adReward entra no seasonProgress antes do fechamento de blocos.
    { name: 'adRewards', run: processAdRewards },
    { name: 'claims', run: processClaims },
    { name: 'seasonProgress', run: processSeasonProgress },
    { name: 'closeBlocks', run: closeBlocks },
    { name: 'leagueSweep', run: leagueSweep },
    // Saques por último: payout externo (provider) consome tempo do job e
    // depende de saldos já consolidados pelos processadores anteriores.
    { name: 'withdrawals', run: processWithdrawals },
  ];

  let failures = 0;
  for (const p of processors) {
    try {
      const result = await p.run(db);
      console.log(`[runner] ${p.name} ok=${serializeForLog(result)}`);
    } catch (err) {
      failures += 1;
      console.error(`[runner] ${p.name} FAILED=${sanitize(err)}`);
    }
  }

  console.log(`[runner] done in ${Date.now() - startedAt}ms failures=${failures}`);
  process.exitCode = failures > 0 ? 1 : 0;
}

// Executa apenas quando invocado diretamente (não em imports de teste).
if (require.main === module) {
  main().catch((err) => {
    console.error(`[runner] fatal=${sanitize(err)}`);
    process.exitCode = 1;
  });
}
