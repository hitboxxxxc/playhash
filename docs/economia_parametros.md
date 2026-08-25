# Economia — Parâmetros Oficiais

Registro histórico das decisões econômicas do PlayHash. A AUTORIDADE é sempre
o backend (`config/economy` + runner); o cliente apenas EXIBE valores
fornecidos pelo servidor (doc 05 §51 — cliente nunca define BLOCK_REWARD ou
participação).

---

## BLOCK_REWARD = 5 COIN por bloco (12.23)

| Campo | Valor |
|---|---|
| Parâmetro | `config/economy.blockRewardUnits` |
| Valor | **5.000.000 units** (= **5 COIN**, `coinPrecision` = 1.000.000) |
| Intervalo do bloco | `blockIntervalMs` = 300.000 ms (**5 minutos**) |
| Versão econômica | `economicRuleVersion` = **2** (bump idempotente via seed) |
| Data da decisão | 2026-08-25 |
| Decisão | **DO DONO DO PROJETO** — BLOCK_REWARD = 5 COIN a cada bloco de 5 minutos |

### Regras de distribuição (doc 05 §21/§39)

- **1 jogador elegível**: recebe os **5 COIN cheios** (5.000.000 units).
- **Múltiplos jogadores**: cada um recebe
  `floor(BLOCK_REWARD × USER_POWER / NETWORK_POWER)`, onde
  `NETWORK_POWER = Σ totalPower` dos elegíveis (`totalPower > 0`).
- **Resíduo**: o que não puder ser distribuído pela divisão inteira fica em
  `config/economy.residueUnits` e é carregado para o próximo bloco
  (conservação: `distribuído + resíduo = reward efetivo`).
- **Idempotência**: `blocks/{periodKey}` com status `finalized` + transações
  com ID determinístico — o mesmo bloco nunca é processado 2×.
- **Auditoria**: `BLOCK_CREATED`, `BLOCK_FINALIZED` e `REWARD_CREDITED` em
  `auditLogs`, todos com o `ruleVersion` vigente no fechamento.
- Transações/históricos ANTIGOS preservam o `ruleVersion` com que foram
  gravados (doc 05 §44) — o bump não reescreve o passado.

### Exibição na MINERAÇÃO (doc 05 §47/§48)

- Fonte única: espelho público `blocks/current`, escrito SOMENTE pelo runner:
  - `totalBlockRewardMinimalUnits` — recompensa-base da config ("RECOMPENSA
    DO BLOCO: 5 COIN");
  - `networkPower` — poder total da rede no último bloco finalizado;
  - `nextBlockAt` — próximo múltiplo de 5 min do relógio do SERVIDOR
    (countdown "Próximo bloco em mm:ss" — display apenas).
- "Sua participação estimada" = `totalPower próprio / networkPower ×
  recompensa do bloco`, SEMPRE rotulada **ESTIMADA** — não é promessa de
  crédito; o crédito real ocorre no fechamento do bloco pelo runner.

### Implementação

- Seed idempotente: `backend/src/seed.ts` → `upgradeEconomyBlockRewardV2`
  (merge apenas de `blockRewardUnits` + `economicRuleVersion`; nunca toca em
  `residueUnits`/`lastFinalizedPeriodKey`/`limits`). Rodar novamente = no-op.
- Distribuição: `backend/src/processors/closeBlocks.ts` (lê BLOCK_REWARD
  EXCLUSIVAMENTE da config — nenhum valor hardcoded).
- Testes: `backend/src/tests/blockDistribution.test.ts` (casos 5 COIN).
- UI: `lib/features/mining/widgets/block_reward_card.dart`,
  `lib/features/mining/widgets/next_block_countdown.dart`.
