// Agenda de Produção, Fase 3 (P7a, d24): com a agenda automática ligada (modo_proposta = 'ligado'), a data da OS é da
// agenda — o salvar NÃO manda scheduled_* (o gatilho do banco recusaria a escrita direta, e o minuto do campo contra o
// segundo do banco fazia o salvamento automático regravar a data: NOVO-agenda-11). Desligada, manda como antes.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const h = vi.hoisted(() => ({ modo: 'ligado', gravar: vi.fn() }));

vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: {} }),
  useAppSetting: (_key: string, fallback = '') => fallback,
}));
vi.mock('@/hooks/use-agenda', async (original) => ({
  ...(await original<typeof import('@/hooks/use-agenda')>()),
  useModoDaProposta: () => ({ data: h.modo }),
}));
vi.mock('@/hooks/use-service-orders', async (original) => ({
  ...(await original<typeof import('@/hooks/use-service-orders')>()),
  useUpdateServiceOrder: () => ({ mutateAsync: h.gravar, mutate: vi.fn(), isPending: false }),
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

const os = {
  id: 'os1', service_order_number: 'OS-00100', status: 'scheduled', priority: 'normal', service_type: 'repair',
  client_id: 'c1', vessel_id: 'v1', problem_description: 'Bomba de porão não liga',
  scheduled_start_at: '2026-11-03T11:00:00+00:00', scheduled_end_at: '2026-11-05T20:00:00+00:00',
  technician_instructions: '', site_access: '', service_order_services: [], service_order_parts: [],
  service_order_technicians: [], updated_at: '2026-10-20T10:00:00Z',
};

function renderizar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <ServiceOrderForm orderId="os1" orderData={os as never} isLoading={false} />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

async function salvar() {
  await screen.findByDisplayValue('Bomba de porão não liga');
  fireEvent.change(screen.getByDisplayValue(/Bomba de porão/), { target: { value: 'Bomba de porão não liga, fusível' } });
  fireEvent.click(screen.getAllByRole('button', { name: /Salvar/ })[0]);
  await vi.waitFor(() => expect(h.gravar).toHaveBeenCalled());
  return h.gravar.mock.calls.at(-1)![0] as Record<string, unknown>;
}

beforeEach(() => h.gravar.mockReset().mockResolvedValue({}));

describe('ServiceOrderForm — as datas com a agenda automática ligada', () => {
  it('ligada: os campos ficam só de leitura e o salvar não manda scheduled_*', async () => {
    h.modo = 'ligado';
    renderizar();
    expect(await screen.findByLabelText(/Início previsto|Início|Data de início/)).toBeDisabled();
    const payload = await salvar();
    expect(payload.problem_description).toBe('Bomba de porão não liga, fusível');
    expect(payload).not.toHaveProperty('scheduled_start_at');
    expect(payload).not.toHaveProperty('scheduled_end_at');
  });

  it('desligada: as datas vão como antes', async () => {
    h.modo = 'desligado';
    renderizar();
    const payload = await salvar();
    expect(payload.scheduled_start_at).toBe('2026-11-03T11:00:00.000Z');
    expect(payload).toHaveProperty('scheduled_end_at');
  });
});
