// A data mostrada é a do fuso da EMPRESA, não a do aparelho de quem abre.
//
// As datas deste sistema são fatos com hora marcada no Brasil: a autorização de uma NF-e,
// o vencimento de uma conta. Sem fixar o fuso, o mesmo registro aparece com datas
// diferentes conforme o dispositivo — e num caso real isso já aconteceu: a NFS-e 1/4 foi
// emitida 27/08/2026 às 22h22, é gravada como "2026-08-28T01:22Z", e em UTC a tela dizia
// 28/08 enquanto o XML dizia 27/08.
//
// Este teste roda com o fuso do processo em UTC de propósito: é assim que o CI roda, e foi
// exatamente onde a divergência apareceu.
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { renderHook } from '@testing-library/react';
import { I18nProvider, useI18n } from './index';

const tzOriginal = process.env.TZ;

describe('fuso das datas exibidas', () => {
  beforeAll(() => { process.env.TZ = 'UTC'; });
  afterAll(() => { process.env.TZ = tzOriginal; });

  function formatar() {
    const { result } = renderHook(() => useI18n(), {
      wrapper: ({ children }) => <I18nProvider>{children}</I18nProvider>,
    });
    return result.current;
  }

  it('nota emitida às 22h de 27/08 não vira 28/08', () => {
    // O instante exato da NFS-e 1/4, como o banco o guarda.
    expect(formatar().formatDate('2026-08-28T01:22:27Z')).toBe('27/08/2026');
  });

  it('o mesmo instante com fuso declarado dá a mesma data', () => {
    // Como o provedor devolve, já com "-03:00": tem de concordar com a linha acima.
    expect(formatar().formatDate('2026-08-27T22:22:27-03:00')).toBe('27/08/2026');
  });

  it('virada do mês: 31/08 às 21h não escorrega para setembro', () => {
    expect(formatar().formatDate('2026-09-01T00:30:00Z')).toBe('31/08/2026');
  });

  it('data sem hora continua sendo o dia que está escrito', () => {
    // Vencimentos vêm como 'YYYY-MM-DD' e são lidos como meia-noite UTC; com o fuso da
    // empresa isso cairia no dia anterior se a conversão fosse ingênua.
    expect(formatar().formatDate('2026-09-18T12:00:00Z')).toBe('18/09/2026');
  });
});
