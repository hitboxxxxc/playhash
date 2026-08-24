import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/claim_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../data/models/season_model.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum _TrackClaimPhase { idle, validating, claimed, failed }

/// Trilha do passe: scroll horizontal dos níveis 1..20 com DUAS linhas —
/// GRATUITO (claimable via ClaimService kind='seasonFree'; claimed ✓;
/// bloqueado por nível) e PREMIUM (cadeado + tooltip; Play Billing ainda
/// não existe ⇒ "ADQUIRIR PASSE" abre sheet informativa, sem promessas).
/// Nível oficial e claimed vêm SEMPRE do backend.
class PassTrack extends ConsumerStatefulWidget {
  const PassTrack({
    super.key,
    required this.season,
    required this.level,
    required this.claimedFree,
    required this.claimedPremium,
    required this.premiumActive,
  });

  final SeasonModel season;
  final int level;
  final Set<int> claimedFree;
  final Set<int> claimedPremium;
  final bool premiumActive;

  @override
  ConsumerState<PassTrack> createState() => _PassTrackState();
}

class _PassTrackState extends ConsumerState<PassTrack> {
  final Map<int, _TrackClaimPhase> _phases = <int, _TrackClaimPhase>{};
  final Map<int, StreamSubscription<ClaimResult>> _subs = <int, StreamSubscription<ClaimResult>>{};

  @override
  void dispose() {
    for (final StreamSubscription<ClaimResult> sub in _subs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _claimFree(int level) async {
    if (_phases[level] == _TrackClaimPhase.validating) return;
    setState(() => _phases[level] = _TrackClaimPhase.validating);
    final ClaimService service = ref.read(claimServiceProvider);
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (uid == null) throw ClaimException('Faça login para resgatar.');
      final String requestId = await service.createClaim(
        uid: uid,
        kind: 'seasonFree',
        refId: '${widget.season.id}:$level',
      );
      if (!mounted) return;
      _subs[level]?.cancel();
      _subs[level] = service.watchResult(requestId).listen(
        (ClaimResult r) {
          if (!mounted) return;
          if (r.isClaimed) {
            setState(() => _phases[level] = _TrackClaimPhase.claimed);
          } else if (r.isFailed) {
            setState(() => _phases[level] = _TrackClaimPhase.failed);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ClaimService.failureMessage(r.failureCode)),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        onError: (Object _) {
          // Offline: permanece validando; o runner processa quando possível.
        },
      );
    } on ClaimException catch (e) {
      if (!mounted) return;
      setState(() => _phases[level] = _TrackClaimPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _phases[level] = _TrackClaimPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar o resgate. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showPremiumSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'ADQUIRIR PASSE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Assinaturas chegam na próxima atualização.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.background,
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int maxLevel = widget.season.freeTrack.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: maxLevel,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final int level = index + 1;
              return _LevelColumn(
                level: level,
                freeReward:
                    index < widget.season.freeTrack.length ? widget.season.freeTrack[index] : null,
                premiumReward: index < widget.season.premiumTrack.length
                    ? widget.season.premiumTrack[index]
                    : null,
                unlocked: level <= widget.level,
                freeClaimed: widget.claimedFree.contains(level) ||
                    _phases[level] == _TrackClaimPhase.claimed,
                premiumClaimed: widget.claimedPremium.contains(level),
                phase: _phases[level] ?? _TrackClaimPhase.idle,
                onClaimFree: () => _claimFree(level),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          button: true,
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              onPressed: _showPremiumSheet,
              icon: const Icon(Icons.workspace_premium, size: 20),
              label: const Text('ADQUIRIR PASSE'),
            ),
          ),
        ),
      ],
    );
  }
}

class _LevelColumn extends StatelessWidget {
  const _LevelColumn({
    required this.level,
    required this.freeReward,
    required this.premiumReward,
    required this.unlocked,
    required this.freeClaimed,
    required this.premiumClaimed,
    required this.phase,
    required this.onClaimFree,
  });

  final int level;
  final SeasonReward? freeReward;
  final SeasonReward? premiumReward;
  final bool unlocked;
  final bool freeClaimed;
  final bool premiumClaimed;
  final _TrackClaimPhase phase;
  final VoidCallback onClaimFree;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Column(
        children: <Widget>[
          Text(
            'NÍVEL $level',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _TrackCell(
            reward: freeReward,
            accent: AppColors.cyan,
            label: 'GRATUITO',
            unlocked: unlocked,
            claimed: freeClaimed,
            phase: phase,
            onClaim: onClaimFree,
          ),
          const SizedBox(height: 8),
          _TrackCell(
            reward: premiumReward,
            accent: AppColors.gold,
            label: 'PREMIUM',
            unlocked: false, // premium sempre travado até Play Billing
            claimed: premiumClaimed,
            phase: _TrackClaimPhase.idle,
            onClaim: null,
          ),
        ],
      ),
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({
    required this.reward,
    required this.accent,
    required this.label,
    required this.unlocked,
    required this.claimed,
    required this.phase,
    required this.onClaim,
  });

  final SeasonReward? reward;
  final Color accent;
  final String label;
  final bool unlocked;
  final bool claimed;
  final _TrackClaimPhase phase;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final bool busy = phase == _TrackClaimPhase.validating;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: ShapeDecoration(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: accent.withValues(alpha: 0.4)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!unlocked)
              SvgPicture.string(NeonIcons.padlock, width: 26, height: 26,
                  colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn))
            else if (claimed)
              const Icon(Icons.check_circle, color: AppColors.green, size: 26)
            else if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2.5),
              )
            else
              Icon(
                Icons.monetization_on,
                color: accent,
                size: 26,
              ),
            const SizedBox(height: 6),
            Text(
              reward == null ? '—' : '${reward!.amountCoins} COIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: unlocked ? accent : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
            ),
            if (unlocked && !claimed && onClaim != null && !busy) ...<Widget>[
              const SizedBox(height: 6),
              SizedBox(
                height: 28,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                  onPressed: onClaim,
                  child: const Text('RESGATAR'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
