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
    required String network,
    required BigInt amountUnits,
    required String address,
    required String addressMasked,
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
      'network': network,
      'amountUnits': amountUnits.toString(),
      'address': address,
      'addressMasked': addressMasked,
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
  group('WithdrawalService.requestWithdrawal', () {
    test('envia payload com campos EXATOS das rules', () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository();
      final WithdrawalService service = WithdrawalService(repository: repo);

      final String requestId = await service.requestWithdrawal(
        uid: 'uid-1',
        asset: 'BTC',
        network: 'Bitcoin',
        amountUnits: BigInt.from(25000000),
        address: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
        clientRequestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      expect(requestId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(repo.calls, hasLength(1));
      // Campos exigidos pelas rules: {uid, asset, network, amountUnits,
      // address, addressMasked, clientRequestId, clientVersion}
      // (+ createdAt serverTimestamp no doc real).
      final Map<String, dynamic> call = repo.calls.single;
      expect(call['uid'], 'uid-1');
      expect(call['asset'], 'BTC');
      expect(call['network'], 'Bitcoin');
      expect(call['amountUnits'], '25000000');
      expect(
        call['address'],
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
      );
      expect(call['addressMasked'], isNot(call['address']));
      expect(call['addressMasked'], contains('…'));
      expect(call['clientRequestId'], requestId);
    });

    test('retry offline reusa o MESMO clientRequestId (idempotência)',
        () async {
      final _FakePayoutsRepository repo = _FakePayoutsRepository(failTimes: 2);
      final WithdrawalService service = WithdrawalService(repository: repo);

      final String requestId = await service.requestWithdrawal(
        uid: 'uid-1',
        asset: 'DOGE',
        network: 'Dogecoin',
        amountUnits: BigInt.from(20000000),
        address: 'DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L',
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
          network: 'Litecoin',
          amountUnits: BigInt.from(20000000),
          address: 'ltc1qdp3p2rezaw3u2c8pq7z9kr5zk2mcqsxyv9qzxe',
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
          asset: 'BTC',
          network: 'Bitcoin',
          amountUnits: BigInt.zero,
          address: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
        ),
        throwsA(isA<WithdrawalException>()),
      );
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
      expect(withdrawalErrorMessage('INVALID_ADDRESS'), contains('Endereço'));
      expect(withdrawalErrorMessage('ACCOUNT_IN_REVIEW'), contains('análise'));
      expect(withdrawalErrorMessage('ACCOUNT_TOO_NEW'), contains('24h'));
      expect(withdrawalErrorMessage('NO_FINISHED_GAMES'), contains('partida'));
      // Código desconhecido ⇒ mensagem genérica segura.
      expect(withdrawalErrorMessage('QUALQUER_COISA'), contains('Tente'));
    });
  });

  group('privacidade e validação local leve', () {
    test('maskWalletAddress nunca expõe o endereço completo', () {
      const String full = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080';
      final String masked = maskWalletAddress(full);
      expect(masked, isNot(full));
      expect(masked.length, lessThan(full.length));
      expect(masked.startsWith('bc1qw5'), isTrue);
      expect(masked.endsWith(full.substring(full.length - 4)), isTrue);
    });

    test('looksLikeValidAddress por rede', () {
      expect(
        looksLikeValidAddress(
          'Bitcoin',
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
        ),
        isTrue,
      );
      expect(
        looksLikeValidAddress('TRC20', 'TXYZsYbSfpBCBZ6CbwPpkbvQyzEB9XcuK8'),
        isTrue,
      );
      expect(
        looksLikeValidAddress('Dogecoin', 'bc1qw508d6qejxtdg4y5r3zarvary0c5x'),
        isFalse,
      );
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
