import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/home/widgets/home_header.dart';

void main() {
  testWidgets('HomeHeader não gera RenderFlex overflow com 320dp de largura',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HomeHeader(
                  displayName: 'JOGADOREXEMPLOMUITOLONGO',
                  availableBalance: BigInt.from(1234567),
                  onAddTap: () {},
                  onNotificationsTap: () {},
                  onSettingsTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Qualquer overflow de RenderFlex é reportado via FlutterError aqui.
    final Object? error = tester.takeException();
    expect(
      error,
      isNot(predicate(
        (Object? e) => e.toString().contains('RenderFlex overflowed'),
        'RenderFlex overflow',
      )),
    );
    expect(error, isNull);
  });
}
