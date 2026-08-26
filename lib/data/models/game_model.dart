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
/// Campos v2 (mergulhos, tiros inimigos, power-ups) caem em padrões seguros
/// quando ausentes no doc legado v1.
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
    this.diverKillBonus = 50,
    this.coinBonus = 250,
    // Breakdown (neon-hopper em diante): score OFICIAL = f(breakdown) no
    // backend; aqui são usados só para EXIBIÇÃO da pontuação na partida.
    this.pointsPerStomp = 0,
    this.pointsPerCoin = 0,
    this.flagBonus = 0,
    this.diveIntervalSeconds = 3.0,
    this.diveIntervalMinSeconds = 1.2,
    this.diveRampPerWave = 0.05,
    this.formationShotIntervalSeconds = 4.0,
    this.enemyBulletSpeed = 220,
    this.diverSpeed = 260,
    this.shieldChance = 0.08,
    this.doubleChance = 0.10,
    this.coinChance = 0.12,
    this.shieldSeconds = 6,
    this.doubleSeconds = 8,
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

  // ---- v2: comportamento (paridade com a referência) ----------------------
  final int diverKillBonus; // +50 por abate de diver
  final int coinBonus; // +250 por moeda
  final int pointsPerStomp; // pontos por pisão (0 = game sem breakdown)
  final int pointsPerCoin; // pontos por moeda
  final int flagBonus; // bônus da bandeira final
  final double diveIntervalSeconds; // intervalo base entre mergulhos
  final double diveIntervalMinSeconds; // piso do intervalo (rampa)
  final double diveRampPerWave; // redução do intervalo por wave
  final double formationShotIntervalSeconds; // tiros da formação
  final double enemyBulletSpeed; // px/s da orbe inimiga
  final double diverSpeed; // px/s de descida do diver
  final double shieldChance; // chance de drop por abate
  final double doubleChance;
  final double coinChance;
  final double shieldSeconds; // duração do escudo
  final double doubleSeconds; // duração do tiro duplo

  /// Espelho SOMENTE-LEITURA da constante econômica `powerBasePerHs`
  /// (config/economy, não legível pelo cliente). Usada exclusivamente para
  /// EXIBIÇÃO estimada ("até +X H/s") — nunca para decidir valores.
  static const int powerUnitsPerHs = 1000;

  /// Cap de poder por sessão em H (exibição estimada). 0 = desconhecido.
  int get powerCapPerSessionHs => powerCapPerSessionBaseUnits ~/ powerUnitsPerHs;

  /// Teto de score aceito (maxScore quando definido, senão maxExpectedScore).
  int get scoreCap => maxScore > 0 ? maxScore : maxExpectedScore;

  factory GameConfig.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> chances =
        (map['powerupChances'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, dynamic> durations =
        (map['powerupDurations'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return GameConfig(
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
      diverKillBonus: _int(map['diverKillBonus']),
      coinBonus: _int(map['coinBonus']),
      pointsPerStomp: _int(map['pointsPerStomp']),
      pointsPerCoin: _int(map['pointsPerCoin']),
      flagBonus: _int(map['flagBonus']),
      diveIntervalSeconds: _dbl(map['diveIntervalSeconds']),
      diveIntervalMinSeconds: _dbl(map['diveIntervalMinSeconds']),
      diveRampPerWave: _dbl(map['diveRampPerWave']),
      formationShotIntervalSeconds: _dbl(map['formationShotIntervalSeconds']),
      enemyBulletSpeed: _dbl(map['enemyBulletSpeed']),
      diverSpeed: _dbl(map['diverSpeed']),
      shieldChance: _dbl(chances['shield']),
      doubleChance: _dbl(chances['double']),
      coinChance: _dbl(chances['coin']),
      shieldSeconds: _dbl(durations['shieldSeconds']),
      doubleSeconds: _dbl(durations['doubleSeconds']),
    );
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static double _dbl(Object? v) => (v as num?)?.toDouble() ?? 0;
}
