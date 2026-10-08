// A aba Configurações › Integrações › Dropbox. O que se protege: sem as chaves no servidor a tela
// diz o que falta; desconectado mostra "Conectar" e leva à URL do Dropbox; conectado mostra a conta
// e a pasta dos barcos; desconectar pede confirmação; a volta do dropbox.com (?dropbox=ok) avisa.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const db = vi.hoisted(() => ({
  status: null as unknown,
  chamadas: [] as Array<Record<string, unknown>>,
  avisos: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: {
      invoke: async (_nome: string, { body }: { body: Record<string, unknown> }) => {
        db.chamadas.push(body);
        if (body.acao === 'status') return { data: db.status, error: null };
        if (body.acao === 'iniciar') return { data: { url: 'https://www.dropbox.com/oauth2/authorize?x=1' }, error: null };
        if (body.acao === 'desconectar') return { data: { ok: true }, error: null };
        return { data: null, error: null };
      },
    },
  },
}));
vi.mock('sonner', () => ({ toast: { success: (t: string) => db.avisos.push(t), error: (t: string) => db.avisos.push(t) } }));

import { DropboxIntegracaoTab } from './DropboxIntegracaoTab';

function montar(rota = '/v2/settings?tab=integracoes') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MemoryRouter initialEntries={[rota]}>
      <QueryClientProvider client={qc}><DropboxIntegracaoTab /></QueryClientProvider>
    </MemoryRouter>,
  );
}

const BASE = { pastaBase: '/HBR-Testes/B2C', linkPastaBase: 'https://www.dropbox.com/home/HBR-Testes/B2C', redirectUri: 'https://x/functions/v1/dropbox-conectar' };

beforeEach(() => {
  db.chamadas = [];
  db.avisos = [];
});

describe('DropboxIntegracaoTab', () => {
  it('sem as chaves no servidor, diz o que falta e não mostra Conectar', async () => {
    db.status = { ...BASE, configurado: false, conectado: false, conta: null };
    montar();
    expect(await screen.findByText(/As chaves do app do Dropbox ainda não estão no servidor/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Conectar ao Dropbox/ })).toBeNull();
  });

  it('desconectado: Conectar pede a URL de autorização', async () => {
    db.status = { ...BASE, configurado: true, conectado: false, conta: null };
    const original = window.location;
    // jsdom não navega: troca o location por um objeto gravável só neste teste.
    Object.defineProperty(window, 'location', { configurable: true, value: { ...original, href: '' } });
    montar();
    await userEvent.click(await screen.findByRole('button', { name: /Conectar ao Dropbox/ }));
    expect(db.chamadas.some((c) => c.acao === 'iniciar')).toBe(true);
    expect(window.location.href).toBe('https://www.dropbox.com/oauth2/authorize?x=1');
    Object.defineProperty(window, 'location', { configurable: true, value: original });
  });

  it('conectado: mostra a conta e a pasta, e desconectar pede confirmação', async () => {
    db.status = {
      ...BASE,
      configurado: true,
      conectado: true,
      conta: { conta_id: 'dbid:1', email: 'hbr.boats@gmail.com', nome: 'HBR Marine', conectado_em: '2026-10-08T12:00:00Z', ultimo_uso_em: null, ultimo_erro: null, ultimo_erro_em: null },
    };
    montar();
    expect(await screen.findByText('HBR Marine')).toBeInTheDocument();
    expect(screen.getByText('/HBR-Testes/B2C')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Desconectar/ }));
    expect(db.chamadas.some((c) => c.acao === 'desconectar')).toBe(false);
    await userEvent.click(screen.getByRole('button', { name: /Sim, desconectar/ }));
    expect(db.chamadas.some((c) => c.acao === 'desconectar')).toBe(true);
  });

  it('a volta do Dropbox com ?dropbox=ok avisa que conectou', async () => {
    db.status = { ...BASE, configurado: true, conectado: false, conta: null };
    montar('/v2/settings?tab=integracoes&dropbox=ok');
    await screen.findByRole('button', { name: /Conectar ao Dropbox/ });
    expect(db.avisos).toContain('Dropbox conectado!');
  });
});
