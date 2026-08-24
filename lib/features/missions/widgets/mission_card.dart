import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/providers.dart';
import '../../../core/services/claim_service.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/mission_model.dart';

enum _ClaimPhase { idle, sending, validating, claimed, failed }

/// Card de MISSÃO: ícone próprio, título, progresso "x / y" com barra ciano,
/// recompensa dourada e botão contextual:
///  - JOGAR (navega para /app/games) quando em progresso;
///  - RESGATAR (claim via [ClaimService]) quando completo;
///  - spinner "VALIDANDO" até o runner processar (≤ ~5 min);
///  - check quando claimed.
/// O cliente NUNCA concede a recompensa — apenas cria a intenção `claims`.
class MissionCard extends ConsumerStatefulWidget {
  const MissionCard({super.key, required this.view, this.onPlay});

  final MissionView view;
  final VoidCallback? onPlay;

  @override
  ConsumerState<MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends ConsumerState<MissionCard> {
  _ClaimPhase _phase = _ClaimPhase.idle;
  StreamSubscription<ClaimResult>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  MissionView get _view => widget.view;

  Future<void> _claim() async {
    if (_phase == _ClaimPhase.sending || _phase == _ClaimPhase.validating) return;
    setState(() => _phase = _ClaimPhase.sending);
    final ClaimService service = ref.read(claimServiceProvider);
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (uid == null) throw ClaimException('Faça login para resgatar.');
      final String requestId = await service.createClaim(
        uid: uid,
        kind: 'mission',
        refId: _view.mission.id,
      );
      if (!mounted) return;
      setState(() => _phase = _ClaimPhase.validating);
      // O runner valida e credita (≤ ~5 min); o doc do claim transiciona
      // pending → claimed/failed e o card reflete.
      _sub?.cancel();
      _sub = service.watchResult(requestId).listen(
        (ClaimResult r) {
          if (!mounted) return;
          if (r.isClaimed) {
            setState(() => _phase = _ClaimPhase.claimed);
          } else if (r.isFailed) {
            setState(() => _phase = _ClaimPhase.failed);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ClaimService.failureMessage(r.failureCode)),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        onError: (Object _) {
          // Offline: permanece "validando"; o runner processa quando possível.
        },
      );
    } on ClaimException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _ClaimPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ClaimPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar o resgate. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool claimed = _view.isClaimed || _phase == _ClaimPhase.claimed;
    final bool claimable = _view.isClaimable && !claimed;
    final bool busy =
        _phase == _ClaimPhase.sending || _phase == _ClaimPhase.validating;

    return NeonPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SvgPicture.string(
            AppAssets.iconForMetric(_view.mission.metric),
            width: 44,
            height: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _view.mission.title.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Progresso: ${_view.progress.progress.clamp(0, _view.mission.target)}'
                  ' / ${_view.mission.target}',
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _view.mission.target <= 0
                        ? 0
                        : (_view.progress.progress / _view.mission.target)
                            .clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.textSecondary.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    SvgPicture.string(AppAssets.coinIconSvg, width: 16, height: 16),
                    const SizedBox(width: 6),
                    // Flexible: títulos/valores longos nunca estouram o card.
                    Flexible(
                      child: Text(
                        'Recompensa: ${_view.mission.rewardCoins} COIN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildAction(claimed, claimable, busy),
        ],
      ),
    );
  }

  Widget _buildAction(bool claimed, bool claimable, bool busy) {
    if (claimed) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.check_circle, color: AppColors.green, size: 28),
          SizedBox(height: 4),
          Text(
            'RESGATADO',
            style: TextStyle(color: AppColors.green, fontSize: 10),
          ),
        ],
      );
    }
    if (busy) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2.5),
          ),
          SizedBox(height: 4),
          Text(
            'VALIDANDO',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
          ),
        ],
      );
    }
    if (claimable) {
      return Semantics(
        button: true,
        label: 'Resgatar recompensa',
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: AppColors.background,
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          onPressed: _claim,
          child: const Text('RESGATAR'),
        ),
      );
    }
    // Em progresso ⇒ JOGAR.
    return Semantics(
      button: true,
      label: 'Jogar para progredir',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cyan,
          side: const BorderSide(color: AppColors.cyan),
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        onPressed: widget.onPlay,
        child: const Text('JOGAR'),
      ),
    );
  }
}
