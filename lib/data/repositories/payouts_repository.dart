import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Allowlist EXATA de campos do intent de saque — ESPELHO do
/// `hasOnly([...])` das rules v3 (withdrawalIntents). Qualquer campo a mais
/// ou a menos ⇒ PERMISSION_DENIED no create. Usado p/ validar o payload nos
/// testes (unit) contra as rules.
const Set<String> kWithdrawalIntentAllowedKeys = <String>{
  'uid',
  'asset',
  'amountUnits',
  'destinationEmail',
  'destinationMasked',
  'clientRequestId',
  'createdAt',
  'clientVersion',
};

/// Ativo de saque — espelho SOMENTE-LEITURA de um item de
/// `config/payouts.assets` ("valores definidos pelo servidor").
///
/// TOLERANTE A LEGADO (12.9): aceita campos v3/v4 e aliases antigos
/// (assetUnitPerCoinScaled→litoshiPerCoin, minWithdrawUnits/feeUnits em
/// units ⇒ coins), ids em qualquer caixa. O PARSE NUNCA BLOQUEIA o saque —
/// é apenas apresentação; a autoridade é 100% do backend.
class PayoutAsset {
  const PayoutAsset({
    required this.id,
    required this.network,
    required this.enabled,
    required this.minWithdrawUnits,
    required this.feeUnits,
    this.litoshiPerCoin = 100,
    this.displayRate = '1 COIN = 0,000001 LTC',
  });

  final String id; // BTC | LTC | DOGE | USDT (SEMPRE uppercase)
  final String network; // FaucetPayEmail (v3/v4) | Bitcoin | Litecoin | …
  final bool enabled;

  /// Mínimo de saque em units (1 coin = 1e6 units).
  final BigInt minWithdrawUnits;

  /// Taxa do servidor em units (descontada do valor bruto).
  final BigInt feeUnits;

  /// Conversão FIXA v3/v4: 1 COIN = N litoshi (apresentação; oficial no
  /// backend). Fallback seguro p/ display quando ausente.
  final int litoshiPerCoin;

  /// Rótulo de exibição da conversão (definido pelo servidor).
  final String displayRate;

  static BigInt _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) return BigInt.tryParse(value) ?? BigInt.zero;
    return BigInt.zero;
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  factory PayoutAsset.fromMap(String id, Map<String, dynamic> map) {
    // Aliases legado → canônico (12.9):
    final int litoshi = _toInt(map['litoshiPerCoin']) != 0
        ? _toInt(map['litoshiPerCoin'])
        : _toInt(map['assetUnitPerCoinScaled']);
    final BigInt minCoins = _toBigInt(map['minWithdrawCoins']);
    final BigInt feeCoins = _toBigInt(map['feeCoins']);
    return PayoutAsset(
      id: id.trim().toUpperCase(),
      network: (map['network'] as String?) ?? 'FaucetPayEmail',
      enabled: map['enabled'] == true,
      minWithdrawUnits: minCoins != BigInt.zero
          ? minCoins * BigInt.from(1000000)
          : _toBigInt(map['minWithdrawUnits']),
      feeUnits: feeCoins != BigInt.zero
          ? feeCoins * BigInt.from(1000000)
          : _toBigInt(map['feeUnits']),
      litoshiPerCoin: litoshi != 0 ? litoshi : 100,
      displayRate: (map['displayRate'] as String?) ??
          (litoshi != 0 ? '1 COIN = 0,00000$litoshi LTC' : '1 COIN = 0,000001 LTC'),
    );
  }
}

/// Config de saques — espelho TOLERANTE de `config/payouts` (12.9): aceita
/// `assets` como LISTA (v1–v3) ou MAPA keyed por id (v4), ids lower/upper.
class PayoutsConfigModel {
  const PayoutsConfigModel({required this.assets});

  /// Apenas os ativos como estão na config (filtrar `enabled` na UI).
  final List<PayoutAsset> assets;

