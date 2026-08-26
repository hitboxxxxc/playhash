import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/collections.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/neon_panel.dart';

/// Tela MINHA CONTA: identidade (avatar + nome + e-mail), edição de nome,
/// redefinição de senha (somente conta e-mail/senha), sair e excluir conta.
///
/// Toda ação é protegida por try/catch com SnackBar de erro — falha de
/// rede/permissão nunca derruba a tela.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  static const int _nameMinLength = 3;
  static const int _nameMaxLength = 24;

  void _snack(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        content: Text(
          message,
          style: TextStyle(color: error ? AppColors.error : AppColors.green),
        ),
      ),
    );
  }

  /// Dialogo "Editar nome": TextField validado (3–24 caracteres) que salva
  /// em `users/{uid}.displayName` E no perfil do Firebase Auth.
  Future<void> _editDisplayName(BuildContext context, String current) async {
    final TextEditingController controller =
        TextEditingController(text: current);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar nome'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: _nameMaxLength,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome de exibição',
            hintText: 'Entre 3 e 24 caracteres',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              final String name = controller.text.trim();
              if (name.length < _nameMinLength ||
                  name.length > _nameMaxLength) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surface,
                    content: Text(
                      'O nome deve ter entre 3 e 24 caracteres.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(name);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result == current) return;

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('sessão');
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(user.uid)
          .update(<String, dynamic>{'displayName': result});
      await user.updateDisplayName(result);
      if (context.mounted) _snack(context, 'Nome atualizado.');
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Não foi possível salvar o nome. Tente novamente.',
            error: true);
      }
    }
  }

  /// Redefinição de senha via e-mail (somente provedor e-mail/senha).
  Future<void> _sendPasswordReset(BuildContext context, String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (context.mounted) _snack(context, 'E-mail de recuperação enviado.');
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Não foi possível enviar o e-mail. Tente novamente.',
            error: true);
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Sair da conta'),
            content: const Text('Deseja realmente sair da sua conta?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('CANCELAR'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('SAIR'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // Mesmo com falha local, segue para o login (estado cliente limpo).
    }
    if (context.mounted) context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Map<String, dynamic>?> profile =
        ref.watch(profileStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('MINHA CONTA')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: profile.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              ),
              // Erro/ausência de doc: usa o que o Firebase Auth tiver.
              error: (_, _) => _buildContent(context, ref, null),
              data: (Map<String, dynamic>? doc) =>
                  _buildContent(context, ref, doc),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? doc,
  ) {
    // Corrente ao vivo (sem await): displayName/e-mail do Firebase Auth.
    User? user;
    bool hasPasswordProvider = false;
    try {
      user = FirebaseAuth.instance.currentUser;
      hasPasswordProvider = user?.providerData
              .any((UserInfo info) => info.providerId == 'password') ??
          false;
    } catch (_) {
      user = null; // Firebase indisponível (ex.: testes) => estado vazio
    }

    final String displayName = (doc?['displayName'] as String?)?.trim() != null &&
            (doc!['displayName'] as String).trim().isNotEmpty
        ? (doc['displayName'] as String).trim()
        : (user?.displayName ?? '');
    final String email = (doc?['email'] as String?)?.trim() != null &&
            (doc!['email'] as String).trim().isNotEmpty
        ? (doc['email'] as String).trim()
        : (user?.email ?? '');
    final String initial =
        displayName.isNotEmpty ? displayName.characters.first.toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: <Widget>[
        // Cabeçalho: avatar com inicial + nome + e-mail.
        NeonPanel(
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: AppTheme.neonLabel(
                    fontSize: 22,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName.isEmpty ? 'JOGADOR' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.neonLabel(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? '—' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _AccountAction(
          icon: Icons.edit_outlined,
          label: 'Editar nome',
          onTap: () => _editDisplayName(context, displayName),
        ),
        const SizedBox(height: 10),
        if (hasPasswordProvider && email.isNotEmpty) ...<Widget>[
          _AccountAction(
            icon: Icons.lock_reset_outlined,
            label: 'Alterar senha',
            onTap: () => _sendPasswordReset(context, email),
          ),
          const SizedBox(height: 10),
        ],
        _AccountAction(
          icon: Icons.person_remove_outlined,
          label: 'Excluir conta',
          danger: false,
          onTap: () => context.push(RoutePaths.settings),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('account-sign-out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('SAIR DA CONTA'),
          onPressed: () => _signOut(context, ref),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Linha de ação da conta (ícone + rótulo + chevron) em painel neon.
class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          icon,
          color: danger ? AppColors.gold : AppColors.cyan,
          size: 22,
        ),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        minLeadingWidth: 24,
        onTap: onTap,
      ),
    );
  }
}
