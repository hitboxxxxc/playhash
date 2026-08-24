import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/mission_model.dart';
import '../models/season_model.dart';

/// Contrato do repositório de temporada — permite fakes nos testes.
abstract interface class SeasonRepositoryApi {
  /// Doc oficial da temporada (`seasons/season-01`, cache-first).
  Future<SeasonModel?> loadSeason();

  /// Observa `seasonProgress/{uid}` em tempo real (null = sem progresso).
  Stream<SeasonProgressModel?> watchSeasonProgress(String uid);

  /// Missões de TEMPORADA (kind='season') + progresso do usuário em stream.
  Stream<List<MissionView>> watchSeasonMissions(String uid);
}

/// Repositório de TEMPORADA. SOMENTE LEITURA — XP, nível e claimed são
/// escritos exclusivamente pelo backend (season_progress/processClaims).
class SeasonRepository implements SeasonRepositoryApi {
  SeasonRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<SeasonModel?> loadSeason() {
    return _cache.readCacheFirst<SeasonModel?>(
      key: '${Collections.seasons}:season-01',
      fromServer: () async {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await _db.collection(Collections.seasons).doc('season-01').get();
        return snap.exists ? SeasonModel.fromMap(snap.id, snap.data()!) : null;
      },
      fromPersistentCache: () async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.seasons)
              .doc('season-01')
              .get(const GetOptions(source: Source.cache));
          return snap.exists ? SeasonModel.fromMap(snap.id, snap.data()!) : null;
        } catch (_) {
          return null; // sem cache disponível
        }
      },
      ttl: const Duration(minutes: 10),
    );
  }

  @override
  Stream<SeasonProgressModel?> watchSeasonProgress(String uid) => _db
          .collection(Collections.seasonProgress)
          .doc(uid)
          .snapshots()
          .map((DocumentSnapshot<Map<String, dynamic>> snap) =>
              snap.exists ? SeasonProgressModel.fromMap(snap.data()!) : null);

  @override
  Stream<List<MissionView>> watchSeasonMissions(String uid) async* {
    // Catálogo de missões (reuso do repositório existente) filtrado para
    // kind='season' + progresso `userMissions/{uid}/items` em tempo real.
    final QuerySnapshot<Map<String, dynamic>> catalogSnap =
        await _db.collection(Collections.missions).get();
    final List<MissionModel> seasonMissions = catalogSnap.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
            MissionModel.fromMap(doc.id, doc.data()))
        .where((MissionModel m) => m.enabled && m.kind == 'season')
        .toList(growable: false);

    await for (final QuerySnapshot<Map<String, dynamic>> snap in _db
        .collection(Collections.userMissions)
        .doc(uid)
        .collection('items')
        .snapshots()) {
      final Map<String, Map<String, dynamic>> items = <String, Map<String, dynamic>>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs)
          doc.id: doc.data(),
      };
      yield <MissionView>[
        for (final MissionModel m in seasonMissions)
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
