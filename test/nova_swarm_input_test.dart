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
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
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

class _FakeSessionsRepo implements GameSessionsRepositoryApi {
  @override
  Future<String> createSession({
    required String uid,
    required String gameId,
    required String clientVersion,
  }) async =>
      'session-input-test';

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

/// Estado atual do painter do PLAYFIELD (ignora mini-naves do HUD).
NovaSwarmState _playfieldState(WidgetTester tester) {
  final CustomPaint paint = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((CustomPaint p) => p.painter is NovaSwarmPainter);
  return (paint.painter as NovaSwarmPainter).state;
}

/// Tiros do JOGADOR no estado (exclui orbes inimigas).
int _playerBolts(NovaSwarmState s) =>
    s.bullets.where((Bullet b) => !b.isEnemy).length;

Future<void> _pumpPlayingField(WidgetTester tester) async {
  // Mock do canal do package_info_plus (mensagens sem handler ficam
  // pendentes e travariam o start da sessão).
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
          GameSessionService(repository: _FakeSessionsRepo()),
        ),
      ],
      child: MaterialApp(home: NovaSwarmScreen(game: _game())),
    ),
  );
  await tester.pump(); // instruções

  await tester.tap(find.text('INICIAR'));
  await tester.pump(); // stage playing

  // COUNTDOWN 3-2-1-GO (~2.8s congelado) + frame do GO.
  await tester.pump(const Duration(milliseconds: 2800));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NOVA SWARM — input de toque (ponteiro)', () {
    testWidgets(
        'pointer down/move move o alvo e dispara (autofire); '
        'pointer up para os tiros', (WidgetTester tester) async {
      await _pumpPlayingField(tester);

      final NovaSwarmState before = _playfieldState(tester);
      expect(before.shooting, isFalse); // sem dedo ⇒ sem tiro

      // DOWN na lateral esquerda (x=80; clamp min = 52 ⇒ alvo 80).
      final TestGesture finger = await tester.startGesture(
        const Offset(80, 480),
      );
      await tester.pump(const Duration(milliseconds: 16));

      NovaSwarmState s = _playfieldState(tester);
      expect(s.shooting, isTrue, reason: 'dedo na tela ⇒ isTouching/shooting');
      expect(s.playerTargetX, closeTo(80, 0.5));

      // ~300ms tocando ⇒ cooldown 160ms respeitado ⇒ ≥1 bolt spawnado.
      int boltsAfterDown = 0;
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        boltsAfterDown =
            _playerBolts(_playfieldState(tester)).clamp(boltsAfterDown, 1 << 30);
      }
      expect(boltsAfterDown, greaterThanOrEqualTo(1),
          reason: 'autofire 160ms deve spawnar tiros enquanto tocando');

      // MOVE para o centro: alvo acompanha o dedo (lerp move a nave).
      await finger.moveTo(const Offset(400, 480));
      await tester.pump(const Duration(milliseconds: 16));
      s = _playfieldState(tester);
      expect(s.shooting, isTrue);
      expect(s.playerTargetX, closeTo(400, 0.5));

      // A nave efetivamente se aproxima do alvo após alguns frames.
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(_playfieldState(tester).playerX, closeTo(400, 40));

      // UP: toque termina ⇒ shooting false e NENHUM bolt novo é criado.
      await finger.up();
      await tester.pump(const Duration(milliseconds: 16));
      s = _playfieldState(tester);
      expect(s.shooting, isFalse);

      final int boltsAtUp = _playerBolts(s);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      // Bolts em voo podem sair da tela, mas nenhum NOVO surge.
      expect(_playerBolts(_playfieldState(tester)), lessThanOrEqualTo(boltsAtUp));
    });

    testWidgets(
        'segundo dedo não interrompe o comando: up do extra mantém o tiro',
        (WidgetTester tester) async {
      await _pumpPlayingField(tester);

      // Primeiro dedo comanda.
      final TestGesture primary = await tester.startGesture(
        const Offset(200, 480),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(_playfieldState(tester).shooting, isTrue);

      // Segundo dedo toca e solta: NÃO pode cancelar o primeiro.
      final TestGesture extra = await tester.startGesture(
        const Offset(600, 200),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await extra.up();
      await tester.pump(const Duration(milliseconds: 16));

      final NovaSwarmState s = _playfieldState(tester);
      expect(s.shooting, isTrue,
          reason: 'up do dedo extra não encerra o toque comandante');
      expect(s.playerTargetX, closeTo(200, 0.5));

      await primary.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_playfieldState(tester).shooting, isFalse);
    });
  });
}
