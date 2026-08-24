import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Mensagens de erro de autenticação SEGURAS em PT-BR.
///
/// Regras (doc 05):
/// - NUNCA exibir "sem conexão" quando o erro NÃO é de rede.
/// - Cada código conhecido tem mensagem ESPECÍFICA.
/// - Erros de configuração (DEVELOPER_ERROR, operation-not-allowed,
///   Firebase não inicializado) têm mensagem clara e acionável.
/// - Nenhuma mensagem expõe detalhes internos, tokens ou existência
///   de contas além do que o próprio fluxo já revela ao usuário.

/// Códigos que REALMENTE indicam problema de rede/offline.
const Set<String> _networkCodes = <String>{
  'network-request-failed',
  'unavailable',
  'deadline-exceeded',
  // google_sign_in (Android): 7 = network_error
  'network_error',
};

/// Detecta erros de rede/offline de forma conservadora:
/// apenas códigos explícitos de rede — nunca por texto genérico.
bool isOfflineError(Object error) {
  if (error is SocketException || error is HttpException) return true;
  if (error is FirebaseAuthException && _networkCodes.contains(error.code)) {
    return true;
  }
  if (error is FirebaseException && _networkCodes.contains(error.code)) {
    return true;
  }
  if (error is PlatformException && _networkCodes.contains(error.code)) {
    return true;
  }
  return false;
}

/// Erro de CONFIGURAÇÃO do app (não do usuário): exige ação no
/// Firebase Console / build — mensagem clara, sem culpar conexão.
bool isConfigError(Object error) {
  if (error is FirebaseAuthException) {
    return error.code == 'operation-not-allowed' ||
        error.code == 'configuration-not-found' ||
        error.code == 'api-not-available' ||
        error.code == 'admin-restricted-operation';
  }
  if (error is PlatformException) {
    // Android ApiException 10 = DEVELOPER_ERROR (SHA-1/oauth client ausente).
    return error.code == '10' ||
        error.code == 'DEVELOPER_ERROR' ||
        error.code == 'developer_error' ||
        error.code == 'api_not_available';
  }
  if (error is GoogleSignInException) {
    return error.code == GoogleSignInExceptionCode.clientConfigurationError;
  }
  return false;
}

String _googleMessage(Object error) {
  if (isOfflineError(error)) {
    return 'Você está sem conexão. Verifique sua internet e tente novamente.';
  }
  if (isConfigError(error)) {
    return 'Login com Google indisponível: configuração do app incompleta '
        '(SHA-1/cliente OAuth não registrado no Firebase Console).';
  }
  if (error is GoogleSignInException) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Login com Google cancelado.';
      default:
        break; // demais códigos caem na mensagem genérica abaixo.
    }
  }
  if (error is PlatformException) {
    switch (error.code) {
      case 'sign_in_canceled':
      case 'signin_canceled':
      case 'sign_in_failed_cancelled':
        return 'Login com Google cancelado.';
      case 'sign_in_failed':
        return 'Não foi possível entrar com o Google. Tente novamente.';
    }
  }
  return 'Não foi possível concluir o login com o Google. Tente novamente.';
}

/// Mapeia qualquer erro de autenticação para mensagem segura em PT-BR.
String safeAuthErrorMessage(Object error) {
  // Firebase não inicializado (build sem google-services.json).
  if (error is FirebaseException &&
      error.code == 'no-options') {
    return 'App não configurado: falta o arquivo google-services.json '
        '(rebuild necessário após baixá-lo do Firebase Console).';
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      // Rede — ÚNICO caso que menciona conexão.
      case 'network-request-failed':
        return 'Você está sem conexão. Verifique sua internet e tente novamente.';

      // Credenciais e-mail/senha.
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'missing-password':
        return 'Digite sua senha.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'E-mail ou senha incorretos.';
      case 'email-already-in-use':
        return 'Este e-mail já está cadastrado. Faça login.';
      case 'weak-password':
        return 'A senha é muito fraca. Use pelo menos 6 caracteres.';
      case 'too-many-requests':
        return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'requires-recent-login':
      case 'user-token-expired':
      case 'invalid-user-token':
        return 'Sua sessão expirou. Entre novamente para continuar.';

      // Configuração do projeto (ação no Firebase Console).
      case 'operation-not-allowed':
        return 'Método de login desativado no Firebase Console '
            '(Authentication → Sign-in method).';
      case 'configuration-not-found':
        return 'Método de login não configurado no projeto Firebase.';
      case 'api-not-available':
        return 'Serviço de autenticação indisponível para esta configuração.';
      case 'admin-restricted-operation':
        return 'Operação restrita pela administração do sistema.';
      case 'credential-already-in-use':
        return 'Esta conta do Google já está vinculada a outro usuário.';
      case 'account-exists-with-different-credential':
        return 'Já existe uma conta com este e-mail usando outro método de login.';
      case 'invalid-verification-code':
        return 'Código de verificação inválido.';
      case 'quota-exceeded':
        return 'Limite de operações atingido. Tente mais tarde.';

      // Específicos do fluxo Google definidos no AuthService.
      case 'google-id-token-missing':
        return 'Falha ao obter credencial do Google. Tente novamente.';
      case 'google-signin-canceled':
      case 'sign_in_canceled':
        return 'Login com Google cancelado.';
    }
    // Código desconhecido do FirebaseAuth: mensagem genérica SEM
    // alegar falta de conexão.
    return 'Não foi possível concluir a operação. Tente novamente.';
  }

  // Fluxos do plugin google_sign_in / intents Android.
  if (error is GoogleSignInException || error is PlatformException) {
    return _googleMessage(error);
  }

  // Falha de permissão do Firestore ao gravar users/{uid}.
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Conta criada, mas não foi possível concluir a configuração '
        'do perfil. Tente entrar novamente.';
  }

  if (isOfflineError(error)) {
    return 'Você está sem conexão. Verifique sua internet e tente novamente.';
  }

  return 'Não foi possível concluir a operação. Tente novamente.';
}
