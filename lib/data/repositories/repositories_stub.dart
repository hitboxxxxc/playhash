import '../../core/constants/collections.dart';
import '../cache_policy.dart';

/// Repositórios STUB da Fase A — apenas esqueleto de leitura cache-first.
/// NENHUMA regra econômica vive aqui (cliente não confiável): saldos,
/// power e pagamentos são calculados/aplicados SOMENTE pelo backend.
/// Implementações reais chegam na Fase B.

/// Perfil próprio (users/{uid}).
class UserRepositoryStub {
  UserRepositoryStub(this._cache);

  final CachePolicy _cache;

  Future<Map<String, dynamic>?> loadOwnProfile(String uid) {
    final String key = '${Collections.users}:$uid';
    return _cache.readCacheFirst<Map<String, dynamic>?>(
      key: key,
      fromServer: () async => null, // TODO(Fase B): get Firestore server
      fromPersistentCache: () async =>
          _cache.get<Map<String, dynamic>?>(key),
    );
  }
}

/// Carteira (wallets/{uid}) — somente leitura espelho; nunca autoridade.
class WalletRepositoryStub {
  const WalletRepositoryStub();

  Future<Map<String, dynamic>?> fetchWallet(String uid) async =>
      null; // TODO(Fase B)
}

/// Power (power/{uid}) — somente leitura espelho; nunca autoridade.
class PowerRepositoryStub {
  const PowerRepositoryStub();

  Future<Map<String, dynamic>?> fetchPower(String uid) async =>
      null; // TODO(Fase B)
}

/// Catálogos públicos (games/missions/achievements/leagues/seasons).
class CatalogRepositoryStub {
  CatalogRepositoryStub(this._cache);

  final CachePolicy _cache;

  Future<List<Map<String, dynamic>>> loadGames() {
    const String key = '${Collections.games}:all';
    return _cache.readCacheFirst<List<Map<String, dynamic>>>(
      key: key,
      fromServer: () async => const <Map<String, dynamic>>[], // TODO(Fase B)
      fromPersistentCache: () async =>
          _cache.get<List<Map<String, dynamic>>>(key) ??
          const <Map<String, dynamic>>[],
      ttl: const Duration(minutes: 15),
    );
  }
}
