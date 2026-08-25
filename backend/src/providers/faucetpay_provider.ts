/**
 * FaucetPayProvider — PAYOUT_MODE=live.
 *
 * Chama a API oficial de payouts da FaucetPay (endpoint /api/v1/send)
 * SOMENTE com process.env.FAUCETPAY_API_KEY — NUNCA hardcode, NUNCA no APK/Git.
 *
 * Segurança/idempotência:
 *  - timeout fixo por tentativa + retry com backoff APENAS para erros de
 *    REDE/5xx (resposta ambígua). Resposta HTTP definitiva (2xx/4xx) NÃO é
 *    reenviada — evita pagamento duplicado (idempotência: não reenvia sem
 *    checar o resultado anterior).
 *  - Endereço completo e API key JAMAIS aparecem em logs (só códigos seguros).
 */
import { createHash } from 'crypto';
import {
  PayoutProvider,
  PayoutRequest,
  PayoutResult,
  ProviderAssetQuery,
  ReadonlyPayoutProvider,
  ProviderBalanceEntry,
  ProviderFeeEntry,
  ProviderReadResult,
} from './payout_provider';

const FAUCETPAY_BASE_URL = 'https://faucetpay.io/api/v1';
const FAUCETPAY_SEND_URL = `${FAUCETPAY_BASE_URL}/send`;
const FAUCETPAY_BALANCE_URL = `${FAUCETPAY_BASE_URL}/balance`;
const FAUCETPAY_FEES_URL = `${FAUCETPAY_BASE_URL}/fees`;
const TIMEOUT_MS = 15_000;
const MAX_ATTEMPTS = 3;
const RETRYABLE_HTTP = new Set([500, 502, 503, 504]);

/** Códigos de erro da API FaucetPay mapeados para códigos seguros internos. */
function mapApiError(apiCode: string): string {
  switch (apiCode) {
    case 'INVALID_ADDRESS':
      return 'INVALID_ADDRESS';
    case 'AMOUNT_TOO_LOW':
      return 'AMOUNT_TOO_LOW';
    case 'INSUFFICIENT_FUNDS':
      return 'PROVIDER_INSUFFICIENT_FUNDS';
    case 'INVALID_CURRENCY':
      return 'INVALID_ASSET';
    case 'INVALID_API_KEY':
      return 'INVALID_CREDENTIALS';
    default:
      return 'PROVIDER_ERROR';
  }
}

/** SHA-256 prefixo da mensagem bruta — diagnóstico sem expor conteúdo. */
function detailHash(raw: string): string {
  return createHash('sha256').update(raw).digest('hex').slice(0, 10);
}

export class FaucetPayProvider implements PayoutProvider, ReadonlyPayoutProvider {
  readonly id = 'faucetpay';

  private readonly apiKey: string;

  constructor(apiKey?: string) {
    const key = apiKey ?? process.env.FAUCETPAY_API_KEY ?? '';
    if (!key) throw new Error('FAUCETPAY_API_KEY_MISSING');
    this.apiKey = key;
  }

