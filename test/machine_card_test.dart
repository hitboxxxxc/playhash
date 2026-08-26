import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/data/models/machine_catalog_model.dart';
import 'package:playhash/features/store/widgets/machine_card.dart';

/// Catálogo fake — preço/poder SEMPRE do "backend".
final MachineCatalogModel kRigScrap = MachineCatalogModel(
  id: 'rig-scrap',
  name: 'RIG SCRAP',
  rarity: 'common',
  powerUnits: 10,
  priceUnits: BigInt.from(400000000),
  maxPerUser: 5,
  enabled: true,
);

/// Tile equivalente ao pior caso do grid da LOJA em tela de 320dp
/// (largura ~134dp) — exatamente onde ocorria "BOTTOM OVERFLOWED".
Future<void> _pumpCard(
  WidgetTester tester, {
  required bool canAfford,
  int ownedCount = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 134,
            height: 280, // orçamento do _cardAspectRatio em 320dp
            child: MachineCard(
              machine: kRigScrap,
              ownedCount: ownedCount,
              canAfford: canAfford,
              onBuy: () {},
              onOpenDetails: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('CARD 320dp sem saldo: nenhum overflow; aviso em linha própria '
      'abaixo do botão', (WidgetTester tester) async {
    await _pumpCard(tester, canAfford: false);

    expect(tester.takeException(), isNull);
    expect(find.text('COMPRAR'), findsOneWidget);
    expect(find.text('Saldo insuficiente'), findsOneWidget);
    expect(find.text('400'), findsOneWidget); // preço sempre visível

    // Aviso DEPOIS do botão na vertical (linha própria, nunca sobreposto).
    final double buttonBottom = tester.getBottomRight(find.text('COMPRAR')).dy;
    final double hintTop = tester.getTopLeft(find.text('Saldo insuficiente')).dy;
    expect(hintTop, greaterThan(buttonBottom));
  });

  testWidgets('CARD 320dp comprável: sem overflow e sem aviso',
      (WidgetTester tester) async {
    await _pumpCard(tester, canAfford: true);

    expect(tester.takeException(), isNull);
    expect(find.text('COMPRAR'), findsOneWidget);
    expect(find.text('Saldo insuficiente'), findsNothing);
  });

  testWidgets('CARD: contador compacto "x/max" com Tooltip completo '
      '(palavra "owned" removida — nada truncado)',
      (WidgetTester tester) async {
    await _pumpCard(tester, canAfford: true, ownedCount: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.textContaining('owned'), findsNothing);

    // Tooltip carrega o significado completo.
    expect(
      find.byTooltip('Você possui 2 de 5 desta máquina'),
      findsOneWidget,
    );
  });

  testWidgets('CARD sem limite (maxPerUser = 0): nenhum contador exibido',
      (WidgetTester tester) async {
    final MachineCatalogModel unlimited = MachineCatalogModel(
      id: 'rig-open',
      name: 'RIG OPEN',
      rarity: 'rare',
      powerUnits: 100,
      priceUnits: BigInt.from(1000000000),
      maxPerUser: 0,
      enabled: true,
    );
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 134,
              height: 280,
              child: MachineCard(
                machine: unlimited,
                ownedCount: 0,
                canAfford: true,
                onBuy: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Nenhum contador "x/max" (o "+100,00 H/s" contém "/", por isso o
    // predicate é ancorado ao formato do contador).
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text && RegExp(r'^\d+/\d+$').hasMatch(w.data ?? ''),
      ),
      findsNothing,
    );
  });
}
