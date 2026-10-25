// Smoke de render das telas de produção (Agenda de Produção, Fase 3, P7a): a Semana e a Carteira passam de "carregando"
// para o conteúdo (o hook roda de verdade: um mock que devolve dado pronto não pegaria hook depois de return), o erro
// aparece com a frase do banco (nunca "nada marcado"), a tela ainda não instalada não quebra, e o Desfazer só pede
// confirmação quando é perda real (a cobrança da conclusão, a diária).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { CARTEIRA_DE_EXEMPLO, SEMANA_DE_EXEMPLO } from './dados-de-exemplo';

const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  aviso: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: (...a: unknown[]) => h.rpc(...a), from: () => ({}) },
}));
vi.mock('sonner', () => ({ toast: h.aviso }));
vi.mock('@/components/FilterPresets', () => ({ FilterPresets: () => null }));

import { SemanaProducao } from './SemanaProducao';
import { CarteiraProducao } from './CarteiraProducao';

function adiado<T>() {
  let resolver!: (v: T) => void;
  const promessa = new Promise<T>((r) => { resolver = r; });
  return { promessa, resolver };
}

function montar(no: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{no}</QueryClientProvider>);
}

beforeEach(() => {
  h.rpc.mockReset();
  h.aviso.mockClear();
  h.aviso.success.mockClear();
  h.aviso.error.mockClear();
});

describe('Agenda › Semana de produção', () => {
  it('carregando → a semana: título, carga por pessoa com texto, blocos, reserva a confirmar, livre e decisões', async () => {
    const d = adiado<{ data: unknown; error: null }>();
    h.rpc.mockReturnValueOnce(d.promessa);
    montar(<SemanaProducao de="2026-11-02" onAbrirOs={() => {}} />);
    expect(screen.getByText('Carregando a semana…')).toBeInTheDocument();
    d.resolver({ data: SEMANA_DE_EXEMPLO, error: null });

    expect(await screen.findByText('Semana de 03 a 06/11 (seg 02 é Finados)')).toBeInTheDocument();
    expect(h.rpc).toHaveBeenCalledWith('agenda_tela_semana', { p_de: '2026-11-02' });
    expect(screen.getByText('comprometido 79% · livre 3 diárias')).toBeInTheDocument();
    // a carga nunca só pela cor: o texto e, no vermelho, a palavra
    expect(screen.getByText('Roberto 1/2')).toBeInTheDocument();
    expect(within(screen.getByTestId('carga-p3')).getByText('acima')).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'João 1/0, acima da carga' })).toBeInTheDocument();
    // o bloco: OS · cliente · bem · pessoas · dia n de N · cliente confirmou
    const bloco = screen.getByTestId('bloco-OS-00069');
    expect(within(bloco).getByText('OS-00069 · Vanderlei · Mar Azul')).toBeInTheDocument();
    expect(within(bloco).getByText('você abre, Roberto o dia todo')).toBeInTheDocument();
    expect(within(bloco).getByText('dia 1 de 3')).toBeInTheDocument();
    expect(within(bloco).getByText(/cliente confirmou/)).toBeInTheDocument();
    expect(within(screen.getByTestId('bloco-OS-00203')).getByText('Reserva, a confirmar')).toBeInTheDocument();
    // a última linha do dia, o feriado, as decisões com o como responder
    expect(screen.getByText('livre: Roberto tarde')).toBeInTheDocument();
    expect(within(screen.getByTestId('dia-2026-11-02')).getByText(/Finados/)).toBeInTheDocument();
    expect(screen.getByText(/Decisão 1: Não cabe tudo/)).toBeInTheDocument();
    expect(screen.getByText(/Responda no WhatsApp/)).toBeInTheDocument();
  });

  it('erro: a frase do banco e "Tentar de novo" (nunca "nada marcado")', async () => {
    h.rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'A agenda de produção é com o administrador.' } });
    montar(<SemanaProducao de="2026-11-02" onAbrirOs={() => {}} />);
    expect(await screen.findByText(/Não consegui ler a semana: A agenda de produção é com o administrador\./)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tentar de novo' })).toBeInTheDocument();
    expect(screen.queryByText('Nada no plano.')).not.toBeInTheDocument();
  });

  it('a tela ainda não instalada no banco (PGRST202): o aviso, sem erro', async () => {
    h.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } });
    montar(<SemanaProducao de="2026-11-02" onAbrirOs={() => {}} />);
    expect(await screen.findByText(/ainda não está instalada no banco\. Use a Grade\./)).toBeInTheDocument();
  });

  it('Desfazer sem perda vai direto; com cobrança, confirma antes — e a frase do banco volta', async () => {
    const user = userEvent.setup();
    h.rpc.mockImplementation(async (nome: string) => (nome === 'agenda_tela_semana'
      ? { data: SEMANA_DE_EXEMPLO, error: null }
      : { data: { ok: true, texto: 'Desfeito: volta como estava.' }, error: null }));
    montar(<SemanaProducao de="2026-11-02" onAbrirOs={() => {}} />);
    const botoes = await screen.findAllByRole('button', { name: /Desfazer/ });
    expect(botoes).toHaveLength(2);

    await user.click(botoes[0]);
    expect(h.rpc).toHaveBeenCalledWith('agenda_desfazer_pela_tela', { p_acao: 'a1' });
    expect(await screen.findByText('O que eu mudei sozinho')).toBeInTheDocument();
    expect(h.aviso.success).toHaveBeenCalledWith('Desfeito: volta como estava.');

    h.rpc.mockClear();
    await user.click((await screen.findAllByRole('button', { name: /Desfazer/ }))[1]);
    expect(await screen.findByText('Desfazer a conclusão?')).toBeInTheDocument();
    expect(h.rpc).not.toHaveBeenCalledWith('agenda_desfazer_pela_tela', expect.anything());
    await user.click(screen.getByRole('button', { name: 'Desfazer' }));
    expect(h.rpc).toHaveBeenCalledWith('agenda_desfazer_pela_tela', { p_acao: 'a2' });
  });

  it('Desfazer recusado pelo banco: o aviso de erro com a frase dele', async () => {
    const user = userEvent.setup();
    h.rpc.mockImplementation(async (nome: string) => (nome === 'agenda_tela_semana'
      ? { data: SEMANA_DE_EXEMPLO, error: null }
      : { data: { ok: false, texto: 'Isso já foi desfeito.' }, error: null }));
    montar(<SemanaProducao de="2026-11-02" onAbrirOs={() => {}} />);
    await user.click((await screen.findAllByRole('button', { name: /Desfazer/ }))[0]);
    await vi.waitFor(() => expect(h.aviso.error).toHaveBeenCalledWith('Isso já foi desfeito.'));
  });
});

