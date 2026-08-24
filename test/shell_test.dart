import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/routing/app_router.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/data/repositories/profile_repository.dart';
import 'package:playhash/features/games/games_screen.dart';
import 'package:playhash/features/home/home_screen.dart';
import 'package:playhash/features/mining/mining_screen.dart';
import 'package:playhash/features/profile/profile_screen.dart';
import 'package:playhash/features/store/store_screen.dart';

/// Fake de [User] — presença/ausência importa para o redirect e o uid
/// para os repositórios da HOME/MINERAÇÃO.
class _FakeUser implements User {
  @override
  String get uid => 'uid-shell';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Fake do serviço de autenticação sem tocar no Firebase.
class _FakeAuthService implements AuthServiceApi {
  User? user;
  int signOutCalls = 0;

  final StreamController<User?> _controller =
      StreamController<User?>.broadcast();

  void emit(User? value) {
    user = value;
    _controller.add(value);
  }

  /// Emite o usuário atual imediatamente (mesmo comportamento do
  /// FirebaseAuth.authStateChanges) e depois repassa mudanças.
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* _controller.stream;
  }

  @override
  Future<User?> currentUser() async => user;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Fake do repositório de perfil.
class _FakeProfileRepository implements ProfileRepositoryApi {
  _FakeProfileRepository({this.doc});

  Map<String, dynamic>? doc;

  @override
  Future<Map<String, dynamic>?> loadOwnProfile(String uid) async => doc;

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String uid) =>
      Stream<Map<String, dynamic>?>.value(doc);

  @override
  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> prefs,
  ) async {}
}

void main() {
  testWidgets(
    'shell navega entre as 5 abas e preserva estado por aba',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService();
      auth.user = _FakeUser();

      // Inicia direto na shell autenticada (AuthGate depende de Firebase
      // real e não é alvo deste teste).
      final GoRouter router = createAppRouter(
        auth: auth,
        initialLocation: RoutePaths.home,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(
              _FakeProfileRepository(doc: <String, dynamic>{
                'displayName': 'Jogador Teste',
              }),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('MEU PODER'), findsOneWidget);

      // JOGAR: seleciona filtro de dificuldade (estado local).
      await tester.tap(find.text('JOGAR'));
      await tester.pumpAndSettle();
      expect(find.byType(GamesScreen), findsOneWidget);
      await tester.tap(find.text('MÉDIO'));
      await tester.pumpAndSettle();

      // MINERAÇÃO (estrutura P4). Sem Firebase no ambiente de teste, os
      // repositórios reais falham => estado de erro com retry (correto).
      await tester.tap(find.text('MINERAÇÃO'));
      await tester.pumpAndSettle();
      expect(find.byType(MiningScreen), findsOneWidget);
      // AppBar da MINERAÇÃO (o bottom nav também usa o rótulo).
      expect(
        find.descendant(
          of: find.byType(MiningScreen),
          matching: find.text('MINERAÇÃO'),
        ),
        findsOneWidget,
      );

      // LOJA.
      await tester.tap(find.text('LOJA'));
      await tester.pumpAndSettle();
      expect(find.byType(StoreScreen), findsOneWidget);

      // PERFIL.
      await tester.tap(find.text('PERFIL'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Minha conta'), findsOneWidget);

      // Volta para HOME e depois JOGAR: estado do filtro deve persistir.
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.text('JOGAR'));
      await tester.pumpAndSettle();
      final Finder medioChip = find.descendant(
        of: find.byType(GamesScreen),
        matching: find.text('MÉDIO'),
      );
      expect(medioChip, findsOneWidget);
      final FilterChip chip = tester.widget<FilterChip>(
        find.ancestor(of: medioChip, matching: find.byType(FilterChip)),
      );
      expect(chip.selected, isTrue, reason: 'estado da aba JOGAR persistido');
    },
  );

  testWidgets(
    'SAIR DA CONTA chama signOut e retorna ao login',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService();
      auth.user = _FakeUser();

      final GoRouter router = createAppRouter(
        auth: auth,
        initialLocation: RoutePaths.profile,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(
              _FakeProfileRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle(); // -> /app/profile
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      // O botão fica abaixo da dobra na lista do perfil.
      await tester.scrollUntilVisible(
        find.text('SAIR DA CONTA'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('SAIR DA CONTA'));
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 1);
      expect(router.routerDelegate.currentConfiguration.uri.path,
          RoutePaths.login);
      expect(find.byType(TextButton), findsWidgets); // tela de login presente
    },
  );

  testWidgets(
    'redirect: rota /app/** sem sessão cai no login',
    (WidgetTester tester) async {
      final _FakeAuthService auth = _FakeAuthService(); // user == null

      final GoRouter router = createAppRouter(auth: auth);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(
              _FakeProfileRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      router.go(RoutePaths.games);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RoutePaths.login,
      );
    },
  );
}
