import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/core/widgets/neon_button.dart';
import 'package:playhash/features/auth/login_screen.dart';

/// Toca o primeiro [NeonButton] (botão ENTRAR de e-mail/senha).
Finder get _entrarButton => find.byType(NeonButton).first;

/// Fake de AuthService — NENHUMA chamada real ao Firebase nos testes.
class FakeAuthService implements AuthServiceApi {
  int signInCalls = 0;
  bool succeed = true;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();

  @override
  Future<User?> currentUser() async => null;

  @override
  Future<User?> signInWithEmail(String email, String password) async {
    signInCalls++;
    if (!succeed) {
      throw Exception('invalid-credential');
    }
    return null;
  }

  @override
  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required DateTime termsAcceptedAt,
  }) async =>
      null;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<User?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}
}

Future<void> _pumpLogin(WidgetTester tester, FakeAuthService fake,
    {VoidCallback? onSuccess}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: LoginScreen(authService: fake, onSuccess: onSuccess),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('validação local bloqueia submit com campos inválidos',
      (WidgetTester tester) async {
    final FakeAuthService fake = FakeAuthService();
    await _pumpLogin(tester, fake);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'), 'email-invalido');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'), '123');
    await tester.tap(_entrarButton);
    await tester.pump();

    expect(find.text('E-mail inválido.'), findsOneWidget);
    expect(find.text('A senha deve ter ao menos 8 caracteres.'),
        findsOneWidget);
    expect(fake.signInCalls, 0);
  });

  testWidgets('login válido chama o serviço e dispara sucesso',
      (WidgetTester tester) async {
    final FakeAuthService fake = FakeAuthService()..succeed = true;
    bool successCalled = false;
    await _pumpLogin(tester, fake,
        onSuccess: () => successCalled = true);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'), 'user@playhash.app');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'), 'senha1234');
    await tester.tap(_entrarButton);
    await tester.pumpAndSettle();

    expect(fake.signInCalls, 1);
    expect(successCalled, isTrue);
  });

  testWidgets('falha de credencial mostra mensagem segura em PT-BR',
      (WidgetTester tester) async {
    final FakeAuthService fake = FakeAuthService()..succeed = false;
    await _pumpLogin(tester, fake);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'), 'user@playhash.app');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'), 'senha1234');
    await tester.tap(_entrarButton);
    await tester.pumpAndSettle();

    expect(fake.signInCalls, 1);
    expect(
      find.text('Não foi possível concluir a operação. Tente novamente.'),
      findsOneWidget,
    );
  });
}
