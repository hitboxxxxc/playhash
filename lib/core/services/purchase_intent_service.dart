import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Resultado de uma intent de compra observada (espelho de leitura — a
/// validação econômica é 100% do runner; o cliente nunca decide valores).
class PurchaseIntentResult {
  const PurchaseIntentResult({
    required this.status,
    this.failureCode,
    this.machineItemId,
  });

  /// 'pending' | 'done' | 'failed'.
  final String status;
  final String? failureCode;
  final String? machineItemId;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  static PurchaseIntentResult fromMap(Map<String, dynamic> data) =>
      PurchaseIntentResult(
        status: (data['status'] as String?) ?? 'pending',
        failureCode: data['failureCode'] as String?,
        machineItemId: data['machineItemId'] as String?,
      );
}

/// Contrato do repositório de intents de compra — permite fakes nos testes.
abstract interface class PurchaseIntentsRepositoryApi {
  /// Cria `purchaseIntents/{clientRequestId}` com EXATAMENTE os campos
  /// exigidos pelas rules: {uid, machineId, clientRequestId, createdAt,
  /// status:'pending'}. O doc id É o clientRequestId ⇒ retry offline
  /// reescreve o MESMO doc (idempotência; update é negado pelas rules).
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  });

  /// Lê o doc atual da intent (null se não existir).
  Future<PurchaseIntentResult?> readIntent(String clientRequestId);

  /// Observa a intent até o runner processar (done/failed).
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId);
}

/// Repositório de intents de compra (`purchaseIntents`).
class PurchaseIntentsRepository implements PurchaseIntentsRepositoryApi {
  PurchaseIntentsRepository({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _intents =>
      _db.collection(Collections.purchaseIntents);

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  }) async {
    await _intents.doc(clientRequestId).set(<String, dynamic>{
      'uid': uid,
      'machineId': machineId,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  @override
  Future<PurchaseIntentResult?> readIntent(String clientRequestId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _intents.doc(clientRequestId).get();
    if (!snap.exists) return null;
    return PurchaseIntentResult.fromMap(snap.data()!);
  }

  @override
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId) =>
      _intents.doc(clientRequestId).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                PurchaseIntentResult.fromMap(snap.data() ?? const <String, dynamic>{}),
          );
}

/// Falha de compra com mensagem SEGURA em PT-BR (sem vazar detalhes internos).
class PurchaseIntentException implements Exception {
  PurchaseIntentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serviço de intenção de compra da LOJA.
///
/// - clientRequestId = UUID v4 gerado no cliente e usado COMO DOC ID:
///   retry offline reenvia o mesmo doc (nunca duplica — idempotência);
/// - payload com EXATAMENTE os campos das rules (nada além);
/// - mensagens de erro seguras por failureCode do runner.
class PurchaseIntentService {
  PurchaseIntentService({PurchaseIntentsRepositoryApi? repository})
      : _repositoryOverride = repository;

  final PurchaseIntentsRepositoryApi? _repositoryOverride;
  final Random _random = Random.secure();

  PurchaseIntentsRepositoryApi get _repository =>
      _repositoryOverride ?? PurchaseIntentsRepository();

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

  /// Cria a intent com retry seguro (mesmo clientRequestId). Se o doc já
  /// existe (retry pós-instabilidade), trata como enviado.
  ///
  /// Retorna o clientRequestId para observação do resultado.
  Future<String> createIntent({
    required String uid,
    required String machineId,
    String? clientRequestId,
    int maxAttempts = 3,
  }) async {
    final String requestId = clientRequestId ?? generateClientRequestId();
    Object? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _repository.createIntent(
          clientRequestId: requestId,
          uid: uid,
          machineId: machineId,
        );
        return requestId;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // Doc já existente (retry) ⇒ update negado; confirma e segue.
          final PurchaseIntentResult? existing =
              await _repository.readIntent(requestId);
          if (existing != null) return requestId;
          throw PurchaseIntentException(
            'A compra não pôde ser enviada agora. Tente novamente em instantes.',
          );
        }
        if (e.code == 'unavailable' || e.code == 'network-request-failed') {
          lastError = e; // offline: retry com o MESMO requestId
        } else {
          throw PurchaseIntentException(
            'Não foi possível enviar a compra. Tente novamente.',
          );
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw PurchaseIntentException(
      'Sem conexão para enviar a compra. Verifique a internet e tente '
      'de novo — nada foi cobrado. ($lastError)',
    );
  }

  /// Observa a intent até done/failed (o runner processa em até ~5 min).
  Stream<PurchaseIntentResult> watchResult(String clientRequestId) =>
      _repository.watchIntent(clientRequestId);

  /// Mensagem SEGURA por código de falha do runner.
  static String failureMessage(String? code) {
    switch (code) {
      case 'INSUFFICIENT_BALANCE':
        return 'Saldo insuficiente para esta compra.';
      case 'MAX_PER_USER_REACHED':
        return 'Você já atingiu o limite deste modelo de máquina.';
      case 'INVALID_MACHINE':
      case 'MACHINE_DISABLED':
        return 'Esta máquina está indisponível no momento.';
      case 'DAILY_LIMIT_REACHED':
        return 'Limite diário de compras atingido. Tente amanhã.';
      case 'DUPLICATE_CLIENT_REQUEST_ID':
        return 'Este pedido já foi registrado. Verifique sua sala de máquinas.';
      default:
        return 'A compra não pôde ser concluída. Tente novamente mais tarde.';
    }
  }
}
