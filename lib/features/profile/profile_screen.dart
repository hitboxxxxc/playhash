import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/profile_header_card.dart';
import 'widgets/profile_menu_list.dart';
import 'widgets/stats_grid.dart';

/// Perfil do usuário: cabeçalho com dados reais do Firestore (`users/{uid}`),
/// grade de estatísticas (placeholders até o backend existir), menu de seções
/// e botão SAIR DA CONTA funcional.
///
/// O perfil observa snapshots em tempo real: edições de displayName feitas em
/// outras telas refletem aqui automaticamente.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final AuthServiceApi auth = ref.read(authServiceProvider);
    try {
      await auth.signOut();
    } catch (_) {
      // Mesmo com falha local, segue para o login (estado cliente limpo).
    }
    if (context.mounted) context.go(RoutePaths.login);
  }

  /// Converte o campo `createdAt` (Timestamp | DateTime | null) com segurança.
  static DateTime? _parseCreatedAt(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  void _openMenuOption(BuildContext context, ProfileMenuOption option) {
    switch (option) {
      case ProfileMenuOption.settings:
        context.push(RoutePaths.settings);
      case ProfileMenuOption.missions:
        context.push(RoutePaths.missions);
      case ProfileMenuOption.achievements:
        context.push(RoutePaths.achievements);
      default:
        context.push(
          '${RoutePaths.comingSoon}?titulo=${Uri.encodeComponent(option.title)}',
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Map<String, dynamic>?> profile =
        ref.watch(profileStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('PERFIL')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: profile.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              ),
              // Erro e documento inexistente caem no mesmo estado vazio:
              // menu e sair da conta permanecem acessíveis.
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
    final Object? createdAt = doc?['createdAt'];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: <Widget>[
        ProfileHeaderCard(
          displayName: doc?['displayName'] as String?,
          photoUrl: doc?['photoUrl'] as String?,
          createdAt: _parseCreatedAt(createdAt),
        ),
        const SizedBox(height: 16),
        Text(
          'ESTATÍSTICAS',
          style: AppTheme.neonLabel(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const StatsGrid(),
        const SizedBox(height: 16),
        ProfileMenuList(
          onItemTap: (ProfileMenuOption option) =>
              _openMenuOption(context, option),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
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