  factory PayoutsConfigModel.fromMap(Map<String, dynamic> map) {
    final Object? raw = map['assets'];
    final List<PayoutAsset> parsed = <PayoutAsset>[];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is Map) {
          final String id = ((item['id'] as String?) ?? '').trim();
          if (id.isEmpty) continue;
          parsed.add(PayoutAsset.fromMap(id, item.cast<String, dynamic>()));
        }
      }
    } else if (raw is Map) {
      raw.forEach((Object? key, Object? value) {
        if (key is String && value is Map) {
          parsed.add(PayoutAsset.fromMap(key, value.cast<String, dynamic>()));
        }
      });
    }
    return PayoutsConfigModel(assets: parsed);
  }
}

/// Espelho SOMENTE-LEITURA de `withdrawals/{id}` (escrito pelo runner).
/// O destino completo NUNCA é exibido — apenas [destinationMasked]
/// (e-mail mascarado no fluxo v3; máscara de endereço no legado).
class WithdrawalModel {
  const WithdrawalModel({
    required this.id,
    required this.uid,
    required this.asset,
    required this.network,
    required this.amountUnits,
    required this.feeUnits,
    required this.receivedUnits,
    required this.destinationMasked,
    required this.status, // processing | completed | failed
    this.providerReference,
    this.errorCode,
    this.createdAt,
  });

  final String id;
  final String uid;
  final String asset;
  final String network;
  final BigInt amountUnits;
  final BigInt feeUnits;
  final BigInt receivedUnits;

  /// Máscara do destino (ex.: 'ow***@example.com') — NUNCA o valor completo.
  final String destinationMasked;
  final String status;
  final String? providerReference;
  final String? errorCode;
  final DateTime? createdAt;

  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  static BigInt _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) return BigInt.tryParse(value) ?? BigInt.zero;
    return BigInt.zero;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  factory WithdrawalModel.fromMap(String id, Map<String, dynamic> map) =>
      WithdrawalModel(
        id: id,
        uid: (map['uid'] as String?) ?? '',
        asset: (map['asset'] as String?) ?? '',
        network: (map['network'] as String?) ?? '',
        amountUnits: _toBigInt(map['amountUnits']),
        feeUnits: _toBigInt(map['feeUnits']),
        receivedUnits: _toBigInt(map['receivedUnits']),
        destinationMasked: (map['destinationMasked'] as String?) ??
            (map['addressMasked'] as String?) ??
            '',
        status: (map['status'] as String?) ?? 'processing',
        providerReference: map['providerReference'] as String?,
        errorCode: map['errorCode'] as String?,
        createdAt: _toDate(map['createdAt']),
      );
}

/// Contrato do repositório de payouts — permite fakes nos testes.
abstract interface class PayoutsRepositoryApi {
  /// Lê `config/payouts` (null se ausente/indisponível).
  Future<PayoutsConfigModel?> loadConfig();

  /// Cria a intent de saque com EXATAMENTE os campos das rules (v3):
  /// {uid, asset, amountUnits, destinationEmail, destinationMasked,
  ///  clientRequestId, createdAt, clientVersion}.
  /// O doc id É o clientRequestId ⇒ retry offline reescreve o MESMO doc.
  Future<void> createWithdrawalIntent({
    required String clientRequestId,
    required String uid,
    required String asset,
    required BigInt amountUnits,
    required String destinationEmail,
    required String destinationMasked,
    required String clientVersion,
  });

  /// Observa o saque processado pelo runner (`withdrawals/{clientRequestId}`).
  Stream<WithdrawalModel?> watchWithdrawal(String clientRequestId);

  /// Observa TODOS os saques do usuário (histórico da carteira), mais
  /// recentes primeiro. Tolerante a falhas ⇒ lista vazia.
  Stream<List<WithdrawalModel>> watchUserWithdrawals(String uid);

  /// Observa o espelho de recompensas `rewards/{uid}/items` (entradas/saídas
  /// escritas pelo backend), mais recentes primeiro. Tolerante a falhas.
  Stream<List<RewardHistoryEntry>> watchRewardItems(String uid);
}

