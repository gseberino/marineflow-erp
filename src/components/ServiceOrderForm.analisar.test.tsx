// O "Analisar" da descrição grava um levantamento e manda abrir a aba Levantamento — que só existe
// com a chave roteiro_execucao_visivel ligada (escondida por padrão desde 05/10/2026). Com a chave
// desligada o botão some junto com a aba; ligada, volta.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({ settings: {} as Record<string, string> }));

vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: estado.settings }),
  useAppSetting: (key: string, fallback = '') => estado.settings[key] || fallback,
}));
// Qualquer leitura do banco devolve vazio: o teste é sobre o botão, não sobre os dados.
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

// O jsdom não tem IntersectionObserver (o formulário o usa para a barra de salvar fixa).
if (!('IntersectionObserver' in globalThis)) {
  (globalThis as Record<string, unknown>).IntersectionObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords() { return []; }
  };
}

function renderForm() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <ServiceOrderForm />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('ServiceOrderForm — "Analisar" a descrição', () => {
  it('sem a chave do roteiro, o botão não aparece (a aba Levantamento, para onde ele manda, está escondida)', async () => {
    estado.settings = {};
    renderForm();
    // a seção da descrição está na tela (o "Reescrever" ao lado continua)
    expect(await screen.findByRole('button', { name: 'Reescrever' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Analisar' })).not.toBeInTheDocument();
  });

  it('com a chave ligada, volta', async () => {
    estado.settings = { roteiro_execucao_visivel: 'true' };
    renderForm();
    expect(await screen.findByRole('button', { name: 'Reescrever' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Analisar' })).toBeInTheDocument();
  });
});
