/// Modelos de LIGAS (catálogo + liga do usuário + ranking).
///
/// Tudo é SOMENTE LEITURA: atribuição de liga, promoção, leaderboard e
/// recompensa diária são decididos 100% pelo backend (league_sweep no
/// runner — docs 03/05). O cliente nunca calcula nem concede nada.
library;

/// Item do catálogo de ligas (`leagues/{id}`).
class LeagueModel {
  const LeagueModel({
    required this.id,
    required this.name,
    required this.tier,
    required this.minPower,
    required this.dailyRewardCoins,
    required this.colorValue,
  });

  final String id;

  /// Nome exibido (BRONZE, PRATA, OURO, PLATINA, DIAMANTE).
  final String name;

  /// 1..5 (maior tier = liga superior).
  final int tier;

  /// Limiar de poder em unidades-base (H/s) — apresentação apenas.
  final int minPower;

  /// Recompensa diária em coins (units ÷ 1e6 — valor oficial é o doc).
  final int dailyRewardCoins;

  /// Cor do tier (hex do doc, ex.: 0xFFF5C542).
  final int colorValue;

  static LeagueModel fromMap(String id, Map<String, dynamic> data) {
    return LeagueModel(
      id: id,
      name: (data['name'] as String?) ?? id,
      tier: (data['tier'] as num?)?.toInt() ?? 0,
      // minPowerUnits é em units BASE (powerBasePerHs = 1.000 ⇒ ÷ 1.000 = H/s).
      minPower: ((data['minPowerUnits'] as num?)?.toInt() ?? 0) ~/ 1000,
      dailyRewardCoins: ((data['dailyRewardUnits'] as num?)?.toInt() ?? 0) ~/ 1000000,
      colorValue: _parseColor(data['color'] as String?),
    );
  }

  static int _parseColor(String? hex) {
    if (hex == null || hex.length < 7) return 0xFF00E5FF;
    return int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFF00E5FF;
  }
}

/// Liga atual do usuário (`userLeagues/{uid}` — escrita SOMENTE do backend).
class UserLeagueModel {
  const UserLeagueModel({
    required this.leagueId,
    required this.leagueName,
    this.lastDailyGrant,
  });

  final String leagueId;
  final String leagueName;

  /// Dia UTC do último grant da recompensa diária (ex.: '2026-08-24').
  final String? lastDailyGrant;

  static UserLeagueModel fromMap(Map<String, dynamic> data) {
    return UserLeagueModel(
      leagueId: (data['leagueId'] as String?) ?? '',
      leagueName: (data['leagueName'] as String?) ?? '',
      lastDailyGrant: data['lastDailyGrant'] as String?,
    );
  }
}

/// Entrada do ranking da liga (`leaderboards/{leagueId}/entries/{uid}`).
/// Expõe APENAS maskedName — nunca dados pessoais (rules: escrita backend).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.maskedName,
    required this.totalPower,
  });

  final String uid;
  final String maskedName;

  /// Poder total em unidades-base (H/s).
  final int totalPower;

  static LeaderboardEntry fromMap(String id, Map<String, dynamic> data) {
    return LeaderboardEntry(
      uid: id,
      maskedName: (data['maskedName'] as String?) ?? '??***',
      totalPower: (data['totalPower'] as num?)?.toInt() ?? 0,
    );
  }
}
