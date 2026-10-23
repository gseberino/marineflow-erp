// Agrupamento da caixa de entrada por favorecido.
//
// O que se testa aqui não é formatação: é quantas DECISÕES o gestor terá de tomar, e se
// alguma despesa grande consegue escapar da revisão individual escondida num grupo.
import { describe, it, expect } from 'vitest';
import {
  agruparPorFavorecido, ordenarGrupos, resumoDoAgrupamento, normalizarFavorecido, SEM_CATEGORIA, motivoForaDoLote,
} from '@/lib/finance-inbox-grouping';
import type { PropostaFinanceira } from '@/hooks/use-finance-review';
import { clienteEscolhido, clienteFaltaEscolher, clientePedeSim } from '@/lib/extrato-vinculo';
// A fonte única do servidor (clienteQueAprovacaoUsa e pedidoDeConfirmacaoDoCliente a usam). O identificacao.ts em si
// não entra aqui: ele importa tipos de https://esm.sh, que o tsc da tela não resolve.
import { situacaoDoClienteSugerido } from '../../supabase/functions/_shared/banking/contraparte';

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

  it('dentro do grupo, da mais recente para a mais antiga', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'A', suggested_date: '2026-01-10' }),
      proposta({ nome: 'A', suggested_date: '2026-06-20' }),
      proposta({ nome: 'A', suggested_date: '2026-03-15' }),
    ], LIMITE);
    expect(grupos[0].propostas.map((p) => p.suggested_date))
      .toEqual(['2026-06-20', '2026-03-15', '2026-01-10']);
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

