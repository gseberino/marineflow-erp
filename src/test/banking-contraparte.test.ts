// Identificador único de contraparte — casos tirados da fila do Extrato de 25/09/2026.
//
// Antes: 3 de 47 saídas com fornecedor, 0 com favorecido, 1 de 24 entradas com cliente.
// Cada teste aqui é um desses casos, e a trava do caso Coremma (nome parecido nunca decide
// em silêncio) tem os seus.
import { describe, it, expect } from 'vitest';
import {
  indexarContrapartes, identificarContraparte, nomeLimpo, frasesDaIdentificacao, nomeDaDescricao, documentoContradiz, documentoNormalizado,
  clienteExigeSim, documentoMascarado, frasePagoPor, fraseDoVeto, pagadoresDoDocumento, vetoDoPagador, RELACOES_DO_PAGADOR,
  ROTULO_DA_RELACAO, type CadastroParaIdentificar,
  clienteDaPropostaExigeSim, nomeSemCpf, perguntaDeQuemEValida, RELACAO_DO_NOME_IDENTICO, situacaoDoClienteSugerido,
} from '../../supabase/functions/_shared/banking/contraparte';

const cadastro: CadastroParaIdentificar = {
  fornecedores: [
    { id: 'f-zeflex', name: 'ZEFLEX HIDRAULICA LTDA', cnpj_cpf: '18.758.137/0002-56' },
    { id: 'f-via', name: 'VIA S.A.', cnpj_cpf: '33.041.260/0652-90' },
    { id: 'f-coremma', name: 'COREMMA COMERCIO', trade_name: 'Itajai', cnpj_cpf: '11.111.111/0001-11' },
  ],
  favorecidos: [
    { id: 'p-roberto', name: 'Roberto Carlos da Silva', document: '111.222.333-44', bank_branch: '0001', bank_account: '12345-6' },
    { id: 'p-mickael', name: 'Mickael Souza', document: null },
  ],
  clientes: [
    { id: 'c-mp', name: 'MP MOTOR HOMES', cpf_cnpj: '44.051.448/0001-00' },
    { id: 'c-felipe', name: 'Felipe Antunes de Lima', cpf_cnpj: '116.742.049-73' },
    { id: 'c-acrisio', name: 'Acrisio Cançado Lopes', cpf_cnpj: '000.000.000-01' },
    { id: 'c-raul', name: 'Raul Schuchovsky', cpf_cnpj: null },
    { id: 'c-joao1', name: 'João Silva', cpf_cnpj: null },
    { id: 'c-joao2', name: 'João Silva', cpf_cnpj: null },
  ],
  historico: [
    // EQUIT pagou uma vez em nome do Acrisio.
    { documento: '04754513000149', lado: 'entrada', client_id: 'c-acrisio' },
    // CPF do Felipe nas SAÍDAS: duas vezes "VIA S.A." (erro antigo) e duas sem ninguém.
    { documento: '11674204973', lado: 'saida', supplier_id: 'f-via' },
    { documento: '11674204973', lado: 'saida', supplier_id: 'f-via' },
    { documento: '11674204973', lado: 'saida' },
    { documento: '11674204973', lado: 'saida' },
    // CPF do Ricardo: lançado uma vez com o fornecedor VIA S.A. (CNPJ) — erro antigo.
    { documento: '05380349986', lado: 'saida', supplier_id: 'f-via' },
    // TSD Logística: sempre sem cadastro.
    { documento: '90136409000122', lado: 'saida' },
  ],
};
const idx = indexarContrapartes(cadastro);

describe('identificarContraparte — entradas', () => {
  it('cliente pelo CNPJ, mesmo cadastrado depois (MP Motorhomes)', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'MP MOTORHOMES RVS ESTACIONAMENTO LTDA', counterparty_document: '44051448000100' }, idx);
    expect(r.cliente).toMatchObject({ id: 'c-mp', por: 'documento' });
    expect(r.cadastrar).toBeNull();
  });

  it('quem já pagou em nome de um cliente (EQUIT → Acrisio) SUGERE — e pede o SIM (leva 8, 22/10/2026)', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'EQUIT ADMINISTRACAO DE BENS LTDA', counterparty_document: '04754513000149' }, idx);
    expect(r.cliente).toMatchObject({ id: 'c-acrisio', por: 'historico' });
    expect(r.cliente?.detalhe).toMatch(/já pagou 1× em nome de Acrisio Cançado Lopes — confira/);
    // Todo histórico de entrada que chega aqui é de terceiro: a aprovação não usa o cliente sem o SIM.
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toBeNull();
  });

  it('nome parecido NÃO identifica o cliente (decisão do dono, 26/09/2026) — pergunta de quem é, sem "cadastrar"', () => {
    // "O sistema nunca pode sugerir ou lançar alguma transação com nomes diferentes."
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY NETO', counterparty_document: '03596447917' }, idx);
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toEqual({ documento: '03596447917', nome: 'RAUL SCHUCHOVSKY NETO', candidatos: [] });
    expect(frasesDaIdentificacao(r)).toContain('De quem é este pagamento? Nenhum cliente reconhecido pelo CPF/CNPJ nem pelo nome');
  });

  it('nome repetido em dois clientes não escolhe nenhum — e pergunta de quem é', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'JOAO SILVA', counterparty_document: '99988877766' }, idx);
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toEqual({ documento: '99988877766', nome: 'JOAO SILVA', candidatos: [] });
  });

  it('dinheiro que entra de um fornecedor é apontado (devolução?), não vira cliente — nem proposta de cadastrar cliente', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'ZEFLEX HIDRAULICA LTDA', counterparty_document: '18758137000256' }, idx);
    expect(r.cliente).toBeNull();
    expect(r.outroCadastro).toEqual({ tipo: 'fornecedor', id: 'f-zeflex', nome: 'ZEFLEX HIDRAULICA LTDA' });
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toMatchObject({ documento: '18758137000256', candidatos: [] });
  });

  it('entrada sem documento e sem nome (maquininha) fica como antes: sem pergunta gravada', () => {
    const r = identificarContraparte({ transaction_type: 'credit', description: 'PAGAMENTO RECEBIDO' }, idx);
    expect(r).toMatchObject({ cliente: null, cadastrar: null, deQuemE: null });
  });

  it('entrada sem documento, só com o nome: pergunta com o nome do extrato', () => {
    const r = identificarContraparte({ transaction_type: 'credit', description: 'Pix recebido de Fulano Beltrano' }, idx);
    expect(r.deQuemE).toEqual({ documento: null, nome: 'Fulano Beltrano', candidatos: [] });
  });
});

