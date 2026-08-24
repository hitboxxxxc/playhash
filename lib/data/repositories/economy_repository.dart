import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';

/// Contrato do repositório de config econômica pública — permite fakes.
abstract interface class EconomyRepositoryApi {
  /// Lê `config/economy.machineSlots` (cache-first). Doc/campo ausente =>
  /// `null` (o cliente usa fallback de apresentação; a seed garante o campo).
  Future<int?> loadMachineSlots();
}

/// Repositório de LEITURA de campos públicos de `config/economy`.
/// Nenhum parâmetro econômico é decidido no cliente — apenas espelho.
class EconomyRepository implements EconomyRepositoryApi {
  EconomyRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Future<int?> loadMachineSlots() {
    const String key = '${Collections.config}:machineSlots';
    return _cache.readCacheFirst<int?>(
      key: key,
      fromServer: () async {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await _db.collection(Collections.config).doc('economy').get();
        final Object? value = snap.get('machineSlots');
        return value is num ? value.toInt() : null;
      },
      fromPersistentCache: () async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap = await _db
              .collection(Collections.config)
              .doc('economy')
              .get(const GetOptions(source: Source.cache));
          final Object? value = snap.get('machineSlots');
          return value is num ? value.toInt() : null;
        } catch (_) {
          return null; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 5),
    );
  }
}
