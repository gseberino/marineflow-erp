// Recibos de um freelancer (F2 da revisão de 24/10, 27/10/2026): o recibo sai do Pix que zera a conta.
// A lista distingue o recibo novo ("Pix R$ X em DD/MM", "Falta o papel assinado") do acerto antigo
// ("a pagar"); a conferência mostra a conta do papel, com o reembolso de comprovante (F2b, 11/10/2026)
// entre o trabalhado e o já recebido, e as travas do banco de uma vez — com trava, não emite.
//
// Simula só a fronteira com o banco (supabase.rpc).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import type { Acerto } from '@/hooks/use-diarias';
import { AcertosDoFreelancer } from './AcertosDoFreelancer';

const rpc = vi.fn();

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: (...a: unknown[]) => rpc(...a) },
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));

const acerto = (o: Partial<Acerto> = {}): Acerto => ({
  id: 'ac1', numero: 1, favorecido_id: 'r', de: '2026-09-01', ate: '2026-09-16', saldo_anterior: 0, dias: 1,
  trabalhado: 180, pago_no_periodo: 100, valor_do_acerto: 142, reembolsos: 62, status: 'fechado',
  criado_em: '2026-09-17T12:00:00Z', reaberto_em: null, motivo_reabertura: null, enviado_ao_freelancer_em: null,
  conferido_em: null, conferido_texto: null, pagos_ate: null, documento: null, hash: null, assinado_em: null, assinatura_arquivo: null, ...o,
});

/** O que o banco devolve ao simular o recibo (fechar_acerto_diarias com p_simular). */
let simulacao: Record<string, unknown> = {};
const simular = (itens: Array<{ codigo: string | null; valor: number }>, o: Record<string, unknown> = {}) => {
  const reembolsos = itens.reduce((s, r) => s + r.valor, 0);
  return {
    ok: true, simulacao: true, favorecido: 'Roberto', de: '2026-09-17', ate: '2026-10-11', saldo_anterior: 0, dias: 2,
    trabalhado: 320, pago_no_periodo: 100, vales: [], resumo: '', reembolsos,
    valor_do_acerto: 220 + reembolsos,
    reembolsos_itens: itens.map((r, i) => ({ data: `2026-09-${20 + i}`, valor: r.valor, descricao: `Reembolso ${r.codigo} · Loja`, codigo: r.codigo })),
    pix: { id: 'px', data: '2026-10-12', valor: 220 + reembolsos, conta: 'C6 - Conta PJ HBR' },
    candidatos: [
      { id: 'v1', data: '2026-09-25', valor: 100, conta: 'C6', aguardando: false, saldo_final: 220 + reembolsos, zera: false },
      { id: 'px', data: '2026-10-12', valor: 220 + reembolsos, conta: 'C6', aguardando: false, saldo_final: 0, zera: true },
    ],
    travas: [], saldo_final: 0,
    ...o,
  };
};

beforeEach(() => {
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => (nome === 'fechar_acerto_diarias'
    ? { data: args.p_simular ? simulacao : { id: 'n', numero: 2, message: 'Recibo nº 0002 fechado' }, error: null }
    : { data: null, error: { message: `rpc inesperada: ${nome}` } }));
});

function renderizar(acertos: Acerto[]) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <AcertosDoFreelancer favorecidoId="r" nome="Roberto Daniel" acertos={acertos} gerandoPdf={false} onRecibo={vi.fn()} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

/** Os rótulos da conferência, na ordem em que aparecem. */
async function abrirConferencia() {
  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /Emitir recibo/ }));
  const dialogo = await screen.findByRole('dialog');
  await within(dialogo).findByText(/^Trabalhado/);
  return { user, dialogo, rotulos: within(dialogo).getAllByRole('term').map((dt) => dt.textContent ?? '') };
}

