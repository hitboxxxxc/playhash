/// Validações locais de formulário (cliente). Mensagens em PT-BR.
/// Nenhuma regra econômica ou de segurança vive aqui — o cliente NÃO é
/// confiável; a autoridade é sempre o backend/Firestore rules.
abstract final class Validators {
  static final RegExp _emailRe = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final RegExp _letterRe = RegExp(r'[A-Za-z]');
  static final RegExp _digitRe = RegExp(r'\d');

  static String? email(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) return 'Informe seu e-mail.';
    if (!_emailRe.hasMatch(v)) return 'E-mail inválido.';
    return null;
  }

  static String? password(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Informe sua senha.';
    if (v.length < 8) return 'A senha deve ter ao menos 8 caracteres.';
    if (!_letterRe.hasMatch(v) || !_digitRe.hasMatch(v)) {
      return 'A senha deve conter letras e números.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Confirme sua senha.';
    if (v != original) return 'As senhas não coincidem.';
    return null;
  }

  static String? displayName(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) return 'Informe seu nome.';
    if (v.length < 3) return 'Nome muito curto (mínimo 3 caracteres).';
    if (v.length > 30) return 'Nome muito longo (máximo 30 caracteres).';
    return null;
  }
}
