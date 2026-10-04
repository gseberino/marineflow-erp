// A aba "Assistente de IA" de Configurações. O que se protege: cada canal grava a SUA chave
// (virar o WhatsApp não liga o app, e vice-versa); o modelo só se escolhe com o Max ligado; a
// reserva grava on/off; o status do PC aparece (disponível ou o motivo de não estar); quem não é
// admin não vê os controles.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const db = vi.hoisted(() => ({
  settings: {} as Record<string, string>,
  gravados: [] as Array<{ key: string; value: string }>,
  status: null as unknown,
  cargo: 'admin',
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: async () => ({ data: Object.entries(db.settings).map(([key, value]) => ({ key, value })), error: null }),
      upsert: async (linha: { key: string; value: string }) => {
        db.gravados.push(linha);
        db.settings[linha.key] = linha.value;
        return { error: null };
      },
    }),
    rpc: async (nome: string) => (nome === 'ai_gateway_status' ? { data: db.status, error: null } : { data: null, error: null }),
  },
}));
vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: db.cargo } }) }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {} } }));

import { AssistenteIATab, nivelAtual, provedorAtual } from './AssistenteIATab';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={qc}><AssistenteIATab /></QueryClientProvider>);
}

const NO_AR = {
  disponivel: true,
  agora: '2026-10-03T22:00:30Z',
  workers: [{ id: 'pc-hbr', enabled: true, last_seen_at: '2026-10-03T22:00:20Z', version: '0.1.0', providers: { 'claude-local': { available: true } }, ativos: 0, maximo: 2 }],
  ultimos: [{ tipo: 'agente_whatsapp', status: 'completed', model_used: 'claude-sonnet-x', duration_ms: 20100, error_code: null, created_at: '2026-10-03T21:32:00Z' }],
};

beforeEach(() => {
  db.settings = { ai_provedor_whatsapp: 'claude_max', ai_whatsapp_max_modelo: 'sonnet', ai_provedor_painel: 'openrouter', ai_whatsapp_max_reserva: 'on' };
  db.gravados = [];
  db.status = NO_AR;
  db.cargo = 'admin';
});

describe('AssistenteIATab', () => {
  it('mostra o PC no ar e os últimos turnos', async () => {
    montar();
    expect(await screen.findByText('Claude Max disponível')).toBeInTheDocument();
    expect(screen.getByText(/PC pc-hbr · último sinal há 10 s · versão 0.1.0 · 0\/2 em andamento/)).toBeInTheDocument();
    expect(screen.getByText(/respondeu/)).toBeInTheDocument();
    expect(screen.getByText('20.1 s')).toBeInTheDocument();
  });

  it('PC fora do ar: diz o motivo e que a mensagem vai pelo OpenRouter', async () => {
    db.status = { ...NO_AR, disponivel: false, workers: [{ ...NO_AR.workers[0], providers: { 'claude-local': { available: false, reason: 'rate_limited' } } }] };
    montar();
    expect(await screen.findByText('Claude Max indisponível agora')).toBeInTheDocument();
    expect(screen.getByText(/Motivo: rate_limited/)).toBeInTheDocument();
  });

  it('cada canal grava a sua chave; o modelo do app só se escolhe com o Max ligado', async () => {
    const user = userEvent.setup();
    montar();
    const app = await screen.findByRole('group', { name: 'Quem responde — Chat do app' });
    const modeloDoApp = screen.getByRole('group', { name: 'Modelo do Claude Max — Chat do app' });
    expect(within(modeloDoApp).getByRole('button', { name: /Opus/ })).toBeDisabled();

    await user.click(within(app).getByRole('button', { name: 'Claude Max' }));
    expect(db.gravados).toEqual([{ key: 'ai_provedor_painel', value: 'claude_max' }]);

    const whatsapp = screen.getByRole('group', { name: 'Quem responde — WhatsApp' });
    expect(within(whatsapp).getByRole('button', { name: 'Claude Max' })).toHaveAttribute('aria-pressed', 'true');
    await user.click(within(screen.getByRole('group', { name: 'Modelo do Claude Max — WhatsApp' })).getByRole('button', { name: /Opus/ }));
    expect(db.gravados.at(-1)).toEqual({ key: 'ai_whatsapp_max_modelo', value: 'opus' });
  });

  it('a reserva grava off e on', async () => {
    const user = userEvent.setup();
    montar();
    const chave = await screen.findByRole('switch', { name: 'Reserva pelo OpenRouter' });
    expect(chave).toHaveAttribute('aria-checked', 'true');
    await user.click(chave);
    expect(db.gravados.at(-1)).toEqual({ key: 'ai_whatsapp_max_reserva', value: 'off' });
  });

  it('quem não é admin não vê os controles', async () => {
    db.cargo = 'financial';
    montar();
    expect(await screen.findByText(/Só o administrador/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Claude Max' })).toBeNull();
  });

  it('leitura das chaves: qualquer coisa fora do previsto vira o padrão', () => {
    expect(provedorAtual(' Claude_Max ')).toBe('claude_max');
    expect(provedorAtual('max')).toBe('openrouter');
    expect(provedorAtual(undefined)).toBe('openrouter');
    expect(nivelAtual('OPUS')).toBe('opus');
    expect(nivelAtual('gpt')).toBe('sonnet');
  });
});
