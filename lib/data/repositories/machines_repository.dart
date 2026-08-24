import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/machine_model.dart';

/// Contrato do repositório de máquinas — permite fakes nos testes.
abstract interface class MachinesRepositoryApi {
  /// Lê `machines/{uid}/items` (cache-first). Vazio se não houver docs.
  Future<List<MachineModel>> loadMachines(String uid);

  /// Observa `machines/{uid}/items` em tempo real (snapshots).
  Stream<List<MachineModel>> watchMachines(String uid);
}

/// Repositório de leitura das máquinas do jogador (`machines/{uid}/items`).
///
/// SOMENTE LEITURA espelho — compra/upgrade/ativação são do backend
/// (rules: `allow write: if false`). Leitura cache-first:
/// 1. Cache em memória (TTL curto);
/// 2. Servidor como fonte de renovação;
/// 3. Fallback: cache persistido do Firestore (offline).
class MachinesRepository implements MachinesRepositoryApi {
  MachinesRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  Query<Map<String, dynamic>> _query(String uid) =>
      _db.collection(Collections.machines).doc(uid).collection('items');

  List<MachineModel> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              MachineModel.fromMap(d.id, d.data()))
          .toList(growable: false);

  @override
  Future<List<MachineModel>> loadMachines(String uid) {
    final String key = '${Collections.machines}:$uid';
    return _cache.readCacheFirst<List<MachineModel>>(
      key: key,
      fromServer: () async => _mapSnapshot(await _query(uid).get()),
      fromPersistentCache: () async {
        try {
          return _mapSnapshot(
            await _query(uid).get(const GetOptions(source: Source.cache)),
          );
        } catch (_) {
          return const <MachineModel>[]; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 2),
    );
  }

  @override
  Stream<List<MachineModel>> watchMachines(String uid) =>
      _query(uid).snapshots().map(_mapSnapshot);
}
