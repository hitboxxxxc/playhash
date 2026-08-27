import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';

class PixelBottomnav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTab;

  const PixelBottomnav({super.key, required this.index, required this.onTab});

  static const List<String> labels = ['HOME', 'SALA', 'GAMES', 'CARTEIRA'];

  @override
  Widget build(BuildContext context) {
    const List<List<String>> icons = [
      PixelIcons.home,
      PixelIcons.monitor,
      PixelIcons.gamepad,
      PixelIcons.wallet,
    ];
    return Container(
      color: PixelTheme.background,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: List.generate(4, (i) {
          final bool selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTab(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? PixelTheme.purpleDark : PixelTheme.panel,
                  border: Border.all(
                      color: selected ? PixelTheme.purple : PixelTheme.border, width: 2),
                  borderRadius: BorderRadius.circular(PixelTheme.radius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelIcon(matrix: icons[i], palette: PixelIcons.palette, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      style: TextStyle(
                          color: selected ? PixelTheme.text : PixelTheme.textDim,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
