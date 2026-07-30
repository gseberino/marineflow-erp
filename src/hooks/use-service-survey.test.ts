import { describe, it, expect } from 'vitest';
import { finalContingency, formatMinutes, type CaseEstimate } from './use-service-survey';

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
