/**
 * DIAGNÓSTICO SOMENTE LEITURA do gate de saques (prompt 12.8).
 * Imprime estado de config/payouts, últimas withdrawalIntents/withdrawals e
 * chaves de rateLimits relevantes ao gate `dailyQuotaOk` das rules.
 * PRIVACIDADE: e-mails/destinos SEMPRE mascarados; nenhum segredo é lido.
 */
import { initAdmin } from './admin';

function maskEmail(email: string): string {
  const at = email.indexOf('@');
  if (at <= 0) return '*'.repeat(Math.min(email.length, 8));
  return `${email.slice(0, Math.min(2, at))}***@${email.slice(at + 1)}`;
}

async function main(): Promise<void> {
  const { db, projectId } = initAdmin();
  console.log(`[diag] project=${projectId} (somente leitura)`);

  // ---- config/payouts -----------------------------------------------------
  const payoutsSnap = await db.doc('config/payouts').get();
  if (!payoutsSnap.exists) {
    console.log('[diag] config/payouts: AUSENTE');
  } else {
    const d = payoutsSnap.data() ?? {};
    console.log(
      `[diag] config/payouts version=${String(d.version)} destinationType=${String(d.destinationType)} futureRateSource=${String(d.futureRateSource)} cooldownHours=${String(d.cooldownHours)} maxPerDay=${String(d.maxPerDay)} minAccountAgeHours=${String(d.minAccountAgeHours)} requireFinishedGames=${String(d.requireFinishedGames)}`,
    );
    const assets = Array.isArray(d.assets) ? d.assets : [];
    for (const raw of assets) {
      const a = raw as Record<string, unknown>;
      console.log(
        `[diag]   asset id=${String(a.id)} enabled=${String(a.enabled)} network=${String(a.network ?? '')}` +
          ` minWithdrawUnits=${String(a.minWithdrawUnits ?? '')} feeUnits=${String(a.feeUnits ?? '')}` +
          ` minWithdrawCoins=${String(a.minWithdrawCoins ?? '-')} feeCoins=${String(a.feeCoins ?? '-')}` +
          ` litoshiPerCoin=${String(a.litoshiPerCoin ?? '-')} providerMinLitoshi=${JSON.stringify(a.providerMinLitoshi ?? null)}` +
          ` assetUnitPerCoinScaled=${String(a.assetUnitPerCoinScaled ?? '-')}`,
      );
    }
  }

  // ---- últimas withdrawalIntents ------------------------------------------
  const intents = await db
    .collection('withdrawalIntents')
    .orderBy('createdAt', 'desc')
    .limit(5)
    .get();
  console.log(`[diag] withdrawalIntents (últimas ${intents.size}):`);
  for (const doc of intents.docs) {
    const d = doc.data();
    const created = d.createdAt?.toDate?.()?.toISOString?.() ?? '?';
    const email =
      typeof d.destinationEmail === 'string' ? maskEmail(d.destinationEmail) : '-';
    console.log(
      `[diag]   intent id=${doc.id} uid=${String(d.uid ?? '')} asset=${String(d.asset ?? '')}` +
        ` amountUnits=${String(d.amountUnits ?? '')} status=${String(d.status ?? '(pending?)')}` +
        ` failureCode=${String(d.failureCode ?? '-')} email=${email} clientVersion=${String(d.clientVersion ?? '')}` +
        ` createdAt=${created}`,
    );
  }

  // ---- últimos withdrawals -------------------------------------------------
  const withdrawals = await db
    .collection('withdrawals')
    .orderBy('createdAt', 'desc')
    .limit(5)
    .get();
  console.log(`[diag] withdrawals (últimos ${withdrawals.size}):`);
  for (const doc of withdrawals.docs) {
    const d = doc.data();
    const created = d.createdAt?.toDate?.()?.toISOString?.() ?? '?';
    console.log(
      `[diag]   wd id=${doc.id} uid=${String(d.uid ?? '')} asset=${String(d.asset ?? '')}` +
        ` status=${String(d.status ?? '')} errorCode=${String(d.errorCode ?? '-')}` +
        ` destinationMasked=${String(d.destinationMasked ?? '-')} payoutSimulated=${String(d.payoutSimulated ?? '-')}` +
        ` createdAt=${created}`,
    );
  }

  // ---- rateLimits: chaves que afetam o gate dailyQuotaOk das rules ---------
  // Rules usam dayKey() SEM zero-pad ('2026-8-25'); backend usa UTC padded
  // ('2026-08-25'). Se o doc existe mas a chave da rules está ausente,
  // `data[k] < limit` ERRA ⇒ PERMISSION_DENIED no create da intent.
  const limits = await db.collection('rateLimits').limit(20).get();
  const now = new Date();
  const rulesKey = `wi_${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;
  const backendKey = `wi_${now.toISOString().slice(0, 10)}`;
  console.log(
    `[diag] rateLimits docs=${limits.size} rulesKeyHoje=${rulesKey} backendKeyHoje=${backendKey}`,
  );
  for (const doc of limits.docs) {
    const keys = Object.keys(doc.data())
      .filter((k) => k !== 'updatedAt')
      .sort()
      .join(',');
    console.log(`[diag]   rateLimits/${doc.id} keys=[${keys}] hasRulesWiKey=${doc.data()[rulesKey] !== undefined}`);
  }

  console.log('[diag] done');
}

main().catch((err: unknown) => {
  console.error(`[diag] fatal=${String((err as Error)?.message ?? err).slice(0, 300)}`);
  process.exitCode = 1;
});
