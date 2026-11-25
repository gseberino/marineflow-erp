// Extrato por conta, com saldo, e o que foi lançado sozinho (Fase 3).
//
// O que se fixa: o saldo de abertura e de fechamento saem das próprias linhas (a mesma conta
// da conferência); cada linha diz o que virou; "lançados sozinhos" tem interruptor e
// desfazer — o que foi feito sem clique precisa ser visível e reversível.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ExtratoPorConta } from './ExtratoPorConta';

const { desfazerMock, salvarMock, estado, LANCADA_PELA_CONFIANCA } = vi.hoisted(() => {
  const LANCADA_PELA_CONFIANCA: Record<string, unknown> = {
    id: 'q1', title: 'Despesa: POSTO AGRICOPEL', suggested_amount: 180.5, suggested_category: 'Combustível e deslocamento',
    suggested_date: '2026-09-20', decided_at: '2026-09-21T09:00:00Z', decision_note: 'Lançada sozinha: confiança 90%',
    automatica: 'confianca', created_payable_id: 'p1', created_receivable_id: null, bank_transactions: { bank_connection_id: 'c6' },
  };
  return {
    desfazerMock: vi.fn(),
    salvarMock: vi.fn(),
    // 24/11/2026: a lista de lançados sozinhos varia por teste (o recebimento baixado pelo boleto entra em alguns).
    // `undefined` é a leitura que ainda não voltou ou que falhou (erro = true): o bloco não pode dizer "0" nem "nada".
    estado: { auto: 'on', sozinhos: [LANCADA_PELA_CONFIANCA] as Array<Record<string, unknown>> | undefined, erro: false },
    LANCADA_PELA_CONFIANCA,
  };
});

// Como a função do banco deixa a proposta depois da baixa (24/11/2026): título do banco, sem conta criada
// (created_receivable_id nulo de propósito) e a nota começando pelo cliente: "<cliente> — recebimento baixado sozinho pelo boleto: …".
const recebimentoBaixado = (id: string, conta: string, valor: number, vencimento: string): Record<string, unknown> => ({
  id, title: 'Receita: CREDITO DE BOLETO', suggested_amount: valor, suggested_category: 'Outras receitas',
  suggested_date: vencimento, decided_at: '2026-11-24T09:00:00Z',
  decision_note: `CLIENTE DE TESTE LTDA — recebimento baixado sozinho pelo boleto: NF-e 2/25 (parcela ${id}), vencimento ${vencimento.split('-').reverse().join('/')} (mesmo valor, crédito no dia do vencimento)`,
  automatica: 'boleto', created_payable_id: null, created_receivable_id: null, bank_transaction_id: `t-${id}`,
  conta_baixada_id: conta, conta_baixada_tipo: 'receivable', bank_transactions: { bank_connection_id: 'c6' },
});
const CONTA_BAIXADA: Record<string, unknown> = {
  id: 'q-boleto', title: 'Despesa: PAGAMENTO DE BOLETO', suggested_amount: 320, suggested_category: 'Fornecedores',
  suggested_date: '2026-11-17', decided_at: '2026-11-22T09:00:00Z',
  decision_note: 'Baixada sozinha pelo boleto: FORNECEDOR DE TESTE, vencimento 17/11/2026 — mesmo valor e mesmo banco do boleto',
  automatica: 'boleto', created_payable_id: null, created_receivable_id: null, bank_transaction_id: 't-pago',
  conta_baixada_id: 'conta-paga', conta_baixada_tipo: 'payable', bank_transactions: { bank_connection_id: 'c6' },
};
/** O cabeçalho do bloco, num texto só: o valor em reais vem com espaço duro do formatador. */
const cabecalho = () => (screen.getByRole('button', { name: /Lançados sozinhos/ }).textContent ?? '').replace(/\s+/g, ' ');
const itemDe = (texto: string | RegExp) => screen.getByText(texto).closest('li')!;

