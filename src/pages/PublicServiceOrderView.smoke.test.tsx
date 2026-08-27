// Smoke de render do PORTAL PÚBLICO — a única tela do sistema que um cliente
// abre sozinho, por um link de WhatsApp, sem ninguém do lado para socorrer.
//
// Existe porque o portal passou a montar o PDF pela função única do ERP
// (NOVO-lev-14) em vez de ter a sua própria cópia. `tsc` e build não pegam erro
// de render — ver a memória `feedback_validar_por_render`.
//
// Os mocks devolvem SEMPRE a mesma referência: objeto novo a cada chamada faz os
// `useEffect` da página entrarem em laço, e o teste trava em vez de falhar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import PublicServiceOrderView from './PublicServiceOrderView';

const ORDEM = {
  id: 'os-1',
  service_order_number: 'ORÇ-00074',
  status: 'draft',
  client_id: 'c-1',
  vessel_id: null,
  created_at: '2026-08-01T12:00:00Z',
  problem_description: 'Trocar banco de baterias',
  grand_total: 12000,
  labor_cost_total: 4000,
  parts_cost_total: 8000,
  travel_cost_total: 0,
  discount_amount: 0,
  tax_amount: 0,
  operational_cost_total: 0,
  quote_validity_days: 15,
  share_token: 'tok-1',
  signed_at: null,
  requires_resignature: false,
};

const AJUSTES = [
  { key: 'company_name', value: 'HBR Marine Solutions' },
  { key: 'public_view_show_service_prices', value: 'true' },
  { key: 'public_view_allow_signature', value: 'true' },
];

// Um construtor de consulta que responde a qualquer encadeamento e termina
// devolvendo o que a tabela pedida tem. Sem isto seria um mock por chamada.
function fazerCliente(porTabela: Record<string, any>) {
  const cliente = {
    from: (tabela: string) => {
      const dados = porTabela[tabela] ?? [];
      const q: any = {
        select: () => q,
        eq: () => q,
        is: () => q,
        not: () => q,
        in: () => q,
        order: () => q,
        limit: () => q,
        maybeSingle: async () => ({ data: Array.isArray(dados) ? dados[0] ?? null : dados, error: null }),
        single: async () => ({ data: Array.isArray(dados) ? dados[0] ?? null : dados, error: null }),
        then: (r: any) => Promise.resolve({ data: dados, error: null }).then(r),
      };
      return q;
    },
  };
  return cliente;
}

const TABELAS = {
  service_orders: [ORDEM],
  clients: [{ id: 'c-1', name: 'Cliente Teste', phone: '(47) 99999-0000' }],
  vessels: [],
  service_order_parts: [],
  service_order_services: [],
  app_settings: AJUSTES,
  service_order_signatures: [],
  payment_condition_presets: [],
};

const cliente = fazerCliente(TABELAS);
vi.mock('@/integrations/supabase/client', () => ({ supabase: fazerCliente({}) }));
vi.mock('@/integrations/supabase/share-client', () => ({ createShareClient: () => cliente }));

const abrir = () =>
  render(
    <MemoryRouter initialEntries={['/view/tok-1']}>
      <Routes>
        <Route path="/view/:token" element={<PublicServiceOrderView />} />
      </Routes>
    </MemoryRouter>,
  );

describe('PublicServiceOrderView — smoke de render', () => {
  beforeEach(() => vi.clearAllMocks());

  it('carrega o documento do link sem crashar', async () => {
    abrir();
    await waitFor(() => expect(screen.getByText(/ORÇ-00074/)).toBeTruthy());
    expect(screen.getByText(/Cliente Teste/)).toBeTruthy();
  });

  // O botão existe e diz o que faz. Chamava printPDF, que abre a janela de
  // impressão — no celular do cliente, é onde a pessoa desiste (NOVO-lev-15).
  it('oferece baixar o PDF', async () => {
    abrir();
    await waitFor(() => expect(screen.getByText(/Baixar PDF/i)).toBeTruthy());
  });
});
