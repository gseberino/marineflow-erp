// Técnico não troca o cliente de uma OS que já existe (decisão do dono, 21/10/2026): sem o
// "Trocar" e com o motivo. O escritório troca normalmente.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({ cargo: 'technician' as string | undefined }));

vi.mock('@/hooks/use-auth', () => {
  const auth = () => ({ user: { id: 'u1', role: estado.cargo }, loading: false });
  return { useOptionalAuth: auth, useAuth: auth };
});
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: {} }),
  useAppSetting: (_key: string, fallback = '') => fallback,
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
  id: 'os1', service_order_number: 'OS-00100', status: 'open', priority: 'normal', service_type: 'repair',
  client_id: 'c1', vessel_id: 'v1', problem_description: 'Inversor não liga', service_order_services: [],
  service_order_parts: [], service_order_technicians: [], updated_at: '2026-10-21T10:00:00Z',
};

function renderiza(dados: Record<string, unknown> = os) {
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

describe('ServiceOrderForm — quem troca o cliente da OS', () => {
  it('técnico: sem "Trocar", com o motivo', async () => {
    estado.cargo = 'technician';
    renderiza();
    expect(await screen.findByText('Só o escritório troca o cliente.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
  });

  it('escritório (admin): o "Trocar" aparece', async () => {
    estado.cargo = 'admin';
    renderiza();
    expect(await screen.findByRole('button', { name: /^Trocar cliente/ })).toBeInTheDocument();
    expect(screen.queryByText('Só o escritório troca o cliente.')).not.toBeInTheDocument();
  });

  it('OS concluída: nem o escritório troca o cliente (e por tabela a embarcação); diz a saída', async () => {
    estado.cargo = 'admin';
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <I18nProvider>
          <MemoryRouter>
            <ServiceOrderForm orderId="os1" orderData={{ ...os, status: 'completed' } as never} isLoading={false} />
          </MemoryRouter>
        </I18nProvider>
      </QueryClientProvider>,
    );
    expect(await screen.findByText('OS concluída: para trocar o cliente, volte a OS para Em andamento.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
  });
});

// Técnico também não troca a embarcação/veículo de uma OS que já tem uma (decisão do dono,
// 22/10/2026); a primeira unidade de uma OS sem unidade ele escolhe.
describe('ServiceOrderForm — quem troca a embarcação ou veículo da OS', () => {
  const MOTIVO = 'Só o escritório troca a embarcação ou veículo.';
  const TROCAR_UNIDADE = /^Trocar a embarcação ou veículo/;

  it('técnico, OS com unidade: sem "Trocar", com o motivo', async () => {
    estado.cargo = 'technician';
    renderiza();
    expect(await screen.findByText(MOTIVO)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: TROCAR_UNIDADE })).not.toBeInTheDocument();
  });

  it('escritório (admin): o "Trocar" da unidade aparece, sem o motivo', async () => {
    estado.cargo = 'admin';
    renderiza();
    expect(await screen.findByRole('button', { name: TROCAR_UNIDADE })).toBeInTheDocument();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
  });

  it('técnico, OS sem unidade: a lista para escolher a primeira aparece, sem o motivo', async () => {
    estado.cargo = 'technician';
    renderiza({ ...os, vessel_id: null });
    expect(await screen.findByRole('combobox', { name: /Embarcação ou veículo/ })).toBeInTheDocument();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
  });

  it('cargo ainda não carregado: sem "Trocar" e sem motivo (falha fechada)', async () => {
    estado.cargo = undefined;
    renderiza();
    expect(await screen.findByText('Embarcação ou veículo *')).toBeInTheDocument();
    // Dá tempo às consultas (agrupamento, levantamento) que também seguram o "Trocar".
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.queryByRole('button', { name: TROCAR_UNIDADE })).not.toBeInTheDocument();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
  });
});
