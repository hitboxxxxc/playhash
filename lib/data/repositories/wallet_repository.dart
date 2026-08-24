import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';
import '../models/wallet_model.dart';

/// Contrato do repositório de carteira — permite fakes nos testes.
abstract interface class WalletRepositoryApi {
  /// Lê `wallets/{uid}` (cache-first). Doc inexistente => `null` (vazio).
  Future<WalletModel?> loadWallet(String uid);

  /// Observa `wallets/{uid}` em tempo real (snapshots).
  Stream<WalletModel?> watchWallet(String uid);
}

/// Repositório de leitura da carteira própria (`wallets/{uid}`).
///
/// SOMENTE LEITURA espelho — saldos são creditados/debitados EXCLUSIVAMENTE
/// pelo backend (rules: `allow write: if false`). Leitura cache-first:
/// 1. Cache em memória (TTL curto);
/// 2. Servidor como fonte de renovação;
/// 3. Fallback: cache persistido do Firestore (offline).
class WalletRepository implements WalletRepositoryApi {
  WalletRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(Collections.wallets).doc(uid);

  @override
  Future<WalletModel?> loadWallet(String uid) {
    final String key = '${Collections.wallets}:$uid';
    return _cache.readCacheFirst<WalletModel?>(
      key: key,
      fromServer: () async {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await _doc(uid).get();
        return snap.exists ? WalletModel.fromMap(snap.data()!) : null;
      },
      fromPersistentCache: () async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await _doc(uid).get(const GetOptions(source: Source.cache));
          return snap.exists ? WalletModel.fromMap(snap.data()!) : null;
        } catch (_) {
          return null; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 2),
    );
  }

  @override
  Stream<WalletModel?> watchWallet(String uid) =>
      _doc(uid).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                snap.exists ? WalletModel.fromMap(snap.data()!) : null,
          );
}
