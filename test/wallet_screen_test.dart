import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/wallet/widgets/asset_selector.dart';
import 'package:playhash/features/wallet/widgets/withdraw_form.dart';

/// Widget tests da CARTEIRA com config FAKE do servidor:
/// - WithdrawForm: MÁX. preenche o saldo; submit emite payload
///   (valor em units + endereço); validação local bloqueia mínimo/saldo;
/// - AssetSelector: chips apenas com ativos habilitados.
void main() {
  final WithdrawAssetInfo asset = WithdrawAssetInfo(
    id: 'BTC',
    network: 'Bitcoin',
    minWithdrawUnits: BigInt.from(20000000), // 20 coins
    feeUnits: BigInt.from(2000000), // 2 coins
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    required BigInt availableBalance,
    required void Function(BigInt, String) onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: WithdrawForm(
                asset: asset,
                availableBalance: availableBalance,
                onSubmit: onSubmit,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('exibe taxa e mínimo vindos da config fake do servidor',
      (WidgetTester tester) async {
    await pumpForm(
      tester,
      availableBalance: BigInt.from(100000000),
      onSubmit: (_, _) {},
    );

    expect(find.textContaining('Taxa: 2'), findsOneWidget);
    expect(find.textContaining('definidos pelo servidor'), findsOneWidget);
    expect(find.text('SOLICITAR SAQUE'), findsOneWidget);
    expect(find.textContaining('até 5 minutos'), findsOneWidget);
  });

  testWidgets('MÁX. preenche o campo com o saldo disponível',
      (WidgetTester tester) async {
    await pumpForm(
      tester,
      availableBalance: BigInt.from(100000000), // 100 coins
      onSubmit: (_, _) {},
    );

    await tester.tap(find.byKey(const ValueKey<String>('max_button')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '100'), findsOneWidget);
  });

  testWidgets('submit válido emite valor (units) e E-MAIL FaucetPay digitado',
      (WidgetTester tester) async {
    BigInt? submittedAmount;
    String? submittedEmail;

    await pumpForm(
      tester,
      availableBalance: BigInt.from(100000000),
      onSubmit: (BigInt amount, String email) {
        submittedAmount = amount;
        submittedEmail = email;
      },
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, '25');
    await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
    await tester.pumpAndSettle();

    // 25 coins = 25 × 1e6 units.
    expect(submittedAmount, BigInt.from(25000000));
    expect(submittedEmail, 'owner@example.com');
  });

  testWidgets('bloqueia valor abaixo do mínimo da config (erro específico)',
      (WidgetTester tester) async {
    BigInt? submitted;

    await pumpForm(
      tester,
      availableBalance: BigInt.from(100000000),
      onSubmit: (BigInt amount, _) => submitted = amount,
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
    );
    await tester.enterText(find.byType(TextFormField).last, '10');
    await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Abaixo do mínimo'), findsOneWidget);
    expect(submitted, isNull);
  });

  testWidgets('bloqueia valor acima do saldo disponível',
      (WidgetTester tester) async {
    BigInt? submitted;

    await pumpForm(
      tester,
      availableBalance: BigInt.from(30000000), // 30 coins
      onSubmit: (BigInt amount, _) => submitted = amount,
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080',
    );
    await tester.enterText(find.byType(TextFormField).last, '50');
    await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
    await tester.pumpAndSettle();

    expect(find.textContaining('insuficiente'), findsOneWidget);
    expect(submitted, isNull);
  });

  testWidgets('AssetSelector renderiza chips dos ativos habilitados e '
      'seleciona por toque', (WidgetTester tester) async {
    String selected = 'BTC';
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setter) {
              setState = setter;
              return AssetSelector(
                assets: const <WalletAssetChip>[
                  WalletAssetChip(id: 'BTC', network: 'Bitcoin', symbol: 'B'),
                  WalletAssetChip(id: 'LTC', network: 'Litecoin', symbol: 'L'),
                  WalletAssetChip(id: 'DOGE', network: 'Dogecoin', symbol: 'D'),
                  WalletAssetChip(id: 'USDT', network: 'TRC20', symbol: 'T'),
                ],
                selectedId: selected,
                onSelected: (String id) => setState(() => selected = id),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('USDT'), findsOneWidget);
    expect(find.text('TRC20'), findsOneWidget);

    await tester.tap(find.text('DOGE'));
    await tester.pumpAndSettle();
    expect(selected, 'DOGE');
  });
}
