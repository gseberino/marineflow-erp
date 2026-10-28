// Tela da OS com agrupamento de OS (28/10/2026): a faixa certa (de OS, não a de orçamento), o "Agrupar com
// outras OS…" só na OS que ainda não começou, o "Desagrupar…" só na agrupada desfazível e o "Cancelar" fora
// dela (o banco recusaria). O agrupamento lido do banco é de mentira; a tela é a de verdade.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({
  cargo: 'admin' as string,
  agrupamento: { comoAgrupado: null, comoOrigem: null } as Record<string, unknown>,
  /** O que os_para_agrupar diz da agrupada (null = sem resposta: a tela usa o palpite pela situação). */
  desagrupavel: null as { podeDesagrupar: boolean; motivo: string | null } | null,
  pedidoDesagrupavel: null as { agrupadoId: string | null; vesselId: string | null | undefined; enabled: boolean } | null,
}));

vi.mock('@/hooks/use-auth', () => {
  const auth = () => ({ user: { id: 'u1', role: estado.cargo }, loading: false });
  return { useOptionalAuth: auth, useAuth: auth };
});
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: {} }),
  useAppSetting: (_key: string, fallback = '') => fallback,
}));
vi.mock('@/hooks/use-agrupar-orcamentos', async (original) => ({
  ...(await original<typeof import('@/hooks/use-agrupar-orcamentos')>()),
  useAgrupamentoDoOrcamento: () => ({ ...estado.agrupamento, isLoading: false, isError: false }),
}));
vi.mock('@/hooks/use-agrupar-os', async (original) => ({
  ...(await original<typeof import('@/hooks/use-agrupar-os')>()),
  useDesagrupavelDaOsAgrupada: (v: { agrupadoId: string | null; vesselId: string | null | undefined; enabled: boolean }) => {
    estado.pedidoDesagrupavel = v;
    return { data: estado.desagrupavel, isLoading: false, isError: false };
  },
}));
vi.mock('@/integrations/supabase/client', () => {
  const vazio = { data: [], error: null, count: 0 };
  const cadeia: unknown = new Proxy(function () {}, {
    get(_alvo, prop) {
      if (prop === 'then') return (ok: (v: unknown) => unknown, falha: (e: unknown) => unknown) => Promise.resolve(vazio).then(ok, falha);
      if (prop === 'single' || prop === 'maybeSingle') return () => Promise.resolve({ data: null, error: null });
      return cadeia;
    },
    apply() { return cadeia; },
  });
  return { supabase: cadeia };
});

import { ServiceOrderForm } from './ServiceOrderForm';

if (!('IntersectionObserver' in globalThis)) {
  (globalThis as Record<string, unknown>).IntersectionObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords() { return []; }
  };
}

const OS = {
  id: 'os1', service_order_number: 'OS-00140', status: 'approved', quote_status: 'approved', priority: 'normal',
  service_type: 'repair', client_id: 'c1', vessel_id: 'v1', problem_description: 'Starlink + inversor',
  converted_to_os_at: '2026-10-27T12:00:00Z', merged_into_id: null, signed_at: null,
  service_order_services: [], service_order_parts: [], service_order_technicians: [], updated_at: '2026-10-27T12:00:00Z',
};

function renderiza(dados: Record<string, unknown>) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <ServiceOrderForm orderId="os1" orderData={dados as never} isLoading={false} />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

async function abrirAcoes() {
  await userEvent.click(screen.getAllByRole('button', { name: /Ações/ })[0]!);
}

beforeEach(() => {
  estado.cargo = 'admin';
  estado.agrupamento = { comoAgrupado: null, comoOrigem: null };
  estado.desagrupavel = null;
  estado.pedidoDesagrupavel = null;
});

