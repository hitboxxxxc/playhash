import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/theme/pixel_theme.dart';
import 'package:playhash/core/widgets/pixel_button.dart';
import 'package:playhash/core/widgets/pixel_card.dart';
import 'package:playhash/core/widgets/pixel_icon.dart';
import 'package:playhash/core/widgets/pixel_icons.dart';
import 'package:playhash/core/widgets/section_title.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: PixelTheme.background,
      body: SizedBox(width: 320, child: child),
    ),
  );
}

void main() {
  testWidgets('todos os ícones constroem sem erro em 320dp', (tester) async {
    final List<List<String>> all = [
      PixelIcons.coin,
      PixelIcons.pickaxe,
      PixelIcons.gamepad,
      PixelIcons.clipboard,
      PixelIcons.gift,
      PixelIcons.wallet,
      PixelIcons.safe,
      PixelIcons.gear,
      PixelIcons.cart,
      PixelIcons.monitor,
      PixelIcons.home,
      PixelIcons.play,
    ];
    final List<Widget> icons = all
        .map((m) => PixelIcon(matrix: m, palette: PixelIcons.palette, size: 32))
        .toList();
    await tester.pumpWidget(_wrap(Wrap(children: icons)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PixelButton desabilitado mostra EM BREVE', (tester) async {
    await tester.pumpWidget(_wrap(const PixelButton(label: 'MELHORAR')));
    expect(find.text('EM BREVE'), findsOneWidget);
  });

  testWidgets('PixelButton habilitado mostra label e responde', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
        _wrap(PixelButton(label: 'COMPRAR', onPressed: () => taps++)));
    expect(find.text('COMPRAR'), findsOneWidget);
    await tester.tap(find.text('COMPRAR'));
    expect(taps, 1);
  });

  testWidgets('PixelCard e SectionTitle sem overflow', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      SectionTitle(text: 'GANHE COIN'),
      SizedBox(height: 8),
      PixelCard(child: Text('conteúdo', style: PixelTheme.label)),
    ])));
    expect(tester.takeException(), isNull);
  });
}
