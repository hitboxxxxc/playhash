import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/widgets/pixel_shell.dart';
import 'package:playhash/core/widgets/pixel_topbar.dart';
import 'package:playhash/core/widgets/pixel_icon.dart';

void main() {
  testWidgets('PixelShell navigation and menu test', (WidgetTester tester) async {
    final List<String> tappedLabels = [];

    await tester.pumpWidget(
      MaterialApp(
        home: PixelShell(
          balanceText: '1.250',
          pages: [
            Container(color: Colors.red, child: const Text('Home')),
            Container(color: Colors.green, child: const Text('Sala')),
            Container(color: Colors.blue, child: const Text('Games')),
            Container(color: Colors.yellow, child: const Text('Carteira')),
          ],
          menuItems: [
            PixelMenuItem(
              label: 'Test Item',
              onTap: () => tappedLabels.add('Test Item'),
            ),
          ],
        ),
      ),
    );

    // Initial state: Home should be visible
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Sala'), findsNothing);

    // Tap tabs and verify content change
    await tester.tap(find.text('SALA'));
    await tester.pumpAndSettle();
    expect(find.text('Sala'), findsOneWidget);

    await tester.tap(find.text('GAMES'));
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsOneWidget);

    await tester.tap(find.text('CARTEIRA'));
    await tester.pumpAndSettle();
    expect(find.text('Carteira'), findsOneWidget);

    // Open menu
    // Find the GestureDetector inside PixelTopbar, which contains the gear icon.
    await tester.tap(find.descendant(
      of: find.byType(PixelTopbar),
      matching: find.byType(GestureDetector),
    ));
    await tester.pumpAndSettle();

    // Verify modal is open and text is present
    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('Test Item'), findsOneWidget);

    // Tap menu item
    await tester.tap(find.text('Test Item'));
    await tester.pumpAndSettle();
    expect(tappedLabels, contains('Test Item'));
  });
}
