import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/neon_button.dart';
import '../../core/widgets/neon_panel.dart';

enum _GateStatus { loading, ready, error }

/// Gate inicial do app:
/// 1. Inicializa Firebase (com retry em caso de erro);
/// 2. Observa authStateChanges e roteia para Home ou Login.
///
/// Captura ausência de configuração Firebase (google-services.json ausente)
/// com mensagem amigável — sem stack traces expostos ao usuário.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  _GateStatus _status = _GateStatus.loading;
  String _errorMessage =
      'Não foi possível iniciar o app. Verifique sua conexão e tente novamente.';
  bool _navigated = false;

  /// Navega uma única vez para a rota inicial correta (shell ou login).
  void _navigateOnce(bool signedIn) {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(signedIn ? RoutePaths.home : RoutePaths.login);
    });
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _status = _GateStatus.loading);
    try {
      await FirebaseService.init();
      if (!mounted) return;
      setState(() => _status = _GateStatus.ready);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _GateStatus.error;
        _errorMessage = _friendlyMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _GateStatus.error;
        _errorMessage =
            'Não foi possível iniciar o app. Verifique sua conexão '
            'e tente novamente.';
      });
    }
  }

  /// Mensagem amigável quando falta configuração (google-services.json).
  String _friendlyMessage(FirebaseException e) {
    final String code = e.code.toLowerCase();
    final String msg = e.message?.toLowerCase() ?? '';
    if (code.contains('no-options') ||
        msg.contains('no-options') ||
        msg.contains('googleserviceprovider') ||
        msg.contains('default firebaseapp is not initialized')) {
      return 'O app ainda não está configurado com o Firebase. '
          'Adicione o arquivo google-services.json em android/app/ '
          'e reinstale o aplicativo.';
    }
    return 'Não foi possível conectar aos serviços do PlayHash. '
        'Verifique sua conexão e tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _GateStatus.loading:
        return const _SplashView();
      case _GateStatus.error:
        return _ErrorView(message: _errorMessage, onRetry: _bootstrap);
      case _GateStatus.ready:
        final AuthServiceApi auth = ref.read(authServiceProvider);
        return StreamBuilder<User?>(
          stream: auth.authStateChanges(),
          builder:
              (BuildContext context, AsyncSnapshot<User?> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _SplashView();
            }
            final bool signedIn = snapshot.data != null;
            _navigateOnce(signedIn);
            return const _SplashView();
          },
        );
    }
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.string(AppAssets.logoSvg, width: 96),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppColors.cyan),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: NeonPanel(
              accent: AppColors.error,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SvgPicture.string(AppAssets.logoSvg, width: 64),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  NeonButton(label: 'Tentar novamente', onPressed: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
