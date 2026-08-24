import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';

/// Snapshot público de bloco — lido SE existir no servidor.
/// NUNCA criado ou presumido localmente: sem backend => `null` => "—" na UI.
class BlockSnapshot {
  const BlockSnapshot({
    this.nextBlockAt,
    this.totalBlockRewardMinimalUnits,
    this.networkPower,
  });

  /// Horário oficial do próximo bloco (schedule fornecido pelo backend).
  /// Sem este campo NÃO há contagem regressiva na UI.
  final DateTime? nextBlockAt;

  /// Recompensa total do bloco (unidades mínimas inteiras).
  final BigInt? totalBlockRewardMinimalUnits;

  /// Poder total da rede (unidade-base inteira H/s).
  final int? networkPower;

  static BigInt? _toBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) return BigInt.tryParse(value);
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory BlockSnapshot.fromMap(Map<String, dynamic> map) => BlockSnapshot(
        nextBlockAt: _toDate(map['nextBlockAt']),
        totalBlockRewardMinimalUnits:
            _toBigInt(map['totalBlockRewardMinimalUnits']),
        networkPower: _toInt(map['networkPower']),
      );
}

/// Entrada do histórico de recompensas (espelho do backend).
class RewardEntry {
  const RewardEntry({
    required this.id,
    required this.amountMinimalUnits,
    this.createdAt,
  });

  final String id;

  /// Valor creditado (unidades mínimas inteiras).
  final BigInt amountMinimalUnits;

  final DateTime? createdAt;

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
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory RewardEntry.fromMap(String id, Map<String, dynamic> map) =>
      RewardEntry(
        id: id,
        amountMinimalUnits:
            _toBigInt(map['amountMinimalUnits'] ?? map['amount']),
        createdAt: _toDate(map['createdAt']),
      );
}

/// Estimativa de recompensa — APENAS aritmética de apresentação sobre
/// valores oficiais do servidor (seu poder / poder da rede × recompensa
/// do bloco). Sem dados oficiais => `null` => "—" na UI.
class RewardEstimate {
  const RewardEstimate({
    required this.share,
    required this.estimatedRewardMinimalUnits,
  });

  /// Participação estimada (0..1).
  final double share;

  /// Recompensa estimada (unidades mínimas inteiras).
  final BigInt estimatedRewardMinimalUnits;
}

/// Contrato do repositório de mineração — permite fakes nos testes.
abstract interface class MiningRepositoryApi {
  /// Config pública de bloco (`blocks/current`) SE existir.
  /// Qualquer falha (doc ausente, permissão, offline sem cache) => `null`.
  Future<BlockSnapshot?> loadBlockSnapshot();

  /// Histórico de recompensas (`rewards/{uid}/items`). Falha => lista vazia.
  Future<List<RewardEntry>> loadRewardHistory(String uid);

  /// Doc de liga do jogador (`userLeagues/{uid}`) SE existir. Falha => `null`.
  Future<Map<String, dynamic>?> loadUserLeague(String uid);

  /// Estimativa de apresentação a partir de valores OFICIAIS do servidor.
  /// Retorna `null` quando faltar qualquer insumo oficial.
  RewardEstimate? estimateReward({required int yourPower, BlockSnapshot? block});
}

/// Repositório de mineração: configs públicas de bloco + histórico.
///
/// O backend de blocos/ligas AINDA NÃO EXISTE: as coleções podem estar
/// ausentes ou negadas pelas rules — TODA falha é tratada como estado
/// vazio (nunca erro, nunca valor inventado).
class MiningRepository implements MiningRepositoryApi {
  MiningRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<BlockSnapshot?> loadBlockSnapshot() async {
    try {
      final String key = '${Collections.blocks}:current';
      return await _cache.readCacheFirst<BlockSnapshot?>(
        key: key,
        fromServer: () async {
          final DocumentSnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.blocks)
              .doc('current')
              .get();
          return snap.exists ? BlockSnapshot.fromMap(snap.data()!) : null;
        },
        fromPersistentCache: () async {
          try {
            final DocumentSnapshot<Map<String, dynamic>> snap = await _db
                .collection(Collections.blocks)
                .doc('current')
                .get(const GetOptions(source: Source.cache));
            return snap.exists ? BlockSnapshot.fromMap(snap.data()!) : null;
          } catch (_) {
            return null;
          }
        },
        ttl: const Duration(minutes: 1),
      );
    } catch (_) {
      return null; // backend de blocos ausente => estado vazio
    }
  }

  @override
  Future<List<RewardEntry>> loadRewardHistory(String uid) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _db
          .collection(Collections.rewards)
          .doc(uid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      return snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              RewardEntry.fromMap(d.id, d.data()))
          .toList(growable: false);
    } catch (_) {
      return const <RewardEntry>[]; // backend ausente => vazio
    }
  }

  @override
  Future<Map<String, dynamic>?> loadUserLeague(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _db.collection(Collections.userLeagues).doc(uid).get();
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null; // backend de ligas ausente => estado vazio
    }
  }

  @override
  RewardEstimate? estimateReward({
    required int yourPower,
    BlockSnapshot? block,
  }) {
    if (block == null) return null;
    final int? network = block.networkPower;
    final BigInt? reward = block.totalBlockRewardMinimalUnits;
    if (network == null || network <= 0 || yourPower <= 0 || reward == null) {
      return null;
    }
    final BigInt your = BigInt.from(yourPower);
    final BigInt net = BigInt.from(network);
    return RewardEstimate(
      share: yourPower / network,
      estimatedRewardMinimalUnits: (reward * your) ~/ net,
    );
  }
}
