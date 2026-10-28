// Financeiro › Diárias: cartões com o saldo de cada freelancer, extrato com saldo corrido, grade do
// mês com a ficha do dia, e excluir com Desfazer (sem diálogo de confirmação).
//
// Simula só a fronteira com o banco (supabase.rpc): os hooks de verdade rodam, então o teste pega
// o que a tela manda para as funções do banco — que é o que importa.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ROTULO_REEMBOLSO, ROTULO_REEMBOLSOS } from '@/lib/extrato-diarias';
import { DiariasPanel, type FiltroDasDiarias } from './DiariasPanel';

const rpc = vi.fn();
const toastFn = vi.fn();
const exportToCSV = vi.fn();

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpc(...a),
    // A leitura do cadastro dos freelancers (CPF e PIX) que os documentos fazem, e a dos acertos.
    from: (tabela: string) => ({ select: () => ({
      in: async () => ({ data: [
        { id: 'r', name: 'Roberto', document: '12345678940', pix_key: null },
        { id: 'm', name: 'Mickael', document: '98765432100', pix_key: null },
      ], error: null }),
      eq: () => ({ order: async () => ({ data: tabela === 'acertos_diarias' ? acertosNoBanco : [], error: null }) }),
    }) }),
  },
}));

/** O acerto nº 0001 do Roberto trava 01/09 a 16/09 (o dia 16/09 do extrato fica travado). */
let acertosNoBanco: unknown[] = [];
const acertoDoRoberto = {
  id: 'ac1', numero: 1, favorecido_id: 'r', de: '2026-09-01', ate: '2026-09-16', saldo_anterior: 0, dias: 1,
  trabalhado: 180, pago_no_periodo: 0, valor_do_acerto: 180, status: 'fechado', criado_em: '2026-09-17T12:00:00Z',
  reaberto_em: null, motivo_reabertura: null, enviado_ao_freelancer_em: '2026-09-17T12:05:00Z', conferido_em: '2026-09-17T13:00:00Z',
  conferido_texto: 'ok',
};
vi.mock('@/lib/export-utils', () => ({ exportToCSV: (...a: unknown[]) => exportToCSV(...a) }));
vi.mock('sonner', () => ({
  toast: Object.assign((...a: unknown[]) => toastFn(...a), { success: vi.fn(), error: vi.fn() }),
}));
vi.mock('@/hooks/use-payees', () => ({
  useServiceOrdersVinculaveis: () => ({ data: [] }),
  usePayees: () => ({ data: [{ id: 's1', name: 'Gustavo', kind: 'socio' }] }),
}));

const pessoas = [
  { id: 'r', nome: 'Roberto', diaria: 160, desde: '2026-08-25', dias: 12, trabalhado: 1980, pago: 1530,
    ultimo_pagamento: '2026-09-27', saldo_final: 450, estado: 'deve' },
  { id: 'm', nome: 'Mickael', diaria: 130, desde: '2026-09-10', dias: 4, trabalhado: 580, pago: 600,
    ultimo_pagamento: '2026-08-28', saldo_final: -20, estado: 'adiantado' },
];

const contaDoRoberto = {
  favorecido: { id: 'r', nome: 'Roberto', desde: '2026-08-25', saldo_inicial: 0, diaria: 160 },
  de: null, ate: null, saldo_anterior: 0, dias: 1, trabalhado: 180, pago: 100, saldo_final: 80, estado: 'deve',
  linhas: [
    { data: '2026-09-16', tipo: 'dia', id: 'd1', jornada: 'inteiro', fracao: 1, valor_diaria: 160, extras: 20,
      descontos: 0, trabalhado: 180, pago: 0, descricao: null, conta: null, categoria: null,
      observacao: 'Gerador do Marcelo', os: [{ id: 'o1', numero: 'OS-0042' }], saldo: 180 },
    { data: '2026-09-22', tipo: 'pagamento', id: 'p1', jornada: null, fracao: null, valor_diaria: null, extras: null,
      descontos: null, trabalhado: 0, pago: 100, descricao: 'Pix enviado para Roberto', conta: 'C6 - Conta PJ HBR',
      categoria: 'Diárias de freelancers', observacao: null, os: [], saldo: 80 },
  ],
};
/**
 * Reembolso de comprovante (F2b, 11/10/2026), na forma do contrato da spec F3 (3.7): a linha
 * `reembolso` soma a favor dele (trabalhado = valor, pago = 0, conta = código CMP) e o topo ganha
 * `reembolsos`; saldo_final = anterior + trabalhado + reembolsos − pago.
 */
let comReembolso = false;
const linhaDeReembolso = {
  data: '2026-09-18', tipo: 'reembolso', id: 'rb1', jornada: null, fracao: null, valor_diaria: null, extras: null,
  descontos: null, trabalhado: 62, pago: 0, descricao: 'Reembolso CMP-00124 · AutoZone', conta: 'CMP-00124',
  categoria: 'Peças e materiais', observacao: null, os: [{ id: 'o1', numero: 'OS-0042' }], saldo: 242, aguardando: false,
};
const contaComReembolso = () => ({
  ...contaDoRoberto, reembolsos: 62, saldo_final: 142,
  linhas: [contaDoRoberto.linhas[0], linhaDeReembolso, { ...contaDoRoberto.linhas[1], saldo: 142 }],
});
/**
 * Pagamento dividido (resposta 4 do dono, 11/10/2026), na forma do contrato da spec dos ajustes (4.1):
 * a proposta lista os reembolsos em aberto; o pagamento já dividido vem como UMA linha com o sufixo
 * "(inclui reembolso de despesas pagas pelo técnico: R$ X)" e o reembolso coberto, "pago em DD/MM".
 */
