import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/routing/app_router.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/core/services/cloud_functions_service.dart';
import 'package:playhash/core/widgets/neon_button.dart';
import 'package:playhash/data/repositories/profile_repository.dart';
import 'package:playhash/features/settings/settings_screen.dart';

/// Fake de [User] — apenas uid importa para os repositórios.
class _FakeUser implements User {
  @override
  String get uid => 'uid-1';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Fake do serviço de autenticação sem tocar no Firebase.
class _FakeAuthService implements AuthServiceApi {
  _FakeAuthService({this.user});

  User? user;
  int signOutCalls = 0;

  @override
  Future<User?> currentUser() async => user;

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Fake do repositório de perfil com stream controlável.
class _FakeProfileRepository implements ProfileRepositoryApi {
  final StreamController<Map<String, dynamic>?> _controller =
      StreamController<Map<String, dynamic>?>.broadcast();

  Map<String, dynamic>? doc;
  Map<String, dynamic>? savedNotificationPrefs;

  void emit(Map<String, dynamic>? value) {
    doc = value;
    _controller.add(value);
  }

  @override
  Future<Map<String, dynamic>?> loadOwnProfile(String uid) async => doc;

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String uid) async* {
    yield doc;
    yield* _controller.stream;
  }

  @override
  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> prefs,
  ) async {
    savedNotificationPrefs = prefs;
  }
}

/// Fake do serviço de Cloud Functions.
class _FakeCloudFunctionsService implements CloudFunctionsServiceApi {
  int deleteCalls = 0;

  @override
  Future<void> deleteMyAccount() async => deleteCalls++;
}

ProfileRepositoryApi _repoFactory(_FakeProfileRepository repo) => repo;

