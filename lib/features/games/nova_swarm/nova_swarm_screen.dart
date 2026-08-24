import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/game_session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../data/models/game_model.dart';
import 'engine/game_state.dart';
import 'engine/input_controller.dart';
import 'engine/physics.dart';
import 'engine/renderer.dart';
import 'widgets/countdown_overlay.dart';
import 'widgets/hud.dart';
import 'widgets/instructions_overlay.dart';
import 'widgets/result_overlay.dart';

/// NOVA SWARM — shooter espacial 2D (FÁCIL, 60s, 3 vidas, ondas crescentes).
/// 100% renderizado em código (CustomPaint único), 60fps alvo, zero assets.
///
/// Fluxo de sessão: instruções → INICIAR cria gameSessions (open) → partida →
/// finishSession (score único) → runner valida → POWER 24h → resultado.
class NovaSwarmScreen extends ConsumerStatefulWidget {
  const NovaSwarmScreen({super.key, required this.game});

  final GameModel game;

  @override
  ConsumerState<NovaSwarmScreen> createState() => _NovaSwarmScreenState();
}

enum _ScreenStage { instructions, creating, playing, finished }

class _NovaSwarmScreenState extends ConsumerState<NovaSwarmScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final NovaSwarmInputController _input;
  ValueNotifier<NovaSwarmState>? _game;

  /// Último elapsed do Ticker — usado para calcular o DELTA real por frame
  /// (o Ticker entrega tempo ABSOLUTO desde o start; usá-lo direto como dt
  /// acelerava o jogo ~3× após os primeiros 50ms).
  Duration? _lastElapsed;

  bool _starting = false; // trava contra duplo toque em INICIAR

  _ScreenStage _stage = _ScreenStage.instructions;
  String? _startError;

  // Sessão (intenção validada pelas rules; autoridade = backend).
  String? _sessionId;
  ResultStage _resultStage = ResultStage.idle;
  GameSessionServerResult? _serverResult;
  bool _finishing = false;

  /// COUNTDOWN v2: loop congelado até o GO (~2.8s); timer inicia no GO
  /// (o tempo de jogo só avança quando o step roda).
  bool _countdownDone = false;

  NovaSwarmConfig get _config => NovaSwarmConfig.fromGame(widget.game);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = NovaSwarmInputController(_applyInput);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.stop();
    _game?.dispose();
    super.dispose();
  }

  // ---- Ciclo de vida: auto-pause ao perder foco ---------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pause();
    }
  }

  /// Callback do [NovaSwarmInputController]: aplica (alvo, toque ativo) à
  /// MESMA instância de estado lida pelo Ticker (via ValueNotifier).
  /// Durante o countdown o loop está congelado, mas o alvo/toque são
  /// registrados — segurar o dedo através do GO funciona sem re-toque.
  void _applyInput(double targetX, bool isTouching) {
    final NovaSwarmState? s = _game?.value;
    if (s == null ||
        s.phase != NovaSwarmPhase.playing ||
        s.endReason != null) {
      return;
    }
    _game!.value = s.copyWith(playerTargetX: targetX, shooting: isTouching);
  }

  // ---- Loop ---------------------------------------------------------------
  void _onTick(Duration elapsedReal) {
    final NovaSwarmState? s = _game?.value;
    if (s == null || s.phase != NovaSwarmPhase.playing || s.endReason != null) {
      _lastElapsed = null; // retomada recomeça a contagem de delta
      return;
    }
    // COUNTDOWN: loop congelado — nada avança até o GO.
    if (!_countdownDone) {
      _lastElapsed = null;
      return;
    }
    // Delta REAL entre ticks (clamp 50ms para evitar salto pós-lag).
    final Duration last = _lastElapsed ?? elapsedReal;
    _lastElapsed = elapsedReal;
    final double dt =
        ((elapsedReal - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    try {
      final StepResult result = step(s, dt);
      _game!.value = result.state;
      for (final GameEvent e in result.events) {
        switch (e) {
          case GameEvent.enemyKilled:
          case GameEvent.eliteKilled:
          case GameEvent.diverKilled:
          case GameEvent.waveCleared:
          case GameEvent.powerupCollected:
            HapticFeedback.lightImpact();
            break;
          case GameEvent.lifeLost:
          case GameEvent.shieldAbsorbed:
            HapticFeedback.mediumImpact();
            break;
        }
      }
      if (result.state.endReason != null) _onGameEnd(result.state);
    } catch (_) {
      // DEFESA: uma exceção dentro de um callback de Ticker aborta o
      // reagendamento e o loop morre EM SILÊNCIO (start congelado). Engolimos
      // o erro deste frame para o jogo nunca ficar zumbi.
      _lastElapsed = null;
    }
  }

  // ---- Sessão -------------------------------------------------------------
  Future<void> _startSessionAndPlay() async {
    if (_starting) return; // duplo toque não cria duas sessões
    _starting = true;
    setState(() {
      _stage = _ScreenStage.creating;
      _startError = null;
    });
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (uid == null) {
        throw GameSessionException(
          'Sessão expirada. Entre novamente para jogar.',
        );
      }
      // Timeout 5s + retry ficam no serviço; erro ⇒ NUNCA navegamos para o
      // playfield sem sessão 'open' (nada de estado zumbi).
      final String sessionId = await ref
          .read(gameSessionServiceProvider)
          .startSession(uid: uid, gameId: widget.game.id);
      if (!mounted) return;
      _sessionId = sessionId;
      _initGame();
      _lastElapsed = null;
      setState(() => _stage = _ScreenStage.playing);
      _ticker.start(); // Ticker ativo desde o frame 0 do playfield
    } on GameSessionException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _ScreenStage.instructions;
        _startError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _ScreenStage.instructions;
        _startError = 'Não foi possível iniciar a sessão. Tente novamente.';
      });
    } finally {
      _starting = false;
    }
  }

  void _initGame() {
    // Área REAL do playfield (MediaQuery menos insets/SafeArea) — evita âncora
    // do jogador fora do canvas em dispositivos com barras de sistema.
    final MediaQueryData mq = MediaQuery.of(context);
    final Size size = Size(
      mq.size.width,
      mq.size.height - mq.padding.top - mq.padding.bottom,
    );
    _game?.dispose();
    _game = ValueNotifier<NovaSwarmState>(
      createInitialState(config: _config, fieldSize: size),
    );
    _countdownDone = false; // countdown 3-2-1-GO a cada partida
  }

  Future<void> _onGameEnd(NovaSwarmState s) async {
    _ticker.stop();
    _input.release(); // autofire nunca sobrevive ao fim da partida
    if (!mounted) return;
    // v2: NÃO envia automaticamente — o painel final mostra
    // "COLETAR RECOMPENSA", que garante o finishSession (retry idempotente).
    setState(() {
      _stage = _ScreenStage.finished;
      _resultStage = ResultStage.idle;
    });
  }

  Future<void> _sendScore(int score) async {
    final String? sessionId = _sessionId;
    if (sessionId == null || _finishing) return;
    _finishing = true;
    setState(() => _resultStage = ResultStage.sending);
    try {
      await ref
          .read(gameSessionServiceProvider)
          .finishSession(sessionId: sessionId, score: score);
      if (!mounted) return;
      setState(() => _resultStage = ResultStage.validating);
      _listenServerResult(sessionId);
    } on GameSessionException {
      if (!mounted) return;
      setState(() => _resultStage = ResultStage.sendFailed);
    } finally {
      _finishing = false;
    }
  }

  void _listenServerResult(String sessionId) {
    final Stream<GameSessionServerResult> stream =
        ref.read(gameSessionServiceProvider).watchResult(sessionId);
    stream.listen(
      (GameSessionServerResult r) {
        if (!mounted || !r.processed) return;
        setState(() {
          _serverResult = r;
          _resultStage = r.status == 'rejected'
              ? ResultStage.rejected
              : ResultStage.granted;
        });
      },
      onError: (Object _) {
        // Stream falhou (offline): permanece "em validação"; o runner
        // processa quando possível e o histórico do catálogo reflete depois.
      },
    );
  }

  void _pause() {
    final NovaSwarmState? s = _game?.value;
    if (s == null ||
        s.phase != NovaSwarmPhase.playing ||
        s.endReason != null) {
      return;
    }
    _input.release(); // solta o dedo logicamente (sem autofire zumbi)
    _game!.value = s.copyWith(phase: NovaSwarmPhase.paused, shooting: false);
  }

  void _resume() {
    final NovaSwarmState? s = _game?.value;
    if (s == null || s.phase != NovaSwarmPhase.paused) return;
    _lastElapsed = null; // delta não acumula o tempo pausado
    _game!.value = s.copyWith(phase: NovaSwarmPhase.playing);
  }

  /// Saída no meio da partida: envia o score parcial (sessão open→finished)
  /// para não deixar sessões órfãs; se ainda muito curta, o backend rejeita
  /// com segurança (DURATION_TOO_SHORT) — nunca valor inventado.
  Future<void> _finishAndPop() async {
    final NovaSwarmState? s = _game?.value;
    final NavigatorState nav = Navigator.of(context);
    if (_stage == _ScreenStage.playing && s != null && !_finishing) {
      _ticker.stop();
      _stage = _ScreenStage.finished;
      await _sendScore(s.score);
    }
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _stage != _ScreenStage.playing,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _finishAndPop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000005),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                _buildBody(Size(constraints.maxWidth, constraints.maxHeight)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Size size) {
    switch (_stage) {
      case _ScreenStage.instructions:
      case _ScreenStage.creating:
        return InstructionsOverlay(
          game: widget.game,
          onStart: _startSessionAndPlay,
          isLoading: _stage == _ScreenStage.creating,
          error: _startError,
          onBack: () => Navigator.of(context).pop(),
        );
      case _ScreenStage.playing:
      case _ScreenStage.finished:
        final NovaSwarmState? initial = _game?.value;
        if (initial == null) {
          return InstructionsOverlay(
            game: widget.game,
            onStart: _startSessionAndPlay,
            isLoading: false,
            error: _startError,
            onBack: () => Navigator.of(context).pop(),
          );
        }
        // REATIVO: o HUD/pausa/resultado reconstruem a CADA tick — sem isso o
        // TEMPO ficava preso no valor inicial mesmo com o loop rodando.
        return ValueListenableBuilder<NovaSwarmState>(
          valueListenable: _game!,
          builder: (BuildContext context, NovaSwarmState s, _) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Campo de jogo: pintor único (sem input aqui).
              CustomPaint(
                painter: NovaSwarmPainter(
                  state: s,
                  repaint: _game!,
                ),
                child: const SizedBox.expand(),
              ),
              // COUNTDOWN 3-2-1-GO (loop congelado; timer inicia no GO).
              // IgnorePointer interno: NUNCA absorve toques do playfield.
              if (!_countdownDone && s.endReason == null)
                CountdownOverlay(
                  onFinished: () {
                    if (!mounted) return;
                    setState(() => _countdownDone = true);
                    _lastElapsed = null;
                  },
                ),
              // INPUT em nível de PONTEIRO — camada NO TOPO da stack do
              // playfield (abaixo apenas de HUD/pausa/resultado). Listener
              // bruto não entra na arena de gestos: nenhum overlay/scroll
              // rouba o toque. Multi-touch: só o primeiro dedo comanda.
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (PointerDownEvent e) => _input
                      .onPointerDown(e.pointer, e.localPosition, size),
                  onPointerMove: (PointerMoveEvent e) => _input
                      .onPointerMove(e.pointer, e.localPosition, size),
                  onPointerUp: (PointerUpEvent e) =>
                      _input.onPointerUp(e.pointer),
                  onPointerCancel: (PointerCancelEvent e) =>
                      _input.onPointerCancel(e.pointer),
                  child: const SizedBox.expand(),
                ),
              ),
              // HUD topo (botão de pausa fica ACIMA da camada de input).
              Align(
                alignment: Alignment.topCenter,
                child: NovaSwarmHud(
                  score: s.score,
                  timeLeft: s.timeLeft.ceil(),
                  lives: s.lives,
                  maxLives: _config.lives,
                  wave: s.wave,
                  shieldRemaining: s.isShieldActive
                      ? ((s.shieldUntil - s.elapsed) / _config.shieldSeconds)
                          .clamp(0.0, 1.0)
                      : 0,
                  doubleRemaining: s.isDoubleActive
                      ? ((s.doubleUntil - s.elapsed) / _config.doubleSeconds)
                          .clamp(0.0, 1.0)
                      : 0,
                  doubleLevel: s.doubleLevel,
                  onPause: _pause,
                ),
              ),
              // Pausa (auto-pause por lifecycle também passa aqui — nunca
              // mais pausa invisível). Montada SOMENTE quando pausada:
              // absorve hits apenas enquanto visível.
              if (s.phase == NovaSwarmPhase.paused && s.endReason == null)
                _PauseOverlay(onResume: _resume, onQuit: _finishAndPop),
              // Resultado. Montado SOMENTE no fim: absorve hits apenas
              // enquanto visível.
              if (_stage == _ScreenStage.finished)
                ResultOverlay(
                  stage: _resultStage,
                  score: s.score,
                  kills: s.kills,
                  waves: s.wave,
                  endReason: switch (s.endReason) {
                    NovaSwarmEndReason.timeUp => 'timeUp',
                    NovaSwarmEndReason.dead => 'dead',
                    null => null,
                  },
                  powerUpsCollected: s.totalPowerUpsCollected,
                  serverResult: _serverResult,
                  onCollect:
                      (_resultStage == ResultStage.idle ||
                              _resultStage == ResultStage.sendFailed)
                          ? () => _sendScore(s.score)
                          : null,
                  onBack: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        );
    }
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onQuit});

  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF000005).withValues(alpha: 0.75),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'PAUSADO',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: AppColors.cyan,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O cronômetro da sessão continua no servidor.\n'
              'Pausas longas podem invalidar a partida.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: NeonButton(label: 'CONTINUAR', onPressed: onResume),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 220,
              child: NeonButton(
                label: 'SAIR E ENVIAR',
                onPressed: onQuit,
                color: AppColors.purple,
              ),
            ),
          ],
        ),
      );
}
