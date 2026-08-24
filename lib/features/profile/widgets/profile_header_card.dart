import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';

/// Card chanfrado de cabeçalho do Perfil: avatar (foto se houver, senão
/// placeholder SVG), displayName, nível (placeholder "Nível 1") e
/// "Jogador desde [mês/ano]" derivado de `createdAt` do Firestore.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    this.displayName,
    this.photoUrl,
    this.createdAt,
  });

  final String? displayName;
  final String? photoUrl;
  final DateTime? createdAt;

  static const List<String> _monthNames = <String>[
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// "Jogador desde março de 2024" — ou apenas "Jogador" sem data conhecida.
  String get _memberSince {
    if (createdAt == null) return 'Jogador PlayHash';
    final DateTime date = createdAt!;
    return 'Jogador desde ${_monthNames[date.month - 1]} de ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 16,
          side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.45)),
        ),
        shadows: <BoxShadow>[
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.12),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            _Avatar(photoUrl: hasPhoto ? photoUrl : null),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (displayName == null || displayName!.isEmpty)
                        ? 'Jogador'
                        : displayName!,
                    style: AppTheme.neonLabel(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Placeholder honesto: progressão/XP ainda não implementados.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: ShapeDecoration(
                      color: AppColors.purple.withValues(alpha: 0.18),
                      shape: ChamferedBorder(
                        cut: 6,
                        side: BorderSide(
                          color: AppColors.purple.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Text(
                      'NÍVEL 1',
                      style: AppTheme.neonLabel(
                        fontSize: 11,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _memberSince,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: ChamferedBorder(
            cut: 14,
            side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.6)),
          ),
        ),
        child: ClipPath(
          clipper: _ChamferClipper(),
          child: photoUrl != null
              ? Image.network(
                  photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _PlaceholderAvatar(),
                )
              : const _PlaceholderAvatar(),
        ),
      ),
    );
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  const _PlaceholderAvatar();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: SvgPicture.string(AppAssets.avatarSvg),
      ),
    );
  }
}

class _ChamferClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const double c = 14;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(_ChamferClipper oldClipper) => false;
}
