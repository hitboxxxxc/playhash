import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../constants/collections.dart';

/// Contrato de autenticação — permite fakes nos testes sem tocar no Firebase.
abstract interface class AuthServiceApi {
  Stream<User?> authStateChanges();
  Future<User?> currentUser();
  Future<User?> signInWithEmail(String email, String password);
  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required DateTime termsAcceptedAt,
  });
  Future<void> sendPasswordReset(String email);
  Future<User?> signInWithGoogle();
  Future<void> signOut();
}

/// Implementação Firebase da autenticação.
///
/// Segurança:
/// - Google Sign-In SEM client id hardcoded (configuração nativa via
///   google-services.json).
/// - `termsAcceptedAt` é OBRIGATÓRIO no registro (auditoria de aceite).
/// - Nenhum log contém e-mail, senha ou tokens.
class FirebaseAuthService implements AuthServiceApi {
  GoogleSignIn? _google;
  bool _googleInitialized = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<GoogleSignIn> _googleClient() async {
    final GoogleSignIn google = _google ??= GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize();
      _googleInitialized = true;
    }
    return google;
  }

  @override
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  @override
  Future<User?> currentUser() async => _auth.currentUser;

  @override
  Future<User?> signInWithEmail(String email, String password) async {
    final UserCredential cred =
        await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _touchLastLogin(cred.user);
    return cred.user;
  }

  @override
  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required DateTime termsAcceptedAt,
  }) async {
    // Aceite dos Termos é obrigatório — recusa registro sem timestamp.
    assert(
      termsAcceptedAt.isBefore(DateTime.now().toUtc().add(const Duration(minutes: 1))),
      'termsAcceptedAt é obrigatório no registro.',
    );

    final UserCredential cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final User? user = cred.user;
    if (user == null) return null;

    await user.updateDisplayName(displayName);
    await user.reload();

    await _ensureUserDoc(
      user,
      displayName: displayName,
      termsAcceptedAt: termsAcceptedAt,
    );
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  @override
  Future<User?> signInWithGoogle() async {
    final GoogleSignIn google = await _googleClient();
    final GoogleSignInAccount account = await google.authenticate();

    final String? idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Falha ao obter token do Google.',
      );
    }

    final UserCredential cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    await _ensureUserDoc(cred.user);
    return cred.user;
  }

  @override
  Future<void> signOut() async {
    if (_googleInitialized) {
      await (_google?.signOut() ?? Future<void>.value());
    }
    await _auth.signOut();
  }

  /// Atualiza apenas lastLoginAt (campo permitido nas rules de update).
  Future<void> _touchLastLogin(User? user) async {
    if (user == null) return;
    await _db
        .collection(Collections.users)
        .doc(user.uid)
        .set(<String, dynamic>{
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Garante o documento do usuário em users/{uid}.
  /// Campos restritos ao whitelist definido em firestore.rules.
  Future<void> _ensureUserDoc(
    User? user, {
    String? displayName,
    DateTime? termsAcceptedAt,
  }) async {
    if (user == null) return;
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection(Collections.users).doc(user.uid);

    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get();
    } on FirebaseException {
      // Offline: tenta o cache antes de desistir silenciosamente.
      snap = await ref.get(const GetOptions(source: Source.cache));
    }

    if (!snap.exists) {
      await ref.set(<String, dynamic>{
        'displayName': displayName ?? user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'settings': <String, dynamic>{},
        if (termsAcceptedAt != null)
          'termsAcceptedAt': Timestamp.fromDate(termsAcceptedAt.toUtc()),
      });
    } else {
      await _touchLastLogin(user);
    }
  }
}
