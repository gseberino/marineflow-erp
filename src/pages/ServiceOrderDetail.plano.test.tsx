// Smoke da tela da OS com o cartão "Plano" (Agenda de Produção, Fase 3, P7a): acima das abas, para o administrador, numa
// OS que já não é orçamento e com a agenda de produção ligada — e a tela de antes para o técnico e com a agenda desligada.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { PLANO_DE_EXEMPLO } from '@/components/agenda/producao/dados-de-exemplo';

const h = vi.hoisted(() => ({
  papel: 'admin',
  config: { data: null as unknown, error: null as unknown },
  rpc: vi.fn(),
}));

vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: {} }),
  useAppSetting: (_key: string, fallback = '') => fallback,
}));
vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrder: () => ({
    data: { id: 'os-69', status: 'scheduled', service_order_number: 'OS-00069', service_order_services: [] },
    isLoading: false, error: null,
  }),
}));
vi.mock('@/hooks/use-audit-log', () => ({ useRecordHistory: () => ({ data: [] }) }));
vi.mock('@/hooks/use-auth', () => ({ useOptionalAuth: () => ({ user: { id: 'u1', role: h.papel } }) }));
vi.mock('@/integrations/supabase/client', () => {
  const builder: Record<string, unknown> = {};
  builder.select = () => builder;
  builder.maybeSingle = async () => h.config;
  return { supabase: { rpc: (...a: unknown[]) => h.rpc(...a), from: () => builder } };
});
vi.mock('@/components/ServiceOrderForm', () => ({ ServiceOrderForm: () => <div>formulário</div> }));
vi.mock('@/components/ServiceOrderTimeline', () => ({ ServiceOrderTimeline: () => null }));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({ EntityTasksPanel: () => null }));
vi.mock('@/components/service-orders/ServiceRoutePanel', () => ({ ServiceRoutePanel: () => null }));
vi.mock('@/components/service-orders/SurveyPanel', () => ({ SurveyPanel: () => null }));

import ServiceOrderDetail from './ServiceOrderDetail';

function renderOs() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/service-orders/os-69']}>
          <Routes><Route path="/service-orders/:id" element={<ServiceOrderDetail />} /></Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  h.papel = 'admin';
  h.config = { data: { jornada_horas: 8, carga_max: '0.80', modo_leitura: 'sombra', modo_proposta: 'ligado' }, error: null };
  h.rpc.mockReset();
  h.rpc.mockResolvedValue({ data: { ...PLANO_DE_EXEMPLO, status: 'scheduled', pode_entregar: false }, error: null });
});

describe('OS — o cartão Plano', () => {
  it('administrador, OS agendada, agenda ligada: o cartão acima das abas, e as abas de sempre', async () => {
    renderOs();
    expect(await screen.findByTestId('plano-da-os')).toBeInTheDocument();
    expect(h.rpc).toHaveBeenCalledWith('os_plano_da_os', { p_os: 'os-69' });
    expect(screen.getByRole('tab', { name: /Detalhes da OS/ })).toBeInTheDocument();
    expect(screen.getByText('formulário')).toBeInTheDocument();
    // o cartão vem antes das abas na página
    const cartao = screen.getByTestId('plano-da-os');
    const abas = screen.getByRole('tablist');
    expect(cartao.compareDocumentPosition(abas) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('o técnico e a agenda desligada: a tela de antes, sem o cartão nem a leitura', async () => {
    h.papel = 'technician';
    const a = renderOs();
    expect(screen.getByText('formulário')).toBeInTheDocument();
    expect(screen.queryByTestId('plano-da-os')).not.toBeInTheDocument();
    a.unmount();
    h.papel = 'admin';
    h.config = { data: null, error: { code: 'PGRST205', message: 'Could not find the table' } };
    renderOs();
    await new Promise((r) => setTimeout(r, 20));
    expect(screen.queryByTestId('plano-da-os')).not.toBeInTheDocument();
    expect(h.rpc).not.toHaveBeenCalled();
  });
});
