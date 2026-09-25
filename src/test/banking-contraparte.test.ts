// Identificador único de contraparte — casos tirados da fila do Extrato de 25/09/2026.
//
// Antes: 3 de 47 saídas com fornecedor, 0 com favorecido, 1 de 24 entradas com cliente.
// Cada teste aqui é um desses casos, e a trava do caso Coremma (nome parecido nunca decide
// em silêncio) tem os seus.
import { describe, it, expect } from 'vitest';
import {
  indexarContrapartes, identificarContraparte, nomeLimpo, frasesDaIdentificacao, nomeDaDescricao,
  type CadastroParaIdentificar,
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

  it('quem já pagou em nome de um cliente (EQUIT → Acrisio)', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'EQUIT ADMINISTRACAO DE BENS LTDA', counterparty_document: '04754513000149' }, idx);
    expect(r.cliente).toMatchObject({ id: 'c-acrisio', por: 'historico' });
    expect(r.cliente?.detalhe).toMatch(/já pagou 1× em nome de Acrisio/);
  });

  it('nome parecido é sugestão marcada, nunca silenciosa (RAUL SCHUCHOVSKY NETO)', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'RAUL SCHUCHOVSKY NETO', counterparty_document: '03596447917' }, idx);
    expect(r.cliente).toMatchObject({ id: 'c-raul', por: 'nome_parecido' });
    expect(r.cliente?.detalhe).toMatch(/confira/);
  });

  it('nome repetido em dois clientes não escolhe nenhum — e sugere cadastrar', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'JOAO SILVA', counterparty_document: '99988877766' }, idx);
    expect(r.cliente).toBeNull();
    expect(r.cadastrar).toEqual({ tipo: 'cliente', documento: '99988877766', nome: 'JOAO SILVA' });
  });

  it('dinheiro que entra de um fornecedor é apontado (devolução?), não vira cliente', () => {
    const r = identificarContraparte({ transaction_type: 'credit', counterparty_name: 'ZEFLEX HIDRAULICA LTDA', counterparty_document: '18758137000256' }, idx);
    expect(r.cliente).toBeNull();
    expect(r.outroCadastro).toEqual({ tipo: 'fornecedor', id: 'f-zeflex', nome: 'ZEFLEX HIDRAULICA LTDA' });
  });
});

describe('identificarContraparte — saídas', () => {
  it('fornecedor pelo CNPJ', () => {
    const r = identificarContraparte({ transaction_type: 'debit', counterparty_name: 'ZEFLEX HIDRAULICA LTDA', counterparty_document: '18758137000256' }, idx);
    expect(r.fornecedor).toMatchObject({ id: 'f-zeflex', por: 'documento' });
  });

  it('favorecido pelo CPF, pela conta bancária e pelo nome parecido', () => {
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_document: '11122233344' }, idx).favorecido)
      .toMatchObject({ id: 'p-roberto', por: 'documento' });
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_name: 'R C SILVA', counterparty_branch: '1', counterparty_account: '123456' }, idx).favorecido)
      .toMatchObject({ id: 'p-roberto', por: 'conta_bancaria' });
    expect(identificarContraparte({ transaction_type: 'debit', counterparty_name: 'MICKAEL SOUZA SANTOS' }, idx).favorecido)
      .toMatchObject({ id: 'p-mickael', por: 'nome_parecido' });
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
