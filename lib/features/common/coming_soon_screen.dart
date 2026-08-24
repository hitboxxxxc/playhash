import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Rota placeholder para seções ainda não implementadas.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text((title ?? 'SEÇÃO').toUpperCase())),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'EM BREVE',
              style: AppTheme.neonLabel(fontSize: 22),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Esta seção está em construção.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('VOLTAR'),
            ),
          ],
        ),
      ),
    );
  }
}
