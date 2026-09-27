// Smoke da tela de favorecidos.
//
// O que importa provar: os cinco tipos convivem e são filtráveis, e desativar NÃO apaga.
// Pagamentos antigos apontam para esta tabela — apagar um favorecido deixaria despesas
// órfãs no histórico, e o histórico é justamente o que não pode mudar depois.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import PayeesPage from './PayeesPage';
import type { Favorecido } from '@/hooks/use-payees';
import { totaisPorFavorecido } from '@/lib/favorecidos-no-ano';

const { favorecidos, salvarMock, totaisMock } = vi.hoisted(() => ({
  salvarMock: vi.fn(),
  totaisMock: vi.fn(),
  favorecidos: [
    {
      id: 'p1', name: 'Gustavo Seberino da Silva', kind: 'socio',
      document: '12345678901', phone: null, email: null,
      pix_key: 'gustavo@hbr.com.br', pix_key_type: 'email',
      bank_name: 'C6', bank_branch: '0001', bank_account: '12345-6', account_type: 'corrente',
      default_category: 'Pró-labore', commission_percentage: null,
      notes: null, active: true,
    },
    {
      id: 'p2', name: 'Felipe Vendas', kind: 'comissionado',
      document: '98765432100', phone: null, email: null,
      pix_key: null, pix_key_type: null, bank_name: null, bank_branch: null,
      bank_account: null, account_type: null, default_category: null,
      commission_percentage: 5, notes: null, active: true,
    },
    {
      id: 'p3', name: 'João Diarista', kind: 'diarista',
      document: null, phone: null, email: null,
      pix_key: null, pix_key_type: null, bank_name: null, bank_branch: null,
      bank_account: null, account_type: null, default_category: null,
      commission_percentage: null, notes: null, active: false,
    },
  ] as Favorecido[],
}));

vi.mock('@/hooks/use-payees', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-payees')>();
  return {
    ...real,
    usePayees: () => ({ data: favorecidos, isLoading: false }),
    useSalvarPayee: () => ({ mutate: salvarMock, isPending: false }),
    useTotaisDosFavorecidos: (ano: number) => totaisMock(ano),
  };
});

// O ano da tela é o de hoje; os dados do teste acompanham.
const ANO = new Date().getFullYear();
const pago = (payee_id: string, amount: number, expense_category: string) =>
  ({ payee_id, amount, paid_amount: amount, status: 'paid', expense_category });

beforeEach(() => {
  totaisMock.mockReset();
  totaisMock.mockImplementation((ano: number) => ({
    isError: false,
    data: totaisPorFavorecido(ano === ANO
      ? [pago('p1', 3000, 'Pró-labore'), pago('p1', 3000, 'Pró-labore'), pago('p1', 1500, 'Retirada de sócio'),
         { payee_id: 'p3', amount: 400, paid_amount: 0, status: 'pending', expense_category: 'Salários e encargos' }]
      : [pago('p1', 900, 'Pró-labore')]),
  }));
});

/** O texto do elemento com espaços comuns (o real vem com espaço não separável). */
const texto = (el: HTMLElement) => (el.textContent ?? '').replace(/ /g, ' ');