// ─── Pagadores conhecidos (leva 8, 22/10/2026) ───────────────────────────────────────────────────
// Quem costuma pagar por um cliente, guardado com o SIM do dono (pagadores_do_cliente, 'confirmado').
describe('pagador conhecido', () => {
  const base: CadastroParaIdentificar = {
    ...cadastro,
    clientes: [
      ...cadastro.clientes,
      { id: 'c-maria', name: 'Maria Teste', cpf_cnpj: '222.333.444-55' },
      { id: 'c-pedro', name: 'Pedro Teste', cpf_cnpj: null },
    ],
    pagadores: [
      // a empresa do Acrisio (EQUIT, matriz)
      { documento: '04754513000149', client_id: 'c-acrisio', relacao: 'empresa_do_cliente', confirmado_em: '2026-10-22T13:00:00Z' },
      // o cônjuge da Maria
      { documento: '55566677788', client_id: 'c-maria', relacao: 'conjuge', confirmado_em: '2026-10-22T02:30:00Z' },
      // a marina paga pelos dois
      { documento: '33444555000166', client_id: 'c-maria', relacao: 'marina', confirmado_em: '2026-10-20T12:00:00Z' },
      { documento: '33444555000166', client_id: 'c-pedro', relacao: 'marina', confirmado_em: '2026-10-20T12:00:00Z' },
      // pagador de cliente que não está no cadastro lido (inativo): ignorado
      { documento: '66677788899', client_id: 'c-inativo', relacao: 'parente', confirmado_em: '2026-10-20T12:00:00Z' },
    ],
  };
  const i = indexarContrapartes(base);

  it('de UM cliente: sugestão com o motivo, que pede o SIM', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'FULANO CONJUGE', counterparty_document: '555.666.777-88' }, i);
    expect(r.cliente).toMatchObject({ id: 'c-maria', nome: 'Maria Teste', por: 'pagador_conhecido', relacao: 'conjuge' });
    // 22/10 02:30 UTC é 21/10 em Brasília
    expect(r.cliente?.detalhe).toBe('Pago pelo cônjuge de Maria Teste, guardado por você em 21/10 — confira');
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
    expect(r.deQuemE).toBeNull();
    expect(r.cadastrar).toBeNull();
  });

  it('CNPJ pela raiz: a filial da empresa guardada também é ela', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'EQUIT FILIAL', counterparty_document: '04754513000230' }, i);
    expect(r.cliente).toMatchObject({ id: 'c-acrisio', por: 'pagador_conhecido' });
    expect(r.cliente?.detalhe).toMatch(/^Pago pela empresa de Acrisio Cançado Lopes, guardado por você em 22\/10/);
  });

  it('o pagador conhecido vem antes do histórico (o mesmo documento já pagou pelo Acrisio)', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_document: '04754513000149' }, i);
    expect(r.cliente?.por).toBe('pagador_conhecido');
  });

  it('de DOIS ou mais clientes (marina): ninguém é escolhido — a pergunta, com eles como candidatos', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'MARINA DO PORTO LTDA', counterparty_document: '33444555000166' }, i);
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toEqual({
      documento: '33444555000166', nome: 'MARINA DO PORTO LTDA',
      candidatos: [
        { id: 'c-maria', nome: 'Maria Teste', relacao: 'marina' },
        { id: 'c-pedro', nome: 'Pedro Teste', relacao: 'marina' },
      ],
    });
    expect(frasesDaIdentificacao(r)).toContain('De quem é este pagamento? Este CNPJ paga por mais de um cliente: Maria Teste, Pedro Teste');
  });

  it('o documento do PRÓPRIO cliente vence o pagador guardado', () => {
    const comConflito = indexarContrapartes({
      ...base,
      pagadores: [{ documento: '44051448000100', client_id: 'c-felipe', relacao: 'outro', confirmado_em: null }],
    });
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_document: '44051448000100' }, comConflito);
    expect(r.cliente).toMatchObject({ id: 'c-mp', por: 'documento' });
  });

  it('pagador de cliente inativo (fora do cadastro lido) não sugere ninguém', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'PARENTE DE INATIVO', counterparty_document: '66677788899' }, i);
    expect(r.cliente).toBeNull();
    expect(r.deQuemE).toMatchObject({ documento: '66677788899', candidatos: [] });
    expect(pagadoresDoDocumento(i, '66677788899')).toEqual([]);
  });

  it('saída nunca usa pagador (é só entrada)', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'FULANO CONJUGE', counterparty_document: '55566677788' }, i);
    expect(r.cliente).toBeNull();
    expect(r.deQuemE).toBeNull();
    expect(r.cadastrar).toEqual({ tipo: 'favorecido', documento: '55566677788', nome: 'FULANO CONJUGE' });
  });

  it('matriz e filial guardadas para o mesmo cliente contam uma vez', () => {
    const dup = indexarContrapartes({
      ...base,
      pagadores: [
        { documento: '04754513000149', client_id: 'c-acrisio', relacao: 'empresa_do_cliente' },
        { documento: '04754513000230', client_id: 'c-acrisio', relacao: 'empresa_do_cliente' },
      ],
    });
    expect(pagadoresDoDocumento(dup, '04754513000149')).toHaveLength(1);
    expect(identificarContraparte({ transaction_type: 'credit', counterparty_document: '04754513000149' }, dup).cliente?.por).toBe('pagador_conhecido');
  });
});

