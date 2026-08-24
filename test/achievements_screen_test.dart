import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/claim_service.dart';
import 'package:playhash/data/models/achievement_model.dart';
import 'package:playhash/features/achievements/achievements_screen.dart';

AchievementView _view(
  String id, {
  String category = 'games',
  int progress = 0,
  bool claimed = false,
  int target = 1,
  int reward = 50,
  String metric = 'plays',
}) {
  return AchievementView(
    achievement: AchievementModel(
      id: id,
      category: category,
      title: id,
      description: 'desc',
      metric: metric,
      target: target,
      rewardCoins: reward,
      enabled: true,
    ),
    progress: AchievementProgress(progress: progress, claimed: claimed),
  );
}

class _FakeClaimService extends ClaimService {
  _FakeClaimService();
}

Future<void> _pump(
  WidgetTester tester,
  List<AchievementView> views,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        achievementsStreamProvider
            .overrideWith((Ref ref) => Stream<List<AchievementView>>.value(views)),
        claimServiceProvider.overrideWithValue(_FakeClaimService()),
      ],
      child: const MaterialApp(home: AchievementsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('contador "X de Y desbloqueadas" reflete o progresso oficial',
      (WidgetTester tester) async {
    await _pump(tester, <AchievementView>[
      _view('PRIMEIRA PARTIDA', progress: 1, target: 1),
      _view('100 ABATES', progress: 30, target: 100),
      _view('5 MAQUINAS', progress: 5, target: 5, category: 'collection'),
    ]);

    expect(find.text('2 de 3 desbloqueadas'), findsOneWidget);
  });

  testWidgets('conquista claimable mostra RESGATAR; bloqueada não mostra',
      (WidgetTester tester) async {
    await _pump(tester, <AchievementView>[
      _view('PRIMEIRA PARTIDA', progress: 1, target: 1),
      _view('100 ABATES', progress: 30, target: 100),
    ]);

    expect(find.text('RESGATAR'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('30 / 100'), findsOneWidget);
  });

  testWidgets('conquista claimed mostra check (sem botão RESGATAR)',
      (WidgetTester tester) async {
    await _pump(tester, <AchievementView>[
      _view('PRIMEIRA PARTIDA', progress: 1, target: 1, claimed: true),
    ]);

    expect(find.text('RESGATAR'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('aba de categoria filtra a grade', (WidgetTester tester) async {
    await _pump(tester, <AchievementView>[
      _view('CONQUISTA JOGO', category: 'games', progress: 1),
      _view('CONQUISTA MINERACAO', category: 'mining', progress: 1),
    ]);

    expect(find.text('CONQUISTA JOGO'), findsOneWidget);
    expect(find.text('CONQUISTA MINERACAO'), findsOneWidget);

    await tester.tap(find.text('MINERAÇÃO'));
    await tester.pumpAndSettle();

    expect(find.text('CONQUISTA JOGO'), findsNothing);
    expect(find.text('CONQUISTA MINERACAO'), findsOneWidget);
  });

  testWidgets('lista vazia mostra estado vazio (sem crash)',
      (WidgetTester tester) async {
    await _pump(tester, const <AchievementView>[]);
    expect(find.text('0 de 0 desbloqueadas'), findsOneWidget);
    expect(find.text('Nenhuma conquista nesta categoria.'), findsOneWidget);
  });
}
