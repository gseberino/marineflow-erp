import { describe, it, expect } from 'vitest';
import { computeDocumentHash, type HashableServiceOrder, type HashableLine } from './document-hash';

const baseOrder: HashableServiceOrder = {
  service_order_number: 'SO-TEST-001',
  status: 'draft',
  problem_description: 'problema',
  diagnosis: null,
  solution_applied: null,
  customer_visible_report: null,
  payment_conditions: null,
  extra_notes: null,
  grand_total: 1000,
  labor_cost_total: 700,
  parts_cost_total: 300,
  travel_cost_total: 0,
  discount_amount: 0,
  tax_amount: 0,
  operational_cost_total: 0,
  quote_validity_date: null,
};

const svcA: HashableLine = { name: 'Alpha', qty: 1, unit_price: 100, line_total: 100 };
const svcB: HashableLine = { name: 'Beta', qty: 2, unit_price: 50, line_total: 100 };
const partA: HashableLine = { name: 'Filtro óleo', qty: 1, unit_price: 60, line_total: 60 };
const partB: HashableLine = { name: 'Vela', qty: 4, unit_price: 30, line_total: 120 };

describe('computeDocumentHash', () => {
  it('produces a deterministic hex hash for valid input', async () => {
    const h = await computeDocumentHash(baseOrder, [svcA, svcB], [partA, partB], 'termos');
    expect(typeof h).toBe('string');
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  it('does not throw when a service name is undefined', async () => {
    const broken = { ...svcA, name: undefined as unknown as string };
    await expect(
      computeDocumentHash(baseOrder, [broken, svcB], [partA, partB]),
    ).resolves.toMatch(/^[0-9a-f]{64}$/);
  });

  it('does not throw when a part name is null', async () => {
    const broken = { ...partA, name: null as unknown as string };
    await expect(
      computeDocumentHash(baseOrder, [svcA], [broken, partB]),
    ).resolves.toMatch(/^[0-9a-f]{64}$/);
  });

  it('does not throw when the entire service entry is undefined-shaped', async () => {
    await expect(
      computeDocumentHash(
        baseOrder,
        [{} as HashableLine, svcB],
        [partA],
      ),
    ).resolves.toMatch(/^[0-9a-f]{64}$/);
  });

  it('is order-independent for services and parts', async () => {
    const h1 = await computeDocumentHash(baseOrder, [svcA, svcB], [partA, partB], 't');
    const h2 = await computeDocumentHash(baseOrder, [svcB, svcA], [partB, partA], 't');
    expect(h1).toEqual(h2);
  });

  it('changes when a service quantity changes', async () => {
    const h1 = await computeDocumentHash(baseOrder, [svcA, svcB], [], 't');
    const h2 = await computeDocumentHash(
      baseOrder,
      [svcA, { ...svcB, qty: 3 }],
      [],
      't',
    );
    expect(h1).not.toEqual(h2);
  });

  it('changes when a service name changes', async () => {
    const h1 = await computeDocumentHash(baseOrder, [svcA], [], 't');
    const h2 = await computeDocumentHash(baseOrder, [{ ...svcA, name: 'Alpha Plus' }], [], 't');
    expect(h1).not.toEqual(h2);
  });

  it('treats whitespace-only name as empty (normalized)', async () => {
    const h1 = await computeDocumentHash(
      baseOrder,
      [{ ...svcA, name: '   ' }],
      [],
    );
    const h2 = await computeDocumentHash(
      baseOrder,
      [{ ...svcA, name: '' }],
      [],
    );
    expect(h1).toEqual(h2);
  });
});
