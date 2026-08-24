import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('aceita e-mails válidos', () {
      expect(Validators.email('user@playhash.app'), isNull);
      expect(Validators.email('user.name+tag@sub.dominio.com'), isNull);
    });

    test('rejeita vazio ou inválido', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('sem-arroba'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('user @dominio.com'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('aceita senha com 8+ caracteres, letra e número', () {
      expect(Validators.password('abc12345'), isNull);
      expect(Validators.password('SenhaForte99'), isNull);
    });

    test('rejeita curta, sem letra ou sem número', () {
      expect(Validators.password('Ab1'), isNotNull); // curta
      expect(Validators.password('12345678'), isNotNull); // sem letra
      expect(Validators.password('abcdefgh'), isNotNull); // sem número
      expect(Validators.password(''), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('exige coincidência', () {
      expect(
        Validators.confirmPassword('abc12345', 'abc12345'),
        isNull,
      );
      expect(
        Validators.confirmPassword('abc12345', 'xyz99999'),
        isNotNull,
      );
      expect(Validators.confirmPassword('', 'abc12345'), isNotNull);
    });
  });

  group('Validators.displayName', () {
    test('aceita nomes entre 3 e 30 caracteres', () {
      expect(Validators.displayName('Ana'), isNull);
      expect(Validators.displayName('Jogador Neon'), isNull);
      expect(Validators.displayName('a' * 30), isNull);
    });

    test('rejeita curto, longo e vazio', () {
      expect(Validators.displayName('ab'), isNotNull);
      expect(Validators.displayName('a' * 31), isNotNull);
      expect(Validators.displayName('   '), isNotNull);
      expect(Validators.displayName(null), isNotNull);
    });
  });
}
