import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PurchaseException implements Exception {
  final String code;
  const PurchaseException(this.code);
  @override
  String toString() => code;
}

class MachineShopService {
  static int _readInt(Map<String, dynamic>? data, String key) {
    final Object? v = data?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final s = v.trim();
      return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
    }
    return 0;
  }

  static int _activeTemp(Map<String, dynamic>? p) {
    if (p == null) return 0;
    final Object? exp = p['temporaryPowerExpiresAt'];
    final int temp = _readInt(p, 'temporaryPower');
    if (exp is Timestamp &&
        exp.millisecondsSinceEpoch > DateTime.now().millisecondsSinceEpoch) {
      return temp;
    }
    return 0;
  }

  static Future<void> buyMachine({
    required String machineId,
    required String name,
    required int priceCoins,
    required int powerBase,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const PurchaseException('SEM_LOGIN');
    final db = FirebaseFirestore.instance;
    final walletRef = db.doc('wallets/$uid');
    final machineRef = db.doc('machines/$uid/items/$machineId');
    final powerRef = db.doc('power/$uid');

    await db.runTransaction((tx) async {
      // ===== LEITURAS =====
      final wallet = (await tx.get(walletRef)).data();
      final power = (await tx.get(powerRef)).data();
      final exists = (await tx.get(machineRef)).exists;

      if (exists) throw const PurchaseException('JA_POSSUIDA');
      final int balance = _readInt(wallet, 'availableBalance');
      final int price = priceCoins * 1000000;
      if (balance < price) throw const PurchaseException('SALDO_INSUFICIENTE');

      final int permanent = _readInt(power, 'permanentPower');
      final int temp = _activeTemp(power);

      // ===== ESCRITAS =====
      tx.set(walletRef, {'availableBalance': balance - price},
          SetOptions(merge: true));
      tx.set(machineRef, {
        'type': machineId,
        'name': name,
        'level': 1,
        'power': powerBase,
        'active': true,
        'purchasedAt': FieldValue.serverTimestamp(),
      });
      tx.set(powerRef, {
        'permanentPower': permanent + powerBase,
        'totalPower': permanent + powerBase + temp,
      }, SetOptions(merge: true));
    });
  }

  static Future<void> upgradeMachine({
    required String machineId,
    required int priceCoins,
    required int powerBase,
    required int maxLevel,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const PurchaseException('SEM_LOGIN');
    final db = FirebaseFirestore.instance;
    final walletRef = db.doc('wallets/$uid');
    final machineRef = db.doc('machines/$uid/items/$machineId');
    final powerRef = db.doc('power/$uid');

    await db.runTransaction((tx) async {
      // ===== LEITURAS =====
      final wallet = (await tx.get(walletRef)).data();
      final power = (await tx.get(powerRef)).data();
      final machine = (await tx.get(machineRef)).data();

      if (machine == null) throw const PurchaseException('NAO_POSSUIDA');
      final int level = _readInt(machine, 'level');
      if (level >= maxLevel) throw const PurchaseException('NIVEL_MAX');

      final int cost = ((priceCoins * 75 ~/ 100) * level) * 1000000;
      final int balance = _readInt(wallet, 'availableBalance');
      if (balance < cost) throw const PurchaseException('SALDO_INSUFICIENTE');

      final int oldPower = _readInt(machine, 'power');
      final int newPower = (powerBase * (100 + 25 * level)) ~/ 100;
      final int delta = newPower - oldPower;

      final int permanent = _readInt(power, 'permanentPower');
      final int temp = _activeTemp(power);

      // ===== ESCRITAS =====
      tx.set(walletRef, {'availableBalance': balance - cost},
          SetOptions(merge: true));
      tx.update(machineRef, {'level': level + 1, 'power': newPower});
      tx.set(powerRef, {
        'permanentPower': permanent + delta,
        'totalPower': permanent + delta + temp,
      }, SetOptions(merge: true));
    });
  }
}