vi.mock('@/hooks/use-bank-connections', () => ({
  useBankConnections: () => ({ data: [{ id: 'c6', label: 'C6 - Conta PJ HBR' }] }),
}));
vi.mock('@/hooks/use-fechamento', () => ({
  useConferenciasDeSaldo: () => ({ data: [{ bank_connection_id: 'c6', fecha: true, diferenca: 0, saldo_do_provedor: 1386.61 }] }),
}));
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSetting: () => estado.auto,
  useUpdateAppSetting: () => ({ mutate: salvarMock, isPending: false }),
}));
vi.mock('@/hooks/use-lancamentos', () => ({
  useDesfazerAprovacao: () => ({ mutate: desfazerMock, isPending: false }),
}));
vi.mock('@/hooks/use-extrato-conta', () => ({
  useLancadosSozinhos: () => ({ data: estado.sozinhos, isError: estado.erro }),
  useExtratoDaConta: () => ({ isLoading: false, error: null, data: [
    // Mais recente primeiro, como a função devolve.
    { id: 't3', data: '2026-09-23', descricao: 'Pix enviado', contraparte: 'JOSE CARLOS ABEL', documento: null, tipo: 'debit', valor: -150,
      saldo_apos: 850, situacao: 'lancada', pendente: false, lancamento_tipo: 'payable', lancamento_id: 'p9', lancamento_descricao: 'x',
      categoria: 'Serviços de terceiros', quem: 'José Carlos', tipo_fora: null, motivo_fora: null, proposta_id: null },
    { id: 't2', data: '2026-09-10', descricao: 'Pix recebido', contraparte: 'MP MOTORHOMES', documento: '44051448000100', tipo: 'credit', valor: 500,
      saldo_apos: 1000, situacao: 'nova', pendente: false, lancamento_tipo: null, lancamento_id: null, lancamento_descricao: null,
      categoria: null, quem: null, tipo_fora: null, motivo_fora: null, proposta_id: 'q9' },
    { id: 't1', data: '2026-09-02', descricao: 'PGTO FAT CARTAO', contraparte: null, documento: null, tipo: 'debit', valor: -200,
      saldo_apos: 500, situacao: 'fora', pendente: false, lancamento_tipo: null, lancamento_id: null, lancamento_descricao: null,
      categoria: null, quem: null, tipo_fora: 'fatura_cartao', motivo_fora: 'Pagamento de fatura', proposta_id: null },
  ] }),
}));
vi.mock('@/components/FinanceReviewInbox', () => ({ FinanceReviewInbox: ({ contaId }: { contaId: string | null }) => <div>fila da conta {contaId ?? 'todas'}</div> }));
vi.mock('@/components/IgnoradasPanel', () => ({ IgnoradasPanel: ({ contaId }: { contaId: string | null }) => <div>fora da fila {contaId ?? 'todas'}</div> }));
// As fichas de saldo têm teste próprio; aqui só importa que escolher uma ficha escolhe a conta.
vi.mock('@/components/SaldosDasContas', () => ({
  SaldosDasContas: ({ onEscolher }: { onEscolher?: (id: string | null) => void }) => (
    <div><button type="button" onClick={() => onEscolher?.('c6')}>ficha C6</button><button type="button" onClick={() => onEscolher?.(null)}>ficha todas</button></div>
  ),
}));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => { desfazerMock.mockReset(); salvarMock.mockReset(); estado.auto = 'on'; estado.sozinhos = [LANCADA_PELA_CONFIANCA]; estado.erro = false; });

