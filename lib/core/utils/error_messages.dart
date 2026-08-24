import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Detecta erros de rede/offline de forma agnóstica ao provedor.
bool isOfflineError(Object error) {
  if (error is SocketException || error is HttpException) return true;
  if (error is FirebaseException) {
    final String code = error.code.toLowerCase();
    return code.contains('network') ||
        code.contains('unavailable') ||
        code.contains('deadline-exceeded');
  }
  final String msg = error.toString().toLowerCase();
  return msg.contains('network') ||
      msg.contains('socket') ||
      msg.contains('connection');
}

/// Mensagens de erro SEGURAS em PT-BR.
/// Nunca expõem detalhes internos, e-mails ou existência de contas.
String safeAuthErrorMessage(Object error) {
  if (isOfflineError(error)) {
    return 'Você está sem conexão. Verifique sua internet e tente novamente.';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'email-already-in-use':
        return 'Este e-mail já está cadastrado.';
      case 'weak-password':
        return 'A senha é muito fraca.';
      case 'too-many-requests':
        return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
      case 'requires-recent-login':
        return 'Sessão expirada. Entre novamente para continuar.';
      case 'google-id-token-missing':
      case 'google-signin-canceled':
      case 'sign_in_canceled':
        return 'Login com Google cancelado.';
    }
  }
  return 'Não foi possível concluir a operação. Tente novamente.';
}
