import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/machine_catalog_model.dart';

/// Contrato do repositório do catálogo de máquinas — permite fakes nos testes.
abstract interface class MachineCatalogRepositoryApi {
  /// Lê as máquinas HABILITADAS de `config/machines` (cache-first, TTL curto).
  /// Vazio se não houver docs.
  Future<List<MachineCatalogModel>> loadCatalog();
}

/// Repositório do catálogo público de máquinas (`config/machines/{id}`).
///
/// SOMENTE LEITURA — preços/poder/limites são decisão EXCLUSIVA do backend
/// (rules: `allow write: if false`). Leitura cache-first com TTL curto:
/// 1. Cache em memória;
/// 2. Servidor como fonte de renovação;
/// 3. Fallback: cache persistido do Firestore (offline).
class MachineCatalogRepository implements MachineCatalogRepositoryApi {
  MachineCatalogRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  List<MachineCatalogModel> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              MachineCatalogModel.fromMap(d.id, d.data()))
          .where((MachineCatalogModel m) => m.enabled)
          .toList(growable: false);

  @override
  Future<List<MachineCatalogModel>> loadCatalog() {
    const String key = '${Collections.configMachines}:enabled';
    return _cache.readCacheFirst<List<MachineCatalogModel>>(
      key: key,
      fromServer: () async =>
          _mapSnapshot(await _db.collection(Collections.configMachines).get()),
      fromPersistentCache: () async {
        try {
          return _mapSnapshot(
            await _db
                .collection(Collections.configMachines)
                .get(const GetOptions(source: Source.cache)),
          );
        } catch (_) {
          return const <MachineCatalogModel>[]; // sem cache persistido
        }
      },
      ttl: const Duration(minutes: 2),
    );
  }
}
