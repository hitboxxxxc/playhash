/// Ticker de EXIBIÇÃO provisório — apenas apresentação.
/// A autoridade do ticker virá do `currencyId` fornecido pelo backend;
/// NUNCA usar esta constante como dado econômico.
const String kDisplayCoinTicker = 'COIN';

/// Formatação de SALDO — SOMENTE para apresentação.
///
/// Recebe unidades mínimas INTEIRAS (1 moeda = 1.000.000 unidades mínimas)
/// e exibe com ATÉ 6 casas decimais no padrão pt-BR. Usa aritmética inteira
/// (BigInt) para evitar erros de ponto flutuante. Sem lógica econômica.
abstract final class CoinFormat {
  static const int _decimals = 6;
  static final BigInt _scale = BigInt.from(1000000);

  /// Formata unidades mínimas como valor decimal pt-BR (até 6 casas,
  /// zeros à direita removidos). Ex.: 4210000 → "4,21".
  static String formatMinimalUnits(BigInt minimalUnits) {
    final bool negative = minimalUnits < BigInt.zero;
    final BigInt abs = negative ? -minimalUnits : minimalUnits;
    final BigInt whole = abs ~/ _scale;
    final BigInt frac = abs % _scale;

    String fracStr = frac.toString().padLeft(_decimals, '0');
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');

    final String sign = negative ? '-' : '';
    final String wholeStr = _groupThousands(whole.toString());
    if (fracStr.isEmpty) return '$sign$wholeStr';
    return '$sign$wholeStr,$fracStr';
  }

  /// Valor formatado + ticker de exibição. Ex.: "4,21 COIN".
  static String formatWithTicker(BigInt minimalUnits) =>
      '${formatMinimalUnits(minimalUnits)} $kDisplayCoinTicker';

  /// Formata LITOSHI como decimal LTC pt-BR (até 8 casas, zeros à direita
  /// aparados). Ex.: 1800 → "0,000018"; 0 → "0". APENAS apresentação —
  /// o cálculo oficial é 100% do backend.
  static String formatLitoshi(BigInt litoshi) {
    final BigInt whole = litoshi ~/ BigInt.from(100000000);
    final BigInt frac = litoshi % BigInt.from(100000000);
    String fracStr = frac.toString().padLeft(8, '0');
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
    if (fracStr.isEmpty) return '$whole';
    return '$whole,$fracStr';
  }

  /// Agrupa a parte inteira em blocos de 3 com "." (pt-BR).
  static String _groupThousands(String digits) {
    final StringBuffer out = StringBuffer();
    final int len = digits.length;
    for (int i = 0; i < len; i++) {
      out.write(digits[i]);
      final int remaining = len - i - 1;
      if (remaining > 0 && remaining % 3 == 0) out.write('.');
    }
    return out.toString();
  }
}
