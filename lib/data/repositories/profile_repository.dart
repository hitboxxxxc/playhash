import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../cache_policy.dart';

/// Contrato do repositório de perfil — permite fakes nos testes.
abstract interface class ProfileRepositoryApi {
  /// Lê `users/{uid}` (cache-first). Documento inexistente => `null`
  /// (estado vazio, NÃO erro).
  Future<Map<String, dynamic>?> loadOwnProfile(String uid);

  /// Observa `users/{uid}` em tempo real (snapshots). Documento inexistente
  /// => eventos com `null`. Usado pela tela de Perfil para refletir edições
  /// feitas em outras telas (ex.: displayName nas Configurações).
  Stream<Map<String, dynamic>?> watchOwnProfile(String uid);

  /// Salva preferências de notificação em
  /// `users/{uid}.settings.notifications` (merge — campo permitido pelas
  /// rules de update).
  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> prefs,
  );
}

/// Repositório de leitura/escrita restrita do perfil próprio (`users/{uid}`).
///
/// Leitura: cache-first via [CachePolicy.readCacheFirst]:
/// 1. Cache em memória (TTL curto — perfil muda pouco);
/// 2. Servidor como fonte de renovação;
/// 3. Fallback: cache persistido do Firestore (offline).
///
/// Escrita: apenas preferências de UI (`settings.notifications`). Campos
/// econômicos e exclusão de conta são SEMPRE responsabilidade do backend.
class ProfileRepository implements ProfileRepositoryApi {
  ProfileRepository(this._cache, {FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final CachePolicy _cache;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection(Collections.users).doc(uid);

  @override
  Future<Map<String, dynamic>?> loadOwnProfile(String uid) {
    final String key = '${Collections.users}:$uid';
    return _cache.readCacheFirst<Map<String, dynamic>?>(
      key: key,
      fromServer: () async {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await _userDoc(uid).get();
        return snap.exists ? snap.data() : null;
      },
      fromPersistentCache: () async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await _userDoc(uid).get(const GetOptions(source: Source.cache));
          return snap.exists ? snap.data() : null;
        } catch (_) {
          return null; // sem cache persistido disponível
        }
      },
      ttl: const Duration(minutes: 5),
    );
  }

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String uid) =>
      _userDoc(uid).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                snap.exists ? snap.data() : null,
          );

  @override
  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> prefs,
  ) {
    // Merge preserva os demais campos do documento; `settings` inteiro é
    // reescrito apenas no submapa de notificações.
    return _userDoc(uid).set(
      <String, dynamic>{
        'settings': <String, dynamic>{
          'notifications': prefs,
        },
      },
      SetOptions(merge: true),
    );
  }
}
