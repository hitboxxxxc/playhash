import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/data/models/power_model.dart';
import 'package:playhash/data/repositories/machines_repository.dart';
import 'package:playhash/data/repositories/mining_repository.dart';
import 'package:playhash/data/repositories/power_repository.dart';
import 'package:playhash/features/mining/mining_screen.dart';

/// Fake de [User] — apenas uid importa para os repositórios.
class _FakeUser implements User {
  @override
  String get uid => 'uid-1';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuthService implements AuthServiceApi {
  _FakeAuthService({this.user});

  User? user;

  @override
  Future<User?> currentUser() async => user;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

class _FakeMachinesRepository implements MachinesRepositoryApi {
  _FakeMachinesRepository(this.machines);

  List<MachineModel> machines;

  @override
  Future<List<MachineModel>> loadMachines(String uid) async => machines;

  @override
  Stream<List<MachineModel>> watchMachines(String uid) =>
      Stream<List<MachineModel>>.value(machines);
}

class _FakeMiningRepository implements MiningRepositoryApi {
  _FakeMiningRepository({this.history = const <RewardEntry>[]});

  BlockSnapshot? block;
  List<RewardEntry> history;
  Map<String, dynamic>? league;

  @override
  Future<BlockSnapshot?> loadBlockSnapshot() async => block;

  @override
  Stream<BlockSnapshot?> watchBlockSnapshot() =>
      Stream<BlockSnapshot?>.value(block);

  @override
  Future<List<RewardEntry>> loadRewardHistory(String uid) async => history;

  @override
  Future<Map<String, dynamic>?> loadUserLeague(String uid) async => league;

  @override
  RewardEstimate? estimateReward({
    required int yourPower,
    BlockSnapshot? block,
  }) {
    if (block == null) return null;
    final int? network = block.networkPower;
    final BigInt? reward = block.totalBlockRewardMinimalUnits;
    if (network == null || network <= 0 || yourPower <= 0 || reward == null) {
      return null;
    }
    return RewardEstimate(
      share: yourPower / network,
      estimatedRewardMinimalUnits: (reward * BigInt.from(yourPower)) ~/
          BigInt.from(network),
    );
  }
}

Future<void> _pumpMining(
  WidgetTester tester, {
  required _FakeAuthService auth,
  required _FakePowerRepository powerRepo,
  required _FakeMachinesRepository machinesRepo,
  required _FakeMiningRepository miningRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        powerRepositoryProvider.overrideWithValue(powerRepo),
        machinesRepositoryProvider.overrideWithValue(machinesRepo),
        miningRepositoryProvider.overrideWithValue(miningRepo),
      ],
      child: const MaterialApp(home: MiningScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MINERAÇÃO sem backend exibe estados vazios e "—" (nada inventado)',
      (WidgetTester tester) async {
    await _pumpMining(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
      miningRepo: _FakeMiningRepository(),
    );

    // Header de poder sem dado => "—".
    expect(find.text('MEU PODER'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    // Cards estruturais presentes.
    expect(find.text('PRÓXIMA LIGA'), findsOneWidget);
    expect(find.text('DISTRIBUIÇÃO DO PODER'), findsOneWidget);
    expect(find.text('RECOMPENSA'), findsOneWidget);
    expect(find.text('HISTÓRICO DE RECOMPENSAS'), findsOneWidget);

    // Empty states.
    expect(find.text('SEM PODER PARA DISTRIBUIR'), findsOneWidget);
    expect(find.text('NENHUMA RECOMPENSA AINDA'), findsOneWidget);

    // Disclaimer fixo.
    expect(
      find.textContaining('recompensas virtuais'),
      findsOneWidget,
    );
  });

  testWidgets('MINERAÇÃO com dados oficiais formata poder, distribuição e histórico',
      (WidgetTester tester) async {
    const int totalPower = 897461000000000000; // 897,461 PH/s
    const int machinesPower = 650000000000000000; // 650 PH/s
    final _FakeMiningRepository miningRepo = _FakeMiningRepository(
      history: <RewardEntry>[
        RewardEntry(
          id: 'r1',
          amountMinimalUnits: BigInt.from(170900), // 0,1709 COIN
        ),
      ],
    );

    await _pumpMining(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      powerRepo: _FakePowerRepository(
        const PowerModel(
          permanentPower: totalPower,
          temporaryPower: 0,
          totalPower: totalPower,
        ),
      ),
      machinesRepo: _FakeMachinesRepository(<MachineModel>[
        const MachineModel(
          id: 'm1',
          type: 'rig',
          level: 12,
          power: machinesPower,
          active: true,
        ),
      ]),
      miningRepo: miningRepo,
    );

    // Total formatado (pt-BR, 2 casas) — aparece no header e no painel.
    expect(find.text('897,46 PH/s'), findsWidgets);

    // Distribuição: máquinas 650 PH/s (72,4%) e jogos 247,461 PH/s (27,6%).
    expect(find.text('650,00 PH/s'), findsOneWidget);
    expect(find.text('247,46 PH/s'), findsOneWidget);
    expect(find.text('72,4%'), findsOneWidget);
    expect(find.text('27,6%'), findsOneWidget);

    // Histórico com valor oficial formatado.
    expect(find.text('+0,1709 COIN'), findsOneWidget);

    // Sem schedule de bloco => sem contagem inventada (tudo "—").
    expect(find.text('PRÓXIMO BLOCO'), findsOneWidget);
  });

  testWidgets('MINERAÇÃO sem sessão (uid null) não quebra e mostra vazio',
      (WidgetTester tester) async {
    await _pumpMining(
      tester,
      auth: _FakeAuthService(user: null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
      miningRepo: _FakeMiningRepository(),
    );

    expect(find.text('MEU PODER'), findsOneWidget);
    expect(find.text('NENHUMA RECOMPENSA AINDA'), findsOneWidget);
  });
}
