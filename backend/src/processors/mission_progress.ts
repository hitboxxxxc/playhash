/**
 * Progresso de MISSÕES e CONQUISTAS — helpers idempotentes usados pelos
 * processadores do runner (doc 05: o cliente NUNCA escreve progresso).
 *
 * Modelo:
 *  - Missões: userMissions/{uid}/items/{missionId} com periodKey
 *    (daily = YYYY-MM-DD UTC, weekly = YYYY-Www ISO). Troca de período
 *    => progresso reinicia (claimed preservado).
 *  - Conquistas: userAchievements/{uid}/items/{achievementId} SEM reset
 *    (cumulativo ou máximo histórico).
 *
 * Idempotência: o progresso só é aplicado quando o EVENTO de origem é
 * consolidado (session granted/created, purchase done, claim concedido) —
 * todos com guardas determinísticas próprias. Reexecução do mesmo evento
 * não re-aplica (as guardas dos processadores impedem).
 *
 * Funções PURAS (periodKeyFor, computeProgress, validateKillsConsistency)
 * são unit-testáveis sem Firestore.
 */
import { FieldValue, Firestore, WriteBatch } from 'firebase-admin/firestore';

// ---------------------------------------------------------------------------
// Períodos (PURO)
// ---------------------------------------------------------------------------

export type MissionKind = 'daily' | 'weekly' | 'season';

/** Chave ISO-8601 de semana UTC: YYYY-Www (semana começa na segunda). */
export function isoWeekKey(date: Date): string {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  const dayNum = d.getUTCDay() || 7; // Mon=1..Sun=7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // quinta da semana ISO
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7,
  );
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/** periodKey da missão: daily = YYYY-MM-DD, weekly = YYYY-Www (UTC). */
export function periodKeyFor(kind: MissionKind, nowMs: number): string {
  const date = new Date(nowMs);
  if (kind === 'daily') return date.toISOString().slice(0, 10);
  return isoWeekKey(date);
}

// ---------------------------------------------------------------------------
// Progresso (PURO)
// ---------------------------------------------------------------------------

export type ProgressMode = 'add' | 'max';

/**
 * Calcula o novo progresso. Se o doc do usuário está em outro período
 * (missão), o progresso parte de 0 (reset de período). 'add' acumula;
 * 'max' retém o maior valor histórico do período (ex.: pontos numa partida).
 */
export function computeProgress(input: {
  currentProgress: number;
  currentPeriodKey: string;
  expectedPeriodKey: string;
  mode: ProgressMode;
  value: number;
}): number {
  const base =
    input.currentPeriodKey === input.expectedPeriodKey
      ? input.currentProgress
      : 0;
  return input.mode === 'add' ? base + input.value : Math.max(base, input.value);
}

/**
 * Consistência de kills (PURO): kills ≥ 0 inteiro e, quando o game define
 * pointsPerKill, kills × pointsPerKill ≤ score (cada abate vale PELO MENOS
 * pointsPerKill — waveBonus/hits só adicionam). Retorna null quando ok.
 */