/// Entrada do espelho de histórico de recompensas (rewards/{uid}/items).
class RewardHistoryEntry {
  const RewardHistoryEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.currencyId,
    this.referenceId,
    this.status,
    this.createdAt,
  });

  final String id;
  final String type;
  final BigInt amount; // negativo = saída
  final String currencyId;
  final String? referenceId;
  final String? status;
  final DateTime? createdAt;

  static BigInt _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) return BigInt.tryParse(value) ?? BigInt.zero;
    return BigInt.zero;
  }

  factory RewardHistoryEntry.fromMap(String id, Map<String, dynamic> map) =>
      RewardHistoryEntry(
        id: id,
        type: (map['type'] as String?) ?? '',
        amount: _toBigInt(map['amount']),
        currencyId: (map['currencyId'] as String?) ?? 'coins',
        referenceId: map['referenceId'] as String?,
        status: map['status'] as String?,
        createdAt: map['createdAt'] is Timestamp
            ? (map['createdAt']! as Timestamp).toDate()
            : null,
      );
}

/// Repositório de payouts/saques. O cliente NUNCA calcula taxas nem decide
/// valores — apenas envia a intenção e observa o resultado do runner.
class PayoutsRepository implements PayoutsRepositoryApi {
  PayoutsRepository({FirebaseFirestore? firestore}) : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<PayoutsConfigModel?> loadConfig() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _db.doc(Collections.configPayouts).get();
      if (!snap.exists) return null;
      return PayoutsConfigModel.fromMap(snap.data()!);
    } catch (_) {
      return null; // tolerante a offline/permissão
    }
  }

  @override
  Future<void> createWithdrawalIntent({
    required String clientRequestId,
    required String uid,
    required String asset,
    required BigInt amountUnits,
    required String destinationEmail,
    required String destinationMasked,
    required String clientVersion,
  }) async {
    await _db
        .collection(Collections.withdrawalIntents)
        .doc(clientRequestId)
        .set(<String, dynamic>{
      'uid': uid,
      'asset': asset,
      // Rules exigem amountUnits is INT — NUNCA string (string ⇒
      // PERMISSION_DENIED). BigInt cabe em int64 p/ valores realistas.
      'amountUnits': amountUnits.toInt(),
      'destinationEmail': destinationEmail,
      'destinationMasked': destinationMasked,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'clientVersion': clientVersion,
    });
  }

  @override
  Stream<WithdrawalModel?> watchWithdrawal(String clientRequestId) => _db
          .collection(Collections.withdrawals)
          .doc(clientRequestId)
          .snapshots()
          .map((DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!snap.exists) return null;
        return WithdrawalModel.fromMap(snap.id, snap.data()!);
      });

  @override
  Stream<List<WithdrawalModel>> watchUserWithdrawals(String uid) {
    // Queries SEM orderBy (evita índice composto). Ordenação na memória.
    return _db.collection(Collections.withdrawals)
        .where('uid', isEqualTo: uid)
        .limit(50)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final List<WithdrawalModel> raw = snap.docs
          .map((d) => WithdrawalModel.fromMap(d.id, d.data()))
          .toList(growable: false);

      // Ordenação na memória por createdAt desc (evita índice composto).
      raw.sort((a, b) {
        final DateTime da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

      // Deduplicação por createdAt + status (mesma entrada duplicada).
      final List<WithdrawalModel> deduped = <WithdrawalModel>[];
      for (final w in raw) {
        if (!deduped.any((existing) =>
            existing.createdAt == w.createdAt && existing.status == w.status)) {
          deduped.add(w);
        }
      }

      return deduped;
    }).handleError((_) => const <WithdrawalModel>[]);
  }

  @override
  Stream<List<RewardHistoryEntry>> watchRewardItems(String uid) {
    // Queries SEM orderBy (evita índice composto). Ordenação na memória.
    return _db.collection('${Collections.rewards}/$uid/items')
        .limit(50)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final List<RewardHistoryEntry> raw = snap.docs
          .map((d) => RewardHistoryEntry.fromMap(d.id, d.data()))
          .toList(growable: false);

      // Ordenação na memória por createdAt desc (evita índice composto).
      raw.sort((a, b) {
        final DateTime da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

      // Deduplicação por referenceId (mesma recompensa duplicada).
      final List<RewardHistoryEntry> deduped = <RewardHistoryEntry>[];
      for (final r in raw) {
        if (!deduped.any((existing) => existing.referenceId == r.referenceId)) {
          deduped.add(r);
        }
      }

      return deduped;
    }).handleError((_) => const <RewardHistoryEntry>[]);
  }
}