/// Rola até o finder existir na árvore (ListView constrói filhos sob demanda)
/// e o traz totalmente para o viewport antes de interações.
Future<void> _scrollToItem(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(WidgetTester tester, _FakeAuthService auth,
    _FakeProfileRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          _repoFactory(repo),
        ),
        cloudFunctionsServiceProvider
            .overrideWithValue(_FakeCloudFunctionsService()),
      ],
      child: MaterialApp.router(
        routerConfig: createAppRouter(
          auth: auth,
          initialLocation: RoutePaths.profile,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'perfil renderiza header, stats placeholders, menu e SAIR DA CONTA',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository()
        ..emit(<String, dynamic>{
          'displayName': 'Ana Jogadora',
          'createdAt': null,
        });

      await _pumpProfile(tester, auth, repo);

      // Header.
      expect(find.text('Ana Jogadora'), findsOneWidget);
      expect(find.text('NÍVEL 1'), findsOneWidget);

      // Stats placeholders honestos (sem números inventados).
      expect(find.text('PODER TOTAL'), findsOneWidget);
      expect(find.text('LIGA'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);

      // Menu completo.
      for (final String title in <String>[
        'Minha conta',
        'Carteira',
        'Histórico',
        'Conquistas',
        'Ligas',
        'Indicações',
        'Configurações',
        'Suporte',
        'Termos e Privacidade',
      ]) {
        expect(find.text(title), findsOneWidget);
      }

      await _scrollToItem(tester, find.text('SAIR DA CONTA'));
      expect(find.text('SAIR DA CONTA'), findsOneWidget);
    },
  );

  testWidgets(
    '"Jogador desde [mês/ano]" é derivado de createdAt do Firestore',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository()
        ..emit(<String, dynamic>{
          'displayName': 'Bruno',
          'createdAt': Timestamp.fromDate(DateTime(2024, 3, 10)),
        });

      await _pumpProfile(tester, auth, repo);

      expect(find.text('Jogador desde março de 2024'), findsOneWidget);
    },
  );

  testWidgets(
    'atualização em tempo real: novo displayName reflete na tela',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository()
        ..emit(<String, dynamic>{'displayName': 'Nome Antigo'});

      await _pumpProfile(tester, auth, repo);
      expect(find.text('Nome Antigo'), findsOneWidget);

      repo.emit(<String, dynamic>{'displayName': 'Nome Novo'});
      await tester.pumpAndSettle();

      expect(find.text('Nome Novo'), findsOneWidget);
      expect(find.text('Nome Antigo'), findsNothing);
    },
  );

  testWidgets(
    'erro/ausência de perfil não quebra a tela: menu e sair seguem visíveis',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository();

      await _pumpProfile(tester, auth, repo);

      expect(find.text('Jogador'), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);

      await _scrollToItem(tester, find.text('SAIR DA CONTA'));
      expect(find.text('SAIR DA CONTA'), findsOneWidget);
    },
  );

  testWidgets(
    'SAIR DA CONTA chama signOut e retorna ao login',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository()
        ..emit(<String, dynamic>{'displayName': 'Ana'});

      await _pumpProfile(tester, auth, repo);

      await tester.scrollUntilVisible(
        find.text('SAIR DA CONTA'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('SAIR DA CONTA'));
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 1);
    },
  );

  testWidgets(
    'menu Configurações abre a tela de configurações',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository()
        ..emit(<String, dynamic>{'displayName': 'Ana'});

      await _pumpProfile(tester, auth, repo);

      await _scrollToItem(tester, find.text('Configurações'));
      await tester.tap(find.text('Configurações'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('CONTA'), findsOneWidget);
      expect(find.text('NOTIFICAÇÕES'), findsOneWidget);

      // Seção Privacidade (abaixo da dobra) com o item crítico.
      await _scrollToItem(tester, find.text('EXCLUIR CONTA'));
      expect(find.text('EXCLUIR CONTA'), findsOneWidget);
    },
  );

  testWidgets(
    'configurações: toggle de notificação salva preferências no repositório',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository();
      final _FakeCloudFunctionsService functions =
          _FakeCloudFunctionsService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(repo),
            cloudFunctionsServiceProvider.overrideWithValue(functions),
          ],
          child: MaterialApp.router(
            routerConfig: createAppRouter(
              auth: auth,
              initialLocation: RoutePaths.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollToItem(tester, find.text('Recompensas'));
      await tester.tap(find.text('Recompensas'));
      await tester.pumpAndSettle();

      expect(repo.savedNotificationPrefs, isNotNull);
      expect(repo.savedNotificationPrefs!['rewards'], isFalse);
      expect(repo.savedNotificationPrefs!['missions'], isTrue);
    },
  );

  testWidgets(
    'exclusão de conta: confirmação dupla chama backend (nunca cliente direto)',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(user: _FakeUser());
      final _FakeProfileRepository repo = _FakeProfileRepository();
      final _FakeCloudFunctionsService functions =
          _FakeCloudFunctionsService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(repo),
            cloudFunctionsServiceProvider.overrideWithValue(functions),
          ],
          child: MaterialApp.router(
            routerConfig: createAppRouter(
              auth: auth,
              initialLocation: RoutePaths.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abre o fluxo.
      await _scrollToItem(tester, find.text('EXCLUIR CONTA'));
      await tester.tap(find.text('EXCLUIR CONTA'));
      await tester.pumpAndSettle();

      // Passo 1: botão desabilitado até marcar ciência.
      expect(find.textContaining('PERMANENTE'), findsOneWidget);
      await tester.tap(find.byType(NeonButton)); // CONTINUAR
      await tester.pump();
      expect(functions.deleteCalls, 0);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(NeonButton)); // CONTINUAR
      await tester.pumpAndSettle();

      // Passo 2: exige senha.
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'senha1234',
      );
      await tester.tap(find.byType(NeonButton)); // EXCLUIR CONTA
      await tester.pumpAndSettle();

      expect(functions.deleteCalls, 1);
      expect(auth.signOutCalls, 1); // sessão encerrada após solicitação
    },
  );
}
