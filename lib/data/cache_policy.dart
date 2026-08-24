/// Política de cache da camada de dados.
///
/// Estratégia `readCacheFirst`:
/// 1. Cache EM MEMÓRIA com TTL (configs/catálogos);
/// 2. Cache PERSISTIDO do Firestore (fallback offline);
/// 3. Servidor como fonte de renovação.
///
/// IMPORTANTE: valores ECONÔMICOS (wallets, power, prêmios) lidos por aqui
/// NUNCA são autoridade local — são apenas espelho de leitura. A autoridade
/// é sempre o servidor/backend; o cliente não é confiável.
class CachePolicy {
  CachePolicy({this.defaultTtl = const Duration(minutes: 10)});

  final Duration defaultTtl;

  final Map<String, _CacheEntry> _memory = <String, _CacheEntry>{};

  bool isValid(String key, {Duration? ttl}) {
    final _CacheEntry? entry = _memory[key];
    if (entry == null) return false;
    final Duration effective = ttl ?? defaultTtl;
    return DateTime.now().difference(entry.fetchedAt) < effective;
  }

  T? get<T>(String key, {Duration? ttl}) {
    if (!isValid(key, ttl: ttl)) return null;
    return _memory[key]!.value as T?;
  }

  void put(String key, Object? value) {
    _memory[key] = _CacheEntry(value, DateTime.now());
  }

  void invalidate(String key) => _memory.remove(key);

  void clear() => _memory.clear();

  /// Lê primeiro do cache em memória (TTL); se expirado/ausente, busca do
  /// servidor e atualiza o cache. Se o servidor falhar (ex.: offline),
  /// cai para o [fromPersistentCache] mesmo com dado "velho".
  Future<T> readCacheFirst<T>({
    required String key,
    required Future<T> Function() fromServer,
    required Future<T?> Function() fromPersistentCache,
    Duration? ttl,
  }) async {
    final T? cached = get<T>(key, ttl: ttl);
    if (cached != null) return cached;

    try {
      final T fresh = await fromServer();
      put(key, fresh);
      return fresh;
    } catch (_) {
      // Fallback offline: cache persistido (pode estar expirado).
      final T? stale = await fromPersistentCache();
      if (stale != null) {
        put(key, stale);
        return stale;
      }
      rethrow;
    }
  }
}

class _CacheEntry {
  const _CacheEntry(this.value, this.fetchedAt);

  final Object? value;
  final DateTime fetchedAt;
}
