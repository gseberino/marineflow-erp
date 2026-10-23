// Regra de ENTRADA — "o Pix do CPF/CNPJ X entra como <categoria>" (resposta 18 do dono, 26/09/2026).
//
// O que precisa ficar provado: só por documento (11 ou 14 dígitos), com categoria de RECEITA, e
// sempre "só sugere" — a receita espera o OK do dono. Desde a leva 8 (22/10/2026) a regra NOVA
// não diz o cliente (quem paga por um cliente se guarda em pagadores_do_cliente, com o SIM do
// administrador); a regra ANTIGA que já diz continua lida e não perde o cliente ao ser editada — menos se o
// CPF/CNPJ for trocado (o cliente era daquele documento: levá-lo junto seria um vínculo novo sem o SIM).
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
      ? [
          { name: 'Serviços prestados', dre_group: 'receita' }, { name: 'Sinal e adiantamento', dre_group: 'receita' },
          { name: 'Aporte de sócio', dre_group: 'nao_operacional' },
        ]
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

  it('"Dinheiro que entra": documento e categoria de receita, SEM cliente — e só sugere', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir(null);
    await user.click(screen.getByRole('button', { name: 'Dinheiro que entra' }));
    await user.type(screen.getByLabelText('CPF ou CNPJ de quem paga'), '123.456.789-01');

    // Um seletor só: a categoria. O campo "É do cliente" saiu (leva 8).
    const combos = screen.getAllByRole('combobox');
    expect(combos).toHaveLength(1);
    expect(screen.queryByText('É do cliente')).not.toBeInTheDocument();
    await user.click(combos[0]);
    // Plano de receita, não de despesa.
    expect(screen.queryByText('Peças e materiais')).not.toBeInTheDocument();
    await user.click(await screen.findByText('Serviços prestados'));
    // E diz onde se guarda quem paga por um cliente.
    expect(screen.getByText(/se guarda em "Quem paga pelos clientes"/)).toBeInTheDocument();

    // Não há como pedir "lançar sozinha" numa regra de entrada.
    expect(screen.queryByText(/Lançar sozinha/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({
      match_type: 'document', match_value: '12345678901', direction: 'credit',
      set_client_id: null, set_category: 'Serviços prestados', set_dre_group: 'receita',
      set_supplier_id: null, autonomy: 'suggest',
    });
  });

  it('CPF/CNPJ com dígitos a menos não salva e diz por quê', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({ match_type: 'document', match_value: '', direction: 'credit', set_client_id: null, set_category: 'Serviços prestados' });
    await user.type(screen.getByLabelText('CPF ou CNPJ de quem paga'), '1234567890');
    expect(screen.getByText(/CPF tem 11 dígitos e CNPJ, 14/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar regra' })).toBeDisabled();
  });

  it('a semente vinda de uma entrada da fila abre pronta — e nunca nasce com cliente', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    // Mesmo que alguém mande cliente numa semente (regra nova, sem id), ela não sai com ele.
    abrir({ match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: 'c-joao', set_category: 'Serviços prestados' });
    // Já é de entrada: o seletor de sentido é da regra nova, e ela já tem sentido.
    expect(screen.getByLabelText('CPF ou CNPJ de quem paga')).toHaveValue('12345678901');
    expect(screen.queryByTestId('regra-antiga-com-cliente')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({ direction: 'credit', set_client_id: null, autonomy: 'suggest' });
  });

  it('regra ANTIGA que já diz o cliente: mostra quem é, sem seletor, e editar não apaga o cliente', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({
      id: 'r-antiga', match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: 'c-joao',
      set_category: 'Serviços prestados', origin: 'user',
    });
    const aviso = screen.getByTestId('regra-antiga-com-cliente');
    expect(aviso).toHaveTextContent(/é do cliente João Silva, e continua valendo como está/);
    expect(screen.getAllByRole('combobox')).toHaveLength(1);
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({
      id: 'r-antiga', direction: 'credit', set_client_id: 'c-joao', set_category: 'Serviços prestados', autonomy: 'suggest',
    });
  });

  it('regra ANTIGA com cliente e CPF/CNPJ trocado: o cliente sai da regra, com aviso para guardar o pagador', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({
      id: 'r-equit', match_type: 'document', match_value: '04754513000149', direction: 'credit', set_client_id: 'c-joao',
      set_category: 'Serviços prestados', origin: 'user',
    });
    const campo = screen.getByLabelText('CPF ou CNPJ de quem paga');
    await user.clear(campo);
    await user.type(campo, '11.222.333/0001-81');
    const aviso = screen.getByTestId('regra-antiga-com-cliente');
    expect(aviso).toHaveTextContent(/dizia que o dinheiro do CPF\/CNPJ 04\.754\.513\/0001-49 é do cliente João Silva/);
    expect(aviso).toHaveTextContent(/Com outro CPF\/CNPJ, ela deixa de dizer o cliente/);
    expect(aviso).toHaveTextContent(/guarde o pagador em "Quem paga pelos clientes"/);
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({
      id: 'r-equit', match_value: '11222333000181', direction: 'credit', set_client_id: null,
      set_category: 'Serviços prestados', autonomy: 'suggest',
    });
  });

  it('regra ANTIGA: voltar ao mesmo CPF/CNPJ (digitado com pontuação) mantém o cliente', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({
      id: 'r-equit', match_type: 'document', match_value: '04754513000149', direction: 'credit', set_client_id: 'c-joao',
      set_category: 'Serviços prestados',
    });
    const campo = screen.getByLabelText('CPF ou CNPJ de quem paga');
    await user.clear(campo);
    await user.type(campo, '04.754.513/0001-49');
    expect(screen.getByTestId('regra-antiga-com-cliente')).toHaveTextContent(/continua valendo como está/);
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({ match_value: '04754513000149', set_client_id: 'c-joao' });
  });

  it('aporte de sócio não tem cliente: salva sem ele — e a regra antiga que virou aporte perde o cliente', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    abrir({
      id: 'r-velha', match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: 'c-joao',
      set_category: 'Serviços prestados',
    });
    await user.click(screen.getAllByRole('combobox')[0]);
    await user.click(await screen.findByText('Aporte de sócio'));
    expect(screen.getByTestId('regra-antiga-com-cliente')).toHaveTextContent(/Como Aporte de sócio não é receita, ela deixa de dizer/);
    await user.click(screen.getByRole('button', { name: 'Salvar regra' }));
    expect(salvarMock.mock.calls[0][0]).toMatchObject({
      direction: 'credit', set_client_id: null, set_category: 'Aporte de sócio', autonomy: 'suggest',
    });
  });

  it('a frase da regra de aporte diz o documento, sem cliente', () => {
    const r = {
      id: 'r', match_type: 'document', match_value: '12345678901', direction: 'credit', set_client_id: null,
      set_category: 'Aporte de sócio',
    } as RegraFinanceira;
    expect(frasearRegra(r)).toBe('dinheiro que entra de quem tem o CPF/CNPJ 123.456.789-01 → Aporte de sócio');
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
