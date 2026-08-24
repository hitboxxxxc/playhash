import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/achievement_model.dart';

/// Contrato do repositório de conquistas — permite fakes nos testes.
abstract interface class AchievementsRepositoryApi {
  /// Catálogo `achievements/*` habilitado (cache-first).
  Future<List<AchievementModel>> loadCatalog();

  /// Observa catálogo + `userAchievements/{uid}/items` combinados em tempo real.
  Stream<List<AchievementView>> watchAchievements(String uid);
}

/// Repositório de CONQUISTAS: catálogo cache-first + progresso em stream.
/// SOMENTE LEITURA — progresso/claimed são escritos exclusivamente pelo
/// runner (rules: `allow write: if false`).
class AchievementsRepository implements AchievementsRepositoryApi {
  AchievementsRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<List<AchievementModel>> loadCatalog() {
    return _cache.readCacheFirst<List<AchievementModel>>(
      key: '${Collections.achievements}:catalog',
      fromServer: () async {
        final QuerySnapshot<Map<String, dynamic>> snap =
            await _db.collection(Collections.achievements).get();
        return snap.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  AchievementModel.fromMap(doc.id, doc.data()),
            )
            .where((AchievementModel a) => a.enabled)
            .toList(growable: false);
      },
      fromPersistentCache: () async {
        try {
          final QuerySnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.achievements)
              .get(const GetOptions(source: Source.cache));
          return snap.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    AchievementModel.fromMap(doc.id, doc.data()),
              )
              .where((AchievementModel a) => a.enabled)
              .toList(growable: false);
        } catch (_) {
          return const <AchievementModel>[];
        }
      },
      ttl: const Duration(minutes: 10),
    );
  }

  @override
  Stream<List<AchievementView>> watchAchievements(String uid) async* {
    final List<AchievementModel> catalog = await loadCatalog();
    await for (final QuerySnapshot<Map<String, dynamic>> snap in _db
        .collection(Collections.userAchievements)
        .doc(uid)
        .collection('items')
        .snapshots()) {
      final Map<String, Map<String, dynamic>> items = <String, Map<String, dynamic>>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs)
          doc.id: doc.data(),
      };
      yield <AchievementView>[
        for (final AchievementModel a in catalog)
          AchievementView(
            achievement: a,
            progress: items.containsKey(a.id)
                ? AchievementProgress.fromMap(items[a.id]!)
                : const AchievementProgress(progress: 0, claimed: false),
          ),
      ];
    }
  }
}
