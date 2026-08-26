import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/data/models/power_model.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/economy_repository.dart';
import 'package:playhash/data/repositories/machines_repository.dart';
import 'package:playhash/core/widgets/next_block_countdown.dart';
import 'package:playhash/data/repositories/mining_repository.dart';
import 'package:playhash/data/repositories/power_repository.dart';
import 'package:playhash/data/repositories/profile_repository.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/home/home_screen.dart';

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

class _FakeProfileRepository implements ProfileRepositoryApi {
  _FakeProfileRepository(this.doc);

  Map<String, dynamic>? doc;

  @override
  Future<Map<String, dynamic>?> loadOwnProfile(String uid) async => doc;

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String uid) =>
      Stream<Map<String, dynamic>?>.value(doc);

  @override
  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> prefs,
  ) async {}
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
  final StreamController<List<MachineModel>> _controller =
      StreamController<List<MachineModel>>.broadcast();

  /// Simula o runner aprovando uma compra: novo item entra na stream.
  void emit(List<MachineModel> value) {
    machines = value;
    _controller.add(value);
  }

  @override
  Future<List<MachineModel>> loadMachines(String uid) async => machines;

  @override
  Stream<List<MachineModel>> watchMachines(String uid) => _controller.stream;
}

class _FakeEconomyRepository implements EconomyRepositoryApi {
  _FakeEconomyRepository(this.machineSlots);

  int? machineSlots;

  @override
  Future<int?> loadMachineSlots() async => machineSlots;
}

class _FakeMiningRepository implements MiningRepositoryApi {
  _FakeMiningRepository([BlockSnapshot? block])
      : _controller = StreamController<BlockSnapshot?>.broadcast() {
    if (block != null) {
      this.block = block;
      _controller.add(block);
    }
  }

  BlockSnapshot? block;
  final StreamController<BlockSnapshot?> _controller;

  /// Simula o runner regravando `blocks/current` (bloco fechado).
  void emit(BlockSnapshot? value) {
    block = value;
    _controller.add(value);
  }

  @override
  Future<BlockSnapshot?> loadBlockSnapshot() async => block;

  /// Replay do valor atual + updates (broadcast perde eventos sem listener).
  @override
  Stream<BlockSnapshot?> watchBlockSnapshot() async* {
    yield block;
    yield* _controller.stream;
  }

  @override
  Future<List<RewardEntry>> loadRewardHistory(String uid) async =>
      const <RewardEntry>[];

  @override
  Future<Map<String, dynamic>?> loadUserLeague(String uid) async => null;

