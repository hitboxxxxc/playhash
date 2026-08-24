/// Logo e ícones do PlayHash como strings SVG (sem assets externos).
/// Renderizados via flutter_svg (`SvgPicture.string`).
abstract final class AppAssets {
  /// Logotipo: hexágono neon com hash "#".
  static const String logoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <polygon points="32,3 58,17.5 58,46.5 32,61 6,46.5 6,17.5"
           fill="#0B0E1A" stroke="#00E5FF" stroke-width="3"/>
  <g stroke="#7C4DFF" stroke-width="4" stroke-linecap="round">
    <line x1="27" y1="21" x2="23" y2="43"/>
    <line x1="41" y1="21" x2="37" y2="43"/>
    <line x1="19" y1="28" x2="45" y2="28"/>
    <line x1="17" y1="36" x2="43" y2="36"/>
  </g>
</svg>''';

  /// Ícone de e-mail.
  static const String mailIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect x="3" y="5" width="18" height="14" rx="2"
        fill="none" stroke="#00E5FF" stroke-width="2"/>
  <path d="m4 7 8 6 8-6" fill="none" stroke="#00E5FF" stroke-width="2"/>
</svg>''';

  /// Ícone de cadeado (senha).
  static const String lockIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect x="5" y="10" width="14" height="10" rx="2"
        fill="none" stroke="#00E5FF" stroke-width="2"/>
  <path d="M8 10V7a4 4 0 0 1 8 0v3"
        fill="none" stroke="#00E5FF" stroke-width="2"/>
</svg>''';

  /// Avatar placeholder (silhueta neon) — usado enquanto não há foto.
  static const String avatarSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <circle cx="32" cy="32" r="30" fill="#0B0E1A"
          stroke="#00E5FF" stroke-width="2"/>
  <circle cx="32" cy="24" r="10" fill="none"
          stroke="#7C4DFF" stroke-width="3"/>
  <path d="M14 52c3-11 10-15 18-15s15 4 18 15"
        fill="none" stroke="#7C4DFF" stroke-width="3"
        stroke-linecap="round"/>
</svg>''';

  /// Ícone do Google (monocromático, neutro).
  static const String googleIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="10" fill="none" stroke="#FFFFFF" stroke-width="2"/>
  <path d="M17 12h-5v2.5h2.8A4 4 0 1 1 13 8.6l1.9-1.9A7 7 0 1 0 19 12Z"
        fill="#FFFFFF"/>
</svg>''';

  // ---- Ícones de MISSÕES/CONQUISTAS (artes próprias em código) ----------

  /// Gamepad (missões/conquistas de partidas).
  static const String gamepadIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M7 8h10a5 5 0 0 1 5 5v2a3 3 0 0 1-5.4 1.8L15 15H9l-1.6 1.8A3 3 0 0 1 2 15v-2a5 5 0 0 1 5-5Z"
        fill="none" stroke="#00E5FF" stroke-width="2" stroke-linejoin="round"/>
  <path d="M8 11v4M6 13h4" stroke="#00E5FF" stroke-width="2" stroke-linecap="round"/>
  <circle cx="16" cy="12" r="1.2" fill="#7C4DFF"/>
  <circle cx="18.5" cy="14" r="1.2" fill="#7C4DFF"/>
</svg>''';

  /// Troféu (missões/conquistas de pontos).
  static const String trophyIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M7 4h10v5a5 5 0 0 1-10 0V4Z" fill="none" stroke="#FFC400" stroke-width="2"/>
  <path d="M7 5H4v2a3 3 0 0 0 3 3M17 5h3v2a3 3 0 0 1-3 3"
        fill="none" stroke="#FFC400" stroke-width="2"/>
  <path d="M12 14v4M8 20h8" stroke="#FFC400" stroke-width="2" stroke-linecap="round"/>
</svg>''';

  /// Alvo/mira (missões/conquistas de abates).
  static const String targetIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="9" fill="none" stroke="#00E5FF" stroke-width="2"/>
  <circle cx="12" cy="12" r="5" fill="none" stroke="#7C4DFF" stroke-width="2"/>
  <circle cx="12" cy="12" r="1.6" fill="#00E5FF"/>
  <path d="M12 1v4M12 19v4M1 12h4M19 12h4"
        stroke="#00E5FF" stroke-width="2" stroke-linecap="round"/>
</svg>''';

  /// Raio (conquistas de poder H/s).
  static const String boltIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" fill="none"
        stroke="#00E5FF" stroke-width="2" stroke-linejoin="round"/>
</svg>''';

  /// Servidor/rig (conquistas de máquinas).
  static const String serverIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect x="4" y="3" width="16" height="7" rx="1.5" fill="none" stroke="#7C4DFF" stroke-width="2"/>
  <rect x="4" y="14" width="16" height="7" rx="1.5" fill="none" stroke="#7C4DFF" stroke-width="2"/>
  <circle cx="8" cy="6.5" r="1.2" fill="#00E5FF"/>
  <circle cx="8" cy="17.5" r="1.2" fill="#00E5FF"/>
  <path d="M13 6.5h4M13 17.5h4" stroke="#00E5FF" stroke-width="2" stroke-linecap="round"/>
</svg>''';

  /// Carrinho (missões de compra).
  static const String cartIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M3 4h2l2.4 11.2A2 2 0 0 0 9.4 17h8.2a2 2 0 0 0 2-1.6L21 8H6"
        fill="none" stroke="#00E5FF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="10" cy="20.5" r="1.5" fill="#7C4DFF"/>
  <circle cx="17" cy="20.5" r="1.5" fill="#7C4DFF"/>
</svg>''';

  /// Presente (conquistas de resgates).
  static const String giftIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect x="3" y="9" width="18" height="12" rx="1.5" fill="none" stroke="#FFC400" stroke-width="2"/>
  <path d="M3 13h18M12 9v12" stroke="#FFC400" stroke-width="2"/>
  <path d="M12 9c-4 0-5.5-1.5-5.5-3A2 2 0 0 1 9 4c2 0 3 2.5 3 5Zm0 0c4 0 5.5-1.5 5.5-3A2 2 0 0 0 15 4c-2 0-3 2.5-3 5Z"
        fill="none" stroke="#FFC400" stroke-width="2"/>
</svg>''';

  /// Moeda (recompensa) — dourada.
  static const String coinIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="9" fill="none" stroke="#FFC400" stroke-width="2"/>
  <circle cx="12" cy="12" r="5.5" fill="none" stroke="#FFC400" stroke-width="1.5"/>
  <path d="M12 8.5v7M9.8 10.2h4.4M9.8 13.8h4.4"
        stroke="#FFC400" stroke-width="1.5" stroke-linecap="round"/>
</svg>''';

  /// Cadeado esmaecido (conquista bloqueada).
  static const String lockDimIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect x="5" y="10" width="14" height="10" rx="2"
        fill="none" stroke="#9AA3C0" stroke-width="2"/>
  <path d="M8 10V7a4 4 0 0 1 8 0v3"
        fill="none" stroke="#9AA3C0" stroke-width="2"/>
</svg>''';

  /// Ícone por métrica de missão/conquista (fonte única dos cards).
  static String iconForMetric(String metric) {
    switch (metric) {
      case 'plays':
        return gamepadIconSvg;
      case 'max_score':
        return trophyIconSvg;
      case 'kills':
        return targetIconSvg;
      case 'buys':
        return cartIconSvg;
      case 'power':
        return boltIconSvg;
      case 'machines':
        return serverIconSvg;
      case 'claims':
        return giftIconSvg;
      default:
        return gamepadIconSvg;
    }
  }
}
