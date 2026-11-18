import { describe, it, expect } from 'vitest';
import { textoDaRevisao, type RevisaoNaSituacao, type SituacaoDaRevisao } from './use-revisao-do-documento';

const rev = (n: number, extra: Partial<RevisaoNaSituacao> = {}): RevisaoNaSituacao => ({
  revisao: n, codigo: 'AAAA-BBBB', emitida_em: '2026-11-15T13:00:00Z',
  enviada_em: null, enviada_via: null, aprovada_em: null, assinada_em: null, ...extra,
});
const sit = (s: Partial<SituacaoDaRevisao>): SituacaoDaRevisao => ({
  tipo: 'quote', atual: null, enviada: null, aprovada: null, mudou_desde_a_ultima: false, ...s,
});

describe('a revisão na linha sob o número', () => {
  it('sem PDF gerado ainda, nada', () => {
    expect(textoDaRevisao(sit({}))).toBeNull();
    expect(textoDaRevisao(null)).toBeNull();
  });

  it('cliente com a revisão atual: sem alerta', () => {
    const r = rev(2, { enviada_em: '2026-11-16T12:00:00Z', enviada_via: 'tela' });
    expect(textoDaRevisao(sit({ atual: r, enviada: r }))).toMatchObject({ curto: 'Rev. 2 · enviada ao cliente', alerta: false });
  });

  it('cliente com uma revisão antiga: alerta e as datas na dica', () => {
    const t = textoDaRevisao(sit({ atual: rev(3), enviada: rev(2, { enviada_em: '2026-11-15T12:00:00Z' }) }))!;
    expect(t.curto).toBe('Rev. 3 · cliente tem a Rev. 2');
    expect(t.alerta).toBe(true);
    expect(t.completo).toContain('O cliente recebeu a Rev. 2 em 15/11/2026.');
  });

  it('mudou depois da última: diz que o próximo PDF sai como a seguinte', () => {
    const t = textoDaRevisao(sit({ atual: rev(3), mudou_desde_a_ultima: true }))!;
    expect(t.curto).toBe('Rev. 3 · alterado depois da Rev. 3');
    expect(t.completo).toContain('o próximo PDF sai como Rev. 4');
    expect(t.alerta).toBe(true);
  });

  it('aprovada numa revisão anterior à atual: alerta', () => {
    const t = textoDaRevisao(sit({ atual: rev(4), aprovada: rev(3, { aprovada_em: '2026-11-16T12:00:00Z' }) }))!;
    expect(t.curto).toBe('Rev. 4 · aprovada na Rev. 3');
    expect(t.alerta).toBe(true);
    const assinada = textoDaRevisao(sit({ atual: rev(3), aprovada: rev(3, { assinada_em: '2026-11-16T12:00:00Z' }) }))!;
    expect(assinada.curto).toBe('Rev. 3 · assinada');
    expect(assinada.alerta).toBe(false);
  });
});
