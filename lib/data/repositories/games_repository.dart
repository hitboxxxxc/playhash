import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/game_model.dart';

/// Contrato do repositório de catálogo de jogos — permite fakes nos testes.
abstract interface class GamesRepositoryApi {
  /// Lê os games HABILITADOS (cache-first). Vazio se não houver docs.
  Future<List<GameModel>> loadGames();
}

/// Repositório do catálogo público de jogos (`games/{gameId}`).
///
/// SOMENTE LEITURA — escrita é exclusiva do backend (rules: `allow write:
/// if false`). Leitura cache-first: memória (TTL) → servidor → cache
/// persistido (offline).
class GamesRepository implements GamesRepositoryApi {
  GamesRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  List<GameModel> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              GameModel.fromMap(d.id, d.data()))
          .where((GameModel g) => g.enabled)
          .toList(growable: false);

  @override
  Future<List<GameModel>> loadGames() {
    const String key = '${Collections.games}:enabled';
    return _cache.readCacheFirst<List<GameModel>>(
      key: key,
      fromServer: () async =>
          _mapSnapshot(await _db.collection(Collections.games).get()),
      fromPersistentCache: () async {
        try {
          return _mapSnapshot(
            await _db
                .collection(Collections.games)
                .get(const GetOptions(source: Source.cache)),
          );
        } catch (_) {
          return const <GameModel>[]; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 5),
    );
  }
}
