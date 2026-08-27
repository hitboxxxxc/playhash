import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/achievements_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/common/coming_soon_screen.dart';
import '../../features/games/games_screen.dart';
import '../../features/home/pixel_home_screen.dart';
import '../../features/leagues/leagues_screen.dart';
import '../../features/missions/missions_screen.dart';
import '../../features/profile/account_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/season_pass/season_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/auth_gate.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../widgets/pixel_shell.dart';
import '../../data/models/wallet_model.dart';

/// Caminhos de rota — fonte única de verdade para navegação.
abstract final class RoutePaths {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String comingSoon = '/coming-soon';

  // Shell principal (5 abas — estado preservado por aba).
  static const String home = '/app/home';
  static const String games = '/app/games';
  static const String mining = '/app/mining';
  static const String store = '/app/store';
  static const String profile = '/app/profile';

  // Telas empurradas a partir das abas (fora da shell, mas autenticadas).
  static const String wallet = '/wallet';
  static const String settings = '/app/settings';
  static const String account = '/app/account';
  static const String history = '/app/history';
  static const String missions = '/app/missions';
  static const String achievements = '/app/achievements';
  static const String leagues = '/leagues';
  static const String season = '/season';
}

/// Cria o roteador do app.
///
/// - Shell principal com [StatefulShellRoute.indexedStack] (5 branches);
/// - Redirect por autenticação: rotas `/app/**` exigem sessão ativa;
/// - [auth] injetável para testes (fake sem Firebase).
GoRouter createAppRouter({AuthServiceApi? auth, String? initialLocation}) {
  final AuthServiceApi authService = auth ?? FirebaseAuthService();

  return GoRouter(
    initialLocation: initialLocation ?? RoutePaths.splash,
    refreshListenable: _AuthRefreshStream(_safeAuthStream(authService)),
    redirect: (Object _, GoRouterState state) async {
      final String location = state.matchedLocation;
      if (!location.startsWith('/app')) return null;

      bool signedIn = false;
      try {
        signedIn = await authService.currentUser() != null;
      } catch (_) {
        signedIn = false; // Firebase indisponível => trata como deslogado
      }
      if (!signedIn) return RoutePaths.login;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.splash,
        builder: (_, _) => const AuthGate(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.comingSoon,
        builder: (_, GoRouterState state) => ComingSoonScreen(
          title: state.uri.queryParameters['titulo'],
        ),
      ),
      GoRoute(
        path: RoutePaths.wallet,
        builder: (_, _) => const WalletScreen(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.account,
        builder: (_, _) => const AccountScreen(),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (_, _) => const HistoryScreen(),
      ),
      GoRoute(
        path: RoutePaths.missions,
        builder: (_, _) => const MissionsScreen(),
      ),
      GoRoute(
        path: RoutePaths.achievements,
        builder: (_, _) => const AchievementsScreen(),
      ),
      GoRoute(
        path: RoutePaths.leagues,
        builder: (_, _) => const LeaguesScreen(),
      ),
      GoRoute(
        path: RoutePaths.season,
        builder: (_, _) => const SeasonScreen(),
      ),
      GoRoute(
        path: '/app',
        builder: (BuildContext context, GoRouterState state) {
          final ValueNotifier<int> shellIndex = ValueNotifier(0);
          return Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              // Saldo real no topo — MESMO padrão do chip de saldo da home
              // antiga: coins = availableBalance ~/ 1000000 (1 coin = 1e6
              // unidades mínimas). Sem dado => "—".
              final AsyncValue<WalletModel?> walletAsync =
                  ref.watch(walletStreamProvider);
              final WalletModel? wallet = walletAsync.value;
              final String balanceText = wallet?.availableBalance == null
                  ? '—'
                  : (wallet!.availableBalance ~/ BigInt.from(1000000))
                      .toString();
              return PixelShell(
                balanceText: balanceText,
                indexNotifier: shellIndex,
                pages: [
                  PixelHomeScreen(onPlayGames: () => shellIndex.value = 2),
                  const _SalaPlaceholder(),
                  const GamesScreen(),
                  const WalletScreen(),
                ],
                menuItems: [
                  PixelMenuItem(label: 'Mineração', onTap: () => context.push(RoutePaths.mining)),
                  PixelMenuItem(label: 'Loja', onTap: () => context.push(RoutePaths.store)),
                  PixelMenuItem(label: 'Missões', onTap: () => context.push(RoutePaths.missions)),
                  PixelMenuItem(label: 'Conquistas', onTap: () => context.push(RoutePaths.achievements)),
                  PixelMenuItem(label: 'Ligas', onTap: () => context.push(RoutePaths.leagues)),
                  PixelMenuItem(label: 'Temporada', onTap: () => context.push(RoutePaths.season)),
                  PixelMenuItem(label: 'Perfil', onTap: () => context.push(RoutePaths.profile)),
                  PixelMenuItem(label: 'Configurações', onTap: () => context.push(RoutePaths.settings)),
                ],
              );
            },
          );
        },
      ),
      GoRoute(path: RoutePaths.home, redirect: (_, _) => '/app'),
      GoRoute(path: RoutePaths.games, redirect: (_, _) => '/app'),
      GoRoute(path: RoutePaths.mining, redirect: (_, _) => '/app'),
      GoRoute(path: RoutePaths.store, redirect: (_, _) => '/app'),
      GoRoute(path: RoutePaths.profile, redirect: (_, _) => '/app'),
    ],
  );
}

/// Roteador global da aplicação (produção).
final GoRouter appRouter = createAppRouter();

class _SalaPlaceholder extends StatelessWidget {
  const _SalaPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('SALA — próxima etapa',
            style: TextStyle(color: Color(0xFF9AA3B8))),
      ),
    );
  }
}

/// Stream de mudanças de autenticação tolerante a Firebase não inicializado
/// (ex.: ambiente de teste sem google-services.json).
Stream<dynamic> _safeAuthStream(AuthServiceApi auth) {
  try {
    return auth.authStateChanges();
  } catch (_) {
    return const Stream<dynamic>.empty();
  }
}

/// Notifica o [GoRouter] quando o estado de autenticação muda.
class _AuthRefreshStream extends ChangeNotifier {
  _AuthRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen(
      (_) => notifyListeners(),
      onError: (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
