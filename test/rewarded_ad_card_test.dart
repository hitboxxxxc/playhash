import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/ad_reward_service.dart';
import 'package:playhash/core/services/ad_service.dart';
import 'package:playhash/data/repositories/ads_repository.dart';
import 'package:playhash/features/store/widgets/rewarded_ad_card.dart';

/// Fake do serviço de anúncios (sem SDK AdMob).
class _FakeAds implements AdServiceApi {
  _FakeAds({this.loaded = true});

  final bool loaded;
  final StreamController<RewardedAdState> _controller =
      StreamController<RewardedAdState>.broadcast();

  VoidCallback? onEarned;
  int loadCalls = 0;

  @override
  RewardedAdState get state =>
      loaded ? RewardedAdState.loaded : RewardedAdState.failedLoad;

  @override
  bool get isLoaded => loaded;

  @override
  Stream<RewardedAdState> get stateStream => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadRewarded() async {
    loadCalls += 1;
  }

  @override
  Future<bool> showRewarded({
    required VoidCallback onEarnedReward,
    required VoidCallback onDismissed,
  }) async {
    if (!loaded) return false;
    onEarned = onEarnedReward;
    // Simula o usuário completando o vídeo.
    onEarnedReward();
    onDismissed();
    return true;
  }
}

/// Fake do repositório de anúncios — captura payload e controla streams.
class _FakeRepository implements AdsRepositoryApi {
  final List<Map<String, String>> calls = <Map<String, String>>[];
  final StreamController<AdRewardIntentResult> intentController =
      StreamController<AdRewardIntentResult>.broadcast();

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String adUnitId,
    required String clientVersion,
  }) async {
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
      intentController.stream;

  @override
  Stream<List<AdRewardEntry>> watchTodayRewards(String uid) =>
      const Stream<List<AdRewardEntry>>.empty();

  @override
  Stream<int?> watchDailyLimit() => const Stream<int?>.empty();
}

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('card exibe título, contador "0 de 10 hoje" e botão ASSISTIR',
      (WidgetTester tester) async {
    final _FakeAds ads = _FakeAds();
    await tester.pumpWidget(
      _wrap(
        RewardedAdCard(
          uid: 'uid-1',
          ads: ads,
          repository: _FakeRepository(),
          clientVersion: 'test',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ASSISTA E GANHE 1 COIN'), findsOneWidget);
    expect(find.text('0 de 10 hoje'), findsOneWidget);
    expect(find.text('ASSISTIR'), findsOneWidget);
  });

  testWidgets('fluxo completo: show → onUserEarnedReward → createIntent com '
      'payload == campos das rules → sheet de validação', (WidgetTester tester) async {
    final _FakeAds ads = _FakeAds();
    final _FakeRepository repo = _FakeRepository();
    await tester.pumpWidget(
      _wrap(
        RewardedAdCard(
          uid: 'uid-1',
          ads: ads,
          service: AdRewardService(repository: repo),
          repository: repo,
          clientVersion: '9.9.9',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ASSISTIR'));
    // NOTA: o sheet pendente tem spinner infinito ⇒ pumpAndSettle NUNCA
    // assentaria; usar pumps explícitos.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Payload com EXATAMENTE os campos das rules.
    expect(repo.calls, hasLength(1));
    expect(repo.calls.single['uid'], 'uid-1');
    expect(repo.calls.single['adUnitId'], isNotEmpty);
    expect(repo.calls.single['clientVersion'], '9.9.9');

    // Sheet "Validando com o servidor…" visível enquanto pending.
    expect(find.text('Validando com o servidor…'), findsOneWidget);

    // Runner processa ⇒ done ⇒ sheet mostra +1 COIN.
    repo.intentController.add(
      const AdRewardIntentResult(status: 'done'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('+1 COIN'), findsOneWidget);
  });

  testWidgets('intent failed mostra mensagem SEGURA por failureCode',
      (WidgetTester tester) async {
    final _FakeAds ads = _FakeAds();
    final _FakeRepository repo = _FakeRepository();
    await tester.pumpWidget(
      _wrap(
        RewardedAdCard(
          uid: 'uid-1',
          ads: ads,
          service: AdRewardService(repository: repo),
          repository: repo,
          clientVersion: 'test',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ASSISTIR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    repo.intentController.add(
      const AdRewardIntentResult(status: 'failed', failureCode: 'DAILY_LIMIT_REACHED'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Limite diário'), findsOneWidget);
  });

  testWidgets('sem anúncio carregado: botão desabilitado, sem quebrar a loja',
      (WidgetTester tester) async {
    final _FakeAds ads = _FakeAds(loaded: false);
    final _FakeRepository repo = _FakeRepository();
    await tester.pumpWidget(
      _wrap(
        RewardedAdCard(
          uid: 'uid-1',
          ads: ads,
          service: AdRewardService(repository: repo),
          repository: repo,
          clientVersion: 'test',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder button = find.widgetWithText(ElevatedButton, 'ASSISTIR');
    expect(button, findsOneWidget);
    final ElevatedButton elevated =
        button.evaluate().single.widget as ElevatedButton;
    expect(elevated.onPressed, isNull); // desabilitado

    // Nenhuma intent é criada sem anúncio exibido.
    expect(repo.calls, isEmpty);
  });
}