describe('Agenda › Carteira de produção', () => {
  it('carregando → os cartões com a idade em texto, a próxima ação e quem trava; o filtro por situação', async () => {
    const user = userEvent.setup();
    const d = adiado<{ data: unknown; error: null }>();
    h.rpc.mockReturnValueOnce(d.promessa);
    const abrir = vi.fn();
    montar(<CarteiraProducao onAbrirOs={abrir} />);
    expect(screen.getByText('Carregando a carteira…')).toBeInTheDocument();
    d.resolver({ data: CARTEIRA_DE_EXEMPLO, error: null });

    const cartao = await screen.findByTestId('cartao-OS-00032');
    expect(within(cartao).getByText('OS-00032 · Kalmar · Kalmar 40')).toBeInTheDocument();
    expect(within(cartao).getByText('há 118 dias úteis')).toBeInTheDocument();
    expect(within(cartao).getByText('o cliente liberar')).toBeInTheDocument();
    expect(within(cartao).getByText('trava: o cliente')).toBeInTheDocument();
    expect(screen.getAllByTestId(/^cartao-/)).toHaveLength(3);

    // o filtro (MultiFilterBar): "Situação" com o número de cada grupo
    await user.click(screen.getByRole('button', { name: /Filtros/ }));
    await user.click(await screen.findByText('Material com data (1)'));
    expect(screen.getAllByTestId(/^cartao-/).map((c) => c.getAttribute('data-testid'))).toEqual(['cartao-OS-00112']);

    await user.click(screen.getByTestId('cartao-OS-00112'));
    expect(abrir).toHaveBeenCalledWith('os-112');
  });

  it('erro: a frase do banco; a tela ainda não instalada: o aviso', async () => {
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '57014', message: 'tempo esgotado' } });
    const { unmount } = montar(<CarteiraProducao onAbrirOs={() => {}} />);
    expect(await screen.findByText(/Não consegui ler a carteira: tempo esgotado/)).toBeInTheDocument();
    unmount();
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '42883', message: 'function does not exist' } });
    montar(<CarteiraProducao onAbrirOs={() => {}} />);
    expect(await screen.findByText(/A carteira de produção ainda não está instalada no banco/)).toBeInTheDocument();
  });
});