describe('ExtratoPorConta', () => {
  it('abre na fila de todas as contas; extrato com saldo pede uma conta, por escrito', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    expect(screen.getByText('fila da conta todas')).toBeInTheDocument();
    // Botão apagado não mostra dica: o motivo tem de estar escrito.
    await user.click(screen.getByRole('tab', { name: 'Extrato com saldo' }));
    expect(screen.getByText(/Escolha uma conta nas fichas acima/)).toBeInTheDocument();
  });

  it('a ficha escolhe a conta da fila', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: 'ficha C6' }));
    expect(screen.getByText('fila da conta c6')).toBeInTheDocument();
  });

  it('lançados sozinhos: interruptor e desfazer', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getByText('Despesa: POSTO AGRICOPEL')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Desfazer/ }));
    expect(desfazerMock.mock.calls[0][0]).toMatchObject({ tipo: 'payable', id: 'p1' });
    // Desligar pede confirmação: o primeiro clique não muda nada.
    await user.click(screen.getByRole('button', { name: 'Ligado — desligar' }));
    expect(salvarMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Sim, desligar' }));
    expect(salvarMock).toHaveBeenCalledWith({ key: 'finance_auto_approve', value: 'off' });
  });

  // 24/11/2026: a conta a RECEBER de NF-e com boleto passou a ser baixada pelo crédito do boleto. O que foi feito sem
  // clique tem de aparecer aqui e ter Desfazer do lado certo — e a entrada não pode inflar o total das saídas.
  it('só saídas: o cabeçalho continua "quantos · total", sem falar em recebimento', () => {
    estado.sozinhos = [LANCADA_PELA_CONFIANCA, CONTA_BAIXADA];
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: 2 · R$ 500,50');
    expect(cabecalho()).not.toMatch(/recebimento/);
  });

  it('recebimento baixado pelo boleto: aparece como entrada e o cabeçalho não soma a entrada com a saída', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [recebimentoBaixado('3/3', 'r1', 5238.02, '2026-11-13'), LANCADA_PELA_CONFIANCA];
    renderizar(<ExtratoPorConta />);
    // 180,50 de saída e 5.238,02 de entrada: nada de "2 · R$ 5.418,52".
    expect(cabecalho()).toContain('nos últimos 30 dias: 1 · R$ 180,50 · 1 recebimento baixado R$ 5.238,02');
    expect(cabecalho()).not.toContain('5.418,52');

    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    const item = itemDe('Receita: CREDITO DE BOLETO');
    expect(within(item).getByText(/CLIENTE DE TESTE LTDA — recebimento baixado sozinho pelo boleto/)).toBeInTheDocument();
    // A linha corta o texto: a nota inteira fica na dica.
    expect(within(item).getByTitle(/vencimento 13\/11\/2026 \(mesmo valor, crédito no dia do vencimento\)/)).toBeInTheDocument();
    expect((item.textContent ?? '').replace(/\s+/g, ' ')).toContain('+R$ 5.238,02');
    // A saída ao lado continua sem sinal.
    expect((itemDe('Despesa: POSTO AGRICOPEL').textContent ?? '').replace(/\s+/g, ' ')).not.toContain('+R$');
  });

  it('Desfazer do recebimento chama o tipo "receivable" com o id da conta a receber', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [recebimentoBaixado('3/3', 'r1', 5238.02, '2026-11-13'), LANCADA_PELA_CONFIANCA];
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    const item = itemDe('Receita: CREDITO DE BOLETO');
    // Um botão só: a baixa não cria conta, então não há o "Desfazer" de lançamento criado.
    expect(within(item).getAllByRole('button', { name: /Desfazer/ })).toHaveLength(1);
    await user.click(within(item).getByRole('button', { name: /Desfazer/ }));
    expect(desfazerMock).toHaveBeenCalledTimes(1);
    expect(desfazerMock.mock.calls[0][0]).toEqual({
      tipo: 'receivable', id: 'r1', motivo: 'Recebimento baixado pelo boleto — desfeito para revisão',
    });
  });

  it('Desfazer da conta a pagar baixada pelo boleto continua "payable", com o motivo de sempre', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [CONTA_BAIXADA, recebimentoBaixado('3/3', 'r1', 5238.02, '2026-11-13')];
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    const item = itemDe('Despesa: PAGAMENTO DE BOLETO');
    expect(within(item).getByText(/Baixada sozinha pelo boleto: FORNECEDOR DE TESTE/)).toBeInTheDocument();
    expect((item.textContent ?? '').replace(/\s+/g, ' ')).not.toContain('+R$');
    await user.click(within(item).getByRole('button', { name: /Desfazer/ }));
    expect(desfazerMock.mock.calls[0][0]).toEqual({
      tipo: 'payable', id: 'conta-paga', motivo: 'Baixada pelo boleto — desfeita para revisão',
    });
  });

  it('só recebimentos: o cabeçalho diz zero saídas e conta os recebimentos à parte', () => {
    estado.sozinhos = [recebimentoBaixado('2/3', 'r1', 5237.99, '2026-10-16'), recebimentoBaixado('3/3', 'r2', 5238.02, '2026-11-13')];
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: 0 · 2 recebimentos baixados R$ 10.476,01');
  });

  // 24/11/2026 (revisão): a segunda linha do recebimento pode ocupar até duas linhas — no celular a data na frente
  // escondia o cliente. A conta a pagar baixada e o lançado por confiança continuam numa linha só, como eram.
  it('recebimento: a nota pode ocupar duas linhas (com a data na frente); as saídas continuam numa linha só', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [recebimentoBaixado('3/3', 'r1', 5238.02, '2026-11-13'), CONTA_BAIXADA, LANCADA_PELA_CONFIANCA];
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    const nota = within(itemDe('Receita: CREDITO DE BOLETO')).getByText(/recebimento baixado sozinho pelo boleto/);
    expect(nota.className).toBe('line-clamp-2 break-words text-xs text-muted-foreground');
    expect((nota.textContent ?? '').replace(/\s+/g, ' ')).toMatch(/^13\/11\/2026 · CLIENTE DE TESTE LTDA — recebimento baixado/);
    const classeDasSaidas = 'block truncate text-xs text-muted-foreground';
    const notaDaContaPaga = within(itemDe('Despesa: PAGAMENTO DE BOLETO')).getByText(/Baixada sozinha pelo boleto/);
    expect(notaDaContaPaga.className).toBe(classeDasSaidas);
    expect(notaDaContaPaga).not.toHaveAttribute('title');
    expect(within(itemDe('Despesa: POSTO AGRICOPEL')).getByText(/Lançada sozinha: confiança 90%/).className).toBe(classeDasSaidas);
  });

  // 24/11/2026 (revisão): leitura que falha não pode virar "0" nem "Nada foi lançado sem clique" — é o bloco que
  // mostra o que foi feito sem clique, e afirmava "nada" justamente quando não tinha conseguido ler.
  it('leitura que falhou sem dado nenhum: diz que não leu, em vez de "0" e "Nada foi lançado"', async () => {
    const user = userEvent.setup();
    estado.sozinhos = undefined; estado.erro = true;
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: não consegui ler — recarregue a página');
    expect(cabecalho()).not.toMatch(/30 dias: 0/);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getByText(/Não consegui ler os lançados sozinhos — recarregue a página\. O que foi lançado ou baixado sem clique continua valendo\./)).toBeInTheDocument();
    expect(screen.queryByText('Nada foi lançado sem clique neste período.')).not.toBeInTheDocument();
  });

  it('enquanto a leitura não volta: "lendo…", não "0"', async () => {
    const user = userEvent.setup();
    estado.sozinhos = undefined;
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: lendo…');
    expect(cabecalho()).not.toMatch(/30 dias: 0/);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getByText('Lendo…')).toBeInTheDocument();
    expect(screen.queryByText('Nada foi lançado sem clique neste período.')).not.toBeInTheDocument();
  });

  // Releitura que falha depois de uma leitura boa: o react-query guarda a lista anterior. Ela continua na tela, com os
  // Desfazer — trocar a lista certa por um aviso esconderia o que dá para desfazer.
  it('releitura que falha com a lista boa em mãos: a lista e o Desfazer continuam', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [recebimentoBaixado('3/3', 'r1', 5238.02, '2026-11-13'), LANCADA_PELA_CONFIANCA]; estado.erro = true;
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: 1 · R$ 180,50 · 1 recebimento baixado R$ 5.238,02');
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getAllByRole('button', { name: /Desfazer/ })).toHaveLength(2);
    expect(screen.queryByText(/Não consegui ler/)).not.toBeInTheDocument();
  });

  it('leitura feita e lista vazia: aí sim "0" e "Nada foi lançado sem clique neste período."', async () => {
    const user = userEvent.setup();
    estado.sozinhos = [];
    renderizar(<ExtratoPorConta />);
    expect(cabecalho()).toContain('nos últimos 30 dias: 0');
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getByText('Nada foi lançado sem clique neste período.')).toBeInTheDocument();
  });

  it('a Ajuda explica a baixa do recebimento e o que o Desfazer faz', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: 'Como funciona o lançar sozinho' }));
    const frases = await screen.findAllByText(/a conta a receber de NF-e com boleto é baixada quando o banco mostra o\s+crédito do boleto no dia do vencimento, no mesmo valor/);
    expect(frases.length).toBeGreaterThan(0);
  });

  it('link antigo de "Fora da fila" abre essa visão', () => {
    renderizar(<ExtratoPorConta visaoInicial="fora" />);
    expect(screen.getByText('fora da fila todas')).toBeInTheDocument();
  });

  // 26/09/2026: na tela do Extrato as visões viraram abas da página. Com a visão escolhida
  // por fora, o seletor interno some — dois seletores para a mesma coisa seriam a duplicação
  // que a reorganização veio desfazer —, e a conta também pode vir de fora.
  it('com a visão e a conta controladas por fora, não mostra o seletor interno', async () => {
    const user = userEvent.setup();
    const escolher = vi.fn();
    const { rerender } = renderizar(<ExtratoPorConta visao="revisar" contaId={null} onEscolherConta={escolher} />);
    expect(screen.queryByRole('tablist', { name: 'Visão do extrato' })).not.toBeInTheDocument();
    expect(screen.getByText('fila da conta todas')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Anotar antes do banco/ })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'ficha C6' }));
    expect(escolher).toHaveBeenCalledWith('c6');

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    rerender(<QueryClientProvider client={qc}><I18nProvider><ExtratoPorConta visao="fora" contaId="c6" onEscolherConta={escolher} /></I18nProvider></QueryClientProvider>);
    expect(screen.getByText('fora da fila c6')).toBeInTheDocument();
    // "Anotar antes do banco" é da fila: nas outras visões não aparece.
    expect(screen.queryByRole('button', { name: /Anotar antes do banco/ })).not.toBeInTheDocument();
  });
});

describe('ExtratoComSaldo (dentro do Extrato por conta)', () => {
  it('mostra saldo de abertura e fechamento e o que cada linha virou', async () => {
    const { ExtratoComSaldo } = await import('./ExtratoComSaldo');
    renderizar(<ExtratoComSaldo conexaoId="c6" nomeDaConta="C6" />);
    // Abertura = saldo da linha mais antiga menos o valor dela: 500 − (−200) = 700.
    expect(screen.getByText('R$ 700,00')).toBeInTheDocument();
    expect(screen.getByText('R$ 850,00')).toBeInTheDocument();
    expect(screen.getByText(/Lançada:/)).toBeInTheDocument();
    expect(screen.getByText('Esperando decisão no Extrato')).toBeInTheDocument();
    expect(screen.getByText(/Fora da fila: Pagamento de fatura/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Lançadas (1)' })).toBeInTheDocument();
  });
});
