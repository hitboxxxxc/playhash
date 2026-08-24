import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/claim_service.dart';

/// Fake do repositório de claims: simula doc id = clientRequestId (update
/// negado quando o doc já existe — retry idempotente) e stream de resultado.
class _FakeClaimsRepository implements ClaimsRepositoryApi {
  _FakeClaimsRepository();

  static const bool failOnDuplicate = true;
  final Map<String, Map<String, dynamic>> docs = <String, Map<String, dynamic>>{};
  int createCalls = 0;

  @override
  Future<void> createClaim({
    required String clientRequestId,
    required String uid,
    required String kind,
    required String refId,
  }) async {
    createCalls += 1;
    if (failOnDuplicate && docs.containsKey(clientRequestId)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'doc já existe',
      );
    }
    docs[clientRequestId] = <String, dynamic>{
      'uid': uid,
      'kind': kind,
      'refId': refId,
      'clientRequestId': clientRequestId,
      'status': 'pending',
    };
  }

  @override
  Future<ClaimResult?> readClaim(String clientRequestId) async {
    final Map<String, dynamic>? data = docs[clientRequestId];
    return data == null ? null : ClaimResult.fromMap(data);
  }

  @override
  Stream<ClaimResult> watchClaim(String clientRequestId) =>
      Stream<ClaimResult>.fromIterable(<ClaimResult>[
        ClaimResult.fromMap(docs[clientRequestId] ?? const <String, dynamic>{}),
      ]);
}

void main() {
  group('ClaimService.createClaim', () {
    test('cria o claim com os campos EXATOS das rules', () async {
      final _FakeClaimsRepository repo = _FakeClaimsRepository();
      final ClaimService service = ClaimService(repository: repo);

      final String requestId = await service.createClaim(
        uid: 'uid-1',
        kind: 'mission',
        refId: 'm_daily_play3',
        clientRequestId: 'req-12345678',
      );

      expect(requestId, 'req-12345678');
      expect(repo.docs['req-12345678'], <String, dynamic>{
        'uid': 'uid-1',
        'kind': 'mission',
        'refId': 'm_daily_play3',
        'clientRequestId': 'req-12345678',
        'status': 'pending',
      });
    });

    test('retry com o MESMO clientRequestId não duplica (idempotência)', () async {
      final _FakeClaimsRepository repo = _FakeClaimsRepository();
      final ClaimService service = ClaimService(repository: repo);

      await service.createClaim(
        uid: 'uid-1',
        kind: 'achievement',
        refId: 'a_first_match',
        clientRequestId: 'req-12345678',
      );
      // Segunda chamada (retry pós-instabilidade): doc já existe ⇒ update
      // negado, mas o serviço confirma a existência e trata como enviado.
      final String again = await service.createClaim(
        uid: 'uid-1',
        kind: 'achievement',
        refId: 'a_first_match',
        clientRequestId: 'req-12345678',
      );

      expect(again, 'req-12345678');
      expect(repo.docs.length, 1);
    });

    test('gera UUID v4 com clientRequestId ausente', () async {
      final ClaimService service = ClaimService(
        repository: _FakeClaimsRepository(),
      );
      final String id = service.generateClientRequestId();
      final RegExp uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuid.hasMatch(id), isTrue);
    });
  });

  group('ClaimService.watchResult / failureMessage', () {
    test('transiciona pending → claimed via stream do doc', () async {
      final _FakeClaimsRepository repo = _FakeClaimsRepository();
      await repo.createClaim(
        clientRequestId: 'req-12345678',
        uid: 'uid-1',
        kind: 'mission',
        refId: 'm_daily_play3',
      );
      // Runner processou:
      repo.docs['req-12345678']!['status'] = 'claimed';

      final ClaimService service = ClaimService(repository: repo);
      final ClaimResult result = await service.watchResult('req-12345678').first;

      expect(result.isClaimed, isTrue);
      expect(result.isFailed, isFalse);
    });

    test('mensagens seguras por failureCode (sem vazar detalhes internos)', () {
      expect(
        ClaimService.failureMessage('CLAIM_PROGRESS_INSUFFICIENT'),
        contains('progresso'),
      );
      expect(
        ClaimService.failureMessage('CLAIM_ALREADY_CLAIMED'),
        contains('já foi resgatada'),
      );
      expect(
        ClaimService.failureMessage('CLAIM_PERIOD_MISMATCH'),
        contains('período'),
      );
      expect(
        ClaimService.failureMessage('DAILY_LIMIT_REACHED'),
        contains('Limite diário'),
      );
      expect(
        ClaimService.failureMessage('CLAIM_DISABLED'),
        contains('indisponível'),
      );
      // Código desconhecido ⇒ mensagem genérica segura.
      expect(
        ClaimService.failureMessage('INTERNAL_EXPLOSION'),
        contains('Tente novamente'),
      );
    });
  });
}
