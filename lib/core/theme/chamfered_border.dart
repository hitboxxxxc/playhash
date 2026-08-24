import 'package:flutter/material.dart';

/// [OutlinedBorder] próprio com cantos chanfrados (corte diagonal a 45°),
/// identidade visual do PlayHash. Compatível com botões Material.
class ChamferedBorder extends OutlinedBorder {
  const ChamferedBorder({
    super.side,
    this.cut = 12,
  });

  /// Tamanho do corte diagonal em cada canto.
  final double cut;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _buildPath(Rect rect) {
    final double c = cut.clamp(0.0, rect.shortestSide / 2);
    return Path()
      ..moveTo(rect.left + c, rect.top)
      ..lineTo(rect.right - c, rect.top)
      ..lineTo(rect.right, rect.top + c)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - c, rect.bottom)
      ..lineTo(rect.left + c, rect.bottom)
      ..lineTo(rect.left, rect.bottom - c)
      ..lineTo(rect.left, rect.top + c)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(_buildPath(rect), side.toPaint());
  }

  @override
  ChamferedBorder copyWith({BorderSide? side, double? cut}) => ChamferedBorder(
        side: side ?? this.side,
        cut: cut ?? this.cut,
      );

  @override
  ChamferedBorder scale(double t) =>
      ChamferedBorder(side: side.scale(t), cut: cut * t);
}
