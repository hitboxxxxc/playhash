// Testes do mapeamento de erros de autenticação (doc 05 — mensagens
// seguras PT-BR; "sem conexão" SOMENTE para erros de rede reais).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:playhash/core/services/auth_error_messages.dart';

FirebaseAuthException authErr(String code) =>
    FirebaseAuthException(code: code, message: null);

void main() {
  group('isOfflineError — apenas erros de rede REAIS', () {
    test('true para network-request-failed', () {
      expect(isOfflineError(authErr('network-request-failed')), isTrue);
    });
    test('false para DEVELOPER_ERROR/10 (configuração, não rede)', () {
      expect(
        isOfflineError(
          PlatformException(code: '10', message: 'Developer error'),
        ),
        isFalse,
      );
    });
    test('false para operation-not-allowed (provedor desativado)', () {
      expect(isOfflineError(authErr('operation-not-allowed')), isFalse);
    });
    test('false para invalid-credential', () {
      expect(isOfflineError(authErr('invalid-credential')), isFalse);
    });
  });

  group('safeAuthErrorMessage — mensagens específicas PT-BR', () {
    test('invalid-credential → e-mail ou senha incorretos', () {
      expect(safeAuthErrorMessage(authErr('invalid-credential')),
          contains('E-mail ou senha incorretos'));
    });
    test('email-already-in-use → já cadastrado', () {
      expect(safeAuthErrorMessage(authErr('email-already-in-use')),
          contains('já está cadastrado'));
    });
    test('weak-password → senha fraca', () {
      expect(safeAuthErrorMessage(authErr('weak-password')),
          contains('muito fraca'));
    });
    test('operation-not-allowed → método desativado no Console', () {
      final msg = safeAuthErrorMessage(authErr('operation-not-allowed'));
      expect(msg, contains('desativado'));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });
    test('network-request-failed → mensagem de conexão', () {
      expect(safeAuthErrorMessage(authErr('network-request-failed')),
          contains('sem conexão'));
    });
    test('DEVELOPER_ERROR (PlatformException 10) → configuração, sem '
        'falar de conexão', () {
      final msg = safeAuthErrorMessage(
        PlatformException(code: '10', message: 'Developer error'),
      );
      expect(msg, contains('configuração'));
      expect(msg.toLowerCase(), isNot(contains('sem conexão')));
    });
    test('erro desconhecido NUNCA diz "sem conexão"', () {
      final msg = safeAuthErrorMessage(authErr('some-unknown-code'));
      expect(msg.toLowerCase(), isNot(contains('sem conexão')));
      expect(msg, isNotEmpty);
    });
  });
}
