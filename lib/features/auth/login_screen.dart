import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/neon_button.dart';
import '../../core/widgets/neon_panel.dart';
import '../../core/widgets/neon_text_field.dart';

/// Tela de login: e-mail/senha + Google.
/// Estados tratados: loading, erro (mensagem segura) e offline.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.authService,
    this.onSuccess,
  });

  /// Injetável para testes (FakeAuthService) — sem tocar no Firebase.
  final AuthServiceApi? authService;

  /// Callback opcional de sucesso (usado em testes); padrão navega p/ /home.
  final VoidCallback? onSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  bool _offline = false;
  String? _error;

  AuthServiceApi get _auth =>
      widget.authService ?? ref.read(authServiceProvider);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loadingEmail = true;
      _error = null;
      _offline = false;
    });
    try {
      await _auth.signInWithEmail(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      _handleSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = isOfflineError(e);
        _error = safeAuthErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _signInGoogle() async {
    setState(() {
      _loadingGoogle = true;
      _error = null;
      _offline = false;
    });
    try {
      await _auth.signInWithGoogle();
      if (!mounted) return;
      _handleSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = isOfflineError(e);
        _error = safeAuthErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  void _handleSuccess() {
    if (widget.onSuccess != null) {
      widget.onSuccess!();
    } else {
      context.go('/app/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      label: 'PlayHash',
                      child: Center(
                        child:
                            SvgPicture.string(AppAssets.logoSvg, width: 88),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ENTRAR',
                      textAlign: TextAlign.center,
                      style: AppTheme.neonLabel(fontSize: 22),
                    ),
                    const SizedBox(height: 24),
                    NeonPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_offline)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Sem conexão — verifique sua internet.',
                                style: AppTheme.neonLabel(
                                  fontSize: 13,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error!,
                                style: AppTheme.neonLabel(
                                  fontSize: 13,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          NeonTextField(
                            controller: _emailCtrl,
                            labelText: 'E-mail',
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.email],
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 14),
                          NeonTextField(
                            controller: _passCtrl,
                            labelText: 'Senha',
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            validator: Validators.password,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loadingEmail || _loadingGoogle
                                  ? null
                                  : () => context.go('/forgot-password'),
                              child: const Text(
                                'Esqueci minha senha',
                                style: TextStyle(
                                  color: AppColors.cyan,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          NeonButton(
                            label: 'Entrar',
                            isLoading: _loadingEmail,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 14),
                          NeonButton(
                            label: 'Entrar com Google',
                            color: AppColors.purple,
                            isLoading: _loadingGoogle,
                            onPressed: _signInGoogle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text(
                          'Não tem conta?',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () => context.go('/register'),
                          child: const Text(
                            'CADASTRE-SE',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
