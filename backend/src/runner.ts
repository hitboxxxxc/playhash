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
import { FaucetPayProvider, decimalToUnits } from './providers/faucetpay_provider';

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
): Promise<{ executed: boolean; keyValid?: boolean }> {
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

  // v3: mínimo REAL do envio INTERNO por e-mail (LTC/litoshi). Quando a API
  // expõe o mínimo, compara com o providerMinLitoshi da config e recomenda
  // ajuste de minWithdrawCoins — o AJUSTE é registrado no relatório (a edição
  // da config continua sendo ação humana/seed).
  const ltcCfg = payouts.getAsset('LTC');
  if (ltcCfg) {
    const cfgMin = ltcCfg.providerMinLitoshi;
    console.log(
      `[runner] payoutProbe ltc providerMinLitoshi(config)=${cfgMin ?? 'null'}` +
        ` minWithdrawCoins=${ltcCfg.minWithdrawUnits / 1_000_000n}`,
    );
    if (fees.ok) {
      const ltcFee = fees.data.find((f) => f.asset.toUpperCase() === 'LTC');
      if (ltcFee?.minUnits !== undefined) {
        console.log(`[runner] payoutProbe ltc providerMinLitoshi(real)=${ltcFee.minUnits}`);
        if (cfgMin === null || ltcFee.minUnits > cfgMin) {
          console.log(
            '[runner] payoutProbe RECOMMENDATION: mínimo REAL > config — ajustar ' +
              'providerMinLitoshi/minWithdrawCoins em config/payouts (seed v3) e relatar.',
          );
        }
      } else {
        console.log(
          '[runner] payoutProbe ltc providerMinLitoshi(real)=UNAVAILABLE ' +
            '(API não expõe mínimo do envio interno)',
        );
      }
    }
  }
  return { executed: true, keyValid: true };
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
