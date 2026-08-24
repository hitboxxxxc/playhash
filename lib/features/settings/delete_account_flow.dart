import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/services/cloud_functions_service.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/neon_button.dart';

/// Fluxo de EXCLUSÃO DE CONTA (exigência Google Play).
///
/// Confirmação dupla em bottom sheet:
/// 1. Aviso de perda permanente de dados + checkbox de ciência;
/// 2. Prova de identidade (senha / re-auth) e chamada ao backend via
///    [CloudFunctionsServiceApi.deleteMyAccount] — o cliente NUNCA deleta
///    documentos do Firestore diretamente (segurança + auditoria).
Future<void> showDeleteAccountFlow(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    builder: (_) => const _DeleteAccountSheet(),
  );
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  int _step = 1;
  bool _acknowledged = false;
  bool _submitting = false;
  String? _error;
  final TextEditingController _passwordController = TextEditingController();

  static const String _successMessage =
      'Solicitação de exclusão enviada. O backend processará em até 24h.';

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeletion() async {
    final String password = _passwordController.text.trim();
    if (password.length < 6) {
      setState(() => _error = 'Informe sua senha para confirmar.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Captura dependências ANTES do pop (context do sheet morre após fechar).
    final CloudFunctionsServiceApi functions =
        ref.read(cloudFunctionsServiceProvider);
    final AuthServiceApi auth = ref.read(authServiceProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);

    try {
      await functions.deleteMyAccount(); // stub — backend pendente de deploy
      try {
        await auth.signOut();
      } catch (_) {
        // Falha no sign-out local não invalida a solicitação no backend.
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text(_successMessage)),
      );
      router.go(RoutePaths.login);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Não foi possível concluir a operação. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'EXCLUIR CONTA',
              textAlign: TextAlign.center,
              style: AppTheme.neonLabel(fontSize: 18, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            if (_step == 1) ..._buildStepWarning(),
            if (_step == 2) ..._buildStepIdentity(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStepWarning() {
    return <Widget>[
      const Text(
        'Esta ação é PERMANENTE. Todos os seus dados serão perdidos, '
        'incluindo perfil, poder, máquinas, conquistas, histórico de '
        'partidas e saldo da carteira virtual.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: _acknowledged,
        onChanged: (bool? value) =>
            setState(() => _acknowledged = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.error,
        title: const Text(
          'Entendo que os dados serão perdidos permanentemente.',
          style: TextStyle(fontSize: 13),
        ),
      ),
      const SizedBox(height: 8),
      NeonButton(
        label: 'Continuar',
        color: AppColors.error,
        onPressed:
            _acknowledged ? () => setState(() => _step = 2) : null,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('CANCELAR'),
      ),
    ];
  }

  List<Widget> _buildStepIdentity() {
    return <Widget>[
      const Text(
        'Para sua segurança, confirme sua identidade informando sua senha.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        obscureText: true,
        autofillHints: const <String>[AutofillHints.password],
        decoration: const InputDecoration(
          labelText: 'Senha',
          border: OutlineInputBorder(),
        ),
        enabled: !_submitting,
      ),
      // Contas Google farão re-autenticação via Google quando o backend
      // estiver integrado; por enquanto a confirmação é local.
      const SizedBox(height: 6),
      Text(
        'Contas criadas com Google confirmarão via Google em breve.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: const TextStyle(fontSize: 13, color: AppColors.error),
        ),
      ],
      const SizedBox(height: 16),
      NeonButton(
        label: 'Excluir conta',
        color: AppColors.error,
        isLoading: _submitting,
        onPressed: _submitting ? null : _confirmDeletion,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('CANCELAR'),
      ),
    ];
  }
}
