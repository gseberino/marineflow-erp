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

  it('o relato entra embaixo das notas do técnico, com a data — nada se perde', () => {
    const { tecnico } = registroDaVia(
      { ...vazio, relato: 'Vazamento na conexão da bomba' },
      new Date(2026, 9, 1),
    );
    expect(tecnico).toBe('[Via lançada em 01/10/2026]\nO que encontrei / pendente / vigiar: Vazamento na conexão da bomba');
    expect(juntarNotas('Check-in do técnico.', tecnico)).toBe(`Check-in do técnico.\n\n${tecnico}`);
    expect(juntarNotas(null, tecnico)).toBe(tecnico);
  });

  it('material além do previsto vai para as notas internas, não para o documento do cliente', () => {
    // As notas do técnico saem impressas no documento da OS do cliente; margem não.
    const r = registroDaVia({ ...vazio, materialExtra: '2 abraçadeiras' }, new Date(2026, 9, 1));
    expect(r.tecnico).toBe('');
    expect(r.interno).toBe('[Via lançada em 01/10/2026]\nMaterial além do previsto: 2 abraçadeiras');
  });

  it('papel sem texto não cria registro vazio nas notas', () => {
    expect(registroDaVia({ ...vazio, relato: '   ' }, new Date())).toEqual({ tecnico: '', interno: '' });
    expect(juntarNotas('notas antigas', '')).toBe('notas antigas');
  });

  it('o botão Lançar só acende quando há algo para gravar', () => {
    expect(temAlgoParaLancar(vazio)).toBe(false);
    expect(temAlgoParaLancar({ ...vazio, chegada: '2026-10-01T08:30' })).toBe(true);
    expect(temAlgoParaLancar({ servicos: { a: { situacao: 'parcial' } } })).toBe(true);
  });
});
