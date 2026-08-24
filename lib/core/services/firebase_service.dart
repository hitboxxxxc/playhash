import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Bootstrap centralizado do Firebase.
/// - Inicializa o app uma única vez.
/// - Configura o Firestore com cache/persistência local (100 MB).
///
/// Nenhum segredo vive aqui: a configuração Android vem exclusivamente do
/// `android/app/google-services.json` (fornecido pelo Firebase Console).
abstract final class FirebaseService {
  static bool _initialized = false;

  /// Cache/persistência offline do Firestore: ~100 MB.
  static const int firestoreCacheSizeBytes = 104857600;

  static bool get isInitialized => _initialized;

  /// Lança exceção se a configuração estiver ausente (ex.: sem
  /// google-services.json) — tratado pelo AuthGate com mensagem amigável.
  static Future<void> init() async {
    if (_initialized) return;
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: firestoreCacheSizeBytes,
    );
    _initialized = true;
  }
}
