import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

/// Tela "Esqueci minha senha": envia e-mail de redefinição.
/// Mensagem de sucesso é genérica (não revela se o e-mail existe).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.authService});

  final AuthServiceApi? authService;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();

  bool _loading = false;
  bool _sent = false;
  String? _error;

  AuthServiceApi get _auth =>
      widget.authService ?? ref.read(authServiceProvider);

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.sendPasswordReset(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = safeAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('RECUPERAR SENHA')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: NeonPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: SvgPicture.string(
                          AppAssets.mailIconSvg,
                          width: 56,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_sent)
                        Text(
                          'Se este e-mail estiver cadastrado, você receberá '
                          'um link para redefinir sua senha.',
                          textAlign: TextAlign.center,
                          style: AppTheme.neonLabel(
                            fontSize: 14,
                            color: AppColors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else ...<Widget>[
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
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 16),
                        NeonButton(
                          label: 'Enviar link',
                          isLoading: _loading,
                          onPressed: _submit,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
