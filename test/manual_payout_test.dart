import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/config/payout_config.dart' show kFeeCoins;
import 'package:playhash/core/services/payout/manual_provider.dart';
import 'package:playhash/core/services/payout/payout_provider.dart';
import 'package:playhash/core/services/withdrawal_service.dart';

// ---- FAKES -------------------------------------------------------------------

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

/// Provider controlável: devolve o resultado programado (pending p/ manual).
class FakeProvider implements PayoutProvider {
  FakeProvider(this.result);

  PayoutResult result;

  @override
  Future<PayoutResult> sendPayout({
    required String destination,
    required int amountLitoshi,
  }) async =>
      result;
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

void main() {
  group('ManualProvider (mesma interface PayoutProvider)', () {
    test('sendPayout ⇒ PENDING (handoff do operador; sem rede)', () async {
      final PayoutResult result =
          await ManualProvider().sendPayout(destination: 'a@b.com', amountLitoshi: 800);
      expect(result.isPending, isTrue);
      expect(result.success, isFalse);
      expect(result.errorCode, isNull);
    });

    test('amount <= 0 ⇒ INVALID_AMOUNT', () async {
      final PayoutResult result =
          await ManualProvider().sendPayout(destination: 'a@b.com', amountLitoshi: 0);
      expect(result.errorCode, PayoutErrorCodes.invalidAmount);
    });
  });

  group('WithdrawalService em MODO MANUAL (provider pending)', () {
    test('reserva + doc withdrawals/{id} status=pending; SEM conclusão',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeRecords records = FakeRecords();
      final WithdrawalService service = WithdrawalService(
        provider: FakeProvider(const PayoutResult.pending()),
        ledger: ledger,
        records: records,
      );

      final WithdrawalOutcome outcome = await service.withdraw(
        uid: 'u1',
        amountCoins: 10,
        destination: 'owner@example.com',
        clientRequestId: 'req-manual-1',
      );

      expect(outcome.isPending, isTrue);
      // RESERVA: available −= X, pending += X (soma constante).
      expect(ledger.available, BigInt.from(40) * coin);
      expect(ledger.pending, BigInt.from(10) * coin);
      expect(ledger.total, BigInt.from(50) * coin);
      // Doc pendente com os campos da espec.
      final Map<String, dynamic> doc = records.docs['req-manual-1']!;
      expect(doc['status'], 'pending');
      expect(doc['uid'], 'u1');
      expect(doc['asset'], 'LTC');
      expect(doc['amountCoins'], 10);
      expect(doc['feeCoins'], kFeeCoins);
      expect(doc['litoshi'], 800);
      expect(doc['destinationMasked'], 'ow***@example.com');
    });

    test('IDEMPOTÊNCIA manual: mesmo id não regrava nem re-reserva',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(50) * coin);
      final FakeRecords records = FakeRecords();
      final WithdrawalService service = WithdrawalService(
        provider: FakeProvider(const PayoutResult.pending()),
        ledger: ledger,
        records: records,
      );
      await service.withdraw(
        uid: 'u1',
        amountCoins: 5,
        destination: 'owner@example.com',
        clientRequestId: 'req-dup-m',
      );
      await service.withdraw(
        uid: 'u1',
        amountCoins: 5,
        destination: 'owner@example.com',
        clientRequestId: 'req-dup-m',
      );
      expect(ledger.available, BigInt.from(45) * coin);
      expect(ledger.pending, BigInt.from(5) * coin);
    });
  });

  group('manualSettlementFor (transição observada pelo operador)', () {
    test('somente pending→terminal liquida', () {
      expect(
        manualSettlementFor(previousStatus: null, currentStatus: 'completed'),
        ManualSettlement.none,
      );
      expect(
        manualSettlementFor(previousStatus: null, currentStatus: 'failed'),
        ManualSettlement.none,
      );
      expect(
        manualSettlementFor(previousStatus: 'pending', currentStatus: 'pending'),
        ManualSettlement.none,
      );
      expect(
        manualSettlementFor(
            previousStatus: 'pending', currentStatus: 'completed'),
        ManualSettlement.conclude,
      );
      expect(
        manualSettlementFor(previousStatus: 'pending', currentStatus: 'failed'),
        ManualSettlement.refund,
      );
      expect(
        manualSettlementFor(
            previousStatus: 'completed', currentStatus: 'failed'),
        ManualSettlement.none,
      );
    });

    test('soma NUNCA crescente na sequência completa do modo manual',
        () async {
      final FakeLedger ledger = FakeLedger(available: BigInt.from(30) * coin);
      final BigInt initialTotal = ledger.total;
      final FakeRecords records = FakeRecords();
      final WithdrawalService service = WithdrawalService(
        provider: FakeProvider(const PayoutResult.pending()),
        ledger: ledger,
        records: records,
      );

      // (a) saque → reserva (soma constante).
      await service.withdraw(
        uid: 'u1',
        amountCoins: 6,
        destination: 'a@example.com',
        clientRequestId: 'm-1',
      );
      expect(ledger.total, initialTotal);

      // (b) operador define 'failed' ⇒ estorno integral (soma constante).
      await ledger.refund(uid: 'u1', amountUnits: BigInt.from(6) * coin);
      expect(ledger.available, initialTotal);
      expect(ledger.pending, BigInt.zero);
      expect(ledger.total, initialTotal);

      // (c) novo saque → reserva.
      await service.withdraw(
        uid: 'u1',
        amountCoins: 4,
        destination: 'a@example.com',
        clientRequestId: 'm-2',
      );
      expect(ledger.total, initialTotal);

      // (d) operador paga e define 'completed' ⇒ total DIMINUI.
      await ledger.conclude(uid: 'u1', amountUnits: BigInt.from(4) * coin);
      expect(ledger.pending, BigInt.zero);
      expect(ledger.total, initialTotal - (BigInt.from(4) * coin));
      expect(ledger.total <= initialTotal, isTrue);
    });
  });
}
