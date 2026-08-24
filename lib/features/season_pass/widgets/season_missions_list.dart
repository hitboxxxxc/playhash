import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/mission_model.dart';
import '../../missions/widgets/mission_card.dart';

/// Missões da TEMPORADA (kind='season') reutilizando [MissionCard] —
/// progresso/claim idênticos às missões diárias (intenção `claims`
/// validada pelo runner; o cliente nunca concede recompensa).
class SeasonMissionsList extends ConsumerWidget {
  const SeasonMissionsList({super.key, required this.views});

  final List<MissionView> views;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (views.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Nenhuma missão de temporada disponível agora.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (int i = 0; i < views.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 12),
          MissionCard(
            view: views[i],
            onPlay: () => context.push(RoutePaths.games),
          ),
        ],
      ],
    );
  }
}