describe('ServiceOrderForm — agrupar OS', () => {
  it('OS que ainda não começou: o menu oferece "Agrupar com outras OS…" (não o de orçamentos)', async () => {
    renderiza(OS);
    await abrirAcoes();
    expect(await screen.findByRole('menuitem', { name: /Agrupar com outras OS…/ })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Agrupar com outros orçamentos…/ })).not.toBeInTheDocument();
    // OS comum (não agrupada) cancela normalmente — contraprova do caso da agrupada abaixo
    expect(screen.getByRole('menuitem', { name: /Cancelar OS/ })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Desagrupar…/ })).not.toBeInTheDocument();
  });

  it('OS em execução: não oferece agrupar', async () => {
    renderiza({ ...OS, status: 'in_progress' });
    await abrirAcoes();
    expect(await screen.findByRole('menuitem', { name: /Duplicar/ })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Agrupar com outras OS…/ })).not.toBeInTheDocument();
  });

  it('agrupada desfazível: faixa de OS com a assinatura das originais, Desagrupar no menu e sem Cancelar', async () => {
    estado.agrupamento = {
      comoAgrupado: {
        agrupamentoId: 'g1', tipo: 'os',
        origens: [{ id: 'a', numero: 'OS-00032', assinada: false }, { id: 'b', numero: 'OS-00033', assinada: true }],
      },
      comoOrigem: null,
    };
    renderiza(OS);
    expect(screen.getByText('Esta OS reúne OS-00032, OS-00033.')).toBeInTheDocument();
    expect(screen.getByText(/A assinatura do cliente ficou na OS-00033/)).toBeInTheDocument();
    expect(screen.getByText(/Para cancelá-la, desagrupe primeiro/)).toBeInTheDocument();
    expect(screen.queryByText(/Este orçamento reúne/)).not.toBeInTheDocument();
    await abrirAcoes();
    expect(await screen.findByRole('menuitem', { name: /Desagrupar…/ })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Cancelar OS/ })).not.toBeInTheDocument();
  });

  it('agrupada que já começou: faixa sem Desagrupar', async () => {
    estado.agrupamento = {
      comoAgrupado: { agrupamentoId: 'g1', tipo: 'os', origens: [{ id: 'a', numero: 'OS-00100', assinada: false }, { id: 'b', numero: 'OS-00128', assinada: false }] },
      comoOrigem: null,
    };
    renderiza({ ...OS, status: 'in_progress' });
    expect(screen.getByText('Esta OS reúne OS-00100, OS-00128.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Desagrupar' })).not.toBeInTheDocument();
  });

  it('origem: faixa "Esta OS foi agrupada em…" no lugar da de bloqueio', () => {
    estado.agrupamento = {
      comoAgrupado: null,
      comoOrigem: { agrupadoId: 'nova', agrupadoNumero: 'OS-00140', agrupadoEmAberto: true, tipo: 'os' },
    };
    renderiza({ ...OS, id: 'os1', service_order_number: 'OS-00100', status: 'cancelled', merged_into_id: 'nova' });
    expect(screen.getByText('Esta OS foi agrupada em OS-00140.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Abrir OS-00140' })).toHaveAttribute('href', '/v2/service-orders/nova');
    expect(screen.queryByText(/Este orçamento foi agrupado/)).not.toBeInTheDocument();
  });

  // A régua é a do banco (os_para_agrupar → agrupados_ativos), não a situação: uma agrupada ainda 'open' com
  // hora apontada não desagrupa — e aí o banco ACEITA cancelar, então o Cancelar tem de voltar.
  it('agrupada "open" que o banco diz não desagrupável: Cancelar de volta, sem Desagrupar, faixa com a frase do banco', async () => {
    estado.agrupamento = {
      comoAgrupado: { agrupamentoId: 'g1', tipo: 'os', origens: [{ id: 'a', numero: 'OS-00100', assinada: false }, { id: 'b', numero: 'OS-00128', assinada: false }] },
      comoOrigem: null,
    };
    estado.desagrupavel = {
      podeDesagrupar: false,
      motivo: 'OS-00140 já começou a ser executada (hora apontada): não dá mais para desagrupar. As originais ficam como histórico.',
    };
    renderiza({ ...OS, status: 'open' });
    expect(estado.pedidoDesagrupavel).toEqual({ agrupadoId: 'os1', vesselId: 'v1', enabled: true });
    expect(screen.getByText(/OS-00140 já começou a ser executada \(hora apontada\)/)).toBeInTheDocument();
    expect(screen.queryByText(/Para cancelá-la, desagrupe primeiro/)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Desagrupar' })).not.toBeInTheDocument();
    await abrirAcoes();
    expect(await screen.findByRole('menuitem', { name: /Cancelar OS/ })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: /Desagrupar…/ })).not.toBeInTheDocument();
  });

  it('origem cuja agrupada o banco diz não desagrupável: a faixa traz a frase do banco (pergunta pela agrupada)', () => {
    estado.agrupamento = {
      comoAgrupado: null,
      comoOrigem: { agrupadoId: 'nova', agrupadoNumero: 'OS-00140', agrupadoEmAberto: true, tipo: 'os' },
    };
    estado.desagrupavel = {
      podeDesagrupar: false,
      motivo: 'OS-00140 ganhou conta a receber depois de agrupar. Cancele ou mova isso para uma das originais antes de desagrupar.',
    };
    renderiza({ ...OS, id: 'os1', service_order_number: 'OS-00100', status: 'cancelled', merged_into_id: 'nova' });
    expect(estado.pedidoDesagrupavel).toEqual({ agrupadoId: 'nova', vesselId: 'v1', enabled: true });
    expect(screen.getByText(/OS-00140 ganhou conta a receber depois de agrupar/)).toBeInTheDocument();
    expect(screen.queryByText(/Para mexer nesta, desagrupe/)).not.toBeInTheDocument();
  });
});