let reembolsoEmAberto = false;
let pagamentoJaDividido = false;
const contaComPagamentoDividido = () => {
  const c = contaComReembolso();
  return { ...c, linhas: [
    c.linhas[0],
    { ...c.linhas[1], observacao: 'pago em 22/09' },
    { ...c.linhas[2], descricao: 'Pix enviado para Roberto (inclui reembolso de despesas pagas pelo técnico: R$ 62,00)' },
  ] };
};
const contaVazia = (id: string, nome: string, desde: string) => ({
  favorecido: { id, nome, desde, saldo_inicial: 0, diaria: 130 },
  de: null, ate: null, saldo_anterior: 0, dias: 0, trabalhado: 0, pago: 0, saldo_final: 0, estado: 'quitado', linhas: [],
});

beforeEach(() => {
  acertosNoBanco = [];
  comReembolso = false;
  reembolsoEmAberto = false;
  pagamentoJaDividido = false;
  toastFn.mockReset();
  exportToCSV.mockReset();
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => {
    switch (nome) {
      case 'resumo_freelancers':
        if (args.p_atalho === 'em_aberto') {
          return { data: { pessoas: [{ ...pessoas[0], de: '2026-09-23', ate: null, pago_aguardando_banco: 100, pago_falta_aprovar: 50 }],
            trabalhado: 160, pago: 150, dias: 1, deve: 10, adiantado: 0 }, error: null };
        }
        if (comReembolso) {
          return { data: { pessoas: [{ ...pessoas[0], reembolsos: 62, saldo_final: 512 }, pessoas[1]],
            trabalhado: 2560, pago: 2130, reembolsos: 62, dias: 16, deve: 512, adiantado: 20 }, error: null };
        }
        return { data: { pessoas, trabalhado: 2560, pago: 2130, dias: 16, deve: 450, adiantado: 20 }, error: null };
      case 'conta_corrente_freelancer':
        if (args.p_atalho === 'em_aberto') {
          return { data: { ...contaDoRoberto, de: '2026-09-23', ate: null, saldo_anterior: 0, pago: 150, pago_aguardando_banco: 100,
            pago_falta_aprovar: 50,
            linhas: [{ ...contaDoRoberto.linhas[1], id: 'a1', data: '2026-10-06', conta: 'Anotado — aguardando o banco',
              descricao: 'Adiantamento diarias', aguardando: true },
              // 27/10/2026: o Pix que o banco já trouxe e espera a fila (por CPF, ou anotado e já casado)
              { ...contaDoRoberto.linhas[1], id: 'b1', data: '2026-10-10', pago: 50, conta: 'No banco — falta aprovar na fila',
                descricao: 'Pix enviado para Roberto', categoria: null, aguardando: true }] }, error: null };
        }
        if (args.p_favorecido_id === 'r') {
          return { data: pagamentoJaDividido ? contaComPagamentoDividido() : comReembolso ? contaComReembolso() : contaDoRoberto, error: null };
        }
        return { data: contaVazia('m', 'Mickael', '2026-09-10'), error: null };
      case 'proposta_de_divisao_do_pagamento': {
        const valor = Number(args.p_valor);
        const emAberto = reembolsoEmAberto
          ? [{ id: 'rb1', codigo: 'CMP-00124', data: '2026-09-18', valor: 62, categoria: 'Peças e materiais',
              descricao: 'Reembolso CMP-00124 · AutoZone', acerto: null }]
          : [];
        const cabe = emAberto.filter((r) => r.valor <= valor);
        const reembolsos = cabe.reduce((s, r) => s + r.valor, 0);
        return { data: { favorecido: { id: args.p_favorecido_id, nome: 'Roberto' }, valor, em_aberto: emAberto,
          propostos: cabe.map((r) => r.id), reembolsos, diarias: valor - reembolsos, partes: [] }, error: null };
      }
      case 'registrar_pagamento_do_freelancer':
        return { data: { ok: true, forma: args.p_forma, anotacao_id: 'a9', payable_id: null,
          divisao: { id: null, status: 'nenhuma', diarias: args.p_valor, reembolsos: 0, partes: [] }, message: 'Pagamento registrado.' }, error: null };
      case 'dividir_pagamento_do_freelancer':
        return { data: { ok: true, divisao: { id: 'dv1', status: 'aplicada', diarias: 38, reembolsos: 62, partes: [] },
          message: 'Pagamento dividido.' }, error: null };
      case 'apagar_diaria':
        return { data: { message: 'Diária de Roberto em qua 16/09 apagada.', apagado: {
          favorecido_id: 'r', data: '2026-09-16', jornada: 'inteiro', valor_diaria: 160, extras: 20, descontos: 0,
          observacao: 'Gerador do Marcelo', os_ids: ['o1'] } }, error: null };
      case 'registrar_diaria':
        return { data: { acao: 'atualizado', diaria_id: 'd1', message: 'ok' }, error: null };
      case 'anotar_transacao':
      case 'lancar_no_caixa':
        return { data: { ok: true, message: 'Anotado.' }, error: null };
      case 'fechar_acerto_diarias':
        return args.p_simular
          ? { data: { ok: true, favorecido: 'Roberto', de: '2026-09-17', ate: args.p_ate ?? '2026-10-05', saldo_anterior: 180, dias: 0, trabalhado: 0,
              pago_no_periodo: 100, valor_do_acerto: 80, resumo: '', travas: [],
              pix: { id: 'px', data: '2026-10-05', valor: 80, conta: 'C6' },
              candidatos: [{ id: 'px', data: '2026-10-05', valor: 80, conta: 'C6', aguardando: false, saldo_final: 0, zera: true }] }, error: null }
          : { data: { id: 'ac2', numero: 2, message: 'Recibo nº 0002 fechado.' }, error: null };
      case 'cadastrar_freelancer':
        if (String(args.p_nome).startsWith('Roberto')) {
          return { data: null, error: { message: 'Roberto já tem diária cadastrada (veja em Financeiro › Diárias).' } };
        }
        return { data: {
          acao: 'criado', favorecido_id: args.p_simular ? null : 'j', nome: args.p_nome, valor_diaria: args.p_valor_diaria,
          desde: args.p_desde, chave_pix: 'joao@exemplo.com', tipo_chave: 'email', regra: 'sem_cpf',
          message: args.p_simular ? undefined : `${args.p_nome} cadastrado: diária de R$ 150,00 desde ter 29/09.`,
        }, error: null };
      default:
        return { data: null, error: { message: `rpc inesperada: ${nome}` } };
    }
  });
});

