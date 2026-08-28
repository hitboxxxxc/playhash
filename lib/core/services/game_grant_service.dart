import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GrantException implements Exception {
  final String code;
  const GrantException(this.code);
  @override
  String toString() => code;
}

class GameGrantService {
  static int _i(Map<String, dynamic>? d, String k) {
    final Object? v = d?[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static Future<int> finishSession({
    required String gameId,
    required String gameDocPath,
    required int score,
    required Map<String, dynamic> breakdown,
    required int durationMs,
    required int grantedPower,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const GrantException('SEM_LOGIN');
    final db = FirebaseFirestore.instance;
    final powerRef = db.doc('power/$uid');
    final String sessionId =
        DateTime.now().microsecondsSinceEpoch.toString() + uid.substring(0, 4);

    int granted = 0;
    await db.runTransaction((tx) async {
      final eco = (await tx.get(db.doc('config/economy'))).data();
      final game = (await tx.get(db.doc(gameDocPath))).data();
      final power = (await tx.get(powerRef)).data();

      final int perGame = _i(game, 'powerCapPerSessionBaseUnits');
      final int globalCap = _i(eco, 'maxGamePowerPerSession');
      granted = grantedPower;
      if (perGame > 0 && granted > perGame) granted = perGame;
      if (globalCap > 0 && granted > globalCap) granted = globalCap;
      if (granted <= 0) throw const GrantException('SEM_RECOMPENSA');

      final int oldTemp = _i(power, 'temporaryPower');
      final int oldPerm = _i(power, 'permanentPower');
      final Timestamp now = Timestamp.now();
      final Timestamp exp = Timestamp.fromMillisecondsSinceEpoch(
          now.millisecondsSinceEpoch + 24 * 3600 * 1000);

      tx.set(db.doc('gameSessions/$sessionId'), {
        'uid': uid,
        'gameId': gameId,
        'clientRequestId': sessionId,
        'startedAt': now,
        'finishedAt': now,
        'status': 'finished',
        'score': score,
        'breakdown': breakdown,
        'durationMs': durationMs,
        'grantedPower': granted,
        'deviceGranted': true,
        'clientVersion': '1.0.0',
      });
      tx.set(powerRef, {
        'temporaryPower': oldTemp + granted,
        'permanentPower': oldPerm,
        'totalPower': oldPerm + oldTemp + granted,
        'temporaryPowerExpiresAt': exp,
        'lastGrantAt': now,
      }, SetOptions(merge: true));
    });
    return granted;
  }
}