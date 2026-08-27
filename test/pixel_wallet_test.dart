import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/wallet/pixel_wallet_screen.dart';

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
  Stream<User?> authStateChanges() => Stream<User?>.value(_FakeUser());
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeWalletRepository implements WalletRepositoryApi {
  _FakeWalletRepository(this.wallet);
  final WalletModel? wallet;
  @override
  Future<WalletModel?> loadWallet(String uid) async => wallet;
  @override
  Stream<WalletModel?> watchWallet(String uid) =>
      Stream<WalletModel?>.value(wallet);
}

void main() {
  testWidgets('pixel wallet balance 1.92 and chips', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final WalletModel fakeWallet = WalletModel(
      internalBalance: BigInt.from(1929394),
      availableBalance: BigInt.from(1929394),
      pendingBalance: BigInt.zero,
      lifetimeEarned: BigInt.from(1929394),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          walletRepositoryProvider
              .overrideWithValue(_FakeWalletRepository(fakeWallet)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PixelWalletScreen()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1.92'), findsOneWidget);
    expect(find.textContaining('LTC'), findsWidgets);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('DOGE'), findsOneWidget);
    expect(find.text('DGB'), findsOneWidget);
    expect(find.text('POL'), findsOneWidget);

    expect(find.textContaining('PIX'), findsNothing);
    expect(find.textContaining('R\$'), findsNothing);

    await tester.tap(find.text('BTC'));
    await tester.pump();

    expect(find.text('BTC: Disponível em breve'), findsOneWidget);
  });
}
