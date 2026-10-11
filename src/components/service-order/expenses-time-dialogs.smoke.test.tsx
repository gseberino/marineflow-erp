// Despesas da OS: a que nasceu de um comprovante do WhatsApp (resposta 2 do dono, 11/10/2026) é custo
// interno — selo "CMP-00124 · custo interno" (não aparece para o cliente), sem editar nem excluir na
// tela: o caminho é cancelar o comprovante, que desfaz junto o que ele gravou. A despesa lançada à mão
// continua como sempre ("Interno" quando não é faturável; editar e excluir valem).
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ExpensesTimeDialogs } from './expenses-time-dialogs';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));
vi.mock('@/lib/arquivo-privado', () => ({
  useLinkDoArquivo: () => ({ url: null }),
  LinkDoArquivo: ({ children }: { children: unknown }) => children,
}));
vi.mock('@/components/CategoriaDespesaSelect', () => ({ CategoriaDespesaSelect: () => null }));

const despesa = (o: Record<string, unknown>) => ({
  id: 'e', expense_date: '2026-10-10', category: 'Combustível e deslocamento', description: 'Gasolina', amount: 62,
  paid_by: 'company', reimbursed: false, billable_to_client: true, receipt_url: null, suppliers: null, origem_codigo: null, ...o,
});

function renderizar() {
  const handleEditExpense = vi.fn();
  const removeExpense = { mutate: vi.fn() };
  const noop = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <ExpensesTimeDialogs
          isNew={false} orderId="os1"
          showExpensesDialog setShowExpensesDialog={noop} showTimeDialog={false} setShowTimeDialog={noop}
          showExpForm={false} setShowExpForm={noop} showTimeForm={false} setShowTimeForm={noop}
          expForm={{}} setExpForm={noop} timeForm={{}} setTimeForm={noop}
          editingExpenseId={null} resetExpForm={noop}
          handleAddExpense={noop} handleAddTime={noop} handleEditExpense={handleEditExpense}
          handleUploadReceipt={noop} handleRemoveReceipt={noop} uploadingReceipt={false} receiptInputRef={{ current: null }}
          soExpenses={[
            despesa({ id: 'cmp', description: 'Posto Shell', billable_to_client: false, origem_codigo: 'CMP-00124' }),
            despesa({ id: 'manual', description: 'Pedágio da ida', billable_to_client: false }),
            despesa({ id: 'cobrada', description: 'Frete da peça', billable_to_client: true }),
          ]}
          timeEntries={[]} suppliers={[]} appUsers={[]}
          addExpense={{ isPending: false }} addTime={{ isPending: false }} removeExpense={removeExpense}
          removeTime={{ mutate: noop }} updateExpense={{ isPending: false }}
          setQuickSupplierOpen={noop} setQuickSupplierName={noop}
        />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { handleEditExpense, removeExpense };
}

const linhaDe = (descricao: string) => screen.getByText(descricao).closest('tr') as HTMLElement;

describe('Despesas da OS com a despesa que nasceu de comprovante', () => {
  it('o selo diz o CMP e "custo interno", com o porquê: não aparece para o cliente', () => {
    renderizar();
    const linha = linhaDe('Posto Shell');
    const selo = within(linha).getByText('CMP-00124 · custo interno');
    expect(selo.closest('[title]')).toHaveAttribute('title', 'Não aparece para o cliente');
    // o selo do CMP fica no lugar do "Interno" (não os dois)
    expect(within(linha).queryByText('Interno')).not.toBeInTheDocument();
  });

  it('editar e excluir ficam travados, com o caminho escrito: cancelar o CMP pelo WhatsApp', async () => {
    const user = userEvent.setup();
    const { handleEditExpense, removeExpense } = renderizar();
    const linha = linhaDe('Posto Shell');
    const editar = within(linha).getByRole('button', { name: 'Editar esta despesa' });
    expect(editar).toBeDisabled();
    expect(editar.closest('[title]')).toHaveAttribute('title',
      'Nasceu do CMP-00124: para mudar, cancele o comprovante pelo WhatsApp ("cancelar cmp 124 motivo")');

    await user.click(within(linha).getByRole('button', { name: /Mais ações para despesa Posto Shell/ }));
    const item = await screen.findByRole('menuitem', { name: /Para excluir, cancele o CMP-00124 pelo WhatsApp/ });
    expect(item).toHaveAttribute('aria-disabled', 'true');
    expect(screen.queryByRole('menuitem', { name: 'Excluir esta despesa' })).not.toBeInTheDocument();
    await user.click(item);
    expect(removeExpense.mutate).not.toHaveBeenCalled();
    expect(handleEditExpense).not.toHaveBeenCalled();
  });

  it('a despesa lançada à mão continua como hoje: "Interno" quando não é faturável, editar e excluir valem', async () => {
    const user = userEvent.setup();
    const { handleEditExpense } = renderizar();
    const manual = linhaDe('Pedágio da ida');
    expect(within(manual).getByText('Interno')).toBeInTheDocument();
    expect(within(manual).queryByText(/custo interno/)).not.toBeInTheDocument();
    const editar = within(manual).getByRole('button', { name: 'Editar esta despesa' });
    expect(editar).toBeEnabled();
    await user.click(editar);
    expect(handleEditExpense).toHaveBeenCalledWith(expect.objectContaining({ id: 'manual' }));

    const cobrada = linhaDe('Frete da peça');
    expect(within(cobrada).queryByText('Interno')).not.toBeInTheDocument();
    expect(within(cobrada).getByRole('button', { name: 'Editar esta despesa' })).toBeEnabled();

    // (com o menu aberto o resto da tela fica escondido dos leitores de tela: por último)
    await user.click(within(manual).getByRole('button', { name: /Mais ações para despesa Pedágio da ida/ }));
    expect(await screen.findByRole('menuitem', { name: 'Excluir esta despesa' })).not.toHaveAttribute('aria-disabled');
  });
});
