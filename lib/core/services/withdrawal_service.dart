import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/payout_config.dart';
import '../constants/collections.dart';
import 'payout/faucetpay_provider.dart';
import 'payout/manual_provider.dart';
import 'payout/payout_provider.dart';

// ---- PARÂMETROS LOCAIS (12.18 — config local; exibição derivada) -----------

/// Unidades mínimas por COIN (padrão do app): 1 COIN = 1e6 units.
final BigInt kUnitsPerCoin = BigInt.from(1000000);

// ---- MENSAGENS SEGURAS ------------------------------------------------------

/// Mensagem SEGURA em PT-BR por errorCode CANÔNICO. SEM mensagem de cooldown
/// (12.18: trava de 24h removida). Detalhes técnicos ficam só no log local.
String withdrawalErrorMessage(String? errorCode) {
  switch (errorCode) {
    case 'INSUFFICIENT_BALANCE':
      return 'Saldo disponível insuficiente para este saque.';
    case 'BELOW_MIN':
    case 'AMOUNT_TOO_LOW':
      return 'Valor abaixo do mínimo permitido.';
    case 'INVALID_AMOUNT':
      return 'Valor inválido para o saque.';
    case 'EMAIL_INVALID':
    case 'INVALID_ADDRESS':
      return 'Destino inválido para o saque.';
    case 'INVALID_EMAIL':
      return 'E-mail da FaucetPay inválido.';
    case 'EMAIL_NOT_FOUND':
    case 'DESTINO_NAO_VINCULADO':
      return 'Este e-mail/endereço não está vinculado a uma conta '
          'FaucetPay. Use o endereço LTC da sua FaucetPay.';
    case 'INSUFFICIENT_PROVIDER_BALANCE':
      return 'Provedor temporariamente sem saldo. Tente mais tarde.';
    case 'RATE_LIMIT':
      return 'Muitas solicitações ao provedor. Tente mais tarde.';
    case 'INVALID_API_KEY':
      return 'Pagamento temporariamente indisponível. Tente novamente mais '
          'tarde.';
    case 'PROVIDER_ERROR':
      return 'Provedor de pagamento temporariamente indisponível. '
          'Tente novamente mais tarde.';
    default:
      return 'Não foi possível concluir o saque. O valor foi estornado ao '
          'saldo disponível.';
  }
}

/// Exceção de saque com mensagem segura.
class WithdrawalException implements Exception {
  WithdrawalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Máscara segura de E-MAIL p/ exibição local: 2 primeiros caracteres do
/// local + '***@' + domínio (espelha maskEmail do backend). O e-mail
/// completo NUNCA é exibido em UI/histórico.
String maskEmail(String email) {
  final int at = email.indexOf('@');
  if (at <= 0) return '*' * email.length.clamp(0, 8);
  final String local = email.substring(0, at);
  final String domain = email.substring(at + 1);
  final String prefix = local.substring(0, local.length < 2 ? local.length : 2);
  return '$prefix***@$domain';
}

/// Regex de e-mail (formato básico; a autoridade é o provedor).
final RegExp kDestinationEmailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Validação LOCAL leve do e-mail FaucetPay (aviso apenas).
bool isValidDestinationEmail(String email) {
  final String v = email.trim();
  return v.length >= 6 && v.length <= 254 && kDestinationEmailRe.hasMatch(v);
}

// ---- DESTINO DUPLO (12.22): e-mail OU endereço LTC vinculado -----------------

/// Endereço LTC legado (Base58, P2PKH 'L' / P2SH 'M').
final RegExp kLtcLegacyAddressRe = RegExp(r'^(L|M)[1-9A-HJ-NP-Za-km-z]{25,33}$');

/// Endereço LTC bech32 (segwit, ex.: ltc1q...).
final RegExp kLtcBech32AddressRe = RegExp(r'^ltc1[0-9a-z]{6,}$');

/// Tipo de destino detectado por [detectDestinationType].
enum DestinationType { email, ltcAddress }

/// Detecta o tipo do destino (12.22): e-mail OU endereço LTC (legado ou
/// bech32). Retorna null quando nenhum dos dois formatos casa.
DestinationType? detectDestinationType(String value) {
  final String v = value.trim();
  if (v.isEmpty) return null;
  if (kDestinationEmailRe.hasMatch(v)) return DestinationType.email;
  if (kLtcLegacyAddressRe.hasMatch(v) || kLtcBech32AddressRe.hasMatch(v)) {
    return DestinationType.ltcAddress;
  }
  return null;
}

/// Validação LOCAL leve do destino DUPLO (e-mail ou endereço LTC).
bool isValidDestination(String value) =>
    detectDestinationType(value) != null;

/// Máscara segura do DESTINO p/ exibição (12.22):
///  - e-mail: 2 primeiros + '***@' + domínio ([maskEmail]);
///  - endereço LTC: 4 primeiros + '…' + 4 últimos.
/// O valor completo NUNCA é exibido em UI/histórico.
String maskDestination(String value) {
  final String v = value.trim();
  if (detectDestinationType(v) == DestinationType.ltcAddress) {
    if (v.length <= 8) return '*' * v.length;
    return '${v.substring(0, 4)}…${v.substring(v.length - 4)}';
  }
  return maskEmail(v);
}

/// Resultado FINAL do saque processado NO CLIENTE (12.18/12.20).
class WithdrawalOutcome {
  const WithdrawalOutcome({
    required this.status,
    this.errorCode,
    this.reference,
    this.detail,
  });