export function validateKillsConsistency(
  kills: unknown,
  score: number,
  pointsPerKill: number,
): string | null {
  if (kills === undefined || kills === null) return null; // opcional (legado)
  if (typeof kills !== 'number' || !Number.isSafeInteger(kills) || kills < 0) {
    return 'KILLS_INVALID';
  }
  if (kills > 0) {
    if (pointsPerKill <= 0) return 'KILLS_NOT_SUPPORTED';
    if (kills * pointsPerKill > score) return 'KILLS_INCONSISTENT';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Catálogos (cache curto — leitura admin)
// ---------------------------------------------------------------------------

export interface MissionCatalogItem {
  id: string;
  kind: MissionKind;
  metric: string;
  target: number;
  enabled: boolean;
  /** periodKey fixo (missões de temporada); '' para daily/weekly. */
  periodKey: string;
}

export interface AchievementCatalogItem {
  id: string;
  metric: string;
  target: number;
  enabled: boolean;
}

const CATALOG_TTL_MS = 60_000;
let missionsCache: { value: MissionCatalogItem[]; loadedAt: number } | null = null;
let achievementsCache: { value: AchievementCatalogItem[]; loadedAt: number } | null =
  null;

/** Visível para testes/injeção. */
export function invalidateMissionCatalogCache(): void {
  missionsCache = null;
  achievementsCache = null;
}

function numOr0(v: unknown): number {
  const n = Number(v);
  return Number.isSafeInteger(n) && n > 0 ? n : 0;
}

export async function loadMissionCatalog(
  db: Firestore,
): Promise<MissionCatalogItem[]> {
  if (missionsCache && Date.now() - missionsCache.loadedAt < CATALOG_TTL_MS) {
    return missionsCache.value;
  }
  const snap = await db.collection('missions').get();
  const value: MissionCatalogItem[] = [];
  for (const doc of snap.docs) {
    const rawKind = doc.get('kind');
    const kind: MissionKind =
      rawKind === 'weekly' ? 'weekly' : rawKind === 'season' ? 'season' : 'daily';
    const metric = doc.get('metric');
    const target = numOr0(doc.get('target'));
    if (typeof metric !== 'string' || metric.length === 0 || target <= 0) continue;
    value.push({
      id: doc.id,
      kind,
      metric,
      target,
      enabled: doc.get('enabled') === true,
      // Temporada: periodKey fixo do doc; daily/weekly: resolvido por evento.
      periodKey: kind === 'season' ? String(doc.get('periodKey') ?? '') : '',
    });
  }
  missionsCache = { value, loadedAt: Date.now() };
  return value;
}

export async function loadAchievementCatalog(
  db: Firestore,
): Promise<AchievementCatalogItem[]> {
  if (achievementsCache && Date.now() - achievementsCache.loadedAt < CATALOG_TTL_MS) {
    return achievementsCache.value;
  }
  const snap = await db.collection('achievements').get();
  const value: AchievementCatalogItem[] = [];
  for (const doc of snap.docs) {
    const metric = doc.get('metric');
    const target = numOr0(doc.get('target'));
    if (typeof metric !== 'string' || metric.length === 0 || target <= 0) continue;
    value.push({
      id: doc.id,
      metric,
      target,
      enabled: doc.get('enabled') === true,
    });
  }
  achievementsCache = { value, loadedAt: Date.now() };
  return value;
}

// ---------------------------------------------------------------------------
// Aplicação de progresso (Firestore/admin)
// ---------------------------------------------------------------------------

/**
 * Aplica progresso em lote para TODOS os itens do catálogo com o metric.
 * Retorna quantos itens foram atualizados (progresso mudou).
 */
interface ItemState {
  progress: number;
  claimed: boolean;
  periodKey: string;
}

async function applyProgress(
  db: Firestore,
  targets: { id: string; target: number; periodKey: string }[],
  basePath: (id: string) => string,
  mode: ProgressMode,
  value: number,
): Promise<number> {
  if (targets.length === 0 || value <= 0) return 0;
  const states = await db.getAll(
    ...targets.map((t) => db.doc(basePath(t.id))),
  );
  const batch: WriteBatch = db.batch();
  let updated = 0;
  states.forEach((snap, i) => {
    const target = targets[i]!;
    const current: ItemState = snap.exists
      ? {
          progress: Number(snap.get('progress') ?? 0),
          claimed: snap.get('claimed') === true,
          periodKey: String(snap.get('periodKey') ?? ''),
        }
      : { progress: 0, claimed: false, periodKey: '' };
    const next = computeProgress({
      currentProgress: current.progress,
      currentPeriodKey: current.periodKey,
      expectedPeriodKey: target.periodKey,
      mode,
      value,
    });
    if (next === current.progress && current.periodKey === target.periodKey) return;
    batch.set(
      db.doc(basePath(target.id)),
      {
        progress: next,
        claimed: current.claimed,
        periodKey: target.periodKey,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    updated += 1;
  });
  if (updated > 0) await batch.commit();
  return updated;
}

/**
 * Progresso de MISSÕES para um evento (metric, mode, value) no período atual.
 * Ex.: bumpMissionProgress(db, uid, 'plays', 'add', 1, nowMs).
 */
export async function bumpMissionProgress(
  db: Firestore,
  uid: string,
  metric: string,
  mode: ProgressMode,
  value: number,
  nowMs: number,
): Promise<number> {
  const catalog = await loadMissionCatalog(db);
  const targets = catalog
    .filter((m) => m.enabled && m.metric === metric)
    .map((m) => ({
      id: m.id,
      target: m.target,
      // Temporada usa o periodKey FIXO do catálogo; daily/weekly derivam do
      // momento do evento (UTC).
      periodKey: m.kind === 'season' ? m.periodKey : periodKeyFor(m.kind, nowMs),
    }));
  return applyProgress(
    db,
    targets,
    (id) => `userMissions/${uid}/items/${id}`,
    mode,
    value,
  );
}

/**
 * Progresso de CONQUISTAS (sem período — periodKey fixo '' nunca reinicia).
 */
export async function bumpAchievementProgress(
  db: Firestore,
  uid: string,
  metric: string,
  mode: ProgressMode,
  value: number,
): Promise<number> {
  const catalog = await loadAchievementCatalog(db);
  const targets = catalog
    .filter((a) => a.enabled && a.metric === metric)
    .map((a) => ({ id: a.id, target: a.target, periodKey: '' }));
  return applyProgress(
    db,
    targets,
    (id) => `userAchievements/${uid}/items/${id}`,
    mode,
    value,
  );
}

/**
 * Sweep de PODER (conquistas a_power_100/a_power_1k): chamado no closeBlocks
 * com as entradas de poder já carregadas — grava max(power H/s) por usuário.
 */
export async function sweepPowerAchievements(
  db: Firestore,
  entries: { uid: string; powerUnits: bigint }[],
  powerBasePerHs: number,
): Promise<number> {
  if (entries.length === 0 || powerBasePerHs <= 0) return 0;
  const catalog = await loadAchievementCatalog(db);
  const hasPowerMetric = catalog.some((a) => a.enabled && a.metric === 'power');
  if (!hasPowerMetric) return 0;
  let updated = 0;
  for (const e of entries) {
    const hs = Number(e.powerUnits / BigInt(powerBasePerHs));
    if (hs <= 0) continue;
    updated += await bumpAchievementProgress(db, e.uid, 'power', 'max', hs);
  }
  return updated;
}