  @override
  RewardEstimate? estimateReward({
    required int yourPower,
    BlockSnapshot? block,
  }) =>
      null;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _FakeAuthService auth,
  required _FakeProfileRepository profileRepo,
  required _FakeWalletRepository walletRepo,
  required _FakePowerRepository powerRepo,
  required _FakeMachinesRepository machinesRepo,
  _FakeEconomyRepository? economyRepo,
  _FakeMiningRepository? miningRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profileRepo),
        walletRepositoryProvider.overrideWithValue(walletRepo),
        powerRepositoryProvider.overrideWithValue(powerRepo),
        machinesRepositoryProvider.overrideWithValue(machinesRepo),
        economyRepositoryProvider
            .overrideWithValue(economyRepo ?? _FakeEconomyRepository(10)),
        miningRepositoryProvider
            .overrideWithValue(miningRepo ?? _FakeMiningRepository(null)),
      ],
      child: const MaterialApp(home: HomeScreen()),
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
  testWidgets('HOME sem dados: header vazio, "—" no saldo/poder e 10 slots travados',
      (WidgetTester tester) async {
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(null),
      walletRepo: _FakeWalletRepository(null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    // Header sem perfil => "JOGADOR", nível indisponível.
    expect(find.text('JOGADOR'), findsOneWidget);
    expect(find.text('NÍVEL —'), findsOneWidget);

    // Saldo sem carteira => "—".
    expect(find.text('—'), findsWidgets);

    // Card de poder estrutural.
    expect(find.text('MEU PODER'), findsOneWidget);
    expect(find.text('Multiplicador: —'), findsOneWidget);
    // Sem schedule do backend => traços (nunca horário inventado).
    expect(find.textContaining('Próxima recompensa em --:--'), findsOneWidget);

    // Sala de máquinas: 2 prateleiras × 5 slots, todos VAZIOS ("+")
    // (machineSlots = 10; nada travado).
    expect(_emptySlots, findsNWidgets(10));
    expect(_lockedSlots, findsNothing);
    expect(find.text('EDITAR SALA'), findsOneWidget);
    expect(find.text('ORGANIZAR'), findsOneWidget);

    // Stats rápidos.
    expect(find.text('PODER DAS MÁQUINAS'), findsOneWidget);
    expect(find.text('PODER DOS JOGOS'), findsOneWidget);
    expect(find.text('PRÓXIMA RECOMPENSA'), findsOneWidget);
    expect(find.text('RANKING GLOBAL'), findsOneWidget);
  });

  testWidgets('HOME com dados oficiais: nome, saldo e poder formatados',
      (WidgetTester tester) async {
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(<String, dynamic>{
        'displayName': 'MinerX7',
      }),
      walletRepo: _FakeWalletRepository(
        WalletModel(
          internalBalance: BigInt.from(12458750000),
          availableBalance: BigInt.from(12458750000), // 12.458,75 COIN
          pendingBalance: BigInt.zero,
          lifetimeEarned: BigInt.from(12458750000),
        ),
      ),
      powerRepo: _FakePowerRepository(
        const PowerModel(
          permanentPower: 897461000000000000,
          temporaryPower: 0,
          totalPower: 897461000000000000, // 897,46 PH/s
        ),
      ),
      machinesRepo: _FakeMachinesRepository(<MachineModel>[
        const MachineModel(
          id: 'm1',
          type: 'rig',
          level: 12,
          power: 650000000000000000,
          active: true,
          metadata: <String, dynamic>{'rarity': 'epic'},
        ),
      ]),
    );

    expect(find.text('MinerX7'), findsOneWidget);
    expect(find.text('12.458,75 COIN'), findsOneWidget);
    expect(find.text('897,46 PH/s'), findsOneWidget);
    expect(find.text('LV.12'), findsOneWidget);

    // 1 máquina => 9 slots vazios, nenhum travado.
    expect(_emptySlots, findsNWidgets(9));
    expect(_lockedSlots, findsNothing);
  });

  testWidgets('HOME: countdown "Próxima recompensa em" usa o MESMO widget '
      'compartilhado da MINERAÇÃO e refresca com o schedule do backend',
      (WidgetTester tester) async {
    final _FakeMiningRepository miningRepo = _FakeMiningRepository(
      BlockSnapshot(nextBlockAt: DateTime.now().add(const Duration(minutes: 5))),
    );
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(null),
      walletRepo: _FakeWalletRepository(null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
      miningRepo: miningRepo,
    );

    // Com schedule oficial: mm:ss visível (nada de "--:--"/"—").
    final Finder countdownLine = find.byWidgetPredicate(
      (Widget w) =>
          w is Text &&
          RegExp(r'^Próxima recompensa em \d{2}:\d{2}$').hasMatch(w.data ?? ''),
    );
    expect(countdownLine, findsOneWidget);
    expect(find.byType(NextBlockCountdown), findsOneWidget);

    // Runner regrava `blocks/current` => rótulo refresca SEM recarregar.
    miningRepo.emit(
      BlockSnapshot(nextBlockAt: DateTime.now().add(const Duration(minutes: 4))),
    );
    await tester.pumpAndSettle();

    final String before = tester.widget<Text>(countdownLine).data!;
    expect(before, startsWith('Próxima recompensa em 0'));
  });

  testWidgets('HOME: máquina nova na stream da sala exibe toast '
      '"Máquina instalada na sala" e atualiza os slots',
      (WidgetTester tester) async {
    final _FakeMachinesRepository machinesRepo =
        _FakeMachinesRepository(const <MachineModel>[]);
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(null),
      walletRepo: _FakeWalletRepository(null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: machinesRepo,
    );

    expect(_emptySlots, findsNWidgets(10));

    // Runner aprova a compra => item entra em machines/{uid}/items.
    machinesRepo.emit(const <MachineModel>[
      MachineModel(
        id: 'item-1',
        type: 'rig-scrap',
        level: 1,
        power: 10,
        active: true,
        metadata: <String, dynamic>{'rarity': 'common'},
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Máquina instalada na sala'), findsOneWidget);
    expect(find.text('LV.1'), findsOneWidget);
    expect(_emptySlots, findsNWidgets(9));
  });

  testWidgets('HOME: botão "+" abre bottom sheet informativo "EM BREVE"',
      (WidgetTester tester) async {
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(null),
      walletRepo: _FakeWalletRepository(null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    // O "+" do header (slots vazios da sala também usam "+").
    await tester.tap(find.byTooltip('Adicionar saldo (em breve)'));
    await tester.pumpAndSettle();

    expect(find.text('EM BREVE'), findsOneWidget);
    expect(find.textContaining('disponível em uma próxima atualização'),
        findsOneWidget);
  });

  testWidgets('HOME: "EDITAR SALA" abre informativo "EM BREVE"',
      (WidgetTester tester) async {
    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      profileRepo: _FakeProfileRepository(null),
      walletRepo: _FakeWalletRepository(null),
      powerRepo: _FakePowerRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    await tester.scrollUntilVisible(
      find.text('EDITAR SALA'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('EDITAR SALA'));
    await tester.pumpAndSettle();

    expect(find.text('EM BREVE'), findsOneWidget);
  });
}
