import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/repositories/payouts_repository.dart';

/// Resultado observado de um saque processado pelo runner.
class WithdrawalResult {
  const WithdrawalResult({required this.status, this.errorCode, this.reference});

  /// 'processing' | 'completed' | 'failed'.
  final String status;
  final String? errorCode;

  /// providerReference MASCARADA p/ exibição (ex.: "SIM-1a2b…").
  final String? reference;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

/// Mensagem SEGURA em PT-BR por errorCode CANÔNICO do runner (12.9):
/// ASSET_DISABLED · BELOW_MIN · INSUFFICIENT_BALANCE · COOLDOWN_ACTIVE ·
/// ANTIFRAUD · EMAIL_INVALID · PROVIDER_ERROR. Códigos legados (docs antigos)
/// continuam mapeados; detalhes técnicos ficam só no log local.
String withdrawalErrorMessage(String? errorCode) {
  switch (errorCode) {
    case 'INSUFFICIENT_BALANCE':
      return 'Saldo disponível insuficiente para este saque.';
    // Canônico 12.9 + legados:
    case 'BELOW_MINIMUM':
    case 'AMOUNT_TOO_LOW':
    case 'BELOW_PROVIDER_MIN':
    case 'BELOW_MIN':
      return 'Valor abaixo do mínimo definido pelo servidor.';
    case 'COOLDOWN_ACTIVE':
      return 'Aguarde o intervalo entre saques (24h).';
    // Canônico ANTIFRAUD + legados que convergem p/ ele:
    case 'ANTIFRAUD':
    case 'DAILY_LIMIT_REACHED':
      return 'Saques temporariamente indisponíveis para esta conta. '
          'Tente novamente mais tarde.';
    case 'ACCOUNT_TOO_NEW':
      return 'Sua conta ainda não tem 24h — tente mais tarde.';
    case 'NO_FINISHED_GAMES':
      return 'Jogue ao menos uma partida antes de solicitar um saque.';
    case 'ACCOUNT_IN_REVIEW':
      return 'Conta em análise. Saques bloqueados temporariamente.';
    // Canônico EMAIL_INVALID + legados:
    case 'EMAIL_INVALID':
    case 'INVALID_ADDRESS':
      return 'Destino inválido para o saque.';
    case 'PROVIDER_ERROR':
      return 'Provedor de pagamento temporariamente indisponível. '
          'Tente novamente mais tarde.';
    case 'INVALID_EMAIL':
      return 'E-mail da FaucetPay inválido.';
    case 'EMAIL_NOT_FOUND':
      return 'E-mail não encontrado na FaucetPay. Confira sua conta.';
    case 'INSUFFICIENT_PROVIDER_BALANCE':
      return 'Provedor temporariamente sem saldo. Tente mais tarde.';
    case 'RATE_LIMIT':
      return 'Muitas solicitações ao provedor. Tente mais tarde.';
    case 'ASSET_DISABLED':
      return 'Ativo temporariamente indisponível para saque.';
    default:
      return 'Não foi possível concluir o saque. Tente novamente.';
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

/// Regex de e-mail (formato básico; a autoridade é o backend/rules).
final RegExp kDestinationEmailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Validação LOCAL leve do e-mail FaucetPay (aviso apenas — a autoridade é
/// o runner + rules). Comprimento dentro do aceito pelas rules (6..254).
bool isValidDestinationEmail(String email) {
  final String v = email.trim();
  return v.length >= 6 && v.length <= 254 && kDestinationEmailRe.hasMatch(v);
}

/// Serviço de SAQUE — o cliente SÓ cria a intenção e observa o resultado.
///
/// - clientRequestId = UUID v4 usado COMO doc id ⇒ retry offline reenvia o
///   MESMO documento (idempotência; nunca duplica saque);
/// - payload com EXATAMENTE os campos das rules;
/// - taxas/mínimos vêm SEMPRE de config/payouts ("valores definidos pelo
///   servidor") — nada é calculado/decidido no cliente.
class WithdrawalService {
  WithdrawalService({PayoutsRepositoryApi? repository})
      : _repositoryOverride = repository;

  final PayoutsRepositoryApi? _repositoryOverride;
  final Random _random = Random.secure();

  PayoutsRepositoryApi get _repository =>
      _repositoryOverride ?? PayoutsRepository();

  /// UUID v4 próprio (sem dependência externa) — mesmo padrão do purchase
  /// intent service.
  String generateClientRequestId() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final String h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Cria a intent de saque com retry seguro (MESMO clientRequestId em todas
  /// as tentativas). Destino = E-MAIL da conta FaucetPay (v3, transferência
  /// interna). Retorna o requestId para observação do resultado.
  ///
  /// MAPEAMENTO DE ERROS: "sem conexão" SOMENTE para falha REAL de rede
  /// (`unavailable`/`network-request-failed`/SocketException). Demais erros
  /// (permission-denied, invalid-argument, …) NUNCA viram "sem conexão" —
  /// recebem mensagem segura específica; o código técnico vai apenas para o
  /// log local (dart:developer), sem dados sensíveis.
  Future<String> requestWithdrawal({
    required String uid,
    required String asset,
    required BigInt amountUnits,
    required String destinationEmail,
    String? clientRequestId,
    String clientVersion = 'dev',
    int maxAttempts = 3,
  }) async {
    if (amountUnits <= BigInt.zero) {
      throw WithdrawalException('Valor inválido.');
    }
    final String email = destinationEmail.trim();
    if (!isValidDestinationEmail(email)) {
      throw WithdrawalException('E-mail da FaucetPay inválido.');
    }
    final String requestId = clientRequestId ?? generateClientRequestId();
    final String masked = maskEmail(email);
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _repository.createWithdrawalIntent(
          clientRequestId: requestId,
          uid: uid,
          asset: asset,
          amountUnits: amountUnits,
          destinationEmail: email,
          destinationMasked: masked,
          clientVersion: clientVersion,
        );
        return requestId;
      } on FirebaseException catch (e) {
        developer.log('withdrawal intent error code=${e.code}',
            name: 'WithdrawalService');
        if (_isOfflineCode(e.code)) {
          // offline/instável ⇒ nova tentativa com MESMO id
          continue;
        }
        if (e.code == 'permission-denied') {
          // CORREÇÃO 12.8: "atualize o app" SOMENTE existe para
          // incompatibilidade REAL de clientVersion (não há esse gate nas
          // rules). Recusa de rules/config/ativo ⇒ mensagem acionável neutra;
          // código técnico fica só no log local.
          throw WithdrawalException(
            'Saque indisponível para este ativo no momento. '
            'Tente novamente mais tarde.',
          );
        }
        throw WithdrawalException(
          'Não foi possível concluir o saque. Tente novamente.',
        );
      } on Exception catch (e) {
        // Erros de rede fora do Firestore (SocketException etc.).
        developer.log('withdrawal intent error type=${e.runtimeType}',
            name: 'WithdrawalService');
        continue; // trata como rede instável ⇒ retry
      }
    }
    throw WithdrawalException(
      'Sem conexão para enviar a solicitação. Tente novamente.',
    );
  }

  /// Códigos do Firestore que REALMENTE indicam problema de conectividade.
  static bool _isOfflineCode(String code) =>
      code == 'unavailable' || code == 'network-request-failed';

  /// Observa o saque até o runner concluir (completed/failed).
  Stream<WithdrawalResult> watchWithdrawal(String clientRequestId) =>
      _repository.watchWithdrawal(clientRequestId).map((WithdrawalModel? w) {
        if (w == null) {
          return const WithdrawalResult(status: 'processing');
        }
        return WithdrawalResult(
          status: w.status,
          errorCode: w.errorCode,
          reference: _maskReference(w.providerReference),
        );
      });

  /// providerReference mascarada: mantém prefixo e 4 chars finais.
  static String? _maskReference(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    if (reference.length <= 8) return reference;
    return '${reference.substring(0, 5)}…'
        '${reference.substring(reference.length - 4)}';
  }
}
