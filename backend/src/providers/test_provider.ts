/**
 * TestProvider — PAYOUT_MODE=test (PADRÃO de desenvolvimento).
 *
 * Simula um payout BEM-SUCEDIDO com providerReference deterministicamente
 * única ("SIM-<uuid>") e marca payoutSimulated=true para auditoria
 * (WITHDRAWAL_COMPLETED.detail.payoutSimulated). NUNCA toca rede externa.
 */
import { randomUUID } from 'crypto';
import { PayoutProvider, PayoutRequest, PayoutResult } from './payout_provider';

export class TestProvider implements PayoutProvider {
  readonly id = 'test';

  async sendPayout(_req: PayoutRequest): Promise<PayoutResult> {
    // Sem log do endereço; apenas confirmação genérica.
    return {
      status: 'completed',
      providerReference: `SIM-${randomUUID()}`,
      payoutSimulated: true,
    };
  }
}
