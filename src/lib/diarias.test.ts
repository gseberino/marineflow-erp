import { describe, it, expect } from 'vitest';
import { diaCurto, intervaloDoPeriodo, rotuloDaJornada, valorDoDia } from './diarias';

describe('diárias — regras da tela', () => {
  it('o valor do dia é a mesma conta da coluna gerada no banco', () => {
    expect(valorDoDia('inteiro', 160)).toBe(160);
    expect(valorDoDia('meio', 160)).toBe(80);
    expect(valorDoDia('faltou', 160)).toBe(0);
    expect(valorDoDia('inteiro', 130, 20)).toBe(150);
    expect(valorDoDia('meio', 181, 12.5, 2)).toBe(101);
  });

  it('os atalhos de período cobrem o mês inteiro, inclusive a virada do ano', () => {
    expect(intervaloDoPeriodo('mes', '2026-09-28')).toEqual({ de: '2026-09-01', ate: '2026-09-30' });
    expect(intervaloDoPeriodo('mes_anterior', '2026-09-28')).toEqual({ de: '2026-08-01', ate: '2026-08-31' });
    expect(intervaloDoPeriodo('mes_anterior', '2027-01-10')).toEqual({ de: '2026-12-01', ate: '2026-12-31' });
    expect(intervaloDoPeriodo('mes', '2028-02-10')).toEqual({ de: '2028-02-01', ate: '2028-02-29' });
    expect(intervaloDoPeriodo('tudo', '2026-09-28')).toEqual({ de: null, ate: null });
  });

  it('o dia curto é o do calendário, não o de meia-noite em UTC', () => {
    expect(diaCurto('2026-09-24')).toBe('qui 24/09');
    expect(diaCurto('2026-09-07')).toBe('seg 07/09');
  });

  it('a jornada tem o nome da tela', () => {
    expect(rotuloDaJornada('inteiro')).toBe('Dia inteiro');
    expect(rotuloDaJornada('faltou')).toBe('Não trabalhou');
    expect(rotuloDaJornada(null)).toBe('—');
  });
});
