import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/power_model.dart';

/// Contrato do repositório de poder — permite fakes nos testes.
abstract interface class PowerRepositoryApi {
  /// Lê `power/{uid}` (cache-first). Doc inexistente => `null` (vazio, não erro).
  Future<PowerModel?> loadPower(String uid);

  /// Observa `power/{uid}` em tempo real (snapshots).
  Stream<PowerModel?> watchPower(String uid);
}

/// Repositório de leitura do poder próprio (`power/{uid}`).
///
/// SOMENTE LEITURA espelho — escrita de power é exclusiva do backend
/// (rules: `allow write: if false`). Leitura cache-first:
/// 1. Cache em memória (TTL curto — power muda com frequência);
/// 2. Servidor como fonte de renovação;
/// 3. Fallback: cache persistido do Firestore (offline).
class PowerRepository implements PowerRepositoryApi {
  PowerRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(Collections.power).doc(uid);

  @override
  Future<PowerModel?> loadPower(String uid) {
    final String key = '${Collections.power}:$uid';
    return _cache.readCacheFirst<PowerModel?>(
      key: key,
      fromServer: () async {
        final DocumentSnapshot<Map<String, dynamic>> snap = await _doc(uid).get();
        return snap.exists ? PowerModel.fromMap(snap.data()!) : null;
      },
      fromPersistentCache: () async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await _doc(uid).get(const GetOptions(source: Source.cache));
          return snap.exists ? PowerModel.fromMap(snap.data()!) : null;
        } catch (_) {
          return null; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 2),
    );
  }

  @override
  Stream<PowerModel?> watchPower(String uid) =>
      _doc(uid).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                snap.exists ? PowerModel.fromMap(snap.data()!) : null,
          );
}
