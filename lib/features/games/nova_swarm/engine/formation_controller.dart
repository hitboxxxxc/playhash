import 'dart:math';
import 'dart:ui';

import 'wave_spawner.dart';

/// Geometria da formação em um instante — CENTRADA e CONTIDA (corrige o
/// drift da v1 que levava inimigos para fora da tela).
///
/// - cols = min(6, E); rows = ceil(E / cols); gaps 44×40dp.
/// - topo = 8% da altura do campo.
/// - x = centerX + sin(t × 0.6) × A, com
///   A = min(24dp, (playW − formW)/2 − 8dp) clampado a ≥ 0
///   ⇒ a formação NUNCA sai da tela, em nenhuma largura.
/// - bob vertical senoidal ±3dp.
abstract final class FormationController {
  /// Largura do sprite do inimigo (9px × 3dp) usada no cálculo de contenção.
  static const double enemyWidth = 27;

  /// Amplitude máxima do sway (dp).
  static const double maxAmplitude = 24;

  /// Margem mínima entre a borda da formação e a borda do playfield (dp).
  static const double edgeMargin = 8;

  /// Frequência do sway (rad/s ⇒ sin(t × 0.6)).
  static const double swayOmega = 0.6;

  /// Frequência do bob vertical (Hz ~0.9 ⇒ ±3dp suave).
  static const double bobOmega = 1.8;

  /// Amplitude do bob vertical (dp).
  static const double bobAmplitude = 3;

  /// Amplitude CONTIDA do sway para [fieldWidth] e nº de colunas.
  /// A = min(24, (playW − formW)/2 − 8), nunca negativa.
  static double swayAmplitudeFor({
    required double fieldWidth,
    required int cols,
  }) {
    final double formWidth = FormationGeometry.formWidthFor(cols);
    final double free = (fieldWidth - formWidth) / 2 - edgeMargin;
    return max(0, min(maxAmplitude, free));
  }

  /// Offset horizontal do sway no instante [t] (s).
  static double swayOffset({
    required double t,
    required double amplitude,
  }) =>
      sin(t * swayOmega) * amplitude;

  /// Offset vertical do bob no instante [t] (s): ±3dp.
  static double bobOffset(double t) => sin(t * bobOmega) * bobAmplitude;

  /// Topo da formação: 8% da altura do campo.
  static double topFor(double fieldHeight) => fieldHeight * 0.08;

  /// Geometria completa para uma wave.
  static FormationGeometry compute({
    required int enemyCount,
    required Size fieldSize,
  }) {
    final int cols = WaveSpawner.columnsForCount(enemyCount);
    final int rows = (enemyCount / cols).ceil();
    return FormationGeometry(
      count: enemyCount,
      cols: cols,
      rows: rows,
      centerX: fieldSize.width / 2,
      topY: topFor(fieldSize.height),
      amplitude: swayAmplitudeFor(fieldWidth: fieldSize.width, cols: cols),
      fieldSize: fieldSize,
    );
  }
}

/// Resultado imutável do cálculo de layout (testável sem Flutter rendering).
class FormationGeometry {
  const FormationGeometry({
    required this.count,
    required this.cols,
    required this.rows,
    required this.centerX,
    required this.topY,
    required this.amplitude,
    required this.fieldSize,
  });

  /// Nº total de inimigos da wave (a última fileira pode ser parcial).
  final int count;
  final int cols;
  final int rows;
  final double centerX;
  final double topY;
  final double amplitude;
  final Size fieldSize;

  /// Largura total da grade cheia: (cols−1)×44 + sprite.
  static double formWidthFor(int cols) =>
      (cols - 1) * WaveSpawner.colSpacing + FormationController.enemyWidth;

  double get formWidth => formWidthFor(cols);

  /// Limites horizontais da formação com o sway máximo — SEMPRE dentro do
  /// campo (invariante testado para 320/360/411dp).
  double get minX => centerX - formWidth / 2 - amplitude;
  double get maxX => centerX + formWidth / 2 + amplitude;

  bool get isContained => minX >= 0 && maxX <= fieldSize.width;

  /// Posição de slot de um inimigo no instante [t].
  /// A última fileira (possivelmente parcial) também fica centralizada.
  Offset slotPosition({required int row, required int col, required double t}) {
    final int colsInRow =
        row == rows - 1 ? count - (rows - 1) * cols : cols;
    final double rowOffset = (col - (colsInRow - 1) / 2) * WaveSpawner.colSpacing;
    final double x = centerX +
        FormationController.swayOffset(t: t, amplitude: amplitude) +
        rowOffset;
    final double y =
        topY + row * WaveSpawner.rowSpacing + FormationController.bobOffset(t);
    return Offset(x, y);
  }
}
