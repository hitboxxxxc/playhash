import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Escudos de LIGA — arte 100% própria em SVG (sem assets de terceiros).
/// Um único path de escudo com asa, colorido por tier e numerado com o
/// algarismo romano do tier (I..V), no estilo pixel/neon do app.
abstract final class LeagueShield {
  static const List<String> _roman = <String>['I', 'II', 'III', 'IV', 'V'];

  /// Escudo SVG próprio: corpo + asas + numeral do tier.
  static String svg(String colorHex, int tier) {
    final String roman = _roman[(tier - 1).clamp(0, 4)];
    return '''
<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <path d="M32 4 L56 12 V32 C56 46 46 56 32 60 C18 56 8 46 8 32 V12 Z"
        fill="#0B0E1A" stroke="$colorHex" stroke-width="3"/>
  <path d="M14 18 L8 12 V32 C8 40 11 47 16 52 Z" fill="$colorHex" opacity="0.55"/>
  <path d="M50 18 L56 12 V32 C56 40 53 47 48 52 Z" fill="$colorHex" opacity="0.55"/>
  <path d="M32 10 L50 16 V32 C50 43 42 51 32 55 C22 51 14 43 14 32 V16 Z"
        fill="$colorHex" opacity="0.22"/>
  <text x="32" y="40" font-family="monospace" font-size="20" font-weight="bold"
        fill="$colorHex" text-anchor="middle">$roman</text>
</svg>''';
  }

  /// Widget pronto do escudo.
  static Widget icon({
    required String colorHex,
    required int tier,
    double size = 48,
  }) {
    return SvgPicture.string(
      svg(colorHex, tier),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
