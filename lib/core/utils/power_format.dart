/// Formatação de PODER — SOMENTE para apresentação.
///
/// Recebe a unidade-base INTEIRA (H/s) e escala em múltiplos de 1000:
/// H/s → KH/s → MH/s → GH/s → TH/s → PH/s → EH/s → ZH/s → YH/s.
///
/// NENHUMA lógica econômica vive aqui: o valor exibido é apenas espelho
/// formatado do dado oficial fornecido pelo servidor.
abstract final class PowerFormat {
  static const List<String> _units = <String>[
    'H/s', 'KH/s', 'MH/s', 'GH/s', 'TH/s', 'PH/s', 'EH/s', 'ZH/s', 'YH/s',
  ];

  /// Formata a quantidade de unidades-base (H/s) na maior escala possível,
  /// com 2 casas decimais no padrão pt-BR (vírgula decimal, ponto de milhar).
  /// Valores negativos (dado inválido) exibem "—".
  static String format(num baseUnits) {
    if (baseUnits < 0) return '—';
    double value = baseUnits.toDouble();
    int index = 0;
    while (value >= 1000 && index < _units.length - 1) {
      value /= 1000;
      index++;
    }
    return '${_formatDecimal(value)} ${_units[index]}';
  }

  /// Apenas o valor numérico (sem unidade), 2 casas, pt-BR.
  static String _formatDecimal(double value) {
    final List<String> parts = value.toStringAsFixed(2).split('.');
    return '${_groupThousands(parts[0])},${parts[1]}';
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
