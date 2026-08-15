import { describe, it, expect } from 'vitest';
import { checkMeasure, extractNumbers } from './survey-measure';

/**
 * O caso que originou tudo: a resposta da distância no ORÇ-00074 tinha DOIS
 * números, o motor leu o primeiro e dimensionou cabo para metade do percurso.
 */
describe('quantos números a resposta tem', () => {
  it('lê vírgula decimal como decimal', () => {
    expect(extractNumbers('2,5 metros')).toEqual([2.5]);
  });

  it('acha todos os números da frase', () => {
    expect(extractNumbers('2,5 até o inversor e 2 até o quadro')).toEqual([2.5, 2]);
  });

  it('texto sem número devolve lista vazia', () => {
    expect(extractNumbers('não consegui medir')).toEqual([]);
  });

  it('aguenta nulo e vazio', () => {
    expect(extractNumbers(null)).toEqual([]);
    expect(extractNumbers('')).toEqual([]);
  });
});

describe('conferência da grandeza', () => {
  const dist = { unit: 'm', min: 0.5, max: 60 };

  it('valor dentro da faixa passa sem aviso', () => {
    const r = checkMeasure('4,5', dist);
    expect(r.value).toBe(4.5);
    expect(r.warning).toBeNull();
  });

  // A regressão exata do ORÇ-00074.
  it('avisa quando há mais de um número, e diz qual vai usar', () => {
    const r = checkMeasure('2,5 até o inversor e 2 até o quadro', dist);
    expect(r.numberCount).toBe(2);
    expect(r.value).toBe(2.5);
    expect(r.warning).toContain('2 números');
    expect(r.warning).toContain('2.5');
  });

  // Não soma sozinho: podem ser alternativas, trechos, ou valor com tolerância.
  // Somar seria inventar uma interpretação que ninguém confirmou.
  it('NÃO soma os números por conta própria', () => {
    const r = checkMeasure('2,5 e 2', dist);
    expect(r.value).toBe(2.5);
    expect(r.value).not.toBe(4.5);
  });

  // O erro de digitação que mais custa: vírgula fora do lugar vira cabo de
  // quatro vezes o preço.
  it('avisa acima da faixa — a vírgula trocada', () => {
    const r = checkMeasure('25', { unit: 'm', min: 0.5, max: 20 });
    expect(r.warning).toContain('acima');
    expect(r.warning).toContain('vírgula');
  });

  it('avisa abaixo da faixa', () => {
    const r = checkMeasure('0,05', dist);
    expect(r.warning).toContain('abaixo');
  });

  // Avisar não é barrar: o valor sai mesmo com aviso, porque quem está no local
  // vê o que o cadastro não previu.
  it('mesmo fora da faixa, o valor é devolvido', () => {
    expect(checkMeasure('500', dist).value).toBe(500);
  });

  it('sem faixa cadastrada, só confere se há número', () => {
    expect(checkMeasure('123456', { unit: 'km' }).warning).toBeNull();
  });

  it('resposta sem número avisa, mas só se houver texto', () => {
    expect(checkMeasure('não deu para medir', dist).warning).toContain('Não encontrei');
    expect(checkMeasure('', dist).warning).toBeNull();
  });

  it('aceita número direto, sem texto no meio', () => {
    const r = checkMeasure(4.5, dist);
    expect(r.value).toBe(4.5);
    expect(r.numberCount).toBe(1);
  });

  // Temperatura negativa é leitura válida em refrigeração.
  it('não confunde negativo com erro', () => {
    const r = checkMeasure('-18', { unit: '°C', min: -30, max: 40 });
    expect(r.value).toBe(-18);
    expect(r.warning).toBeNull();
  });
});
