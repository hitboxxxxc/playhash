import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/providers.dart';
import '../../core/theme/pixel_theme.dart';
import '../../core/utils/power_format.dart';
import '../../core/widgets/next_block_countdown.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/services/offline_mining_service.dart';
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
/// Estrutura:
///   - Expanded + SingleChildScrollView (conteúdo rola: card poder, countdown, GANHE COIN)
///   - BÔNUS DIÁRIO fixo embaixo (Padding), quase colado na BottomNav
///   - SafeArea topo/baixo vem do [PixelShell].
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
  bool _idleDialogShown = false;
  Timer? _offlineTimer;

  @override
  void initState() {
    super.initState();
    _subscribeBlock();
    _checkIdleRewards();
    _startOfflineMiningTimer();
  }

  @override
  void dispose() {
    _blockSub?.cancel();
    _offlineTimer?.cancel();
    super.dispose();
  }

  void _startOfflineMiningTimer() {
    // run once now (boot: check-in diário + coleta offline; dialog se > 0)
    unawaited(_bootCollect());
    // then every 5 minutes while app is in foreground
    _offlineTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        unawaited(OfflineMiningService.collect());
      }
    });
  }

  /// Coleta no BOOT (14.11-FIX2): chama [OfflineMiningService.collect] 1×;
  /// se creditou moedas, mostra o dialog "ENQUANTO VOCÊ ESTEVE FORA".
  Future<void> _bootCollect() async {
    try {
      final OfflineCollectResult r = await OfflineMiningService.collect();
      if (!mounted || r.coins <= 0) return;
      final walletAsync = ref.read(walletStreamProvider);
      _showIdleDialog(_fmtCoins2(r.coins), walletAsync.value?.availableBalance);
    } catch (e) {
      debugPrint('Boot offline collect failed: $e');
    }
  }

  /// Formata unidades mínimas (escala 1e6) como decimal pt-BR "1.234,56".
  String _fmtCoins2(int units) {
    final BigInt scale = BigInt.from(1000000);
    final BigInt whole = BigInt.from(units) ~/ scale;
    final BigInt frac = (BigInt.from(units) % scale).abs();
    return '${_groupThousands(whole.toString())},${frac.toString().padLeft(6, '0').substring(0, 2)}';
  }

  /// Botão "COLETAR RECOMPENSAS OFFLINE" (14.11-FIX2) — chama
  /// [OfflineMiningService.collect] e mostra SnackBar conforme o reason:
  ///  - 'ok'       → verde "+`<valor>` COIN coletados (`<n>` períodos)";
  ///  - 'nada'     → "Nada a coletar agora";
  ///  - 'sem_poder'→ "Compre máquinas ou jogue para gerar poder".
  /// O stream de `wallets/{uid}` (walletStreamProvider) atualiza o saldo
  /// automaticamente após a transação.
  Future<void> _collectOffline() async {
    try {
      final OfflineCollectResult r = await OfflineMiningService.collect();
      if (!mounted) return;
      final String message;
      final Color color;
      if (r.reason == 'ok') {
        message = '+${_fmtCoins2(r.coins)} COIN coletados (${r.periods} períodos)';
        color = PixelTheme.green;
      } else if (r.reason == 'sem_poder') {
        message = 'Compre máquinas ou jogue para gerar poder';
        color = PixelTheme.purple;
      } else {
        message = 'Nada a coletar agora';
        color = PixelTheme.purple;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Offline collect failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao coletar recompensas offline'),
          backgroundColor: PixelTheme.purple,
        ),
      );
    }
  }

  /// Verifica recompensas ociosas ("enquanto você esteve fora") na inicialização.
  /// 1. Lê users/{uid}.lastLoginAt (prev) ANTES de qualquer update.
  /// 2. Lê rewards/{uid}/items limit 200 (sem orderBy), soma amount dos createdAt em (prev, agora].
  /// 3. Se soma > 0 → Dialog pixel.
  /// 4. Depois: users/{uid}.update({'lastLoginAt': Timestamp.now()}).
  Future<void> _checkIdleRewards() async {
    try {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _idleDialogShown) return;
      _idleDialogShown = true;

      final db = FirebaseFirestore.instance;
      final userRef = db.doc('users/$uid');

      // 1. Ler lastLoginAt anterior
      final userSnap = await userRef.get();
      final prevLogin = userSnap.get('lastLoginAt') as Timestamp?;
      if (prevLogin == null) {
        // Primeiro login, apenas atualiza lastLoginAt
        await userRef.update({'lastLoginAt': FieldValue.serverTimestamp()});
        return;
      }
      final prevLoginMs = prevLogin.toDate().millisecondsSinceEpoch;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 2. Ler rewards/{uid}/items (limit 200, sem orderBy)
      final rewardsSnap = await db
          .collection('rewards/$uid/items')
          .limit(200)
          .get();

      BigInt totalCoins = BigInt.zero;
      for (final doc in rewardsSnap.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final amountStr = data['amount'] as String?;
        final type = data['type'] as String?;
        final currencyId = data['currencyId'] as String?;

        if (createdAt == null || amountStr == null) continue;
        if (type != 'REWARD_BLOCK') continue; // apenas blocos de mineração
        if (currencyId != 'coins') continue;

        final createdMs = createdAt.toDate().millisecondsSinceEpoch;
        if (createdMs > prevLoginMs && createdMs <= nowMs) {
          totalCoins += BigInt.tryParse(amountStr) ?? BigInt.zero;
        }
      }

      // 3. Se soma > 0 → Dialog pixel
      if (totalCoins > BigInt.zero && mounted) {
        // Converter para string formatada pt-BR
        final scale = BigInt.from(1000000);
        final whole = totalCoins ~/ scale;
        final frac = (totalCoins % scale).abs();
        final wholeStr = _groupThousands(whole.toString());
        final fracStr = frac.toString().padLeft(6, '0').substring(0, 2);
        final formatted = '$wholeStr,$fracStr COIN';

        // Get current balance for dialog
        final walletAsync = ref.watch(walletStreamProvider);
        final currentBalance = walletAsync.value?.availableBalance;
        _showIdleDialog(formatted, currentBalance);
      }

      // 4. Atualizar lastLoginAt
      await userRef.update({'lastLoginAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // Falha silenciosa - não quebra a tela (ex.: testes sem Firebase mockado)
      debugPrint('Idle rewards check failed: $e');
    }
  }

  /// Formata BigInt (unidades mínimas 1e6) para string pt-BR "1.234,56 COIN"
  String _formatBalance(BigInt? balance) {
    if (balance == null || balance == BigInt.zero) return '0,00 COIN';
    final BigInt scale = BigInt.from(1000000);
    final BigInt whole = balance ~/ scale;
    final BigInt frac = (balance % scale).abs();
    final String wholeStr = _groupThousands(whole.toString());
    final String fracStr = frac.toString().padLeft(6, '0').substring(0, 2);
    return '$wholeStr,$fracStr COIN';
  }

  void _showIdleDialog(String formattedCoins, BigInt? currentBalance) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => Dialog(
        backgroundColor: PixelTheme.panel,
        child: Container(
          decoration: BoxDecoration(
            color: PixelTheme.panel,
            border: Border.all(color: PixelTheme.gold, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PixelIcon(
                        matrix: PixelIcons.coin,
                        palette: PixelIcons.palette,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ENQUANTO VOCÊ ESTEVE FORA',
                        style: TextStyle(
                          color: PixelTheme.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Suas máquinas e poder geraram, mesmo com o app fechado:',
                textAlign: TextAlign.center,
                style: PixelTheme.label,
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '+$formattedCoins',
                  style: const TextStyle(
                    color: PixelTheme.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Este valor JÁ foi somado ao seu saldo pelo servidor.',
                textAlign: TextAlign.center,
                style: PixelTheme.label,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Saldo atual: ${_formatBalance(currentBalance)}',
                  style: const TextStyle(
                    color: PixelTheme.greenLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PixelButton(
                label: 'ENTENDI',
                style: PixelButtonStyle.green,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
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

  /// Chip dourado da recompensa estimada: `<valor> COIN` com 2 casas decimais
  /// (ex.: `4,90 COIN`; se 0 => `0,00 COIN`). NUNCA `—` com dado existente.
  String _formatRewardChip(BigInt? minimalUnits) {
    if (minimalUnits == null || minimalUnits == BigInt.zero) {
      return '0,00 COIN';
    }
    // Converte unidades mínimas (escala 1e6) para decimal pt-BR com 2 casas.
    final BigInt scale = BigInt.from(1000000);
    final BigInt whole = minimalUnits ~/ scale;
    final BigInt frac = (minimalUnits % scale).abs();
    final String wholeStr = _groupThousands(whole.toString());
    final String fracStr = frac.toString().padLeft(6, '0').substring(0, 2);
    return '$wholeStr,$fracStr COIN';
  }

  /// Agrupa a parte inteira em blocos de 3 com `.` (pt-BR).
  String _groupThousands(String digits) {
    final StringBuffer out = StringBuffer();
    final int len = digits.length;
    for (int i = 0; i < len; i++) {
      out.write(digits[i]);
      final int remaining = len - i - 1;
      if (remaining > 0 && remaining % 3 == 0) out.write('.');
    }
    return out.toString();
  }

  /// Card "COLETAR RECOMPENSAS OFFLINE" (14.11) — o check-in diário é feito
  /// automaticamente pelo serviço no boot ([_startOfflineMiningTimer]); este
  /// botão reexecuta a coleta sob demanda e mostra SnackBar "+X COIN".
  Widget _buildCheckInCard() {
    return PixelCard(
      borderColor: PixelTheme.purple,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text(
            'COLETAR RECOMPENSAS OFFLINE',
            style: TextStyle(
              color: PixelTheme.purple,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PixelTheme.panel,
              border: Border.all(
                color: PixelTheme.green,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Check-in diário automático mantém suas máquinas ATIVAS por 24h.\n'
              'Períodos de 5 min não processados são creditados aqui.',
              style: TextStyle(
                color: PixelTheme.text,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          PixelButton(
            label: 'COLETAR RECOMPENSAS OFFLINE',
            style: PixelButtonStyle.purple,
            onPressed: _collectOffline,
          ),
        ],
      ),
    );
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

    // --- WIDGETS REUTILIZÁVEIS (extraídos inline para clareza) ---

    // Card roxo: SEU PODER DE MINERAÇÃO
    final Widget powerCard = PixelCard(
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
    );

    // Linha do countdown
    final Widget countdownLine = Padding(
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
    );

    // Row GANHE COIN: FAÇA TAREFAS + JOGUE MINIGAMES
    final Widget earnRow = Row(
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
    );

    // Card BÔNUS DIÁRIO (fixo embaixo)
    final Widget bonusCard = GestureDetector(
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
    );

    // --- ESTRUTURA FINAL ---
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              children: [
                powerCard,
                const SizedBox(height: 12),
                countdownLine,
                const SizedBox(height: 12),
                _buildCheckInCard(),
                const SizedBox(height: 12),
                const SectionTitle(text: 'GANHE COIN'),
                const SizedBox(height: 8),
                earnRow,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: bonusCard,
        ),
      ],
    );
  }

  void _bonus(BuildContext context) {
    // Show rewarded ad sheet from store
  }
}