// ─── Simulação de 22/10/2026, P1: o cliente SEM documento que paga com o próprio CPF ─────────────────────────────
// O CPF dele cai no histórico (passo 3) antes do nome idêntico (passo 4). Quando os dois apontam o MESMO cliente, é o
// próprio cliente pagando — a prova é o nome idêntico, sem SIM, como era antes da leva 8. Nos outros casos o
// histórico continua pedindo o SIM.
describe('histórico × nome idêntico (P1)', () => {
  const comHistorico = (historico: CadastroParaIdentificar['historico']) => indexarContrapartes({ ...cadastro, historico });
  const CPF_DO_RAUL = '03596447917';

  it('cliente sem documento, nome idêntico e o histórico dele: nome idêntico, SEM pedir o SIM', () => {
    const i = comHistorico([
      { documento: CPF_DO_RAUL, lado: 'entrada', client_id: 'c-raul' },
      { documento: CPF_DO_RAUL, lado: 'entrada', client_id: 'c-raul' },
    ]);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL }, i);
    expect(r.cliente).toMatchObject({ id: 'c-raul', por: 'nome_identico' });
    expect(r.cliente?.detalhe).toBe('Nome idêntico ao do cliente Raul Schuchovsky (este CPF já pagou 2× em nome dele)');
    expect(clienteExigeSim(r.cliente?.por)).toBe(false);
    expect(r.deQuemE).toBeNull();
  });

  it('o mesmo histórico com OUTRO nome (terceiro pagando pelo Raul): continua histórico, pede o SIM', () => {
    const i = comHistorico([{ documento: CPF_DO_RAUL, lado: 'entrada', client_id: 'c-raul' }]);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY NETO', counterparty_document: CPF_DO_RAUL }, i);
    expect(r.cliente).toMatchObject({ id: 'c-raul', por: 'historico' });
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
  });

  it('nome idêntico a um cliente, mas o histórico do CPF é de OUTRO cliente: histórico dele, com SIM (nunca o nome)', () => {
    const i = comHistorico([{ documento: CPF_DO_RAUL, lado: 'entrada', client_id: 'c-felipe' }]);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL }, i);
    expect(r.cliente).toMatchObject({ id: 'c-felipe', por: 'historico' });
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
  });

  it('cliente COM documento e nome idêntico, pago por outro CPF (homônimo, MEI): histórico, com SIM', () => {
    const i = comHistorico([{ documento: '99911122233', lado: 'entrada', client_id: 'c-felipe' }]);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'FELIPE ANTUNES DE LIMA', counterparty_document: '99911122233' }, i);
    expect(r.cliente).toMatchObject({ id: 'c-felipe', por: 'historico' });
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
  });

  it('nome repetido em dois clientes sem documento: o nome não escolhe — fica o histórico, com SIM', () => {
    const i = comHistorico([{ documento: '88877766655', lado: 'entrada', client_id: 'c-joao1' }]);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'JOAO SILVA', counterparty_document: '88877766655' }, i);
    expect(r.cliente).toMatchObject({ id: 'c-joao1', por: 'historico' });
  });
});

