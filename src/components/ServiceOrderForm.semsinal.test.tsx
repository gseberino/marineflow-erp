// Aviso do sinal na tela do orçamento (28/10/2026): a tarefa "aprovado sem sinal — receber o sinal e
// converter" abre o orçamento, e no aprovado a tela não oferecia nem o sinal nem a conversão sem sinal
// (o aviso só existia no "aguardando sinal"). O banco é de mentira; a tela é a de verdade.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

vi.mock('@/hooks/use-auth', () => {
  const auth = () => ({ user: { id: 'u1', role: 'admin' }, loading: false });
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

const ORC = {
  id: 'orc1', service_order_number: 'ORÇ-00083', status: 'draft', quote_status: 'approved', priority: 'normal',
  service_type: 'repair', client_id: 'c1', vessel_id: 'v1', problem_description: 'Adicional: bomba de porão',
  converted_to_os_at: null, merged_into_id: null, signed_at: null,
  service_order_services: [], service_order_parts: [], service_order_technicians: [], updated_at: '2026-10-27T12:00:00Z',
};

function renderiza(dados: Record<string, unknown>) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <ServiceOrderForm orderId="orc1" orderData={dados as never} isLoading={false} />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('ServiceOrderForm — aviso do sinal', () => {
  it('orçamento aprovado: aviso próprio com "Registrar sinal" e "Converter sem sinal"', () => {
    renderiza(ORC);
    expect(screen.getByText('Orçamento aprovado — falta o sinal')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Registrar sinal/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Converter sem sinal/ })).toBeInTheDocument();
  });

  it('aguardando sinal: o aviso de sempre, com os dois botões', () => {
    renderiza({ ...ORC, quote_status: 'awaiting_deposit' });
    expect(screen.getByText('Aguardando pagamento do sinal')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Converter sem sinal/ })).toBeInTheDocument();
  });

  it('enviado (cliente ainda não aprovou) e OS já convertida: sem aviso', () => {
    const { unmount } = renderiza({ ...ORC, quote_status: 'sent' });
    expect(screen.queryByRole('button', { name: /Converter sem sinal/ })).not.toBeInTheDocument();
    unmount();
    renderiza({ ...ORC, service_order_number: 'OS-00083', status: 'approved', converted_to_os_at: '2026-10-28T10:00:00Z' });
    expect(screen.queryByText(/falta o sinal|Aguardando pagamento do sinal/)).not.toBeInTheDocument();
  });
});
