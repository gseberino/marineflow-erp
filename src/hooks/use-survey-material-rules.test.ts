import { describe, it, expect } from 'vitest';
import { ruleInWords, type MaterialRule } from './use-survey-material-rules';

/**
 * A frase é o que se aprova. Ninguém confere nove campos de formulário para
 * decidir se uma regra de material está certa; todo mundo confere "2 m por
 * unidade medida, +15% de folga, de Cabo 35 mm²".
 */
const base: Pick<MaterialRule,
  'condition_type' | 'match_value' | 'min_value' | 'max_value'
  | 'qty_mode' | 'qty_fixed' | 'qty_factor' | 'qty_slack_pct'> = {
  condition_type: 'sempre', match_value: null, min_value: null, max_value: null,
  qty_mode: 'fixa', qty_fixed: 1, qty_factor: 1, qty_slack_pct: 0,
};

describe('a regra dita em voz alta', () => {
  it('descreve a regra do cabo com o fator e a folga', () => {
    expect(
      ruleInWords(
        { ...base, qty_mode: 'proporcional', qty_factor: 2, qty_slack_pct: 15 },
        'Cabo flexível 35 mm²', 'M',
      ),
    ).toBe('Sempre que respondida: 2 M por unidade medida, +15% de folga de Cabo flexível 35 mm²');
  });

  it('conta por item quando a pergunta é de quantidade', () => {
    expect(
      ruleInWords({ ...base, qty_mode: 'por_unidade', qty_factor: 1 }, 'Kit Mangueira', 'un'),
    ).toBe('Sempre que respondida: 1 un por item contado de Kit Mangueira');
  });

  it('sem folga não inventa "+0%"', () => {
    expect(ruleInWords({ ...base, qty_fixed: 2 }, 'Terminal', 'un'))
      .toBe('Sempre que respondida: 2 un de Terminal');
  });

  it.each([
    [{ condition_type: 'sim' as const }, 'Quando a resposta for sim'],
    [{ condition_type: 'nao' as const }, 'Quando a resposta for não'],
    [{ condition_type: 'igual' as const, match_value: 'bagageiro' }, 'Quando a resposta for "bagageiro"'],
    [{ condition_type: 'contem' as const, match_value: 'Victron' }, 'Quando a resposta citar "Victron"'],
    [{ condition_type: 'faixa' as const, min_value: 5, max_value: 15 }, 'De 5 a 15'],
    [{ condition_type: 'faixa' as const, min_value: 15, max_value: null }, 'Acima de 15'],
    [{ condition_type: 'faixa' as const, min_value: null, max_value: 5 }, 'Até 5'],
  ])('diz a condição %#', (patch, esperado) => {
    const frase = ruleInWords({ ...base, ...patch }, 'Produto', 'un');
    expect(frase.startsWith(esperado)).toBe(true);
  });

  // Produto sem unidade cadastrada não pode virar "2 undefined".
  it('produto sem unidade não escreve lixo', () => {
    expect(ruleInWords({ ...base, qty_fixed: 3 }, 'Peça', null))
      .toBe('Sempre que respondida: 3 de Peça');
  });
});
