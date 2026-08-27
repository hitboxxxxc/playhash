import 'package:flutter/material.dart';

class PixelIcon extends StatelessWidget {
  final List<String> matrix;
  final Map<String, Color> palette;
  final double size;
  final Color? background;

  const PixelIcon({
    super.key,
    required this.matrix,
    required this.palette,
    this.size = 24,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PixelIconPainter(
        matrix: matrix,
        palette: palette,
        background: background,
      ),
    );
  }
}

class _PixelIconPainter extends CustomPainter {
  final List<String> matrix;
  final Map<String, Color> palette;
  final Color? background;

  _PixelIconPainter({
    required this.matrix,
    required this.palette,
    this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (matrix.isEmpty) return;
    final int rows = matrix.length;
    int cols = 0;
    for (final String row in matrix) {
      if (row.length > cols) cols = row.length;
    }
    if (cols == 0) return;

    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background!);
    }

    final double cellW = size.width / cols;
    final double cellH = size.height / rows;
    final double cell = cellW < cellH ? cellW : cellH;
    final double offsetX = (size.width - cell * cols) / 2;
    final double offsetY = (size.height - cell * rows) / 2;
    final Paint paint = Paint();

    for (int y = 0; y < rows; y++) {
      final String row = matrix[y];
      for (int x = 0; x < row.length && x < cols; x++) {
        final String ch = row[x];
        if (ch == '.' || ch == ' ') continue;
        final Color? color = palette[ch];
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(offsetX + x * cell, offsetY + y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelIconPainter oldDelegate) =>
      oldDelegate.matrix != matrix || oldDelegate.palette != palette;
}
