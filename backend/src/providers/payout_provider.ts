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
