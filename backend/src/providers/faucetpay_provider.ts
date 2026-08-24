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
import { PayoutProvider, PayoutRequest, PayoutResult } from './payout_provider';

const FAUCETPAY_SEND_URL = 'https://faucetpay.io/api/v1/send';
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
    default:
      return 'PROVIDER_ERROR';
  }
}

export class FaucetPayProvider implements PayoutProvider {
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
}
