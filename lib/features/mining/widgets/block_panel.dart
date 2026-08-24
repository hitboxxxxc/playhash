import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/repositories/mining_repository.dart';

/// Painel "RECOMPENSA" — linhas preenchidas APENAS com dados oficiais do
/// [MiningRepository]. Sem backend => "—" em tudo. A contagem regressiva
/// SÓ existe quando o backend provê `nextBlockAt` (nunca hardcode).
class BlockPanel extends StatefulWidget {
  const BlockPanel({
    super.key,
    this.block,
    this.yourPower,
    this.estimate,
  });

  final BlockSnapshot? block;
  final int? yourPower;
  final RewardEstimate? estimate;

  @override
  State<BlockPanel> createState() => _BlockPanelState();
}

class _BlockPanelState extends State<BlockPanel> {
  Timer? _ticker;
  DateTime? _nextBlockAt;

  @override
  void initState() {
    super.initState();
    _syncSchedule();
  }

  @override
  void didUpdateWidget(BlockPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSchedule();
  }

  void _syncSchedule() {
    final DateTime? next = widget.block?.nextBlockAt;
    if (next == _nextBlockAt) return;
    _ticker?.cancel();
    _ticker = null;
    _nextBlockAt = next;
    if (next != null) {
      // Contagem visual apenas com schedule oficial do backend.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _totalRewardLabel {
    final BigInt? totalReward = widget.block?.totalBlockRewardMinimalUnits;
    if (totalReward == null) return '—';
    return CoinFormat.formatWithTicker(totalReward);
  }

  String get _yourPowerLabel {
    final int? power = widget.yourPower;
    if (power == null || power <= 0) return '—';
    return PowerFormat.format(power);
  }

  String get _networkPowerLabel {
    final int? network = widget.block?.networkPower;
    if (network == null || network <= 0) return '—';
    return PowerFormat.format(network);
  }

  String get _countdownLabel {
    final DateTime? next = _nextBlockAt;
    if (next == null) return '—';
    final Duration remaining = next.difference(DateTime.now());
    if (remaining.isNegative) return '—';
    final int hours = remaining.inHours;
    final int minutes = remaining.inMinutes.remainder(60);
    final int seconds = remaining.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final RewardEstimate? estimate = widget.estimate;

    return NeonPanel(
      accent: AppColors.purple,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Text(
              'RECOMPENSA',
              style: AppTheme.neonLabel(fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),
          _Row(
            icon: NeonIcons.clock,
            iconColor: AppColors.purple,
            label: 'PRÓXIMO BLOCO',
            value: _countdownLabel,
            valueColor: AppColors.gold,
          ),
          _Row(
            icon: NeonIcons.coin,
            iconColor: AppColors.gold,
            label: 'RECOMPENSA TOTAL DO BLOCO',
            value: _totalRewardLabel,
            valueColor: AppColors.gold,
          ),
          _Row(
            icon: NeonIcons.bolt,
            iconColor: AppColors.cyan,
            label: 'SEU PODER',
            value: _yourPowerLabel,
            valueColor: AppColors.cyan,
          ),
          _Row(
            icon: NeonIcons.globe,
            iconColor: AppColors.cyan,
            label: 'PODER TOTAL DA REDE',
            value: _networkPowerLabel,
            valueColor: AppColors.cyan,
          ),
          _Row(
            icon: NeonIcons.users,
            iconColor: AppColors.green,
            label: 'PARTICIPAÇÃO ESTIMADA',
            value: estimate == null
                ? '—'
                : '${(estimate.share * 100).toStringAsFixed(2)}%',
            valueColor: AppColors.green,
          ),
          _Row(
            icon: NeonIcons.coin,
            iconColor: AppColors.gold,
            label: 'RECOMPENSA ESTIMADA',
            value: estimate == null
                ? '—'
                : CoinFormat.formatWithTicker(estimate.estimatedRewardMinimalUnits),
            valueColor: AppColors.gold,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SvgPicture.string(
                NeonIcons.info,
                width: 16,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Valores calculados pelo sistema; recompensas virtuais; '
                  'estimativas não são definitivas.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Linha rótulo/valor do painel.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SvgPicture.string(
            icon,
            width: 18,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Semantics(
            label: label,
            value: value,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: value == '—' ? AppColors.textSecondary : valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
