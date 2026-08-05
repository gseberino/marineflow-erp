// Smoke do levantamento — com foco no que o ativo já respondeu antes.
//
// A regra que mais importa: a resposta anterior é ATALHO, nunca preenchimento
// automático. O cilindro pode ter mudado de lugar entre um serviço e outro, e
// dar como certo o que ninguém olhou é pior que perguntar de novo. Por isso o
// campo continua vazio até alguém clicar, e a idade da informação aparece junto
// — resposta de dois anos merece desconfiança.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { SurveyPanel } from './SurveyPanel';

const { estado, gravadas, reaberturas } = vi.hoisted(() => ({
  estado: {
    perguntas: [] as any[],
    anteriores: {} as Record<string, any>,
    survey: { id: 's1', status: 'draft', service_survey_answers: [] } as any,
  },
  gravadas: [] as any[],
  reaberturas: [] as any[],
}));

const seisMesesAtras = new Date(Date.now() - 180 * 86400000).toISOString();

vi.mock('@/hooks/use-service-survey', async (orig) => {
  const real = await orig<any>();
  return {
    ...real,
    useSurveyTrigger: () => ({
      data: { precisa: true, motivos: ['serviço sem histórico'], casos_conhecidos: 0, dispersao_pct: null },
    }),
    useCaseEstimate: () => ({ data: { tem_base: false, casos: 0 } }),
    useSurveyQuestions: () => ({ data: estado.perguntas, isLoading: false }),
    // Levantamento já aberto: é aí que a pergunta aparece na tela.
    useServiceOrderSurvey: () => ({ data: estado.survey }),
    usePreviousAnswers: () => ({ data: estado.anteriores }),
    useStartSurvey: () => ({ mutate: () => {}, isPending: false }),
    useAnswerSurvey: () => ({
      mutate: (args: any, opts: any) => { gravadas.push(args); opts?.onSuccess?.(); },
      mutateAsync: async () => {},
      isPending: false,
    }),
    useCloseSurvey: () => ({ mutateAsync: async () => {}, isPending: false }),
    useReopenSurvey: () => ({
      mutate: (args: any, opts: any) => { reaberturas.push(args); opts?.onSuccess?.(); },
      isPending: false,
    }),
  };
});

vi.mock('./SuggestedMaterialsPanel', () => ({
  SuggestedMaterialsPanel: () => null,
}));

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <SurveyPanel serviceOrderId="os1" serviceId="sv1" clientId="c1" vesselId="v1" valorEstimado={5000} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const perguntaTexto = {
  id: 't1', seq: 1, question: 'Onde fica o cilindro de gás?',
  help_text: null, answer_type: 'texto', options: null,
  price_impact: 'alto', ask_remotely: false,
};

beforeEach(() => {
  estado.perguntas = [perguntaTexto];
  estado.anteriores = {};
  estado.survey = { id: 's1', status: 'draft', service_survey_answers: [] };
  gravadas.length = 0;
  reaberturas.length = 0;
});

/**
 * Levantamento fechado precisa continuar corrigível.
 *
 * O dono foi a um orçamento já preenchido e a tela não deixava mexer em nada —
 * mas o banco sempre permitiu: a trava era só de interface. Quem mede erra, e
 * obrigar a refazer nove perguntas por causa de um número é o caminho mais
 * curto para ninguém mais levantar nada.
 */
describe('levantamento fechado continua corrigível', () => {
  const fechado = {
    id: 's1', status: 'closed', confidence: 'alta',
    confidence_rationale: 'sei o acesso',
    service_survey_answers: [{
      seq: 1, template_id: 't1', question_snapshot: 'Qual a distância?',
      answer_value: '2,5 metros', skipped_reason: null, photo_path: null,
      answered_at: seisMesesAtras,
    }],
  };

  it('mostra o que foi levantado e oferece corrigir', () => {
    estado.survey = fechado;
    renderPanel();
    expect(screen.getByText('2,5 metros')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /corrigir/i })).toBeInTheDocument();
  });

  it('corrigir regrava a resposta MANTENDO o template_id', async () => {
    estado.survey = fechado;
    renderPanel();

    await userEvent.click(screen.getByRole('button', { name: /corrigir/i }));
    const campo = screen.getByDisplayValue('2,5 metros');
    await userEvent.clear(campo);
    await userEvent.type(campo, '4,5 metros');
    await userEvent.click(screen.getByRole('button', { name: /^salvar$/i }));

    expect(gravadas).toHaveLength(1);
    expect(gravadas[0].answer).toBe('4,5 metros');
    expect(gravadas[0].seq).toBe(1);
    // Sem o template_id a resposta perde o vínculo com a pergunta do catálogo:
    // some do histórico do ativo e para de disparar regra de material.
    expect(gravadas[0].templateId).toBe('t1');
  });

  it('reabrir devolve o levantamento sem apagar as respostas', async () => {
    estado.survey = fechado;
    renderPanel();

    await userEvent.click(screen.getByRole('button', { name: /reabrir para completar/i }));
    expect(reaberturas).toHaveLength(1);
    expect(reaberturas[0].surveyId).toBe('s1');
    expect(screen.getByText('2,5 metros')).toBeInTheDocument();
  });

  it('levantamento em andamento não oferece reabertura', () => {
    renderPanel();
    expect(screen.queryByRole('button', { name: /reabrir/i })).not.toBeInTheDocument();
  });
});

describe('memória do levantamento por ativo', () => {
  it('sem histórico do ativo, a pergunta aparece sozinha', () => {
    renderPanel();
    expect(screen.getByText('Onde fica o cilindro de gás?')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /continua igual/i })).not.toBeInTheDocument();
  });

  it('mostra a resposta anterior, de qual OS veio e há quanto tempo', () => {
    estado.anteriores = {
      t1: {
        template_id: 't1', question: 'Onde fica o cilindro de gás?',
        answer: 'bagageiro traseiro', answered_at: seisMesesAtras,
        service_order_number: 'OS-00042',
      },
    };
    renderPanel();
    expect(screen.getByText('bagageiro traseiro')).toBeInTheDocument();
    expect(screen.getByText(/há 6 meses/)).toBeInTheDocument();
    expect(screen.getByText(/OS-00042/)).toBeInTheDocument();
  });

  it('não preenche o campo sozinho: só depois do clique a resposta entra', async () => {
    estado.anteriores = {
      t1: {
        template_id: 't1', question: 'Onde fica o cilindro de gás?',
        answer: 'bagageiro traseiro', answered_at: seisMesesAtras, service_order_number: null,
      },
    };
    renderPanel();

    const campo = screen.getByPlaceholderText('resposta') as HTMLInputElement;
    expect(campo.value).toBe('');

    await userEvent.click(screen.getByRole('button', { name: /continua igual/i }));
    expect(campo.value).toBe('bagageiro traseiro');
  });

  // Se as opções da pergunta mudaram desde a última vez, a resposta antiga não
  // entra no Select — o botão viraria um clique sem efeito visível. O histórico
  // continua à mostra, porque ainda informa quem está no local.
  it('esconde o atalho quando a opção antiga não existe mais', () => {
    estado.perguntas = [{
      ...perguntaTexto, answer_type: 'escolha', options: ['bagageiro', 'externo'],
    }];
    estado.anteriores = {
      t1: {
        template_id: 't1', question: 'Onde fica o cilindro de gás?',
        answer: 'porta-malas', answered_at: seisMesesAtras, service_order_number: null,
      },
    };
    renderPanel();

    expect(screen.getByText('porta-malas')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /continua igual/i })).not.toBeInTheDocument();
  });
});
