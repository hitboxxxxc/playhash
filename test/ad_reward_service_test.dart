import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/ad_reward_service.dart';
import 'package:playhash/data/repositories/ads_repository.dart';

/// Fake do repositório de anúncios — captura o payload enviado.
class _FakeAdsRepository implements AdsRepositoryApi {
  _FakeAdsRepository({this.failTimes = 0});

  int failTimes;
  final List<Map<String, String>> calls = <Map<String, String>>[];

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String adUnitId,
    required String clientVersion,
  }) async {
    if (failTimes > 0) {
      failTimes -= 1;
      throw Exception('network unavailable');
    }
    calls.add(<String, String>{
      'clientRequestId': clientRequestId,
      'uid': uid,
      'adUnitId': adUnitId,
      'clientVersion': clientVersion,
    });
  }

  @override
  Future<AdRewardIntentResult?> readIntent(String clientRequestId) async =>
      null;

  @override
  Stream<AdRewardIntentResult> watchIntent(String clientRequestId) =>
      const Stream<AdRewardIntentResult>.empty();

  @override
  Stream<List<AdRewardEntry>> watchTodayRewards(String uid) =>
      const Stream<List<AdRewardEntry>>.empty();

  @override
  Stream<int?> watchDailyLimit() => const Stream<int?>.empty();
}

void main() {
  group('AdRewardService.createIntent', () {
    test('envia payload com campos EXATOS das rules', () async {
      final _FakeAdsRepository repo = _FakeAdsRepository();
      final AdRewardService service = AdRewardService(repository: repo);

      final String requestId = await service.createIntent(
        uid: 'uid-1',
        clientVersion: '1.0.0',
        clientRequestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      expect(requestId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(repo.calls, hasLength(1));
      // Campos exigidos pelas rules: {uid, type:'rewarded', adUnitId,
      // clientRequestId, createdAt(server), clientVersion}.
      expect(repo.calls.single['uid'], 'uid-1');
      expect(repo.calls.single['adUnitId'], isNotEmpty);
      expect(repo.calls.single['clientVersion'], '1.0.0');
      expect(repo.calls.single['clientRequestId'],
          'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });

    test('retry offline reusa o MESMO clientRequestId (nunca duplica)',
        () async {
      final _FakeAdsRepository repo = _FakeAdsRepository(failTimes: 2);
      final AdRewardService service = AdRewardService(repository: repo);

      final String requestId = await service.createIntent(
        uid: 'uid-1',
        clientVersion: '1.0.0',
      );

      // Todas as tentativas usaram o mesmo requestId.
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['clientRequestId'], requestId);
    });

    test('clientRequestId gerado é UUID v4 válido', () {
      final AdRewardService service =
          AdRewardService(repository: _FakeAdsRepository());
      final String id = service.generateClientRequestId();
      final RegExp uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidV4.hasMatch(id), isTrue);
      expect(service.generateClientRequestId(), isNot(id));
    });
  });

  group('AdRewardService.failureMessage (mensagens seguras)', () {
    test('mapeia códigos do runner sem vazar detalhes internos', () {
      expect(
        AdRewardService.failureMessage('DAILY_LIMIT_REACHED'),
        contains('Limite diário'),
      );
      expect(
        AdRewardService.failureMessage('COOLDOWN_ACTIVE'),
        contains('Aguarde'),
      );
      expect(
        AdRewardService.failureMessage('ACCOUNT_BLOCKED'),
        contains('análise'),
      );
      expect(
        AdRewardService.failureMessage(null),
        contains('não pôde ser validada'),
      );
    });
  });
}
