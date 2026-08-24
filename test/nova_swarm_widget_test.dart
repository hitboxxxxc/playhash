import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/game_session_service.dart';
import 'package:playhash/data/models/game_model.dart';
import 'package:playhash/features/games/nova_swarm/nova_swarm_screen.dart';
import 'package:playhash/features/games/nova_swarm/widgets/instructions_overlay.dart';
import 'package:playhash/features/games/nova_swarm/widgets/result_overlay.dart';

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

void main() {
  group('InstructionsOverlay', () {
    testWidgets('mostra título, instruções, regras e botão INICIAR',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstructionsOverlay(
              game: _game(),
              onStart: () {},
              isLoading: false,
            ),
          ),
        ),
      );

      expect(find.text('NOVA SWARM'), findsOneWidget);
      expect(
        find.textContaining('Toque e SEGURE'),
        findsOneWidget,
      );
      expect(find.textContaining('Duração: 60s'), findsOneWidget);
      expect(find.textContaining('Vidas: 3'), findsOneWidget);
      expect(find.textContaining('2 acertos'), findsOneWidget);
      expect(find.text('INICIAR'), findsOneWidget);
    });

    testWidgets('estado criando sessão desabilita botão (loading)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstructionsOverlay(
              game: _game(),
              onStart: () {},
              isLoading: true,
            ),
          ),
        ),
      );
      // Em loading o rótulo dá lugar ao spinner e o botão fica desabilitado.
      expect(find.text('INICIAR'), findsNothing);
      final ElevatedButton elevated =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(elevated.onPressed, isNull);
    });

    testWidgets('erro seguro PT-BR é exibido', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstructionsOverlay(
              game: _game(),
              onStart: () {},
              isLoading: false,
              error: 'Sem conexão. Verifique a internet e tente novamente.',
            ),
          ),
        ),
      );
      expect(
        find.text('Sem conexão. Verifique a internet e tente novamente.'),
        findsOneWidget,
      );
    });
  });

  group('ResultOverlay', () {
    testWidgets('estágio sending mostra "Enviando resultado…"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultOverlay(
              stage: ResultStage.sending,
              score: 2450,
              kills: 12,
              waves: 2,
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.text('2450'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Enviando resultado…'), findsOneWidget);
    });

    testWidgets('estágio validating mostra validação pelo servidor',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultOverlay(
              stage: ResultStage.validating,
              score: 2450,
              kills: 12,
              waves: 2,
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Em validação pelo servidor'), findsOneWidget);
    });

    testWidgets('serverResult concedido mostra poder e expiração',
        (WidgetTester tester) async {
      final DateTime expires = DateTime(2026, 8, 25, 14, 30);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultOverlay(
              stage: ResultStage.granted,
              score: 12000,
              kills: 40,
              waves: 4,
              serverResult: GameSessionServerResult(
                processed: true,
                status: 'granted',
                powerAmountHs: 100,
                expiresAt: expires,
              ),
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('+100 H/s por 24h'), findsOneWidget);
      expect(find.textContaining('expira 14:30'), findsOneWidget);
      expect(find.text('VITÓRIA!'), findsOneWidget);
    });

    testWidgets('rejeitada mostra mensagem segura', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultOverlay(
              stage: ResultStage.rejected,
              score: 999,
              kills: 3,
              waves: 1,
              serverResult: const GameSessionServerResult(
                processed: true,
                status: 'rejected',
                reason: 'DURATION_TOO_SHORT',
              ),
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Sessão rejeitada'), findsOneWidget);
    });
  });

  group('NovaSwarmScreen (fluxo)', () {
    testWidgets('abre no overlay de instruções ANTES de criar sessão',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(AsyncValue<String?>.data(null)),
          ],
          child: MaterialApp(home: NovaSwarmScreen(game: _game())),
        ),
      );
      expect(find.text('NOVA SWARM'), findsOneWidget);
      expect(find.text('INICIAR'), findsOneWidget);
      // Nenhuma partida em curso: HUD ausente.
      expect(find.text('SCORE'), findsNothing);
    });
  });
}
