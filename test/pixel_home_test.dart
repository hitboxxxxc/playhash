import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/core/widgets/next_block_countdown.dart';
import 'package:playhash/data/models/power_model.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/mining_repository.dart';
import 'package:playhash/data/repositories/power_repository.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/home/pixel_home_screen.dart';

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
  Stream<PowerModel?> watchPower(String uid) async* {
    yield power;
  }
}

class _FakeWalletRepository implements WalletRepositoryApi {
  _FakeWalletRepository(this.wallet);

  WalletModel? wallet;

  @override
  Future<WalletModel?> loadWallet(String uid) async => wallet;

  @override
  Stream<WalletModel?> watchWallet(String uid) async* {
    yield wallet;
  }
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

  @override
  Future<BlockSnapshot?> loadBlockSnapshot() async => block;

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
  }) {
    if (block == null) return null;
    // Para teste: 5 COIN = 5 * 1.000.000 unidades mínimas
    return RewardEstimate(
      share: yourPower / (yourPower * 2),
      estimatedRewardMinimalUnits: BigInt.from(5000000),
    );
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _FakeAuthService auth,
  required _FakePowerRepository powerRepo,
  required _FakeWalletRepository walletRepo,
  required _FakeMiningRepository miningRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        powerRepositoryProvider.overrideWithValue(powerRepo),
        walletRepositoryProvider.overrideWithValue(walletRepo),
        miningRepositoryProvider.overrideWithValue(miningRepo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PixelHomeScreen(onPlayGames: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'PixelHomeScreen em 320dp: sem overflow; chip "PODER DE MINERAÇÃO TOTAL" '
      'com texto completo; countdown "Próxima recompensa em mm:ss" presente',
      (WidgetTester tester) async {
    final BlockSnapshot block = BlockSnapshot(
      nextBlockAt: DateTime.now().add(const Duration(minutes: 5)),
      totalBlockRewardMinimalUnits: BigInt.from(10000000),
      networkPower: 2000000,
    );

    await _pumpHome(
      tester,
      auth: _FakeAuthService(user: _FakeUser()),
      powerRepo: _FakePowerRepository(
        const PowerModel(
          permanentPower: 1500000,
          temporaryPower: 0,
          totalPower: 1500000, // 1,50 MH/s
        ),
      ),
      walletRepo: _FakeWalletRepository(
        // saldo=1.250.000.000 unidades mínimas = 1.250 COIN (do prompt).
        WalletModel(
          internalBalance: BigInt.from(1250000000),
          availableBalance: BigInt.from(1250000000),
          pendingBalance: BigInt.zero,
          lifetimeEarned: BigInt.from(1250000000),
        ),
      ),
      miningRepo: _FakeMiningRepository(block),
    );

    // 1) Sem "RenderFlex overflowed" no log de erros.
    expect(tester.takeException(), isNull);

    // 2) Chip "PODER DE MINERAÇÃO TOTAL" — texto INTEIRO visível (sem truncar).
    expect(find.text('PODER DE MINERAÇÃO TOTAL'), findsOneWidget);

    // 3) bigValue do PODER ATUAL: 1,50 (formato PowerFormat sem unidade).
    expect(find.text('1,50'), findsOneWidget);
    // 4) Unidade MH/s no label roxo.
    expect(find.text('MH/s'), findsOneWidget);

    // 5) Chip dourado da recompensa estimada: 5 COIN (fake do estimateReward).
    expect(find.text('5 COIN'), findsOneWidget);

    // 6) Countdown "Próxima recompensa em mm:ss" presente (NEXT widget).
    expect(find.byType(NextBlockCountdown), findsOneWidget);
    final Finder countdownLine = find.byWidgetPredicate(
      (Widget w) =>
          w is Text &&
          RegExp(r'^Próxima recompensa em \d{2}:\d{2}$').hasMatch(w.data ?? ''),
    );
    expect(countdownLine, findsOneWidget);
  });
}
