import { describe, it, expect } from 'vitest';
import {
  finalContingency, formatMinutes, howLongAgo, canReuseAnswer,
  type CaseEstimate, type PreviousAnswer, type SurveyQuestion,
} from './use-service-survey';

const comBase = (contingencia: number): CaseEstimate => ({
  tem_base: true, casos: 5, p50_min: 220, p80_min: 300, contingencia_pct: contingencia,
});

describe('contingência final (P18)', () => {
  // A contingência do histórico mede a dispersão dos casos. A confiança de quem
  // levantou é outra coisa: mede o que ficou sem resposta. As duas se somam.
  it('confiança alta não acrescenta nada à dispersão do histórico', () => {
    expect(finalContingency(comBase(12), 'alta')).toBe(12);
  });

  it('confiança média acrescenta 5 pontos', () => {
    expect(finalContingency(comBase(12), 'media')).toBe(17);
  });

  it('confiança baixa acrescenta 10 pontos', () => {
    expect(finalContingency(comBase(12), 'baixa')).toBe(22);
  });

  it('sem base histórica não inventa contingência', () => {
    expect(finalContingency({ tem_base: false, casos: 1 }, 'baixa')).toBeNull();
    expect(finalContingency(null, 'alta')).toBeNull();
    expect(finalContingency(undefined, 'media')).toBeNull();
  });

  it('trata contingência ausente como zero em vez de quebrar', () => {
    expect(finalContingency({ tem_base: true, casos: 3 }, 'media')).toBe(5);
  });
});

describe('idade da resposta anterior', () => {
  const diasAtras = (n: number) => new Date(Date.now() - n * 86400000).toISOString();

  it.each([
    [0, 'hoje'],
    [1, 'há 1 dia'],
    [12, 'há 12 dias'],
    [90, 'há 3 meses'],
    [45, 'há 1 mês'],
    [400, 'há 1 ano'],
    [800, 'há 2 anos'],
  ])('%s dias atrás vira "%s"', (dias, esperado) => {
    expect(howLongAgo(diasAtras(dias as number))).toBe(esperado);
  });

  // Sem data não dá para dizer se ainda vale. Melhor um rótulo vago do que uma
  // idade inventada — quem lê decide olhando.
  it('sem data não inventa idade', () => {
    expect(howLongAgo(null)).toBe('levantamento anterior');
    expect(howLongAgo(undefined)).toBe('levantamento anterior');
  });
});

describe('reaproveitar a resposta anterior', () => {
  const resp = (answer: string): PreviousAnswer => ({
    template_id: 't1', question: 'Onde fica o cilindro?', answer,
    answered_at: new Date().toISOString(), service_order_number: 'OS-00042',
  });
  const pergunta = (
    answer_type: SurveyQuestion['answer_type'], options: string[] | null = null,
  ) => ({ answer_type, options });

  it('texto livre sempre pode ser reaproveitado', () => {
    expect(canReuseAnswer(pergunta('texto'), resp('bagageiro traseiro'))).toBe(true);
    expect(canReuseAnswer(pergunta('medida'), resp('14 m'))).toBe(true);
  });

  it('escolha só reaproveita se a opção ainda existir', () => {
    const q = pergunta('escolha', ['bagageiro', 'externo']);
    expect(canReuseAnswer(q, resp('bagageiro'))).toBe(true);
    // A pergunta mudou de opções desde a última vez: o valor antigo não entraria
    // no Select, e o botão pareceria quebrado.
    expect(canReuseAnswer(q, resp('porta-malas'))).toBe(false);
  });

  it('sem pergunta ou sem resposta anterior não oferece atalho', () => {
    expect(canReuseAnswer(undefined, resp('x'))).toBe(false);
    expect(canReuseAnswer(pergunta('texto'), undefined)).toBe(false);
    expect(canReuseAnswer(pergunta('texto'), resp(''))).toBe(false);
  });
});

describe('formatação de tempo no levantamento', () => {
  it.each([
    [null, '—'],
    [45, '45 min'],
    [60, '1h'],
    [220, '3h40'],
    [300, '5h'],
  ])('formata %s como %s', (input, esperado) => {
    expect(formatMinutes(input as number | null)).toBe(esperado);
  });
});
