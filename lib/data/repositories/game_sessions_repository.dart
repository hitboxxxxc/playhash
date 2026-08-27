import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Contrato do repositório de sessões de partida — permite fakes nos testes.
abstract interface class GameSessionsRepositoryApi {
  /// Cria `gameSessions/{clientRequestId}` {uid, gameId, clientRequestId,
  /// startedAt, clientVersion, status:'open'} e retorna o id.
  /// `startedAt` usa timestamp do servidor (rules impõem ≈ request.time).
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
    String? clientRequestId,
  });

  /// Fecha a sessão num ÚNICO update open→finished {score, kills, breakdown,
  /// finishedAt}. `kills` é OPCIONAL (games sem contagem de inimigos não
  /// enviam). `breakdown` é OPCIONAL (neon-hopper em diante): mapa EXATO
  /// {stomps:int, coins:int, flagReached:bool} — o score OFICIAL é
  /// recalculado pelo backend a partir dele (doc 05 §12/§51). Idempotente:
  /// se já estiver finished (retry pós-instabilidade), trata como sucesso.
  Future<void> finishSession({
    required String sessionId,
    required int score,
    int? kills,
    Map<String, dynamic>? breakdown,
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
/// O doc id É o clientRequestId (UUID v4) ⇒ retry offline reescreve o MESMO
/// doc (idempotência; update é negado pelas rules).
class GameSessionsRepository implements GameSessionsRepositoryApi {
  GameSessionsRepository({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection(Collections.gameSessions);

  final Random _random = Random.secure();

  /// UUID v4 próprio (sem dependência externa).
  String generateClientRequestId() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final String h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
    String? clientRequestId,
  }) async {
    final String requestId = clientRequestId ?? generateClientRequestId();
    await _sessions.doc(requestId).set(<String, dynamic>{
      'uid': uid,
      'gameId': gameId,
      'clientRequestId': requestId,
      'startedAt': FieldValue.serverTimestamp(),
      'clientVersion': clientVersion,
      'status': 'open',
    });
    return requestId;
  }

  @override
  Future<void> finishSession({
    required String sessionId,
    required int score,
    int? kills,
    Map<String, dynamic>? breakdown,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _sessions.doc(sessionId);
    try {
      await ref.update(<String, dynamic>{
        'status': 'finished',
        'score': score,
        'kills': ?kills,
        'breakdown': ?breakdown,
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
