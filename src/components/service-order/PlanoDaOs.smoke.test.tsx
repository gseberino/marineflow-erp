// Smoke de render do cartão "Plano" da OS (Agenda de Produção, Fase 3, P7a): carregando → o resumo numa linha; aberto, os
// marcos, a duração com a fonte, o material com o nível A–E e o trecho, planejado × realizado com a diária só "lançada"/"a
// confirmar" (nunca o valor); o Corrigir dias (rótulo acima, meio em meio dia) e o Entregue pela porta; o erro com a frase
// do banco; a tela ainda não instalada some sem erro; e quem não é admin/financeiro não vê o cartão.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { PLANO_DE_EXEMPLO } from '@/components/agenda/producao/dados-de-exemplo';

const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  config: { data: null as unknown, error: null as unknown },
  papel: 'admin' as string,
  aviso: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder: Record<string, unknown> = {};
  builder.select = () => builder;
  builder.maybeSingle = async () => h.config;
  return { supabase: { rpc: (...a: unknown[]) => h.rpc(...a), from: () => builder } };
});
vi.mock('sonner', () => ({ toast: h.aviso }));
vi.mock('@/hooks/use-auth', () => ({ useOptionalAuth: () => ({ user: { id: 'u1', role: h.papel } }) }));

import { PlanoDaOs, PlanoDaOsNaOs } from './PlanoDaOs';

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
  h.aviso.success.mockClear();
  h.aviso.error.mockClear();
  h.config = { data: { jornada_horas: 8, carga_max: '0.80', modo_leitura: 'sombra', modo_proposta: 'ligado' }, error: null };
  h.papel = 'admin';
});

