// Agrupamento da caixa de entrada por favorecido.
//
// O que se testa aqui não é formatação: é quantas DECISÕES o gestor terá de tomar, e se
// alguma despesa grande consegue escapar da revisão individual escondida num grupo.
import { describe, it, expect } from 'vitest';
import {
  agruparPorFavorecido, resumoDoAgrupamento, normalizarFavorecido, SEM_CATEGORIA,
} from '@/lib/finance-inbox-grouping';
import type { PropostaFinanceira } from '@/hooks/use-finance-review';

const LIMITE = 500;

let seq = 0;
function proposta(o: Partial<PropostaFinanceira> & {
  nome?: string | null; documento?: string | null; descricao?: string | null;
} = {}): PropostaFinanceira {
  const { nome, documento, descricao, ...resto } = o;
  seq += 1;
  return {
    id: `p${seq}`,
    kind: 'create_payable',
    status: 'pending',
    bank_transaction_id: `t${seq}`,
    related_transaction_id: null,
    title: 'Despesa',
    reasoning: null,
    confidence: 60,
    suggested_amount: 100,
    suggested_date: '2026-03-10',
    suggested_category: SEM_CATEGORIA,
    suggested_description: nome ?? 'Despesa',
    suggested_supplier_id: null,
    dre_group: 'despesa_operacional',
    applied_rule_id: null,
    suggested_payee_id: null,
    suggested_service_order_id: null,
    suggested_purchase_order_id: null,
    created_at: '2026-03-10T10:00:00Z',
    bank_transactions: {
      counterparty_name: nome ?? null,
      counterparty_document: documento ?? null,
      counterparty_bank: null, counterparty_branch: null, counterparty_account: null,
      payment_method: null, payment_reason: null,
      merchant_name: null, merchant_document: null, installment_label: null,
      pix_end_to_end_id: null,
      description: descricao ?? nome ?? 'COMPRA',
      source_type: 'credit_card', bank_ref_id: `ref${seq}`,
    },
    ...resto,
  } as PropostaFinanceira;
}

