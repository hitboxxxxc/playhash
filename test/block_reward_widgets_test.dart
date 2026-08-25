import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/data/repositories/mining_repository.dart';
import 'package:playhash/features/mining/widgets/block_reward_card.dart';
import 'package:playhash/features/mining/widgets/next_block_countdown.dart';

/// 12.23 — Cards da MINERAÇÃO: recompensa do bloco (5 COIN), participação
/// ESTIMADA e countdown "Próximo bloco em mm:ss". Valores SEMPRE do backend;
/// sem dados oficiais => "—"/"--:--" (nada inventado no cliente).
void main() {
  testWidgets('BlockRewardCard exibe 5 COIN do backend e estimativa rotulada',
      (WidgetTester tester) async {
    final BlockSnapshot block = BlockSnapshot(
      totalBlockRewardMinimalUnits: BigInt.from(5000000), // 5 COIN
      networkPower: 400,
    );
    final RewardEstimate estimate = RewardEstimate(
      share: 0.25,
      estimatedRewardMinimalUnits: BigInt.from(1250000), // 1,25 COIN
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockRewardCard(block: block, estimate: estimate),
        ),
      ),
    );

    expect(find.text('RECOMPENSA DO BLOCO'), findsOneWidget);
    expect(find.text('5 COIN'), findsOneWidget);
    expect(find.text('ESTIMADA'), findsOneWidget);
    expect(find.text('1,25 COIN'), findsOneWidget);
  });

  testWidgets('BlockRewardCard sem dados oficiais exibe "—" (nada inventado)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BlockRewardCard()),
      ),
    );

    expect(find.text('RECOMPENSA DO BLOCO'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('NextBlockCountdown formata mm:ss a partir do schedule oficial',
      (WidgetTester tester) async {
    final DateTime next =
        DateTime.now().add(const Duration(minutes: 2, seconds: 5));
    final BlockSnapshot block = BlockSnapshot(nextBlockAt: next);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NextBlockCountdown(block: block)),
      ),
    );
    await tester.pump();

    final String text = tester.widget<Text>(
      find.textContaining('Próximo bloco em'),
    ).data!;
    expect(text, matches(RegExp(r'^Próximo bloco em \d{2}:\d{2}$')));
    expect(text.startsWith('Próximo bloco em 02:'), isTrue);
  });

  testWidgets('NextBlockCountdown sem schedule exibe "--:--"',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NextBlockCountdown()),
      ),
    );

    expect(find.text('Próximo bloco em --:--'), findsOneWidget);
  });
}
