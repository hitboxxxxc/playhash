import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/pixel_theme.dart';
import '../../core/utils/coin_format.dart';
import '../../core/utils/power_format.dart';
import '../../core/widgets/next_block_countdown.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../core/widgets/section_title.dart';
import '../../data/models/power_model.dart';
import '../../data/repositories/mining_repository.dart';

/// Aba HOME (pixel) — DADOS REAIS copiados da [HomeScreen] antiga:
///   - stream de [PowerModel] (`powerStreamProvider`) -> totalPower;
///   - MESMO formatador de poder ([PowerFormat.format]) — H/s → KH/s → ... → YH/s;
///   - [MiningRepository.estimateReward] -> chip dourado `<valor> COIN`
///     (mesma fonte da home/mineração; null => `0 COIN`);
///   - ticker [NextBlockCountdown] `Próxima recompensa em mm:ss` usando o
///     MESMO widget compartilhado da MINERAÇÃO (alinhado ao servidor).
///
/// Enquadramento: card com chip full-width + FittedBox + texto 10/letterSpacing
/// 0.5 (sem truncar), colunas com Expanded + divisor vertical, paddings 12,
/// Row com crossAxisAlignment.center. Linha do countdown ABAIXO do card.
class PixelHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onPlayGames;

  const PixelHomeScreen({super.key, required this.onPlayGames});

  @override
  ConsumerState<PixelHomeScreen> createState() => _PixelHomeScreenState();
}

class _PixelHomeScreenState extends ConsumerState<PixelHomeScreen> {
  static const TextStyle labelPurple =
      TextStyle(color: PixelTheme.purple, fontSize: 12);
  static const TextStyle textCianoBold = TextStyle(
    color: PixelTheme.cyan,
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );
  static const TextStyle textVerdeBold = TextStyle(
    color: PixelTheme.green,
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );
  static const TextStyle textRoxoBold = TextStyle(
    color: PixelTheme.purple,
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );
  static const TextStyle textDouradoBold20 = TextStyle(
    color: PixelTheme.gold,
    fontWeight: FontWeight.bold,
    fontSize: 20,
  );

  /// Snapshot oficial de bloco (`blocks/current`) — fonte do horário.
  /// Tolerante a backend ausente: falha => null => "--:--" (NUNCA inventado).
  BlockSnapshot? _block;

  StreamSubscription<BlockSnapshot?>? _blockSub;

  @override
  void initState() {
    super.initState();
    _subscribeBlock();
  }

  @override
  void dispose() {
    _blockSub?.cancel();
    super.dispose();
  }

  /// Stream do bloco em tempo real (mesma fonte da home/mineração antiga).
  /// Falha => null (estado vazio — nunca quebra a tela).
  void _subscribeBlock() {
    try {
      _blockSub ??= ref
          .read(miningRepositoryProvider)
          .watchBlockSnapshot()
          .listen(
            (BlockSnapshot? block) {
              if (!mounted) return;
              setState(() => _block = block);
            },
            onError: (Object _) {/* estado vazio — nunca quebra a tela */},
          );
    } catch (_) {/* sem backend => "--:--" */}
  }

  /// Valor formatado do poder total (MESMO formatador da home antiga).
  /// `null` ou 0 => "0" (nunca "—" com dado existente — fonte oficial).
  String _formatPowerText(int? totalPower) {
    if (totalPower == null || totalPower <= 0) return '0';
    // Extrai apenas a parte numérica (sem unidade) — unidade vai no label roxo.
    final String formatted = PowerFormat.format(totalPower);
    final int spaceIdx = formatted.indexOf(' ');
    return spaceIdx > 0 ? formatted.substring(0, spaceIdx) : formatted;
  }

  /// Unidade do poder formatado (ex.: "H/s", "PH/s"). 0 => "H/s".
  String _formatPowerUnit(int? totalPower) {
    if (totalPower == null || totalPower <= 0) return 'H/s';
    final String formatted = PowerFormat.format(totalPower);
    final int spaceIdx = formatted.indexOf(' ');
    return spaceIdx > 0 ? formatted.substring(spaceIdx + 1) : 'H/s';
  }

