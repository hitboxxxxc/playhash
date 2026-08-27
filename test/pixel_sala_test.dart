import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/data/models/machine_catalog_model.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/data/models/power_model.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/machine_catalog_repository.dart';
import 'package:playhash/data/repositories/machines_repository.dart';
import 'package:playhash/data/repositories/mining_repository.dart';
import 'package:playhash/data/repositories/power_repository.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/machines/pixel_sala_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'uid-1';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuthService implements AuthServiceApi {
  @override
  Future<User?> currentUser() async => _FakeUser();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final List<MachineCatalogModel> kFakeCatalog = <MachineCatalogModel>[
  MachineCatalogModel(
    id: 'rig-scrap',
    name: 'RIG SCRAP',
    rarity: 'common',
    powerUnits: 250,
    priceUnits: BigInt.from(250000000),
    maxPerUser: 5,
    enabled: true,
    maxLevel: 5,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  ),
  MachineCatalogModel(
    id: 'rig-nova',
    name: 'RIG NOVA',
    rarity: 'legendary',
    powerUnits: 2000,
    priceUnits: BigInt.from(5000000000),
    maxPerUser: 1,
    enabled: true,
    maxLevel: 5,
    levelPowerStep: 0.25,
    upgradeCostFactor: 0.75,
  ),
];

class _FakeCatalogRepository implements MachineCatalogRepositoryApi {
  _FakeCatalogRepository(this.catalog);
  List<MachineCatalogModel> catalog;
  @override
  Future<List<MachineCatalogModel>> loadCatalog() async => catalog;
}

class _FakeWalletRepository implements WalletRepositoryApi {
  _FakeWalletRepository(this.wallet);
  WalletModel? wallet;
  @override
  Future<WalletModel?> loadWallet(String uid) async => wallet;
  @override
  Stream<WalletModel?> watchWallet(String uid) =>
      Stream<WalletModel?>.value(wallet);
}

class _FakeMachinesRepository implements MachinesRepositoryApi {
  _FakeMachinesRepository(this.machines);
  List<MachineModel> machines;
  @override
  Future<List<MachineModel>> loadMachines(String uid) async => machines;
  @override
  Stream<List<MachineModel>> watchMachines(String uid) =>
      Stream<List<MachineModel>>.value(machines);
}

class _FakePowerRepository implements PowerRepositoryApi {
  _FakePowerRepository(this.power);
  PowerModel? power;
  @override
  Future<PowerModel?> loadPower(String uid) async => power;
  @override
  Stream<PowerModel?> watchPower(String uid) =>
      Stream<PowerModel?>.value(power);
}

class _FakeMiningRepository implements MiningRepositoryApi {
  @override
  Future<BlockSnapshot?> loadBlockSnapshot() async => null;
  @override
  Stream<BlockSnapshot?> watchBlockSnapshot() =>
      const Stream<BlockSnapshot?>.empty();
  @override
  Future<List<RewardEntry>> loadRewardHistory(String uid) async =>
      const <RewardEntry>[];
  @override
  Future<Map<String, dynamic>?> loadUserLeague(String uid) async => null;
  @override
  RewardEstimate? estimateReward(
      {required int yourPower, BlockSnapshot? block}) {
    return null;
  }
}

Future<void> _pumpSala(
  WidgetTester tester, {
  required List<MachineModel> owned,
  int powerBase = 18500,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_FakeAuthService()),
        machineCatalogRepositoryProvider.overrideWithValue(
          _FakeCatalogRepository(kFakeCatalog),
        ),
        walletRepositoryProvider.overrideWithValue(
          _FakeWalletRepository(
            WalletModel(
              internalBalance: BigInt.from(10000000000),
              availableBalance: BigInt.from(10000000000),
              pendingBalance: BigInt.zero,
              lifetimeEarned: BigInt.from(10000000000),
            ),
          ),
        ),
        machinesRepositoryProvider
            .overrideWithValue(_FakeMachinesRepository(owned)),
        powerRepositoryProvider.overrideWithValue(
          _FakePowerRepository(PowerModel(totalPower: powerBase, permanentPower: powerBase, temporaryPower: 0)),
        ),
        miningRepositoryProvider.overrideWithValue(_FakeMiningRepository()),
      ],
      child: const MaterialApp(home: PixelSalaScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('SALA em 320dp: 2 owned (nv1 e nv3) + 18500 power renderiza sem overflow',
      (WidgetTester tester) async {
    await _pumpSala(
      tester,
      owned: const <MachineModel>[
        MachineModel(
          id: 'item-1',
          type: 'rig-scrap',
          level: 1,
          power: 250,
          active: true,
        ),
        MachineModel(
          id: 'item-2',
          type: 'rig-nova',
          level: 3,
          power: 3000,
          active: true,
        ),
      ],
      powerBase: 18500,
    );

    // Sem overflow em 320dp
    expect(tester.takeException(), isNull);

    // Textos exigidos
    expect(find.text('PODER TOTAL'), findsWidgets);
    expect(find.text('LOJA'), findsOneWidget);
    expect(find.text('SUA SALA'), findsOneWidget);
    expect(find.text('RIG SCRAP'), findsOneWidget);
    expect(find.text('RIG NOVA'), findsOneWidget);
    expect(find.text('APRIMORAR'), findsWidgets);
    expect(find.text('IR PARA LOJA'), findsWidgets);
  });

  testWidgets('SALA: tocar na máquina abre sheet de detalhes com PRÓXIMO NÍVEL',
      (WidgetTester tester) async {
    await _pumpSala(
      tester,
      owned: const <MachineModel>[
        MachineModel(
          id: 'item-1',
          type: 'rig-scrap',
          level: 1,
          power: 250,
          active: true,
        ),
      ],
    );

    expect(find.text('RIG SCRAP'), findsOneWidget);
    // Toca na card da máquina (fora do botão aprimorar)
    await tester.tap(find.text('RIG SCRAP'));
    await tester.pumpAndSettle();

    // Sheet de detalhes deve abrir com 'PRÓXIMO NÍVEL'
    expect(find.textContaining('PRÓXIMO NÍVEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SALA: chip NÍVEL MÁX para máquina no nível máximo',
      (WidgetTester tester) async {
    await _pumpSala(
      tester,
      owned: const <MachineModel>[
        MachineModel(
          id: 'item-1',
          type: 'rig-scrap',
          level: 5,
          power: 250,
          active: true,
        ),
      ],
    );

    expect(find.text('NÍVEL MÁX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
