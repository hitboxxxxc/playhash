/// Espelho SOMENTE-LEITURA de um item do catálogo `config/machines/{id}`.
/// Preço, poder, raridade e limites são SEMPRE do backend — o cliente
/// apenas exibe e envia a intenção de compra.
class MachineCatalogModel {
  const MachineCatalogModel({
    required this.id,
    required this.name,
    required this.rarity,
    required this.powerUnits,
    required this.priceUnits,
    required this.maxPerUser,
    required this.enabled,
    this.currencyId = 'coins',
    this.maxLevel = 1,
    this.levelPowerStep = 0.0,
    this.upgradeCostFactor = 0.0,
  });

  final String id;
  final String name;

  /// 'common' | 'rare' | 'epic' | 'legendary' (v2). Vazio = legado.
  final String rarity;

  /// Poder permanente em H/s (unidade-base inteira).
  final int powerUnits;

  /// Preço em unidades mínimas inteiras (1 coin = 1.000.000 units).
  final BigInt priceUnits;

  /// Limite de unidades por usuário (0 = sem limite informado).
  final int maxPerUser;

  final bool enabled;
  final String currencyId;

  /// Nível máximo da máquina (default 1 = sem upgrade).
  final int maxLevel;

  /// Incremento de poder por nível (ex.: 0.25 = 25% do poder base por nível).
  final double levelPowerStep;

  /// Fator de custo de upgrade: custo = price * factor * currentLevel.
  final double upgradeCostFactor;

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static BigInt _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) return BigInt.tryParse(value) ?? BigInt.zero;
    return BigInt.zero;
  }

  factory MachineCatalogModel.fromMap(String id, Map<String, dynamic> map) =>
      MachineCatalogModel(
        id: id,
        name: ((map['name'] as String?) ?? id).trim(),
        rarity: ((map['rarity'] as String?) ?? '').toLowerCase().trim(),
        powerUnits: _toInt(map['powerUnits'] ?? map['powerAmount']),
        priceUnits: _toBigInt(map['priceUnits']),
        maxPerUser: _toInt(map['maxPerUser']),
        enabled: map['enabled'] == true,
        currencyId: (map['currencyId'] as String?) ?? 'coins',
        maxLevel: _toInt(map['maxLevel'] ?? 1),
        levelPowerStep: _toDouble(map['levelPowerStep'] ?? 0.0),
        upgradeCostFactor: _toDouble(map['upgradeCostFactor'] ?? 0.0),
      );
}
