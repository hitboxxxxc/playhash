import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';

/// Opções do menu vertical do Perfil.
enum ProfileMenuOption {
  account('Minha conta', Icons.person_outline),
  wallet('Carteira', Icons.account_balance_wallet_outlined),
  history('Histórico', Icons.history),
  missions('Missões', Icons.flag_outlined),
  achievements('Conquistas', Icons.emoji_events_outlined),
  leagues('Ligas', Icons.leaderboard_outlined),
  season('Temporada', Icons.calendar_month_outlined),
  referrals('Indicações', Icons.card_giftcard_outlined),
  settings('Configurações', Icons.settings_outlined),
  support('Suporte', Icons.help_outline),
  termsPrivacy('Termos e Privacidade', Icons.description_outlined);

  const ProfileMenuOption(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Menu vertical do Perfil. Cada opção dispara [onItemTap]; itens futuros
/// apontam para rotas placeholder "Em breve" (decisão da tela chamadora).
class ProfileMenuList extends StatelessWidget {
  const ProfileMenuList({
    super.key,
    required this.onItemTap,
  });

  final ValueChanged<ProfileMenuOption> onItemTap;

  @override
  Widget build(BuildContext context) {
    final List<ProfileMenuOption> options = ProfileMenuOption.values;

    // Material transparente: permite que os ListTiles pintem ink splashes
    // sobre o fundo do painel (evita assertion do Material).
    return NeonPanel(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            ListTile(
              key: ValueKey<ProfileMenuOption>(options[i]),
              leading: Icon(
                options[i].icon,
                color: AppColors.cyan,
                size: 22,
              ),
              title: Text(
                options[i].title,
                style: const TextStyle(fontSize: 14),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
              minLeadingWidth: 24,
              onTap: () => onItemTap(options[i]),
            ),
            if (i < options.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.textSecondary.withValues(alpha: 0.15),
              ),
          ],
        ],
        ),
      ),
    );
  }
}
