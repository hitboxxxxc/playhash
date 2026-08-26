import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/core/widgets/machine_sprite.dart';
import 'package:playhash/data/models/machine_catalog_model.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/machine_catalog_repository.dart';
import 'package:playhash/data/repositories/machines_repository.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/store/store_screen.dart';

/// Fake de [User] — apenas uid importa.
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

/// Catálogo fake (espelho de config/machines) — preços/poder SEMPRE do
/// "backend" (nada decidido no cliente).
final List<MachineCatalogModel> kFakeCatalog = <MachineCatalogModel>[
  MachineCatalogModel(
    id: 'rig-scrap',
    name: 'RIG SCRAP',
    rarity: 'common',
    powerUnits: 10,
    priceUnits: BigInt.from(400000000),
    maxPerUser: 5,
    enabled: true,
  ),
  MachineCatalogModel(
    id: 'rig-nova',
    name: 'RIG NOVA',
    rarity: 'legendary',
    powerUnits: 500,
    priceUnits: BigInt.from(15000000000),
    maxPerUser: 1,
    enabled: true,
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

Future<void> _pumpStore(
  WidgetTester tester, {
  required _FakeCatalogRepository catalogRepo,
  required _FakeWalletRepository walletRepo,
  required _FakeMachinesRepository machinesRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(
          _FakeAuthService(user: _FakeUser()),
        ),
        machineCatalogRepositoryProvider.overrideWithValue(catalogRepo),
        walletRepositoryProvider.overrideWithValue(walletRepo),
        machinesRepositoryProvider.overrideWithValue(machinesRepo),
      ],
      child: const MaterialApp(home: StoreScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('LOJA renderiza catálogo da config fake com sprites e preços',
      (WidgetTester tester) async {
    await _pumpStore(
      tester,
      catalogRepo: _FakeCatalogRepository(kFakeCatalog),
      walletRepo: _FakeWalletRepository(
        WalletModel(
          internalBalance: BigInt.from(1000000000),
          availableBalance: BigInt.from(1000000000), // 1.000 coins
          pendingBalance: BigInt.zero,
          lifetimeEarned: BigInt.from(1000000000),
        ),
      ),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    // Saldo formatado no header.
    expect(find.text('1.000'), findsOneWidget);
    expect(find.text('COIN'), findsOneWidget);

    // Catálogo: nomes, poder e preços vindos da config.
    expect(find.text('RIG SCRAP'), findsOneWidget);
    expect(find.text('RIG NOVA'), findsOneWidget);
    expect(find.text('+10,00 H/s'), findsOneWidget);
    expect(find.text('+500,00 H/s'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(find.text('15.000'), findsOneWidget);

    // Sprites pixel-art próprios (CustomPainter), um por card.
    expect(
      find.byWidgetPredicate((Widget w) => w is MachineSprite),
      findsNWidgets(2),
    );

    // Chips de raridade.
    expect(find.text('COMUM'), findsOneWidget);
    expect(find.text('LENDÁRIO'), findsOneWidget);

    // "x/max" compacto (sem a palavra "owned" — nada truncado).
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
  });

  testWidgets('LOJA em tela estreita (320dp): cards sem overflow',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            _FakeAuthService(user: _FakeUser()),
          ),
          machineCatalogRepositoryProvider
              .overrideWithValue(_FakeCatalogRepository(kFakeCatalog)),
          walletRepositoryProvider.overrideWithValue(
            _FakeWalletRepository(null), // aviso "Saldo insuficiente" visível
          ),
          machinesRepositoryProvider
              .overrideWithValue(_FakeMachinesRepository(const [])),
        ],
        child: const MaterialApp(home: StoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Nenhum erro de layout (BOTTOM OVERFLOWED) nos tiles.
    expect(tester.takeException(), isNull);
    expect(find.text('COMPRAR'), findsNWidgets(2));
    expect(find.text('Saldo insuficiente'), findsNWidgets(2));
  });

  testWidgets('LOJA: saldo insuficiente desabilita COMPRAR sem esconder preço',
      (WidgetTester tester) async {
    await _pumpStore(
      tester,
      catalogRepo: _FakeCatalogRepository(kFakeCatalog),
      walletRepo: _FakeWalletRepository(
        WalletModel(
          internalBalance: BigInt.from(100000000),
          availableBalance: BigInt.from(100000000), // 100 coins
          pendingBalance: BigInt.zero,
          lifetimeEarned: BigInt.from(100000000),
        ),
      ),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    // Preço continua visível.
    expect(find.text('400'), findsOneWidget);
    // Aviso discreto.
    expect(find.text('Saldo insuficiente'), findsNWidgets(2));
    // Botões COMPRAR desabilitados.
    final Finder buyButtons = find.ancestor(
      of: find.text('COMPRAR'),
      matching: find.byType(TextButton),
    );
    expect(buyButtons, findsNWidgets(2));
    final TextButton disabled = tester.widget<TextButton>(buyButtons.first);
    expect(disabled.onPressed, isNull);
  });

  testWidgets('LOJA: limite atingido desabilita COMPRAR',
      (WidgetTester tester) async {
    await _pumpStore(
      tester,
      catalogRepo: _FakeCatalogRepository(kFakeCatalog),
      walletRepo: _FakeWalletRepository(
        WalletModel(
          internalBalance: BigInt.from(100000000000),
          availableBalance: BigInt.from(100000000000), // 100.000 coins
          pendingBalance: BigInt.zero,
          lifetimeEarned: BigInt.from(100000000000),
        ),
      ),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[
        MachineModel(
          id: 'i1',
          type: 'rig-nova',
          level: 1,
          power: 500,
          active: true,
          metadata: <String, dynamic>{'rarity': 'legendary'},
        ),
      ]),
    );

    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('Limite atingido'), findsOneWidget);
    // RIG SCRAP continua comprável (saldo suficiente, sem limite atingido).
    final Finder buyButtons = find.ancestor(
      of: find.text('COMPRAR'),
      matching: find.byType(TextButton),
    );
    final List<TextButton> buttons =
        tester.widgetList<TextButton>(buyButtons).toList();
    expect(buttons.any((TextButton b) => b.onPressed != null), isTrue);
  });

  testWidgets('LOJA: categorias EM BREVE exibem conteúdo vazio informativo',
      (WidgetTester tester) async {
    await _pumpStore(
      tester,
      catalogRepo: _FakeCatalogRepository(kFakeCatalog),
      walletRepo: _FakeWalletRepository(null),
      machinesRepo: _FakeMachinesRepository(const <MachineModel>[]),
    );

    await tester.tap(find.text('BOOSTERS'));
    await tester.pumpAndSettle();

    expect(find.text('BOOSTERS EM BREVE'), findsOneWidget);
    expect(
      find.textContaining('será publicada pelo servidor'),
      findsOneWidget,
    );
  });
}
