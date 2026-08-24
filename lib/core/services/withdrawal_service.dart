import 'dart:async';
import 'dart:math';

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

/// Mensagem SEGURA em PT-BR por errorCode do runner (sem detalhes internos).
String withdrawalErrorMessage(String? errorCode) {
  switch (errorCode) {
    case 'INSUFFICIENT_BALANCE':
      return 'Saldo disponível insuficiente para este saque.';
    case 'BELOW_MINIMUM':
    case 'AMOUNT_TOO_LOW':
      return 'Valor abaixo do mínimo definido pelo servidor.';
    case 'COOLDOWN_ACTIVE':
      return 'Aguarde o intervalo entre saques (24h).';
    case 'DAILY_LIMIT_REACHED':
      return 'Limite diário de saques atingido.';
    case 'ACCOUNT_TOO_NEW':
      return 'Sua conta ainda não tem 24h — tente mais tarde.';
    case 'NO_FINISHED_GAMES':
      return 'Jogue ao menos uma partida antes de solicitar um saque.';
    case 'ACCOUNT_IN_REVIEW':
      return 'Conta em análise. Saques bloqueados temporariamente.';
    case 'INVALID_ADDRESS':
      return 'Endereço inválido para a rede selecionada.';
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

/// Máscara segura de endereço p/ exibição local: 6 primeiros + '…' + 4
/// últimos (espelha maskAddress do backend).
String maskWalletAddress(String address) {
  if (address.length <= 10) return '*' * address.length;
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}

/// Validação LOCAL leve do endereço (aviso apenas — a autoridade é o runner).
bool looksLikeValidAddress(String network, String address) {
  switch (network.toUpperCase()) {
    case 'BITCOIN':
      return RegExp(r'^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{11,71})$')
          .hasMatch(address);
    case 'LITECOIN':
      return RegExp(r'^(?:[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}|ltc1[a-z0-9]{11,71})$')
          .hasMatch(address);
    case 'DOGECOIN':
      return RegExp(r'^D[a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(address);
    case 'TRC20':
      return RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(address);
    default:
      return false;
  }
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
  /// as tentativas). Retorna o requestId para observação do resultado.
  Future<String> requestWithdrawal({
    required String uid,
    required String asset,
    required String network,
    required BigInt amountUnits,
    required String address,
    String? clientRequestId,
    String clientVersion = 'dev',
    int maxAttempts = 3,
  }) async {
    if (amountUnits <= BigInt.zero) {
      throw WithdrawalException('Valor inválido.');
    }
    final String requestId = clientRequestId ?? generateClientRequestId();
    final String masked = maskWalletAddress(address);
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _repository.createWithdrawalIntent(
          clientRequestId: requestId,
          uid: uid,
          asset: asset,
          network: network,
          amountUnits: amountUnits,
          address: address,
          addressMasked: masked,
          clientVersion: clientVersion,
        );
        return requestId;
      } on Exception {
        // offline/instável ⇒ nova tentativa com MESMO id
      }
    }
    throw WithdrawalException(
      'Sem conexão para enviar a solicitação. Tente novamente.',
    );
  }

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