// ─── O "não" do dono (revisão de 23/10/2026): pagador RECUSADO ou PAUSADO para um cliente ─────────────────────────
// recusar_pagadores_do_cliente e decidir_pagador_do_cliente prometem "não volta a ser sugerido" / "deixa de ser
// sugerido até o administrador reativar". O motor cumpre: aquele cliente nunca é sugerido para aquele documento — nem
// como pagador conhecido, nem pelo histórico unânime, nem pelo nome idêntico. A linha pergunta "de quem é?".
describe('veto do dono (pagador recusado ou pausado)', () => {
  const CPF_DO_RAUL = '03596447917';
  const comVeto = (extra: Partial<CadastroParaIdentificar>) => indexarContrapartes({
    ...cadastro,
    clientes: [...cadastro.clientes, { id: 'c-maria', name: 'Maria Teste', cpf_cnpj: '222.333.444-55' }],
    ...extra,
  });

  it('histórico unânime (EQUIT → Acrisio) com o par RECUSADO: não sugere — pergunta, e diz por quê', () => {
    const i = comVeto({ vetados: [{ documento: '04754513000149', client_id: 'c-acrisio', situacao: 'recusado' }] });
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'EQUIT ADMINISTRACAO DE BENS LTDA', counterparty_document: '04754513000149' }, i);
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toEqual({
      documento: '04754513000149', nome: 'EQUIT ADMINISTRACAO DE BENS LTDA', candidatos: [],
      vetados: [{ id: 'c-acrisio', nome: 'Acrisio Cançado Lopes', situacao: 'recusado' }],
    });
    expect(frasesDaIdentificacao(r)).toContain('Você recusou este CNPJ como pagador de Acrisio Cançado Lopes: Acrisio Cançado Lopes não é sugerido');
  });

  it('CNPJ pela raiz: o "não" dado para a filial vale para a matriz', () => {
    const i = comVeto({ vetados: [{ documento: '04754513000230', client_id: 'c-acrisio', situacao: 'pausado' }] });
    expect(vetoDoPagador(i, '04754513000149', 'c-acrisio')).toBe('pausado');
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_document: '04754513000149' }, i);
    expect(r.cliente).toBeNull();
    expect(r.deQuemE?.vetados).toEqual([{ id: 'c-acrisio', nome: 'Acrisio Cançado Lopes', situacao: 'pausado' }]);
  });

  it('P1 (cliente sem documento, nome idêntico e o histórico dele) com o par vetado: pergunta, sem o nome idêntico', () => {
    const historico = [{ documento: CPF_DO_RAUL, lado: 'entrada' as const, client_id: 'c-raul' }];
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL },
      comVeto({ historico, vetados: [{ documento: CPF_DO_RAUL, client_id: 'c-raul', situacao: 'recusado' }] }));
    expect(r.cliente).toBeNull();
    expect(r.deQuemE?.vetados?.map((v) => v.id)).toEqual(['c-raul']);
  });

  it('nome idêntico de um cliente vetado para este CPF não identifica (sem histórico)', () => {
    const tx = { transaction_type: 'credit' as const, counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL };
    expect(identificarContraparte(tx, comVeto({})).cliente).toMatchObject({ id: 'c-raul', por: 'nome_identico' });
    const r = identificarContraparte(tx, comVeto({ vetados: [{ documento: CPF_DO_RAUL, client_id: 'c-raul', situacao: 'pausado' }] }));
    expect(r.cliente).toBeNull();
    expect(frasesDaIdentificacao(r)).toContain('Você pausou este CPF como pagador de Raul Schuchovsky: Raul Schuchovsky não é sugerido até o administrador reativar');
  });

  it('pagador conhecido: o cliente vetado sai dos pagadores e dos candidatos; sobra um, ele é a sugestão (com SIM)', () => {
    const MARINA = '33444555000166';
    const i = comVeto({
      clientes: [...cadastro.clientes, { id: 'c-maria', name: 'Maria Teste', cpf_cnpj: '222.333.444-55' }, { id: 'c-pedro', name: 'Pedro Teste', cpf_cnpj: null }],
      pagadores: [
        { documento: MARINA, client_id: 'c-maria', relacao: 'marina' },
        { documento: MARINA, client_id: 'c-pedro', relacao: 'marina' },
      ],
      vetados: [{ documento: '33444555000247', client_id: 'c-pedro', situacao: 'recusado' }],
    });
    expect(pagadoresDoDocumento(i, MARINA).map((p) => p.cliente.id)).toEqual(['c-maria']);
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'MARINA DO PORTO LTDA', counterparty_document: MARINA }, i);
    expect(r.cliente).toMatchObject({ id: 'c-maria', por: 'pagador_conhecido' });
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
  });

  it('o histórico vetado não deixa o nome idêntico de OUTRO cliente decidir (a linha pergunta)', () => {
    const historico = [{ documento: '77766655544', lado: 'entrada' as const, client_id: 'c-felipe' }];
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: '77766655544' },
      comVeto({ historico, vetados: [{ documento: '77766655544', client_id: 'c-felipe', situacao: 'recusado' }] }));
    expect(r.cliente).toBeNull();
    expect(r.deQuemE).toMatchObject({ candidatos: [], vetados: [{ id: 'c-felipe' }] });
  });

  it('o documento do PRÓPRIO cliente vence o veto (passo 1); a saída nem olha veto', () => {
    const i = comVeto({ vetados: [{ documento: '44051448000100', client_id: 'c-mp', situacao: 'recusado' }] });
    expect(identificarContraparte({ transaction_type: 'credit', counterparty_document: '44051448000100' }, i).cliente)
      .toMatchObject({ id: 'c-mp', por: 'documento' });
    const saida = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'X', counterparty_document: '11122233344' },
      comVeto({ vetados: [{ documento: '11122233344', client_id: 'c-felipe', situacao: 'recusado' }] }));
    expect(saida.favorecido).toMatchObject({ id: 'p-roberto', por: 'documento' });
    expect(saida.deQuemE).toBeNull();
  });

  it('recusado vence pausado na mesma chave; situação desconhecida ou documento torto não vetam', () => {
    const i = comVeto({
      vetados: [
        { documento: '04754513000149', client_id: 'c-acrisio', situacao: 'recusado' },
        { documento: '04754513000230', client_id: 'c-acrisio', situacao: 'pausado' },
        { documento: '55566677788', client_id: 'c-maria', situacao: 'proposto' },
        { documento: '123', client_id: 'c-maria', situacao: 'recusado' },
      ],
    });
    expect(vetoDoPagador(i, '04754513000149', 'c-acrisio')).toBe('recusado');
    expect(vetoDoPagador(i, '55566677788', 'c-maria')).toBeNull();
    expect(vetoDoPagador(i, '123', 'c-maria')).toBeNull();
    expect(vetoDoPagador(i, '04754513000149', null)).toBeNull();
  });

  it('sem a leitura dos pagadores (pagadoresIndisponiveis): o histórico do cliente sem documento pede o SIM', () => {
    const historico = [{ documento: CPF_DO_RAUL, lado: 'entrada' as const, client_id: 'c-raul' }];
    const tx = { transaction_type: 'credit' as const, counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL };
    expect(identificarContraparte(tx, comVeto({ historico })).cliente?.por).toBe('nome_identico');
    const r = identificarContraparte(tx, comVeto({ historico, pagadoresIndisponiveis: true }));
    expect(r.cliente).toMatchObject({ id: 'c-raul', por: 'historico' });
    expect(clienteExigeSim(r.cliente?.por)).toBe(true);
  });

  it('sem a leitura dos pagadores: o NOME IDÊNTICO não identifica sozinho — vira a pergunta, com o cliente candidato', () => {
    // Revisão de 23/10/2026, item 4: sem saber o que o dono vetou, nome_identico (que a aprovação usa sem o SIM) não sai.
    const tx = { transaction_type: 'credit' as const, counterparty_name: 'RAUL SCHUCHOVSKY', counterparty_document: CPF_DO_RAUL };
    expect(identificarContraparte(tx, comVeto({})).cliente).toMatchObject({ id: 'c-raul', por: 'nome_identico' });
    const r = identificarContraparte(tx, comVeto({ pagadoresIndisponiveis: true }));
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toBeNull();
    expect(r.deQuemE).toEqual({
      documento: CPF_DO_RAUL, nome: 'RAUL SCHUCHOVSKY',
      candidatos: [{ id: 'c-raul', nome: 'Raul Schuchovsky', relacao: RELACAO_DO_NOME_IDENTICO }],
    });
    expect(frasesDaIdentificacao(r)).toContain(
      'De quem é este pagamento? O nome é idêntico ao do cliente Raul Schuchovsky, mas não deu para conferir os pagadores que você guardou agora — confirme o cliente');
    // Sem documento no extrato não há veto a conferir (o veto é por documento): o nome idêntico decide como sempre.
    const semDoc = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY' }, comVeto({ pagadoresIndisponiveis: true }));
    expect(semDoc.cliente).toMatchObject({ id: 'c-raul', por: 'nome_identico' });
    // O documento do próprio cliente continua identificando (passo 1 não depende dos pagadores).
    expect(identificarContraparte({ transaction_type: 'credit', counterparty_document: '44051448000100' }, comVeto({ pagadoresIndisponiveis: true })).cliente)
      .toMatchObject({ id: 'c-mp', por: 'documento' });
  });

  it('a frase do veto', () => {
    expect(fraseDoVeto('recusado', 'CPF', 'X')).toBe('Você recusou este CPF como pagador de X: X não é sugerido');
    expect(fraseDoVeto('pausado', 'CNPJ', 'X')).toBe('Você pausou este CNPJ como pagador de X: X não é sugerido até o administrador reativar');
  });
});

