import { describe, it, expect } from 'vitest';
import {
  linhasParaGravar, registroDaVia, juntarNotas, temAlgoParaLancar, type LancamentoDaVia,
} from './lancar-via';

const vazio: LancamentoDaVia = { servicos: {} };

describe('Lançar a via — o papel vira dado', () => {
  it('só mexe na linha que recebeu situação; em branco fica como está', () => {
    const linhas = linhasParaGravar({
      servicos: {
        a: { situacao: 'feito', motivo: 'sobra de texto' },
        b: { situacao: 'nao_feito', motivo: ' faltou o filtro secador ' },
        c: { situacao: '' },
      },
    });
    expect(linhas).toEqual([
      // Feito não guarda motivo.
      { id: 'a', field_status: 'feito', field_status_note: null },
      { id: 'b', field_status: 'nao_feito', field_status_note: 'faltou o filtro secador' },
    ]);
  });

  it('o relato entra embaixo das notas que já existiam, com a data — nada se perde', () => {
    const registro = registroDaVia(
      { ...vazio, relato: 'Vazamento na conexão da bomba', materialExtra: '2 abraçadeiras' },
      new Date(2026, 9, 1),
    );
    expect(registro).toBe(
      '[Via lançada em 01/10/2026]\n'
      + 'O que encontrei / pendente / vigiar: Vazamento na conexão da bomba\n'
      + 'Material além do previsto: 2 abraçadeiras',
    );
    expect(juntarNotas('Check-in do técnico.', registro)).toBe(`Check-in do técnico.\n\n${registro}`);
    expect(juntarNotas(null, registro)).toBe(registro);
  });

  it('papel sem texto não cria registro vazio nas notas', () => {
    expect(registroDaVia({ ...vazio, relato: '   ' }, new Date())).toBe('');
    expect(juntarNotas('notas antigas', '')).toBe('notas antigas');
  });

  it('o botão Lançar só acende quando há algo para gravar', () => {
    expect(temAlgoParaLancar(vazio)).toBe(false);
    expect(temAlgoParaLancar({ ...vazio, chegada: '2026-10-01T08:30' })).toBe(true);
    expect(temAlgoParaLancar({ servicos: { a: { situacao: 'parcial' } } })).toBe(true);
  });
});
