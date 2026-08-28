import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OfflineCollectResult {
  final int coins;
  final int periods;
  final String reason;
  const OfflineCollectResult(this.coins, this.periods, this.reason);
}

class OfflineMiningService {
  static const int kDayMs = 24 * 3600 * 1000;
  static const int kPeriodMs = 5 * 60 * 1000;

  static String dateKey(Timestamp t) {
    final d = t.toDate();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // FORMATO EXATO DO RUNNER (closeBlocks.ts): docId == periodKey ==
  // String(floor(ms / blockIntervalMs)) — string numérica epoch-based.
  // (O formato ISO 'YYYY-MM-DDTHH:mm' nunca casaria com o docId do blocks.)
  static String periodKeyOf(int ms) {
    return (ms ~/ kPeriodMs).toString();
  }

  static int _i(Map<String, dynamic>? d, String k) {
    final Object? v = d?[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static Future<OfflineCollectResult> collect() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const OfflineCollectResult(0, 0, 'sem_login');
    final db = FirebaseFirestore.instance;
    final Timestamp now = Timestamp.now();

    // 1) check-in anterior ANTES de sobrescrever
    final userSnap = await db.doc('users/$uid').get();
    final Timestamp? prevCheckin =
        userSnap.data()?['lastCheckinAt'] as Timestamp?;

    // 2) check-in de agora (idempotente) + máquinas ON (FONTE ÚNICA: users)
    try {
      await db.doc('checkins/$uid/${dateKey(now)}').set(
          {'uid': uid, 'at': FieldValue.serverTimestamp()},
          SetOptions(merge: false));
    } catch (_) {}
    await db.doc('users/$uid')
        .set({'lastCheckinAt': now, 'machinesOn': true}, SetOptions(merge: true));

    // 3) poder elegível
    final powerSnap = await db.doc('power/$uid').get();
    final int perm = _i(powerSnap.data(), 'permanentPower');
    final int temp = _i(powerSnap.data(), 'temporaryPower');
    final Object? exp = powerSnap.data()?['temporaryPowerExpiresAt'];
    final int tempActive = (exp is Timestamp &&
            exp.millisecondsSinceEpoch > now.millisecondsSinceEpoch)
        ? temp
        : 0;
    final int userPower = perm + tempActive;
    if (userPower <= 0) return const OfflineCollectResult(0, 0, 'sem_poder');

    // 4) janela elegível: [max(lastAcc, now-24h), min(now, prevCheckin+24h)]
    int startMs = now.millisecondsSinceEpoch - kDayMs;
    final walletSnap = await db.doc('wallets/$uid').get();
    final Timestamp? lastAcc =
        walletSnap.data()?['lastAccumulatedAt'] as Timestamp?;
    if (lastAcc != null && lastAcc.millisecondsSinceEpoch > startMs) {
      startMs = lastAcc.millisecondsSinceEpoch;
    }
    int endMs = now.millisecondsSinceEpoch;
    if (prevCheckin != null) {
      final int limit = prevCheckin.millisecondsSinceEpoch + kDayMs;
      if (limit < endMs) endMs = limit;
    } else {
      endMs = startMs; // nunca fez check-in antes: nada a coletar
    }
    startMs = (startMs ~/ kPeriodMs) * kPeriodMs + kPeriodMs;
    endMs = (endMs ~/ kPeriodMs) * kPeriodMs;
    if (startMs > endMs) return const OfflineCollectResult(0, 0, 'nada');

    final List<String> keys = [];
    for (int t = startMs; t <= endMs && keys.length < 288; t += kPeriodMs) {
      keys.add(periodKeyOf(t));
    }
    if (keys.isEmpty) return const OfflineCollectResult(0, 0, 'nada');

    // 5) blocos já processados pelo runner (chunks de 10; docId == periodKey;
    //    SE o closeBlocks usar campo em vez de docId, trocar para where('periodKey'))
    final Set<String> processed = {};
    for (int i = 0; i < keys.length; i += 10) {
      final chunk = keys.sublist(i, i + 10 > keys.length ? keys.length : i + 10);
      try {
        final snap = await db
            .collection('blocks')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          processed.add(d.id);
        }
      } catch (_) {}
    }

    // 6) taxa: reward × userPower/networkPower (mesma fórmula do runner)
    final ecoSnap = await db.doc('config/economy').get();
    final int reward = _i(ecoSnap.data(), 'blockRewardUnits') > 0
        ? _i(ecoSnap.data(), 'blockRewardUnits')
        : 5000000;
    int networkPower = 0;
    try {
      final lastBlocks = await db
          .collection('blocks')
          .orderBy('periodKey', descending: true)
          .limit(1)
          .get();
      if (lastBlocks.docs.isNotEmpty) {
        networkPower = _i(lastBlocks.docs.first.data(), 'networkPower');
      }
    } catch (_) {}
    if (networkPower <= 0) networkPower = userPower;

    int coins = 0;
    int periods = 0;
    for (final k in keys) {
      if (processed.contains(k)) continue;
      final int r = (reward * (userPower / networkPower)).floor();
      if (r > 0) {
        coins += r;
        periods++;
      }
    }
    if (coins <= 0) return const OfflineCollectResult(0, 0, 'nada');

    // 7) crédito (transação; regra exige lastAccumulatedAt crescente + lifetime+=delta)
    await db.runTransaction((tx) async {
      final wRef = db.doc('wallets/$uid');
      final w = (await tx.get(wRef)).data();
      final int bal = _i(w, 'availableBalance');
      final int life = _i(w, 'lifetimeEarned');
      tx.set(wRef, {
        'availableBalance': bal + coins,
        'lifetimeEarned': life + coins,
        'lastAccumulatedAt': now,
      }, SetOptions(merge: true));
      tx.set(db.collection('rewards/$uid/items').doc(), {
        'type': 'REWARD_OFFLINE',
        'amount': coins,
        'periods': periods,
        'createdAt': now,
        'periodFrom': keys.first,
        'periodTo': keys.last,
      });
    });
    return OfflineCollectResult(coins, periods, 'ok');
  }
}
