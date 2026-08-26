import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:playhash/core/config/payout_config.dart';
import 'package:playhash/core/services/payout/payout_provider.dart';
import 'package:playhash/core/services/withdrawal_service.dart';
import 'package:playhash/core/utils/coin_format.dart';
import 'package:playhash/features/wallet/widgets/wallet_history_list.dart';
import 'package:playhash/features/wallet/widgets/withdraw_confirm_sheet.dart';

// ---- FAKES -------------------------------------------------------------------

/// Ledger em memória com o MESMO contrato do FirestoreWalletLedger.
class FakeLedger implements WalletLedger {
  FakeLedger({BigInt? available}) : available = available ?? BigInt.zero;

  BigInt available;
  BigInt pending = BigInt.zero;
  final List<String> ops = <String>[];

  @override
  Future<bool> reserve({
    required String uid,
    required BigInt amountUnits,
  }) async {
    ops.add('reserve');
    if (available < amountUnits) return false;
    available -= amountUnits;
    pending += amountUnits;
    return true;
  }

  @override
  Future<void> conclude({
    required String uid,
    required BigInt amountUnits,
  }) async {
    ops.add('conclude');
    pending -= amountUnits;
  }

  @override
  Future<void> refund({
    required String uid,
    required BigInt amountUnits,
  }) async {
    ops.add('refund');
    pending -= amountUnits;
    available += amountUnits;
  }

  BigInt get total => available + pending;
}

class FakeProvider implements PayoutProvider {
  FakeProvider(this.result);

  PayoutResult result;
  int calls = 0;
  final List<int> litoshiSent = <int>[];
  final List<String> emailsSent = <String>[];

  @override
  Future<PayoutResult> sendPayout({
    required String destination,
    required int amountLitoshi,
  }) async {
    calls += 1;
    emailsSent.add(destination);
    litoshiSent.add(amountLitoshi);
    return result;
  }
}

class FakeRecords implements WithdrawalRecords {
  final Map<String, Map<String, dynamic>> docs =
      <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> findByClientRequestId(
    String clientRequestId,
  ) async =>
      docs[clientRequestId];

  @override
  Future<void> write({
    required String clientRequestId,
    required Map<String, dynamic> data,
  }) async {
    docs[clientRequestId] = data;
  }
}

final BigInt coin = BigInt.from(1000000);

WithdrawalService serviceWith({
  required FakeLedger ledger,
  required FakeProvider provider,
  required FakeRecords records,
}) =>
    WithdrawalService(
      provider: provider,
      ledger: ledger,
      records: records,
    );

