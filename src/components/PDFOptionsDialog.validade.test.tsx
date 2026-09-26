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
// O Dialog do Radix desenha num portal em document.body; input type=date não tem papel ARIA.
const campoDeData = () => document.body.querySelector('input[type="date"]') as HTMLInputElement | null;

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

  // O onChange era `Number(x) || padrão`: -1 e 2.5 iam para o PDF como estavam, e 1e9
  // derrubava a geração. Agora passa pela mesma regra do PDF (primeiraValidade): o que não
  // serve volta ao número com que o diálogo abriu.
  it.each([
    ['-1', '7'],
    ['0', '7'],
    ['99999', '7'],
    ['2.5', '2'],
    ['30', '30'],
  ])('digitar %s no campo de dias deixa %s (e é o que vai ao PDF)', async (digitado, fica) => {
    const { onGenerate } = montar({ initialValidityDays: 7 });
    await waitFor(() => expect(campoDeDias().value).toBe('7'));
    fireEvent.change(campoDeDias(), { target: { value: digitado } });
    expect(campoDeDias().value).toBe(fica);
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(onGenerate.mock.calls[0][2]).toMatchObject({ mode: 'days', days: Number(fica) });
  });

  it('o campo de dias só aceita inteiro de 1 a 3650 (min, max e step)', async () => {
    montar({ initialValidityDays: 7 });
    await waitFor(() => expect(campoDeDias().value).toBe('7'));
    expect(campoDeDias().min).toBe('1');
    expect(campoDeDias().max).toBe('3650');
    expect(campoDeDias().step).toBe('1');
  });

  it('initialValidityDays inválido (-1) não chega ao campo: vale o padrão da empresa', async () => {
    linhasDeAjuste.push({ key: 'quote_validity_days', value: '3' });
    montar({ initialValidityDays: -1 });
    await waitFor(() => expect(campoDeDias().value).toBe('3'));
  });

  // A R19 avisa do vencimento pela data fixa (quote_validity_date); o diálogo abria em "Em
  // dias" e o PDF dizia "Válido por N dias" do mesmo orçamento.
  it('orçamento com data fixa abre em "Data específica" com a data, e o PDF sai com ela', async () => {
    const { onGenerate } = montar({ initialValidityDays: 7, initialValidityDate: '2026-10-10' });
    await waitFor(() => expect(campoDeData()?.value).toBe('2026-10-10'));
    expect((screen.getByRole('radio', { name: /Data específica/i }) as HTMLInputElement).checked).toBe(true);
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(onGenerate.mock.calls[0][2]).toMatchObject({ mode: 'date', date: '2026-10-10', days: 7 });
  });

  it('a data fixa que chega depois de aberto também alcança o diálogo', async () => {
    const { trocar } = montar({ initialValidityDays: undefined });
    await waitFor(() => expect(campoDeDias().value).toBe('15'));
    trocar({ initialValidityDays: 7, initialValidityDate: '2026-10-10' });
    await waitFor(() => expect(campoDeData()?.value).toBe('2026-10-10'));
  });

  it('data fixa que não existe (31/02) não vira "Data específica"', async () => {
    montar({ initialValidityDays: 7, initialValidityDate: '2026-02-31' });
    await waitFor(() => expect(campoDeDias().value).toBe('7'));
    expect((screen.getByRole('radio', { name: /Em dias/i }) as HTMLInputElement).checked).toBe(true);
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
