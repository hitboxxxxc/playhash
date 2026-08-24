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
}
