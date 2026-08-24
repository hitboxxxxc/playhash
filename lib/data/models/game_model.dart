/// Modelo do catálogo de jogos (`games/{gameId}`).
///
/// A config econômica é SEMPRE a recebida do backend — o cliente NUNCA
/// decide valores econômicos (doc 05 §51). Campos ausentes no doc legado
/// caem em 0/'' e são tratados como "não definido".
class GameModel {
  const GameModel({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.enabled,
    required this.version,
    required this.configuration,
  });

  final String id;
  final String name;
  final String difficulty;
  final bool enabled;
  final int version;
  final GameConfig configuration;

  factory GameModel.fromMap(String id, Map<String, dynamic> map) {
    final Map<String, dynamic> rawCfg =
        (map['configuration'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return GameModel(
      id: id,
      name: (map['name'] as String?) ?? id,
      difficulty: (map['difficulty'] as String?) ?? '',
      enabled: map['enabled'] == true,
      version: (map['version'] as num?)?.toInt() ?? 1,
      configuration: GameConfig.fromMap(rawCfg),
    );
  }
}

/// Configuração de gameplay/economia de um game (autoridade: backend).
class GameConfig {
  const GameConfig({
    required this.durationSeconds,
    required this.baseEnemies,
    required this.enemiesPerWaveStep,
    required this.enemyHp,
    required this.lives,
    required this.pointsPerKill,
    required this.pointsPerHit,
    required this.waveBonus,
    required this.maxScore,
    required this.maxScorePerSecond,
    required this.minDurationSeconds,
    required this.maxExpectedScore,
    required this.powerCapPerSessionBaseUnits,
    required this.powerFormula,
  });

  final int durationSeconds;
  final int baseEnemies;
  final int enemiesPerWaveStep;
  final int enemyHp;
  final int lives;
  final int pointsPerKill;
  final int pointsPerHit;
  final int waveBonus;
  final int maxScore;
  final int maxScorePerSecond;
  final int minDurationSeconds;
  final int maxExpectedScore;
  final int powerCapPerSessionBaseUnits;
  final String powerFormula;

  /// Espelho SOMENTE-LEITURA da constante econômica `powerBasePerHs`
  /// (config/economy, não legível pelo cliente). Usada exclusivamente para
  /// EXIBIÇÃO estimada ("até +X H/s") — nunca para decidir valores.
  static const int powerUnitsPerHs = 1000;

  /// Cap de poder por sessão em H (exibição estimada). 0 = desconhecido.
  int get powerCapPerSessionHs => powerCapPerSessionBaseUnits ~/ powerUnitsPerHs;

  /// Teto de score aceito (maxScore quando definido, senão maxExpectedScore).
  int get scoreCap => maxScore > 0 ? maxScore : maxExpectedScore;

  factory GameConfig.fromMap(Map<String, dynamic> map) => GameConfig(
        durationSeconds: _int(map['durationSeconds']),
        baseEnemies: _int(map['baseEnemies']),
        enemiesPerWaveStep: _int(map['enemiesPerWaveStep']),
        enemyHp: _int(map['enemyHp']),
        lives: _int(map['lives']),
        pointsPerKill: _int(map['pointsPerKill']),
        pointsPerHit: _int(map['pointsPerHit']),
        waveBonus: _int(map['waveBonus']),
        maxScore: _int(map['maxScore']),
        maxScorePerSecond: _int(map['maxScorePerSecond']),
        minDurationSeconds: _int(map['minDurationSeconds']),
        maxExpectedScore: _int(map['maxExpectedScore']),
        powerCapPerSessionBaseUnits: _int(map['powerCapPerSessionBaseUnits']),
        powerFormula: (map['powerFormula'] as String?) ?? '',
      );

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;
}
