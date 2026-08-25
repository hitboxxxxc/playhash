/**
 * Camada de PROVEDORES DE PAGAMENTO (payouts) — doc 05 §26/§51.
 *
 * O runner é a ÚNICA autoridade de saque; o cliente nunca fala com o
 * provedor. A seleção do provider é feita por PAYOUT_MODE (env/repo variable):
 *   - "test" (padrão dev) → TestProvider (simulação auditada);
 *   - "live"              → FaucetPayProvider (exige secret FAUCETPAY_API_KEY).
 *
 * CONTRATO: nenhuma implementação pode logar endereço completo de carteira
 * nem credenciais — apenas referências mascaradas/códigos seguros.
 */

export interface PayoutRequest {
  /** Id do ativo (BTC/LTC/DOGE/USDT) — deve existir em config/payouts.assets. */
  asset: string;
  /** Rede de destino (Bitcoin/Litecoin/Dogecoin/TRC20). */
  network: string;
  /** Endereço completo de destino (SÓ em memória; NUNCA em logs). */
  address: string;
  /** Valor BRUTO em units (1 coin = 1e6 units); taxa descontada pelo backend. */
  amountUnits: bigint;
}

export interface PayoutResult {
  status: 'completed' | 'failed';
  /** Referência opaca do provedor (persistida ANTES de considerar pago). */
  providerReference?: string;
  /** Código seguro de falha (sem dados sensíveis). */
  errorCode?: string;
  /** true quando o pagamento foi SIMULADO (TestProvider) — auditoria. */
  payoutSimulated?: boolean;
}

export interface PayoutProvider {
  /** Identificador estável p/ auditoria ("test" | "faucetpay"). */
  readonly id: string;
  sendPayout(req: PayoutRequest): Promise<PayoutResult>;
}

/** Ativo a consultar no provedor (decimais vêm da config/payouts v2). */
export interface ProviderAssetQuery {
  id: string;
  decimals: number;
}

/** Saldo de um ativo na conta do provedor (menor unidade do ativo). */
export interface ProviderBalanceEntry {
  asset: string;
  /** Saldo em menores unidades (ex.: satoshi). BigInt serializado como string. */
  balanceUnits: bigint;
}

/** Taxa/mínimo reportado pelo provedor p/ um ativo. */
export interface ProviderFeeEntry {
  asset: string;
  /** Taxa cobrada pelo provedor em menores unidades. */
  feeUnits: bigint;
  /** Mínimo aceito pelo provedor em menores unidades (quando informado). */
  minUnits?: bigint;
}

export type ProviderReadResult<T> =
  | { ok: true; data: T }
  | { ok: false; errorCode: string };

/**
 * Contrato READ-ONLY opcional (probe): valida a chave e lê saldos/taxas
 * SEM enviar dinheiro. Nenhuma implementação pode logar credenciais.
 */
export interface ReadonlyPayoutProvider {
  /**
   * Confere se a chave é válida e retorna saldos dos ativos informados
   * (consulta READ-ONLY por ativo; nunca envia dinheiro).
   */
  getBalances(assets: ProviderAssetQuery[]): Promise<ProviderReadResult<ProviderBalanceEntry[]>>;
  /** Lê taxas (e mínimos quando disponíveis) por ativo. */
  getFees(): Promise<ProviderReadResult<ProviderFeeEntry[]>>;
}
