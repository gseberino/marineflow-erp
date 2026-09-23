// Como as datas são exibidas. Dois casos que o sistema confundia num só.
//
// 1. INSTANTE (tem hora e zona): a autorização de uma NF-e, um registro de webhook. Vale o
//    fuso da EMPRESA, não o do aparelho de quem abre — senão o mesmo fato aparece com
//    datas diferentes conforme o dispositivo. Caso real: a NFS-e 1/4 foi emitida 27/08/2026
//    às 22h22, é gravada como "2026-08-28T01:22Z", e em UTC a tela dizia 28/08 contra o
//    27/08 do XML.
//
// 2. DIA DO CALENDÁRIO (sem hora): um vencimento. O banco devolve "2026-09-18" e o
//    JavaScript lê como meia-noite UTC — todo fuso a oeste de Greenwich, o Brasil inteiro,
//    exibe o dia ANTERIOR. Era o "um dia a menos" nas parcelas: o DANFE da NF-e 2/25 traz
//    a primeira duplicata em 18/09/2026 e a tela mostrava 17/09. Converter de fuso um dia
//    do calendário é o que o movia.
//
// Roda com o processo em UTC de propósito: é assim que o CI roda, e é o cenário mais
// agressivo para os dois casos.
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { renderHook } from '@testing-library/react';
import { I18nProvider, useI18n } from './index';

const tzOriginal = process.env.TZ;

function formatar() {
  const { result } = renderHook(() => useI18n(), {
    wrapper: ({ children }) => <I18nProvider>{children}</I18nProvider>,
  });
  return result.current;
}

describe('datas exibidas', () => {
  beforeAll(() => { process.env.TZ = 'UTC'; });
  afterAll(() => { process.env.TZ = tzOriginal; });

  describe('vencimento é um DIA, não um instante', () => {
    it('as três duplicatas da NF-e 2/25 batem com o DANFE', () => {
      const { formatDate } = formatar();
      // Exatamente o que está impresso no DANFE, na ordem.
      expect(formatDate('2026-09-18')).toBe('18/09/2026');
      expect(formatDate('2026-10-16')).toBe('16/10/2026');
      expect(formatDate('2026-11-13')).toBe('13/11/2026');
    });

    it('primeiro dia do mês não escorrega para o mês anterior', () => {
      expect(formatar().formatDate('2026-01-01')).toBe('01/01/2026');
    });

    it('29 de fevereiro de ano bissexto continua existindo', () => {
      expect(formatar().formatDate('2028-02-29')).toBe('29/02/2028');
    });
  });

  describe('instante vale no fuso da empresa', () => {
    it('nota emitida às 22h de 27/08 não vira 28/08', () => {
      // O instante da NFS-e 1/4, como o banco o guarda.
      expect(formatar().formatDate('2026-08-28T01:22:27Z')).toBe('27/08/2026');
    });

    it('o mesmo instante com zona declarada dá a mesma data', () => {
      expect(formatar().formatDate('2026-08-27T22:22:27-03:00')).toBe('27/08/2026');
    });

    it('virada do mês: 31/08 às 21h não escorrega para setembro', () => {
      expect(formatar().formatDate('2026-09-01T00:30:00Z')).toBe('31/08/2026');
    });
  });

  it('os dois formatos do MESMO dia concordam entre si', () => {
    // Um vencimento lido da coluna DATE e o mesmo dia lido com hora comercial não podem
    // aparecer em dias diferentes na mesma tela.
    const { formatDate } = formatar();
    expect(formatDate('2026-09-18')).toBe(formatDate('2026-09-18T12:00:00-03:00'));
  });
});