class _Probe extends StatelessWidget {
  const _Probe({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
}

void main() {
  group('WithdrawalService — fluxo reserva → payout → conclusão/estorno', () {
    test('SUCESSO: débito integral, litoshi inteiro, histórico completed',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-987654'));
      final FakeRecords records = FakeRecords();
      final WithdrawalService service =
          serviceWith(ledger: ledger, provider: provider, records: records);

      final WithdrawalOutcome outcome = await service.withdraw(
        uid: 'u1',
        amountCoins: 10,
        destination: 'owner@example.com',
        clientRequestId: 'req-ok-1',
      );

      expect(outcome.isCompleted, isTrue);
      expect(outcome.reference, isNotNull);
      // Débito: total DIMINUIU exatamente 10 COIN; pending zerado.
      expect(ledger.available, BigInt.from(40) * coin);
      expect(ledger.pending, BigInt.zero);
      expect(ledger.total, BigInt.from(40) * coin);
      // Litoshi INTEIRO: (10 − 2) × 100 = 800 (nunca float).
      expect(provider.litoshiSent.single, 800);
      expect(provider.litoshiSent.single, isA<int>());
      // Registro completed com máscara de destino.
      final Map<String, dynamic> doc = records.docs['req-ok-1']!;
      expect(doc['status'], 'completed');
      expect(doc['asset'], 'LTC');
      expect(doc['amountCoins'], 10);
      expect(doc['feeCoins'], kFeeCoins);
      expect(doc['litoshi'], 800);
      expect(doc['destinationMasked'], 'ow***@example.com');
      expect(doc['providerReference'], 'FP-987654');
    });

    test('DESTINO DUPLO: endereço LTC vinculado ⇒ completed + máscara 4+4',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-555001'));
      final FakeRecords records = FakeRecords();
      final WithdrawalService service =
          serviceWith(ledger: ledger, provider: provider, records: records);

      const String ltcAddress = 'LTCMPogVJZPW8W4bC2eSFUdfnGGaPVS4JK';
      final WithdrawalOutcome outcome = await service.withdraw(
        uid: 'u1',
        amountCoins: 10,
        destination: ltcAddress,
        clientRequestId: 'req-ltc-1',
      );

      expect(outcome.isCompleted, isTrue);
      // Provider recebeu o endereço COMPLETO (só no corpo da requisição).
      expect(provider.emailsSent.single, ltcAddress);
      expect(provider.litoshiSent.single, 800);
      // Histórico com máscara de ENDEREÇO: 4 primeiros + … + 4 últimos.
      final Map<String, dynamic> doc = records.docs['req-ltc-1']!;
      expect(doc['status'], 'completed');
      expect(doc['destinationMasked'], 'LTCM…S4JK');
      expect(doc['destinationMasked'], isNot(contains(ltcAddress)));
    });

    test('DESTINO INVÁLIDO (nem e-mail nem LTC) ⇒ exceção, provider NUNCA '
        'chamado', () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-1'));
      final WithdrawalService service = serviceWith(
        ledger: ledger,
        provider: provider,
        records: FakeRecords(),
      );

      await expectLater(
        service.withdraw(
          uid: 'u1',
          amountCoins: 10,
          destination: 'destino-invalido',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      expect(provider.calls, 0);
      // NADA foi reservado.
      expect(ledger.available, BigInt.from(50) * coin);
      expect(ledger.pending, BigInt.zero);
    });

    test('FALHA: estorno INTEGRAL visível + histórico failed', () async {
      final BigInt initial = BigInt.from(50) * coin;
      final FakeLedger ledger = FakeLedger(available: initial);
      final FakeProvider provider = FakeProvider(
          const PayoutResult.failed(PayoutErrorCodes.emailNotFound));
      final FakeRecords records = FakeRecords();
      final WithdrawalService service =
          serviceWith(ledger: ledger, provider: provider, records: records);

      final WithdrawalOutcome outcome = await service.withdraw(
        uid: 'u1',
        amountCoins: 10,
        destination: 'ghost@example.com',
        clientRequestId: 'req-fail-1',
      );

      expect(outcome.isFailed, isTrue);
      expect(outcome.errorCode, PayoutErrorCodes.emailNotFound);
      // Saldo volta EXATAMENTE ao valor anterior.
      expect(ledger.available, initial);
      expect(ledger.pending, BigInt.zero);
      expect(ledger.total, initial); // soma NUNCA cresceu
      final Map<String, dynamic> doc = records.docs['req-fail-1']!;
      expect(doc['status'], 'failed');
      expect(doc['errorCode'], PayoutErrorCodes.emailNotFound);
      expect(doc['providerReference'], isNull);
    });

    test('SALDO_INSUFICIENTE: provider NUNCA é chamado', () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(2) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-1'));
      final WithdrawalService service = serviceWith(
        ledger: ledger,
        provider: provider,
        records: FakeRecords(),
      );

      await expectLater(
        service.withdraw(
          uid: 'u1',
          amountCoins: 3,
          destination: 'owner@example.com',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      expect(provider.calls, 0);
    });

    test('limites: abaixo do mínimo e acima do teto são rejeitados', () async {
      final FakeLedger ledger =
          FakeLedger(available: BigInt.from(200000) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-1'));
      final WithdrawalService service = serviceWith(
        ledger: ledger,
        provider: provider,
        records: FakeRecords(),
      );

      // Abaixo do mínimo (3 COIN).
      await expectLater(
        service.withdraw(
          uid: 'u1',
          amountCoins: kMinWithdrawCoins - 1,
          destination: 'owner@example.com',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      // Acima do teto (100.000 COIN).
      await expectLater(
        service.withdraw(
          uid: 'u1',
          amountCoins: kMaxPerWithdrawalCoins + 1,
          destination: 'owner@example.com',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      expect(provider.calls, 0);
    });

    test('IDEMPOTÊNCIA: mesmo clientRequestId nunca reenvia o payout',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-42'));
      final WithdrawalService service = serviceWith(
        ledger: ledger,
        provider: provider,
        records: FakeRecords(),
      );

      final WithdrawalOutcome first = await service.withdraw(
        uid: 'u1',
        amountCoins: 5,
        destination: 'owner@example.com',
        clientRequestId: 'req-dup',
      );
      final WithdrawalOutcome second = await service.withdraw(
        uid: 'u1',
        amountCoins: 5,
        destination: 'owner@example.com',
        clientRequestId: 'req-dup',
      );

      expect(provider.calls, 1); // UMA única chamada ao provedor
      expect(second.isCompleted, first.isCompleted);
      expect(ledger.available, BigInt.from(45) * coin); // débito único
    });

    test('INVARIANTE ANTI-INFLAÇÃO: sequência mista nunca aumenta a soma',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(30) * coin);
      final BigInt initialTotal = ledger.total;

      final FakeRecords records = FakeRecords();
      final WithdrawalService okService = serviceWith(
        ledger: ledger,
        provider: FakeProvider(const PayoutResult.completed('FP-ok')),
        records: records,
      );
      final WithdrawalService failService = serviceWith(
        ledger: ledger,
        provider: FakeProvider(
            const PayoutResult.failed(PayoutErrorCodes.providerError)),
        records: records,
      );

      await okService.withdraw(
          uid: 'u1', amountCoins: 4, destination: 'a@example.com');
      expect(ledger.total, lessThan(initialTotal));
      final BigInt afterFirst = ledger.total;

      await failService.withdraw(
          uid: 'u1', amountCoins: 6, destination: 'b@example.com');
      expect(ledger.total, afterFirst); // estorno mantém a soma

      await okService.withdraw(
          uid: 'u1', amountCoins: 3, destination: 'c@example.com');
      expect(ledger.total, lessThan(afterFirst));

      expect(ledger.available >= BigInt.zero, isTrue);
      expect(ledger.pending >= BigInt.zero, isTrue);
    });

    test('litoshi é SEMPRE inteiro para qualquer valor válido', () async {
      final FakeLedger ledger =
          FakeLedger(available: BigInt.from(500000) * coin);
      final FakeProvider provider =
          FakeProvider(const PayoutResult.completed('FP-int'));
      final WithdrawalService service = serviceWith(
        ledger: ledger,
        provider: provider,
        records: FakeRecords(),
      );

      for (final int coins in <int>[3, 7, 100, 12345, 100000]) {
        await service.withdraw(
          uid: 'u1',
          amountCoins: coins,
          destination: 'owner@example.com',
          clientRequestId: 'req-int-$coins',
        );
        final int expected = (coins - kFeeCoins) * kLitoshiPerCoin;
        expect(provider.litoshiSent.last, expected);
        expect(provider.litoshiSent.last.runtimeType, int);
      }
    });
  });

  group('WithdrawConfirmSheet (widget)', () {
    testWidgets('mostra e-mail mascarado, taxa, conversão e aviso '
        'FaucetPay — SEM cooldown', (WidgetTester tester) async {
      final ValueNotifier<int> coins = ValueNotifier<int>(10);
      addTearDown(coins.dispose);
      await tester.pumpWidget(_Probe(
        child: WithdrawConfirmSheet(
          assetId: 'LTC',
          destinationMasked: 'ow***@example.com',
          amountUnits: BigInt.from(10) * coin,
          feeUnits: BigInt.from(kFeeCoins) * coin,
          litoshiPerCoin: kLitoshiPerCoin,
          displayRate: kDisplayRate,
          minWithdrawUnits: BigInt.from(kMinWithdrawCoins) * coin,
          availableBalance: BigInt.from(50) * coin,
          amountCoins: coins,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('confirm_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('confirm_withdraw')),
        findsOneWidget,
      );
      expect(find.text('ow***@example.com'), findsOneWidget);
      expect(find.text('Taxa'), findsOneWidget);
      expect(find.textContaining('FaucetPay'), findsWidgets);
      // NUNCA mensagem de cooldown 24h.
      expect(find.textContaining('24h'), findsNothing);
      expect(find.textContaining('intervalo'), findsNothing);
      // "Você recebe" = (10−2)×100 = 800 litoshi = 0,000008 LTC.
      expect(find.text('0,000008 LTC'), findsOneWidget);
    });

    testWidgets('valor abaixo do mínimo ⇒ CONFIRMAR desabilitado',
        (WidgetTester tester) async {
      final ValueNotifier<int> coins = ValueNotifier<int>(2);
      addTearDown(coins.dispose);
      await tester.pumpWidget(_Probe(
        child: WithdrawConfirmSheet(
          assetId: 'LTC',
          destinationMasked: 'ow***@example.com',
          amountUnits: BigInt.from(2) * coin,
          feeUnits: BigInt.from(kFeeCoins) * coin,
          litoshiPerCoin: kLitoshiPerCoin,
          displayRate: kDisplayRate,
          minWithdrawUnits: BigInt.from(kMinWithdrawCoins) * coin,
          availableBalance: BigInt.from(50) * coin,
          amountCoins: coins,
        ),
      ));
      await tester.pumpAndSettle();

      final Finder confirm =
          find.byKey(const ValueKey<String>('confirm_withdraw'));
      expect(tester.widget<OutlinedButton>(confirm).onPressed, isNull);
    });
  });

  group('WalletHistoryList (widget)', () {
    testWidgets('exibe chips completed/failed + destino mascarado',
        (WidgetTester tester) async {
      await tester.pumpWidget(_Probe(
        child: WalletHistoryList(items: <WalletHistoryItem>[
          WalletHistoryItem(
            title: 'Saque LTC',
            amount: -BigInt.from(10) * coin,
            status: 'completed',
            destinationMasked: 'ow***@example.com',
          ),
          WalletHistoryItem(
            title: 'Saque LTC',
            amount: -BigInt.from(5) * coin,
            status: 'failed',
            destinationMasked: 'gh***@example.com',
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('CONCLUÍDO'), findsOneWidget);
      expect(find.text('FALHADO'), findsOneWidget);
      expect(find.text('ow***@example.com'), findsOneWidget);
      expect(find.text('gh***@example.com'), findsOneWidget);
      // Valores formatados como saída (negativos).
      expect(
        find.text('-${CoinFormat.formatMinimalUnits(BigInt.from(10) * coin)}'),
        findsOneWidget,
      );
    });
  });
}