describe('cartão Plano da OS', () => {
  it('carregando → o resumo; aberto, os marcos, a duração, o material A–E e planejado × realizado sem valor', async () => {
    const user = userEvent.setup();
    const d = adiado<{ data: unknown; error: null }>();
    h.rpc.mockReturnValueOnce(d.promessa);
    montar(<PlanoDaOs osId="os-69" status="completed" />);
    expect(screen.getByText('Carregando o plano…')).toBeInTheDocument();
    d.resolver({ data: PLANO_DE_EXEMPLO, error: null });

    expect(await screen.findByText('concluído · 3 dias: Roberto (dia todo) (você disse)')).toBeInTheDocument();
    expect(h.rpc).toHaveBeenCalledWith('os_plano_da_os', { p_os: 'os-69' });
    await user.click(screen.getByRole('button', { name: /Ver o plano/ }));

    const cartao = screen.getByTestId('plano-da-os');
    // rótulo acima do valor (DadosDaFicha)
    expect(within(cartao).getByText('Marcos')).toBeInTheDocument();
    expect(within(cartao).getByText(/Entrada qua 29\/07 · início ter 03\/11/)).toBeInTheDocument();
    expect(within(cartao).getByText('faixa 2 a 3,5 dias')).toBeInTheDocument();
    expect(within(cartao).getByText('Você abre e fecha (pela regra)')).toBeInTheDocument();
    expect(within(cartao).getByText('o cliente precisa até qui 05/11')).toBeInTheDocument();
    // o material: o selo com o nível e o texto do nível, e o trecho de onde veio
    expect(within(cartao).getByTitle('na mão').textContent).toBe('A');
    expect(within(cartao).getByTitle('previsão sua').textContent).toBe('C');
    expect(within(cartao).getByText('“o material do Vanderlei chegou da Premel”')).toBeInTheDocument();
    expect(within(cartao).getByText(/pode começar sem/)).toBeInTheDocument();
    // planejado × realizado: a diária só lançada / a confirmar
    expect(within(cartao).getByText(/diária lançada/)).toBeInTheDocument();
    expect(within(cartao).getByText(/diária a confirmar/)).toBeInTheDocument();
    expect(within(cartao).getByText(/\(chuva\)/)).toBeInTheDocument();
    expect(cartao.textContent).not.toMatch(/R\$/);
    // concluída: sem Corrigir dias (a duração não muda mais)
    expect(within(cartao).queryByLabelText('Corrigir dias')).not.toBeInTheDocument();
    expect(within(cartao).getByText(/você foi à tarde/)).toBeInTheDocument();
  });

  it('Corrigir dias (rótulo acima, meio em meio dia) manda os dias ao banco e mostra a frase dele', async () => {
    const user = userEvent.setup();
    h.rpc.mockImplementation(async (nome: string) => (nome === 'os_plano_da_os'
      ? { data: { ...PLANO_DE_EXEMPLO, status: 'scheduled', pode_entregar: false }, error: null }
      : { data: { ok: true, dias: 1.5, texto: 'Duração gravada: 1,5 dia.' }, error: null }));
    montar(<PlanoDaOs osId="os-69" status="scheduled" />);
    await user.click(await screen.findByRole('button', { name: /Ver o plano/ }));
    const campo = screen.getByLabelText('Corrigir dias');
    expect(campo).toHaveAttribute('step', '0.5');
    expect(screen.queryByRole('button', { name: /Entregue/ })).not.toBeInTheDocument();
    // campo numérico (o navegador em pt-BR aceita a vírgula; o jsdom só o ponto)
    await user.type(campo, '1.5');
    await user.click(screen.getByRole('button', { name: /Gravar/ }));
    expect(h.rpc).toHaveBeenCalledWith('os_planejar_pela_tela', { p_os: 'os-69', p_dias: 1.5 });
    await vi.waitFor(() => expect(h.aviso.success).toHaveBeenCalledWith('Duração gravada: 1,5 dia.'));
  });

  it('Entregue: a entrega pela porta (os_registrar_marco, via tela); a recusa é o aviso de erro', async () => {
    const user = userEvent.setup();
    h.rpc.mockImplementation(async (nome: string) => (nome === 'os_plano_da_os'
      ? { data: PLANO_DE_EXEMPLO, error: null }
      : { data: { ok: false, texto: 'A OS ainda não foi concluída.' }, error: null }));
    montar(<PlanoDaOs osId="os-69" status="completed" />);
    await user.click(await screen.findByRole('button', { name: /Entregue/ }));
    expect(h.rpc).toHaveBeenCalledWith('os_registrar_marco', { p_os: 'os-69', p_marco: 'entrega', p_via: 'tela' });
    await vi.waitFor(() => expect(h.aviso.error).toHaveBeenCalledWith('A OS ainda não foi concluída.'));
  });

  it('erro: a frase do banco e "Tentar de novo"; a tela ainda não instalada some sem erro', async () => {
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'O plano da OS é com o administrador.' } });
    const { unmount } = montar(<PlanoDaOs osId="os-69" status="scheduled" />);
    expect(await screen.findByText(/Não consegui ler o plano: O plano da OS é com o administrador\./)).toBeInTheDocument();
    unmount();
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } });
    const { container } = montar(<PlanoDaOs osId="os-69" status="scheduled" />);
    await vi.waitFor(() => expect(h.rpc).toHaveBeenCalledTimes(2));
    await vi.waitFor(() => expect(container.textContent).toBe(''));
  });

  it('só admin/financeiro, fora de orçamento e com a agenda de produção ligada', async () => {
    h.rpc.mockResolvedValue({ data: PLANO_DE_EXEMPLO, error: null });
    h.papel = 'technician';
    const a = montar(<PlanoDaOsNaOs osId="os-69" status="scheduled" />);
    expect(a.container.textContent).toBe('');
    a.unmount();
    h.papel = 'admin';
    const b = montar(<PlanoDaOsNaOs osId="os-69" status="draft" />);
    expect(b.container.textContent).toBe('');
    b.unmount();
    h.config = { data: { jornada_horas: 8, carga_max: '0.80', modo_leitura: 'desligado', modo_proposta: 'desligado' }, error: null };
    const c = montar(<PlanoDaOsNaOs osId="os-69" status="scheduled" />);
    await new Promise((r) => setTimeout(r, 20));
    expect(c.container.textContent).toBe('');
    c.unmount();
    h.config = { data: { jornada_horas: 8, carga_max: '0.80', modo_leitura: 'sombra', modo_proposta: 'sombra' }, error: null };
    montar(<PlanoDaOsNaOs osId="os-69" status="scheduled" />);
    expect(await screen.findByTestId('plano-da-os')).toBeInTheDocument();
  });
});
