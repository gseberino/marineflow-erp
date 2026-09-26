// Regra de ENTRADA — "o Pix do CPF/CNPJ X é do cliente Y" (resposta 18 do dono, 26/09/2026).
//
// O que precisa ficar provado: só por documento (11 ou 14 dígitos), com o cliente, com categoria
// de RECEITA, e sempre "só sugere" — a receita espera o OK do dono.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { EditorDeRegra, frasearRegra } from './FinanceRulesPanel';
import type { RegraFinanceira } from '@/hooks/use-finance-review';

const { salvarMock } = vi.hoisted(() => ({ salvarMock: vi.fn() }));

vi.mock('@/hooks/use-finance-review', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-finance-review')>()),
  useSalvarRegra: () => ({ mutate: salvarMock, isPending: false }),
}));

vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ data: [], isLoading: false }),
}));

// Honra o tipo, como o hook real: entrada oferece plano de RECEITA.
vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: (type?: 'payable' | 'receivable') => ({
    data: type === 'receivable'
      ? [{ name: 'Serviços prestados', dre_group: 'receita' }, { name: 'Sinal e adiantamento', dre_group: 'receita' }]
      : [{ name: 'Peças e materiais', dre_group: 'custo_direto' }],
    isLoading: false,
  }),
}));

vi.mock('@/hooks/use-payees', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-payees')>()),
  useClientesParaReceita: () => ({ data: [{ id: 'c-joao', name: 'João Silva' }, { id: 'c-ana', name: 'Ana Souza' }] }),
}));

function abrir(regra: Partial<RegraFinanceira> | null) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><EditorDeRegra aberto onFechar={() => {}} regra={regra} /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('regra de entrada no editor', () => {
  afterEach(() => salvarMock.mockClear());

  it('"Dinheiro que entra": documento, cliente e categoria de receita — e só sugere', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir(null);
    await user.click(screen.getByRole('button', { name: 'Dinheiro que entra' }));
    await user.type(screen.getByLabelText('CPF ou CNPJ de quem paga'), '123.456.789-01');

    const [cliente, categoria] = screen.getAllByRole('combobox');
    await user.click(cliente);
    await user.click(await screen.findByText('João Silva'));
    await user.click(categoria);
    // Plano de receita, não de despesa.
    expect(screen.queryByText('Peças e materiais')).not.toBeInTheDocument();
    await user.click(await screen.findByText('Serviços prestados'));

    // Não há como pedir "lançar sozinha" numa regra de entrada.
    expect(screen.queryByText(/Lançar sozinha/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({
      match_type: 'document', match_value: '12345678901', direction: 'credit',
      set_client_id: 'c-joao', set_category: 'Serviços prestados', set_dre_group: 'receita',
      set_supplier_id: null, autonomy: 'suggest',
    });
  });

  it('CPF/CNPJ com dígitos a menos não salva e diz por quê', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({ match_type: 'document', match_value: '', direction: 'credit', set_client_id: 'c-joao', set_category: 'Serviços prestados' });
    await user.type(screen.getByLabelText('CPF ou CNPJ de quem paga'), '1234567890');
    expect(screen.getByText(/CPF tem 11 dígitos e CNPJ, 14/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar regra' })).toBeDisabled();
  });

  it('a semente vinda de uma entrada da fila abre pronta', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({ match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: 'c-joao', set_category: 'Serviços prestados' });
    // Já é de entrada: o seletor de sentido é da regra nova, e ela já tem sentido.
    expect(screen.getByLabelText('CPF ou CNPJ de quem paga')).toHaveValue('12345678901');
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({ direction: 'credit', set_client_id: 'c-joao', autonomy: 'suggest' });
  });

  it('a frase da regra diz o documento e o cliente', () => {
    const r = {
      id: 'r', match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: 'c-joao',
      set_category: 'Serviços prestados',
    } as RegraFinanceira;
    expect(frasearRegra(r, undefined, 'João Silva')).toBe(
      'dinheiro que entra de quem tem o CPF/CNPJ 123.456.789-01 → cliente João Silva · Serviços prestados',
    );
  });
});
