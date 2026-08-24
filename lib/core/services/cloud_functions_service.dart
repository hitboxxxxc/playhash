import 'package:flutter/foundation.dart';

/// Contrato dos serviços de backend executados via Cloud Functions.
///
/// O cliente NUNCA executa operações sensíveis diretamente (ex.: deletar o
/// próprio documento em `users/{uid}`): toda ação desse tipo passa pelo
/// backend para auditoria e consistência econômica.
abstract interface class CloudFunctionsServiceApi {
  /// Solicita a exclusão da própria conta.
  ///
  /// O backend (Cloud Function `deleteUserAccount`) é responsável por:
  /// - validar a identidade (re-auth já feita no cliente);
  /// - registrar audit log;
  /// - zerar/anonimizar dados econômicos;
  /// - remover o documento `users/{uid}` e a conta do Auth.
  Future<void> deleteMyAccount();
}

/// Implementação STUB de [CloudFunctionsServiceApi].
///
/// A Cloud Function Node.js (`deleteUserAccount`) será implantada em etapa
/// futura. Quando isso acontecer, trocar o corpo do método por algo como:
///
/// ```dart
/// final callable = FirebaseFunctions.instance
///     .httpsCallable('deleteUserAccount');
/// await callable.call(<String, dynamic>{'reason': reason});
/// ```
///
/// SEGURANÇA: nenhum log contém dados sensíveis (e-mail, senha, tokens).
class CloudFunctionsService implements CloudFunctionsServiceApi {
  @override
  Future<void> deleteMyAccount() async {
    debugPrint(
      '[CloudFunctionsService] deleteUserAccount: solicitação registrada '
      '(stub local — backend pendente de deploy).',
    );
    // Simula latência de rede para feedback honesto na UI.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}
