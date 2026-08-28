import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Coleta de recompensas OFFLINE (14.11) — check-in diário + crédito de
/// períodos de 5 min NÃO processados pelo runner.
///
/// Fluxo:
///  1. CHECK-IN DIÁRIO — `checkins/{uid}/{yyyy-MM-dd}` (idempotente; a escrita
///     pode ser negada pelas rules — ignorada, o estado real vem de
///     `power/{uid}.lastCheckinAt`).
///  2. STATUS DAS MÁQUINAS — ON se o último check-in tem < 24h
///     (`power/{uid}.lastCheckinAt`, fallback `wallets/{uid}.lastCheckinAt`).
///     OFF ⇒ não ganha nada offline. O status é espelhado em `power/{uid}`
///     para a UI (escrita não-fatal).
///  3. GANHOS — períodos de 5 min entre `lastAccumulatedAt` (máx. 24h atrás)
///     e agora cujo bloco NÃO foi finalizado pelo runner.
///     periodKey no formato EXATO do runner (`backend/src/processors/
///     closeBlocks.ts`): `String(floor(ms / blockIntervalMs))` — string
///     numérica epoch-based (NÃO é data ISO).
///     Fórmula: `blockRewardUnits × userPower ÷ networkPower` (BigInt floor,
///     mesma precisão do runner).
///  4. TRANSAÇÃO — soma `availableBalance` + `lifetimeEarned` (strings
///     decimais BigInt), avança `lastAccumulatedAt` (int ms) e grava o
///     espelho `REWARD_OFFLINE` no histórico `rewards/{uid}/items`.
///
/// Regras Firestore (14.11): o aumento de saldo do dono é limitado a
/// 1.500.000.000 unidades por coleta, `lifetimeEarned` deve crescer exatamente
/// o delta do saldo e `lastAccumulatedAt` deve ser estritamente crescente
/// (anti-replay).
class OfflineMiningService {
  OfflineMiningService._();

  /// Intervalo do bloco — ESPELHO do runner (`economy.blockIntervalMs`).
  static const int blockIntervalMs = 300000; // 5 min

  /// Janela máxima de cálculo (performance) e critério de check-in.
  static const int maxWindowMs = 24 * 3600 * 1000; // 24h

  /// Máximo de períodos verificados por coleta (24h / 5min).
  static const int maxPeriods = 288;

  /// Teto de unidades por coleta — ESPELHO da regra de aumento da wallet.
  static const int capUnitsPerCollect = 1500000000; // 1500 COIN

  /// Fallbacks (somente se a leitura falhar/campo ausente).
  static const int fallbackNetworkPower = 1000000; // 1M base units
  static const int fallbackBlockReward = 5000000; // 5 COIN base units

  /// Executa check-in diário + coleta offline.
  /// Retorna as unidades creditadas (0 = nada a coletar / máquinas OFF).
  /// Nunca lança: falhas (Firebase não inicializado em testes, rede, rules)
  /// retornam 0 silenciosamente — a coleta é best-effort.
  static Future<int> collectOfflineRewards() async {
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return 0; // Firebase não inicializado (ex.: testes) — best-effort.
    }
    if (uid == null) return 0;