describe('agrupamento por favorecido', () => {
  it('junta o mesmo estabelecimento numa decisão só', () => {
    // O caso real: 34 compras no mesmo lugar somando R$ 320. Uma pergunta, não 34.
    const grupos = agruparPorFavorecido(
      Array.from({ length: 34 }, () => proposta({ nome: 'SPG*DEPARTAMENTO DE ES CURITIBA', suggested_amount: 9.42 })),
      LIMITE,
    );
    expect(grupos).toHaveLength(1);
    expect(grupos[0].propostas).toHaveLength(34);
    expect(grupos[0].total).toBeCloseTo(320.28, 2);
  });

  it('ignora caixa, acento e espaço repetido do extrato', () => {
    // "EC          *INOHOUSE" e "ec *inohouse" são o mesmo lugar; espaço a mais é ruído do
    // banco, não identidade.
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'EC          *INOHOUSE' }),
      proposta({ nome: 'ec *inohouse' }),
      proposta({ nome: 'Padaria Açucena' }),
      proposta({ nome: 'PADARIA ACUCENA' }),
    ], LIMITE);
    expect(grupos).toHaveLength(2);
    expect(grupos.every((g) => g.propostas.length === 2)).toBe(true);
  });

  it('documento vale mais que nome escrito diferente', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'ALEX GONCALVES MACHADO', documento: '54834240000199' }),
      proposta({ nome: '54.834.240 ALEX G MACHADO', documento: '54.834.240/0001-99' }),
    ], LIMITE);
    expect(grupos).toHaveLength(1);
  });

  it('fornecedor cadastrado manda em tudo', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'MARINE EXPRESS', suggested_supplier_id: 'f1' }),
      proposta({ nome: 'MARINE EXPRESS COMERCIAL IMPOR', suggested_supplier_id: 'f1' }),
    ], LIMITE);
    expect(grupos).toHaveLength(1);
    expect(grupos[0].supplierId).toBe('f1');
  });

  it('sem nome no extrato, cada histórico é seu próprio grupo — não um balaio', () => {
    // Juntar tudo que o banco não identificou daria um grupo gigante de coisas sem relação,
    // e classificá-lo de uma vez seria pior que não classificar.
    const grupos = agruparPorFavorecido([
      proposta({ nome: null, descricao: 'TRANSF ENVIADA PIX 8821' }),
      proposta({ nome: null, descricao: 'TRANSF ENVIADA PIX 9930' }),
    ], LIMITE);
    expect(grupos).toHaveLength(2);
  });

  it('despesa grande não escapa da revisão individual dentro do grupo', () => {
    // É a regra que protege o dinheiro: o grupo resolve a CATEGORIA de todas, mas o botão
    // de aprovar do grupo não pode alcançar uma saída de R$ 4.000.
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'FELIPE ANTUNES', suggested_amount: 120 }),
      proposta({ nome: 'FELIPE ANTUNES', suggested_amount: 4000 }),
      proposta({ nome: 'FELIPE ANTUNES', suggested_amount: 500 }),
    ], LIMITE);
    expect(grupos[0].emLote.map((p) => p.suggested_amount)).toEqual([120]);
    expect(grupos[0].individuais.map((p) => p.suggested_amount)).toEqual([4000, 500]);
    expect(grupos[0].totalEmLote).toBe(120);
  });

  it('transferência entre contas nunca entra no lote do grupo', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'HBR BOATS', kind: 'internal_transfer', suggested_amount: 50 }),
    ], LIMITE);
    expect(grupos[0].emLote).toHaveLength(0);
    expect(grupos[0].individuais).toHaveLength(1);
  });

  it('mostra o período e avisa quando o sistema hesitou entre categorias', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'POSTO X', suggested_category: 'Combustível e deslocamento', suggested_date: '2025-11-15' }),
      proposta({ nome: 'POSTO X', suggested_category: 'Peças e materiais', suggested_date: '2026-04-18' }),
    ], LIMITE);
    expect(grupos[0].categorias).toEqual(['Combustível e deslocamento', 'Peças e materiais']);
    expect(grupos[0].semCategoria).toBe(false);
    expect(grupos[0].primeiraData).toBe('2025-11-15');
    expect(grupos[0].ultimaData).toBe('2026-04-18');
  });

  it('só é "sem categoria" quando nenhuma linha do grupo tem uma de verdade', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'LOJA Y' }),
      proposta({ nome: 'LOJA Y', suggested_category: 'Peças e materiais' }),
      proposta({ nome: 'LOJA Z' }),
    ], LIMITE);
    const y = grupos.find((g) => g.rotulo === 'LOJA Y')!;
    const z = grupos.find((g) => g.rotulo === 'LOJA Z')!;
    expect(y.semCategoria).toBe(false);
    expect(z.semCategoria).toBe(true);
  });

  it('os que mais rendem decisão vêm primeiro', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'UM SÓ', suggested_amount: 400 }),
      proposta({ nome: 'REPETIDO' }), proposta({ nome: 'REPETIDO' }), proposta({ nome: 'REPETIDO' }),
    ], LIMITE);
    expect(grupos[0].rotulo).toBe('REPETIDO');
  });

  it('resume o quanto o agrupamento economiza', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'A' }), proposta({ nome: 'A' }), proposta({ nome: 'A' }),
      proposta({ nome: 'B' }), proposta({ nome: 'B' }),
      proposta({ nome: 'C' }),
    ], LIMITE);
    expect(resumoDoAgrupamento(grupos)).toMatchObject({
      grupos: 3, propostas: 6, repetidos: 2, propostasEmRepetidos: 5,
    });
  });
});

describe('normalização do nome', () => {
  it('não funde nomes diferentes', () => {
    expect(normalizarFavorecido('MERCADO LIVRE')).not.toBe(normalizarFavorecido('MERCADO PAGO'));
  });
  it('devolve vazio quando não há nada identificável', () => {
    expect(normalizarFavorecido('   ***   ')).toBe('');
  });
});
