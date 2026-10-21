// A OS relê do banco depois de cada gravação (o salvamento automático invalida a consulta), e o
// efeito de orderData reescrevia o formulário INTEIRO: o que a pessoa digitou enquanto a gravação
// ia e voltava sumia. Estes casos simulam a releitura com um rerender de orderData.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

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
  id: 'os1', service_order_number: 'ORÇ-00100', status: 'draft', priority: 'normal', service_type: 'repair',
  client_id: 'c1', vessel_id: 'v1', problem_description: 'Bomba de porão não liga',
  technician_instructions: '', site_access: '', service_order_services: [], service_order_parts: [],
  service_order_technicians: [], updated_at: '2026-10-20T10:00:00Z',
};

function tela(orderData: typeof os) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <ServiceOrderForm orderId="os1" orderData={orderData as never} isLoading={false} />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>
  );
}

const descricao = () => screen.getByDisplayValue(/Bomba de porão/) as HTMLTextAreaElement;

describe('ServiceOrderForm — releitura da OS não apaga o que está sendo digitado', () => {
  it('texto digitado durante a gravação sobrevive à releitura', async () => {
    const { rerender } = render(tela(os));
    await screen.findByDisplayValue('Bomba de porão não liga');

    // A pessoa continua digitando...
    fireEvent.change(descricao(), { target: { value: 'Bomba de porão não liga, fusível queimado' } });
    // ...e chega a releitura de uma gravação anterior (o banco ainda tem o texto antigo).
    rerender(tela({ ...os, updated_at: '2026-10-20T10:00:02Z' }));

    expect(descricao().value).toBe('Bomba de porão não liga, fusível queimado');
  });

  it('campo que a pessoa não mexeu recebe a mudança do banco (outra pessoa, assistente)', async () => {
    const { rerender } = render(tela(os));
    await screen.findByDisplayValue('Bomba de porão não liga');
    fireEvent.change(descricao(), { target: { value: 'Bomba de porão não liga, fusível queimado' } });

    rerender(tela({ ...os, technician_instructions: 'Levar multímetro', updated_at: '2026-10-20T10:00:03Z' }));

    expect(descricao().value).toBe('Bomba de porão não liga, fusível queimado');
    expect((screen.getByLabelText(/Instrução ao técnico/) as HTMLTextAreaElement).value).toBe('Levar multímetro');
  });

  it('outra OS na mesma tela: vale tudo do banco, nada da anterior', async () => {
    const { rerender } = render(tela(os));
    await screen.findByDisplayValue('Bomba de porão não liga');
    fireEvent.change(descricao(), { target: { value: 'Bomba de porão não liga, fusível queimado' } });

    rerender(tela({ ...os, id: 'os2', service_order_number: 'ORÇ-00101', problem_description: 'Gerador sem partida' }));

    expect(await screen.findByDisplayValue('Gerador sem partida')).toBeInTheDocument();
    expect(screen.queryByDisplayValue(/fusível queimado/)).not.toBeInTheDocument();
  });
});
