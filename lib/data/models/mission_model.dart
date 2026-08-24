/// Modelos de MISSÕES (catálogo + progresso do usuário).
///
/// O catálogo vem de `missions/{id}` (somente leitura) e o progresso de
/// `userMissions/{uid}/items/{missionId}` (escrito SOMENTE pelo runner a
/// partir de eventos reais). O cliente NUNCA calcula nem concede recompensa.
library;

/// Item do catálogo de missões (`missions/{id}`).
class MissionModel {
  const MissionModel({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.metric,
    required this.target,
    required this.rewardCoins,
    required this.enabled,
  });

  final String id;

  /// 'daily' | 'weekly'.
  final String kind;
  final String title;
  final String description;

  /// Métrica de progresso (plays · max_score · kills · buys).
  final String metric;
  final int target;

  /// Recompensa em coins (apresentação; units ÷ 1e6 — valor oficial é o
  /// rewardConfig do catálogo processado pelo runner).
  final int rewardCoins;
  final bool enabled;

  static MissionModel fromMap(String id, Map<String, dynamic> data) {
    final Map<String, dynamic> reward =
        (data['rewardConfig'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final int units = (reward['amountUnits'] as num?)?.toInt() ?? 0;
    return MissionModel(
      id: id,
      kind: (data['kind'] as String?) ?? 'daily',
      title: (data['title'] as String?) ?? id,
      description: (data['description'] as String?) ?? '',
      metric: (data['metric'] as String?) ?? '',
      target: (data['target'] as num?)?.toInt() ?? 0,
      // 1 coin = 1_000_000 units (config/economy.coinPrecision).
      rewardCoins: units ~/ 1000000,
      enabled: data['enabled'] == true,
    );
  }
}

/// Progresso do usuário para uma missão (`userMissions/{uid}/items/{id}`).
class MissionProgress {
  const MissionProgress({required this.progress, required this.claimed});

  final int progress;
  final bool claimed;

  static MissionProgress fromMap(Map<String, dynamic> data) => MissionProgress(
        progress: (data['progress'] as num?)?.toInt() ?? 0,
        claimed: data['claimed'] == true,
      );
}

/// Visão combinada (catálogo + progresso) consumida pelos cards.
class MissionView {
  const MissionView({required this.mission, required this.progress});

  final MissionModel mission;
  final MissionProgress progress;

  bool get isComplete => progress.progress >= mission.target;

  /// Completa e ainda não resgatada ⇒ botão RESGATAR.
  bool get isClaimable => isComplete && !progress.claimed;

  bool get isClaimed => progress.claimed;
}
