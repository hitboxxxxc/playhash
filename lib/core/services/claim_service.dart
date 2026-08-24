import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Resultado de um claim observado (espelho de leitura — a concessão da
/// recompensa é 100% do runner; o cliente NUNCA credita saldo — doc 05 §42).
class ClaimResult {
  const ClaimResult({required this.status, this.failureCode});

  /// 'pending' | 'claimed' | 'failed'.
  final String status;
  final String? failureCode;

  bool get isClaimed => status == 'claimed';
  bool get isFailed => status == 'failed';

  static ClaimResult fromMap(Map<String, dynamic> data) => ClaimResult(
        status: (data['status'] as String?) ?? 'pending',
        failureCode: data['failureCode'] as String?,
      );
}

/// Contrato do repositório de claims — permite fakes nos testes.
abstract interface class ClaimsRepositoryApi {
  /// Cria `claims/{clientRequestId}` com EXATAMENTE os campos exigidos pelas
  /// rules: {uid, kind, refId, clientRequestId, createdAt, status:'pending'}.
  /// O doc id É o clientRequestId ⇒ retry offline reescreve o MESMO doc
  /// (idempotência; update é negado pelas rules).
  Future<void> createClaim({
    required String clientRequestId,
    required String uid,
    required String kind,
    required String refId,
  });

  /// Lê o doc atual do claim (null se não existir).
  Future<ClaimResult?> readClaim(String clientRequestId);

  /// Observa o claim até o runner processar (claimed/failed, ≤ ~5 min).
  Stream<ClaimResult> watchClaim(String clientRequestId);
}

/// Repositório de claims (`claims`).
class ClaimsRepository implements ClaimsRepositoryApi {
  ClaimsRepository({FirebaseFirestore? firestore}) : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _claims =>
      _db.collection(Collections.claims);

  @override
  Future<void> createClaim({
    required String clientRequestId,
    required String uid,
    required String kind,
    required String refId,
  }) async {
    await _claims.doc(clientRequestId).set(<String, dynamic>{
      'uid': uid,
      'kind': kind,
      'refId': refId,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  @override
  Future<ClaimResult?> readClaim(String clientRequestId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _claims.doc(clientRequestId).get();
    if (!snap.exists) return null;
    return ClaimResult.fromMap(snap.data()!);
  }

  @override
  Stream<ClaimResult> watchClaim(String clientRequestId) =>
      _claims.doc(clientRequestId).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                ClaimResult.fromMap(snap.data() ?? const <String, dynamic>{}),
          );
}

/// Falha de claim com mensagem SEGURA em PT-BR (sem vazar detalhes internos).
class ClaimException implements Exception {
  ClaimException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serviço de RESGATE de missões/conquistas.
///
/// - clientRequestId = UUID v4 gerado no cliente e usado COMO DOC ID:
///   retry offline reenvia o mesmo doc (nunca duplica — idempotência);
/// - payload com EXATAMENTE os campos das rules (nada além);
/// - o runner valida progresso/período e credita a wallet (≤ ~5 min);
/// - mensagens de erro seguras por failureCode do runner.
class ClaimService {
  ClaimService({ClaimsRepositoryApi? repository}) : _repositoryOverride = repository;

  final ClaimsRepositoryApi? _repositoryOverride;
  final Random _random = Random.secure();

  ClaimsRepositoryApi get _repository =>
      _repositoryOverride ?? ClaimsRepository();

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

  /// Cria a intenção de resgate com retry seguro (mesmo clientRequestId).
  /// Se o doc já existe (retry pós-instabilidade), trata como enviado.
  /// Retorna o clientRequestId para observação do resultado.
  Future<String> createClaim({
    required String uid,
    required String kind, // 'mission' | 'achievement'
    required String refId,
    String? clientRequestId,
    int maxAttempts = 3,
  }) async {
    final String requestId = clientRequestId ?? generateClientRequestId();
    Object? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _repository.createClaim(
          clientRequestId: requestId,
          uid: uid,
          kind: kind,
          refId: refId,
        );
        return requestId;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // Doc já existente (retry) ⇒ update negado; confirma e segue.
          final ClaimResult? existing = await _repository.readClaim(requestId);
          if (existing != null) return requestId;
          throw ClaimException(
            'O resgate não pôde ser enviado agora. Tente novamente em instantes.',
          );
        }
        if (e.code == 'unavailable' || e.code == 'network-request-failed') {
          lastError = e; // offline: retry com o MESMO requestId
        } else {
          throw ClaimException(
            'Não foi possível enviar o resgate. Tente novamente.',
          );
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw ClaimException(
      'Sem conexão para enviar o resgate. Verifique a internet e tente '
      'de novo — nada foi perdido. ($lastError)',
    );
  }

  /// Observa o claim até claimed/failed (o runner processa em até ~5 min).
  Stream<ClaimResult> watchResult(String clientRequestId) =>
      _repository.watchClaim(clientRequestId);

  /// Mensagem SEGURA por código de falha do runner.
  static String failureMessage(String? code) {
    switch (code) {
      case 'CLAIM_PROGRESS_INSUFFICIENT':
        return 'O progresso desta recompensa ainda não foi validado. '
            'Tente novamente em instantes.';
      case 'CLAIM_ALREADY_CLAIMED':
        return 'Esta recompensa já foi resgatada.';
      case 'CLAIM_PERIOD_MISMATCH':
        return 'O período desta missão terminou. Confira as missões de hoje.';
      case 'DAILY_LIMIT_REACHED':
        return 'Limite diário de resgates atingido. Tente amanhã.';
      case 'CLAIM_DISABLED':
      case 'CLAIM_CATALOG_MISSING':
      case 'CLAIM_REWARD_INVALID':
        return 'Esta recompensa está indisponível no momento.';
      default:
        return 'O resgate não pôde ser concluído. Tente novamente mais tarde.';
    }
  }
}
