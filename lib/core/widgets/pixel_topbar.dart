import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';

class PixelTopbar extends StatelessWidget {
  final String balanceText;
  final VoidCallback? onSettings;

  const PixelTopbar({super.key, required this.balanceText, this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: PixelTheme.panel,
                border: Border.all(color: PixelTheme.border, width: 2),
                borderRadius: BorderRadius.circular(PixelTheme.radius),
              ),
              child: Row(
                children: [
                  const PixelIcon(matrix: PixelIcons.coin, palette: PixelIcons.palette, size: 28),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(balanceText,
                            style: PixelTheme.title.copyWith(fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const Text('COIN',
                            style: TextStyle(
                                color: PixelTheme.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PixelTheme.panel,
                border: Border.all(color: PixelTheme.border, width: 2),
                borderRadius: BorderRadius.circular(PixelTheme.radius),
              ),
              child: const PixelIcon(matrix: PixelIcons.gear, palette: PixelIcons.palette, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}
