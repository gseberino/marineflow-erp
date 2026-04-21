// Hash determinístico do conteúdo essencial da OS, para detectar
// alterações depois que o cliente assinou.

export interface HashableServiceOrder {
  service_order_number: string;
  status: string;
  problem_description?: string | null;
  diagnosis?: string | null;
  solution_applied?: string | null;
  customer_visible_report?: string | null;
  payment_conditions?: string | null;
  extra_notes?: string | null;
  grand_total?: number | null;
  labor_cost_total?: number | null;
  parts_cost_total?: number | null;
  travel_cost_total?: number | null;
  discount_amount?: number | null;
  tax_amount?: number | null;
  operational_cost_total?: number | null;
  quote_validity_date?: string | null;
}

export interface HashableLine {
  name: string;
  qty: number;
  unit_price: number;
  line_total: number;
}

function normalizeNumber(n: any): number {
  const v = Number(n || 0);
  return Math.round(v * 100) / 100;
}

export async function computeDocumentHash(
  order: HashableServiceOrder,
  services: HashableLine[],
  parts: HashableLine[],
  termsText?: string,
): Promise<string> {
  const payload = {
    n: order.service_order_number,
    s: order.status,
    pd: order.problem_description || '',
    dg: order.diagnosis || '',
    sa: order.solution_applied || '',
    cvr: order.customer_visible_report || '',
    pc: order.payment_conditions || '',
    en: order.extra_notes || '',
    qvd: order.quote_validity_date || '',
    tot: normalizeNumber(order.grand_total),
    lab: normalizeNumber(order.labor_cost_total),
    par: normalizeNumber(order.parts_cost_total),
    tra: normalizeNumber(order.travel_cost_total),
    disc: normalizeNumber(order.discount_amount),
    tax: normalizeNumber(order.tax_amount),
    op: normalizeNumber(order.operational_cost_total),
    svc: services
      .map((s) => ({
        n: s.name,
        q: normalizeNumber(s.qty),
        u: normalizeNumber(s.unit_price),
        t: normalizeNumber(s.line_total),
      }))
      .sort((a, b) => a.n.localeCompare(b.n)),
    prt: parts
      .map((p) => ({
        n: p.name,
        q: normalizeNumber(p.qty),
        u: normalizeNumber(p.unit_price),
        t: normalizeNumber(p.line_total),
      }))
      .sort((a, b) => a.n.localeCompare(b.n)),
    trm: (termsText || '').trim(),
  };
  const json = JSON.stringify(payload);
  const enc = new TextEncoder().encode(json);
  const buf = await crypto.subtle.digest('SHA-256', enc);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}