function renderPagina() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter><PayeesPage /></MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('PayeesPage', () => {
  it('lista favorecidos de todos os tipos, inclusive comissionado', async () => {
    renderPagina();
    expect(await screen.findByText('Gustavo Seberino da Silva')).toBeInTheDocument();
    expect(screen.getByText('Felipe Vendas')).toBeInTheDocument();
    expect(screen.getByText('Comissionado')).toBeInTheDocument();
  });

  it('mostra o percentual do comissionado', async () => {
    renderPagina();
    expect(await screen.findByText('5%')).toBeInTheDocument();
  });

  it('mostra os dados bancários sem exigir abrir o cadastro', async () => {
    // O motivo de a tabela existir: não ter que procurar chave Pix no banco a cada pagamento.
    renderPagina();
    expect(await screen.findByText('gustavo@hbr.com.br')).toBeInTheDocument();
    expect(screen.getByText(/C6 · 0001 · 12345-6/)).toBeInTheDocument();
    // CPF com máscara: dígitos crus não se conferem de olho.
    expect(screen.getByText('123.456.789-01')).toBeInTheDocument();
  });

  it('inativo continua visível, marcado como tal', async () => {
    renderPagina();
    expect(await screen.findByText('João Diarista')).toBeInTheDocument();
    expect(screen.getByText('Inativo')).toBeInTheDocument();
  });

  it('desativar não apaga — só marca inativo', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.click(await screen.findByLabelText(/Desativar Gustavo/i));
    expect(salvarMock).toHaveBeenCalledWith({ id: 'p1', active: false });
  });

  it('filtra por tipo', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.click(await screen.findByRole('tab', { name: /Comissionado \(1\)/ }));
    expect(screen.queryByText('Gustavo Seberino da Silva')).not.toBeInTheDocument();
    expect(screen.getByText('Felipe Vendas')).toBeInTheDocument();
  });

  it('mostra quanto cada um recebeu no ano, separado por categoria, e o que falta pagar', async () => {
    renderPagina();
    const gustavo = await screen.findByText(new RegExp(`Recebeu em ${ANO}:`));
    expect(texto(gustavo)).toBe(`Recebeu em ${ANO}: R$ 7.500,00 · 3 pagamentos`);
    expect(texto(screen.getByText(/^Pró-labore R\$/))).toBe('Pró-labore R$ 6.000,00 · Retirada de sócio R$ 1.500,00');
    // Quem não recebeu nada no ano diz isso, em vez de ficar em branco — e o que está a pagar.
    expect(screen.getByText(`Nada pago em ${ANO}.`)).toBeInTheDocument();
    expect(texto(screen.getByText(new RegExp(`^Nada pago em ${ANO} ·`)))).toBe(`Nada pago em ${ANO} · a pagar R$ 400,00`);
    // O total da lista em tela, com o que ainda está a pagar.
    expect(texto(screen.getByText(new RegExp(`Pago em ${ANO} a quem está nesta lista`))))
      .toBe(`Pago em ${ANO} a quem está nesta lista: R$ 7.500,00 (3 pagamentos) · a pagar R$ 400,00`);
  });

  it('o ano anterior troca os totais (o do informe de rendimentos)', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.click(await screen.findByRole('button', { name: String(ANO - 1) }));
    expect(totaisMock).toHaveBeenLastCalledWith(ANO - 1);
    expect(texto(await screen.findByText(new RegExp(`Recebeu em ${ANO - 1}:`)))).toBe(`Recebeu em ${ANO - 1}: R$ 900,00 · 1 pagamento`);
    expect(screen.getByText('Tudo em Pró-labore')).toBeInTheDocument();
  });

  it('a aba escolhida muda o total da lista', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.click(await screen.findByRole('tab', { name: /Comissionado \(1\)/ }));
    expect(texto(screen.getByText(new RegExp(`Pago em ${ANO} a quem está nesta lista`))))
      .toBe(`Pago em ${ANO} a quem está nesta lista: R$ 0,00 (0 pagamentos)`);
  });

  it('se a soma falhar, a tela continua e diz que os valores não aparecem', async () => {
    totaisMock.mockImplementation(() => ({ isError: true, data: undefined }));
    renderPagina();
    expect(await screen.findByText('Gustavo Seberino da Silva')).toBeInTheDocument();
    expect(screen.getByText(new RegExp(`Não consegui somar o que foi pago em ${ANO}`))).toBeInTheDocument();
    expect(screen.queryByText(/Recebeu em/)).not.toBeInTheDocument();
  });

  it('busca por nome, documento ou chave Pix', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.type(await screen.findByPlaceholderText(/Nome, CPF/i), 'gustavo@hbr');
    expect(screen.getByText('Gustavo Seberino da Silva')).toBeInTheDocument();
    expect(screen.queryByText('Felipe Vendas')).not.toBeInTheDocument();
  });
});
