import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/purchase_intent_service.dart';

/// Fake do repositório de intents — captura o payload enviado.
class _FakeIntentsRepository implements PurchaseIntentsRepositoryApi {
  _FakeIntentsRepository({this.failTimes = 0});

  int failTimes;
  final List<Map<String, String>> calls = <Map<String, String>>[];

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  }) async {
    if (failTimes > 0) {
      failTimes -= 1;
      throw Exception('network unavailable');
    }
    calls.add(<String, String>{
      'clientRequestId': clientRequestId,
      'uid': uid,
      'machineId': machineId,
    });
  }

  @override
  Future<PurchaseIntentResult?> readIntent(String clientRequestId) async =>
      null;

  @override
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId) =>
      const Stream<PurchaseIntentResult>.empty();
}

void main() {
  group('PurchaseIntentService.createIntent', () {
    test('envia payload com campos EXATOS das rules', () async {
      final _FakeIntentsRepository repo = _FakeIntentsRepository();
      final PurchaseIntentService service =
          PurchaseIntentService(repository: repo);

      final String requestId = await service.createIntent(
        uid: 'uid-1',
        machineId: 'rig-scrap',
        clientRequestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      expect(requestId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(repo.calls, hasLength(1));
      // Campos exigidos pelas rules: uid, machineId, clientRequestId
      // (+ createdAt serverTimestamp e status:'pending' no doc real).
      expect(repo.calls.single['uid'], 'uid-1');
      expect(repo.calls.single['machineId'], 'rig-scrap');
      expect(repo.calls.single['clientRequestId'],
          'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });

    test('retry offline reusa o MESMO clientRequestId (idempotência)',
        () async {
      final _FakeIntentsRepository repo = _FakeIntentsRepository(failTimes: 2);
      final PurchaseIntentService service =
          PurchaseIntentService(repository: repo);

      final String requestId = await service.createIntent(
        uid: 'uid-1',
        machineId: 'rig-volt',
      );

      // Todas as tentativas usaram o mesmo requestId — nunca duplica.
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['clientRequestId'], requestId);
    });

    test('clientRequestId gerado é UUID v4 válido', () async {
      final PurchaseIntentService service =
          PurchaseIntentService(repository: _FakeIntentsRepository());
      final String id = service.generateClientRequestId();
      final RegExp uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidV4.hasMatch(id), isTrue);
      // Dois ids gerados nunca coincidem.
      expect(service.generateClientRequestId(), isNot(id));
    });
  });

  group('PurchaseIntentService.failureMessage (mensagens seguras)', () {
    test('mapeia códigos do runner sem vazar detalhes internos', () {
      expect(
        PurchaseIntentService.failureMessage('INSUFFICIENT_BALANCE'),
        contains('Saldo insuficiente'),
      );
      expect(
        PurchaseIntentService.failureMessage('MAX_PER_USER_REACHED'),
        contains('limite'),
      );
      expect(
        PurchaseIntentService.failureMessage('INVALID_MACHINE'),
        contains('indisponível'),
      );
      expect(
        PurchaseIntentService.failureMessage('DAILY_LIMIT_REACHED'),
        contains('Limite diário'),
      );
      // Código desconhecido => mensagem genérica segura.
      expect(
        PurchaseIntentService.failureMessage('QUALQUER_COISA'),
        contains('não pôde ser concluída'),
      );
    });
  });

  group('PurchaseIntentResult', () {
    test('parse do espelho do doc', () {
      final PurchaseIntentResult done = PurchaseIntentResult.fromMap(
        <String, dynamic>{
          'status': 'done',
          'machineItemId': 'item-1',
        },
      );
      expect(done.isDone, isTrue);
      expect(done.machineItemId, 'item-1');

      final PurchaseIntentResult failed = PurchaseIntentResult.fromMap(
        <String, dynamic>{
          'status': 'failed',
          'failureCode': 'INSUFFICIENT_BALANCE',
        },
      );
      expect(failed.isFailed, isTrue);
      expect(failed.failureCode, 'INSUFFICIENT_BALANCE');

      const PurchaseIntentResult pending =
          PurchaseIntentResult(status: 'pending');
      expect(pending.isDone, isFalse);
      expect(pending.isFailed, isFalse);
    });
  });
}
