import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/game_session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../data/models/game_model.dart';
import 'engine/input_state.dart';
import 'engine/physics.dart';
import 'engine/renderer.dart';
import 'widgets/instructions_overlay.dart';
import 'widgets/joystick_widget.dart';
import 'widgets/jump_button.dart';
import 'widgets/result_overlay.dart';

/// NEON HOPPER — plataforma 2D side-scroll (MÉDIO, 45s, 3 vidas).
/// 100% renderizado em código (CustomPaint único), 60fps alvo, zero assets,
/// identidade própria (NENHUM conteúdo de terceiros).
///
/// Controles multi-toque reais: zona esquerda = joystick dinâmico horizontal;
/// zona direita = botão PULO (buffer + coyote; soltar cedo = pulo curto).
///
/// Fluxo de sessão (idêntico ao NOVA SWARM): instruções → INICIAR cria
/// gameSessions (open) → partida → finishSession com BREAKDOWN {stomps,
/// coins, flagReached} → runner recalcula o score OFICIAL → POWER 24h.
class NeonHopperScreen extends ConsumerStatefulWidget {
  const NeonHopperScreen({super.key, required this.game});

  final GameModel game;

  @override
  ConsumerState<NeonHopperScreen> createState() => _NeonHopperScreenState();
}

enum _ScreenStage { instructions, creating, playing, finished }

