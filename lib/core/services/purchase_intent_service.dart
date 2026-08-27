import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/collections.dart';
import '../../data/models/machine_catalog_model.dart';

/// Null-safe helper to extract active temporary power.
/// Returns 0 if power map is null, temp power expired, or fields missing.
int _activeTemporaryPower(Map<String, dynamic>? power) {
  if (power == null) return 0;
  final Object? exp = power['temporaryPowerExpiresAt'];
  final int temp = _intField(power, 'temporaryPower');
  if (exp is Timestamp &&
      exp.millisecondsSinceEpoch > DateTime.now().millisecondsSinceEpoch) {
    return temp;
  }
  return 0;
}

/// Null-safe int extraction from a map (tolerant: String/num).
int _intField(Map<String, dynamic>? data, String key) {
  final Object? v = data?[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
  }
  return 0;
}


/// Resultado de uma intent de compra observada (espelho de leitura — a
/// validação econômica é 100% do runner; o cliente nunca decide valores).
class PurchaseIntentResult {
  const PurchaseIntentResult({
    required this.status,
    this.failureCode,
    this.machineItemId,
  });

  /// 'pending' | 'done' | 'failed'.
  final String status;
  final String? failureCode;
  final String? machineItemId;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  static PurchaseIntentResult fromMap(Map<String, dynamic> data) =>
      PurchaseIntentResult(
        status: (data['status'] as String?) ?? 'pending',
        failureCode: data['failureCode'] as String?,
        machineItemId: data['machineItemId'] as String?,
      );
}

/// Resultado de uma intent de upgrade observada.
class MachineUpgradeIntentResult {
  const MachineUpgradeIntentResult({
    required this.status,
    this.failureCode,
    this.newLevel,
  });

  /// 'pending' | 'done' | 'failed'.
  final String status;
  final String? failureCode;
  final int? newLevel;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  static MachineUpgradeIntentResult fromMap(Map<String, dynamic> data) =>
      MachineUpgradeIntentResult(
        status: (data['status'] as String?) ?? 'pending',
        failureCode: data['failureCode'] as String?,
        newLevel: data['newLevel'] != null
            ? _intField(data, 'newLevel')
            : null,
      );
}

/// Contrato do repositório de intents de compra — permite fakes nos testes.
abstract interface class PurchaseIntentsRepositoryApi {
  /// Cria `purchaseIntents/{clientRequestId}` com EXATAMENTE os campos
  /// exigidos pelas rules: {uid, machineId, clientRequestId, createdAt,
  /// status:'pending'}. O doc id É o clientRequestId ⇒ retry offline
  /// reescreve o MESMO doc (idempotência; update é negado pelas rules).
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  });

  /// Lê o doc atual da intent (null se não existir).
  Future<PurchaseIntentResult?> readIntent(String clientRequestId);

  /// Observa a intent até o runner processar (done/failed).
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId);
}