describe('AcertosDoFreelancer: recibo no Pix que zera', () => {
  it('a lista: recibo novo diz o Pix e que falta o papel assinado; o antigo continua "a pagar"', () => {
    renderizar([
      acerto({ id: 'n1', numero: 2, documento: {} as never, pagos_ate: '2026-09-17', valor_do_acerto: 142 }),
      acerto({ id: 'ac0', numero: 1, reembolsos: 0, status: 'reaberto' }),
    ]);
    expect(screen.getByText(/Pix R\$\s?142,00 em 17\/09/)).toBeInTheDocument();
    expect(screen.getByText('Falta o papel assinado')).toBeInTheDocument();
    expect(screen.getByText(/a pagar R\$\s?142,00/)).toBeInTheDocument();
    expect(screen.getByText(/1 diária\(s\) · reembolso de despesas pagas pelo técnico R\$\s?62,00 · já recebido R\$\s?100,00/)).toBeInTheDocument();
  });

  it('papel assinado (F4): o recibo assinado diz quando e oferece ver o papel; o que falta oferece anexar no menu', async () => {
    const user = userEvent.setup();
    renderizar([
      acerto({ id: 'n2', numero: 3, documento: {} as never, assinado_em: '2026-10-25T15:00:00Z', assinatura_arquivo: 'diarias/recibos/n2/1.jpg' }),
      acerto({ id: 'n1', numero: 2, documento: {} as never }),
    ]);
    expect(screen.getByText((_, el) => el?.tagName === 'DIV' && (el.textContent ?? '').trim() === 'Assinado 25/10/2026')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Ver papel assinado/ })).toBeInTheDocument();
    expect(screen.getByText('Falta o papel assinado')).toBeInTheDocument();
    await user.click(screen.getAllByRole('button', { name: /Mais ações/ })[1]);
    expect(await screen.findByRole('menuitem', { name: /Anexar papel assinado/ })).toBeInTheDocument();
    expect(screen.getByLabelText('Papel assinado')).toHaveAttribute('accept', 'image/*,application/pdf');
  });

  it('a conferência: o reembolso entre o trabalhado e o já recebido, e o Pix que zera por último', async () => {
    simulacao = simular([{ codigo: 'CMP-00124', valor: 62 }, { codigo: 'CMP-00130', valor: 30 }]);
    renderizar([]);
    const { dialogo, rotulos } = await abrirConferencia();
    const iTrab = rotulos.findIndex((r) => r.startsWith('Trabalhado'));
    const iReemb = rotulos.indexOf('(+) Reembolso de despesas pagas pelo técnico (CMP-00124, CMP-00130)');
    expect(iReemb).toBe(iTrab + 1);
    expect(rotulos[iReemb + 1]).toBe('(−) Já recebido');
    expect(rotulos[iReemb + 2]).toBe('Pix de 12/10');
    expect(within(dialogo).getByText('Pix de 12/10').nextElementSibling?.textContent).toMatch(/R\$\s?312,00/);
    expect(within(dialogo).getByRole('button', { name: /12\/10.*zera a conta/ })).toHaveAttribute('aria-pressed', 'true');
    expect(rpc).toHaveBeenCalledWith('fechar_acerto_diarias', expect.objectContaining({ p_favorecido_id: 'r', p_simular: true, p_pix_id: null }));
  });

  it('com mais de três comprovantes, a conferência resume ("e mais N"); o recibo é que lista todos', async () => {
    simulacao = simular(['CMP-00124', 'CMP-00125', 'CMP-00126', 'CMP-00127'].map((codigo) => ({ codigo, valor: 10 })));
    renderizar([]);
    const { rotulos } = await abrirConferencia();
    expect(rotulos).toContain('(+) Reembolso de despesas pagas pelo técnico (CMP-00124, CMP-00125, CMP-00126 e mais 1)');
  });

  it('reembolso sem código de comprovante: só o rótulo, sem "()" vazio; sem reembolso, nada de reembolso', async () => {
    simulacao = simular([{ codigo: null, valor: 62 }]);
    renderizar([]);
    const { rotulos } = await abrirConferencia();
    expect(rotulos).toContain('(+) Reembolso de despesas pagas pelo técnico');
    expect(rotulos.some((r) => r.includes('()'))).toBe(false);
  });

  it('emitir manda o Pix escolhido; escolher outro Pix pergunta de novo ao banco', async () => {
    simulacao = simular([]);
    renderizar([]);
    const { user, dialogo } = await abrirConferencia();
    await user.click(within(dialogo).getByRole('button', { name: /25\/09/ }));
    expect(rpc).toHaveBeenCalledWith('fechar_acerto_diarias', expect.objectContaining({ p_simular: true, p_pix_id: 'v1' }));
    await user.click(within(dialogo).getByRole('button', { name: /^Emitir recibo$/ }));
    expect(rpc).toHaveBeenCalledWith('fechar_acerto_diarias', expect.objectContaining({ p_simular: false, p_pix_id: 'px' }));
  });

  it('com trava, lista todas e não emite', async () => {
    simulacao = simular([], { ok: false, travas: ['Falta o CPF de Roberto no cadastro.', 'Pix de 10/10 (R$ 510,00) está na fila: aprove antes do recibo.'] });
    renderizar([]);
    const { dialogo } = await abrirConferencia();
    expect(within(dialogo).getByText('Falta o CPF de Roberto no cadastro.')).toBeInTheDocument();
    expect(within(dialogo).getByText(/está na fila: aprove antes do recibo/)).toBeInTheDocument();
    expect(within(dialogo).getByRole('button', { name: /^Emitir recibo$/ })).toBeDisabled();
  });

  it('só o primeiro recibo pergunta "Serviços desde"; os textos dizem que os reembolsos também ficam travados', async () => {
    simulacao = simular([]);
    renderizar([acerto({ documento: {} as never })]);
    expect(screen.getByText(/trava os dias e os reembolsos até a data/)).toBeInTheDocument();
    const { dialogo } = await abrirConferencia();
    expect(within(dialogo).queryByLabelText('Serviços desde')).toBeNull();
  });
});