describe('ordem da fila', () => {
  // Não existe uma ordem certa — existe a que serve ao que se está fazendo. O que importa
  // é que cada opção realmente mude a lista, senão o seletor é decoração.
  const monta = () => agruparPorFavorecido([
    proposta({ nome: 'ZEBRA', suggested_date: '2026-06-01', suggested_category: 'Peças e materiais' }),
    proposta({ nome: 'ALFA', suggested_date: '2026-01-01' }),
    proposta({ nome: 'ALFA', suggested_date: '2026-02-01' }),
    proposta({ nome: 'ALFA', suggested_date: '2026-03-01' }),
  ], LIMITE);

  it('mais linhas primeiro é o padrão do mutirão', () => {
    expect(ordenarGrupos(monta(), 'decisoes').map((g) => g.rotulo)).toEqual(['ALFA', 'ZEBRA']);
  });

  it('prontos para aprovar sobem, mesmo tendo menos linhas', () => {
    // ZEBRA tem uma linha só, mas já tem categoria: é despacho imediato.
    expect(ordenarGrupos(monta(), 'prontos').map((g) => g.rotulo)).toEqual(['ZEBRA', 'ALFA']);
  });

  it('a tela pode dizer o que a lista não sabe: a categoria recém-escolhida', () => {
    const escolhido = ordenarGrupos(monta(), 'prontos', (g) => g.rotulo === 'ALFA');
    expect(escolhido.map((g) => g.rotulo)).toEqual(['ALFA', 'ZEBRA']);
  });

  it('por data usa a movimentação mais recente do grupo', () => {
    expect(ordenarGrupos(monta(), 'data').map((g) => g.rotulo)).toEqual(['ZEBRA', 'ALFA']);
  });

  it('por favorecido respeita acento do português', () => {
    const grupos = agruparPorFavorecido([
      proposta({ nome: 'Ótica Central' }), proposta({ nome: 'Auto Peças' }), proposta({ nome: 'Zé Materiais' }),
    ], LIMITE);
    expect(ordenarGrupos(grupos, 'favorecido').map((g) => g.rotulo))
      .toEqual(['Auto Peças', 'Ótica Central', 'Zé Materiais']);
  });

  it('não altera a lista original', () => {
    const grupos = monta();
    const antes = grupos.map((g) => g.rotulo);
    ordenarGrupos(grupos, 'favorecido');
    expect(grupos.map((g) => g.rotulo)).toEqual(antes);
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

describe("pergunta sem resposta não entra no lote (decisão do dono, 26/09/2026)", () => {
  it("OS ou OC sugerida vai para a revisão individual, com o motivo certo", () => {
    const comOs = proposta({ nome: "LOJA", suggested_service_order_id: "os1" });
    const comOc = proposta({ nome: "LOJA", suggested_purchase_order_id: "oc1" });
    const normal = proposta({ nome: "LOJA" });
    const [g] = agruparPorFavorecido([comOs, comOc, normal], LIMITE);
    expect(g.emLote.map((p) => p.id)).toEqual([normal.id]);
    expect(g.motivos[comOs.id]).toBe("responder_os");
    expect(g.motivos[comOc.id]).toBe("responder_os");
  });

  it("respondida na tela, volta para o lote", () => {
    const comOs = proposta({ nome: "LOJA", suggested_service_order_id: "os1" });
    const [g] = agruparPorFavorecido([comOs], LIMITE, { [comOs.id]: { serviceOrderId: null } });
    expect(g.emLote.map((p) => p.id)).toEqual([comOs.id]);
  });

  it("vínculo sugerido pequeno tem o motivo dele, não 'acima do limite'", () => {
    const v = proposta({ nome: "LOJA", suggested_amount: 50, vinculo_sugerido: { principal: {
      tipo: "payable", id: "c1", rotulo: "Conta: x", valor: 50, confianca: 80, nivel: "probable", motivos: [],
      diferenca: 0, lancamentoId: "c1", lado: "payable", ordemDeServicoId: null, clienteId: null, clienteNome: null,
      converteOrcamento: false, jaLancado: false,
    }, alternativas: [] } } as never);
    const [g] = agruparPorFavorecido([v], LIMITE);
    expect(g.motivos[v.id]).toBe("responder_vinculo");
    expect(motivoForaDoLote(v, LIMITE)).toBe("responder_vinculo");
  });

  it("OS que o dono anotou já é resposta", () => {
    const anotada = proposta({ nome: "LOJA", suggested_service_order_id: "os1",
      evidencia: { anotacao: { id: "a1", os_id: "os1" } } } as never);
    expect(motivoForaDoLote(anotada, LIMITE)).toBeNull();
  });
});

describe("serviço de terceiro sem 'para onde foi' não entra no lote (decisão do dono, 26/09/2026)", () => {
  it("sem resposta fica de fora, com o motivo dele", () => {
    const servico = proposta({ nome: "JOAO PINTOR", suggested_category: "Serviços de terceiros" });
    const normal = proposta({ nome: "JOAO PINTOR", suggested_category: "Peças e materiais" });
    const [g] = agruparPorFavorecido([servico, normal], LIMITE);
    expect(g.emLote.map((p) => p.id)).toEqual([normal.id]);
    expect(g.motivos[servico.id]).toBe("responder_destino");
  });

  it("respondido (para a HBR, com centro e o que foi feito), volta para o lote", () => {
    const servico = proposta({ nome: "JOAO PINTOR", suggested_category: "Serviços de terceiros" });
    expect(motivoForaDoLote(servico, LIMITE, {
      destino: "empresa", category: "Serviços de terceiros para a empresa", costCenterId: "cc", notes: "pintura da sede",
    })).toBeNull();
    // Metade da resposta não basta: sem "o que foi feito" continua de fora.
    expect(motivoForaDoLote(servico, LIMITE, { destino: "empresa", costCenterId: "cc" })).toBe("responder_destino");
  });

  it("casar com o que já está lançado não pergunta para onde foi", () => {
    const servico = proposta({ nome: "JOAO PINTOR", suggested_category: "Serviços de terceiros" });
    expect(motivoForaDoLote(servico, LIMITE, { vinculo: { id: "c1" } })).toBeNull();
  });

  it("a OS anotada pelo WhatsApp responde o destino; falta só o que foi feito", () => {
    const anotada = proposta({ nome: "JOAO PINTOR", suggested_category: "Serviços de terceiros", suggested_service_order_id: "os1",
      evidencia: { anotacao: { id: "a1", os_id: "os1" } } } as never);
    expect(motivoForaDoLote(anotada, LIMITE)).toBe("responder_destino");
    expect(motivoForaDoLote(anotada, LIMITE, { notes: "mão de obra da solda" })).toBeNull();
  });
});

describe('entrada que sai sem receita não entra no lote (revisão de 28/09/2026)', () => {
  const entrada = (categoria: string) => proposta({ kind: 'create_receivable', suggested_category: categoria, nome: 'HBR ENGENHARIA' });

  it('transferência ou aporte, sugerido ou escolhido na linha: uma a uma', () => {
    expect(motivoForaDoLote(entrada('Transferência entre contas'), LIMITE)).toBe('sem_receita');
    expect(motivoForaDoLote(entrada('Aporte de sócio'), LIMITE)).toBe('sem_receita');
    // A categoria escolhida na linha vale mais que a sugerida — nos dois sentidos.
    expect(motivoForaDoLote(entrada('Serviços prestados'), LIMITE, { category: 'Aporte de sócio' })).toBe('sem_receita');
    expect(motivoForaDoLote(entrada('Aporte de sócio'), LIMITE, { category: 'Serviços prestados' })).toBeNull();
  });

  it('receita comum pequena continua no lote; a SAÍDA "Transferência entre contas" também', () => {
    expect(motivoForaDoLote(entrada('Serviços prestados'), LIMITE)).toBeNull();
    expect(motivoForaDoLote(proposta({ suggested_category: 'Transferência entre contas' }), LIMITE)).toBeNull();
  });

  it('no agrupado, a entrada sem receita fica fora do botão do grupo, com o motivo', () => {
    const grupos = agruparPorFavorecido([entrada('Aporte de sócio'), entrada('Serviços prestados')], LIMITE, {});
    const g = grupos.find((x) => x.propostas.length === 2)!;
    expect(g.emLote).toHaveLength(1);
    expect(g.individuais).toHaveLength(1);
    expect(Object.values(g.motivos)).toEqual(['sem_receita']);
  });
});

/**
 * Leva 8 (22/10/2026): o cliente sugerido por quem pagou — pagador conhecido, histórico de
 * terceiro, vínculo antigo — pede o SIM. A tela mostra e manda o MESMO cliente que o servidor
 * usaria (clienteEscolhido = clienteQueAprovacaoUsa), e a linha sem resposta não vai no lote.
 */
describe('cliente que pede o SIM (leva 8)', () => {
  const entrada = (por: string | null, cliente: string | null = 'c-ana') => proposta({
    kind: 'create_receivable', suggested_category: 'Serviços prestados', nome: 'MARIA DA SILVA',
    suggested_client_id: cliente,
    evidencia: por ? { cliente: { id: cliente ?? 'x', nome: 'Ana Souza', por: por as never, detalhe: 'x' } } : null,
  });

  it('clienteEscolhido: o sugerido só vale sem SIM; a escolha da pessoa vale sempre', () => {
    expect(clienteEscolhido(entrada('documento'))).toBe('c-ana');
    expect(clienteEscolhido(entrada('regra'))).toBe('c-ana');
    expect(clienteEscolhido(entrada('nome_identico'))).toBe('c-ana');
    // Sugerido SEM prova nenhuma (e sem anotação): ninguém disse de quem é — o servidor recusaria (4ª rodada).
    expect(clienteEscolhido(entrada(null))).toBeNull();
    expect(clienteEscolhido(entrada(null), { clientId: 'c-ana' })).toBe('c-ana');
    for (const por of ['pagador_conhecido', 'historico', 'vinculo']) {
      expect(clienteEscolhido(entrada(por))).toBeNull();
      expect(clienteEscolhido(entrada(por), { clientId: 'c-ana' })).toBe('c-ana');
      expect(clienteEscolhido(entrada(por), { clientId: 'c-rui' })).toBe('c-rui');
    }
  });

  it('clientePedeSim: só com sugerido que pede SIM e ninguém respondeu', () => {
    expect(clientePedeSim(entrada('pagador_conhecido'))).toBe(true);
    expect(clientePedeSim(entrada('historico'))).toBe(true);
    expect(clientePedeSim(entrada('pagador_conhecido'), { clientId: 'c-ana' })).toBe(false);
    expect(clientePedeSim(entrada('documento'))).toBe(false);
    expect(clientePedeSim(entrada('pagador_conhecido', null))).toBe(false);
  });

  it('a linha que pede o SIM fica fora do lote; respondida, volta', () => {
    expect(motivoForaDoLote(entrada('pagador_conhecido'), LIMITE)).toBe('responder_cliente');
    expect(motivoForaDoLote(entrada('historico'), LIMITE)).toBe('responder_cliente');
    expect(motivoForaDoLote(entrada('pagador_conhecido'), LIMITE, { clientId: 'c-ana' })).toBeNull();
    expect(motivoForaDoLote(entrada('documento'), LIMITE)).toBeNull();
    // Transferência ou aporte sai sem receita: o motivo é esse, não o cliente.
    expect(motivoForaDoLote(entrada('pagador_conhecido'), LIMITE, { category: 'Aporte de sócio' })).toBe('sem_receita');
  });

  it('no agrupado, o botão do grupo não alcança quem pede o SIM', () => {
    const grupos = agruparPorFavorecido([entrada('pagador_conhecido'), entrada('documento')], LIMITE, {});
    const g = grupos.find((x) => x.propostas.length === 2)!;
    expect(g.emLote).toHaveLength(1);
    expect(Object.values(g.motivos)).toEqual(['responder_cliente']);
  });
});

/**
 * Revisão de 23/10/2026: a ANOTAÇÃO do dono ("o Pix de 1.500 é da TSD") é instrução dele — vale como o SIM. O
 * _aplicar_anotacao troca o cliente sugerido e deixa a prova antiga do motor (de outro cliente) na evidência; a tela
 * usa a mesma conta do servidor (clienteDaPropostaExigeSim) e não pede "Sim, é do <outro>".
 */
describe('a anotação do dono vence a prova antiga (revisão de 23/10/2026)', () => {
  const comAnotacao = (sugerido: string | null, por: string, anotacao: { id?: string; os_id?: string | null } | null) => proposta({
    kind: 'create_receivable', suggested_category: 'Serviços prestados', nome: 'MARIA DA SILVA',
    suggested_client_id: sugerido,
    evidencia: {
      cliente: { id: 'c-ana', nome: 'Ana Souza', por: por as never, detalhe: 'x' },
      ...(anotacao ? { anotacao } : {}),
    },
  });

  it('anotação que trocou o cliente: o anotado vale, sem SIM, e a linha volta ao lote', () => {
    for (const por of ['pagador_conhecido', 'historico', 'vinculo']) {
      const p = comAnotacao('c-tsd', por, { id: 'an-1', os_id: null });
      expect(clienteEscolhido(p)).toBe('c-tsd');
      expect(clientePedeSim(p)).toBe(false);
      expect(motivoForaDoLote(p, LIMITE)).toBeNull();
      // A escolha da pessoa continua valendo mais que tudo.
      expect(clienteEscolhido(p, { clientId: 'c-rui' })).toBe('c-rui');
    }
  });

  it('anotação DESFEITA (a marca saiu, o sugerido ficou): falta escolher — nem o sugerido, nem "Sim, é do <prova>", fora do lote', () => {
    // 4ª rodada: desligar o comprovante tira a marca da anotação da evidência e mantém o sugerido que ela pôs. Ninguém
    // disse mais de quem é: o servidor recusa com "Escolha o cliente…" (PEDIDO_DE_ESCOLHA_DO_CLIENTE).
    for (const por of ['pagador_conhecido', 'historico', 'vinculo', 'documento']) {
      const p = comAnotacao('c-tsd', por, null);
      expect(clienteEscolhido(p)).toBeNull();
      expect(clientePedeSim(p)).toBe(false);
      expect(clienteFaltaEscolher(p)).toBe(true);
      expect(motivoForaDoLote(p, LIMITE)).toBe('escolher_cliente');
      // Escolhido um cliente (qualquer um, inclusive o da prova antiga), a linha volta ao lote com ele.
      for (const escolhido of ['c-tsd', 'c-ana']) {
        expect(clienteEscolhido(p, { clientId: escolhido })).toBe(escolhido);
        expect(clienteFaltaEscolher(p, { clientId: escolhido })).toBe(false);
        expect(motivoForaDoLote(p, LIMITE, { clientId: escolhido })).toBeNull();
      }
    }
  });

  it('marca da anotação SEM id não é anotação em vigor: falta escolher', () => {
    const p = comAnotacao('c-tsd', 'pagador_conhecido', { os_id: null });
    expect(clienteEscolhido(p)).toBeNull();
    expect(clienteFaltaEscolher(p)).toBe(true);
  });

  it('transferência ou aporte: sai sem receita — o motivo é esse, não o cliente', () => {
    const p = comAnotacao('c-tsd', 'pagador_conhecido', null);
    expect(motivoForaDoLote(p, LIMITE, { category: 'Aporte de sócio' })).toBe('sem_receita');
  });

  it('anotação com a OS do mesmo cliente da prova é o SIM; só com categoria, não', () => {
    const comOS = comAnotacao('c-ana', 'pagador_conhecido', { id: 'an-2', os_id: 'os-60' });
    expect(clienteEscolhido(comOS)).toBe('c-ana');
    expect(clientePedeSim(comOS)).toBe(false);

    const soCategoria = comAnotacao('c-ana', 'historico', { id: 'an-3', os_id: null });
    expect(clienteEscolhido(soCategoria)).toBeNull();
    expect(clientePedeSim(soCategoria)).toBe(true);
    expect(motivoForaDoLote(soCategoria, LIMITE)).toBe('responder_cliente');
  });

  it('sem ler a anotação, a tela erra para o lado da pergunta: o mesmo cliente da prova, sem OS, ainda pede o "sim"', () => {
    // A anotação aplicada só guarda {id, os_id} na evidência; que o dono anotou o MESMO cliente da prova só se sabe
    // lendo a anotação — o servidor e o assistente leem e dispensam o SIM; a tela, não (divergência conhecida, baixa:
    // um "sim" a mais, nunca uma baixa sem ele).
    const p = comAnotacao('c-ana', 'pagador_conhecido', { id: 'an-4', os_id: null });
    expect(clientePedeSim(p)).toBe(true);
    // O servidor, com a anotação LIDA, dispensa o SIM.
    expect(situacaoDoClienteSugerido('c-ana', p.evidencia?.cliente, { cliente_id: 'c-ana', os_id: null })).toBe('vale');
  });
});

/**
 * A tela e o servidor não podem discordar sobre o que acontece quando se clica em aprovar (extrato-vinculo.ts). O
 * servidor sem ler a anotação (a marca que a evidência guarda) decide por situacaoDoClienteSugerido: usa o sugerido só
 * em "vale" (clienteQueAprovacaoUsa), pede "Sim, é do X" em "pede_sim" e recusa com "Escolha o cliente…" em "escolher"
 * (pedidoDeConfirmacaoDoCliente). A tela mostra o mesmo cliente e pede a mesma resposta — caso a caso.
 */
describe('paridade tela × servidor no cliente da entrada (4ª rodada)', () => {
  type Situacao = 'vale' | 'pede_sim' | 'escolher' | 'sem_sugestao';
  const casos: Array<[string, string | null, { id: string; por: string } | null, { id?: string; os_id?: string | null } | null, Situacao]> = [
    ['documento do sugerido', 'c-ana', { id: 'c-ana', por: 'documento' }, null, 'vale'],
    ['regra do sugerido', 'c-ana', { id: 'c-ana', por: 'regra' }, null, 'vale'],
    ['pagador conhecido do sugerido', 'c-ana', { id: 'c-ana', por: 'pagador_conhecido' }, null, 'pede_sim'],
    ['histórico do sugerido', 'c-ana', { id: 'c-ana', por: 'historico' }, null, 'pede_sim'],
    ['vínculo do sugerido', 'c-ana', { id: 'c-ana', por: 'vinculo' }, null, 'pede_sim'],
    ['anotação em vigor trocou o cliente', 'c-tsd', { id: 'c-ana', por: 'pagador_conhecido' }, { id: 'an-1', os_id: null }, 'vale'],
    ['anotação com OS', 'c-ana', { id: 'c-ana', por: 'historico' }, { id: 'an-2', os_id: 'os-60' }, 'vale'],
    ['anotação só com categoria', 'c-ana', { id: 'c-ana', por: 'historico' }, { id: 'an-3', os_id: null }, 'pede_sim'],
    ['anotação desfeita, prova de outro', 'c-tsd', { id: 'c-ana', por: 'pagador_conhecido' }, null, 'escolher'],
    ['anotação desfeita, prova forte de outro', 'c-tsd', { id: 'c-ana', por: 'documento' }, null, 'escolher'],
    ['sugerido sem prova nenhuma', 'c-tsd', null, null, 'escolher'],
    ['anotação em vigor sem prova', 'c-tsd', null, { id: 'an-5', os_id: null }, 'vale'],
    ['sem sugerido', null, { id: 'c-ana', por: 'pagador_conhecido' }, null, 'sem_sugestao'],
  ];

  it.each(casos)('%s → %s', (_nome, sugerido, prova, anotacao, esperado) => {
    const p = proposta({
      kind: 'create_receivable', suggested_category: 'Serviços prestados', nome: 'MARIA DA SILVA',
      suggested_client_id: sugerido,
      evidencia: {
        ...(prova ? { cliente: { id: prova.id, nome: 'Ana Souza', por: prova.por as never, detalhe: 'x' } } : {}),
        ...(anotacao ? { anotacao } : {}),
      },
    });
    // O servidor (sem ler a anotação: a marca da evidência).
    expect(situacaoDoClienteSugerido(sugerido, p.evidencia?.cliente, p.evidencia?.anotacao ?? null)).toBe(esperado);
    // A tela.
    expect(clienteEscolhido(p)).toBe(esperado === 'vale' ? sugerido : null);
    expect(clientePedeSim(p)).toBe(esperado === 'pede_sim');
    expect(clienteFaltaEscolher(p)).toBe(esperado === 'escolher');
    expect(motivoForaDoLote(p, LIMITE)).toBe(
      esperado === 'pede_sim' ? 'responder_cliente' : esperado === 'escolher' ? 'escolher_cliente' : null,
    );
  });
});
