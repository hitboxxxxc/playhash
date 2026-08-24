import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/claim_service.dart';
import 'package:playhash/data/models/mission_model.dart';
import 'package:playhash/data/models/season_model.dart';
import 'package:playhash/features/season_pass/season_screen.dart';

SeasonModel _season() {
  final DateTime start = DateTime.now().subtract(const Duration(days: 1));
  return SeasonModel(
    id: 'season-01',
    name: 'TEMPORADA 01',
    startAt: start,
    endAt: start.add(const Duration(days: 30)),
    levelXp: 1200,
    freeTrack: List<SeasonReward>.generate(
      20,
      (int i) => SeasonReward(type: 'coins', amountCoins: 100 + 50 * i),
    ),
    premiumTrack: List<SeasonReward>.generate(
      20,
      (int i) => SeasonReward(type: 'coins', amountCoins: 500 + 150 * i),
    ),
  );
}

MissionView _seasonMission({int progress = 0, bool claimed = false}) {
  return MissionView(
    mission: const MissionModel(
      id: 's01_play50',
      kind: 'season',
      title: 'Jogue 50 partidas na temporada',
      description: 'desc',
      metric: 'plays',
      target: 50,
      rewardCoins: 300,
      enabled: true,
    ),
    progress: MissionProgress(progress: progress, claimed: claimed),
  );
}

class _FakeClaimService extends ClaimService {
  _FakeClaimService();
}

Future<void> _pump(
  WidgetTester tester, {
  SeasonModel? season,
  SeasonProgressModel? progress,
  List<MissionView> missions = const <MissionView>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        seasonProvider.overrideWith((Ref ref) async => season),
        seasonProgressStreamProvider.overrideWith(
          (Ref ref) => Stream<SeasonProgressModel?>.value(progress),
        ),
        seasonMissionsStreamProvider.overrideWith(
          (Ref ref) => Stream<List<MissionView>>.value(missions),
        ),
        claimServiceProvider.overrideWithValue(_FakeClaimService()),
      ],
      child: const MaterialApp(home: SeasonScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TEMPORADA: header com nome, nível e XP dentro do nível',
      (WidgetTester tester) async {
    await _pump(
      tester,
      season: _season(),
      progress: const SeasonProgressModel(
        seasonId: 'season-01',
        xp: 2040,
        level: 2,
        claimedFree: <int>{},
        claimedPremium: <int>{},
        premiumActive: false,
      ),
    );

    expect(find.text('TEMPORADA'), findsOneWidget); // appbar
    // Header + coluna do nível 2 na trilha.
    expect(find.text('NÍVEL 2'), findsNWidgets(2));
    expect(find.text('XP 840 / 1200'), findsOneWidget);
    expect(find.textContaining('Termina em'), findsOneWidget);
  });

  testWidgets('trilha: nível alcançado claimable; claimed mostra ✓; premium travada',
      (WidgetTester tester) async {
    await _pump(
      tester,
      season: _season(),
      progress: const SeasonProgressModel(
        seasonId: 'season-01',
        xp: 0,
        level: 2,
        claimedFree: <int>{1},
        claimedPremium: <int>{},
        premiumActive: false,
      ),
    );

    // Nível 1 claimed (✓), nível 2 claimable (RESGATAR), premium travada.
    expect(find.text('RESGATAR'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    expect(find.text('PREMIUM'), findsWidgets);
    expect(find.text('ADQUIRIR PASSE'), findsOneWidget);
  });

  testWidgets('ADQUIRIR PASSE abre sheet "em breve" (sem promessas)',
      (WidgetTester tester) async {
    await _pump(tester, season: _season());

    await tester.tap(find.text('ADQUIRIR PASSE'));
    await tester.pumpAndSettle();

    expect(find.text('Assinaturas chegam na próxima atualização.'),
        findsOneWidget);
  });

  testWidgets('missões da temporada listadas com progresso e recompensa',
      (WidgetTester tester) async {
    await _pump(
      tester,
      season: _season(),
      missions: <MissionView>[_seasonMission(progress: 28)],
    );

    expect(find.text('MISSÕES DA TEMPORADA'), findsOneWidget);
    expect(find.textContaining('JOGUE 50 PARTIDAS'), findsOneWidget);
    expect(find.text('Progresso: 28 / 50'), findsOneWidget);
    expect(find.text('Recompensa: 300 COIN'), findsOneWidget);
  });

  testWidgets('sem temporada ativa ⇒ estado vazio (nada inventado)',
      (WidgetTester tester) async {
    await _pump(tester, season: null);

    expect(find.text('Nenhuma temporada ativa no momento.'), findsOneWidget);
  });
}