/// Repositório de intents de compra (`purchaseIntents`).
class PurchaseIntentsRepository implements PurchaseIntentsRepositoryApi {
  PurchaseIntentsRepository({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _intents =>
      _db.collection(Collections.purchaseIntents);

  @override
  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  }) async {
    await _intents.doc(clientRequestId).set(<String, dynamic>{
      'uid': uid,
      'machineId': machineId,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  @override
  Future<PurchaseIntentResult?> readIntent(String clientRequestId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _intents.doc(clientRequestId).get();
    if (!snap.exists) return null;
    return PurchaseIntentResult.fromMap(snap.data()!);
  }

  @override
  Stream<PurchaseIntentResult> watchIntent(String clientRequestId) =>
      _intents.doc(clientRequestId).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                PurchaseIntentResult.fromMap(snap.data() ?? const <String, dynamic>{}),
          );
}

/// Repositório de intents de upgrade de máquina (`machineUpgradeIntents`).
class MachineUpgradeIntentsRepository {
  MachineUpgradeIntentsRepository({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _intents =>
      _db.collection('machineUpgradeIntents');

  Future<void> createIntent({
    required String clientRequestId,
    required String uid,
    required String machineId,
  }) async {
    await _intents.doc(clientRequestId).set(<String, dynamic>{
      'uid': uid,
      'machineId': machineId,
      'clientRequestId': clientRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Future<MachineUpgradeIntentResult?> readIntent(String clientRequestId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _intents.doc(clientRequestId).get();
    if (!snap.exists) return null;
    return MachineUpgradeIntentResult.fromMap(snap.data()!);
  }

  Stream<MachineUpgradeIntentResult> watchIntent(String clientRequestId) =>
      _intents.doc(clientRequestId).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                MachineUpgradeIntentResult.fromMap(
                    snap.data() ?? const <String, dynamic>{}),
          );
}

/// Falha de compra com mensagem SEGURA em PT-BR (sem vazar detalhes internos).
class PurchaseIntentException implements Exception {
  PurchaseIntentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serviço de intenção de compra da LOJA.
///
/// - clientRequestId = UUID v4 gerado no cliente e usado COMO DOC ID:
///   retry offline reenvia o mesmo doc (nunca duplica — idempotência);
/// - payload com EXATAMENTE os campos das rules (nada além);
/// - mensagens de erro seguras por failureCode do runner.
class PurchaseIntentService {
  PurchaseIntentService({PurchaseIntentsRepositoryApi? repository})
      : _repositoryOverride = repository;

  final PurchaseIntentsRepositoryApi? _repositoryOverride;
  final Random _random = Random.secure();

  PurchaseIntentsRepositoryApi get _repository =>
      _repositoryOverride ?? PurchaseIntentsRepository();

  /// Repositório de intents de upgrade.
  final MachineUpgradeIntentsRepository _upgradeRepository =
      MachineUpgradeIntentsRepository();

  /// UUID v4 próprio (sem dependência externa).
  String generateClientRequestId() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final String h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Cria a intent de compra com retry seguro (mesmo clientRequestId).
  Future<String> createIntent({
    required String uid,
    required String machineId,
    String? clientRequestId,
    int maxAttempts = 3,
  }) async {
    final String requestId = clientRequestId ?? generateClientRequestId();
    Object? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _repository.createIntent(
          clientRequestId: requestId,
          uid: uid,
          machineId: machineId,
        );
        return requestId;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          final PurchaseIntentResult? existing =
              await _repository.readIntent(requestId);
          if (existing != null) return requestId;
          throw PurchaseIntentException(
            'A compra não pôde ser enviada agora. Tente novamente em instantes.',
          );
        }
        if (e.code == 'unavailable' || e.code == 'network-request-failed') {
          lastError = e;
        } else {
          throw PurchaseIntentException(
            'Não foi possível enviar a compra. Tente novamente.',
          );
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw PurchaseIntentException(
      'Sem conexão para enviar a compra. Verifique a internet e tente '
      'de novo — nada foi cobrado. ($lastError)',
    );
  }

  /// Cria a intent de upgrade com retry seguro.
  Future<String> createUpgradeIntent({
    required String uid,
    required String machineId,
    String? clientRequestId,
    int maxAttempts = 3,
  }) async {
    final String requestId = clientRequestId ?? generateClientRequestId();
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _upgradeRepository.createIntent(
          clientRequestId: requestId,
          uid: uid,
          machineId: machineId,
        );
        return requestId;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          final MachineUpgradeIntentResult? existing =
              await _upgradeRepository.readIntent(requestId);
          if (existing != null) return requestId;
          throw PurchaseIntentException(
            'O upgrade não pôde ser enviado agora. Tente novamente.',
          );
        }
        if (e.code == 'unavailable' || e.code == 'network-request-failed') {
          // offline: retry com o MESMO requestId
        } else {
          throw PurchaseIntentException(
            'Não foi possível enviar o upgrade. Tente novamente.',
          );
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw PurchaseIntentException(
      'Sem conexão para enviar o upgrade. Verifique a internet e tente de novo.',
    );
  }

  /// Observa a intent de compra até done/failed.
  Stream<PurchaseIntentResult> watchResult(String clientRequestId) =>
      _repository.watchIntent(clientRequestId);

  /// Observa a intent de upgrade até done/failed.
  Stream<MachineUpgradeIntentResult> watchUpgradeResult(String clientRequestId) =>
      _upgradeRepository.watchIntent(clientRequestId);

  /// Mensagem SEGURA por código de falha do runner.
  static String failureMessage(String? code) {
    switch (code) {
      case 'INSUFFICIENT_BALANCE':
        return 'Saldo insuficiente para esta compra.';
      case 'MAX_PER_USER_REACHED':
        return 'Você já atingiu o limite deste modelo de máquina.';
      case 'INVALID_MACHINE':
      case 'MACHINE_DISABLED':
        return 'Esta máquina está indisponível no momento.';
      case 'DAILY_LIMIT_REACHED':
        return 'Limite diário de compras atingido. Tente amanhã.';
      case 'DUPLICATE_CLIENT_REQUEST_ID':
        return 'Este pedido já foi registrado. Verifique sua sala de máquinas.';
      case 'MACHINE_NOT_OWNED':
        return 'Você não possui esta máquina.';
      case 'MAX_LEVEL_REACHED':
        return 'Esta máquina já está no nível máximo.';
      default:
        return 'A operação não pôde ser concluída. Tente novamente mais tarde.';
    }
  }

  // ===== FUNÇÕES IMEDIATAS (DECISÃO DO DONO) =====

  /// Compra imediata de uma máquina via transação Firestore.
  Future<void> buyMachineNow({
    required String uid,
    required MachineCatalogModel machine,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    await db.runTransaction((Transaction tx) async {
      // ===== FASE A — SOMENTE LEITURAS =====
      final walletRef = db.doc('wallets/$uid');
      final powerRef = db.doc('power/$uid');
      final machineRef = db.collection('machines/$uid/items').doc();

      final walletSnap = await tx.get(walletRef);
      final powerSnap = await tx.get(powerRef);
      final machineSnap = await tx.get(machineRef);

      final wallet = walletSnap.data();
      final power = powerSnap.data();

      final int balance = _intField(wallet, 'availableBalance');
      final int price = machine.priceUnits.toInt();
      final int machinePower = machine.powerUnits.toInt();

      if (machineSnap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'JA_POSSUIDA',
          message: 'Machine already owned',
        );
      }
      if (balance < price) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'SALDO_INSUFICIENTE',
          message: 'Insufficient balance',
        );
      }

      final int permanent = _intField(power, 'permanentPower');
      final int activeTemp = _activeTemporaryPower(power);
      final int newPermanent = permanent + machinePower;

      // ===== FASE B — SOMENTE ESCRITAS =====
      tx.update(walletRef, {'availableBalance': balance - price});
      tx.set(machineRef, {
        'type': machine.id,
        'level': 1,
        'power': machinePower,
        'active': true,
        'purchasedAt': FieldValue.serverTimestamp(),
      });
      tx.update(powerRef, {
        'permanentPower': newPermanent,
        'totalPower': newPermanent + activeTemp,
      });
    });
  }

  /// Upgrade imediato de uma máquina via transação Firestore.
  Future<void> upgradeMachineNow({
    required String uid,
    required MachineCatalogModel machine,
    required int currentLevel,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    await db.runTransaction((Transaction tx) async {
      // ===== FASE A — LEITURAS =====
      final walletRef = db.doc('wallets/$uid');
      final powerRef = db.doc('power/$uid');
      final machineRef = db.collection('machines/$uid/items').doc();

      final walletSnap = await tx.get(walletRef);
      final powerSnap = await tx.get(powerRef);
      final machineSnap = await tx.get(machineRef);

      final machineData = machineSnap.data();
      if (machineData == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'NAO_POSSUIDA',
          message: 'Machine not owned',
        );
      }

      final int level = _intField(machineData, 'level');
      final int maxLevel = machine.maxLevel;
      if (level >= maxLevel) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'NIVEL_MAX',
          message: 'Max level reached',
        );
      }

      final int cost = _calculateUpgradeCost(machine, level);
      final int balance = _intField(walletSnap.data(), 'availableBalance');
      if (balance < cost) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'SALDO_INSUFICIENTE',
          message: 'Insufficient balance',
        );
      }

      final int oldPower = _intField(machineData, 'power');
      final int basePower = machine.powerUnits;
      final int newPower = (basePower * (100 + 25 * level)) ~/ 100; // nível+1, inteiro
      final int delta = newPower - oldPower;

      final power = powerSnap.data();
      final int permanent = _intField(power, 'permanentPower');
      final int activeTemp = _activeTemporaryPower(power);

      // ===== FASE B — ESCRITAS =====
      tx.update(walletRef, {'availableBalance': balance - cost});
      tx.update(machineRef, {'level': level + 1, 'power': newPower});
      tx.update(powerRef, {
        'permanentPower': permanent + delta,
        'totalPower': permanent + delta + activeTemp,
      });
    });
  }

  /// Calcula custo de upgrade: round(price * 0.75 * level) em base units.
  /// Mantém a mesma fórmula já usada na tela.
  int _calculateUpgradeCost(MachineCatalogModel machine, int currentLevel) {
    final int price = machine.priceUnits.toInt();
    final double factor = machine.upgradeCostFactor;
    return (price * factor * currentLevel).round();
  }

  // Helper methods removed - not used
}
