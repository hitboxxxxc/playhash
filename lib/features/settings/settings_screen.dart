import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'delete_account_flow.dart';
import 'widgets/settings_section.dart';

/// Tela de CONFIGURAÇÕES.
///
/// - Notificações: preferências persistidas em `users/{uid}.settings.notifications`;
/// - Aplicativo: preferências locais (som/música/idioma/tema — tema é dark-neon fixo);
/// - Privacidade: documentos legais via url_launcher + EXCLUIR CONTA;
/// - Rodapé: versão do app via package_info_plus.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Notificações (persistidas no Firestore).
  bool _notifyRewards = true;
  bool _notifyMissions = true;
  bool _notifyEvents = true;

  // Aplicativo (preferências locais por enquanto).
  bool _sound = true;
  bool _music = true;

  static const String _privacyUrl = 'https://playhash.app/privacidade';
  static const String _termsUrl = 'https://playhash.app/termos';

  Future<void> _saveNotificationPrefs() async {
    final String? uid;
    try {
      uid = await ref.read(currentUidProvider.future);
    } catch (_) {
      return; // sem sessão — nada a salvar
    }
    if (uid == null) return; // sem sessão — nada a salvar

    try {
      await ref.read(profileRepositoryProvider).saveNotificationPreferences(
        uid,
        <String, dynamic>{
          'rewards': _notifyRewards,
          'missions': _notifyMissions,
          'events': _notifyEvents,
        },
      );
    } catch (_) {
      // Falha silenciosa e sem dados sensíveis em log; o estado local
      // permanece como fonte da UI até nova tentativa.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar as preferências.'),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir: $url')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    }
  }

  void _pushComingSoon(String title) => context.push(
        '${RoutePaths.comingSoon}?titulo=${Uri.encodeComponent(title)}',
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONFIGURAÇÕES')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: <Widget>[
                // ---- CONTA ------------------------------------------------
                SettingsSection(
                  title: 'Conta',
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.edit_outlined,
                          color: AppColors.cyan),
                      title: const Text('Editar perfil',
                          style: TextStyle(fontSize: 14)),
                      onTap: () => _pushComingSoon('Editar perfil'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline,
                          color: AppColors.cyan),
                      title: const Text('Alterar senha',
                          style: TextStyle(fontSize: 14)),
                      onTap: () => _pushComingSoon('Alterar senha'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.security_outlined,
                          color: AppColors.cyan),
                      title:
                          const Text('Segurança', style: TextStyle(fontSize: 14)),
                      onTap: () => _pushComingSoon('Segurança'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- NOTIFICAÇÕES ----------------------------------------
                SettingsSection(
                  title: 'Notificações',
                  children: <Widget>[
                    SwitchListTile(
                      value: _notifyRewards,
                      onChanged: (bool value) {
                        setState(() => _notifyRewards = value);
                        _saveNotificationPrefs();
                      },
                      activeThumbColor: AppColors.cyan,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recompensas',
                          style: TextStyle(fontSize: 14)),
                    ),
                    SwitchListTile(
                      value: _notifyMissions,
                      onChanged: (bool value) {
                        setState(() => _notifyMissions = value);
                        _saveNotificationPrefs();
                      },
                      activeThumbColor: AppColors.cyan,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Missões',
                          style: TextStyle(fontSize: 14)),
                    ),
                    SwitchListTile(
                      value: _notifyEvents,
                      onChanged: (bool value) {
                        setState(() => _notifyEvents = value);
                        _saveNotificationPrefs();
                      },
                      activeThumbColor: AppColors.cyan,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Eventos',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- APLICATIVO ------------------------------------------
                SettingsSection(
                  title: 'Aplicativo',
                  children: <Widget>[
                    SwitchListTile(
                      value: _sound,
                      onChanged: (bool value) =>
                          setState(() => _sound = value),
                      activeThumbColor: AppColors.cyan,
                      contentPadding: EdgeInsets.zero,
                      title:
                          const Text('Som', style: TextStyle(fontSize: 14)),
                    ),
                    SwitchListTile(
                      value: _music,
                      onChanged: (bool value) =>
                          setState(() => _music = value),
                      activeThumbColor: AppColors.cyan,
                      contentPadding: EdgeInsets.zero,
                      title:
                          const Text('Música', style: TextStyle(fontSize: 14)),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          const Icon(Icons.language, color: AppColors.cyan),
                      title: const Text('Idioma',
                          style: TextStyle(fontSize: 14)),
                      trailing: const Text(
                        'Português (BR)',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      onTap: () => _pushComingSoon('Idioma'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.dark_mode_outlined,
                          color: AppColors.cyan),
                      title:
                          const Text('Tema', style: TextStyle(fontSize: 14)),
                      trailing: const Text(
                        'Escuro (neon)',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      onTap: () => _pushComingSoon('Tema'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- PRIVACIDADE -----------------------------------------
                SettingsSection(
                  title: 'Privacidade',
                  accent: AppColors.error,
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.policy_outlined,
                          color: AppColors.cyan),
                      title: const Text('Política de Privacidade',
                          style: TextStyle(fontSize: 14)),
                      onTap: () => _openUrl(_privacyUrl),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined,
                          color: AppColors.cyan),
                      title: const Text('Termos de Uso',
                          style: TextStyle(fontSize: 14)),
                      onTap: () => _openUrl(_termsUrl),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_forever,
                          color: AppColors.error),
                      title: Text(
                        'EXCLUIR CONTA',
                        style: AppTheme.neonLabel(
                          fontSize: 14,
                          color: AppColors.error,
                        ),
                      ),
                      subtitle: const Text(
                        'Exclusão permanente dos seus dados',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      onTap: () => showDeleteAccountFlow(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- SUPORTE ----------------------------------------------
                SettingsSection(
                  title: 'Suporte',
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.help_outline,
                          color: AppColors.cyan),
                      title:
                          const Text('Ajuda', style: TextStyle(fontSize: 14)),
                      onTap: () => _pushComingSoon('Ajuda'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mail_outline,
                          color: AppColors.cyan),
                      title: const Text('Contato',
                          style: TextStyle(fontSize: 14)),
                      onTap: () => _pushComingSoon('Contato'),
                    ),
                  ],
                ),

                // ---- RODAPÉ: VERSÃO ---------------------------------------
                const SizedBox(height: 24),
                FutureBuilder<String>(
                  future: _loadVersion(),
                  builder:
                      (BuildContext context, AsyncSnapshot<String> snapshot) {
                    return Center(
                      child: Text(
                        'VERSÃO ${snapshot.data ?? '—'}',
                        style: AppTheme.neonLabel(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Versão do app; fallback seguro quando plugin indisponível (ex.: testes).
  Future<String> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.0.0';
    }
  }
}
