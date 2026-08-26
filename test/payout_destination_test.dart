import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/services/payout/faucetpay_provider.dart';
import 'package:playhash/core/services/withdrawal_service.dart';

void main() {
  group('detectDestinationType (12.22 — destino duplo)', () {
    test('e-mails válidos ⇒ DestinationType.email', () {
      expect(detectDestinationType('owner@example.com'),
          DestinationType.email);
      expect(detectDestinationType('  a.b+tag@sub.dominio.com.br  '),
          DestinationType.email);
    });

    test('endereço LTC legado (L/M Base58) ⇒ DestinationType.ltcAddress',
        () {
      expect(detectDestinationType('LTCMPogVJZPW8W4bC2eSFUdfnGGaPVS4JK'),
          DestinationType.ltcAddress);
      expect(detectDestinationType('M9vFRMBbKUVqPKUWVusBcV7y34sZFEWDq5'),
          DestinationType.ltcAddress);
    });

    test('endereço LTC bech32 (ltc1…) ⇒ DestinationType.ltcAddress', () {
      expect(detectDestinationType('ltc1qkzm9fvbhhqymjc vju7zt3xwdpp'.replaceAll(' ', '')),
          DestinationType.ltcAddress);
      expect(detectDestinationType('ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7k'),
          DestinationType.ltcAddress);
    });

    test('formatos inválidos ⇒ null', () {
      expect(detectDestinationType('destino-invalido'), isNull);
      expect(detectDestinationType('owner@example'), isNull); // sem TLD
      expect(
          detectDestinationType('bc1qxyw3unconstrained'), isNull); // BTC
      expect(
          detectDestinationType('LTCMPogVJZPW8W4bC2eSFUdfnGGaPVS4J0'), // '0'
          isNull); // 0 não está no alfabeto Base58
      expect(detectDestinationType(''), isNull);
      expect(detectDestinationType('ltc1UPPERCASE'), isNull);
    });
  });

  group('maskDestination (máscaras seguras)', () {
    test('e-mail ⇒ 2 primeiros + ***@ + domínio', () {
      expect(maskDestination('owner@example.com'), 'ow***@example.com');
    });

    test('endereço LTC ⇒ 4 primeiros + … + 4 últimos', () {
      const String addr = 'LTCMPogVJZPW8W4bC2eSFUdfnGGaPVS4JK';
      final String masked = maskDestination(addr);
      expect(masked, 'LTCM…S4JK');
      expect(masked.contains(addr), isFalse);
    });
  });

  group('withdrawalErrorMessage (mensagens seguras)', () {
    test('DESTINO_NAO_VINCULADO/EMAIL_NOT_FOUND ⇒ mensagem dupla (12.22)',
        () {
      final String msg = withdrawalErrorMessage('DESTINO_NAO_VINCULADO');
      expect(msg, contains('não está vinculado a uma conta FaucetPay'));
      expect(msg, contains('endereço LTC da sua FaucetPay'));
      expect(withdrawalErrorMessage('EMAIL_NOT_FOUND'), msg);
    });
  });

  group('parseBalanceRawToLitoshi (saldo com decimais corretos)', () {
    test('raw inteiro 1270355 ⇒ 1270355 litoshi = 0,01270355 LTC', () {
      expect(parseBalanceRawToLitoshi(1270355), BigInt.from(1270355));
    });

    test('raw string inteira "49900" ⇒ 49900 litoshi', () {
      expect(parseBalanceRawToLitoshi('49900'), BigInt.from(49900));
    });

    test('decimal legado "0.00012345" ⇒ 12345 litoshi', () {
      expect(parseBalanceRawToLitoshi('0.00012345'), BigInt.from(12345));
    });

    test('zero e valores grandes', () {
      expect(parseBalanceRawToLitoshi(0), BigInt.zero);
      expect(parseBalanceRawToLitoshi(100000000), BigInt.from(100000000));
    });

    test('inválido ⇒ null', () {
      expect(parseBalanceRawToLitoshi(null), isNull);
      expect(parseBalanceRawToLitoshi('abc'), isNull);
      expect(parseBalanceRawToLitoshi(<String, dynamic>{}), isNull);
    });
  });
}