  /// 'completed' | 'failed' | 'pending' (modo MANUAL — aguarda operador).
  final String status;
  final String? errorCode;

  /// providerReference MASCARADA p/ exibição (ex.: "FP-123…4567").
  final String? reference;

  /// Detalhe técnico CURTO e SEGURO (sem segredo) p/ exibição na UI.
  final String? detail;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';
}

// ---- ABSTRAÇÕES (testáveis sem Firebase/rede) -------------------------------

/// Ledger da carteira — operações ATÔMICAS em `wallets/{uid}`.
///
/// INVARIANTE ANTI-INFLAÇÃO (rules 12.18): disponível+pendente NUNCA aumenta
/// pelo cliente. Reserva mantém a soma; conclusão DIMINUI; estorno mantém.
abstract interface class WalletLedger {
  /// Reserva [amountUnits]: available −= amount, pending += amount.
  /// Retorna false se saldo disponível insuficiente (doc ausente conta como 0).
  Future<bool> reserve({required String uid, required BigInt amountUnits});

  /// Conclusão: pending −= amount (total DIMINUI — dinheiro saiu de verdade).
  Future<void> conclude({required String uid, required BigInt amountUnits});

  /// Estorno INTEGRAL: pending −= amount E available += amount (soma volta).
  Future<void> refund({required String uid, required BigInt amountUnits});
}

/// Registro de saques (`withdrawals/{clientRequestId}`) escrito pelo cliente.
abstract interface class WithdrawalRecords {
  /// Doc existente para o id (idempotência) ou null.
  Future<Map<String, dynamic>?> findByClientRequestId(String clientRequestId);

