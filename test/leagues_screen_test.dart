import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/data/models/league_model.dart';
import 'package:playhash/data/models/power_model.dart';
import 'package:playhash/features/leagues/leagues_screen.dart';

const List<LeagueModel> kLeagues = <LeagueModel>[
  LeagueModel(id: 'bronze', name: 'BRONZE', tier: 1, minPower: 100, dailyRewardCoins: 50, colorValue: 0xFFB0713B),
  LeagueModel(id: 'prata', name: 'PRATA', tier: 2, minPower: 500, dailyRewardCoins: 100, colorValue: 0xFFC0C8D4),
  LeagueModel(id: 'ouro', name: 'OURO', tier: 3, minPower: 1500, dailyRewardCoins: 250, colorValue: 0xFFF5C542),
  LeagueModel(id: 'platina', name: 'PLATINA', tier: 4, minPower: 10000, dailyRewardCoins: 500, colorValue: 0xFF7FE3DE),
  LeagueModel(id: 'diamante', name: 'DIAMANTE', tier: 5, minPower: 100000, dailyRewardCoins: 1000, colorValue: 0xFF5AA7FF),
];

Future<void> _pump(
  WidgetTester tester, {
  List<LeagueModel> leagues = kLeagues,
  UserLeagueModel? userLeague,
  List<LeaderboardEntry> entries = const <LeaderboardEntry>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        leaguesCatalogProvider.overrideWith((Ref ref) async => leagues),
        userLeagueStreamProvider.overrideWith((Ref ref) => Stream<UserLeagueModel?>.value(userLeague)),
        powerStreamProvider.overrideWith((Ref ref) => Stream<PowerModel?>.value(null)),
        currentUidProvider.overrideWith((Ref ref) async => 'me-uid'),
        leaderboardProvider.overrideWith(
          (Ref ref, String leagueId) => Stream<List<LeaderboardEntry>>.value(entries),
        ),
      ],
      child: const MaterialApp(home: LeaguesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('LIGAS: fileira exibe as 5 ligas com poder necessário',
      (WidgetTester tester) async {
    await _pump(tester);

    for (final String name in <String>['BRONZE', 'PRATA', 'OURO', 'PLATINA', 'DIAMANTE']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('Poder necessário:'), findsNWidgets(5));
  });

  testWidgets('liga atual destacada + card com próxima liga e progresso',
      (WidgetTester tester) async {
    await _pump(
      tester,
      userLeague: const UserLeagueModel(leagueId: 'ouro', leagueName: 'OURO'),
    );

    expect(find.text('OURO I'), findsOneWidget);
    expect(find.textContaining('Próxima liga: PLATINA'), findsOneWidget);
    expect(find.text('SEM LIGA AINDA'), findsNothing);
  });

  testWidgets('sem liga ⇒ estado vazio (nada inventado)',
      (WidgetTester tester) async {
    await _pump(tester, userLeague: null);

    expect(find.text('SEM LIGA AINDA'), findsOneWidget);
    expect(find.text('RANKING DA LIGA'), findsNothing);
  });

  testWidgets('ranking exibe VOCÊ destacado e maskedName dos outros',
      (WidgetTester tester) async {
    await _pump(
      tester,
      userLeague: const UserLeagueModel(leagueId: 'ouro', leagueName: 'OURO'),
      entries: const <LeaderboardEntry>[
        LeaderboardEntry(uid: 'u1', maskedName: 'PL***', totalPower: 2450),
        LeaderboardEntry(uid: 'u2', maskedName: 'MI***', totalPower: 1980),
        LeaderboardEntry(uid: 'me-uid', maskedName: 'CR***', totalPower: 897),
      ],
    );

    expect(find.text('RANKING DA LIGA'), findsOneWidget);
    expect(find.text('VOCÊ'), findsOneWidget);
    expect(find.text('PL***'), findsOneWidget);
    // Dados pessoais nunca aparecem (apenas maskedName).
    expect(find.textContaining('me-uid'), findsNothing);
  });

  testWidgets('recompensa diária mostra valor e origem no servidor',
      (WidgetTester tester) async {
    await _pump(
      tester,
      userLeague: const UserLeagueModel(
        leagueId: 'ouro',
        leagueName: 'OURO',
        lastDailyGrant: '2026-08-24',
      ),
    );

    expect(find.textContaining('Recompensa diária da liga OURO'), findsOneWidget);
    expect(find.textContaining('250 COIN'), findsOneWidget);
    expect(find.textContaining('servidor'), findsOneWidget);
    expect(find.textContaining('Último envio: 2026-08-24'), findsOneWidget);
  });
}
