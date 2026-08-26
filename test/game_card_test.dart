import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/data/models/game_model.dart';
import 'package:playhash/features/games/nova_swarm/engine/player_sprite.dart';
import 'package:playhash/features/games/nova_swarm/engine/renderer.dart';
import 'package:playhash/features/games/widgets/game_card.dart';

/// Finder do thumbnail desenhado em código (mini cena estrelada).
Finder _thumbPainterFinder() => find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is NovaSwarmThumbPainter,
    );

GameModel _game(String id) => GameModel.fromMap(id, <String, dynamic>{
      'name': id == 'nova-swarm' ? 'NOVA SWARM' : 'OUTRO JOGO',
      'difficulty': 'easy',
      'enabled': true,
      'version': 2,
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

Widget _wrap(GameModel game, {bool implemented = true}) =>
    ProviderScope(
      overrides: [
        bestScoreProvider.overrideWith((Ref ref, String gameId) async => 0),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 420,
              width: 320,
              child: GameCard(
                game: game,
                onPlay: () {},
                implemented: implemented,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('card nova-swarm usa assets/nave/capa.png como thumbnail',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_game('nova-swarm')));
    await tester.pump();

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      PlayerShipSprites.capa,
    );
    // v3: capa INTEIRA (sem crop) — contain com letterbox discreto.
    expect(image.fit, BoxFit.contain);
    // Thumbnail desenhado em código NÃO deve estar presente neste card.
    expect(_thumbPainterFinder(), findsNothing);
  });

  testWidgets('outro jogo implementado mantém thumbnail desenhada em código',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_game('outro-jogo')));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(_thumbPainterFinder(), findsOneWidget);
  });

  testWidgets('card EM BREVE permanece intacto (sem capa, botão desabilitado)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_game('futuro-jogo'), implemented: false));
    await tester.pump();

    // Chip "EM BREVE" + rótulo do botão desabilitado.
    expect(find.text('EM BREVE'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
    final ElevatedButton button =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });
}
