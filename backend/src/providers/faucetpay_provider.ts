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

/**
 * Erros do ENVIO INTERNO (por e-mail/usuário FaucetPay) mapeados para códigos
 * TIPADOS seguros. A mensagem real da API varia ("Invalid or missing
 * username/email", "USER_NOT_FOUND", …) ⇒ matching por substring, em caixa
 * baixa. NUNCA inclui o e-mail no código/retorno.
 */
export function mapEmailSendError(rawMessage: string): string {
  const msg = String(rawMessage ?? '').toLowerCase();
  if (
    msg.includes('username') ||
    msg.includes('user_not_found') ||
    msg.includes('invalid_email') ||
    msg.includes('email not found')
  ) {
    return 'EMAIL_NOT_FOUND';
  }
  if (msg.includes('amount too low') || msg.includes('amount_too_low')) {
    return 'BELOW_MIN';
  }
  if (msg.includes('insufficient')) {
    return 'INSUFFICIENT_PROVIDER_BALANCE';
  }
  if (msg.includes('rate limit') || msg.includes('too many')) {
    return 'RATE_LIMIT';
  }
  if (msg.includes('invalid api key')) {
    return 'INVALID_CREDENTIALS';
  }
  return 'API_ERROR';
}

/**
 * BigInt em menores unidades → string decimal EXATA do ativo (sem float).
 * Ex.: 100n com 8 decimais ⇒ "0.000001" (1 COIN = 0,000001 LTC).
 */
export function unitsToDecimalString(units: bigint, decimals = 8): string {
  const neg = units < 0n;
  const abs = (neg ? -units : units).toString().padStart(decimals + 1, '0');
  const intPart = abs.slice(0, abs.length - decimals);
  const fracPart = abs.slice(abs.length - decimals).replace(/0+$/, '');
  const s = fracPart ? `${intPart}.${fracPart}` : intPart;
  return neg ? `-${s}` : s;
}

/**
 * Mensagem operacional sanitizada p/ log: redige qualquer token longo
 * (padrão de chave/endereço) e trunca. Nunca expõe credenciais.
 */
function sanitizeDetail(raw: string): string {
  return raw.replace(/[A-Za-z0-9]{20,}/g, '<redacted>').slice(0, 80);
}

export class FaucetPayProvider implements PayoutProvider, ReadonlyPayoutProvider {
  readonly id = 'faucetpay';

  private readonly apiKey: string;

  constructor(apiKey?: string) {
    const key = apiKey ?? process.env.FAUCETPAY_API_KEY ?? '';
    if (!key) throw new Error('FAUCETPAY_API_KEY_MISSING');
    this.apiKey = key;
  }

  /**
   * Ponto de entrada único do processador. Fluxo v3 (destinationEmail
   * presente) delega ao envio INTERNO por e-mail; fluxo legado usa endereço.
   */
  async sendPayout(req: PayoutRequest): Promise<PayoutResult> {
    if (req.destinationEmail) {
      return this.sendToUser({
        asset: req.asset,
        amountLitoshi: req.amountUnits,
        email: req.destinationEmail,
      });
    }
    return this.postSend(
      {
        api_key: this.apiKey,
        to: req.address,
        currency: req.asset,
        amount: unitsToDecimalString(req.amountUnits, 8),
      },
      mapApiError,
    );
  }

  /**
   * ENVIO INTERNO FaucetPay POR E-MAIL (transferência entre usuários da
   * plataforma — NUNCA endereço externo de carteira). Mesma política de
   * retry do sendPayout: apenas rede/5xx/timeout são reenviados; resposta
   * definitiva NUNCA é reenviada (evita pagamento duplicado). O e-mail é
   * usado SOMENTE no corpo da requisição — jamais em logs/erros.
   */
  async sendToUser(params: {
    asset: string;
    /** Valor LÍQUIDO em litoshi (menores unidades do ativo). */
    amountLitoshi: bigint;
    /** E-mail da conta FaucetPay do destinatário (nunca logado). */
    email: string;
  }): Promise<PayoutResult> {
    return this.postSend(
      {
        api_key: this.apiKey,
        to: params.email,
        currency: params.asset,
        amount: unitsToDecimalString(params.amountLitoshi, 8),
      },
      mapEmailSendError,
    );
  }

  /** POST /send compartilhado com retry APENAS p/ ambiguidade (rede/5xx). */
  private async postSend(
    form: Record<string, string>,
    mapError: (raw: string) => string,
  ): Promise<PayoutResult> {
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      try {
        const res = await fetch(FAUCETPAY_SEND_URL, {
          method: 'POST',
          headers: { 'content-type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams(form),
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
          errorCode: mapError(String(body?.message ?? '')),
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
      // Alguns endpoints read-only respondem {message:"OK"} SEM campo success.
      const isOk = body.success === true || String(body['message'] ?? '') === 'OK';
      if (!isOk) {
        const raw = String(body['message'] ?? '');
        return { ok: false, errorCode: mapApiError(raw), detailMsg: sanitizeDetail(raw) };
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
        const isOk = body.success === true || String(body['message'] ?? '') === 'OK';
        if (!isOk) {
          const raw = String(body['message'] ?? '');
          return { ok: false, errorCode: mapApiError(raw), detailMsg: sanitizeDetail(raw) };
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
