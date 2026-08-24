import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/machine_model.dart';
import 'machine_slot.dart';

/// SALA DE MÁQUINAS REAL: slots = config/economy.machineSlots (fallback 10),
/// em prateleiras de 5. Slots preenchidos pelas máquinas owned (sprite por
/// raridade + badge "LV.X" verde); slots vazios = "+"; slots travados
/// (índice >= machineSlots) = cadeado. Botões "EDITAR SALA"/"ORGANIZAR"
/// abrem informativo "em breve".
class MachineRoomGrid extends StatelessWidget {
  const MachineRoomGrid({
    super.key,
    required this.machines,
    this.machineSlots = 10,
    this.loading = false,
    required this.onEditRoomTap,
    required this.onOrganizeTap,
  });

  static const int _slotsPerShelf = 5;

  final List<MachineModel> machines;
  final int machineSlots;
  final bool loading;
  final VoidCallback onEditRoomTap;
  final VoidCallback onOrganizeTap;

  /// Posições RENDERIZADAS: mínimo 2 prateleiras (10); machineSlots maior
  /// adiciona prateleiras. Índices >= machineSlots são travados (cadeado).
  int get _totalSlots {
    final int slots = machineSlots < 0 ? 0 : machineSlots;
    final int shelves = (slots / _slotsPerShelf).ceil();
    return (shelves < 2 ? 2 : shelves) * _slotsPerShelf;
  }

  int get _shelfCount => _totalSlots ~/ _slotsPerShelf;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: AppColors.purple,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int shelf = 0; shelf < _shelfCount; shelf++) ...<Widget>[
            if (shelf > 0) ...<Widget>[
              const SizedBox(height: 10),
              _ShelfDivider(label: 'RIG 0${shelf + 1}'),
              const SizedBox(height: 10),
            ],
            Row(
              children: <Widget>[
                for (int slot = 0; slot < _slotsPerShelf; slot++) ...<Widget>[
                  if (slot > 0) const SizedBox(width: 8),
                  Expanded(child: _buildSlot(shelf, slot)),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _RoomButton(
                  label: 'EDITAR SALA',
                  onTap: onEditRoomTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoomButton(
                  label: 'ORGANIZAR',
                  onTap: onOrganizeTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlot(int shelf, int slot) {
    final int index = shelf * _slotsPerShelf + slot;
    if (index >= _totalSlots) return const SizedBox.shrink();

    final bool locked = index >= machineSlots;
    final MachineModel? machine =
        loading || locked || index >= machines.length ? null : machines[index];

    return MachineSlot(
      machine: machine,
      slotIndex: index,
      locked: locked,
      loading: loading,
    );
  }
}

/// Divisor decorativo entre prateleiras.
class _ShelfDivider extends StatelessWidget {
  const _ShelfDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

/// Botão da sala (≥48dp, contraste adequado).
class _RoomButton extends StatelessWidget {
  const _RoomButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: SizedBox(
        height: 48,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.5)),
            ),
          ),
          child: TextButton(
            onPressed: onTap,
            child: Text(
              label,
              style: AppTheme.neonLabel(
                fontSize: 12,
                color: AppColors.cyan,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
