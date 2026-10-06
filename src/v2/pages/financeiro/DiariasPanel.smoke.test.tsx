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
const contaVazia = (id: string, nome: string, desde: string) => ({
  favorecido: { id, nome, desde, saldo_inicial: 0, diaria: 130 },
  de: null, ate: null, saldo_anterior: 0, dias: 0, trabalhado: 0, pago: 0, saldo_final: 0, estado: 'quitado', linhas: [],
});

beforeEach(() => {
  acertosNoBanco = [];
  toastFn.mockReset();
  exportToCSV.mockReset();
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => {
    switch (nome) {
      case 'resumo_freelancers':
        if (args.p_atalho === 'em_aberto') {
          return { data: { pessoas: [{ ...pessoas[0], de: '2026-09-23', ate: null, pago_aguardando_banco: 100 }],
            trabalhado: 160, pago: 100, dias: 1, deve: 60, adiantado: 0 }, error: null };
        }
        return { data: { pessoas, trabalhado: 2560, pago: 2130, dias: 16, deve: 450, adiantado: 20 }, error: null };
      case 'conta_corrente_freelancer':
        if (args.p_atalho === 'em_aberto') {
          return { data: { ...contaDoRoberto, de: '2026-09-23', ate: null, saldo_anterior: 0, pago: 100, pago_aguardando_banco: 100,
            linhas: [{ ...contaDoRoberto.linhas[1], id: 'a1', data: '2026-10-06', conta: 'Anotado — aguardando o banco',
              descricao: 'Adiantamento diarias', aguardando: true }] }, error: null };
        }
        return { data: args.p_favorecido_id === 'r' ? contaDoRoberto : contaVazia('m', 'Mickael', '2026-09-10'), error: null };
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
          ? { data: { favorecido: 'Roberto', de: '2026-09-17', ate: args.p_ate, saldo_anterior: 180, dias: 0, trabalhado: 0,
              pago_no_periodo: 100, valor_do_acerto: 80, pago_aguardando_banco: 0, resumo: '' }, error: null }
          : { data: { id: 'ac2', numero: 2, message: 'Acerto nº 0002 fechado.' }, error: null };
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
  it('um cartão por freelancer, com o saldo e se você deve ou adiantou', async () => {
    const user = userEvent.setup();
    const { onVerExtrato } = renderizar('resumo');
    expect(await screen.findByText('Roberto')).toBeInTheDocument();
    expect(screen.getByText('Mickael')).toBeInTheDocument();
    expect(screen.getAllByText('Você deve').length).toBeGreaterThan(0);
    expect(screen.getByText('Adiantado')).toBeInTheDocument();
    await user.click(screen.getAllByRole('button', { name: 'Ver extrato' })[0]);
    expect(onVerExtrato).toHaveBeenCalledWith('r');
  });

  it('o extrato mostra o dia com a OS e o pagamento com a conta de onde saiu', async () => {
    renderizar('extrato');
    expect(await screen.findByText('OS OS-0042')).toBeInTheDocument();
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

  it('vários dias: só os dias úteis que faltam; o já lançado fica como está', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS OS-0042');
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

  it('grade: "Não trabalhou" grava a falta; dia antes do início da conta corrente não abre', async () => {
    const user = userEvent.setup();
    renderizar('grade');
    const antes = (await screen.findAllByRole('gridcell', { name: 'Mickael em ter 01/09' }))[0];
    expect(antes).toBeDisabled();

    await user.click(screen.getAllByRole('gridcell', { name: 'Mickael em seg 14/09' })[0]);
    const ficha = await screen.findByRole('dialog');
    expect(within(ficha).getByText('Nada lançado neste dia.')).toBeInTheDocument();
    await user.click(within(ficha).getByRole('button', { name: 'Não trabalhou' }));
    await waitFor(() => expect(chamadas('registrar_diaria')[0]).toMatchObject({ p_favorecido_id: 'm', p_data: '2026-09-14', p_jornada: 'faltou' }));
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

  it('registrar pagamento por Pix: anota para o banco casar, na categoria das diárias; bolso do sócio leva o sócio', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS OS-0042');
    await user.click(screen.getByRole('button', { name: /^Registrar pagamento$/ }));
    const dialogo = await screen.findByRole('dialog');
    fireEvent.change(within(dialogo).getByLabelText('Valor (R$)'), { target: { value: '10000' } });
    fireEvent.change(within(dialogo).getByLabelText('Data do pagamento'), { target: { value: '2026-09-30' } });
    await user.click(within(dialogo).getByRole('button', { name: 'Registrar pagamento' }));
    await waitFor(() => expect(chamadas('anotar_transacao')).toHaveLength(1));
    expect(chamadas('anotar_transacao')[0]).toMatchObject({
      p_sentido: 'saida', p_valor: 100, p_data: '2026-09-30', p_favorecido_id: 'r', p_categoria: 'Diárias de freelancers',
      p_descricao: 'Pagamento de diárias — Roberto',
    });

    await user.click(screen.getByRole('button', { name: /^Registrar pagamento$/ }));
    const outro = await screen.findByRole('dialog');
    fireEvent.change(within(outro).getByLabelText('Valor (R$)'), { target: { value: '5000' } });
    await user.click(within(outro).getByRole('radio', { name: /Do bolso de um sócio/ }));
    await user.click(within(outro).getByRole('button', { name: 'Registrar pagamento' }));
    await waitFor(() => expect(chamadas('lancar_no_caixa')).toHaveLength(1));
    expect(chamadas('lancar_no_caixa')[0]).toMatchObject({ p_pago_por: 'socio', p_socio_id: 's1', p_favorecido_id: 'r', p_valor: 50 });
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

  it('fechar acerto: confere (simula) pela data e só então fecha', async () => {
    const user = userEvent.setup();
    renderizar('extrato');
    await screen.findByText('OS OS-0042');
    await user.click(screen.getByRole('button', { name: /Fechar acerto/ }));
    const dialogo = await screen.findByRole('dialog');
    expect(await within(dialogo).findByText('A pagar neste acerto')).toBeInTheDocument();
    expect(chamadas('fechar_acerto_diarias')[0]).toMatchObject({ p_favorecido_id: 'r', p_simular: true });
    await user.click(within(dialogo).getByRole('button', { name: 'Fechar acerto' }));
    await waitFor(() => expect(chamadas('fechar_acerto_diarias').some((a) => a.p_simular === false)).toBe(true));
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
