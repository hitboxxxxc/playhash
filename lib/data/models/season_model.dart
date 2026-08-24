/// Modelos de TEMPORADA (doc da season + progresso do usuário).
///
/// XP, nível e trilhas são 100% derivados pelo backend (season_progress +
/// processClaims). O cliente apenas EXIBE — nunca calcula nem concede.
library;

/// Recompensa de um nível da trilha do passe.
class SeasonReward {
  const SeasonReward({required this.type, required this.amountCoins});

  final String type;
  final int amountCoins;

  static SeasonReward fromMap(Map<String, dynamic> data) {
    return SeasonReward(
      type: (data['type'] as String?) ?? 'coins',
      amountCoins: ((data['amountUnits'] as num?)?.toInt() ?? 0) ~/ 1000000,
    );
  }
}

/// Doc `seasons/{id}` (fonte oficial de nome, janela e trilhas).
class SeasonModel {
  const SeasonModel({
    required this.id,
    required this.name,
    required this.startAt,
    required this.endAt,
    required this.levelXp,
    required this.freeTrack,
    required this.premiumTrack,
  });

  final String id;
  final String name;
  final DateTime startAt;
  final DateTime endAt;

  /// XP linear por nível (doc — o cliente NÃO deriva nível por conta própria;
  /// o nível oficial vem de seasonProgress/{uid} escrito pelo backend).
  final int levelXp;
  final List<SeasonReward> freeTrack;
  final List<SeasonReward> premiumTrack;

  bool isActive(DateTime now) => now.isAfter(startAt) && now.isBefore(endAt);

  static SeasonModel fromMap(String id, Map<String, dynamic> data) {
    DateTime parseTs(Object? raw) {
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      final dynamic t = raw;
      try {
        return (t.toDate() as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    List<SeasonReward> parseTrack(Object? raw) {
      if (raw is! List) return const <SeasonReward>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SeasonReward.fromMap)
          .toList(growable: false);
    }

    final Map<String, dynamic> tracks =
        (data['tracks'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return SeasonModel(
      id: id,
      name: (data['name'] as String?) ?? id,
      startAt: parseTs(data['startAt']),
      endAt: parseTs(data['endAt']),
      levelXp: (data['levelXp'] as num?)?.toInt() ?? 1200,
      freeTrack: parseTrack(tracks['free']),
      premiumTrack: parseTrack(tracks['premium']),
    );
  }
}

/// Progresso do usuário na temporada (`seasonProgress/{uid}` — backend).
class SeasonProgressModel {
  const SeasonProgressModel({
    required this.seasonId,
    required this.xp,
    required this.level,
    required this.claimedFree,
    required this.claimedPremium,
    required this.premiumActive,
  });

  final String seasonId;
  final int xp;

  /// Nível OFICIAL derivado pelo backend (só sobe — nunca pelo cliente).
  final int level;
  final Set<int> claimedFree;
  final Set<int> claimedPremium;
  final bool premiumActive;

  static SeasonProgressModel fromMap(Map<String, dynamic> data) {
    Set<int> parseClaimed(Object? raw) {
      if (raw is! Map) return const <int>{};
      return raw.keys
          .map((dynamic k) => int.tryParse(k.toString()) ?? -1)
          .where((int v) => v > 0)
          .toSet();
    }

    return SeasonProgressModel(
      seasonId: (data['seasonId'] as String?) ?? '',
      xp: (data['xp'] as num?)?.toInt() ?? 0,
      level: (data['level'] as num?)?.toInt() ?? 1,
      claimedFree: parseClaimed(data['claimedFree']),
      claimedPremium: parseClaimed(data['claimedPremium']),
      premiumActive: data['premiumActive'] == true,
    );
  }
}
