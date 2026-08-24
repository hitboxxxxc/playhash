import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Contrato do repositório de sessões de partida — permite fakes nos testes.
abstract interface class GameSessionsRepositoryApi {
  /// Cria `gameSessions/{id}` {uid, gameId, startedAt, clientVersion,
  /// status:'open'} e retorna o id. `startedAt` usa timestamp do servidor
  /// (rules impõem ≈ request.time).
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
  });

  /// Fecha a sessão num ÚNICO update open→finished {score, finishedAt}.
  /// Idempotente: se já estiver finished (retry pós-instabilidade), trata
  /// como sucesso.
  Future<void> finishSession({
    required String sessionId,
    required int score,
  });

  /// Observa o doc da própria sessão (processed/serverResult do backend).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(String sessionId);

  /// Maior score finished PRÓPRIO no game (para "Melhor:" no catálogo).
  /// Sem índice composto: filtros de igualdade + máximo calculado no cliente.
  Future<int> bestScore({required String uid, required String gameId});
}

/// Repositório de INTENÇÕES de sessão (`gameSessions`).
///
/// O cliente só escreve intenções com campos exatos validados pelas rules;
/// score/duração/poder são validados SOMENTE pelo backend (runner).
class GameSessionsRepository implements GameSessionsRepositoryApi {
  GameSessionsRepository({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection(Collections.gameSessions);

  @override
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = await _sessions.add(
      <String, dynamic>{
        'uid': uid,
        'gameId': gameId,
        'startedAt': FieldValue.serverTimestamp(),
        'clientVersion': clientVersion,
        'status': 'open',
      },
    );
    return ref.id;
  }

  @override
  Future<void> finishSession({
    required String sessionId,
    required int score,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _sessions.doc(sessionId);
    try {
      await ref.update(<String, dynamic>{
        'status': 'finished',
        'score': score,
        'finishedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Possível retry após fechamento anterior: sessão já finished ⇒ ok.
        final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
        if (snap.data()?['status'] == 'finished') return;
      }
      rethrow;
    }
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(
    String sessionId,
  ) =>
      _sessions.doc(sessionId).snapshots();

  @override
  Future<int> bestScore({
    required String uid,
    required String gameId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _sessions
        .where('uid', isEqualTo: uid)
        .where('gameId', isEqualTo: gameId)
        .where('status', isEqualTo: 'finished')
        .get();
    int best = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      final int score = (doc.data()['score'] as num?)?.toInt() ?? 0;
      if (score > best) best = score;
    }
    return best;
  }
}
