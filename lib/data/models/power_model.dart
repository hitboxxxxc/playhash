import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Espelho SOMENTE-LEITURA de `power/{uid}`.
/// Autoridade econômica: SEMPRE o backend. O cliente nunca calcula power.
class PowerModel {
  const PowerModel({
    required this.permanentPower,
    required this.temporaryPower,
    this.temporaryPowerExpiresAt,
    required this.totalPower,
    this.updatedAt,
  });

  /// Poder permanente (unidade-base inteira H/s).
  final int permanentPower;

  /// Poder temporário/bônus (unidade-base inteira H/s).
  final int temporaryPower;

  /// Expiração do poder temporário (se houver).
  final DateTime? temporaryPowerExpiresAt;

  /// Total oficial informado pelo servidor (unidade-base inteira H/s).
  final int totalPower;

  /// Momento da última atualização feita pelo backend.
  final DateTime? updatedAt;

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

  factory PowerModel.fromMap(Map<String, dynamic> map) => PowerModel(
        permanentPower: _toInt(map['permanentPower']),
        temporaryPower: _toInt(map['temporaryPower']),
        temporaryPowerExpiresAt: _toDate(map['temporaryPowerExpiresAt']),
        totalPower: _toInt(map['totalPower']),
        updatedAt: _toDate(map['updatedAt']),
      );
}