describe('clienteExigeSim, frasePagoPor e documentoMascarado', () => {
  it('só vínculo, pagador conhecido e histórico pedem o SIM', () => {
    for (const por of ['vinculo', 'pagador_conhecido', 'historico']) expect(clienteExigeSim(por)).toBe(true);
    for (const por of ['documento', 'nome_identico', 'regra', 'conta_bancaria', null, undefined]) expect(clienteExigeSim(por)).toBe(false);
  });

  it('a frase de cada relação', () => {
    expect(frasePagoPor('empresa_do_cliente', 'X')).toBe('Pago pela empresa de X');
    expect(frasePagoPor('conjuge', 'X')).toBe('Pago pelo cônjuge de X');
    expect(frasePagoPor('parente', 'X')).toBe('Pago por um parente de X');
    expect(frasePagoPor('marina', 'X')).toBe('Pago pela marina de X');
    expect(frasePagoPor('seguradora', 'X')).toBe('Pago pela seguradora de X');
    expect(frasePagoPor('outro', 'X')).toBe('Pago por quem costuma pagar por X');
    expect(RELACOES_DO_PAGADOR.map((r) => ROTULO_DA_RELACAO[r])).toEqual(['Empresa do cliente', 'Cônjuge', 'Parente', 'Marina', 'Seguradora', 'Outro']);
  });

  it('CPF de terceiro mascarado; CNPJ inteiro; resto nulo', () => {
    expect(documentoMascarado('123.456.789-01')).toBe('***.456.789-**');
    expect(documentoMascarado('04754513000149')).toBe('04.754.513/0001-49');
    expect(documentoMascarado('2559947000324')).toBe('02.559.947/0003-24');
    expect(documentoMascarado('123')).toBeNull();
    expect(documentoMascarado(null)).toBeNull();
  });
});

// ─── CPF dentro do NOME (revisão de 23/10/2026, item 3 — LGPD) ─────────────────────────────────────────────────
describe('nomeSemCpf', () => {
  it('CPF solto ou formatado dentro do nome vira ***.456.789-**; CNPJ, valor, data e o resto ficam', () => {
    expect(nomeSemCpf('12345678901-MARIA SOUZA')).toBe('***.456.789-**-MARIA SOUZA');
    expect(nomeSemCpf('JOAO PRESTADOR 98765432100')).toBe('JOAO PRESTADOR ***.654.321-**');
    expect(nomeSemCpf('Quem enviou (CPF/CNPJ 123.456.789-01) não é X')).toBe('Quem enviou (CPF/CNPJ ***.456.789-**) não é X');
    expect(nomeSemCpf('12345678901 98765432100')).toBe('***.456.789-** ***.654.321-**');
    for (const fica of ['12.345.678/0001-99', '12345678000199', 'R$ 1.500,00 em 12/10/2026', 'PIX 2026-10-12', 'MEI 12.345.678 JOAO', '1234567890123']) {
      expect(nomeSemCpf(fica)).toBe(fica);
    }
    expect(nomeSemCpf(null)).toBeNull();
    expect(nomeSemCpf(undefined)).toBeUndefined();
  });

  it('o mascarado de um CPF no nome é o mesmo do documentoMascarado (a mesma pessoa, o mesmo texto)', () => {
    expect(nomeSemCpf('12345678901')).toBe(documentoMascarado('12345678901'));
  });
});

