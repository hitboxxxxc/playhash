import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/config/ads_config.dart';
import '../../data/repositories/ads_repository.dart';

/// Falha de recompensa por anúncio com mensagem SEGURA em PT-BR (sem vazar
/// detalhes internos do runner).
class AdRewardException implements Exception {
  AdRewardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serviço de INTENÇÃO de recompensa por anúncio (LOJA — "Assista e ganhe
/// 1 COIN").
///
/// - Chamado SOMENTE após `onUserEarnedReward` (anúncio sempre iniciado pelo
///   usuário; a recompensa é concedida EXCLUSIVAMENTE pelo runner);
/// - clientRequestId = UUID v4 gerado no cliente e usado COMO DOC ID:
///   retry offline reenvia o MESMO doc (nunca duplica — idempotência);
/// - payload com EXATAMENTE os campos das rules;
/// - mensagens de erro seguras por failureCode do runner.
class AdRewardService {
  AdRewardService({AdsRepositoryApi? repository})
      : _repositoryOverride = repository;

  final AdsRepositoryApi? _repositoryOverride;
  final Random _random = Random.secure();

  AdsRepositoryApi get _repository =>
      _repositoryOverride ?? AdsRepository();

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

  /// Registra a intenção com retry seguro (MESMO clientRequestId). Se o doc
  /// já existe (retry pós-instabilidade), trata como enviado.
  ///
  /// Retorna o clientRequestId para observação do resultado.
  Future<String> createIntent({
    required String uid,
    required String clientVersion,
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
          adUnitId: AdsConfig.rewardedUnitId,
          clientVersion: clientVersion,
        );
        return requestId;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // Doc já existente (retry) ⇒ update negado; confirma e segue.
          final AdRewardIntentResult? existing =
              await _repository.readIntent(requestId);
          if (existing != null) return requestId;
          throw AdRewardException(
            'Não foi possível registrar sua recompensa agora. Tente novamente.',
          );
        }
        if (e.code == 'unavailable' || e.code == 'network-request-failed') {
          lastError = e; // offline: retry com o MESMO requestId
        } else {
          throw AdRewardException(
            'Não foi possível registrar sua recompensa. Tente novamente.',
          );
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    // Offline persistente: a intent fica PENDENTE no cliente — ao reconectar,
    // chamar createIntent de novo com o MESMO clientRequestId (não duplica).
    throw AdRewardException(
      'Sem conexão para validar sua recompensa. Reconecte e tente de novo '
      '— seu vídeo foi contabilizado. ($lastError)',
    );
  }

  /// Observa a intent até done/failed (o runner processa em até ~5 min).
  Stream<AdRewardIntentResult> watchResult(String clientRequestId) =>
      _repository.watchIntent(clientRequestId);

  /// Stream das recompensas concedidas HOJE (contador "X de Y hoje").
  Stream<List<AdRewardEntry>> watchTodayRewards(String uid) =>
      _repository.watchTodayRewards(uid);

  /// Mensagem SEGURA por código de falha do runner.
  static String failureMessage(String? code) {
    switch (code) {
      case 'DAILY_LIMIT_REACHED':
        return 'Limite diário de vídeos atingido. Volte amanhã!';
      case 'COOLDOWN_ACTIVE':
        return 'Aguarde um pouco antes de assistir outro vídeo.';
      case 'ACCOUNT_BLOCKED':
      case 'ANTIFRAUD_FLAG':
        return 'Conta em análise. Fale com o suporte se isso persistir.';
      case 'ADS_DISABLED':
        return 'Recompensas por vídeo estão indisponíveis no momento.';
      default:
        return 'A recompensa não pôde ser validada. Tente novamente mais tarde.';
    }
  }
}
