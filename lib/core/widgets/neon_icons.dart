/// Ícones vetoriais próprios do PlayHash (SVG gerados em código — NENHUMA
/// arte copiada de referências externas). Todos usam traço branco e são
/// recoloridos em runtime via [ColorFilter] pelo consumidor.
abstract final class NeonIcons {
  static const String _head =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="#FFFFFF" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round">';

  static const String _tail = '</svg>';

  /// HOME — casa com telhado chanfrado.
  static const String home =
      '$_head'
      '<path d="M4 11.2 12 4l8 7.2V19a1 1 0 0 1-1 1h-4.4v-5.4h-5.2V20H5a1 1 0 0 1-1-1z"/>'
      '$_tail';

  /// JOGAR — gamepad com direcional e botões.
  static const String gamepad =
      '$_head'
      '<rect x="2.6" y="7.6" width="18.8" height="9.2" rx="4.6"/>'
      '<path d="M7.2 10.4v3.6M5.4 12.2H9"/>'
      '<circle cx="15.6" cy="10.9" r="0.6" fill="#FFFFFF"/>'
      '<circle cx="18" cy="13.3" r="0.6" fill="#FFFFFF"/>'
      '$_tail';

  /// MINERAÇÃO — picareta.
  static const String pickaxe =
      '$_head'
      '<path d="M4.5 20 13 9.5"/>'
      '<path d="M8.2 4.6c4.4-.9 9.3 1.4 11.4 5.6"/>'
      '<path d="M8.2 4.6l1.6 2M19.6 10.2l-2.4-.9"/>'
      '$_tail';

  /// LOJA — carrinho de compras.
  static const String cart =
      '$_head'
      '<path d="M3 4.4h2.2l2.3 10.8h10l2.3-8H6.1"/>'
      '<circle cx="9.4" cy="19.2" r="1.5"/>'
      '<circle cx="16.6" cy="19.2" r="1.5"/>'
      '$_tail';

  /// PERFIL — pessoa.
  static const String person =
      '$_head'
      '<circle cx="12" cy="8.2" r="3.6"/>'
      '<path d="M5 20c.4-3.6 3.3-5.4 7-5.4s6.6 1.8 7 5.4"/>'
      '$_tail';

  /// ENERGIA/PODER — raio.
  static const String bolt =
      '$_head'
      '<path d="M13.2 2.6 5 13.4h5.4L10.8 21.4 19 10.6h-5.4z"/>'
      '$_tail';

  /// MOEDA — círculo com núcleo.
  static const String coin =
      '$_head'
      '<circle cx="12" cy="12" r="8.4"/>'
      '<circle cx="12" cy="12" r="4.6"/>'
      '$_tail';

  /// ESCUDO — progressão de liga.
  static const String shield =
      '$_head'
      '<path d="M12 3 5 5.8v5.3c0 4.6 3 7.9 7 9.9 4-2 7-5.3 7-9.9V5.8z"/>'
      '$_tail';

  /// CADEADO — slot travado.
  static const String padlock =
      '$_head'
      '<rect x="5.6" y="10.6" width="12.8" height="9.2" rx="1.6"/>'
      '<path d="M8.6 10.6V8.2a3.4 3.4 0 0 1 6.8 0v2.4"/>'
      '$_tail';

  /// RELÓGIO — contagem/próximo bloco.
  static const String clock =
      '$_head'
      '<circle cx="12" cy="12" r="8.4"/>'
      '<path d="M12 7.4V12l3.2 2"/>'
      '$_tail';

  /// TROFÉU — ranking.
  static const String trophy =
      '$_head'
      '<path d="M7.4 4h9.2v4.2a4.6 4.6 0 0 1-9.2 0z"/>'
      '<path d="M7.4 5.2H4.6a2.9 2.9 0 0 0 3 3.6M16.6 5.2h2.8a2.9 2.9 0 0 1-3 3.6"/>'
      '<path d="M12 12.8v3.4M8.6 20h6.8M10 16.2h4"/>'
      '$_tail';

  /// CHIP — poder das máquinas.
  static const String chip =
      '$_head'
      '<rect x="6.4" y="6.4" width="11.2" height="11.2" rx="1.6"/>'
      '<rect x="10" y="10" width="4" height="4"/>'
      '<path d="M9.2 6.4V3.4M14.8 6.4V3.4M9.2 20.6v-3M14.8 20.6v-3M6.4 9.2H3.4M6.4 14.8H3.4M20.6 9.2h-3M20.6 14.8h-3"/>'
      '$_tail';

  /// GLOBO — poder total da rede.
  static const String globe =
      '$_head'
      '<circle cx="12" cy="12" r="8.4"/>'
      '<ellipse cx="12" cy="12" rx="3.8" ry="8.4"/>'
      '<path d="M3.8 12h16.4"/>'
      '$_tail';

  /// USUÁRIOS — participação.
  static const String users =
      '$_head'
      '<circle cx="9" cy="8.6" r="3"/>'
      '<path d="M3.4 19c.4-3 2.7-4.6 5.6-4.6s5.2 1.6 5.6 4.6"/>'
      '<circle cx="16.6" cy="9.4" r="2.4"/>'
      '<path d="M15.4 14.6c2.6.1 4.6 1.5 5.2 4"/>'
      '$_tail';

  /// SINO — notificações.
  static const String bell =
      '$_head'
      '<path d="M6.2 16.2v-5.4a5.8 5.8 0 0 1 11.6 0v5.4l1.6 2.6H4.6z"/>'
      '<path d="M10 20.4a2.1 2.1 0 0 0 4 0"/>'
      '$_tail';

  /// ENGRENAGEM — configurações.
  static const String gear =
      '$_head'
      '<circle cx="12" cy="12" r="3.1"/>'
      '<path d="M12 3v2.6M12 18.4V21M3 12h2.6M18.4 12H21M5.6 5.6l1.9 1.9M16.5 16.5l1.9 1.9M18.4 5.6l-1.9 1.9M7.5 16.5l-1.9 1.9"/>'
      '$_tail';

  /// INFORMAÇÃO — disclaimers.
  static const String info =
      '$_head'
      '<circle cx="12" cy="12" r="8.4"/>'
      '<path d="M12 11v5"/><circle cx="12" cy="8" r="0.5" fill="#FFFFFF"/>'
      '$_tail';
}
