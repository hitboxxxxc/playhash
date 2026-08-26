import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/repositories/game_sessions_repository.dart';

/// Resultado do servidor para uma sessão processada (espelho de leitura —
/// a autoridade é SEMPRE o runner; o cliente nunca calcula poder).
class GameSessionServerResult {
  const GameSessionServerResult({
    required this.processed,
    required this.status,
    this.powerAmountHs,
    this.expiresAt,
    this.reason,
  });

  final bool processed;

  /// 'granted' | 'already_granted' | 'rejected' (após processed).
  final String status;

  /// Poder concedido em H (units ÷ 1000) — somente exibição.
  final int? powerAmountHs;
  final DateTime? expiresAt;

  /// Motivo da rejeição (código do backend), quando houver.
  final String? reason;

  static GameSessionServerResult fromMap(Map<String, dynamic> data) {
    final Map<String, dynamic> raw =
        (data['serverResult'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final bool processed = data['processed'] == true;
    final String status = (raw['status'] as String?) ?? '';
    final int? powerHs = raw['powerAmount'] != null
        ? (int.tryParse(raw['powerAmount'].toString()) ?? 0) ~/
            GameConfigPowerMirror.unitsPerHs
        : null;
    final Object? expires = raw['expiresAt'];
    return GameSessionServerResult(
      processed: processed,
      status: status,
      powerAmountHs: powerHs,
      expiresAt: expires is Timestamp ? expires.toDate() : null,
      reason: (raw['reason'] as String?),
    );
  }
}

/// Espelho somente-leitura de `powerBasePerHs` (config/economy) para converter
/// units → H na EXIBIÇÃO. Nunca usado para decidir valores econômicos.
abstract final class GameConfigPowerMirror {
  static const int unitsPerHs = 1000;
}

/// Falha de sessão com mensagem SEGURA em PT-BR (sem vazar detalhes internos).
class GameSessionException implements Exception {
  GameSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serviço de sessão de partida: abre (antes do play), fecha (score único) e
/// observa o processamento pelo backend.
///
/// Tratamentos:
/// - offline ao enviar: retry com backoff (update open→finished é idempotente);
/// - sessão já fechada: tratado como sucesso;
/// - erro de regra/permissão: mensagem segura PT-BR.
class GameSessionService {
  GameSessionService({
    GameSessionsRepositoryApi? repository,
    this.maxFinishAttempts = 4,
    this.startTimeout = const Duration(seconds: 5),
    this.maxStartAttempts = 2,
  }) : _repositoryOverride = repository;

  final GameSessionsRepositoryApi? _repositoryOverride;
  final int maxFinishAttempts;

  /// Timeout por tentativa de abertura de sessão. Estourou ⇒ retry; falhou
  /// tudo ⇒ erro visível (o playfield NUNCA abre sem sessão 'open').
  final Duration startTimeout;
  final int maxStartAttempts;

  String? _clientVersion;

  GameSessionsRepositoryApi get _repository =>
      _repositoryOverride ?? GameSessionsRepository();

  /// Cria a sessão ANTES do play. Retorna o sessionId.
  ///
  /// Timeout de [startTimeout] por tentativa com até [maxStartAttempts]
  /// tentativas (erros definitivos como permission-denied não repetem).
  Future<String> startSession({
    required String uid,
    required String gameId,
  }) async {
    final String clientVersion = await _version();
    Object? lastError;
    for (int attempt = 0; attempt < maxStartAttempts; attempt++) {
      try {
        return await _repository
            .createSession(
              uid: uid,
              gameId: gameId,
              clientVersion: clientVersion,
            )
            .timeout(startTimeout);
      } on FirebaseException catch (e) {
        // Erro de regra/rede definitivo: repetir não muda o resultado.
        throw GameSessionException(_mapError(e));
      } on TimeoutException {
        lastError = 'timeout';
      } catch (e) {
        lastError = e;
      }
    }
    throw GameSessionException(
      lastError == 'timeout'
          ? 'A criação da sessão demorou demais. Verifique sua conexão '
              'e tente novamente.'
          : 'Não foi possível iniciar a sessão. Verifique sua conexão '
              'e tente de novo.',
    );
  }

  /// Envia o score (update único open→finished). `kills` é opcional e
  /// validado pelo backend (kills × pointsPerKill ≤ score). `breakdown` é
  /// opcional (neon-hopper em diante): mapa EXATO {stomps, coins, flagReached}
  /// — o score OFICIAL é recalculado pelo backend a partir dele. Retry
  /// seguro: se o update chegou ao servidor mas a resposta se perdeu, a nova
  /// tentativa encontra a sessão finished e é tratada como sucesso.
  Future<void> finishSession({
    required String sessionId,
    required int score,
    int? kills,
    Map<String, dynamic>? breakdown,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < maxFinishAttempts; attempt++) {
      try {
        await _repository.finishSession(
          sessionId: sessionId,
          score: score,
          kills: kills,
          breakdown: breakdown,
        );
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw GameSessionException(
            'A sessão já foi encerrada ou não pôde ser validada.',
          );
        }
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      // Backoff antes de reenviar (offline/instabilidade).
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw GameSessionException(
      'Sem conexão para enviar o resultado. O score desta partida não foi registrado — tente novamente mais tarde. ($lastError)',
    );
  }

  /// Observa o doc da sessão para exibir processed/serverResult.
  Stream<GameSessionServerResult> watchResult(String sessionId) =>
      _repository.watchSession(sessionId).map(
            (DocumentSnapshot<Map<String, dynamic>> snap) =>
                GameSessionServerResult.fromMap(snap.data() ?? const <String, dynamic>{}),
          );

  Future<String> _version() async {
    if (_clientVersion != null) return _clientVersion!;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return _clientVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      return _clientVersion = 'unknown';
    }
  }

  String _mapError(FirebaseException e) {
    switch (e.code) {
      case 'unavailable':
      case 'network-request-failed':
        return 'Sem conexão. Verifique a internet e tente novamente.';
      case 'permission-denied':
        return 'A sessão não pôde ser aberta agora. Tente novamente em instantes.';
      case 'failed-precondition':
        return 'O jogo está temporariamente indisponível.';
      default:
        return 'Não foi possível iniciar a sessão. Tente novamente.';
    }
  }
}
