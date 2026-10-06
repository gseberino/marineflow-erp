// O link público da OS não pode pedir coluna interna, e a migration tem que fechar
// exatamente as colunas que o código considera internas (achado de 01/10/2026).
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  COLUNAS_INTERNAS, OS_PUBLICA, CLIENTE_PUBLICO, VEICULO_PUBLICO, MARINA_PUBLICA,
  LINHA_SERVICO_PUBLICA, PECA_PUBLICA, PRODUTO_PUBLICO, DESPESA_PUBLICA,
} from '../../supabase/functions/_shared/pdf/colunas-publicas';

const lista = (s: string) => s.split(',').map((c) => c.trim()).filter(Boolean);

const PUBLICAS: Record<string, string> = {
  service_orders: OS_PUBLICA,
  clients: CLIENTE_PUBLICO,
  vessels: VEICULO_PUBLICO,
  marinas: MARINA_PUBLICA,
  service_order_services: LINHA_SERVICO_PUBLICA,
  service_order_parts: PECA_PUBLICA,
  products: PRODUTO_PUBLICO,
  service_order_expenses: DESPESA_PUBLICA,
};

describe('portal do cliente — colunas públicas × internas', () => {
  it.each(Object.entries(PUBLICAS))('%s: nenhuma coluna pública é interna', (tabela, colunas) => {
    const internas = new Set(COLUNAS_INTERNAS[tabela] ?? []);
    expect(lista(colunas).filter((c) => internas.has(c))).toEqual([]);
  });

  it('custo, comissão e notas internas estão fechados', () => {
    expect(COLUNAS_INTERNAS.service_order_parts).toEqual(expect.arrayContaining(['unit_cost_snapshot', 'line_total_cost']));
    expect(COLUNAS_INTERNAS.service_orders).toEqual(expect.arrayContaining([
      'internal_notes', 'commission_rate', 'commission_amount', 'commissioned_person',
    ]));
    expect(COLUNAS_INTERNAS.products).toEqual(expect.arrayContaining(['cost_price', 'profit_margin']));
  });

  it('a assinatura do cliente continua com tudo que o hash usa', () => {
    // computeDocumentHash (src/lib/document-hash.ts) lê estes campos da ordem.
    const hash = [
      'service_order_number', 'status', 'problem_description', 'diagnosis', 'solution_applied',
      'customer_visible_report', 'payment_conditions', 'extra_notes', 'quote_validity_date',
      'grand_total', 'labor_cost_total', 'parts_cost_total', 'travel_cost_total',
      'discount_amount', 'tax_amount', 'operational_cost_total',
    ];
    expect(hash.filter((c) => !lista(OS_PUBLICA).includes(c))).toEqual([]);
  });

  it('a migration fecha exatamente as colunas internas do código', () => {
    const sql = readFileSync(
      resolve(__dirname, '../../supabase/migrations/20261001190104_portal_cliente_sem_colunas_internas.sql'),
      'utf8',
    );
    const json = sql.match(/internas jsonb := '([\s\S]*?)'::jsonb/)![1];
    expect(JSON.parse(json)).toEqual(COLUNAS_INTERNAS);
  });

  it('o portal não lê mais nada com select(\'*\')', () => {
    const portal = readFileSync(resolve(__dirname, '../pages/PublicServiceOrderView.tsx'), 'utf8');
    expect(portal).not.toMatch(/\.select\(\s*['"`]\*/);
    expect(portal).toContain('carregarPDFData(order.id, sb, { publico: true })');
  });
});
