import 'package:flutter/material.dart';
import '../theme/pixel_theme.dart';
import 'pixel_topbar.dart';
import 'pixel_bottomnav.dart';

class PixelMenuItem {
  final String label;
  final VoidCallback onTap;
  const PixelMenuItem({required this.label, required this.onTap});
}

class PixelShell extends StatefulWidget {
  final String balanceText;
  final List<Widget> pages;
  final List<PixelMenuItem> menuItems;

  const PixelShell({
    super.key,
    required this.balanceText,
    required this.pages,
    required this.menuItems,
  });

  @override
  State<PixelShell> createState() => _PixelShellState();
}

class _PixelShellState extends State<PixelShell> {
  int _index = 0;

  void _openMenu() {
    showModalBottomSheet(
      backgroundColor: PixelTheme.panel,
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('MENU', style: PixelTheme.title),
            const SizedBox(height: 4),
            ...widget.menuItems.map((m) => ListTile(
                  title: Text(m.label,
                      style: const TextStyle(color: PixelTheme.text)),
                  onTap: () {
                    Navigator.of(context).pop();
                    m.onTap();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelTheme.background,
      body: Column(
        children: [
          PixelTopbar(balanceText: widget.balanceText, onSettings: _openMenu),
          Expanded(child: IndexedStack(index: _index, children: widget.pages)),
        ],
      ),
      bottomNavigationBar:
          PixelBottomnav(index: _index, onTab: (i) => setState(() => _index = i)),
    );
  }
}
