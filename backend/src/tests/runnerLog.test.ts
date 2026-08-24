/**
 * Testes das correções do runner (doc backend.md):
 * - serializeForLog NUNCA lança com BigInt (causa raiz do falso FAILED
 *   no caminho scheduled) e preserva valores como string.
 * - INDEX_SPECS cobre exatamente as queries compostas dos processadores
 *   (status + orderBy), evitando regressão de índice ausente.
 */
import { serializeForLog } from '../runner';
import { INDEX_SPECS } from '../ensureIndexes';

describe('serializeForLog (runner)', () => {
  it('serializa bigint sem lançar TypeError', () => {
    expect(() =>
      JSON.stringify({ a: 1n }),
    ).toThrow(); // comportamento nativo que quebrava o log

    const out = serializeForLog({ currentPeriod: 5, residueUnits: 42n });
    expect(() => JSON.parse(out)).not.toThrow();
    expect(JSON.parse(out)).toEqual({ currentPeriod: 5, residueUnits: '42' });
  });

  it('serializa estruturas aninhadas com bigint (Map → objeto via entries)', () => {
    const summary = {
      scanned: 3,
      rewards: Object.fromEntries([
        ['u1', 100n],
        ['u2', 250n],
      ]),
    };
    const parsed = JSON.parse(serializeForLog(summary));
    expect(parsed.rewards.u1).toBe('100');
    expect(parsed.rewards.u2).toBe('250');
    expect(parsed.scanned).toBe(3);
  });

  it('preserva tipos não-bigint', () => {
    const parsed = JSON.parse(
      serializeForLog({ s: 'x', n: 1.5, b: false, nil: null }),
    );
    expect(parsed).toEqual({ s: 'x', n: 1.5, b: false, nil: null });
  });
});

describe('INDEX_SPECS (garantia de índices compostos)', () => {
  it('cobre gameSessions: status+processed+finishedAt ASC', () => {
    const spec = INDEX_SPECS.find((s) => s.collectionGroup === 'gameSessions');
    expect(spec).toBeDefined();
    expect(spec!.fields.map((f) => f.fieldPath)).toEqual([
      'status',
      'processed',
      'finishedAt',
    ]);
    expect(spec!.fields.every((f) => f.order === 'ASCENDING')).toBe(true);
  });

  it('cobre purchaseIntents: status+createdAt ASC', () => {
    const spec = INDEX_SPECS.find(
      (s) => s.collectionGroup === 'purchaseIntents',
    );
    expect(spec).toBeDefined();
    expect(spec!.fields.map((f) => f.fieldPath)).toEqual([
      'status',
      'createdAt',
    ]);
  });

  it('espelha firestore.indexes.json declarado no repo', async () => {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const fs = await import('fs');
      const path = await import('path');
      const raw = fs.readFileSync(
        path.resolve(__dirname, '../../../firestore.indexes.json'),
        'utf8',
      );
      const declared = JSON.parse(raw) as {
        indexes: Array<{
          collectionGroup: string;
          fields: Array<{ fieldPath: string; order: string }>;
        }>;
      };
      for (const spec of INDEX_SPECS) {
        const match = declared.indexes.find(
          (i) => i.collectionGroup === spec.collectionGroup,
        );
        expect(match).toBeDefined();
        expect(match!.fields.map((f) => `${f.fieldPath}:${f.order}`)).toEqual(
          spec.fields.map((f) => `${f.fieldPath}:${f.order}`),
        );
      }
  });
});
