import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';

class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _dashes()),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(text.toUpperCase(), style: PixelTheme.title),
          ),
        ),
        Expanded(child: _dashes()),
      ],
    );
  }

  Widget _dashes() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SizedBox(
          height: 6,
          width: constraints.maxWidth,
          child: CustomPaint(
            painter: _DashPainter(),
            size: Size(constraints.maxWidth, 6),
          ),
        );
      },
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = PixelTheme.purple;
    double x = 0;
    bool on = true;
    while (x < size.width) {
      if (on) canvas.drawRect(Rect.fromLTWH(x, 1.5, 6, 3), paint);
      x += on ? 11 : 5;
      on = !on;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
