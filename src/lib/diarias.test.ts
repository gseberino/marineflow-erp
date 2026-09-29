import { describe, it, expect } from 'vitest';
import {
  datasDoIntervalo, diaCurto, diasDoMes, ehFimDeSemana, intervaloDoMes, intervaloDoPeriodo, mesDe, nomeDoMes, rotuloDaJornada,
  somarMes, valorDoDia,
} from './diarias';

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

  it('a grade tem todos os dias do mês e anda de mês em mês, virando o ano', () => {
    expect(diasDoMes('2026-09')).toHaveLength(30);
    expect(diasDoMes('2028-02')).toHaveLength(29);
    expect(diasDoMes('2026-09')[0]).toBe('2026-09-01');
    expect(intervaloDoMes('2026-02')).toEqual({ de: '2026-02-01', ate: '2026-02-28' });
    expect(somarMes('2026-12', 1)).toBe('2027-01');
    expect(somarMes('2026-01', -1)).toBe('2025-12');
    expect(mesDe('2026-09-24')).toBe('2026-09');
    expect(nomeDoMes('2026-09')).toBe('Setembro de 2026');
  });

  it('vários dias: só dias úteis por padrão; sábado e domingo só se marcados', () => {
    // 19/09/2026 foi sábado.
    expect(datasDoIntervalo('2026-09-19', '2026-09-23')).toEqual(['2026-09-21', '2026-09-22', '2026-09-23']);
    expect(datasDoIntervalo('2026-09-19', '2026-09-21', { sabado: true })).toEqual(['2026-09-19', '2026-09-21']);
    expect(datasDoIntervalo('2026-09-19', '2026-09-21', { sabado: true, domingo: true })).toHaveLength(3);
    expect(datasDoIntervalo('2026-09-30', '2026-10-01')).toEqual(['2026-09-30', '2026-10-01']);
    expect(datasDoIntervalo('2026-09-25', '2026-09-21')).toEqual([]);
  });

  it('fim de semana é sábado e domingo do calendário', () => {
    expect(ehFimDeSemana('2026-09-26')).toBe(true);
    expect(ehFimDeSemana('2026-09-27')).toBe(true);
    expect(ehFimDeSemana('2026-09-28')).toBe(false);
  });

  it('a jornada tem o nome da tela', () => {
    expect(rotuloDaJornada('inteiro')).toBe('Dia inteiro');
    expect(rotuloDaJornada('faltou')).toBe('Não trabalhou');
    expect(rotuloDaJornada(null)).toBe('—');
  });
});
