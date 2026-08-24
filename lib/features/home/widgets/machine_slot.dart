import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/machine_icons.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../data/models/machine_model.dart';

/// Slot da sala de máquinas: máquina com badge de nível e SVG próprio
/// colorido por raridade; slot vazio/travado exibe cadeado.
class MachineSlot extends StatelessWidget {
  const MachineSlot({
    super.key,
    required this.machine,
    required this.slotIndex,
    this.loading = false,
  });

  /// Máquina oficial do servidor; `null` => slot vazio/travado.
  final MachineModel? machine;
  final int slotIndex;
  final bool loading;

  Color get _rarityColor {
    final String? rarity =
        (machine?.metadata['rarity'] as String?)?.toLowerCase().trim();
    switch (rarity) {
      case 'uncommon':
        return AppColors.green;
      case 'rare':
        return AppColors.purple;
      case 'epic':
      case 'legendary':
        return AppColors.gold;
      case 'common':
      default:
        return AppColors.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double side = _slotSide(context);

    if (loading) {
      return Center(child: SkeletonBox(width: side, height: side));
    }

    final MachineModel? machine = this.machine;
    if (machine == null) {
      return _LockedSlot(size: side);
    }

    final Color color = _rarityColor;
    return Semantics(
      label: 'Máquina nível ${machine.level}',
      value: machine.power > 0 ? PowerFormat.format(machine.power) : null,
      child: SizedBox(
        width: side,
        height: side + 18,
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.7)),
              ),
              child: Text(
                'LV.${machine.level}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                width: side,
                decoration: ShapeDecoration(
                  color: AppColors.background,
                  shape: ChamferedBorder(
                    cut: 8,
                    side: BorderSide(color: color.withValues(alpha: 0.45)),
                  ),
                ),
                child: Center(
                  child: MachineIcons.colored(
                    MachineIcons.byIndex(slotIndex),
                    color: color,
                    size: side * 0.55,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Largura do slot responsiva à largura disponível da tela.
  double _slotSide(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // 5 slots + espaçamentos + padding horizontal da tela/painel.
    final double available = width - 40 - 28 - 4 * 8;
    return (available / 5).clamp(48.0, 76.0);
  }
}

/// Slot vazio/travado com cadeado.
class _LockedSlot extends StatelessWidget {
  const _LockedSlot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Slot de máquina travado',
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: AppColors.background,
          shape: ChamferedBorder(
            cut: 8,
            side: BorderSide(
              color: AppColors.textSecondary.withValues(alpha: 0.25),
            ),
          ),
        ),
        child: Center(
          child: Opacity(
            opacity: 0.55,
            child: SvgPicture.string(
              NeonIcons.padlock,
              width: size * 0.4,
              colorFilter: const ColorFilter.mode(
                AppColors.textSecondary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
