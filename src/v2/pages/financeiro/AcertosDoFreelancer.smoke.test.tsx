// Acertos de um freelancer com reembolso de comprovante (F2b dos comprovantes, 11/10/2026): a lista
// diz quanto de reembolso entrou em cada acerto e a conferência do "Fechar acerto" mostra a linha
// "(+) Reembolsos (CMP-…)" entre o trabalhado e os vales — os números vêm da simulação do banco.
//
// Simula só a fronteira com o banco (supabase.rpc), na forma do contrato da spec F3 (3.7).
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
  conferido_em: null, conferido_texto: null, ...o,
});

/** O que o banco devolve ao simular o acerto (fechar_acerto_diarias com p_simular). */
let simulacao: Record<string, unknown> = {};
const simulacaoComReembolsos = (itens: Array<{ codigo: string; valor: number }>) => ({
  ok: true, simulacao: true, favorecido: 'Roberto', de: '2026-09-17', ate: '2026-10-11', saldo_anterior: 0, dias: 2,
  trabalhado: 320, pago_no_periodo: 100, pago_aguardando_banco: 0, vales: [], resumo: '',
  reembolsos: itens.reduce((s, r) => s + r.valor, 0),
  valor_do_acerto: 220 + itens.reduce((s, r) => s + r.valor, 0),
  reembolsos_itens: itens.map((r, i) => ({ data: `2026-09-${20 + i}`, valor: r.valor, descricao: `Reembolso ${r.codigo} · Loja`, codigo: r.codigo })),
});

beforeEach(() => {
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string) => (nome === 'fechar_acerto_diarias'
    ? { data: simulacao, error: null }
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
async function rotulosDaConferencia() {
  const dialogo = await screen.findByRole('dialog');
  await within(dialogo).findByText('A pagar neste acerto');
  return { dialogo, rotulos: within(dialogo).getAllByRole('term').map((dt) => dt.textContent ?? '') };
}

describe('AcertosDoFreelancer com reembolso de comprovante', () => {
  it('a lista diz o reembolso do acerto; sem reembolso, a linha é a de antes', () => {
    renderizar([acerto(), acerto({ id: 'ac0', numero: 0, reembolsos: 0, status: 'reaberto' })]);
    expect(screen.getByText(/1 diária\(s\) · reembolsos R\$\s?62,00 · vales R\$\s?100,00/)).toBeInTheDocument();
    expect(screen.getAllByText(/diária\(s\)/).filter((e) => !/reembolsos/.test(e.textContent ?? ''))).toHaveLength(1);
  });

  it('a conferência do fechamento mostra "(+) Reembolsos (CMP-…)" entre o trabalhado e os vales', async () => {
    simulacao = simulacaoComReembolsos([{ codigo: 'CMP-00124', valor: 62 }, { codigo: 'CMP-00130', valor: 30 }]);
    const user = userEvent.setup();
    renderizar([]);
    await user.click(screen.getByRole('button', { name: /Fechar acerto/ }));
    const { dialogo, rotulos } = await rotulosDaConferencia();

    const iTrab = rotulos.findIndex((r) => r.startsWith('Trabalhado'));
    const iReemb = rotulos.indexOf('(+) Reembolsos (CMP-00124, CMP-00130)');
    const iVales = rotulos.indexOf('(−) Vales já pagos');
    expect(iReemb).toBe(iTrab + 1);
    expect(iVales).toBe(iReemb + 1);
    const valor = within(dialogo).getByText('(+) Reembolsos (CMP-00124, CMP-00130)').nextElementSibling;
    expect(valor?.textContent).toMatch(/R\$\s?92,00/);
    expect(within(dialogo).getByText('A pagar neste acerto').nextElementSibling?.textContent).toMatch(/R\$\s?312,00/);
    expect(rpc).toHaveBeenCalledWith('fechar_acerto_diarias', expect.objectContaining({ p_favorecido_id: 'r', p_simular: true }));
  });

  it('com mais de três comprovantes, a conferência resume ("e mais N"); o recibo é que lista todos', async () => {
    simulacao = simulacaoComReembolsos(['CMP-00124', 'CMP-00125', 'CMP-00126', 'CMP-00127'].map((codigo) => ({ codigo, valor: 10 })));
    const user = userEvent.setup();
    renderizar([]);
    await user.click(screen.getByRole('button', { name: /Fechar acerto/ }));
    const { rotulos } = await rotulosDaConferencia();
    expect(rotulos).toContain('(+) Reembolsos (CMP-00124, CMP-00125, CMP-00126 e mais 1)');
  });

  it('reembolso sem código de comprovante (origem_codigo nulo): "(+) Reembolsos", sem "()" vazio', async () => {
    const s = simulacaoComReembolsos([{ codigo: 'CMP-00124', valor: 62 }]);
    simulacao = { ...s, reembolsos_itens: s.reembolsos_itens.map((r) => ({ ...r, codigo: null })) };
    const user = userEvent.setup();
    renderizar([]);
    await user.click(screen.getByRole('button', { name: /Fechar acerto/ }));
    const { rotulos } = await rotulosDaConferencia();
    expect(rotulos).toContain('(+) Reembolsos');
    expect(rotulos.some((r) => r.includes('()'))).toBe(false);
  });

  it('os textos do acerto dizem que os reembolsos também ficam travados', async () => {
    renderizar([acerto()]);
    expect(screen.getByText(/trava os dias e os reembolsos até a data/)).toBeInTheDocument();
  });

  it('sem reembolso no período (ou banco de antes da F2b), a conferência é a de antes', async () => {
    const { reembolsos: _r, reembolsos_itens: _i, ...semF2b } = simulacaoComReembolsos([]);
    simulacao = semF2b;
    const user = userEvent.setup();
    renderizar([]);
    await user.click(screen.getByRole('button', { name: /Fechar acerto/ }));
    const { rotulos } = await rotulosDaConferencia();
    expect(rotulos.some((r) => r.includes('Reembolsos'))).toBe(false);
    expect(rotulos).toContain('(−) Vales já pagos');
  });
});