    try {
      return await _collect(uid);
    } catch (_) {
      return 0; // falha silenciosa — nunca quebra a UI.
    }
  }

  static Future<int> _collect(String uid) async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();
    final nowMs = now.millisecondsSinceEpoch;

    // 1. CHECK-IN DIÁRIO (obrigatório para máquinas ON).
    final todayKey = _dateKey(now);
    final checkinRef = db.doc('checkins/$uid/$todayKey');
    try {
      await checkinRef.set({
        'uid': uid,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {/* ignora (já existe / sem permissão nas rules) */}

    // 2. STATUS DAS MÁQUINAS (ON/OFF) — lê o último check-in ANTES de gravar
    // o novo (senão o status seria sempre ON).
    final powerRef = db.doc('power/$uid');
    final powerSnap = await powerRef.get();
    final powerData = powerSnap.data();

    int? lastCheckinMs = _readIntMs(powerData?['lastCheckinAt']);
    if (lastCheckinMs == null) {
      final walletSnap0 = await db.doc('wallets/$uid').get();
      lastCheckinMs = _readIntMs(walletSnap0.data()?['lastCheckinAt']);
    }
    final isOnline =
        lastCheckinMs != null && (nowMs - lastCheckinMs) < maxWindowMs;

    // Atualiza status no power doc para UI (não-fatal: doc pode não existir).
    try {
      await powerRef.set({
        'machinesOn': isOnline,
        'lastCheckinAt': nowMs,
      }, SetOptions(merge: true));
    } catch (_) {/* sem power doc / sem permissão — segue o fluxo */}

    if (!isOnline) return 0; // Máquinas OFF: não ganha nada offline.

    // 3. CALCULAR GANHOS OFFLINE.
    final walletRef = db.doc('wallets/$uid');
    final walletSnap = await walletRef.get();
    final walletData = walletSnap.data();
    final lastAccumulatedMs =
        _readIntMs(walletData?['lastAccumulatedAt']) ?? nowMs;

    // Limita o cálculo a no máximo 24h atrás (performance).
    final startMs = lastAccumulatedMs < nowMs - maxWindowMs
        ? nowMs - maxWindowMs
        : lastAccumulatedMs;

    final userPower = _readIntMs(powerData?['totalPower']) ??
        ((_readIntMs(powerData?['permanentPower']) ?? 0) +
            (_readIntMs(powerData?['temporaryPower']) ?? 0));
    if (userPower <= 0) return 0;

    // Poder da rede: último bloco conhecido (fallback 1M base units).
    int networkPower = fallbackNetworkPower;
    try {
      final lastBlockSnap = await db
          .collection('blocks')
          .orderBy('periodKey', descending: true)
          .limit(1)
          .get();
      if (lastBlockSnap.docs.isNotEmpty) {
        networkPower = _readIntMs(lastBlockSnap.docs.first.data()['networkPower']) ??
            fallbackNetworkPower;
      }
    } catch (_) {
      networkPower = fallbackNetworkPower;
    }
    if (networkPower <= 0) return 0;

    // Recompensa por bloco (config/economy; fallback 5 COIN base units).
    int blockReward = fallbackBlockReward;
    try {
      final ecoSnap = await db.doc('config/economy').get();
      blockReward =
          _readIntMs(ecoSnap.data()?['blockRewardUnits']) ?? fallbackBlockReward;
    } catch (_) {
      blockReward = fallbackBlockReward;
    }
    if (blockReward <= 0) return 0;

    // Períodos de 5 min não processados pelo runner (formato epoch-based).
    final periodsToCheck = _generatePeriodKeys(startMs, nowMs);
    if (periodsToCheck.isEmpty) return 0;

    // Blocos já finalizados na janela (1 consulta; chaves numéricas de mesmo
    // comprimento ⇒ range lexicográfico == range numérico).
    final processedBlocks = await db
        .collection('blocks')
        .where('periodKey', isGreaterThanOrEqualTo: periodsToCheck.first)
        .where('periodKey', isLessThanOrEqualTo: periodsToCheck.last)
        .limit(300)
        .get();
    final processedSet = processedBlocks.docs.map((d) => d.id).toSet();

    // Fórmula: Reward × (UserPower ÷ NetworkPower) — BigInt floor (precisão
    // idêntica à do runner; double perderia precisão nas unidades mínimas).
    final rewardPerPeriod = BigInt.from(blockReward) *
            BigInt.from(userPower) ~/
            BigInt.from(networkPower);
    int periodsCount = 0;
    if (rewardPerPeriod > BigInt.zero) {
      for (final period in periodsToCheck) {
        if (!processedSet.contains(period)) periodsCount++;
      }
    }
    if (periodsCount <= 0) return 0;

    BigInt coinsEarned = rewardPerPeriod * BigInt.from(periodsCount);
    final cap = BigInt.from(capUnitsPerCollect);
    if (coinsEarned > cap) coinsEarned = cap; // teto da rule por coleta
    if (coinsEarned <= BigInt.zero) return 0;

    // 4. TRANSAÇÃO: ATUALIZAR SALDO + HISTÓRICO (tudo-ou-nada).
    await db.runTransaction((tx) async {
      final wSnapTx = await tx.get(walletRef);
      final wDataTx = wSnapTx.data();
      final currentBal =
          BigInt.tryParse('${wDataTx?['availableBalance'] ?? '0'}') ??
              BigInt.zero;
      final currentLife =
          BigInt.tryParse('${wDataTx?['lifetimeEarned'] ?? '0'}') ??
              BigInt.zero;

      tx.update(walletRef, {
        'availableBalance': (currentBal + coinsEarned).toString(),
        'lifetimeEarned': (currentLife + coinsEarned).toString(),
        'lastAccumulatedAt': nowMs,
      });

      tx.set(db.collection('rewards/$uid/items').doc(), {
        'type': 'REWARD_OFFLINE',
        'amount': coinsEarned.toString(),
        'currencyId': 'coins',
        'periods': periodsCount,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'completed',
      });
    });

    return coinsEarned.toInt();
  }

  /// Chave do dia (UTC local do device) — `yyyy-MM-dd` com zero-pad.
  static String _dateKey(Timestamp t) {
    final d = t.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Gera as chaves dos períodos de 5 min em [start, end).
  /// FORMATO EXATO DO RUNNER (`closeBlocks.ts`): `String(floor(ms / 300000))`
  /// — string numérica epoch-based (NÃO `YYYY-MM-DDTHH:mm`; o runner usa
  /// periodKey epoch-based e o match precisa ser exato).
  static List<String> _generatePeriodKeys(int startMs, int endMs) {
    final List<String> keys = [];
    var current = (startMs ~/ blockIntervalMs) * blockIntervalMs;
    while (current < endMs && keys.length < maxPeriods) {
      keys.add((current ~/ blockIntervalMs).toString());
      current += blockIntervalMs;
    }
    return keys;
  }

  /// Lê um valor temporal/numérico tolerante (int ms | num | string | Timestamp).
  /// O schema usa strings decimais (BigInt) e int-ms; versões antigas podem
  /// ter gravado Timestamp. Nunca lança.
  static int? _readIntMs(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    return null;
  }
}
