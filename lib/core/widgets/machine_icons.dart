import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Ilustrações vetoriais PRÓPRIAS de máquinas (SVG gerados em código —
/// nenhuma arte copiada de referências externas). Traço branco recolorido
/// em runtime via [ColorFilter] conforme a raridade da máquina.
abstract final class MachineIcons {
  static const String _head =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="#FFFFFF" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">';

  static const String _tail = '</svg>';

  /// Variante 0 — rig de mineração com ventoinha.
  static const String rig =
      '$_head'
      '<rect x="5" y="4" width="14" height="16" rx="1.6"/>'
      '<circle cx="12" cy="10.4" r="3.4"/>'
      '<path d="M12 7v2.2M12 11.8V14M8.9 8.7l1.9 1.1M13.2 11l1.9 1.1"/>'
      '<path d="M7.4 17.6h9.2M7.4 19.4h5.4"/>'
      '$_tail';

  /// Variante 1 — rack de servidores.
  static const String server =
      '$_head'
      '<rect x="4.6" y="3.6" width="14.8" height="16.8" rx="1.6"/>'
      '<path d="M7.4 7.4h9.2M7.4 12h9.2M7.4 16.6h9.2"/>'
      '<circle cx="16.2" cy="7.4" r="0.5" fill="#FFFFFF"/>'
      '<circle cx="16.2" cy="12" r="0.5" fill="#FFFFFF"/>'
      '<circle cx="16.2" cy="16.6" r="0.5" fill="#FFFFFF"/>'
      '$_tail';

  /// Variante 2 — terminal/desktop.
  static const String terminal =
      '$_head'
      '<rect x="3.6" y="4.6" width="16.8" height="11" rx="1.6"/>'
      '<path d="M6.6 8.2l2.4 2-2.4 2M11.4 12.6h4"/>'
      '<path d="M9.4 19.4h5.2M12 15.6v3.8"/>'
      '$_tail';

  /// Ilustração de estado vazio da distribuição de poder — anel pontilhado.
  static const String donutEmpty =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="#FFFFFF" stroke-width="1.6" '
      'stroke-linecap="round" stroke-dasharray="2.4 2.4">'
      '<circle cx="12" cy="12" r="7.4"/>'
      '<circle cx="12" cy="12" r="3.4"/>'
      '</svg>';

  /// Retorna a variante de ícone pelo índice do slot (cicla os 3 desenhos).
  static String byIndex(int index) {
    switch (index % 3) {
      case 0:
        return rig;
      case 1:
        return server;
      default:
        return terminal;
    }
  }

  /// Render helper: SVG recolorizado.
  static Widget colored(
    String svg, {
    required Color color,
    double size = 40,
  }) {
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
