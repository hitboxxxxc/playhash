import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Espelho SOMENTE-LEITURA de um item em `machines/{uid}/items/{itemId}`.
/// Compra, upgrade e ativação de máquinas são responsabilidade EXCLUSIVA
/// do backend — o cliente apenas exibe.
class MachineModel {
  const MachineModel({
    required this.id,
    required this.type,
    required this.level,
    required this.power,
    this.purchasedAt,
    required this.active,
    this.metadata = const <String, dynamic>{},
  });

  final String id;

  /// Tipo da máquina (ex.: 'rig', 'server', 'terminal') — informativo.
  final String type;

  /// Nível atual (exibido no badge "LV.X").
  final int level;

  /// Poder da máquina (unidade-base inteira H/s).
  final int power;

  final DateTime? purchasedAt;

  /// Máquina ativa (inativa não conta para totais exibidos).
  final bool active;

  /// Metadados adicionais (ex.: `rarity` para cor do ícone).
  final Map<String, dynamic> metadata;

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Campos do backend (runner): machineId, name, rarity, level, active,
  /// powerAmount (H/s), acquiredAt. Campos legados (type/power/purchasedAt)
  /// continuam aceitos para compatibilidade.
  factory MachineModel.fromMap(String id, Map<String, dynamic> map) {
    final Map<String, dynamic> metadata = map['metadata'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(map['metadata'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final Object? rarity = map['rarity'];
    if (rarity is String && rarity.isNotEmpty) metadata['rarity'] = rarity;
    return MachineModel(
      id: id,
      type: ((map['machineId'] as String?) ?? (map['type'] as String?) ?? '')
          .trim(),
      level: map['level'] != null ? _toInt(map['level']) : 1,
      power: _toInt(map['powerAmount'] ?? map['power']),
      purchasedAt: _toDate(map['acquiredAt'] ?? map['purchasedAt']),
      active: map['active'] is bool ? map['active'] as bool : true,
      metadata: metadata,
    );
  }
}
