import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Espelho SOMENTE-LEITURA de `wallets/{uid}`.
/// Autoridade econômica: SEMPRE o backend. Saldos nunca são calculados
/// nem alterados no cliente — apenas exibidos.
class WalletModel {
  const WalletModel({
    required this.internalBalance,
    required this.availableBalance,
    required this.pendingBalance,
    required this.lifetimeEarned,
    this.updatedAt,
  });

  /// Saldo interno (unidades mínimas inteiras).
  final BigInt internalBalance;

  /// Saldo disponível (unidades mínimas inteiras).
  final BigInt availableBalance;

  /// Saldo pendente (unidades mínimas inteiras).
  final BigInt pendingBalance;

  /// Total ganho historicamente (unidades mínimas inteiras).
  final BigInt lifetimeEarned;

  /// Momento da última atualização feita pelo backend.
  final DateTime? updatedAt;

  static BigInt _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) {
      final BigInt? parsed = BigInt.tryParse(value);
      if (parsed != null) return parsed;
      // Tolerância: double serializado como string ("1.5e6").
      final double? asDouble = double.tryParse(value);
      if (asDouble != null) return BigInt.from(asDouble.toInt());
    }
    if (value is double) return BigInt.from(value.toInt());
    return BigInt.zero;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory WalletModel.fromMap(Map<String, dynamic> map) => WalletModel(
        internalBalance: _toBigInt(map['internalBalance']),
        availableBalance: _toBigInt(map['availableBalance']),
        pendingBalance: _toBigInt(map['pendingBalance']),
        lifetimeEarned: _toBigInt(map['lifetimeEarned']),
        updatedAt: _toDate(map['updatedAt']),
      );
}
