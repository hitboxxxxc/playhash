/**
 * PlayHash — tipos centrais da economia (doc 05).
 *
 * REGRA DE OURO: todo valor econômico é INTEIRO em "units"
 * (1 coin = coinPrecision units) e manipulado como BigInt.
 * NUNCA usar float/double para valores econômicos.
 */

export type Int = bigint;

export interface EconomyLimits {
  /** Máximo de sessões de jogo processadas por usuário por dia (UTC). */
  maxSessionsPerDay: number;
  /** Máximo de intenções de compra processadas por usuário por dia (UTC). */
  maxPurchaseIntentsPerDay: number;
  /** Máximo de claims (missões/conquistas) concedidos por usuário por dia (UTC). */
  maxClaimsPerDay: number;
  /** Duração mínima aceitável de sessão (ms). */
  minSessionDurationMs: number;
  /** Duração máxima aceitável de sessão (ms). */
  maxSessionDurationMs: number;
  /** Cap de score por segundo (anti-autoplay/cheat). */
  maxScorePerSecond: number;
  /** Duração do poder temporário concedido por partida (24h). */
  tempGrantDurationMs: number;
  /** Tamanho máximo de lote por execução do runner. */
  maxBatchSize: number;
  /** Máximo de usuários considerados em um bloco (proteção de cota Spark). */
  maxUsersPerBlock: number;
}

export interface EconomyConfig {
  /** Recompensa base por bloco, em units (BigInt). */
  blockRewardUnits: bigint;
  /** Intervalo do bloco (300000 = 5 min). */
  blockIntervalMs: number;
  /** Casas decimais da moeda em units (1_000_000 => 6 casas). */
  coinPrecision: number;
  /** Base de power padrão (usada quando o game não define powerBaseReward). */
  powerBasePerHs: number;
  /** Resíduo determinístico carregado para o próximo bloco (units). */
  residueUnits: bigint;
  /** Versão da regra econômica — propagada para grants/auditoria/transações. */
  economicRuleVersion: number;
  limits: EconomyLimits;
}

/**
 * configuration dentro de games/{gameId}.
 *
 * Campos legados (tap-blitz/reflex-rush): powerBaseReward + powerCapPerSession
 * (fórmula proporcional simples).
 * Campos estendidos (nova-swarm em diante): duração nominal, limites de score
 * por game e fórmula `linear_cap`:
 *   power = floor(min(score / maxExpectedScore, 1) × powerCapPerSessionBaseUnits)
 * Todos os campos estendidos são OPCIONAIS (0/'' = ausente) para manter
 * compatibilidade com docs antigos já semeados.
 */
export interface GameConfiguration {
  maxExpectedScore: number;
  powerBaseReward: number;
  powerCapPerSession: number;
  /** Duração nominal da partida em segundos (0 = sem duração nominal). */
  durationSeconds: number;
  /** Score máximo ABSOLUTO aceito (0 = usa maxExpectedScore). */
  maxScore: number;
  /** Cap de score/segundo específico do game (0 = usa limite da economia). */
  maxScorePerSecond: number;
  /** Duração mínima específica do game em segundos (0 = usa limite da economia). */
  minDurationSeconds: number;
  /** Cap de poder por sessão em UNITS (não em H). */
  powerCapPerSessionBaseUnits: number;
  /** 'linear_cap' | '' (legado). */
  powerFormula: string;
  /** Pontos por abate (0 = game sem contagem de inimigos). */
  pointsPerKill: number;
}

export interface GameDoc {
  id: string;
  enabled: boolean;
  configuration: GameConfiguration | null;
}

export interface MachineDoc {
  id: string;
  name: string;
  priceUnits: bigint;
  /** Poder da máquina em H/s (unidade-base inteira). */
  powerAmount: bigint;
  currencyId: string;
  enabled: boolean;
  /** Raridade v2 (common|rare|epic|legendary). '' = legado sem raridade. */
  rarity: string;
  /** Limite de unidades por usuário (0 = sem limite configurado). */
  maxPerUser: number;
}

/** Documento tempGrants/{grantId} (poder temporário de 24h). */
export interface TempGrantData {
  uid: string;
  powerAmount: bigint;
  source: 'game';
  acquiredAtMs: number;
  expiresAtMs: number;
  gameId?: string;
  gameSessionId?: string;
  economicRuleVersion: number;
  expired: boolean;
}

export interface GrantRecord extends TempGrantData {
  grantId: string;
}

export interface PowerSnapshot {
  permanentPower: bigint;
  totalPower: bigint;
}

export type AuditStatus = 'SUCCESS' | 'REJECTED' | 'FAILED';

export interface AuditEntry {
  /** Determinístico: `${type}:${referenceId}` ⇒ append-only idempotente. */
  eventId: string;
  userId: string | null;
  type: AuditEventType;
  valueUnits?: bigint | null;
  currencyId?: string | null;
  referenceId: string;
  origin: string;
  ruleVersion: number;
  status: AuditStatus;
  detail?: Record<string, unknown>;
}

export type AuditEventType =
  | 'GAME_POWER_GRANTED'
  | 'GAME_POWER_EXPIRED'
  | 'GAME_SESSION_REJECTED'
  | 'MACHINE_PURCHASED'
  | 'PURCHASE_FAILED'
  | 'BLOCK_CREATED'
  | 'BLOCK_FINALIZED'
  | 'REWARD_CREDITED'
  | 'MISSION_REWARD_GRANTED'
  | 'ACHIEVEMENT_REWARD_GRANTED'
  | 'CLAIM_REJECTED'
  | 'DEV_TOPUP'
  | 'LEAGUE_PROMOTED'
  | 'LEAGUE_REWARD_GRANTED'
  | 'SEASON_XP_GRANTED'
  | 'SEASON_REWARD_GRANTED'
  // Anúncios (doc 04/05 §31) — recompensa validada SOMENTE no backend.
  | 'AD_REWARD_GRANTED'
  | 'AD_REWARD_REJECTED'
  // Saques (doc 05 §26/§51) — intents processados pelo runner.
  | 'WITHDRAWAL_REQUESTED'
  | 'WITHDRAWAL_RESERVED'
  | 'WITHDRAWAL_COMPLETED'
  | 'WITHDRAWAL_FAILED'
  // Micro-teste live opcional (payoutLiveTest; NÃO reserva saldo de usuário).
  | 'WITHDRAWAL_TEST'
  | 'REWARD_REVERSED'
  | 'ACCOUNT_ECONOMIC_LOCK';

export interface ProcessingSummary {
  scanned: number;
  granted: number;
  rejected: number;
  failed: number;
}