  /// Grava o registro com doc id = clientRequestId (create-only nas rules).
  Future<void> write({
    required String clientRequestId,
    required Map<String, dynamic> data,
  });
}

BigInt _toBigInt(Object? value) {
  if (value is int) return BigInt.from(value);
  if (value is num) return BigInt.from(value.toInt());
  if (value is String) {
    final BigInt? parsed = BigInt.tryParse(value);
    if (parsed != null) return parsed;
    final double? asDouble = double.tryParse(value);
    if (asDouble != null) return BigInt.from(asDouble.toInt());
  }
  return BigInt.zero;
}

/// Implementação Firestore do ledger — transações em `wallets/{uid}`.
/// Saldos serializados como STRING decimal (mesmo formato do backend).
class FirestoreWalletLedger implements WalletLedger {
  FirestoreWalletLedger({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _walletDoc(String uid) =>
      _db.collection(Collections.wallets).doc(uid);

  @override
  Future<bool> reserve({
    required String uid,
    required BigInt amountUnits,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _walletDoc(uid);
    final bool? ok = await _db.runTransaction<bool?>((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) return false; // sem carteira ⇒ sem saldo
      final Map<String, dynamic> data = snap.data()!;
      final BigInt available = _toBigInt(data['availableBalance']);
      if (available < amountUnits) return false; // SALDO_INSUFICIENTE
      tx.update(ref, <String, dynamic>{
        'availableBalance': (available - amountUnits).toString(),
        'pendingBalance': (_toBigInt(data['pendingBalance']) + amountUnits)
            .toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    return ok ?? false;
  }

  @override
  Future<void> conclude({
    required String uid,
    required BigInt amountUnits,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _walletDoc(uid);
    await _db.runTransaction<void>((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      tx.update(ref, <String, dynamic>{
        'pendingBalance':
            (_toBigInt(data['pendingBalance']) - amountUnits).toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> refund({
    required String uid,
    required BigInt amountUnits,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _walletDoc(uid);
    await _db.runTransaction<void>((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      tx.update(ref, <String, dynamic>{
        'pendingBalance':
            (_toBigInt(data['pendingBalance']) - amountUnits).toString(),
        'availableBalance':
            (_toBigInt(data['availableBalance']) + amountUnits).toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

/// Implementação Firestore dos registros de saque.
class FirestoreWithdrawalRecords implements WithdrawalRecords {
  FirestoreWithdrawalRecords({FirebaseFirestore? firestore})
      : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String clientRequestId) =>
      _db.collection(Collections.withdrawals).doc(clientRequestId);

  @override
  Future<Map<String, dynamic>?> findByClientRequestId(
    String clientRequestId,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _doc(clientRequestId).get();
      return snap.exists ? snap.data() : null;
    } on Exception catch (e) {
      developer.log('withdrawal record lookup error type=${e.runtimeType}',
          name: 'WithdrawalService');
      return null;
    }
  }

  @override
  Future<void> write({
    required String clientRequestId,
    required Map<String, dynamic> data,
  }) async {
    await _doc(clientRequestId).set(data);
  }
}

// ---- SERVIÇO ----------------------------------------------------------------

/// Serviço de SAQUE NO CLIENTE (decisão do dono, 12.18):
///
///   reserva (transação) → payout FaucetPay → conclusão OU estorno integral
///
/// - Idempotência por clientRequestId: o MESMO id nunca é reenviado ao
///   provedor (registro existente ⇒ resultado retornado sem novo payout);
/// - SEM retry automático do payout;
/// - SEM cooldown 24h;
/// - Regra anti-inflação garantida pelas rules + invariantes do ledger.
class WithdrawalService {
  WithdrawalService({
    PayoutProvider? provider,
    WalletLedger? ledger,
    WithdrawalRecords? records,
  })  : _providerOverride = provider,
        _ledgerOverride = ledger,
        _recordsOverride = records;

  final PayoutProvider? _providerOverride;
  final WalletLedger? _ledgerOverride;
  final WithdrawalRecords? _recordsOverride;

  final Random _random = Random.secure();

  PayoutProvider get _provider =>
      _providerOverride ?? _defaultProvider;

  WalletLedger get _ledger => _ledgerOverride ?? FirestoreWalletLedger();

  WithdrawalRecords get _records =>
      _recordsOverride ?? FirestoreWithdrawalRecords();

  static PayoutProvider? _cachedDefaultProvider;

  /// Provider padrão conforme [kPayoutMode] (12.20):
  ///  - 'auto'   ⇒ FaucetPay real (chave via --dart-define ou config local
  ///    gitignored);
  ///  - 'manual' ⇒ [ManualProvider] (handoff p/ o operador; sem rede).
  /// Instanciado sob demanda.
  static PayoutProvider get _defaultProvider =>
      _cachedDefaultProvider ??= (kPayoutMode == 'manual'
          ? ManualProvider()
          : FaucetPayProvider());

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

  /// Executa o fluxo completo do saque e devolve o resultado FINAL.
  ///
  /// [amountCoins] deve ser um inteiro dentro de
  /// [kMinWithdrawCoins..kMaxPerWithdrawalCoins]. Recebido em litoshi:
  /// `(amountCoins − kFeeCoins) × kLitoshiPerCoin` (aritmética inteira §20).
  Future<WithdrawalOutcome> withdraw({
    required String uid,
    required int amountCoins,
    required String destination,
    String? clientRequestId,
  }) async {
    // --- validação local (mensagens seguras) ---
    if (amountCoins < kMinWithdrawCoins) {
      throw WithdrawalException(
        'Valor abaixo do mínimo ($kMinWithdrawCoins COIN).',
      );
    }
    if (amountCoins > kMaxPerWithdrawalCoins) {
      throw WithdrawalException(
        'Valor acima do teto por saque ($kMaxPerWithdrawalCoins COIN).',
      );
    }
    final String dest = destination.trim();
    if (!isValidDestination(dest)) {
      throw WithdrawalException(
        'Informe um e-mail FaucetPay ou um endereço LTC válido.',
      );
    }

    final String requestId = clientRequestId ?? generateClientRequestId();
    final String masked = maskDestination(dest);

    // --- IDEMPOTÊNCIA: registro existente ⇒ NUNCA reenviar o mesmo id ---
    final Map<String, dynamic>? existing =
        await _records.findByClientRequestId(requestId);
    if (existing != null) {
      developer.log('withdrawal already recorded — no resend',
          name: 'WithdrawalService');
      return _outcomeFromRecord(existing);
    }

    final BigInt amountUnits = BigInt.from(amountCoins) * kUnitsPerCoin;

    // --- (a) RESERVA atômica ---
    final bool reserved = await _ledger.reserve(
      uid: uid,
      amountUnits: amountUnits,
    );
    if (!reserved) {
      throw WithdrawalException(withdrawalErrorMessage('INSUFFICIENT_BALANCE'));
    }

    // --- (b) PAYOUT (litoshi inteiro; SEM retry automático) ---
    final int litoshi = (amountCoins - kFeeCoins) * kLitoshiPerCoin;
    final PayoutResult result = await _provider.sendPayout(
      destination: dest,
      amountLitoshi: litoshi,
    );

    // --- (b2) MODO MANUAL: doc `pending` + aguarda o operador (12.20).
    // A reserva JÁ foi feita (soma constante); a finalização/estorno acontece
    // AUTOMATICAMENTE quando o [ManualPayoutWatcher] observar o status
    // definido pelo operador no Console ('completed'/'failed').
    if (result.isPending) {
      await _safeRecord(<String, dynamic>{
        'uid': uid,
        'asset': 'LTC',
        'network': 'FaucetPayEmail',
        'amountCoins': amountCoins,
        'feeCoins': kFeeCoins,
        'litoshi': litoshi,
        'amountUnits': amountUnits.toString(),
        'feeUnits': (BigInt.from(kFeeCoins) * kUnitsPerCoin).toString(),
        'receivedUnits':
            (BigInt.from(amountCoins - kFeeCoins) * kUnitsPerCoin).toString(),
        'destinationMasked': masked,
        'status': 'pending',
        'providerReference': null,
        'errorCode': null,
        'createdAt': FieldValue.serverTimestamp(),
      }, requestId);
      developer.log('withdrawal pending (manual operator handoff)',
          name: 'WithdrawalService');
      return const WithdrawalOutcome(status: 'pending');
    }

    if (result.success) {
      // --- (c) CONCLUSÃO: total DIMINUI + histórico completed ---
      await _ledger.conclude(uid: uid, amountUnits: amountUnits);
      await _safeRecord(<String, dynamic>{
        'uid': uid,
        'asset': 'LTC',
        'network': 'FaucetPayEmail',
        'amountCoins': amountCoins,
        'feeCoins': kFeeCoins,
        'litoshi': litoshi,
        'amountUnits': amountUnits.toString(),
        'feeUnits': (BigInt.from(kFeeCoins) * kUnitsPerCoin).toString(),
        'receivedUnits':
            (BigInt.from(amountCoins - kFeeCoins) * kUnitsPerCoin).toString(),
        'destinationMasked': masked,
        'status': 'completed',
        'providerReference': result.providerReference,
        'errorCode': null,
        'createdAt': FieldValue.serverTimestamp(),
      }, requestId);
      return WithdrawalOutcome(
        status: 'completed',
        reference: maskReference(result.providerReference),
        detail: result.detail,
      );
    }

    // --- (d) FALHA: ESTORNO INTEGRAL + histórico failed ---
    await _ledger.refund(uid: uid, amountUnits: amountUnits);
    await _safeRecord(<String, dynamic>{
      'uid': uid,
      'asset': 'LTC',
      'network': 'FaucetPayEmail',
      'amountCoins': amountCoins,
      'feeCoins': kFeeCoins,
      'litoshi': litoshi,
      'amountUnits': amountUnits.toString(),
      'feeUnits': (BigInt.from(kFeeCoins) * kUnitsPerCoin).toString(),
      'receivedUnits': BigInt.zero.toString(),
      'destinationMasked': masked,
      'status': 'failed',
      'providerReference': null,
      'errorCode': result.errorCode,
      'createdAt': FieldValue.serverTimestamp(),
    }, requestId);
    developer.log('withdrawal failed code=${result.errorCode} — refunded',
        name: 'WithdrawalService');
    return WithdrawalOutcome(
      status: 'failed',
      errorCode: result.errorCode,
      detail: result.detail,
    );
  }

  WithdrawalOutcome _outcomeFromRecord(Map<String, dynamic> data) {
    final String status = (data['status'] as String?) ?? 'failed';
    return WithdrawalOutcome(
      status: status,
      errorCode: data['errorCode'] as String?,
      reference: maskReference(data['providerReference'] as String?),
    );
  }

  /// Grava o registro sem deixar a falha de escrita quebrar o fluxo
  /// (dinheiro/payout já aconteceu; histórico é best-effort aqui).
  Future<void> _safeRecord(Map<String, dynamic> data, String requestId) async {
    try {
      await _records.write(clientRequestId: requestId, data: data);
    } on Exception catch (e) {
      developer.log('withdrawal record write error type=${e.runtimeType}',
          name: 'WithdrawalService');
    }
  }

  /// providerReference mascarada: mantém prefixo e 4 chars finais.
  static String? maskReference(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    if (reference.length <= 8) return reference;
    return '${reference.substring(0, 5)}…'
        '${reference.substring(reference.length - 4)}';
  }
}

// ---- MODO MANUAL: observador de status definido pelo operador (12.20) -------

/// Ação de liquidação derivada da TRANSIÇÃO de status de um doc
/// `withdrawals/{id}` editado pelo operador no Firebase Console.
enum ManualSettlement { none, conclude, refund }

/// Função PURA (testável): só age em transição OBSERVADA pending→terminal.
/// Docs já terminais no primeiro snapshot são IGNORADOS (assumidos como já
/// liquidados em sessão anterior) — evita estorno/débito duplicado entre
/// reinícios do app. Soma available+pending NUNCA cresce:
///  - conclude ⇒ total DIMINUI (dinheiro saiu de verdade);
///  - refund   ⇒ soma constante (estorno integral).
ManualSettlement manualSettlementFor({
  required String? previousStatus,
  required String currentStatus,
}) {
  if (previousStatus != 'pending') return ManualSettlement.none;
  switch (currentStatus) {
    case 'completed':
      return ManualSettlement.conclude;
    case 'failed':
      return ManualSettlement.refund;
    default:
      return ManualSettlement.none;
  }
}

/// Observa `withdrawals` do próprio uid em tempo real e liquida sozinho:
/// status→'completed' ⇒ [WalletLedger.conclude]; status→'failed' ⇒
/// [WalletLedger.refund]. O operador edita o doc pelo Console (bypassa
/// rules — cliente NUNCA atualiza withdrawals).
class ManualPayoutWatcher {
  ManualPayoutWatcher({WalletLedger? ledger, FirebaseFirestore? firestore})
      : _ledgerOverride = ledger,
        _dbOverride = firestore;

  final WalletLedger? _ledgerOverride;
  final FirebaseFirestore? _dbOverride;

  WalletLedger get _ledger => _ledgerOverride ?? FirestoreWalletLedger();

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  /// Stream de "ticks" de liquidação (termina se o listener falhar).
  ///
  /// 12.21: cancelamento/teardown da stream pode lançar MissingPluginException
  /// (é um Error, não Exception) — tratado como NÃO-FATAL: catch silencioso
  /// com log técnico local (tipo apenas, sem stack completa).
  Stream<void> watch(String uid) async* {
    final Map<String, String> seenStatus = <String, String>{};
    try {
      await for (final QuerySnapshot<Map<String, dynamic>> snap
          in _db
              .collection(Collections.withdrawals)
              .where('uid', isEqualTo: uid)
              .snapshots()) {
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snap.docs) {
          final Map<String, dynamic> data = doc.data();
          final String current = (data['status'] as String?) ?? '';
          final String? previous = seenStatus[doc.id];
          seenStatus[doc.id] = current;
          final ManualSettlement action = manualSettlementFor(
              previousStatus: previous, currentStatus: current);
          if (action == ManualSettlement.none) continue;
          final BigInt amountUnits = _toBigInt(data['amountUnits']);
          if (amountUnits <= BigInt.zero) continue; // doc inválido: ignora
          try {
            if (action == ManualSettlement.conclude) {
              await _ledger.conclude(uid: uid, amountUnits: amountUnits);
              developer.log(
                  'manual payout concluded id-masked len=${doc.id.length}',
                  name: 'ManualPayoutWatcher');
            } else {
              await _ledger.refund(uid: uid, amountUnits: amountUnits);
              developer.log(
                  'manual payout refunded id-masked len=${doc.id.length}',
                  name: 'ManualPayoutWatcher');
            }
          } on Exception catch (e) {
            developer.log(
                'manual settlement error type=${e.runtimeType} '
                'action=$action',
                name: 'ManualPayoutWatcher');
          }
        }
      }
    } on Object catch (e) {
      // MissingPluginException/teardown no cancel da stream: não-fatal.
      developer.log('manual watcher stream ended type=${e.runtimeType}',
          name: 'ManualPayoutWatcher');
    }
  }
}
