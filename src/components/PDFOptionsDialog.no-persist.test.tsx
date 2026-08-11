// MF-AUD-014 — o diálogo de PDF não pode gravar configuração da empresa.
//
// O defeito que este teste guarda: até 10/08/2026, clicar em Baixar ou Imprimir gravava os
// checkboxes em `app_settings.pdf_options_<tipo>` — tabela GLOBAL, não preferência de
// usuário. Quem desmarcasse "termos e condições" para mandar um documento sem eles desligava
// os termos de toda a empresa, para sempre, inclusive nos PDFs que o cliente recebe por
// WhatsApp. Ninguém pediu isso e nada avisava.
//
// O teste mira o efeito observável (nenhuma escrita sai do componente), não a implementação:
// o supabase inteiro é espionado, então tanto faz por qual hook a escrita tentasse passar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { PDFOptionsDialog } from './PDFOptionsDialog';
import { DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';

const { upsert, insert, update, appSettingsRows } = vi.hoisted(() => ({
  upsert: vi.fn(async () => ({ error: null })),
  insert: vi.fn(async () => ({ error: null })),
  update: vi.fn(async () => ({ error: null })),
  appSettingsRows: [] as Array<{ key: string; value: string }>,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: async () => ({ data: appSettingsRows, error: null }),
      upsert,
      insert,
      update,
    }),
  },
}));

function renderDialog(props: Partial<Parameters<typeof PDFOptionsDialog>[0]> = {}) {
  const onGenerate = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <PDFOptionsDialog
          open
          onOpenChange={() => {}}
          documentType="quote"
          onGenerate={onGenerate}
          {...props}
        />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { onGenerate };
}

beforeEach(() => {
  upsert.mockClear();
  insert.mockClear();
  update.mockClear();
  appSettingsRows.length = 0;
  localStorage.clear();
});

describe('PDFOptionsDialog — não persiste preferência (MF-AUD-014)', () => {
  it('gerar o PDF não escreve nada no banco', async () => {
    const { onGenerate } = renderDialog();
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));

    expect(onGenerate).toHaveBeenCalledTimes(1);
    expect(upsert).not.toHaveBeenCalled();
    expect(insert).not.toHaveBeenCalled();
    expect(update).not.toHaveBeenCalled();
  });

  it('mexer nos checkboxes e gerar continua sem escrever nada — nem no localStorage', async () => {
    const { onGenerate } = renderDialog();

    const termos = await screen.findByLabelText(/termos e condições|terms and conditions/i);
    await userEvent.click(termos);
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));

    // a escolha vale para ESTE documento...
    expect(onGenerate.mock.calls[0][1]).toMatchObject({ showTerms: false });
    // ...e não sobrou em lugar nenhum
    expect(upsert).not.toHaveBeenCalled();
    expect(Object.keys(localStorage)).toHaveLength(0);
  });

  it('herda o padrão da empresa como estado inicial dos checkboxes', async () => {
    appSettingsRows.push({ key: 'pdf_options_quote', value: JSON.stringify({ showTerms: false, showCommission: true }) });
    const { onGenerate } = renderDialog();

    // o padrão gravado chega pela query e alcança os checkboxes mesmo com o diálogo já aberto
    const termos = await screen.findByLabelText(/termos e condições|terms and conditions/i);
    await waitFor(() => expect((termos as HTMLElement).getAttribute('data-state')).toBe('unchecked'));

    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(onGenerate.mock.calls[0][1]).toMatchObject({ showTerms: false, showCommission: true });
  });

  it('sem padrão gravado, usa o padrão de fábrica', async () => {
    const { onGenerate } = renderDialog();
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));

    const usadas = onGenerate.mock.calls[0][1];
    expect(usadas).toMatchObject({
      showTerms: DEFAULT_PDF_OPTIONS.showTerms,
      showServicePrices: DEFAULT_PDF_OPTIONS.showServicePrices,
      showCommission: DEFAULT_PDF_OPTIONS.showCommission,
    });
  });

  it('reabrir o diálogo esquece o que foi marcado da vez anterior', async () => {
    const primeira = renderDialog();
    const termos = await screen.findByLabelText(/termos e condições|terms and conditions/i);
    await userEvent.click(termos);
    await userEvent.click(screen.getByRole('button', { name: /imprimir|print/i }));
    expect(primeira.onGenerate.mock.calls[0][1]).toMatchObject({ showTerms: false });

    // segunda abertura, do zero: volta ao padrão — nada foi lembrado
    const segunda = renderDialog();
    const botoes = screen.getAllByRole('button', { name: /imprimir|print/i });
    await userEvent.click(botoes[botoes.length - 1]);
    expect(segunda.onGenerate.mock.calls[0][1]).toMatchObject({ showTerms: DEFAULT_PDF_OPTIONS.showTerms });
  });
});
