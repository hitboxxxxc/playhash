/// Modelos de CONQUISTAS (catálogo + progresso do usuário).
///
/// Catálogo: `achievements/{id}` (somente leitura). Progresso:
/// `userAchievements/{uid}/items/{achievementId}` — escrito SOMENTE pelo
/// runner (sem período/reset). Recompensa concedida apenas via claim.
library;

/// Categorias de conquista (abas da tela).
class AchievementCategory {
  const AchievementCategory._();

  static const String all = 'all';
  static const String games = 'games';
  static const String mining = 'mining';
  static const String collection = 'collection';
  static const String missions = 'missions';
}

/// Item do catálogo de conquistas (`achievements/{id}`).
class AchievementModel {
  const AchievementModel({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.metric,
    required this.target,
    required this.rewardCoins,
    required this.enabled,
  });

  final String id;

  /// games | mining | collection | missions.
  final String category;
  final String title;
  final String description;
  final String metric;
  final int target;
  final int rewardCoins;
  final bool enabled;

  static AchievementModel fromMap(String id, Map<String, dynamic> data) {
    final Map<String, dynamic> reward =
        (data['rewardConfig'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final int units = (reward['amountUnits'] as num?)?.toInt() ?? 0;
    return AchievementModel(
      id: id,
      category: (data['category'] as String?) ?? AchievementCategory.games,
      title: (data['title'] as String?) ?? id,
      description: (data['description'] as String?) ?? '',
      metric: (data['metric'] as String?) ?? '',
      target: (data['target'] as num?)?.toInt() ?? 0,
      rewardCoins: units ~/ 1000000,
      enabled: data['enabled'] == true,
    );
  }
}

/// Progresso do usuário (`userAchievements/{uid}/items/{id}`).
class AchievementProgress {
  const AchievementProgress({required this.progress, required this.claimed});

  final int progress;
  final bool claimed;

  static AchievementProgress fromMap(Map<String, dynamic> data) =>
      AchievementProgress(
        progress: (data['progress'] as num?)?.toInt() ?? 0,
        claimed: data['claimed'] == true,
      );
}

/// Visão combinada (catálogo + progresso) consumida pelos cards.
class AchievementView {
  const AchievementView({required this.achievement, required this.progress});

  final AchievementModel achievement;
  final AchievementProgress progress;

  bool get isUnlocked => progress.progress >= achievement.target;

  bool get isClaimable => isUnlocked && !progress.claimed;

  bool get isClaimed => progress.claimed;
}
