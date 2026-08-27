import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/data/models/game_model.dart';
import 'package:playhash/features/games/pixel_games_screen.dart';
import 'package:playhash/features/games/nova_swarm/nova_swarm_screen.dart';

void main() {
  final testGames = [
    const GameModel(
      id: 'nova-swarm',
      name: 'NOVA SWARM',
      difficulty: 'easy',
      enabled: true,
      version: 1,
      configuration: GameConfig(
        durationSeconds: 60,
        baseEnemies: 5,
        enemiesPerWaveStep: 1,
        enemyHp: 1,
        lives: 3,
        pointsPerKill: 10,
        pointsPerHit: 1,
        waveBonus: 50,
        maxScore: 1000,
        maxScorePerSecond: 20,
        minDurationSeconds: 10,
        maxExpectedScore: 500,
        powerCapPerSessionBaseUnits: 400000,
        powerFormula: 'score',
      ),
    ),
    const GameModel(
      id: 'neon-hopper',
      name: 'NEON HOPPER',
      difficulty: 'medium',
      enabled: true,
      version: 1,
      configuration: GameConfig(
        durationSeconds: 60,
        baseEnemies: 5,
        enemiesPerWaveStep: 1,
        enemyHp: 1,
        lives: 3,
        pointsPerKill: 10,
        pointsPerHit: 1,
        waveBonus: 50,
        maxScore: 1000,
        maxScorePerSecond: 20,
        minDurationSeconds: 10,
        maxExpectedScore: 500,
        powerCapPerSessionBaseUnits: 600000,
        powerFormula: 'score',
      ),
    ),
    const GameModel(
      id: 'placeholder-game',
      name: 'EM BREVE GAME',
      difficulty: 'hard',
      enabled: true,
      version: 1,
      configuration: GameConfig(
        durationSeconds: 60,
        baseEnemies: 5,
        enemiesPerWaveStep: 1,
        enemyHp: 1,
        lives: 3,
        pointsPerKill: 10,
        pointsPerHit: 1,
        waveBonus: 50,
        maxScore: 1000,
        maxScorePerSecond: 20,
        minDurationSeconds: 10,
        maxExpectedScore: 500,
        powerCapPerSessionBaseUnits: 800000,
        powerFormula: 'score',
      ),
    ),
  ];

  testWidgets('PixelGamesScreen displays cards and handles interactions properly on 320dp', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesCatalogProvider.overrideWith((ref) => Future.value(testGames)),
        ],
        child: const MaterialApp(
          home: PixelGamesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Check header
    expect(find.text('GAMES'), findsOneWidget);
    expect(find.text('Jogue e ganhe poder de mineração!'), findsOneWidget);

    // Check columns
    expect(find.text('COOLDOWN'), findsNWidgets(3));
    expect(find.text('RECOMPENSA'), findsNWidgets(3));
    expect(find.text('DIFICULDADE'), findsNWidgets(3));

    // Check placeholder badge
    expect(find.text('EM BREVE'), findsOneWidget);

    // Check no overflow
    expect(tester.takeException(), isNull);

    // Tap on implemented game play button
    final playIcon = find.byType(GestureDetector).first;
    await tester.tap(playIcon);
    await tester.pumpAndSettle();

    // Expect to navigate or at least attempt navigation (NovaSwarmScreen or NeonHopperScreen present)
    expect(find.byType(NovaSwarmScreen), findsOneWidget);
  });
}
