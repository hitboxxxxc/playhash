/// Abstração PayoutProvider (doc 05 §27, mantida na decisão 12.18).
///
/// O payout FaucetPay agora roda NO CLIENTE (decisão do dono), mas a
/// abstração permanece: qualquer implementação recebe e-mail de destino +
/// valor em litoshi (inteiros — §20 precisão inteira) e devolve um resultado
/// tipado com códigos SEGUROS (nunca dados sensíveis).
library;

/// Códigos de erro SEGUROS do provider (nunca contêm chave/e-mail).
abstract final class PayoutErrorCodes {
  static const String providerError = 'PROVIDER_ERROR';
  static const String invalidAmount = 'INVALID_AMOUNT';
  static const String insufficientProviderBalance =
      'INSUFFICIENT_PROVIDER_BALANCE';
  static const String emailNotFound = 'EMAIL_NOT_FOUND';

  /// fp=456 "The recipient is not payable — no user owns that address":
  /// e-mail/endereço NÃO vinculado a uma conta FaucetPay (12.22).
  static const String unlinkedDestination = 'DESTINO_NAO_VINCULADO';
  static const String rateLimit = 'RATE_LIMIT';

  /// Chave da FaucetPay inválida/expirada ("Invalid API key" na espec).
  static const String invalidApiKey = 'INVALID_API_KEY';
}

/// Resultado de um payout.
class PayoutResult {
  const PayoutResult.completed(String this.providerReference, {this.detail})
      : success = true,
        errorCode = null;

  const PayoutResult.failed(String this.errorCode, {this.detail})
      : success = false,
        providerReference = null;

  /// MODO MANUAL: handoff para o operador (SEM chamada de rede). O doc
  /// `withdrawals/{id}` fica `status:'pending'` até o operador definir
  /// 'completed'/'failed' pelo Firebase Console.
  const PayoutResult.pending()
      : success = false,
        errorCode = null,
        providerReference = null,
        detail = null;

  final bool success;

  /// Referência do provedor (ex.: 'FP-123456') em caso de sucesso.
  final String? providerReference;

  /// Código seguro em caso de falha ([PayoutErrorCodes]).
  final String? errorCode;

  /// Detalhe técnico CURTO e SEGURO p/ exibição na UI (sem segredo):
  /// ex.: "http=200 fp=400 msg=Invalid API key". NUNCA contém chave/e-mail.
  final String? detail;

  /// True quando o resultado é um handoff MANUAL ([PayoutResult.pending]).
  bool get isPending =>
      !success && errorCode == null && providerReference == null;
}

/// Contrato do provedor de payout — permite fakes nos testes.
abstract interface class PayoutProvider {
  /// Envia [amountLitoshi] (INTEIRO, menores unidades) para o
  /// [destination]: e-mail/username da conta FaucetPay OU endereço LTC
  /// vinculado (linked address) — doc oficial /send (12.22).
  ///
  /// Implementações NUNCA devem logar a API key ou o destino completo.
  Future<PayoutResult> sendPayout({
    required String destination,
    required int amountLitoshi,
  });
}
