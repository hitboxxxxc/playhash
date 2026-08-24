import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/league_model.dart';

/// Contrato do repositório de ligas — permite fakes nos testes.
abstract interface class LeaguesRepositoryApi {
  /// Catálogo `leagues/*` ordenado por tier (cache-first).
  Future<List<LeagueModel>> loadLeagues();

  /// Observa `userLeagues/{uid}` em tempo real (null = sem liga ainda).
  Stream<UserLeagueModel?> watchUserLeague(String uid);
}

/// Repositório de LIGAS: catálogo cache-first + liga do usuário em stream.
/// SOMENTE LEITURA — atribuição/promoção/diária são do backend (runner).
class LeaguesRepository implements LeaguesRepositoryApi {
  LeaguesRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<List<LeagueModel>> loadLeagues() {
    return _cache.readCacheFirst<List<LeagueModel>>(
      key: '${Collections.leagues}:catalog',
      fromServer: () async {
        final QuerySnapshot<Map<String, dynamic>> snap =
            await _db.collection(Collections.leagues).get();
        final List<LeagueModel> leagues = snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                LeagueModel.fromMap(doc.id, doc.data()))
            .toList(growable: false);
        leagues.sort((LeagueModel a, LeagueModel b) => a.tier.compareTo(b.tier));
        return leagues;
      },
      fromPersistentCache: () async {
        try {
          final QuerySnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.leagues)
              .get(const GetOptions(source: Source.cache));
          final List<LeagueModel> leagues = snap.docs
              .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  LeagueModel.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          leagues.sort((LeagueModel a, LeagueModel b) => a.tier.compareTo(b.tier));
          return leagues;
        } catch (_) {
          return const <LeagueModel>[]; // sem cache disponível
        }
      },
      ttl: const Duration(minutes: 10),
    );
  }

  @override
  Stream<UserLeagueModel?> watchUserLeague(String uid) => _db
          .collection(Collections.userLeagues)
          .doc(uid)
          .snapshots()
          .map((DocumentSnapshot<Map<String, dynamic>> snap) =>
              snap.exists ? UserLeagueModel.fromMap(snap.data()!) : null);
}
