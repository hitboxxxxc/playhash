import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// COUNTDOWN 3 → 2 → 1 → GO! (v2): 700ms por passo, dígitos PIXEL desenhados
/// em código (matrizes próprias, zero assets), pop de escala + fade.
/// O loop do jogo fica CONGELADO durante o countdown; o timer inicia no GO.
class CountdownOverlay extends StatefulWidget {
  const CountdownOverlay({super.key, required this.onFinished});

  /// Chamado uma única vez ao término (~2.8s).
  final VoidCallback onFinished;

  /// Duração total: 4 passos × 700ms.
  static const Duration total = Duration(milliseconds: 2800);

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const int _stepMs = 700;
  static const List<List<String>> _frames = <List<String>>[
    _digit3,
    _digit2,
    _digit1,
    _go,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: CountdownOverlay.total)
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) widget.onFinished();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final int ms = (_controller.value * CountdownOverlay.total.inMilliseconds)
              .round();
          final int step = (ms / _stepMs).clamp(0, _frames.length - 1).floor();
          final double t = (ms % _stepMs) / _stepMs; // 0..1 dentro do passo
          // Pop de escala: começa grande (1.6) e assenta em 1.0.
          final double scale = 1.6 - 0.6 * _easeOut(t);
          // Fade no fim de cada passo (últimos 25%).
          final double opacity =
              t < 0.75 ? 1.0 : 1.0 - ((t - 0.75) / 0.25);

          return ColoredBox(
            color: const Color(0xFF000005).withValues(alpha: 0.45),
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: CustomPaint(
                    size: const Size(150, 50),
                    painter: _PixelFramePainter(_frames[step]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static double _easeOut(double t) => 1 - (1 - t) * (1 - t);
}

// ---- Matrizes de pixel ORIGINAIS (5×7 por glifo, 2 colunas de espaço) ------
const List<String> _digit3 = <String>[
  'XXXXX',
  '....X',
  '....X',
  '.XXXX',
  '....X',
  '....X',
  'XXXXX',
];

const List<String> _digit2 = <String>[
  'XXXXX',
  '....X',
  '....X',
  'XXXXX',
  'X....',
  'X....',
  'XXXXX',
];

const List<String> _digit1 = <String>[
  '..X..',
  '.XX..',
  '..X..',
  '..X..',
  '..X..',
  '..X..',
  'XXXXX',
];

const List<String> _go = <String>[
  '.XXXX.XXX.....X..',
  'X....X...X...XX..',
  'X....X...X..X.X..',
  'X..XXX....X.X..X.',
  'X...X.X...XXXXX..',
  'X...X.X...X...X..',
  '.XXXX.XXX..X...X.',
];

/// Pinta uma matriz de pixel com glow neon ciano.
class _PixelFramePainter extends CustomPainter {
  _PixelFramePainter(this.matrix);

  final List<String> matrix;

  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final int rows = matrix.length;
    final int cols = matrix.first.length;
    final double px = size.width / cols;
    final double py = size.height / rows;

    // Glow (camada borrada).
    _p
      ..color = AppColors.cyan.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (matrix[r][c] == 'X') {
          canvas.drawRect(
            Rect.fromLTWH(c * px, r * py, px, py),
            _p,
          );
        }
      }
    }
    // Núcleo branco-ciano.
    _p.maskFilter = null;
    _p.color = const Color(0xFFEAFDFF);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (matrix[r][c] == 'X') {
          canvas.drawRect(
            Rect.fromLTWH(c * px, r * py, px, py),
            _p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelFramePainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}
