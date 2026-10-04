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
import { DiariasPanel } from './DiariasPanel';

const rpc = vi.fn();
const toastFn = vi.fn();
const exportToCSV = vi.fn();

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpc(...a),
    // Só a leitura do cadastro dos freelancers (CPF e PIX) que os documentos fazem.
    from: () => ({ select: () => ({ in: async () => ({ data: [
      { id: 'r', name: 'Roberto', document: '12345678940', pix_key: null },
      { id: 'm', name: 'Mickael', document: '98765432100', pix_key: null },
    ], error: null }) }) }),
  },
}));
vi.mock('@/lib/export-utils', () => ({ exportToCSV: (...a: unknown[]) => exportToCSV(...a) }));
vi.mock('sonner', () => ({
  toast: Object.assign((...a: unknown[]) => toastFn(...a), { success: vi.fn(), error: vi.fn() }),
}));
vi.mock('@/hooks/use-payees', () => ({ useServiceOrdersVinculaveis: () => ({ data: [] }) }));

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
  toastFn.mockReset();
  exportToCSV.mockReset();
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => {
    switch (nome) {
      case 'resumo_freelancers':
        return { data: { pessoas, trabalhado: 2560, pago: 2130, dias: 16, deve: 450, adiantado: 20 }, error: null };
      case 'conta_corrente_freelancer':
        return { data: args.p_favorecido_id === 'r' ? contaDoRoberto : contaVazia('m', 'Mickael', '2026-09-10'), error: null };
      case 'apagar_diaria':
        return { data: { message: 'Diária de Roberto em qua 16/09 apagada.', apagado: {
          favorecido_id: 'r', data: '2026-09-16', jornada: 'inteiro', valor_diaria: 160, extras: 20, descontos: 0,
          observacao: 'Gerador do Marcelo', os_ids: ['o1'] } }, error: null };
      case 'registrar_diaria':
        return { data: { acao: 'atualizado', diaria_id: 'd1', message: 'ok' }, error: null };
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

function renderizar(aba: 'resumo' | 'extrato' | 'grade', onVerExtrato = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <DiariasPanel aba={aba} filtro={{ periodo: 'tudo', favorecidoId: aba === 'extrato' ? 'r' : null, mes: '2026-09' }}
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
    expect(chamadas('conta_corrente_freelancer')).toContainEqual({ p_favorecido_id: 'r', p_de: '2026-09-01', p_ate: '2026-09-30' });
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
