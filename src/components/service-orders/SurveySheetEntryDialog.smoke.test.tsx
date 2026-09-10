// Smoke do lançamento da folha de campo.
//
// A regra que mais importa: campo em branco no papel NÃO vira resposta vazia —
// vira "não deu para verificar". A diferença não é cosmética: pergunta sem
// resposta é informação (alguém não conseguiu ver, e isso vira contingência no
// preço); pergunta ausente é esquecimento, e some sem deixar rastro.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { SurveySheetEntryDialog } from './SurveySheetEntryDialog';

const { gravadas, atualizacoes } = vi.hoisted(() => ({
  gravadas: [] as any[],
  atualizacoes: [] as any[],
}));

vi.mock('@/hooks/use-service-survey', async (orig) => {
  const real = await orig<any>();
  return {
    ...real,
    useSurveyQuestions: () => ({
      data: [
        { id: 'q1', seq: 1, question: 'Qual a distância?', answer_type: 'medida',
          options: null, price_impact: 'alto', help_text: null, ask_remotely: false },
        { id: 'q2', seq: 2, question: 'Tem detector de gás?', answer_type: 'sim_nao',
          options: null, price_impact: 'baixo', help_text: null, ask_remotely: false },
      ],
      isLoading: false,
    }),
    useStartSurvey: () => ({ mutateAsync: async () => 'survey-1', isPending: false }),
  };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => ({
      // NOVO-lev-23: as respostas entram por UPSERT em (survey_id, seq) — retry
      // após falha parcial regrava as mesmas linhas em vez de duplicá-las.
      upsert: async (linhas: any, opts: any) => {
        gravadas.push({ tabela, linhas, onConflict: opts?.onConflict });
        return { error: null };
      },
      update: (patch: any) => ({
        eq: async () => { atualizacoes.push(patch); return { error: null }; },
      }),
    }),
  },
}));

function renderDialog() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <SurveySheetEntryDialog
          open onOpenChange={() => {}}
          serviceOrderId="os1" serviceId="sv1" orderNumber="ORÇ-00074"
        />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => { gravadas.length = 0; atualizacoes.length = 0; });

describe('lançar a folha preenchida', () => {
  it('mostra todas as perguntas de uma vez, não em fila', () => {
    renderDialog();
    expect(screen.getByText(/Qual a distância/)).toBeInTheDocument();
    expect(screen.getByText(/Tem detector de gás/)).toBeInTheDocument();
  });

  it('marca a que muda o preço', () => {
    renderDialog();
    expect(screen.getByText('muda o preço')).toBeInTheDocument();
  });

  // O ponto do diálogo inteiro.
  it('campo em branco vira "não verificado", não resposta vazia', async () => {
    renderDialog();

    const campos = screen.getAllByPlaceholderText('o que está escrito na folha');
    await userEvent.type(campos[0], '4,5 metros');
    // O segundo fica em branco de propósito.

    await userEvent.click(screen.getByRole('button', { name: /Sim, com ressalva/i }));
    await userEvent.type(
      screen.getByPlaceholderText(/o que já se sabe/i),
      'medi o percurso, não vi o quadro',
    );
    await userEvent.click(screen.getByRole('button', { name: /^Lançar folha$/i }));

    expect(gravadas).toHaveLength(1);
    expect(gravadas[0].onConflict).toBe('survey_id,seq'); // NOVO-lev-23
    const [respondida, embranco] = gravadas[0].linhas;
    expect(respondida.answer_value).toBe('4,5 metros');
    expect(respondida.skipped_reason).toBeNull();
    // NOVO-lev-22: grandeza transcrita com um número vira número estruturado —
    // é o que o dimensionamento lê, em vez de garimpar dígito na frase.
    expect(respondida.numeric_value).toBe(4.5);
    expect(embranco.answer_value).toBeNull();
    expect(embranco.skipped_reason).toBe('em branco na folha de campo');
    expect(embranco.numeric_value).toBeNull();
  });

  // Sem confiança declarada, o levantamento não fecha — é a mesma regra da tela.
  it('não lança sem confiança e justificativa', async () => {
    renderDialog();
    await userEvent.click(screen.getByRole('button', { name: /^Lançar folha$/i }));
    expect(gravadas).toHaveLength(0);
  });

  it('o "enquanto estava lá" entra junto da justificativa', async () => {
    renderDialog();
    await userEvent.type(
      screen.getByPlaceholderText(/copie do bloco da folha/i),
      'cliente pediu tomada extra',
    );
    await userEvent.click(screen.getByRole('button', { name: /Sim, com segurança/i }));
    await userEvent.type(screen.getByPlaceholderText(/o que já se sabe/i), 'tudo conferido');
    await userEvent.click(screen.getByRole('button', { name: /^Lançar folha$/i }));

    expect(atualizacoes[0].confidence).toBe('alta');
    expect(atualizacoes[0].confidence_rationale).toContain('tomada extra');
    // Fecha o levantamento: a folha é registro do que foi feito, não rascunho.
    expect(atualizacoes[0].status).toBe('closed');
  });
});
