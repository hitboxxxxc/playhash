import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/coin_format.dart';

/// Cabeçalho da CARTEIRA — artes próprias em código (CustomPainter), sem
/// imagem externa. Saldo disponível em destaque DOURADO, pendente com ícone
/// de relógio e total vitalício discreto.
///
/// SEM botão DEPOSITAR: o app não aceita depósitos (o usuário ganha moedas
/// jogando, em missões e na liga).
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.availableBalance,
    required this.pendingBalance,
    required this.lifetimeEarned,
  });

  final BigInt availableBalance;
  final BigInt pendingBalance;
  final BigInt lifetimeEarned;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WalletBoxPainter(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SALDO DISPONÍVEL',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              CoinFormat.formatWithTicker(availableBalance),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.gold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(Icons.schedule, size: 16, color: AppColors.cyan),
                const SizedBox(width: 6),
                Text(
                  'Pendente: ${CoinFormat.formatMinimalUnits(pendingBalance)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Total ganho: ${CoinFormat.formatMinimalUnits(lifetimeEarned)}',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caixa própria da carteira: painel chanfrado com bordas neon duplas
/// (dourada + ciano) desenhadas em código.
class _WalletBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cut = 14;
    final Path path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();

    final Paint fill = Paint()..color = AppColors.surface;
    canvas.drawPath(path, fill);

    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.gold.withValues(alpha: 0.55);
    canvas.drawPath(path, border);

    final Paint inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.cyan.withValues(alpha: 0.18);
    canvas.drawPath(path.shift(const Offset(0, 0)), inner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