  /// Chip dourado da recompensa estimada: `<valor> COIN`.
  /// `null` => `0 COIN` (nunca `—` com dado existente).
  String _formatRewardChip(BigInt? minimalUnits) {
    if (minimalUnits == null) return '0 COIN';
    return CoinFormat.formatWithTicker(minimalUnits);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PowerModel?> powerAsync = ref.watch(powerStreamProvider);
    final PowerModel? power = powerAsync.value;
    final int? totalPower = power?.totalPower;

    // Estimativa oficial (servidor) — mesma fonte da home/mineração antiga.
    final RewardEstimate? estimate = ref
        .read(miningRepositoryProvider)
        .estimateReward(yourPower: totalPower ?? 0, block: _block);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          PixelCard(
            borderColor: PixelTheme.purple,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PixelTheme.purpleDark,
                    border: Border.all(color: PixelTheme.purple, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PixelIcon(
                        matrix: PixelIcons.pickaxe,
                        palette: PixelIcons.palette,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'SEU PODER DE MINERAÇÃO',
                            style: PixelTheme.title,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PixelIcon(
                        matrix: PixelIcons.pickaxe,
                        palette: PixelIcons.palette,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Row de conteúdo: colunas com Expanded + divisor vertical +
                // crossAxisAlignment.center. Paddings 12.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text('PODER ATUAL', style: PixelTheme.label),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PixelIcon(
                                matrix: PixelIcons.pickaxe,
                                palette: PixelIcons.palette,
                                size: 40,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Column(
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _formatPowerText(totalPower),
                                        style: PixelTheme.bigValue,
                                        maxLines: 1,
                                      ),
                                    ),
                                    Text(
                                      _formatPowerUnit(totalPower),
                                      style: labelPurple,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: PixelTheme.border),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'RECOMPENSA A CADA 5 MINUTOS',
                            style: PixelTheme.label,
                          ),
                          const SizedBox(height: 8),
                          PixelIcon(
                            matrix: PixelIcons.coin,
                            palette: PixelIcons.palette,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatRewardChip(
                              estimate?.estimatedRewardMinimalUnits,
                            ),
                            style: PixelTheme.label.copyWith(
                              color: PixelTheme.gold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Chip full-width da coluna de poder (sem truncar).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PixelTheme.purpleDark,
                    border: Border.all(color: PixelTheme.purple, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'PODER DE MINERAÇÃO TOTAL',
                      style: const TextStyle(
                        color: PixelTheme.purple,
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Linha do countdown abaixo do card de poder (mesma widget da antiga).
          // Envolta em FittedBox para escalar em telas estreitas (320dp) sem
          // cortar o rótulo/tempo.
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: NextBlockCountdown(
                block: _block,
                label: 'Próxima recompensa em',
                fontSize: 12,
                centered: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SectionTitle(text: 'GANHE COIN'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {}, // Navigate to /missions
                  child: PixelCard(
                    borderColor: PixelTheme.cyan,
                    child: Column(
                      children: [
                        PixelIcon(
                          matrix: PixelIcons.clipboard,
                          palette: PixelIcons.palette,
                          size: 56,
                        ),
                        const SizedBox(height: 8),
                        Text('FAÇA TAREFAS', style: textCianoBold),
                        const SizedBox(height: 4),
                        Text(
                          'Complete tarefas e ganhe coins!',
                          style: PixelTheme.label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onPlayGames,
                  child: PixelCard(
                    borderColor: PixelTheme.green,
                    child: Column(
                      children: [
                        PixelIcon(
                          matrix: PixelIcons.gamepad,
                          palette: PixelIcons.palette,
                          size: 56,
                        ),
                        const SizedBox(height: 8),
                        Text('JOGUE MINIGAMES', style: textVerdeBold),
                        const SizedBox(height: 4),
                        Text(
                          'Divirta-se e ganhe coins jogando!',
                          style: PixelTheme.label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _bonus(context),
            child: PixelCard(
              borderColor: PixelTheme.purple,
              child: Row(
                children: [
                  PixelIcon(
                    matrix: PixelIcons.gift,
                    palette: PixelIcons.palette,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BÔNUS DIÁRIO', style: textRoxoBold),
                        const SizedBox(height: 4),
                        Text(
                          'Resgate seu bônus diário e ganhe mais coins!',
                          style: PixelTheme.label,
                        ),
                      ],
                    ),
                  ),
                  Text('>', style: textDouradoBold20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _bonus(BuildContext context) {
    // Show rewarded ad sheet from store
  }
}
