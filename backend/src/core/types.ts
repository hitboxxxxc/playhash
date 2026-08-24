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

/** configuration dentro de games/{gameId}. */
export interface GameConfiguration {
  maxExpectedScore: number;
  powerBaseReward: number;
  powerCapPerSession: number;
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
  powerAmount: bigint;
  currencyId: string;
  enabled: boolean;
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
  | 'REWARD_CREDITED';

export interface ProcessingSummary {
  scanned: number;
  granted: number;
  rejected: number;
  failed: number;
}
