import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/providers.dart';
import 'package:playhash/core/services/auth_service.dart';
import 'package:playhash/core/services/purchase_intent_service.dart';
import 'package:playhash/data/models/machine_catalog_model.dart';
import 'package:playhash/data/models/machine_model.dart';
import 'package:playhash/data/models/wallet_model.dart';
import 'package:playhash/data/repositories/machine_catalog_repository.dart';
import 'package:playhash/data/repositories/machines_repository.dart';
import 'package:playhash/data/repositories/wallet_repository.dart';
import 'package:playhash/features/store/store_screen.dart';

/// FLUXO DE COMPRA PONTO A PONTO (cliente): card → sheet → CONFIRMAR COMPRA
/// → intent criada (purchaseIntents/{clientRequestId}) → runner aprova
/// (stream done) → toast + refresh. A validação econômica é 100% backend;
/// aqui provamos apenas o contrato do cliente.

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
    powerUnits: 10,
    priceUnits: BigInt.from(400000000),
    maxPerUser: 5,
    enabled: true,
  ),
];

class _FakeCatalogRepository implements MachineCatalogRepositoryApi {
  @override
  Future<List<MachineCatalogModel>> loadCatalog() async => kFakeCatalog;
}

class _FakeWalletRepository implements WalletRepositoryApi {
  @override
  Future<WalletModel?> loadWallet(String uid) async => WalletModel(
        internalBalance: BigInt.from(1000000000),
        availableBalance: BigInt.from(1000000000), // 1.000 COIN ≥ 400
        pendingBalance: BigInt.zero,
        lifetimeEarned: BigInt.from(1000000000),
      );

  @override
  Stream<WalletModel?> watchWallet(String uid) =>
      const Stream<WalletModel?>.empty();
}

class _FakeMachinesRepository implements MachinesRepositoryApi {
  @override
  Future<List<MachineModel>> loadMachines(String uid) async =>
      const <MachineModel>[];

  @override
  Stream<List<MachineModel>> watchMachines(String uid) =>
      const Stream<List<MachineModel>>.empty();
}

/// Captura a intent criada e aprova na hora (runner "instantâneo").
class _FakeIntentsRepository implements PurchaseIntentsRepositoryApi {
  String? createdUid;
  String? createdMachineId;
  String? createdClientRequestId;
  int createCalls = 0;

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  }) async {
    createCalls++;
    createdUid = uid;
    createdMachineId = machineId;
    createdClientRequestId = clientRequestId;
  }

  @override
  Future<PurchaseIntentResult?> readIntent(String clientRequestId) async =>
      null;

  @override
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId) =>
      Stream<PurchaseIntentResult>.value(
        const PurchaseIntentResult(status: 'done', machineItemId: 'item-1'),
      );
}

void main() {
  testWidgets('COMPRA fim a fim: intent criada com uid/machineId/'
      'clientRequestId; done => toast de instalação',
      (WidgetTester tester) async {
    final _FakeIntentsRepository intentsRepo = _FakeIntentsRepository();
    final PurchaseIntentService service =
        PurchaseIntentService(repository: intentsRepo);

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          machineCatalogRepositoryProvider
              .overrideWithValue(_FakeCatalogRepository()),
          walletRepositoryProvider.overrideWithValue(_FakeWalletRepository()),
          machinesRepositoryProvider
              .overrideWithValue(_FakeMachinesRepository()),
          purchaseIntentServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: StoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1) Card → COMPRAR abre o sheet de detalhes.
    await tester.tap(find.text('COMPRAR'));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRMAR COMPRA'), findsOneWidget);

    // 2) CONFIRMAR COMPRA cria a intent e observa o resultado.
    await tester.tap(find.text('CONFIRMAR COMPRA'));
    await tester.pumpAndSettle();

    // Intent criada EXATAMENTE uma vez (idempotente por clientRequestId).
    expect(intentsRepo.createCalls, 1);
    expect(intentsRepo.createdUid, 'uid-1');
    expect(intentsRepo.createdMachineId, 'rig-scrap');
    // clientRequestId v4 (36 chars) — usado como DOC ID.
    expect(intentsRepo.createdClientRequestId!.length, 36);

    // 3) Runner aprovou (done) => fase de sucesso no sheet...
    expect(find.text('COMPRA APROVADA'), findsOneWidget);
    expect(find.text('Sua máquina foi instalada na sala.'), findsOneWidget);

    // ...e toast/refresh na LOJA (onPurchased).
    expect(find.textContaining('Compra aprovada'), findsOneWidget);
  });

  testWidgets('COMPRA falhada (INSUFFICIENT_BALANCE do runner): mensagem '
      'segura por failureCode', (WidgetTester tester) async {
    final _FakeIntentsRepository intentsRepo = _FailedIntentsRepository();
    final PurchaseIntentService service =
        PurchaseIntentService(repository: intentsRepo);

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          machineCatalogRepositoryProvider
              .overrideWithValue(_FakeCatalogRepository()),
          walletRepositoryProvider.overrideWithValue(_FakeWalletRepository()),
          machinesRepositoryProvider
              .overrideWithValue(_FakeMachinesRepository()),
          purchaseIntentServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: StoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('COMPRAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRMAR COMPRA'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saldo insuficiente'), findsOneWidget);
    expect(find.text('COMPRA APROVADA'), findsNothing);
  });
}

class _FailedIntentsRepository extends _FakeIntentsRepository {
  @override
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId) =>
      Stream<PurchaseIntentResult>.value(
        const PurchaseIntentResult(
          status: 'failed',
          failureCode: 'INSUFFICIENT_BALANCE',
        ),
      );
}
