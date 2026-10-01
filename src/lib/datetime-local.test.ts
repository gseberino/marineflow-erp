import { describe, it, expect } from 'vitest';
import { isoParaInputLocal, inputLocalParaIso } from './datetime-local';

describe('campo datetime-local ↔ banco', () => {
  it('grava a hora digitada como hora local, não como UTC', () => {
    // 09:00 digitado no campo é 09:00 no relógio de quem digitou.
    const esperado = new Date(2026, 8, 28, 9, 0).toISOString();
    expect(inputLocalParaIso('2026-09-28T09:00')).toBe(esperado);
  });

  it('mostra no campo a hora local do instante gravado', () => {
    const instante = new Date(2026, 8, 28, 9, 0).toISOString();
    expect(isoParaInputLocal(instante)).toBe('2026-09-28T09:00');
  });

  it('ida e volta não desloca o horário (salvar sem mexer não muda nada)', () => {
    const digitado = '2026-10-01T15:30';
    expect(isoParaInputLocal(inputLocalParaIso(digitado))).toBe(digitado);
    const doBanco = '2026-10-01T18:30:00+00:00';
    expect(inputLocalParaIso(isoParaInputLocal(doBanco))).toBe(new Date(doBanco).toISOString());
  });

  it('vazio e lixo viram vazio, nunca uma data inventada', () => {
    expect(inputLocalParaIso('')).toBeNull();
    expect(inputLocalParaIso(null)).toBeNull();
    expect(inputLocalParaIso('não é data')).toBeNull();
    expect(isoParaInputLocal(null)).toBe('');
    expect(isoParaInputLocal('xx')).toBe('');
  });
});
