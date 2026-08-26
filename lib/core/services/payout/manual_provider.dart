import 'payout_provider.dart';

/// MODO MANUAL DE OPERADOR (12.20) — MESMA interface [PayoutProvider].
///
/// NÃO chama rede. O [sendPayout] devolve [PayoutResult.pending]: o serviço
/// de saque grava `withdrawals/{clientRequestId}` com `status:'pending'`
/// (reserva já feita: available−=X, pending+=X) e a UI mostra
/// "aguardando pagamento manual do operador".
///
/// Finalização/estorno são AUTOMÁTICOS ao OBSERVAR o status definido pelo
/// operador no Firebase Console (que bypassa rules):
///  - status → 'completed' ⇒ pending −= X (total DIMINUI) + histórico completed;
///  - status → 'failed'    ⇒ pending −= X e available += X (estorno integral)
///    + histórico failed.
/// Observação implementada em [ManualPayoutWatcher] (withdrawal_service.dart).
class ManualProvider implements PayoutProvider {
  ManualProvider();

  @override
  Future<PayoutResult> sendPayout({
    required String destination,
    required int amountLitoshi,
  }) async {
    // Validação local mínima (mesma disciplina do provider automático).
    if (amountLitoshi <= 0) {
      return const PayoutResult.failed(PayoutErrorCodes.invalidAmount);
    }
    return const PayoutResult.pending();
  }
}
