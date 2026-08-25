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
  /**
   * Rede de destino. v3 (saque por e-mail): 'faucetpay_email' (transferência
   * INTERNA da FaucetPay); legado: Bitcoin/Litecoin/Dogecoin/TRC20.
   */
  network: string;
  /**
   * Endereço completo de destino (fluxo LEGADO; SÓ em memória; NUNCA em logs).
   * No fluxo v3 por e-mail fica VAZIO — usar destinationEmail.
   */
  address: string;
  /**
   * E-mail da conta FaucetPay do destinatário (fluxo v3; transferência
   * interna). SÓ em memória; NUNCA em logs (apenas máscara).
   */
  destinationEmail?: string;
  /**
   * Valor em MENORES UNIDADES do ativo (litoshi p/ LTC; sat p/ BTC). No fluxo
   * v3 já é o valor LÍQUIDO pós-taxa convertido pelo backend (inteiro).
   */
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
  | {
      ok: false;
      /** Código seguro (sem dados sensíveis). */
      errorCode: string;
      /**
       * Mensagem operacional do provedor SANITIZADA (tokens longos tipo
       * chave/endereço são redigidos; truncada) — nunca contém credenciais.
       */
      detailMsg?: string;
    };

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
