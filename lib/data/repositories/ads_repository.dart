import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';

/// Resultado de uma intent de recompensa por anúncio observada (espelho de
/// leitura — a validação econômica é 100% do runner; o cliente nunca decide
/// valores nem concede coin).
class AdRewardIntentResult {
  const AdRewardIntentResult({
    required this.status,
    this.failureCode,
  });

  /// 'pending' | 'done' | 'failed'.
  final String status;
  final String? failureCode;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';

  static AdRewardIntentResult fromMap(Map<String, dynamic> data) =>
      AdRewardIntentResult(
        status: (data['status'] as String?) ?? 'pending',
        failureCode: data['failureCode'] as String?,
      );
}

/// Recompensa de anúncio CONCEDIDA pelo runner (`adRewards/{id}`) — usada
/// pelo contador diário "X de Y hoje" da LOJA.
class AdRewardEntry {
  const AdRewardEntry({
    required this.id,
    required this.processedAtMs,
  });

  final String id;

  /// Timestamp (ms) do processamento — null enquanto pendente no espelho.
  final int? processedAtMs;

  static AdRewardEntry fromDoc(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final dynamic ts = snap.data()?['processedAt'];
    return AdRewardEntry(
      id: snap.id,
      processedAtMs: ts is Timestamp ? ts.millisecondsSinceEpoch : null,
    );
  }
}

/// Contrato do repositório de anúncios — permite fakes nos testes.
abstract interface class AdsRepositoryApi {
  /// Cria `adRewardIntents/{clientRequestId}` com EXATAMENTE os campos
  /// exigidos pelas rules: {uid, type:'rewarded', adUnitId, clientRequestId,
  /// createdAt, clientVersion}. O doc id É o clientRequestId ⇒ retry offline
  /// reescreve o MESMO doc (idempotência; update é negado pelas rules).
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String adUnitId,
    required String clientVersion,
  });

  /// Lê o doc atual da intent (null se não existir).
  Future<AdRewardIntentResult?> readIntent(String clientRequestId);

  /// Observa a intent até o runner processar (done/failed).
  Stream<AdRewardIntentResult> watchIntent(String clientRequestId);

  /// Stream das recompensas concedidas HOJE (periodKey = dia UTC) para o
  /// contador "X de Y hoje". Tolerante: erro ⇒ stream vazio.
  Stream<List<AdRewardEntry>> watchTodayRewards(String uid);

  /// Stream do limite diário de vídeos publicado em config/ads (autoridade
  /// do backend). Doc ausente ⇒ null (a UI usa fallback seguro).
  Stream<int?> watchDailyLimit();
}

/// Repositório de anúncios (`adRewardIntents` + `adRewards`).
class AdsRepository implements AdsRepositoryApi {
  AdsRepository({FirebaseFirestore? firestore}) : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _intents =>
      _db.collection(Collections.adRewardIntents);

  CollectionReference<Map<String, dynamic>> get _rewards =>
      _db.collection(Collections.adRewards);

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String adUnitId,
    required String clientVersion,
  }) async {
    await _intents.doc(clientRequestId).set(<String, dynamic>{
      'uid': uid,
      'type': 'rewarded',
      'adUnitId': adUnitId,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'clientVersion': clientVersion,
    });
  }

  @override
  Future<AdRewardIntentResult?> readIntent(String clientRequestId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _intents.doc(clientRequestId).get();
    if (!snap.exists) return null;
    return AdRewardIntentResult.fromMap(snap.data()!);
  }

  @override
  Stream<AdRewardIntentResult> watchIntent(String clientRequestId) =>
      _intents.doc(clientRequestId).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                AdRewardIntentResult.fromMap(
                    snap.data() ?? const <String, dynamic>{}),
          );

  @override
  Stream<List<AdRewardEntry>> watchTodayRewards(String uid) {
    try {
      // periodKey UTC do dia (mesma chave usada pelo runner).
      final DateTime now = DateTime.now().toUtc();
      final String periodKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return _rewards
          .where('uid', isEqualTo: uid)
          .where('periodKey', isEqualTo: periodKey)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> qs) => qs.docs
              .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                  AdRewardEntry.fromDoc(d))
              .toList())
          .handleError((Object _) => const <AdRewardEntry>[]);
    } catch (_) {
      // Firebase indisponível (ex.: testes) ⇒ stream vazio, nunca crash.
      return const Stream<List<AdRewardEntry>>.empty();
    }
  }

  @override
  Stream<int?> watchDailyLimit() {
    try {
      return _db.doc(Collections.configAds).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                (snap.data()?['rewarded']
                    as Map<String, dynamic>?)?['dailyLimit'] as int?,
          );
    } catch (_) {
      return const Stream<int?>.empty();
    }
  }
}