// ─── O cliente da proposta ainda pede o SIM? (revisão de 23/10/2026, item 2) ───────────────────────────────────
// A anotação do dono ("o Pix de 1.500 é da TSD") troca o cliente sugerido e mantém a prova antiga do motor.
describe('clienteDaPropostaExigeSim', () => {
  const prova = (id: string, por: string) => ({ id, nome: 'Fulano', por });

  it('pede o SIM só com sugerido = cliente da prova, e prova que pede o SIM', () => {
    for (const por of ['pagador_conhecido', 'historico', 'vinculo']) expect(clienteDaPropostaExigeSim('c1', prova('c1', por))).toBe(true);
    for (const por of ['documento', 'nome_identico', 'regra']) expect(clienteDaPropostaExigeSim('c1', prova('c1', por))).toBe(false);
    expect(clienteDaPropostaExigeSim(null, prova('c1', 'historico'))).toBe(false);
    expect(clienteDaPropostaExigeSim('c1', null)).toBe(false);
  });

  it('cliente da prova diferente do sugerido: nunca "Sim, é do <prova>" (false) — se vale ou não, diz situacaoDoClienteSugerido', () => {
    expect(clienteDaPropostaExigeSim('c-tsd', prova('c-acrisio', 'pagador_conhecido'))).toBe(false);
    expect(clienteDaPropostaExigeSim('c-tsd', prova('c-acrisio', 'pagador_conhecido'), { os_id: null })).toBe(false);
    // sem anotação em vigor, o sugerido não vale: escolher (4ª rodada)
    expect(situacaoDoClienteSugerido('c-tsd', prova('c-acrisio', 'pagador_conhecido'))).toBe('escolher');
  });

  it('a anotação que DISSE o cliente é o SIM; a que não disse, não', () => {
    // disse este cliente
    expect(clienteDaPropostaExigeSim('c1', prova('c1', 'historico'), { cliente_id: 'c1' })).toBe(false);
    // OS anotada (numa entrada o cliente é o da OS)
    expect(clienteDaPropostaExigeSim('c1', prova('c1', 'pagador_conhecido'), { os_id: 'os-60' })).toBe(false);
    // disse outro cliente (o sugerido não é o da anotação): continua pedindo
    expect(clienteDaPropostaExigeSim('c1', prova('c1', 'historico'), { cliente_id: 'c2' })).toBe(true);
    // só categoria/descrição: não disse quem é
    expect(clienteDaPropostaExigeSim('c1', prova('c1', 'pagador_conhecido'), { cliente_id: null, os_id: null })).toBe(true);
    expect(clienteDaPropostaExigeSim('c1', prova('c1', 'pagador_conhecido'), null)).toBe(true);
  });
});

// ─── Revisão de 23/10/2026, 4ª rodada (A): o sugerido que NÃO é o da prova só vale com a anotação que o disse ──────────
// Desligar o comprovante desfaz a anotação: a marca sai da evidência e o sugerido fica. Sem anotação em vigor (desfeita,
// leitura que falhou), ninguém resolveu de quem é — a aprovação não usa nenhum cliente sem a escolha do dono.
describe('situacaoDoClienteSugerido', () => {
  const prova = (id: string, por: string) => ({ id, nome: 'Fulano', por });

  it('sem sugerido: sem_sugestao', () => {
    expect(situacaoDoClienteSugerido(null, prova('c1', 'historico'))).toBe('sem_sugestao');
    expect(situacaoDoClienteSugerido(undefined, null)).toBe('sem_sugestao');
  });

  it('ids iguais: vale pela prova que não pede o SIM; pede_sim pela que pede — a anotação lida com o cliente é o SIM', () => {
    for (const por of ['documento', 'nome_identico', 'regra']) expect(situacaoDoClienteSugerido('c1', prova('c1', por))).toBe('vale');
    for (const por of ['pagador_conhecido', 'historico', 'vinculo']) expect(situacaoDoClienteSugerido('c1', prova('c1', por))).toBe('pede_sim');
    expect(situacaoDoClienteSugerido('c1', prova('c1', 'historico'), { cliente_id: 'c1', os_id: null })).toBe('vale');
    expect(situacaoDoClienteSugerido('c1', prova('c1', 'historico'), { os_id: 'os-60' })).toBe('vale');
    // a marca {id} sobre o MESMO cliente da prova (sem a leitura) não basta: errar para o lado da pergunta
    expect(situacaoDoClienteSugerido('c1', prova('c1', 'historico'), { id: 'a-1' })).toBe('pede_sim');
  });

  it('anotação com o cliente (lida) ou com a OS: o sugerido que não é o da prova vale', () => {
    expect(situacaoDoClienteSugerido('c-tsd', prova('c-acrisio', 'pagador_conhecido'), { cliente_id: 'c-tsd', os_id: null })).toBe('vale');
    expect(situacaoDoClienteSugerido('c-tsd', prova('c-acrisio', 'pagador_conhecido'), { cliente_id: null, os_id: 'os-60' })).toBe('vale');
    expect(situacaoDoClienteSugerido('c-tsd', null, { cliente_id: 'c-tsd', os_id: null })).toBe('vale');
    // a tela, que só tem a marca da evidência ({id}): a anotação em vigor é quem pôs o sugerido
    expect(situacaoDoClienteSugerido('c-tsd', prova('c-acrisio', 'pagador_conhecido'), { id: 'a-1' })).toBe('vale');
    expect(situacaoDoClienteSugerido('c-tsd', null, { id: 'a-1' })).toBe('vale');
  });

  it('anotação desfeita, que falhou na leitura, que não disse o cliente ou que disse outro: escolher', () => {
    const outro = prova('c-acrisio', 'pagador_conhecido');
    expect(situacaoDoClienteSugerido('c-tsd', outro)).toBe('escolher');                       // desfeita (sem marca)
    expect(situacaoDoClienteSugerido('c-tsd', outro, null)).toBe('escolher');                 // leitura que falhou
    expect(situacaoDoClienteSugerido('c-tsd', outro, { cliente_id: null, os_id: null })).toBe('escolher'); // só categoria
    expect(situacaoDoClienteSugerido('c-tsd', outro, { cliente_id: 'c-outro', os_id: null })).toBe('escolher');
    expect(situacaoDoClienteSugerido('c-tsd', prova('c-acrisio', 'documento'))).toBe('escolher'); // qualquer prova de outro
    expect(situacaoDoClienteSugerido('c-tsd', null)).toBe('escolher');                        // sem prova nenhuma
    // e nunca vira "Sim, é do <prova>"
    expect(clienteDaPropostaExigeSim('c-tsd', outro, null)).toBe(false);
  });
});

