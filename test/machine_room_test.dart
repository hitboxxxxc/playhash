import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/core/widgets/machine_sprite.dart';
import 'package:playhash/features/home/widgets/machine_room_grid.dart';

const MachineModel kRigScrap = MachineModel(
  id: 'i1',
  type: 'rig-scrap',
  level: 1,
  power: 10,
  active: true,
  metadata: <String, dynamic>{'rarity': 'common'},
);

Future<void> _pumpGrid(
  WidgetTester tester, {
  required List<MachineModel> machines,
  required int machineSlots,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MachineRoomGrid(
            machines: machines,
            machineSlots: machineSlots,
            onEditRoomTap: () {},
            onOrganizeTap: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final Finder _lockedSlots = find.byWidgetPredicate(
  (Widget w) =>
      w is Semantics && (w.properties.label?.contains('travado') ?? false),
);

final Finder _emptySlots = find.byWidgetPredicate(
  (Widget w) =>
      w is Semantics && (w.properties.label?.contains('vazio') ?? false),
);

void main() {
  testWidgets('SALA: máquina owned renderiza sprite + badge LV.1 verde',
      (WidgetTester tester) async {
    await _pumpGrid(
      tester,
      machines: const <MachineModel>[kRigScrap],
      machineSlots: 10,
    );

    expect(find.text('LV.1'), findsOneWidget);
    expect(find.byType(MachineSprite), findsOneWidget);
    // 1 owned + 9 vazios, nenhum travado.
    expect(_emptySlots, findsNWidgets(9));
    expect(_lockedSlots, findsNothing);
  });

  testWidgets('SALA: slots além de machineSlots aparecem travados',
      (WidgetTester tester) async {
    await _pumpGrid(
      tester,
      machines: const <MachineModel>[kRigScrap],
      machineSlots: 7, // 7 disponíveis; grade de 10 posições => 3 travados
    );

    // 1 owned + 6 vazios + 3 travados.
    expect(_emptySlots, findsNWidgets(6));
    expect(_lockedSlots, findsNWidgets(3));
    expect(find.byType(MachineSprite), findsOneWidget);
  });

  testWidgets('SALA vazia: todos os slots com "+" discreto',
      (WidgetTester tester) async {
    await _pumpGrid(tester, machines: const <MachineModel>[], machineSlots: 10);

    expect(_emptySlots, findsNWidgets(10));
    expect(_lockedSlots, findsNothing);
    expect(find.byType(MachineSprite), findsNothing);
    expect(find.text('EDITAR SALA'), findsOneWidget);
    expect(find.text('ORGANIZAR'), findsOneWidget);
  });
}
