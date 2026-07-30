import { describe, it, expect } from 'vitest';
import {
  summarizeRoute, groupStepsByBlock, nextStep, formatMinutes, elapsedMinutesSince,
  accumulatedMinutes, isAiDraft,
  type ServiceOrderStep,
} from './use-service-steps';

function step(over: Partial<ServiceOrderStep> = {}): ServiceOrderStep {
  return {
    id: Math.random().toString(36).slice(2),
    service_order_id: 'os1',
    service_order_service_id: null,
    template_id: null,
    seq: 1,
    block: null,
    title: 'Passo',
    detail: null,
    kind: 'do',
    mode: 'do_confirm',
    standard_minutes: null,
    is_killer: false,
    requires_photo: false,
    requires_measure: null,
    measure_unit: null,
    measure_value: null,
    status: 'pending',
    na_reason: null,
    blocked_reason_code: null,
    blocked_note: null,
    assigned_user_id: null,
    started_at: null,
    completed_at: null,
    actual_minutes: null,
    origin: 'template',
    notes: null,
    ...over,
  };
}

describe('resumo do roteiro', () => {
  it('conta cada estado uma vez só', () => {
    const s = summarizeRoute([
      step({ status: 'done' }),
      step({ status: 'done' }),
      step({ status: 'blocked' }),
      step({ status: 'not_applicable' }),
      step({ status: 'pending' }),
    ]);
    expect(s).toMatchObject({ total: 5, done: 2, blocked: 1, notApplicable: 1, pending: 1 });
  });

  it('calcula a variação entre padrão e real', () => {
    const s = summarizeRoute([
      step({ status: 'done', standard_minutes: 60, actual_minutes: 90 }),
      step({ status: 'done', standard_minutes: 40, actual_minutes: 30 }),
    ]);
    expect(s.standardMinutes).toBe(100);
    expect(s.actualMinutes).toBe(120);
    expect(s.variancePct).toBe(20);
  });

  it('não inventa variação quando não há tempo padrão', () => {
    const s = summarizeRoute([step({ status: 'done', actual_minutes: 30 })]);
    expect(s.variancePct).toBeNull();
  });

  it('só considera concluído quando todo passo chegou a estado final', () => {
    expect(summarizeRoute([step({ status: 'done' }), step({ status: 'blocked' })]).finished).toBe(false);
    expect(summarizeRoute([step({ status: 'done' }), step({ status: 'not_applicable' })]).finished).toBe(true);
    // Roteiro vazio não é roteiro concluído
    expect(summarizeRoute([]).finished).toBe(false);
  });
});

describe('agrupamento por bloco', () => {
  it('mantém a ordem e não funde blocos separados de mesmo nome', () => {
    const groups = groupStepsByBlock([
      step({ block: 'Preparação', seq: 1 }),
      step({ block: 'Execução', seq: 2 }),
      step({ block: 'Preparação', seq: 3 }),
    ]);
    expect(groups.map((g) => g.block)).toEqual(['Preparação', 'Execução', 'Preparação']);
  });

  it('dá nome ao passo sem bloco em vez de deixar em branco', () => {
    expect(groupStepsByBlock([step({ block: null })])[0].block).toBe('Roteiro');
  });
});

describe('próximo passo', () => {
  it('prioriza o que já está em execução', () => {
    const running = step({ status: 'in_progress', title: 'Em execução' });
    const pending = step({ status: 'pending', title: 'Pendente' });
    expect(nextStep([pending, running])?.title).toBe('Em execução');
  });

  it('pula travados e não aplicáveis', () => {
    const found = nextStep([
      step({ status: 'blocked' }),
      step({ status: 'not_applicable' }),
      step({ status: 'pending', title: 'Alvo' }),
    ]);
    expect(found?.title).toBe('Alvo');
  });

  it('devolve indefinido quando não há o que fazer', () => {
    expect(nextStep([step({ status: 'done' })])).toBeUndefined();
  });
});

describe('formatação de tempo', () => {
  it.each([
    [null, '—'],
    [0, '0 min'],
    [45, '45 min'],
    [60, '1h'],
    [135, '2h15'],
    [65, '1h05'],
  ])('formata %s como %s', (input, expected) => {
    expect(formatMinutes(input as number | null)).toBe(expected);
  });
});

describe('tempo decorrido', () => {
  it('devolve zero sem início', () => {
    expect(elapsedMinutesSince(null)).toBe(0);
  });

  it('arredonda para o minuto mais próximo', () => {
    const started = new Date(Date.now() - 25 * 60 * 1000).toISOString();
    expect(elapsedMinutesSince(started)).toBe(25);
  });

  it('nunca devolve zero para passo já iniciado — zero mentiria na estatística', () => {
    expect(elapsedMinutesSince(new Date().toISOString())).toBe(1);
  });
});

describe('rascunho da IA (IA-1)', () => {
  it('passo da IA sem aprovação é sugestão', () => {
    expect(isAiDraft(step({ origin: 'ai', approved_at: null }))).toBe(true);
  });

  it('passo da IA aprovado deixa de ser sugestão e entra no roteiro', () => {
    expect(isAiDraft(step({ origin: 'ai', approved_at: new Date().toISOString() }))).toBe(false);
  });

  it('passo de template nunca é sugestão, mesmo sem approved_at', () => {
    // Só o que a IA escreveu precisa de assinatura; o catálogo já foi aprovado
    // quando o template foi criado.
    expect(isAiDraft(step({ origin: 'template', approved_at: null }))).toBe(false);
    expect(isAiDraft(step({ origin: 'manual', approved_at: null }))).toBe(false);
    expect(isAiDraft(step({ origin: 'client_request', approved_at: null }))).toBe(false);
  });

  it('sugestão não entra na contagem do roteiro', () => {
    const todos = [
      step({ origin: 'template', status: 'done' }),
      step({ origin: 'ai', approved_at: null, standard_minutes: 60 }),
    ];
    const soAprovados = todos.filter((s) => !isAiDraft(s));
    expect(summarizeRoute(soAprovados).total).toBe(1);
    expect(summarizeRoute(soAprovados).standardMinutes).toBe(0);
  });
});

describe('tempo acumulado com pausa', () => {
  it('soma o trecho em curso ao que já estava acumulado', () => {
    const started = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    expect(accumulatedMinutes(step({ actual_minutes: 30, started_at: started }))).toBe(40);
  });

  it('mantém o acumulado quando o passo está pausado (sem started_at)', () => {
    expect(accumulatedMinutes(step({ actual_minutes: 30, started_at: null }))).toBe(30);
  });

  it('não conta a hora parada: pausar e retomar depois não infla o total', () => {
    // Trabalhou 30 min, pausou, voltou 2h depois e está há 5 min no passo.
    const retomadoHa5min = new Date(Date.now() - 5 * 60 * 1000).toISOString();
    const total = accumulatedMinutes(step({ actual_minutes: 30, started_at: retomadoHa5min }));
    expect(total).toBe(35); // e não 155
  });

  it('devolve nulo para passo que nunca rodou', () => {
    expect(accumulatedMinutes(step({ actual_minutes: null, started_at: null }))).toBeNull();
  });
});
