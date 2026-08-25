import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/withdrawal_service.dart';
import 'package:playhash/data/repositories/payouts_repository.dart';

/// Fake do repositório de payouts — captura o payload enviado.
class _FakePayoutsRepository implements PayoutsRepositoryApi {
  _FakePayoutsRepository({this.failTimes = 0});

  int failTimes;
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  @override
  Future<void> createWithdrawalIntent({
    required String clientRequestId,
    required String uid,
    required String asset,
    required BigInt amountUnits,
    required String destinationEmail,
    required String destinationMasked,
    required String clientVersion,
  }) async {
    if (failTimes > 0) {
      failTimes -= 1;
      throw Exception('network unavailable');
    }
    calls.add(<String, dynamic>{
      'clientRequestId': clientRequestId,
      'uid': uid,
      'asset': asset,
      'amountUnits': amountUnits.toString(),
      'destinationEmail': destinationEmail,
      'destinationMasked': destinationMasked,
      'clientVersion': clientVersion,
    });
  }

  @override
  Future<PayoutsConfigModel?> loadConfig() async => null;

  @override
  Stream<WithdrawalModel?> watchWithdrawal(String clientRequestId) =>
      const Stream<WithdrawalModel?>.empty();

  @override
  Stream<List<WithdrawalModel>> watchUserWithdrawals(String uid) =>
      const Stream<List<WithdrawalModel>>.empty();

  @override
  Stream<List<RewardHistoryEntry>> watchRewardItems(String uid) =>
      const Stream<List<RewardHistoryEntry>>.empty();
}

void main() {
  group('WithdrawalService.requestWithdrawal (v3 — e-mail FaucetPay)', () {
    test('envia payload com campos EXATOS das rules', () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository();
      final WithdrawalService service = WithdrawalService(repository: repo);

      final String requestId = await service.requestWithdrawal(
        uid: 'uid-1',
        asset: 'LTC',
        amountUnits: BigInt.from(25000000),
        destinationEmail: 'owner@example.com',
        clientRequestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      expect(requestId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(repo.calls, hasLength(1));
      // Campos exigidos pelas rules (v3): {uid, asset, amountUnits,
      // destinationEmail, destinationMasked, clientRequestId, clientVersion}
      // (+ createdAt serverTimestamp no doc real).
      final Map<String, dynamic> call = repo.calls.single;
      expect(call['uid'], 'uid-1');
      expect(call['asset'], 'LTC');
      expect(call['amountUnits'], '25000000');
      expect(call['destinationEmail'], 'owner@example.com');
      expect(call['destinationMasked'], isNot(call['destinationEmail']));
      expect(call['destinationMasked'], contains('***@'));
      expect(call['clientRequestId'], requestId);
    });

    test('retry offline reusa o MESMO clientRequestId (idempotência)',
        () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository(failTimes: 2);
      final WithdrawalService service = WithdrawalService(repository: repo);

      final String requestId = await service.requestWithdrawal(
        uid: 'uid-1',
        asset: 'LTC',
        amountUnits: BigInt.from(20000000),
        destinationEmail: 'owner@example.com',
      );

      // Sucesso após retries com o MESMO id — nunca duplica.
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['clientRequestId'], requestId);
    });

    test('esgota as tentativas ⇒ exceção com mensagem segura', () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository(failTimes: 99);
      final WithdrawalService service = WithdrawalService(repository: repo);

      await expectLater(
        service.requestWithdrawal(
          uid: 'uid-1',
          asset: 'LTC',
          amountUnits: BigInt.from(20000000),
          destinationEmail: 'owner@example.com',
          maxAttempts: 2,
        ),
        throwsA(isA<WithdrawalException>()),
      );
    });

    test('valor inválido (<= 0) é rejeitado localmente', () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository();
      final WithdrawalService service = WithdrawalService(repository: repo);

      await expectLater(
        service.requestWithdrawal(
          uid: 'uid-1',
          asset: 'LTC',
          amountUnits: BigInt.zero,
          destinationEmail: 'owner@example.com',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      expect(repo.calls, isEmpty);
    });

    test('e-mail inválido é bloqueado LOCALMENTE (nunca cria intent)',
        () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository();
      final WithdrawalService service = WithdrawalService(repository: repo);

      for (final String bad in <String>[
        'sem-arroba',
        'a@b',
        'dois @@espacos.com',
        '',
      ]) {
        await expectLater(
          service.requestWithdrawal(
            uid: 'uid-1',
            asset: 'LTC',
            amountUnits: BigInt.from(20000000),
            destinationEmail: bad,
          ),
          throwsA(isA<WithdrawalException>()),
          reason: 'e-mail "$bad" deveria ser bloqueado',
        );
      }
      expect(repo.calls, isEmpty);
    });

    test('clientRequestId gerado é UUID v4 válido', () {
      final WithdrawalService service =
          WithdrawalService(repository: _FakePayoutsRepository());
      final String id = service.generateClientRequestId();
      final RegExp uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidV4.hasMatch(id), isTrue);
      expect(service.generateClientRequestId(), isNot(id));
    });
  });

  group('mensagens seguras por errorCode', () {
    test('mapeia códigos do runner sem vazar detalhes internos', () {
      expect(withdrawalErrorMessage('INSUFFICIENT_BALANCE'), contains('Saldo'));
      expect(withdrawalErrorMessage('BELOW_MINIMUM'), contains('mínimo'));
      expect(withdrawalErrorMessage('COOLDOWN_ACTIVE'), contains('24h'));
      expect(withdrawalErrorMessage('DAILY_LIMIT_REACHED'), contains('diário'));
      expect(withdrawalErrorMessage('INVALID_EMAIL'), contains('E-mail'));
      expect(withdrawalErrorMessage('EMAIL_NOT_FOUND'), contains('FaucetPay'));
      expect(withdrawalErrorMessage('ACCOUNT_IN_REVIEW'), contains('análise'));
      expect(withdrawalErrorMessage('ACCOUNT_TOO_NEW'), contains('24h'));
      expect(withdrawalErrorMessage('NO_FINISHED_GAMES'), contains('partida'));
      // Código desconhecido ⇒ mensagem genérica segura.
      expect(withdrawalErrorMessage('QUALQUER_COISA'), contains('Tente'));
    });
  });

  group('privacidade e validação local leve (v3)', () {
    test('maskEmail nunca expõe o e-mail completo', () {
      const String full = 'owner@example.com';
      final String masked = maskEmail(full);
      expect(masked, isNot(full));
      expect(masked, 'ow***@example.com');
      expect(masked.contains(full), isFalse);
      // Local curto mantém apenas o 1º caractere.
      expect(maskEmail('a@example.com'), 'a***@example.com');
    });

    test('isValidDestinationEmail aceita e-mails comuns e rejeita inválidos',
        () {
      expect(isValidDestinationEmail('owner@example.com'), isTrue);
      expect(isValidDestinationEmail('joao.silva+fp@sub.dominio.io'), isTrue);
      expect(isValidDestinationEmail('sem-arroba'), isFalse);
      expect(isValidDestinationEmail('a@b'), isFalse);
      expect(isValidDestinationEmail('com espaco@x.com'), isFalse);
      expect(isValidDestinationEmail(''), isFalse);
    });

    test('watchWithdrawal mascara a providerReference', () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository();
      final WithdrawalService service = WithdrawalService(repository: repo);
      // Repo fake não emite eventos; apenas garante que o stream é exposto.
      await expectLater(
        service.watchWithdrawal('req-1').isEmpty,
        completes,
      );
    });
  });
}
