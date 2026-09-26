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
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import PublicServiceOrderView from './PublicServiceOrderView';
import { buildHTMLDocument, type PDFData, type PDFOptions } from '@/lib/pdf-generator';

// O que o botão Baixar entrega ao gerador. O download de verdade (servidor/html2pdf) não
// roda aqui; o desenho roda, com as MESMAS opções, em buildHTMLDocument.
const baixados = vi.hoisted(() => [] as Array<{ dados: PDFData; opcoes: PDFOptions }>);
vi.mock('@/lib/pdf-generator', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/lib/pdf-generator')>();
  return {
    ...real,
    downloadPDF: async (dados: PDFData, opcoes: PDFOptions) => { baixados.push({ dados, opcoes }); },
  };
});

const ORDEM: Record<string, unknown> = {
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
  // 7, e não 15: o literal do gerador é 15, então só um número diferente prova que a
  // validade do orçamento chegou ao PDF.
  quote_validity_days: 7,
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
  beforeEach(() => {
    vi.clearAllMocks();
    baixados.length = 0;
  });

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

  // Até 26/09/2026 o PDF do portal saía "Válido por 15 dias" para qualquer orçamento: as
  // opções não levavam validade e o gerador caía no literal.
  it('o PDF baixado leva a validade do PRÓPRIO orçamento', async () => {
    abrir();
    fireEvent.click(await screen.findByRole('button', { name: /Baixar PDF/i }));
    await waitFor(() => expect(baixados).toHaveLength(1));
    const { dados, opcoes } = baixados[0];
    expect(opcoes.validity).toEqual({ mode: 'days', days: 7 });
    expect(dados.documentType).toBe('quote');
    // criado em 01/08/2026 (09h de Brasília) + 7 dias
    expect(buildHTMLDocument(dados, opcoes)).toContain('Válido por 7 dias (até 08/08/2026)');
  });

  // O anônimo não enxerga app_settings.quote_validity_days (whitelist), então sem a do
  // orçamento o padrão é 15 — e nunca "NaN dias".
  it('sem validade no orçamento, o PDF cai em 15 dias', async () => {
    const original = ORDEM.quote_validity_days;
    ORDEM.quote_validity_days = null;
    try {
      abrir();
      fireEvent.click(await screen.findByRole('button', { name: /Baixar PDF/i }));
      await waitFor(() => expect(baixados).toHaveLength(1));
      expect(baixados[0].opcoes.validity).toEqual({ mode: 'days', days: 15 });
      expect(buildHTMLDocument(baixados[0].dados, baixados[0].opcoes)).toContain('Válido por 15 dias');
    } finally {
      ORDEM.quote_validity_days = original;
    }
  });
});
