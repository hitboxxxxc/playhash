import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/claim_service.dart';
import 'package:playhash/data/models/mission_model.dart';
import 'package:playhash/features/missions/missions_screen.dart';

MissionView _view(
  String id, {
  String kind = 'daily',
  int progress = 0,
  bool claimed = false,
  int target = 3,
  int reward = 100,
  String metric = 'plays',
}) {
  return MissionView(
    mission: MissionModel(
      id: id,
      kind: kind,
      title: id,
      description: 'desc',
      metric: metric,
      target: target,
      rewardCoins: reward,
      enabled: true,
    ),
    progress: MissionProgress(progress: progress, claimed: claimed),
  );
}

/// Fake do serviço de claim (nenhum acesso real ao Firestore nos testes).
class _FakeClaimService extends ClaimService {
  _FakeClaimService();
}

Future<void> _pump(
  WidgetTester tester,
  List<MissionView> views,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Key única: cada _pump cria um container NOVO (sem reaproveitar o
      // estado do ProviderScope anterior entre cenários do mesmo teste).
      key: UniqueKey(),
      overrides: [
        missionsStreamProvider.overrideWith((Ref ref) => Stream<List<MissionView>>.value(views)),
        claimServiceProvider.overrideWithValue(_FakeClaimService()),
      ],
      child: const MaterialApp(home: MissionsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MISSÕES: abas DIÁRIAS/SEMANAIS/EVENTOS visíveis',
      (WidgetTester tester) async {
    await _pump(tester, <MissionView>[_view('m_daily_play3')]);

    expect(find.text('DIÁRIAS'), findsOneWidget);
    expect(find.text('SEMANAIS'), findsOneWidget);
    expect(find.text('EVENTOS'), findsOneWidget);
  });

  testWidgets('missão em progresso mostra x / y e botão JOGAR',
      (WidgetTester tester) async {
    await _pump(tester, <MissionView>[
      _view('Jogue 3 partidas', progress: 2, target: 3),
    ]);

    expect(find.text('Progresso: 2 / 3'), findsOneWidget);
    expect(find.text('JOGAR'), findsOneWidget);
    expect(find.text('RESGATAR'), findsNothing);
    expect(find.text('Recompensa: 100 COIN'), findsOneWidget);
  });

  testWidgets('missão completa mostra RESGATAR; claimed mostra RESGATADO',
      (WidgetTester tester) async {
    await _pump(tester, <MissionView>[
      _view('Jogue 3 partidas', progress: 3, target: 3),
    ]);
    expect(find.text('RESGATAR'), findsOneWidget);

    await _pump(tester, <MissionView>[
      _view('Jogue 3 partidas', progress: 3, target: 3, claimed: true),
    ]);
    expect(find.text('RESGATAR'), findsNothing);
    expect(find.text('RESGATADO'), findsOneWidget);
  });

  testWidgets('aba SEMANAIS lista apenas missões semanais',
      (WidgetTester tester) async {
    await _pump(tester, <MissionView>[
      _view('MISSAO DIARIA', kind: 'daily', progress: 1),
      _view('MISSAO SEMANAL', kind: 'weekly', progress: 1),
    ]);

    expect(find.text('MISSAO DIARIA'), findsOneWidget);
    expect(find.text('MISSAO SEMANAL'), findsNothing);

    await tester.tap(find.text('SEMANAIS'));
    await tester.pumpAndSettle();

    expect(find.text('MISSAO SEMANAL'), findsOneWidget);
    expect(find.text('MISSAO DIARIA'), findsNothing);
  });

  testWidgets('aba EVENTOS mostra EM BREVE', (WidgetTester tester) async {
    await _pump(tester, <MissionView>[_view('m_daily_play3')]);

    await tester.tap(find.text('EVENTOS'));
    await tester.pumpAndSettle();

    expect(find.text('EM BREVE'), findsOneWidget);
  });

  testWidgets('lista vazia mostra estado vazio (sem crash)',
      (WidgetTester tester) async {
    await _pump(tester, const <MissionView>[]);
    expect(find.text('Nenhuma missão disponível agora.'), findsOneWidget);
  });
}
