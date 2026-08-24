import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Sprite PIXEL-ART próprio de máquina (rig com ventoinha e LEDs) — arte
/// 100% em código, matrizes const. NENHUM asset externo.
///
/// Paleta por raridade:
/// - common:    cinza-azulado
/// - rare:      ciano
/// - epic:      roxo
/// - legendary: dourado
abstract final class MachineSpriteArt {
  /// Legenda: '.' vazio | 'B' corpo escuro | 'b' corpo claro |
  /// 'L' anel/detalhe accent | 'f' pás da ventoinha (accent) |
  /// 'G' brilho da base (accent).
  static const List<String> rigMatrix = <String>[
    '................',
    '...BBBBBBBBBB...',
    '..BbbbbbbbbbbB..',
    '..BbLLLLLLLLbB..',
    '..BbL......LbB..',
    '..BbL.ff.f.LbB..',
    '..BbLf.ff.fLbB..',
    '..BbL.ff.f.LbB..',
    '..BbL.f..f.LbB..',
    '..BbL......LbB..',
    '..BbLLLLLLLLbB..',
    '..BbLLLGGLLLbB..',
    '..BbLbLbLbLbbB..',
    '..BBBBBBBBBBBB..',
    '.GGGGGGGGGGGGGG.',
    '................',
  ];

  static const int cols = 16;
  static const int rows = 16;

  /// Cor de accent por raridade (fallback: common).
  static Color accentFor(String rarity) {
    switch (rarity.toLowerCase().trim()) {
      case 'rare':
        return AppColors.cyan;
      case 'epic':
        return AppColors.purple;
      case 'legendary':
        return AppColors.gold;
      case 'common':
      default:
        return const Color(0xFF8FA3C8); // cinza-azulado
    }
  }

  /// Rótulo de raridade em PT-BR para chips.
  static String rarityLabel(String rarity) {
    switch (rarity.toLowerCase().trim()) {
      case 'rare':
        return 'RARO';
      case 'epic':
        return 'ÉPICO';
      case 'legendary':
        return 'LENDÁRIO';
      case 'common':
        return 'COMUM';
      default:
        return 'COMUM';
    }
  }
}

/// Widget do sprite: CustomPainter pinta a matriz com a paleta da raridade.
class MachineSprite extends StatelessWidget {
  const MachineSprite({
    super.key,
    required this.rarity,
    this.size = 72,
  });

  final String rarity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MachineSpritePainter(accent: MachineSpriteArt.accentFor(rarity)),
      ),
    );
  }
}

class _MachineSpritePainter extends CustomPainter {
  const _MachineSpritePainter({required this.accent});

  final Color accent;

  static const Color _bodyDark = Color(0xFF232A3D);
  static const Color _bodyLight = Color(0xFF39445F);

  @override
  void paint(Canvas canvas, Size size) {
    final double cellW = size.width / MachineSpriteArt.cols;
    final double cellH = size.height / MachineSpriteArt.rows;
    final Paint paint = Paint();

    final Color glow = accent.withValues(alpha: 0.35);

    for (int r = 0; r < MachineSpriteArt.rows; r++) {
      final String row = MachineSpriteArt.rigMatrix[r];
      for (int c = 0; c < row.length && c < MachineSpriteArt.cols; c++) {
        final String ch = row[c];
        if (ch == '.') continue;
        paint.color = switch (ch) {
          'B' => _bodyDark,
          'b' => _bodyLight,
          'L' => accent,
          'f' => accent.withValues(alpha: 0.85),
          'G' => glow,
          _ => _bodyDark,
        };
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH),
            Radius.circular(cellW * 0.15),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MachineSpritePainter oldDelegate) =>
      oldDelegate.accent != accent;
}
