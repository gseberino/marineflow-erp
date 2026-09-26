// A validade que o diálogo de Baixar/Imprimir mostra e entrega ao gerador.
//
// Duas coisas que só aparecem com o diálogo montado:
//
//  1. O padrão da empresa vinha de uma cópia própria (`Number(...) || 15`), que aceitava -1
//     e 2.5. Agora vem de validadeDoOrcamento, a mesma função do PDF e da R19.
//  2. As listas abrem o diálogo no clique, ANTES de os dados do orçamento chegarem: o
//     `initialValidityDays` nasce com o padrão da empresa e só depois vira a validade do
//     orçamento. O campo tem de acompanhar essa troca enquanto ninguém o editou — senão o
//     PDF sai com o padrão, que era o defeito das listas até 26/09/2026.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { PDFOptionsDialog } from './PDFOptionsDialog';

const { linhasDeAjuste } = vi.hoisted(() => ({
  linhasDeAjuste: [] as Array<{ key: string; value: string }>,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({ select: async () => ({ data: linhasDeAjuste, error: null }) }),
  },
}));

type Props = Parameters<typeof PDFOptionsDialog>[0];

function montar(props: Partial<Props> = {}) {
  const onGenerate = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const arvore = (p: Partial<Props>) => (
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <PDFOptionsDialog open onOpenChange={() => {}} documentType="quote" onGenerate={onGenerate} {...p} />
      </I18nProvider>
    </QueryClientProvider>
  );
  const r = render(arvore(props));
  return { onGenerate, trocar: (p: Partial<Props>) => r.rerender(arvore({ ...props, ...p })) };
}

const campoDeDias = () => screen.getByRole('spinbutton') as HTMLInputElement;

beforeEach(() => {
  linhasDeAjuste.length = 0;
});

describe('PDFOptionsDialog — validade do orçamento', () => {
  it('abre com o padrão da empresa (3) quando não há validade do orçamento', async () => {
    linhasDeAjuste.push({ key: 'quote_validity_days', value: '3' });
    montar();
    await waitFor(() => expect(campoDeDias().value).toBe('3'));
  });

  it('padrão da empresa fracionado (2.5) vira inteiro (2), como no PDF', async () => {
    linhasDeAjuste.push({ key: 'quote_validity_days', value: '2.5' });
    montar();
    await waitFor(() => expect(campoDeDias().value).toBe('2'));
  });

  it('padrão da empresa inválido (-1) não vira "Válido por -1 dias"', async () => {
    linhasDeAjuste.push({ key: 'quote_validity_days', value: '-1' });
    montar();
    // espera a configuração chegar (sem ela o campo também mostraria 15)
    await new Promise((r) => setTimeout(r, 50));
    expect(campoDeDias().value).toBe('15');
  });

  it('a validade do orçamento que chega depois de aberto alcança o campo e o PDF', async () => {
    linhasDeAjuste.push({ key: 'quote_validity_days', value: '3' });
    // como nas listas: abre sem os dados do orçamento, com o padrão da empresa
    const { onGenerate, trocar } = montar({ initialValidityDays: undefined });
    await waitFor(() => expect(campoDeDias().value).toBe('3'));
    // os dados chegam: o orçamento vale 7
    trocar({ initialValidityDays: 7 });
    await waitFor(() => expect(campoDeDias().value).toBe('7'));

    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(onGenerate).toHaveBeenCalledTimes(1);
    expect(onGenerate.mock.calls[0][2]).toMatchObject({ mode: 'days', days: 7 });
  });

  it('depois que o usuário digitou, a troca tardia não apaga o número dele', async () => {
    const { onGenerate, trocar } = montar({ initialValidityDays: 7 });
    await waitFor(() => expect(campoDeDias().value).toBe('7'));
    fireEvent.change(campoDeDias(), { target: { value: '10' } });
    trocar({ initialValidityDays: 9 });
    await new Promise((r) => setTimeout(r, 20));
    expect(campoDeDias().value).toBe('10');

    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(onGenerate.mock.calls[0][2]).toMatchObject({ mode: 'days', days: 10 });
  });
});
