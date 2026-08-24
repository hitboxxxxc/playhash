import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/machine_sprite.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../data/models/machine_model.dart';

/// Slot da sala de máquinas:
/// - preenchido: sprite pixel próprio por raridade + badge "LV.X" verde;
/// - vazio (dentro de machineSlots): "+" discreto;
/// - travado (índice >= machineSlots): cadeado.
class MachineSlot extends StatelessWidget {
  const MachineSlot({
    super.key,
    required this.machine,
    required this.slotIndex,
    this.locked = false,
    this.loading = false,
  });

  /// Máquina oficial do servidor; `null` => slot vazio/travado.
  final MachineModel? machine;
  final int slotIndex;
  final bool locked;
  final bool loading;

  Color get _rarityColor =>
      MachineSpriteArt.accentFor(machine?.metadata['rarity'] as String? ?? '');

  @override
  Widget build(BuildContext context) {
    final double side = _slotSide(context);

    if (loading) {
      return Center(child: SkeletonBox(width: side, height: side));
    }

    if (locked) return _LockedSlot(size: side);

    final MachineModel? machine = this.machine;
    if (machine == null) return _EmptySlot(size: side);

    final Color color = _rarityColor;
    return Semantics(
      label: 'Máquina ${machine.type}',
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
                border: Border.all(color: AppColors.green.withValues(alpha: 0.7)),
              ),
              child: Text(
                'LV.${machine.level}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.green,
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
                  child: MachineSprite(
                    rarity: machine.metadata['rarity'] as String? ?? '',
                    size: side * 0.72,
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

/// Slot vazio (disponível) com "+" discreto.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Slot de máquina vazio',
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: AppColors.background,
          shape: ChamferedBorder(
            cut: 8,
            side: BorderSide(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add,
            size: size * 0.32,
            color: AppColors.textSecondary.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

/// Slot travado (fora de machineSlots) com cadeado.
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
