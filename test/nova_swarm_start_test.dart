import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/game_session_service.dart';
import 'package:playhash/data/models/game_model.dart';
import 'package:playhash/data/repositories/game_sessions_repository.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/renderer.dart';
import 'package:playhash/features/games/nova_swarm/nova_swarm_screen.dart';

GameModel _game() => GameModel.fromMap('nova-swarm', <String, dynamic>{
      'name': 'NOVA SWARM',
      'difficulty': 'easy',
      'enabled': true,
      'version': 1,
      'configuration': <String, dynamic>{
        'durationSeconds': 60,
        'baseEnemies': 8,
        'enemiesPerWaveStep': 4,
        'enemyHp': 2,
        'lives': 3,
        'pointsPerKill': 150,
        'pointsPerHit': 25,
        'waveBonus': 500,
        'maxScore': 30000,
        'maxScorePerSecond': 500,
        'minDurationSeconds': 5,
        'maxExpectedScore': 12000,
        'powerCapPerSessionBaseUnits': 100000,
        'powerFormula': 'linear_cap',
      },
    });

/// Repositório falso de sessões: criação instantânea ou pendurada (timeout).
class _FakeSessionsRepo implements GameSessionsRepositoryApi {
  _FakeSessionsRepo({this.hangCreate = false});

  /// true ⇒ createSession nunca completa (simula rede lenta/timeout).
  final bool hangCreate;
  int createCalls = 0;

  @override
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
  }) async {
    createCalls++;
    if (hangCreate) return Completer<String>().future;
    return 'session-$createCalls';
  }

  @override
  Future<void> finishSession({
    required String sessionId,
    required int score,
    int? kills,
  }) async {}

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(
    String sessionId,
  ) =>
      const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

  @override
  Future<int> bestScore({required String uid, required String gameId}) async => 0;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  GameSessionsRepositoryApi repo,
) async {
  // Mock do canal do package_info_plus (em testes, mensagens de plataforma
  // sem handler ficam PENDENTES para sempre e travariam o start da sessão).
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (MethodCall call) async => <String, dynamic>{
      'name': 'playhash',
      'version': '1.0.0',
      'buildNumber': '1',
      'packageName': 'com.mustarda.playhash',
      'installerStore': null,
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider
            .overrideWithValue(const AsyncValue<String?>.data('user-1')),
        gameSessionServiceProvider.overrideWithValue(
          GameSessionService(repository: repo),
        ),
      ],
      child: MaterialApp(home: NovaSwarmScreen(game: _game())),
    ),
  );
  await tester.pump(); // settle inicial (instruções)
}

/// Estado atual do painter do PLAYFIELD (ignora mini-naves do HUD).
NovaSwarmState _playfieldState(WidgetTester tester) {
  final CustomPaint paint = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((CustomPaint p) => p.painter is NovaSwarmPainter);
  return (paint.painter as NovaSwarmPainter).state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NOVA SWARM — ciclo de vida do start', () {
    testWidgets('INICIAR abre sessão e o playfield roda: timer decresce, '
        'banner sai e o jogador fica dentro dos limites',
        (WidgetTester tester) async {
      final _FakeSessionsRepo repo = _FakeSessionsRepo();
      await _pumpScreen(tester, repo);

      // Ainda nas instruções: sem HUD.
      expect(find.text('INICIAR'), findsOneWidget);
      expect(find.text('SCORE'), findsNothing);

      await tester.tap(find.text('INICIAR'));
      await tester.pump(); // sessão criada (fake imediato) + stage playing

      // Sessão 'open' criada ANTES do playfield.
      expect(repo.createCalls, 1);
      expect(find.text('SCORE'), findsOneWidget);

      final NovaSwarmState initial = _playfieldState(tester);
      expect(initial.timeLeft, 60);

      // COUNTDOWN v2 (3-2-1-GO): loop congelado por ~2.8s.
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump();
      expect(_playfieldState(tester).timeLeft, 60); // timer só inicia no GO

      // ~3s de jogo em frames de 25ms (dt real por tick).
      for (int i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      // Banner "WAVE 1" é overlay visual de 1s — não bloqueia nada.
      final NovaSwarmState s = _playfieldState(tester);
      expect(s.isBannerActive, isFalse);
      expect(s.elapsed, greaterThan(2.5));
      expect(s.timeLeft, lessThan(60));

      // Timer REAGIU (HUD reconstrói a cada tick): exibe o ceil do estado.
      expect(find.text('60'), findsNothing);
      expect(find.text(s.timeLeft.ceil().toString()), findsOneWidget);

      // Jogador visível desde o frame 0: centro-x, 80% da altura, clamp ok.
      expect(s.playerY, closeTo(s.fieldSize.height * 0.8, 0.01));
      expect(s.playerX, greaterThanOrEqualTo(0));
      expect(s.playerX, lessThanOrEqualTo(s.fieldSize.width));
      expect(initial.playerY, closeTo(initial.fieldSize.height * 0.8, 0.01));
    });

    testWidgets('sessão que estoura o timeout NUNCA abre o playfield: '
        'erro seguro PT-BR + botões TENTAR/VOLTAR',
        (WidgetTester tester) async {
      final _FakeSessionsRepo repo = _FakeSessionsRepo(hangCreate: true);
      await _pumpScreen(tester, repo);

      await tester.tap(find.text('INICIAR'));
      await tester.pump(); // stage creating (spinner)

      // Primeira tentativa: timeout de 5s.
      await tester.pump(const Duration(seconds: 6));
      // Retry automático: segundo timeout de 5s.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      // Duas tentativas (timeout + retry); erro visível; SEM playfield zumbi.
      expect(repo.createCalls, 2);
      expect(find.text('SCORE'), findsNothing);
      expect(find.textContaining('demorou demais'), findsOneWidget);
      expect(find.text('VOLTAR'), findsOneWidget);
      expect(find.text('INICIAR'), findsOneWidget); // TENTAR novamente
    });
  });
}
