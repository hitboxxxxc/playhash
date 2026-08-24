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

  _ScreenStage _stage = _ScreenStage.instructions;
  String? _startError;

  // Sessão (intenção validada pelas rules; autoridade = backend).
  String? _sessionId;
  ResultStage _resultStage = ResultStage.sending;
  GameSessionServerResult? _serverResult;
  bool _finishing = false;

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

  void _applyInput(double targetX, bool shooting) {
    final NovaSwarmState? s = _game?.value;
    if (s == null || s.phase != NovaSwarmPhase.playing) return;
    _game!.value = s.copyWith(playerTargetX: targetX, shooting: shooting);
  }

  // ---- Loop ---------------------------------------------------------------
  void _onTick(Duration elapsedReal) {
    final NovaSwarmState? s = _game?.value;
    if (s == null || s.phase != NovaSwarmPhase.playing) return;
    final double dt = (elapsedReal.inMicroseconds / 1e6).clamp(0.0, 0.05);
    final StepResult result = step(s, dt);
    _game!.value = result.state;
    for (final GameEvent e in result.events) {
      switch (e) {
        case GameEvent.enemyKilled:
        case GameEvent.eliteKilled:
        case GameEvent.waveCleared:
          HapticFeedback.lightImpact();
          break;
        case GameEvent.lifeLost:
          HapticFeedback.mediumImpact();
          break;
      }
    }
    if (result.state.endReason != null) _onGameEnd(result.state);
  }

  // ---- Sessão -------------------------------------------------------------
  Future<void> _startSessionAndPlay() async {
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
      final String sessionId = await ref
          .read(gameSessionServiceProvider)
          .startSession(uid: uid, gameId: widget.game.id);
      if (!mounted) return;
      _sessionId = sessionId;
      _initGame();
      setState(() => _stage = _ScreenStage.playing);
      _ticker.start();
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
    }
  }

  void _initGame() {
    final Size size = MediaQuery.of(context).size;
    _game?.dispose();
    _game = ValueNotifier<NovaSwarmState>(
      createInitialState(config: _config, fieldSize: size),
    );
  }

  Future<void> _onGameEnd(NovaSwarmState s) async {
    _ticker.stop();
    if (!mounted) return;
    setState(() => _stage = _ScreenStage.finished);
    await _sendScore(s.score);
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
    _game!.value = s.copyWith(phase: NovaSwarmPhase.paused, shooting: false);
  }

  void _resume() {
    final NovaSwarmState? s = _game?.value;
    if (s == null || s.phase != NovaSwarmPhase.paused) return;
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
        );
      case _ScreenStage.playing:
      case _ScreenStage.finished:
        final NovaSwarmState? s = _game?.value;
        if (s == null) {
          return InstructionsOverlay(
            game: widget.game,
            onStart: _startSessionAndPlay,
            isLoading: false,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Campo de jogo: pintor único + input por pan.
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent e) =>
                  _input.onPanDown(e.localPosition, size),
              onPointerMove: (PointerMoveEvent e) =>
                  _input.onPanUpdate(e.localPosition, size),
              onPointerUp: (PointerUpEvent e) => _input.onPanEnd(),
              onPointerCancel: (PointerCancelEvent e) => _input.onPanEnd(),
              child: CustomPaint(
                painter: NovaSwarmPainter(
                  state: s,
                  repaint: _game!,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            // HUD topo.
            Align(
              alignment: Alignment.topCenter,
              child: NovaSwarmHud(
                score: s.score,
                timeLeft: s.timeLeft.ceil(),
                lives: s.lives,
                maxLives: _config.lives,
                wave: s.wave,
                onPause: _pause,
              ),
            ),
            // Pausa.
            if (s.phase == NovaSwarmPhase.paused && s.endReason == null)
              _PauseOverlay(onResume: _resume, onQuit: _finishAndPop),
            // Resultado.
            if (_stage == _ScreenStage.finished)
              ResultOverlay(
                stage: _resultStage,
                score: s.score,
                kills: s.kills,
                waves: s.wave,
                serverResult: _serverResult,
                onRetry: _resultStage == ResultStage.sendFailed
                    ? () => _sendScore(s.score)
                    : null,
                onBack: () => Navigator.of(context).pop(),
              ),
          ],
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
