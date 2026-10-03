import { describe, expect, it } from 'vitest';
import { conferirContas, duracaoLegivel, estadoDoPedido, lerProposta, motivoDaFalha, rascunhosCriados } from './orcamento-tecnico-ia';

const respostaValida = {
  format: 'json_schema',
  text: '{}',
  data: {
    premissas_tecnicas: ['Sistema 12 V'],
    margem_adotada: { criterio: 'markup mediano praticado', markup: 1.563 },
    perguntas_pendentes: ['Qual a distância até a bateria?'],
    orcamentos: [
      {
        titulo: 'Instalação do Orion',
        observacoes_valores_provisorios: ['Terminal — Valor provisório — aguardando cotação do fornecedor'],
        resumo: { custo_estimado: 100, margem_aplicada_pct: 56.3, total_materiais_e_equipamentos: 156.3, total_mao_de_obra: 300, total_geral: 456.3 },
        itens: [
          { tipo: 'equipamento', descricao: 'Orion', produto_id: 'p1', servico_id: null, quantidade: 1, unidade: 'UN', custo_unitario: 100, origem_do_custo: 'cadastro', data_do_custo: '2026-07-27', provisorio: false, preco_venda_unitario: 156.3, total_venda: 156.3 },
          { tipo: 'mao_de_obra', descricao: 'Instalação', produto_id: null, servico_id: 's1', quantidade: 2, unidade: 'hora', custo_unitario: 0, origem_do_custo: 'tabela', data_do_custo: null, provisorio: false, preco_venda_unitario: 150, total_venda: 300 },
        ],
      },
    ],
  },
};

describe('lerProposta', () => {
  it('lê a proposta do gateway', () => {
    const p = lerProposta(respostaValida)!;
    expect(p.orcamentos).toHaveLength(1);
    expect(p.orcamentos[0]!.itens[1]).toMatchObject({ tipo: 'mao_de_obra', servicoId: 's1', quantidade: 2, totalVenda: 300 });
    expect(p.margem).toEqual({ criterio: 'markup mediano praticado', markup: 1.563 });
    expect(p.perguntasPendentes).toEqual(['Qual a distância até a bateria?']);
  });

  it('não quebra com resposta vazia, texto ou campos estranhos', () => {
    expect(lerProposta(null)).toBeNull();
    expect(lerProposta({ format: 'text', text: 'oi' })).toBeNull();
    expect(lerProposta({ data: { orcamentos: [] } })).toBeNull();
    const p = lerProposta({ data: { orcamentos: [{ itens: [{ tipo: 'foguete', quantidade: 'x', provisorio: 'sim' }] }] } })!;
    expect(p.orcamentos[0]!.titulo).toBe('Orçamento');
    expect(p.orcamentos[0]!.itens[0]).toMatchObject({ tipo: 'material', quantidade: 0, provisorio: false, descricao: 'Item sem descrição' });
  });
});

describe('conferirContas', () => {
  it('não reclama de contas certas', () => {
    expect(conferirContas(lerProposta(respostaValida)!.orcamentos[0]!)).toEqual([]);
  });

  it('aponta linha e total que não fecham', () => {
    const orc = lerProposta(respostaValida)!.orcamentos[0]!;
    orc.itens[0]!.totalVenda = 999;
    expect(conferirContas(orc)).toEqual([
      '"Orion": quantidade × preço não bate com o total da linha.',
      'O total geral declarado não bate com a soma das linhas.',
    ]);
  });
});

describe('estado, rascunhos e textos', () => {
  it('traduz o status do job', () => {
    expect(estadoDoPedido({ status: 'pending', started_at: null })).toBe('na_fila');
    expect(estadoDoPedido({ status: 'processing', started_at: 'x' })).toBe('montando');
    expect(estadoDoPedido({ status: 'completed', started_at: 'x' })).toBe('pronta');
    expect(estadoDoPedido({ status: 'failed', started_at: 'x' })).toBe('falhou');
    expect(estadoDoPedido({ status: 'cancelled', started_at: null })).toBe('cancelado');
  });

  it('lê os rascunhos já criados', () => {
    expect(rascunhosCriados({ tipo: 'orcamento_tecnico', rascunhos: { '0': 'so-1', '2': 'so-3', x: 'lixo' } })).toEqual({ 0: 'so-1', 2: 'so-3' });
    expect(rascunhosCriados(null)).toEqual({});
  });

  it('formata a duração e explica a falha', () => {
    expect(duracaoLegivel(42_000)).toBe('42 s');
    expect(duracaoLegivel(185_000)).toBe('3 min 05 s');
    expect(motivoDaFalha({ error_code: 'rate_limited', error: 'x' })).toMatch(/limite de uso/);
    expect(motivoDaFalha({ error_code: 'server_error', error: 'detalhe técnico' })).toBe('detalhe técnico');
  });
});