// ─── A pergunta "de quem é?" que sobra (revisão de 23/10/2026, item 5) ─────────────────────────────────────────
describe('perguntaDeQuemEValida', () => {
  const deQuemE = { documento: '12345678901', nome: 'MARIA', candidatos: [] };

  it('sem cliente resolvido, a pergunta vale (com candidatos e vetados como gravados)', () => {
    expect(perguntaDeQuemEValida({ suggested_client_id: null, evidencia: { deQuemE } })).toEqual(deQuemE);
    const comVetado = { ...deQuemE, vetados: [{ id: 'c1', nome: 'X', situacao: 'recusado' as const }] };
    expect(perguntaDeQuemEValida({ evidencia: { deQuemE: comVetado } })).toEqual(comVetado);
  });

  it('anotação do dono ou override gravado (suggested_client_id, sem prova do motor): a pergunta é sobra', () => {
    expect(perguntaDeQuemEValida({ suggested_client_id: 'c-tsd', evidencia: { deQuemE } })).toBeNull();
  });

  it('"É cliente novo" (cadastro pela linha: cliente na prova, por documento): a pergunta é sobra', () => {
    expect(perguntaDeQuemEValida({
      suggested_client_id: 'c-novo', evidencia: { deQuemE, cliente: { id: 'c-novo', nome: 'MARIA', por: 'documento' } },
    })).toBeNull();
  });

  it('linha antiga (motor 2) com cadastrar de CLIENTE vira a mesma pergunta; cadastrar de saída não', () => {
    expect(perguntaDeQuemEValida({ evidencia: { cadastrar: { tipo: 'cliente', documento: '12345678000199', nome: 'MARINA X' } } }))
      .toEqual({ documento: '12345678000199', nome: 'MARINA X', candidatos: [] });
    expect(perguntaDeQuemEValida({ evidencia: { cadastrar: { tipo: 'fornecedor', documento: '12345678000199', nome: 'X' } } })).toBeNull();
    expect(perguntaDeQuemEValida(null)).toBeNull();
    expect(perguntaDeQuemEValida({ evidencia: null })).toBeNull();
  });
});

describe('identificarContraparte — saídas', () => {
  it('fornecedor pelo CNPJ', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'ZEFLEX HIDRAULICA LTDA', counterparty_document: '18758137000256' }, idx);
    expect(r.fornecedor).toMatchObject({ id: 'f-zeflex', por: 'documento' });
  });

  it('favorecido pelo CPF e pela conta bancária — nome parecido não (decisão do dono, 26/09/2026)', () => {
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_document: '11122233344' }, idx).favorecido)
      .toMatchObject({ id: 'p-roberto', por: 'documento' });
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_name: 'R C SILVA', counterparty_branch: '1', counterparty_account: '123456' }, idx).favorecido)
      .toMatchObject({ id: 'p-roberto', por: 'conta_bancaria' });
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_name: 'MICKAEL SOUZA SANTOS' }, idx).favorecido)
      .toBeNull();
  });

  it('histórico dividido não decide (CPF do Felipe já foi "VIA S.A." e ninguém)', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_document: '11674204973' }, idx);
    expect(r.fornecedor).toBeNull();
    expect(r.favorecido).toBeNull();
    // Mas diz de quem é o CPF, e oferece cadastrar como favorecido com o nome certo.
    expect(r.outroCadastro).toMatchObject({ tipo: 'cliente', nome: 'Felipe Antunes de Lima' });
    expect(r.nomeConhecido).toBe('Felipe Antunes de Lima');
    expect(r.cadastrar).toEqual({ tipo: 'favorecido', documento: '11674204973', nome: 'Felipe Antunes de Lima' });
  });

  it('CNPJ sem cadastro sugere cadastrar fornecedor (TSD Logística)', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'TSD LOGISTICA E DISTRIBUIDORA LTDA', counterparty_document: '90136409000122' }, idx);
    expect(r.fornecedor).toBeNull();
    expect(r.cadastrar).toEqual({ tipo: 'fornecedor', documento: '90136409000122', nome: 'TSD LOGISTICA E DISTRIBUIDORA LTDA' });
  });

  it('compra de maquininha sem documento não vira sugestão de cadastro', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'LMGCONFEITARIA' }, idx);
    expect(r.cadastrar).toBeNull();
  });

  it('a trava Coremma: nome fantasia com nome de cidade não sequestra estabelecimento', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'PREMEL - ITAJAI' }, idx);
    expect(r.fornecedor).toBeNull();
  });
});

