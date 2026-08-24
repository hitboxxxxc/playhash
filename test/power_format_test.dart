import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/utils/coin_format.dart';
import 'package:playhash/core/utils/power_format.dart';

void main() {
  group('PowerFormat (apresentação, pt-BR, múltiplos de 1000)', () {
    test('zero => "0,00 H/s"', () {
      expect(PowerFormat.format(0), '0,00 H/s');
    });

    test('valor abaixo de 1000 permanece em H/s', () {
      expect(PowerFormat.format(999), '999,00 H/s');
    });

    test('1000 => 1,00 KH/s', () {
      expect(PowerFormat.format(1000), '1,00 KH/s');
    });

    test('escala com 2 casas pt-BR', () {
      expect(PowerFormat.format(897460), '897,46 KH/s');
      expect(PowerFormat.format(1500000), '1,50 MH/s');
      expect(PowerFormat.format(897461000000000000), '897,46 PH/s');
    });

    test('agrupamento de milhar na parte inteira', () {
      // 1234 * 1000^8 = 1.234,00 YH/s (entrada double: excede int64).
      expect(PowerFormat.format(1234e24), '1.234,00 YH/s');
    });

    test('valor negativo (dado inválido) => "—"', () {
      expect(PowerFormat.format(-1), '—');
    });

    test('escala máxima não estoura', () {
      // 2^62 ≈ 4,61 EH/s — grande valor ainda dentro de int64.
      final int huge = BigInt.from(2).pow(62).toInt();
      final String result = PowerFormat.format(huge);
      expect(result, endsWith('EH/s'));
    });
  });

  group('CoinFormat (unidades mínimas inteiras, até 6 casas, pt-BR)', () {
    test('zero => "0"', () {
      expect(CoinFormat.formatMinimalUnits(BigInt.zero), '0');
    });

    test('1 unidade mínima => "0,000001"', () {
      expect(CoinFormat.formatMinimalUnits(BigInt.one), '0,000001');
    });

    test('trim de zeros à direita', () {
      expect(CoinFormat.formatMinimalUnits(BigInt.from(4210000)), '4,21');
      expect(CoinFormat.formatMinimalUnits(BigInt.from(1000000)), '1');
      expect(CoinFormat.formatMinimalUnits(BigInt.from(1234567)), '1,234567');
    });

    test('agrupamento de milhar', () {
      expect(
        CoinFormat.formatMinimalUnits(BigInt.from(12345678900000)),
        '12.345.678,9',
      );
    });

    test('negativo', () {
      expect(CoinFormat.formatMinimalUnits(BigInt.from(-1500000)), '-1,5');
    });

    test('com ticker de exibição', () {
      expect(
        CoinFormat.formatWithTicker(BigInt.from(4210000)),
        '4,21 COIN',
      );
    });
  });
}