function renderizar(aba: 'resumo' | 'extrato' | 'grade', onVerExtrato = vi.fn(), filtro: Partial<FiltroDasDiarias> = {}) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <DiariasPanel aba={aba}
                      filtro={{ periodo: 'tudo', de: '', ate: '', favorecidoId: aba === 'extrato' ? 'r' : null, mes: '2026-09', ...filtro }}
                      onFiltro={vi.fn()} onVerExtrato={onVerExtrato} />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { onVerExtrato };
}

const chamadas = (nome: string) => rpc.mock.calls.filter(([n]) => n === nome).map(([, a]) => a as Record<string, unknown>);

describe('DiariasPanel', () => {
  it('um cartão por freelancer com UM número ("A pagar" neutro, "Adiantado" em vermelho), na ordem do que mais se deve (F4)', async () => {
    const user = userEvent.setup();
    const { onVerExtrato } = renderizar('resumo');
    expect(await screen.findByText('Roberto')).toBeInTheDocument();
    expect(screen.getByText('Mickael')).toBeInTheDocument();
    const aPagar = screen.getAllByText('A pagar');
    expect(aPagar.length).toBeGreaterThan(0);
    expect(aPagar[0]).not.toHaveClass('text-destructive');
    // no topo, só o total a pagar (e o adiantado); os totais do período que não fechavam saíram
    expect(screen.getByText('A pagar a todos')).toBeInTheDocument();
    expect(screen.queryByText('Trabalhado no período')).not.toBeInTheDocument();
    expect(screen.queryByText('Saldo acumulado')).not.toBeInTheDocument();
    const nomes = screen.getAllByText(/^(Roberto|Mickael)$/).map((e) => e.textContent);
    expect(nomes[0]).toBe('Roberto');
    await user.click(screen.getAllByRole('button', { name: 'Lançamentos e recibo' })[0]);
    expect(onVerExtrato).toHaveBeenCalledWith('r');
    expect(screen.getAllByRole('button', { name: 'Pagar' }).length).toBeGreaterThan(0);
  });

  it('o extrato mostra o dia com a OS e o pagamento com a conta de onde saiu', async () => {
    renderizar('extrato');
    // o número já vem como "OS-0042" do banco: sem outro "OS " na frente
    expect(await screen.findByText('OS-0042')).toBeInTheDocument();
    expect(screen.queryByText('OS OS-0042')).not.toBeInTheDocument();
    expect(screen.getByText(/Gerador do Marcelo/)).toBeInTheDocument();
    expect(screen.getByText('C6 - Conta PJ HBR')).toBeInTheDocument();
    expect(screen.getByText(/Pix enviado para Roberto · Diárias de freelancers/)).toBeInTheDocument();
  });

  it('excluir não pergunta: apaga e oferece Desfazer, que registra o dia de novo como era', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await user.click(await screen.findByRole('button', { name: /Mais ações para dia qua 16\/09/i }));
    await user.click(await screen.findByRole('menuitem', { name: /Excluir o dia/ }));

    await waitFor(() => expect(chamadas('apagar_diaria')).toEqual([{ p_diaria_id: 'd1' }]));
    await waitFor(() => expect(toastFn).toHaveBeenCalled());
    const [mensagem, opcoes] = toastFn.mock.calls[0] as [string, { action: { label: string; onClick: () => void } }];
    expect(mensagem).toMatch(/apagada/);
    expect(opcoes.action.label).toBe('Desfazer');
    opcoes.action.onClick();
    await waitFor(() => expect(chamadas('registrar_diaria')).toEqual([{
      p_favorecido_id: 'r', p_data: '2026-09-16', p_jornada: 'inteiro', p_os_ids: ['o1'],
      p_observacao: 'Gerador do Marcelo', p_extras: 20, p_descontos: 0, p_valor_diaria: 160, p_origem: 'painel',
    }]));
  });

  it('grade: a célula mostra o dia e o pagamento; a ficha marca meio período sem mexer em OS nem extras', async () => {
    const user = userEvent.setup();
    renderizar('grade');
    expect(await screen.findByText('Setembro de 2026')).toBeInTheDocument();
    const celula = (await screen.findAllByRole('gridcell', { name: 'Roberto em qua 16/09' }))[0];
    expect(within(celula).getByText(/Dia R\$\s?180,00/)).toBeInTheDocument();
    expect(within(screen.getAllByRole('gridcell', { name: 'Roberto em ter 22/09' })[0]).getByText(/pago R\$\s?100,00/)).toBeInTheDocument();

    await user.click(celula);
    const ficha = await screen.findByRole('dialog');
    expect(within(ficha).getByText('Roberto · qua 16/09')).toBeInTheDocument();
    // a OS do dia com o número como o banco manda (nada de "OS OS-0042")
    expect(within(ficha).getByText(/^OS-0042/)).toBeInTheDocument();
    expect(within(ficha).queryByText(/OS OS-/)).not.toBeInTheDocument();
    expect(within(ficha).getByRole('button', { name: 'Dia inteiro' })).toHaveAttribute('aria-pressed', 'true');
    await user.click(within(ficha).getByRole('button', { name: 'Meio período' }));
    await waitFor(() => expect(chamadas('registrar_diaria')).toHaveLength(1));
    // Só a jornada: OS, extras, descontos, observação e diária ficam como o dia já tinha.
    expect(chamadas('registrar_diaria')[0]).toEqual({
      p_favorecido_id: 'r', p_data: '2026-09-16', p_jornada: 'meio', p_os_ids: null, p_observacao: null,
      p_extras: null, p_descontos: null, p_valor_diaria: null, p_origem: 'painel',
    });
  });

  it('a planilha do contador junta os dois freelancers do mês da grade, com CPF', async () => {
    const user = userEvent.setup();
    renderizar('grade');
    await screen.findByText('Setembro de 2026');
    await user.click(screen.getByRole('button', { name: /Planilha do contador/ }));
    await waitFor(() => expect(exportToCSV).toHaveBeenCalledTimes(1));
    const [linhas, arquivo] = exportToCSV.mock.calls[0] as [Array<Record<string, string>>, string];
    // A grade pede o mês inteiro às funções do banco, para cada freelancer.
    expect(chamadas('conta_corrente_freelancer')).toContainEqual({ p_favorecido_id: 'r', p_de: '2026-09-01', p_ate: '2026-09-30', p_atalho: null });
    expect(linhas.map((l) => `${l.data} ${l.tipo} ${l.freelancer}`)).toEqual([
      '16/09/2026 Diária Roberto', '22/09/2026 Pagamento Roberto',
    ]);
    expect(linhas[0].cpf).toBe('123.456.789-40');
    expect(arquivo).toMatch(/\.csv$/);
  });

  it('registrar dia (F4/F5): sem "Não trabalhou"; OS, extras e descontos atrás de "Mais detalhes"', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS-0042');
    await user.click(screen.getByRole('button', { name: /Registrar dia/ }));
    const dialogo = await screen.findByRole('dialog');
    expect(within(dialogo).queryByRole('button', { name: 'Não trabalhou' })).not.toBeInTheDocument();
    expect(within(dialogo).queryByLabelText('Extras (R$)')).not.toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: /Mais detalhes/ }));
    expect(within(dialogo).getByLabelText('Extras (R$)')).toBeInTheDocument();
    expect(within(dialogo).getByLabelText('Em qual OS (opcional)')).toBeInTheDocument();
  });

  it('vários dias: só os dias úteis que faltam; o já lançado fica como está', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS-0042');
    await user.click(screen.getByRole('button', { name: /Registrar dia/ }));
    const dialogo = await screen.findByRole('dialog');
    await user.click(within(dialogo).getByRole('button', { name: 'Vários dias' }));
    fireEvent.change(within(dialogo).getByLabelText('De'), { target: { value: '2026-09-14' } });
    fireEvent.change(within(dialogo).getByLabelText('Até'), { target: { value: '2026-09-20' } });
    // 14 a 20/09: dias úteis 14–18; o 16 já tem dia lançado → entram 14, 15, 17 e 18.
    const botao = await within(dialogo).findByRole('button', { name: 'Registrar 4 dias' });
    expect(within(dialogo).getByText(/1 já lançado fica como está/)).toBeInTheDocument();
    await user.click(botao);
    await waitFor(() => expect(chamadas('registrar_diaria').map((a) => a.p_data)).toEqual(['2026-09-14', '2026-09-15', '2026-09-17', '2026-09-18']));
    expect(chamadas('registrar_diaria')[0]).toMatchObject({ p_favorecido_id: 'r', p_jornada: 'inteiro', p_origem: 'painel' });
  });

  it('grade: falta não se lança (F5) — o dia vazio oferece só inteiro e meio; dia antes do início da conta corrente não abre', async () => {
    const user = userEvent.setup();
    renderizar('grade');
    const antes = (await screen.findAllByRole('gridcell', { name: 'Mickael em ter 01/09' }))[0];
    expect(antes).toBeDisabled();

    await user.click(screen.getAllByRole('gridcell', { name: 'Mickael em seg 14/09' })[0]);
    const ficha = await screen.findByRole('dialog');
    expect(within(ficha).getByText('Nada lançado neste dia.')).toBeInTheDocument();
    expect(within(ficha).queryByRole('button', { name: 'Não trabalhou' })).not.toBeInTheDocument();
    await user.click(within(ficha).getByRole('button', { name: 'Meio período' }));
    await waitFor(() => expect(chamadas('registrar_diaria')[0]).toMatchObject({ p_favorecido_id: 'm', p_data: '2026-09-14', p_jornada: 'meio' }));
  });

  // ── Períodos e Pix anotado (pedido do dono, 06/10/2026) ──

  it('"em aberto": o banco calcula o período de cada um; o cartão diz desde quando e o Pix anotado', async () => {
    renderizar('resumo', vi.fn(), { periodo: 'em_aberto' });
    expect(await screen.findByText(/período desde 23\/09/)).toBeInTheDocument();
    expect(screen.getByText(/lançado\(s\) à mão, aguardando o banco confirmar/)).toBeInTheDocument();
    expect(chamadas('resumo_freelancers')[0]).toEqual({ p_de: null, p_ate: null, p_atalho: 'em_aberto' });
  });

  it('extrato: o Pix lançado à mão aparece como "Anotado", já descontando', async () => {
    renderizar('extrato', vi.fn(), { periodo: 'em_aberto' });
    expect(await screen.findByText('Anotado')).toBeInTheDocument();
    expect(screen.getByText('Anotado — aguardando o banco')).toBeInTheDocument();
    expect(chamadas('conta_corrente_freelancer')).toContainEqual({ p_favorecido_id: 'r', p_de: null, p_ate: null, p_atalho: 'em_aberto' });
  });

  it('o Pix que já saiu do banco e espera a fila aparece como "Falta aprovar", à parte do anotado', async () => {
    renderizar('resumo', vi.fn(), { periodo: 'em_aberto' });
    expect(await screen.findByText(/em Pix que já saiu do banco para ele e falta aprovar na fila/)).toBeInTheDocument();
  });

  it('extrato: o Pix da fila tem selo próprio e não vira "Anotado"', async () => {
    renderizar('extrato', vi.fn(), { periodo: 'em_aberto' });
    expect(await screen.findByText('Falta aprovar')).toBeInTheDocument();
    expect(screen.getByText('No banco — falta aprovar na fila')).toBeInTheDocument();
    expect(screen.getByText('Anotado')).toBeInTheDocument();
  });

  it('"Escolher datas…": De/Até vão para o banco; datas invertidas não consultam', async () => {
    renderizar('extrato', vi.fn(), { periodo: 'personalizado', de: '2026-09-14', ate: '2026-09-27' });
    expect(await screen.findByLabelText('Data inicial')).toHaveValue('2026-09-14');
    await waitFor(() => expect(chamadas('conta_corrente_freelancer')).toContainEqual(
      { p_favorecido_id: 'r', p_de: '2026-09-14', p_ate: '2026-09-27', p_atalho: null }));
  });

  it('"Escolher datas…" com a inicial depois da final: avisa e não mostra período', async () => {
    renderizar('resumo', vi.fn(), { periodo: 'personalizado', de: '2026-09-27', ate: '2026-09-14' });
    expect(await screen.findByText('A data inicial é depois da final.')).toBeInTheDocument();
    expect(screen.getByText('Acerte as datas para ver o período.')).toBeInTheDocument();
  });

  /** O botão de registrar do diálogo, depois de conferir os reembolsos em aberto (a proposta do banco). */
  async function botaoDeRegistrar(dialogo: HTMLElement) {
    const botao = await within(dialogo).findByRole('button', { name: 'Registrar pagamento' });
    await waitFor(() => expect(botao).toBeEnabled());
    return botao;
  }

  it('registrar pagamento por Pix: uma função do banco (a do assistente), sem reembolso em aberto tudo em Diárias; bolso do sócio leva o sócio', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS-0042');
    await user.click(screen.getByRole('button', { name: /^Registrar pagamento$/ }));
    const dialogo = await screen.findByRole('dialog');
    fireEvent.change(within(dialogo).getByLabelText('Valor (R$)'), { target: { value: '10000' } });
    fireEvent.change(within(dialogo).getByLabelText('Data do pagamento'), { target: { value: '2026-09-30' } });
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(1));
    expect(chamadas('registrar_pagamento_do_freelancer')[0]).toEqual({
      p_favorecido_id: 'r', p_valor: 100, p_data: '2026-09-30', p_forma: 'pix', p_socio_id: null, p_reembolsos: [],
      p_descricao: 'Pagamento de diárias — Roberto',
    });
    // sem reembolso em aberto, o diálogo é o de antes (nenhum bloco de divisão)
    expect(within(dialogo).queryByText('Divisão deste pagamento')).not.toBeInTheDocument();
    expect(chamadas('anotar_transacao')).toEqual([]);

    await user.click(screen.getByRole('button', { name: /^Registrar pagamento$/ }));
    const outro = await screen.findByRole('dialog');
    fireEvent.change(within(outro).getByLabelText('Valor (R$)'), { target: { value: '5000' } });
    await user.click(within(outro).getByRole('radio', { name: /Do bolso de um sócio/ }));
    await user.click(await botaoDeRegistrar(outro));
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(2));
    expect(chamadas('registrar_pagamento_do_freelancer')[1]).toMatchObject({ p_forma: 'socio', p_socio_id: 's1', p_favorecido_id: 'r', p_valor: 50 });
  });

  // ── Acerto (pedido do dono, 06/10/2026) ──

  it('acerto: o bloco mostra o recibo e o "conferido"; o dia dentro do acerto fica travado', async () => {
    acertosNoBanco = [acertoDoRoberto];
    const user = userEvent.setup();
    renderizar('extrato');
    expect(await screen.findByText('nº 0001')).toBeInTheDocument();
    expect(screen.getByText(/Conferido/)).toBeInTheDocument();
    await user.click(await screen.findByRole('button', { name: /Mais ações para dia qua 16\/09/i }));
    const travado = await screen.findByRole('menuitem', { name: /Travado no acerto nº 0001/ });
    expect(travado).toHaveAttribute('aria-disabled', 'true');
    expect(screen.queryByRole('menuitem', { name: /Excluir o dia/ })).not.toBeInTheDocument();
  });

  it('emitir recibo: confere (simula) e só então fecha, no Pix que zera', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS-0042');
    await user.click(screen.getByRole('button', { name: /Emitir recibo/ }));
    const dialogo = await screen.findByRole('dialog');
    expect(await within(dialogo).findByText('Pix de 05/10')).toBeInTheDocument();
    expect(chamadas('fechar_acerto_diarias')[0]).toMatchObject({ p_favorecido_id: 'r', p_simular: true });
    await user.click(within(dialogo).getByRole('button', { name: /^Emitir recibo$/ }));
    await waitFor(() => expect(chamadas('fechar_acerto_diarias').some((a) => a.p_simular === false && a.p_pix_id === 'px')).toBe(true));
  });

  // ── Reembolso do técnico pelo comprovante (F2b, 11/10/2026) ──

  it('sem reembolso, a tela não fala de reembolso', async () => {
    renderizar('resumo');
    await screen.findByText('Roberto');
    expect(screen.queryByText(/^Reembolso/)).not.toBeInTheDocument();
  });

  it('resumo: o cartão da pessoa e o total do topo mostram o reembolso (rótulo inteiro), entre Trabalhado e Pago', async () => {
    comReembolso = true;
    renderizar('resumo');
    // O topo vem antes dos cartões das pessoas.
    const rotuloDoTopo = (await screen.findAllByText(ROTULO_REEMBOLSOS))[0];
    expect(rotuloDoTopo).toHaveAttribute('title', ROTULO_REEMBOLSOS);
    const cartaoDoTopo = rotuloDoTopo.parentElement!;
    expect(within(cartaoDoTopo).getByText(/R\$\s?62,00/)).toBeInTheDocument();

    const termos = screen.getAllByRole('term');
    const rotulos = termos.map((e) => e.textContent).filter((t) => t === 'Trabalhado' || t === ROTULO_REEMBOLSOS || t === 'Pago');
    // Só o Roberto tem reembolso: o cartão dele tem os três, na ordem; o do Mickael segue sem.
    expect(rotulos).toEqual(['Trabalhado', ROTULO_REEMBOLSOS, 'Pago', 'Trabalhado', 'Pago']);
    const reembolsoDoRoberto = termos.find((e) => e.textContent === ROTULO_REEMBOLSOS)!.closest('div')!;
    expect(within(reembolsoDoRoberto).getByText(/R\$\s?62,00/)).toBeInTheDocument();
    expect(screen.getByText(
      /Saldo = saldo inicial \+ dias trabalhados \(diária \+ extras − descontos\) \+ reembolso de despesas pagas pelo técnico \(com comprovante\) − o que ele recebeu\./,
    )).toBeInTheDocument();
    // o texto que confundia não volta (resposta 9 do dono)
    expect(screen.queryByText(/^Reembolsos/)).not.toBeInTheDocument();
  });

  it('extrato: a linha de reembolso mostra o CMP, a descrição, a categoria, a OS e + valor, sem menu de ações', async () => {
    comReembolso = true;
    renderizar('extrato');
    const codigo = await screen.findByText('CMP-00124');
    const linha = codigo.closest('[title]') as HTMLElement;
    expect(linha).toHaveAttribute('title', 'Para tirar, cancele o CMP-00124 pelo WhatsApp');
    // o selo com o rótulo inteiro; no celular corta com reticências (truncate), sem rolar de lado
    const selo = within(linha).getByText(ROTULO_REEMBOLSO);
    expect(selo).toHaveClass('truncate');
    expect(selo.parentElement).toHaveClass('min-w-0', 'max-w-full');
    // o código uma vez só (no selo e ao lado): a descrição vem sem o "Reembolso CMP-00124 · " do banco
    expect(within(linha).getByText('AutoZone · Peças e materiais')).toBeInTheDocument();
    expect(within(linha).queryByText(/Reembolso CMP-00124/)).not.toBeInTheDocument();
    // o número da OS já vem com o prefixo: nada de "OS OS-0042"
    expect(within(linha).getByText('OS-0042')).toBeInTheDocument();
    expect(within(linha).queryByText('OS OS-0042')).not.toBeInTheDocument();
    // como tirar, visível (o title não aparece no celular): o comando de verdade do WhatsApp
    expect(within(linha).getByText('Reembolso vem do comprovante: para tirar, mande "cancelar cmp 124 motivo" no WhatsApp.'))
      .toBeInTheDocument();
    expect(within(linha).getByText(/^\+ R\$\s?62,00$/)).toBeInTheDocument();
    expect(within(linha).queryAllByRole('button')).toHaveLength(0);
    // Só o dia tem "Mais ações" (o reembolso só sai cancelando o CMP; o pagamento vem do extrato e,
    // sem reembolso em aberto — este já foi pago, por exemplo —, não tem o que dividir).
    expect(screen.getAllByRole('button', { name: /Mais ações para/ })).toHaveLength(1);
    // O topo do extrato ganha o cartão do reembolso.
    const topo = screen.getAllByText(ROTULO_REEMBOLSOS)[0].parentElement!;
    expect(within(topo).getByText(/R\$\s?62,00/)).toBeInTheDocument();
  });

  // ── Pagamento dividido entre diárias e reembolso (resposta 4 do dono, 11/10/2026) ──

  it('extrato: com reembolso em aberto, o Pix das Diárias que veio do banco ganha "Dividir"; o banco recebe os marcados', async () => {
    comReembolso = true;
    reembolsoEmAberto = true;
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('CMP-00124');
    await user.click(await screen.findByRole('button', { name: /Mais ações para pagamento ter 22\/09/i }));
    await user.click(await screen.findByRole('menuitem', { name: /Dividir: diárias e reembolso/ }));
    const dialogo = await screen.findByRole('dialog');
    // a proposta do banco vem marcada: o CMP de R$ 62,00 cabe no Pix de R$ 100,00
    const caixa = await within(dialogo).findByRole('checkbox', { name: /CMP-00124/ });
    expect(caixa).toBeChecked();
    expect(within(dialogo).getByText(/AutoZone · Peças e materiais/)).toBeInTheDocument();
    const totais = within(dialogo).getByText(/^Diárias/).closest('p')!;
    expect(totais.textContent).toMatch(/Diárias R\$\s?38,00/);
    expect(totais.textContent).toMatch(/Reembolso de despesas pagas pelo técnico R\$\s?62,00/);
    expect(chamadas('proposta_de_divisao_do_pagamento')).toContainEqual({ p_favorecido_id: 'r', p_valor: 100 });

    await user.click(within(dialogo).getByRole('button', { name: 'Dividir' }));
    await waitFor(() => expect(chamadas('dividir_pagamento_do_freelancer')).toEqual([{ p_payable_id: 'p1', p_reembolsos: ['rb1'] }]));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  });

  it('dividir: desmarcar tudo não divide (o botão fica parado e diz por quê)', async () => {
    comReembolso = true;
    reembolsoEmAberto = true;
    const user = userEvent.setup();
    renderizar('extrato');
    await user.click(await screen.findByRole('button', { name: /Mais ações para pagamento ter 22\/09/i }));
    await user.click(await screen.findByRole('menuitem', { name: /Dividir: diárias e reembolso/ }));
    const dialogo = await screen.findByRole('dialog');
    await user.click(await within(dialogo).findByRole('checkbox', { name: /CMP-00124/ }));
    expect(within(dialogo).getByText('Marque ao menos um reembolso.')).toBeInTheDocument();
    expect(within(dialogo).getByRole('button', { name: 'Dividir' })).toBeDisabled();
    expect(chamadas('dividir_pagamento_do_freelancer')).toEqual([]);
  });

  it('extrato: o pagamento já dividido oferece desfazer (tudo volta para Diárias); o reembolso coberto diz quando foi pago', async () => {
    pagamentoJaDividido = true;
    const user = userEvent.setup();
    renderizar('extrato');
    expect(await screen.findByText('AutoZone · Peças e materiais · pago em 22/09')).toBeInTheDocument();
    expect(screen.getByText(/inclui reembolso de despesas pagas pelo técnico: R\$ 62,00/)).toBeInTheDocument();
    await user.click(await screen.findByRole('button', { name: /Mais ações para pagamento ter 22\/09/i }));
    expect(screen.queryByRole('menuitem', { name: /Dividir: diárias e reembolso/ })).not.toBeInTheDocument();
    await user.click(await screen.findByRole('menuitem', { name: /Desfazer a divisão/ }));
    // revisão dos ajustes: muda a categoria de lançamentos e devolve os reembolsos — pede confirmação antes
    const confirmar = await screen.findByRole('alertdialog');
    expect(within(confirmar).getByText('Desfazer a divisão?')).toBeInTheDocument();
    expect(within(confirmar).getByText('O pagamento volta inteiro para Diárias e os reembolsos voltam a ficar em aberto.')).toBeInTheDocument();
    expect(chamadas('dividir_pagamento_do_freelancer')).toEqual([]);
    await user.click(within(confirmar).getByRole('button', { name: 'Desfazer' }));
    await waitFor(() => expect(chamadas('dividir_pagamento_do_freelancer')).toEqual([{ p_payable_id: 'p1', p_reembolsos: [] }]));
  });

  it('o Pix anotado (aguardando o banco) não ganha "Dividir": a divisão dele nasce no "Registrar pagamento"', async () => {
    reembolsoEmAberto = true;
    renderizar('extrato', vi.fn(), { periodo: 'em_aberto' });
    expect(await screen.findByText('Anotado')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Mais ações para pagamento/ })).not.toBeInTheDocument();
    expect(chamadas('proposta_de_divisao_do_pagamento')).toEqual([]);
  });

  it('extrato: o reembolso dentro de um acerto fechado diz que está travado e como destravar', async () => {
    comReembolso = true;
    acertosNoBanco = [{ ...acertoDoRoberto, ate: '2026-09-20', reembolsos: 62 }];
    renderizar('extrato');
    const codigo = await screen.findByText('CMP-00124');
    const linha = codigo.closest('[title]') as HTMLElement;
    expect(await within(linha).findByText('Travado no acerto nº 0001 (reabra o acerto para cancelar o CMP-00124).')).toBeInTheDocument();
    expect(within(linha).queryByText(/para tirar, mande/)).not.toBeInTheDocument();
  });

  it('grade: o reembolso tem a marca dele na célula (não é "pago") e a linha do reembolso no rodapé, com o rótulo de todo lugar', async () => {
    comReembolso = true;
    renderizar('grade');
    await screen.findByText('Setembro de 2026');
    const celula = (await screen.findAllByRole('gridcell', { name: 'Roberto em sex 18/09' }))[0];
    expect(within(celula).getByText(/reemb\. R\$\s?62,00/)).toBeInTheDocument();
    expect(within(celula).getByText(/reemb\. R\$\s?62,00/)).toHaveAttribute('title', `${ROTULO_REEMBOLSO} CMP-00124`);
    expect(within(celula).queryByText(/pago/)).not.toBeInTheDocument();
    // resposta 9 do dono: o mesmo rótulo inequívoco (cortado no celular, inteiro no title)
    const rodape = screen.getAllByRole('rowheader', { name: ROTULO_REEMBOLSOS });
    expect(rodape.length).toBeGreaterThan(0);
    expect(rodape[0]).toHaveClass('truncate');
    expect(rodape[0]).toHaveAttribute('title', ROTULO_REEMBOLSOS);
    expect(screen.queryByRole('rowheader', { name: 'Reembolsos' })).not.toBeInTheDocument();
    expect(screen.getByText(/mais o reembolso de despesas pagas pelo técnico/)).toBeInTheDocument();

    // A ficha do dia mostra o reembolso só para ver: sem "Corrigir"/"Excluir" (sai cancelando o CMP).
    await userEvent.setup().click(celula);
    const ficha = await screen.findByRole('dialog');
    expect(within(ficha).queryByText('Nada lançado neste dia.')).not.toBeInTheDocument();
    expect(within(ficha).getByText(ROTULO_REEMBOLSO)).toBeInTheDocument();
    expect(within(ficha).getByText(/^\+ R\$\s?62,00$/)).toBeInTheDocument();
    // o código uma vez só, a descrição e a categoria; e como tirar, visível
    expect(within(ficha).getByText('CMP-00124 · AutoZone · Peças e materiais')).toBeInTheDocument();
    expect(await within(ficha).findByText('Reembolso vem do comprovante: para tirar, mande "cancelar cmp 124 motivo" no WhatsApp.'))
      .toBeInTheDocument();
    expect(within(ficha).queryByRole('button', { name: /Mais ações/ })).not.toBeInTheDocument();
  });

  it('a planilha do contador traz o reembolso com o código e a coluna do reembolso no fim, com o rótulo inequívoco', async () => {
    comReembolso = true;
    const user = userEvent.setup();
    renderizar('grade');
    await screen.findByText('Setembro de 2026');
    await user.click(screen.getByRole('button', { name: /Planilha do contador/ }));
    await waitFor(() => expect(exportToCSV).toHaveBeenCalledTimes(1));
    const [linhas, , colunas] = exportToCSV.mock.calls[0] as [Array<Record<string, string>>, string, Array<{ header: string }>];
    expect(linhas.map((l) => `${l.data} ${l.tipo}`)).toEqual([
      '16/09/2026 Diária', '18/09/2026 Reembolso de despesa paga pelo técnico', '22/09/2026 Pagamento',
    ]);
    expect(linhas[1]).toMatchObject({ conta: 'CMP-00124', reembolso: '62,00', pago: '' });
    expect(colunas.at(-1)?.header).toBe(ROTULO_REEMBOLSO);
  });

  // ── Novo freelancer (pedido do dono, 03/10/2026) ──

  function preencherCadastro(dialogo: HTMLElement, nome: string) {
    fireEvent.change(within(dialogo).getByLabelText('Nome'), { target: { value: nome } });
    fireEvent.change(within(dialogo).getByLabelText('Diária (R$)'), { target: { value: '15000' } });
    fireEvent.change(within(dialogo).getByLabelText('Primeiro dia de trabalho'), { target: { value: '2026-09-29' } });
    fireEvent.change(within(dialogo).getByLabelText('Chave Pix (opcional)'), { target: { value: 'joao@exemplo.com' } });
  }

  it('novo freelancer: confere primeiro (simula, nada gravado) e só então cadastra', async () => {
    const user = userEvent.setup();
    renderizar('resumo');
    await screen.findByText('Roberto');
    await user.click(screen.getByRole('button', { name: /Novo freelancer/ }));
    const dialogo = await screen.findByRole('dialog');
    preencherCadastro(dialogo, 'João Marcelo');
    await user.click(within(dialogo).getByRole('button', { name: 'Conferir' }));

    expect(await within(dialogo).findByText('Pix (e-mail): joao@exemplo.com')).toBeInTheDocument();
    expect(within(dialogo).getByText(/Sem CPF: os Pix para ele vão pedir a sua confirmação/)).toBeInTheDocument();
    expect(chamadas('cadastrar_freelancer')).toEqual([{
      p_nome: 'João Marcelo', p_valor_diaria: 150, p_desde: '2026-09-29', p_chave_pix: 'joao@exemplo.com',
      p_tipo_chave: null, p_documento: null, p_telefone: null, p_observacao: null, p_simular: true,
    }]);

    await user.click(within(dialogo).getByRole('button', { name: 'Cadastrar' }));
    await waitFor(() => expect(chamadas('cadastrar_freelancer')).toHaveLength(2));
    expect(chamadas('cadastrar_freelancer')[1]).toMatchObject({ p_nome: 'João Marcelo', p_simular: false });
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  });

  it('novo freelancer: a recusa do banco aparece na conferência e nada é gravado', async () => {
    const user = userEvent.setup();
    renderizar('resumo');
    await screen.findByText('Roberto');
    await user.click(screen.getByRole('button', { name: /Novo freelancer/ }));
    const dialogo = await screen.findByRole('dialog');
    preencherCadastro(dialogo, 'Roberto');
    await user.click(within(dialogo).getByRole('button', { name: 'Conferir' }));
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('Roberto já tem diária cadastrada');
    expect(within(dialogo).queryByRole('button', { name: 'Cadastrar' })).not.toBeInTheDocument();
    expect(chamadas('cadastrar_freelancer').every((a) => a.p_simular === true)).toBe(true);
  });
});
