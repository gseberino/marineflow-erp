import { describe, expect, it } from 'vitest';
import {
  normalizarAprovacao,
  orcamentosAprovaveis,
  parcelasDaCondicao,
  resumoDaAprovacao,
  sinalDoOrcamento,
} from './conjunto-aprovacao';
import { normalizarConjunto } from './conjunto';

const orc = { labor_cost_total: 1000, parts_cost_total: 500 };

describe('sinalDoOrcamento (3A: o sinal de cada um, pela lib única)', () => {
  it('sem condição: a condição padrão (50% do serviço + 100% das peças)', () => {
    expect(sinalDoOrcamento(orc, null)).toEqual({ valor: 1000, padrao: true });
    expect(sinalDoOrcamento(orc, [])).toEqual({ valor: 1000, padrao: true });
  });
  it('com a parcela de sinal da condição, já com o desconto (discountRatio)', () => {
    const parcelas = [{ tipo: 'aprovacao' as const, services_pct: 50, parts_pct: 100 }, { tipo: 'entrega' as const, services_pct: 50 }];
    expect(sinalDoOrcamento(orc, parcelas)).toEqual({ valor: 1000, padrao: false });
    // desconto de 150 em 1500 = 10%: o sinal cai na mesma proporção
    expect(sinalDoOrcamento({ ...orc, discount_amount: 150 }, parcelas).valor).toBe(900);
  });
  it('condição sem sinal: zero', () => {
    expect(sinalDoOrcamento(orc, [{ tipo: 'entrega', services_pct: 100, parts_pct: 100 }]).valor).toBe(0);
  });
});

describe('parcelasDaCondicao (a mesma resolução do banco)', () => {
  it('preset em lista vence as personalizadas; senão personalizadas; senão nenhuma', () => {
    expect(parcelasDaCondicao([{ percent: 30 }], [{ percent: 10 }])).toEqual([{ percent: 30 }]);
    expect(parcelasDaCondicao(null, [{ percent: 10 }])).toEqual([{ percent: 10 }]);
    expect(parcelasDaCondicao({ x: 1 }, 'lixo')).toBeNull();
  });
});

describe('normalizarAprovacao e resumo', () => {
  const bruto = {
    ok: true, ensaio: false, conjunto_id: 'c1', nome: 'OS-00104 + ORÇ-00140 + OS-00141',
    complementa: { id: 'a', numero: 'OS-00104' }, aprovados: 2, viraram_os: '1', aguardando_sinal: 1,
    documentos: [
      { id: 'a', numero: 'OS-00104', numero_depois: 'OS-00104', situacao: 'assinado', acao: 'nao_muda', texto: 'OS-00104 já foi assinado: não muda.' },
      { id: 'b', numero: 'ORÇ-00140', numero_depois: 'ORÇ-00140', situacao: 'aprovar', acao: 'aguardar_sinal', texto: '…' },
      { id: 'c', numero: 'ORÇ-00141', numero_depois: 'OS-00141', situacao: 'aprovar', acao: 'virar_os', texto: '…' },
      { id: 'd', numero: 'X', acao: 'inventada' },
    ],
    conjunto: null,
  };
  it('normaliza números, ação desconhecida vira "não muda"', () => {
    const r = normalizarAprovacao(bruto)!;
    expect(r.viraram_os).toBe(1);
    expect(r.documentos[3].acao).toBe('nao_muda');
    expect(r.documentos[3].numero_depois).toBe('X');
    expect(normalizarAprovacao(null)).toBeNull();
  });
  it('resumo diz o que virou OS, o que aguarda o sinal e quem complementa', () => {
    expect(resumoDaAprovacao(normalizarAprovacao(bruto)!)).toBe(
      'Pronto: 2 orçamentos aprovados — 1 virou OS (OS-00141) e 1 aguarda o sinal. Complementam a OS-00104.',
    );
    expect(resumoDaAprovacao(normalizarAprovacao({ ...bruto, complementa: null, aprovados: 1, viraram_os: 0, aguardando_sinal: 1 })!))
      .toBe('Pronto: 1 orçamento aprovado — 1 aguarda o sinal.');
  });
});

describe('orcamentosAprovaveis', () => {
  it('só os ativos marcados pelo banco, e nada de conjunto desfeito', () => {
    const c = normalizarConjunto({
      id: 'c', nome: 'n', ativo: true, documentos: [
        { id: 'a', numero: 'OS-1', tipo: 'os', ativo: true, aprovavel: false },
        { id: 'b', numero: 'ORÇ-2', tipo: 'orcamento', ativo: true, aprovavel: true },
        { id: 'z', numero: 'ORÇ-3', tipo: 'orcamento', ativo: false, aprovavel: true },
      ],
    })!;
    expect(orcamentosAprovaveis(c).map((d) => d.id)).toEqual(['b']);
    expect(orcamentosAprovaveis({ ...c, ativo: false })).toEqual([]);
  });
});