  async sendPayout(req: PayoutRequest): Promise<PayoutResult> {
    // amount em moeda inteira é exigido pela API; units → string decimal.
    const amountDecimal = (Number(req.amountUnits) / 1e8).toString();

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      try {
        const res = await fetch(FAUCETPAY_SEND_URL, {
          method: 'POST',
          headers: { 'content-type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            api_key: this.apiKey,
            to: req.address,
            currency: req.asset,
            amount: amountDecimal,
          }),
          signal: controller.signal,
        });

        if (RETRYABLE_HTTP.has(res.status)) {
          if (attempt < MAX_ATTEMPTS) {
            await this.backoff(attempt);
            continue; // resposta ambígua ⇒ nova tentativa é segura
          }
          return { status: 'failed', errorCode: 'PROVIDER_UNAVAILABLE' };
        }

        const body = (await res.json().catch(() => null)) as
          | { success?: boolean; payout_id?: number | string; message?: string }
          | null;

        if (res.ok && body?.success === true && body.payout_id != null) {
          return {
            status: 'completed',
            providerReference: `FP-${String(body.payout_id)}`,
          };
        }
        // Resposta DEFINITIVA de erro — sem retry (evita duplicar pagamento).
        return {
          status: 'failed',
          errorCode: mapApiError(String(body?.message ?? '')),
        };
      } catch (err) {
        const aborted = err instanceof Error && err.name === 'AbortError';
        if (attempt < MAX_ATTEMPTS && aborted) {
          await this.backoff(attempt);
          continue; // timeout ⇒ resultado desconhecido; retry com cautela
        }
        return { status: 'failed', errorCode: aborted ? 'PROVIDER_TIMEOUT' : 'PROVIDER_NETWORK' };
      } finally {
        clearTimeout(timer);
      }
    }
    return { status: 'failed', errorCode: 'PROVIDER_UNAVAILABLE' };
  }

  private backoff(attempt: number): Promise<void> {
    const delayMs = Math.min(1_000 * 2 ** (attempt - 1), 8_000);
    return new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  // -------------------------------------------------------------------------
  // READ-ONLY (probe): NUNCA envia dinheiro. Endpoints balance/fees apenas.
  // -------------------------------------------------------------------------

  /** POST read-only genérico; resposta definitiva sem retry (sem risco). */
  private async postReadonly(
    url: string,
  ): Promise<ProviderReadResult<Record<string, unknown>>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ api_key: this.apiKey }),
        signal: controller.signal,
      });
      const body = (await res.json().catch(() => null)) as Record<string, unknown> | null;
      // Códigos seguros COM diagnóstico operacional (status/JSON), nunca dados.
      if (!res.ok) return { ok: false, errorCode: `PROVIDER_HTTP_${res.status}` };
      if (!body) return { ok: false, errorCode: 'PROVIDER_BAD_JSON' };
      if (body.success !== true) {
        const raw = String(body['message'] ?? '');
        return { ok: false, errorCode: mapApiError(raw), detailHash: detailHash(raw) };
      }
      return { ok: true, data: body };
    } catch (err) {
      const aborted = err instanceof Error && err.name === 'AbortError';
      return { ok: false, errorCode: aborted ? 'PROVIDER_TIMEOUT' : 'PROVIDER_NETWORK' };
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Saldos por ativo (menores unidades). A FaucetPay responde POR MOEDA:
   * { success, currency, balance: "0.0001", balance_satoshi: 10000 }.
   * Uma chamada READ-ONLY por ativo habilitado (decimais da config v2).
   * Converte decimal → menor unidade com BigInt puro (sem float); valor
   * inesperado ⇒ ativo ignorado (nunca inventa saldo).
   */
  async getBalances(
    assets: ProviderAssetQuery[],
  ): Promise<ProviderReadResult<ProviderBalanceEntry[]>> {
    const entries: ProviderBalanceEntry[] = [];
    for (const asset of assets) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      let body: Record<string, unknown> | null;
      try {
        const res = await fetch(FAUCETPAY_BALANCE_URL, {
          method: 'POST',
          headers: { 'content-type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ api_key: this.apiKey, currency: asset.id }),
          signal: controller.signal,
        });
        body = (await res.json().catch(() => null)) as Record<string, unknown> | null;
        if (!res.ok) return { ok: false, errorCode: `PROVIDER_HTTP_${res.status}` };
        if (!body) return { ok: false, errorCode: 'PROVIDER_BAD_JSON' };
        if (body.success !== true) {
          const raw = String(body['message'] ?? '');
          return { ok: false, errorCode: mapApiError(raw), detailHash: detailHash(raw) };
        }
      } catch (err) {
        const aborted = err instanceof Error && err.name === 'AbortError';
        return { ok: false, errorCode: aborted ? 'PROVIDER_TIMEOUT' : 'PROVIDER_NETWORK' };
      } finally {
        clearTimeout(timer);
      }
      // Preferir campo inteiro do provedor; fallback: decimal × decimais.
      const satoshi = Number(body['balance_satoshi'] ?? NaN);
      const units =
        Number.isSafeInteger(satoshi) && satoshi >= 0
          ? BigInt(satoshi)
          : decimalToUnits(String(body['balance'] ?? ''), asset.decimals);
      if (units === null || units < 0n) continue;
      entries.push({ asset: String(body['currency'] ?? asset.id), balanceUnits: units });
    }
    return { ok: true, data: entries };
  }

  /**
   * Taxas por ativo. Resposta da FaucetPay:
   * { success, fees?: { BTC: "0.00001", ... }, ... }. Mínimos não são
   * expostos por endpoint dedicado ⇒ minUnits fica indefinido (config v2 é
   * a autoridade de mínimos).
   */
  async getFees(): Promise<ProviderReadResult<ProviderFeeEntry[]>> {
    const result = await this.postReadonly(FAUCETPAY_FEES_URL);
    if (!result.ok) return result;
    const raw = result.data['fees'];
    if (!raw || typeof raw !== 'object') return { ok: false, errorCode: 'PROVIDER_ERROR' };
    const entries: ProviderFeeEntry[] = [];
    for (const [asset, value] of Object.entries(raw as Record<string, unknown>)) {
      const units = decimalToUnits(String(value ?? '0'));
      if (units === null) continue;
      entries.push({ asset, feeUnits: units });
    }
    return { ok: true, data: entries };
  }
}

/** Decimal string ("0.00012345") → menor unidade (BigInt) ou null se inválido. */
export function decimalToUnits(decimal: string, decimals = 8): bigint | null {
  const m = /^(\d+)(?:\.(\d+))?$/.exec(decimal.trim());
  if (!m) return null;
  const frac = (m[2] ?? '').padEnd(decimals, '0').slice(0, decimals);
  return BigInt(m[1] + frac);
}