describe('nomeLimpo e frases', () => {
  it('tira o CNPJ que o MEI põe no começo do nome', () => {
    expect(nomeLimpo('65.010.587 CRISLAINE REGINA CIOLI')).toBe('CRISLAINE REGINA CIOLI');
  });
  it('as frases dizem por que', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_document: '44051448000100' }, idx);
    expect(frasesDaIdentificacao(r)).toContain('CNPJ confere com o cliente MP MOTOR HOMES');
  });

  it('histórico não liga CPF a fornecedor de CNPJ (Ricardo ≠ VIA S.A.)', () => {
    const r = identificarContraparte({ transaction_type: 'debit', description: 'Pix enviado para Ricardo Amaral Do Nascimento', counterparty_document: '05380349986' }, idx);
    expect(r.fornecedor).toBeNull();
    expect(r.cadastrar).toEqual({ tipo: 'favorecido', documento: '05380349986', nome: 'Ricardo Amaral Do Nascimento' });
  });
  it('nome dentro da descrição do Nubank', () => {
    expect(nomeDaDescricao('Pix enviado para JOSE CARLOS ABEL')).toBe('JOSE CARLOS ABEL');
    expect(nomeDaDescricao('Pix recebido de Juliano Jacinto da Silva')).toBe('Juliano Jacinto da Silva');
    expect(nomeDaDescricao('DEBITO DE CARTAO')).toBeNull();
  });
});

describe("homônimo não é a mesma pessoa (decisão do dono, 26/09/2026)", () => {
  it("documento que contradiz: CPF×CNPJ, raiz de CNPJ diferente, CPF diferente", () => {
    expect(documentoContradiz("11122233344", "11.111.111/0001-11")).toBe(true);
    expect(documentoContradiz("11111111000299", "11.111.111/0001-11")).toBe(false); // filial da mesma empresa
    expect(documentoContradiz("22222222000111", "11.111.111/0001-11")).toBe(true);
    expect(documentoContradiz("11122233344", "111.222.333-45")).toBe(true);
    expect(documentoContradiz("11122233344", null)).toBe(false);
    expect(documentoContradiz("", "111.222.333-44")).toBe(false);
  });

  it("nome idêntico ao do favorecido, mas CPF de outra pessoa: não reconhece, oferece cadastrar", () => {
    const r = identificarContraparte({ transaction_type: "debit", counterparty_name: "ROBERTO CARLOS DA SILVA", counterparty_document: "99988877766" }, idx);
    expect(r.favorecido).toBeNull();
    expect(r.cadastrar).toMatchObject({ tipo: "favorecido", documento: "99988877766" });
  });

  it("nome idêntico sem documento no extrato continua valendo", () => {
    const r = identificarContraparte({ transaction_type: "debit", counterparty_name: "ROBERTO CARLOS DA SILVA" }, idx);
    expect(r.favorecido).toMatchObject({ id: "p-roberto", por: "nome_identico" });
  });
});

describe("anotação entre parênteses no cadastro não é nome", () => {
  it("Thaline Soares Mendonça (Lisiane) é a THALINE SOARES MENDONÇA do Pix", () => {
    expect(nomeLimpo("Thaline Soares Mendonça (Lisiane)")).toBe("THALINE SOARES MENDONCA");
    const i = indexarContrapartes({ fornecedores: [], clientes: [], historico: [],
      favorecidos: [{ id: "p-thaline", name: "Thaline Soares Mendonça (Lisiane)", document: null }] });
    expect(identificarContraparte({ transaction_type: "debit", counterparty_name: "THALINE SOARES MENDONÇA" }, i).favorecido)
      .toMatchObject({ id: "p-thaline", por: "nome_identico" });
  });
});

describe("documento com o zero comido, conta e histórico que contradizem (revisão de 26/09/2026)", () => {
  it("CNPJ com 13 dígitos e CPF com 10 são o mesmo documento", () => {
    expect(documentoNormalizado("2559947000324")).toBe("02559947000324");
    expect(documentoNormalizado("1234567890")).toBe("01234567890");
    expect(documentoContradiz("2559947000324", "02.559.947/0003-24")).toBe(false);
    const i = indexarContrapartes({ fornecedores: [{ id: "f-c", name: "CORREA", cnpj_cpf: "2559947000324" }], favorecidos: [], clientes: [], historico: [] });
    expect(identificarContraparte({ transaction_type: "debit", counterparty_name: "X", counterparty_document: "02559947000324" }, i).fornecedor)
      .toMatchObject({ id: "f-c", por: "documento" });
  });

  it("número no começo do nome só sai quando tem forma de CNPJ", () => {
    expect(nomeLimpo("65.010.587 CRISLAINE REGINA CIOLI")).toBe("CRISLAINE REGINA CIOLI");
    expect(nomeLimpo("2 IRMAOS AUTO PECAS")).toBe("2 IRMAOS AUTO PECAS");
  });

  it("mesma agência e conta, mas CPF de outra pessoa: não é o favorecido", () => {
    const r = identificarContraparte({ transaction_type: "debit", counterparty_name: "FULANO", counterparty_document: "99988877766",
      counterparty_branch: "0001", counterparty_account: "12345-6" }, idx);
    expect(r.favorecido).toBeNull();
  });
});
