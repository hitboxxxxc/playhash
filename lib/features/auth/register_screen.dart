import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Links institucionais — abertos externamente via url_launcher.
abstract final class AppLinks {
  static final Uri terms = Uri.parse('https://playhash.app/termos');
  static final Uri privacy = Uri.parse('https://playhash.app/privacidade');
}

/// Tela de registro. O aceite dos Termos/Privacidade é OBRIGATÓRIO
/// (checkbox) e gera o `termsAcceptedAt` enviado ao backend.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.authService});

  final AuthServiceApi? authService;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _offline = false;
  bool _acceptedTerms = false;
  String? _error;

  AuthServiceApi get _auth =>
      widget.authService ?? ref.read(authServiceProvider);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _launch(Uri uri) async {
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível abrir o link (${uri.host}).'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(() => _error =
          'Você precisa aceitar os Termos de Uso e a Política de Privacidade.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      await _auth.registerWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        displayName: _nameCtrl.text.trim(),
        termsAcceptedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      context.go('/app/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = isOfflineError(e);
        _error = safeAuthErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('CRIAR CONTA')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child:
                          SvgPicture.string(AppAssets.logoSvg, width: 64),
                    ),
                    const SizedBox(height: 16),
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
                            controller: _nameCtrl,
                            labelText: 'Nome de exibição',
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.name],
                            validator: Validators.displayName,
                          ),
                          const SizedBox(height: 14),
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
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[
                              AutofillHints.newPassword,
                            ],
                            validator: Validators.password,
                          ),
                          const SizedBox(height: 14),
                          NeonTextField(
                            controller: _confirmCtrl,
                            labelText: 'Confirmar senha',
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            autofillHints: const <String>[
                              AutofillHints.newPassword,
                            ],
                            validator: (String? v) =>
                                Validators.confirmPassword(v, _passCtrl.text),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: (bool? v) =>
                                setState(() => _acceptedTerms = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: AppColors.cyan,
                            title: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                const Text(
                                  'Li e aceito os ',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _launch(AppLinks.terms),
                                  child: const Text(
                                    'Termos de Uso',
                                    style: TextStyle(
                                      color: AppColors.cyan,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ' e a ',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _launch(AppLinks.privacy),
                                  child: const Text(
                                    'Política de Privacidade',
                                    style: TextStyle(
                                      color: AppColors.cyan,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(
                                  '.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          NeonButton(
                            label: 'Criar conta',
                            isLoading: _loading,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text(
                          'Já tem conta?',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text(
                            'ENTRAR',
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
