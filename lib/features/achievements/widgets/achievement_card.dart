import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/providers.dart';
import '../../../core/services/claim_service.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/achievement_model.dart';

enum _ClaimPhase { idle, sending, validating, claimed, failed }

/// Card de CONQUISTA (grade 2 colunas): desbloqueada/claimable em ciano,
/// bloqueada esmaecida com cadeado; progresso "x / y", recompensa dourada e
/// fluxo de claim idêntico ao das missões (intenção validada pelo runner).
class AchievementCard extends ConsumerStatefulWidget {
  const AchievementCard({super.key, required this.view});

  final AchievementView view;

  @override
  ConsumerState<AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends ConsumerState<AchievementCard> {
  _ClaimPhase _phase = _ClaimPhase.idle;
  StreamSubscription<ClaimResult>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  AchievementView get _view => widget.view;

  Future<void> _claim() async {
    if (_phase == _ClaimPhase.sending || _phase == _ClaimPhase.validating) return;
    setState(() => _phase = _ClaimPhase.sending);
    final ClaimService service = ref.read(claimServiceProvider);
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (uid == null) throw ClaimException('Faça login para resgatar.');
      final String requestId = await service.createClaim(
        uid: uid,
        kind: 'achievement',
        refId: _view.achievement.id,
      );
      if (!mounted) return;
      setState(() => _phase = _ClaimPhase.validating);
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
          // Offline: permanece "validando"; o runner processa depois.
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
    final bool unlocked = _view.isUnlocked;
    final bool claimed = _view.isClaimed || _phase == _ClaimPhase.claimed;
    final bool claimable = _view.isClaimable && !claimed;
    final bool busy =
        _phase == _ClaimPhase.sending || _phase == _ClaimPhase.validating;
    final Color accent = unlocked ? AppColors.cyan : AppColors.textSecondary;

    return NeonPanel(
      accent: accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SvgPicture.string(
                AppAssets.iconForMetric(_view.achievement.metric),
                width: 34,
                height: 34,
              ),
              const Spacer(),
              if (!unlocked)
                SvgPicture.string(AppAssets.lockDimIconSvg, width: 18, height: 18)
              else if (claimed)
                const Icon(Icons.check_circle, color: AppColors.green, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _view.achievement.title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unlocked ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _view.achievement.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            '${_view.progress.progress.clamp(0, _view.achievement.target)}'
            ' / ${_view.achievement.target}',
            style: TextStyle(
              color: unlocked ? AppColors.cyan : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _view.achievement.target <= 0
                  ? 0
                  : (_view.progress.progress / _view.achievement.target)
                      .clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.textSecondary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                unlocked ? AppColors.cyan : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              SvgPicture.string(AppAssets.coinIconSvg, width: 14, height: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${_view.achievement.rewardCoins} COIN',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (claimable && !busy)
                _ClaimButton(onPressed: _claim)
              else if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Resgatar conquista',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: ShapeDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: AppColors.cyan),
              ),
            ),
            child: const Text(
              'RESGATAR',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
}
