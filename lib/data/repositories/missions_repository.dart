import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/mission_model.dart';

/// Contrato do repositório de missões — permite fakes nos testes.
abstract interface class MissionsRepositoryApi {
  /// Catálogo `missions/*` habilitado (cache-first).
  Future<List<MissionModel>> loadCatalog();

  /// Observa `userMissions/{uid}/items` em tempo real (progresso do runner).
  Stream<List<MissionView>> watchMissions(String uid);
}

/// Repositório de MISSÕES: catálogo cache-first + progresso em stream.
/// SOMENTE LEITURA — progresso/claimed são escritos exclusivamente pelo
/// runner (rules: `allow write: if false`).
class MissionsRepository implements MissionsRepositoryApi {
  MissionsRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<List<MissionModel>> loadCatalog() {
    return _cache.readCacheFirst<List<MissionModel>>(
      key: '${Collections.missions}:catalog',
      fromServer: () async {
        final QuerySnapshot<Map<String, dynamic>> snap =
            await _db.collection(Collections.missions).get();
        final List<MissionModel> all = snap.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  MissionModel.fromMap(doc.id, doc.data()),
            )
            .where((MissionModel m) => m.enabled)
            .toList(growable: false);
        return all;
      },
      fromPersistentCache: () async {
        try {
          final QuerySnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.missions)
              .get(const GetOptions(source: Source.cache));
          return snap.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    MissionModel.fromMap(doc.id, doc.data()),
              )
              .where((MissionModel m) => m.enabled)
              .toList(growable: false);
        } catch (_) {
          return const <MissionModel>[]; // sem cache disponível
        }
      },
      ttl: const Duration(minutes: 10),
    );
  }

  @override
  Stream<List<MissionView>> watchMissions(String uid) async* {
    final List<MissionModel> catalog = await loadCatalog();
    await for (final QuerySnapshot<Map<String, dynamic>> snap
        in _db.collection(Collections.userMissions).doc(uid).collection('items').snapshots()) {
      final Map<String, Map<String, dynamic>> items = <String, Map<String, dynamic>>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs)
          doc.id: doc.data(),
      };
      yield <MissionView>[
        for (final MissionModel m in catalog)
          MissionView(
            mission: m,
            progress: items.containsKey(m.id)
                ? MissionProgress.fromMap(items[m.id]!)
                : const MissionProgress(progress: 0, claimed: false),
          ),
      ];
    }
  }
}
