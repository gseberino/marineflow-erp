// Smoke da tela de favorecidos.
//
// O que importa provar: os cinco tipos convivem e são filtráveis, e desativar NÃO apaga.
// Pagamentos antigos apontam para esta tabela — apagar um favorecido deixaria despesas
// órfãs no histórico, e o histórico é justamente o que não pode mudar depois.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import PayeesPage from './PayeesPage';
import type { Favorecido } from '@/hooks/use-payees';

const { favorecidos, salvarMock } = vi.hoisted(() => ({
  salvarMock: vi.fn(),
  favorecidos: [
    {
      id: 'p1', name: 'Gustavo Seberino da Silva', kind: 'socio',
      document: '12345678901', phone: null, email: null,
      pix_key: 'gustavo@hbr.com.br', pix_key_type: 'email',
      bank_name: 'C6', bank_branch: '0001', bank_account: '12345-6', account_type: 'corrente',
      default_category: 'Pró-labore e retirada', commission_percentage: null,
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
  };
});

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

  it('busca por nome, documento ou chave Pix', async () => {
    const user = userEvent.setup();
    renderPagina();
    await user.type(await screen.findByPlaceholderText(/Nome, CPF/i), 'gustavo@hbr');
    expect(screen.getByText('Gustavo Seberino da Silva')).toBeInTheDocument();
    expect(screen.queryByText('Felipe Vendas')).not.toBeInTheDocument();
  });
});