class _NeonHopperScreenState extends ConsumerState<NeonHopperScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final HopperInputController _input;
  ValueNotifier<NeonHopperState>? _game;

  /// Último elapsed do Ticker — delta REAL por frame (clamp 50ms).
  Duration? _lastElapsed;

  bool _starting = false;
  bool _finishing = false;

  _ScreenStage _stage = _ScreenStage.instructions;
  String? _startError;

  // Sessão (intenção validada pelas rules; autoridade = backend).
  String? _sessionId;
  HopperResultStage _resultStage = HopperResultStage.idle;
  GameSessionServerResult? _serverResult;

  /// COUNTDOWN: loop congelado até o GO (~2.8s); timer inicia no GO.
  bool _countdownDone = false;

  HopperConfig get _config => HopperConfig(
        durationSeconds: widget.game.configuration.durationSeconds > 0
            ? widget.game.configuration.durationSeconds
            : 45,
        lives: widget.game.configuration.lives > 0
            ? widget.game.configuration.lives
            : 3,
        pointsPerStomp: widget.game.configuration.pointsPerStomp > 0
            ? widget.game.configuration.pointsPerStomp
            : 100,
        pointsPerCoin: widget.game.configuration.pointsPerCoin > 0
            ? widget.game.configuration.pointsPerCoin
            : 50,
        flagBonus:
            widget.game.configuration.flagBonus > 0 ? widget.game.configuration.flagBonus : 500,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = HopperInputController(_applyInput);
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pause();
    }
  }

  /// Callback do [HopperInputController]: aplica entrada à MESMA instância
  /// de estado lida pelo Ticker. Pulo pressionado AGORA ⇒ buffer 0.12s.
  void _applyInput(double axis, bool jumpPressed, bool jumpHeld) {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.playing || s.endReason != null) {
      return;
    }
    _game!.value = s.copyWith(
      moveAxis: axis,
      jumpHeld: jumpHeld,
      jumpBufferTimer: jumpPressed ? 0.12 : s.jumpBufferTimer,
      jumpCut: !jumpHeld && s.player.vy < 0 ? true : s.jumpCut,
    );
  }

  // ---- Loop ---------------------------------------------------------------
  void _onTick(Duration elapsedReal) {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.playing || s.endReason != null) {
      _lastElapsed = null;
      return;
    }
    if (!_countdownDone) {
      _lastElapsed = null;
      return;
    }
    final Duration last = _lastElapsed ?? elapsedReal;
    _lastElapsed = elapsedReal;
    final double dt = ((elapsedReal - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    try {
      final StepResult result = stepHopper(s, dt);
      _game!.value = result.state;
      for (final HopperEvent e in result.events) {
        switch (e) {
          case HopperEvent.stomp:
          case HopperEvent.coin:
          case HopperEvent.flagReached:
            HapticFeedback.lightImpact();
            break;
          case HopperEvent.lifeLost:
          case HopperEvent.fell:
          case HopperEvent.gameOver:
            HapticFeedback.mediumImpact();
            break;
        }
      }
      if (result.state.endReason != null) _onGameEnd(result.state);
    } catch (_) {
      // DEFESA: exceção no Ticker abortaria o loop EM SILÊNCIO. Engolimos o
      // erro deste frame para o jogo nunca ficar zumbi.
      _lastElapsed = null;
    }
  }

  // ---- Sessão -------------------------------------------------------------
  Future<void> _startSessionAndPlay() async {
    if (_starting) return;
    _starting = true;
    setState(() {
      _stage = _ScreenStage.creating;
      _startError = null;
    });
    try {
      final String? uid = await ref.read(currentUidProvider.future);
      if (uid == null) {
        throw GameSessionException('Sessão expirada. Entre novamente para jogar.');
      }
      final String sessionId = await ref
          .read(gameSessionServiceProvider)
          .startSession(uid: uid, gameId: widget.game.id);
      if (!mounted) return;
      _sessionId = sessionId;
      _initGame();
      _lastElapsed = null;
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
    } finally {
      _starting = false;
    }
  }

  void _initGame() {
    _game?.dispose();
    _game = ValueNotifier<NeonHopperState>(createInitialHopperState(config: _config));
    _countdownDone = false;
  }

  Future<void> _onGameEnd(NeonHopperState s) async {
    _ticker.stop();
    _input.release();
    if (!mounted) return;
    // NÃO envia automaticamente — o painel final mostra "COLETAR RECOMPENSA"
    // (finishSession com breakdown; retry idempotente).
    setState(() {
      _stage = _ScreenStage.finished;
      _resultStage = HopperResultStage.idle;
    });
  }

  Future<void> _sendScore(NeonHopperState s) async {
    final String? sessionId = _sessionId;
    if (sessionId == null || _finishing) return;
    _finishing = true;
    setState(() => _resultStage = HopperResultStage.sending);
    try {
      await ref.read(gameSessionServiceProvider).finishSession(
            sessionId: sessionId,
            score: s.score,
            breakdown: s.breakdown(), // {stomps, coins, flagReached} EXATOS
          );
      if (!mounted) return;
      setState(() => _resultStage = HopperResultStage.validating);
      _listenServerResult(sessionId);
    } on GameSessionException {
      if (!mounted) return;
      setState(() => _resultStage = HopperResultStage.sendFailed);
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
              ? HopperResultStage.rejected
              : HopperResultStage.granted;
        });
      },
      onError: (Object _) {
        // Stream falhou (offline): permanece "em validação"; o runner
        // processa quando possível.
      },
    );
  }

  void _pause() {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.playing || s.endReason != null) {
      return;
    }
    _input.release();
    _game!.value = s.copyWith(phase: HopperPhase.paused, moveAxis: 0, jumpHeld: false);
  }

  void _resume() {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.paused) return;
    _lastElapsed = null;
    _game!.value = s.copyWith(phase: HopperPhase.playing);
  }

  /// Saída no meio da partida: envia o score parcial com breakdown para não
  /// deixar sessões órfãs; muito curta ⇒ backend rejeita com segurança.
  Future<void> _finishAndPop() async {
    final NeonHopperState? s = _game?.value;
    final NavigatorState nav = Navigator.of(context);
    if (_stage == _ScreenStage.playing && s != null && !_finishing) {
      _ticker.stop();
      _stage = _ScreenStage.finished;
      await _sendScore(s);
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
        final NeonHopperState? initial = _game?.value;
        if (initial == null) {
          return InstructionsOverlay(
            game: widget.game,
            onStart: _startSessionAndPlay,
            isLoading: false,
            error: _startError,
            onBack: () => Navigator.of(context).pop(),
          );
        }
        return ValueListenableBuilder<NeonHopperState>(
          valueListenable: _game!,
          builder: (BuildContext context, NeonHopperState s, _) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Campo de jogo (pintor único; sem input aqui).
              CustomPaint(painter: NeonHopperPainter(state: s, repaint: _game!)),

              // COUNTDOWN 3-2-1-GO (loop congelado; timer inicia no GO).
              if (!_countdownDone && s.endReason == null)
                _CountdownOverlay(onFinished: () {
                  if (!mounted) return;
                  setState(() => _countdownDone = true);
                  _lastElapsed = null;
                }),

              // HUD topo: score/tempo/vidas + pausa (ACIMA do input).
              Align(
                alignment: Alignment.topCenter,
                child: _HopperHud(
                  score: s.score,
                  timeLeft: s.timeLeft.ceil(),
                  lives: s.lives,
                  maxLives: _config.lives,
                  stomps: s.stomps,
                  coins: s.coinCount,
                  onPause: _pause,
                ),
              ),

              // CONTROLES (multi-toque real): joystick esquerda + pulo direita.
              if (_stage == _ScreenStage.playing &&
                  s.phase == HopperPhase.playing &&
                  s.endReason == null) ...<Widget>[
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: size.width * 0.5,
                  height: 170,
                  child: JoystickWidget(onAxis: _setAxis),
                ),
                Positioned(
                  right: 16,
                  bottom: 28,
                  width: 128,
                  height: 132,
                  child: JumpButton(onPress: _jumpDown, onRelease: _jumpUp),
                ),
              ],

              // Pausa (auto-pause por lifecycle também passa aqui).
              if (s.phase == HopperPhase.paused && s.endReason == null)
                _PauseOverlay(onResume: _resume, onQuit: _finishAndPop),

              // Resultado (breakdown + status do servidor).
              if (_stage == _ScreenStage.finished)
                ResultOverlay(
                  stage: _resultStage,
                  score: s.score,
                  stomps: s.stomps,
                  coins: s.coinCount,
                  flagReached: s.flagReached,
                  livesLeft: s.lives,
                  endReason: switch (s.endReason) {
                    HopperEndReason.timeUp => 'timeUp',
                    HopperEndReason.dead => 'dead',
                    HopperEndReason.flag => 'flag',
                    null => null,
                  },
                  serverResult: _serverResult,
                  onCollect: (_resultStage == HopperResultStage.idle ||
                          _resultStage == HopperResultStage.sendFailed)
                      ? () => _sendScore(s)
                      : null,
                  onBack: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        );
    }
  }

  void _setAxis(double axis) {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.playing || s.endReason != null) return;
    _game!.value = s.copyWith(moveAxis: axis);
  }

  void _jumpDown() {
    final NeonHopperState? s = _game?.value;
    if (s == null || s.phase != HopperPhase.playing || s.endReason != null) return;
    _game!.value = s.copyWith(jumpHeld: true, jumpBufferTimer: 0.12);
  }

  void _jumpUp() {
    final NeonHopperState? s = _game?.value;
    if (s == null) return;
    // Soltar cedo durante a subida corta o impulso pela metade (no step).
    _game!.value = s.copyWith(jumpHeld: false, jumpCut: s.player.vy < 0);
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _HopperHud extends StatelessWidget {
  const _HopperHud({
    required this.score,
    required this.timeLeft,
    required this.lives,
    required this.maxLives,
    required this.stomps,
    required this.coins,
    required this.onPause,
  });

  final int score;
  final int timeLeft;
  final int lives;
  final int maxLives;
  final int stomps;
  final int coins;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'SCORE $score',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: AppColors.cyan,
                  ),
                ),
                Text(
                  '👣$stomps  ◉$coins',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '$timeLeft',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: timeLeft <= 10 ? AppColors.error : AppColors.gold,
            ),
          ),
          const SizedBox(width: 12),
          // Vidas: corações cheios/vazios.
          for (int i = 0; i < maxLives; i++)
            Icon(
              Icons.favorite,
              size: 16,
              color: i < lives ? AppColors.error : AppColors.textSecondary.withValues(alpha: 0.4),
            ),
          IconButton(
            onPressed: onPause,
            icon: const Icon(Icons.pause, size: 20, color: AppColors.textSecondary),
            tooltip: 'Pausar',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown 3-2-1-GO
// ---------------------------------------------------------------------------

class _CountdownOverlay extends StatefulWidget {
  const _CountdownOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<_CountdownOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
    _ctrl.addStatusListener((AnimationStatus st) {
      if (st == AnimationStatus.completed) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext context, _) {
          final double t = _ctrl.value;
          final String label = t < 0.33 ? '3' : t < 0.66 ? '2' : t < 0.95 ? '1' : 'GO!';
          return ColoredBox(
            color: AppColors.background.withValues(alpha: 0.45),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: label == 'GO!' ? AppColors.green : AppColors.cyan,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pausa
// ---------------------------------------------------------------------------

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
