import { describe, it, expect } from 'vitest';
import {
  parseOFX, parseCSV, parseFile, dedupeByRef, decodeStatementFile, detectFileSource,
} from '@/lib/bank-parser';
import { nomeNoHistorico } from '../../supabase/functions/_shared/banking/pluggy';

const ofxSGML = `
OFXHEADER:100
DATA:OFXSGML
ENCODING:USASCII
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20260715120000[-3:BRT]
<TRNAMT>1450.00
<FITID>2026071500001
<MEMO>PIX RECEBIDO E12345678202607151230ABCDEFGHIJK MARINA DO SOL LTDA 12.345.678/0001-90
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20260716
<TRNAMT>-289.90
<FITID>2026071600002
<MEMO>PAGAMENTO FORNECEDOR PE&amp;A NAUTICA
</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
`;

const ofxXML = `<?xml version="1.0" encoding="UTF-8"?>
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
  <STMTTRN>
    <TRNTYPE>CREDIT</TRNTYPE>
    <DTPOSTED>20260720100000</DTPOSTED>
    <TRNAMT>500.50</TRNAMT>
    <FITID>XML-001</FITID>
    <NAME>JOAO DA SILVA</NAME>
    <MEMO>TED RECEBIDA</MEMO>
  </STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>`;

describe('parseOFX', () => {
  it('extrai data, valor, tipo e identificador do formato SGML', () => {
    const txs = parseOFX(ofxSGML);
    expect(txs).toHaveLength(2);
    expect(txs[0]).toMatchObject({
      transaction_date: '2026-07-15',
      amount: 1450,
      transaction_type: 'credit',
      bank_ref_id: '2026071500001',
    });
    expect(txs[1]).toMatchObject({
      transaction_date: '2026-07-16',
      amount: 289.9,
      transaction_type: 'debit',
      bank_ref_id: '2026071600002',
    });
  });

  it('descarta hora e fuso do DTPOSTED', () => {
    expect(parseOFX(ofxSGML)[0].transaction_date).toBe('2026-07-15');
  });

  it('captura o EndToEndId do Pix para casar com cobranças emitidas', () => {
    expect(parseOFX(ofxSGML)[0].pix_end_to_end_id).toBe('E12345678202607151230ABCDEFGHIJK');
  });

  it('captura o CNPJ da contraparte quando aparece no histórico', () => {
    expect(parseOFX(ofxSGML)[0].counterparty_document).toBe('12345678000190');
  });

  it('decodifica entidades XML na descrição', () => {
    expect(parseOFX(ofxSGML)[1].description).toContain('PE&A NAUTICA');
  });

  it('lê o formato XML com tags de fechamento', () => {
    const txs = parseOFX(ofxXML);
    expect(txs).toHaveLength(1);
    expect(txs[0]).toMatchObject({
      transaction_date: '2026-07-20',
      amount: 500.5,
      transaction_type: 'credit',
      bank_ref_id: 'XML-001',
      counterparty_name: 'JOAO DA SILVA',
    });
  });

  it('respeita TRNTYPE DEBIT mesmo com valor positivo', () => {
    const ofx = `<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260701<TRNAMT>100.00<FITID>X1</STMTTRN>`;
    expect(parseOFX(ofx)[0].transaction_type).toBe('debit');
  });

  it('ignora lançamentos sem data ou valor utilizável', () => {
    const ofx = `<STMTTRN><DTPOSTED><TRNAMT>50.00<FITID>X2</STMTTRN>`
      + `<STMTTRN><DTPOSTED>20260701<TRNAMT>0.00<FITID>X3</STMTTRN>`;
    expect(parseOFX(ofx)).toHaveLength(0);
  });
});

describe('dedupeByRef', () => {
  it('remove repetições do mesmo identificador dentro do arquivo', () => {
    const dup = parseOFX(ofxSGML + ofxSGML);
    expect(dup).toHaveLength(4);
    expect(dedupeByRef(dup)).toHaveLength(2);
  });

  it('mantém linhas sem identificador, que não podem ser comparadas', () => {
    const semRef = [
      { transaction_date: '2026-07-01', description: 'A', amount: 10, transaction_type: 'debit' as const },
      { transaction_date: '2026-07-01', description: 'A', amount: 10, transaction_type: 'debit' as const },
    ];
    expect(dedupeByRef(semRef)).toHaveLength(2);
  });
});

describe('decodeStatementFile', () => {
  it('lê arquivo UTF-8 preservando acentos', () => {
    const buf = new TextEncoder().encode('TRANSFERÊNCIA RECEBIDA').buffer;
    expect(decodeStatementFile(buf)).toBe('TRANSFERÊNCIA RECEBIDA');
  });

  it('lê arquivo Latin-1 sem corromper acentos', () => {
    // "TRANSFERÊNCIA" em ISO-8859-1: Ê = 0xCA, Ê não é UTF-8 válido isolado.
    const latin1 = new Uint8Array([0x54, 0x52, 0x41, 0x4e, 0x53, 0x46, 0x45, 0x52, 0xca, 0x4e, 0x43, 0x49, 0x41]);
    expect(decodeStatementFile(latin1.buffer)).toBe('TRANSFERÊNCIA');
  });
});

describe('parseCSV', () => {
  it('lê CSV com ponto e vírgula e valor único assinado', () => {
    const csv = 'Data;Descrição;Valor\n15/07/2026;PIX RECEBIDO;1.450,00\n16/07/2026;TARIFA;-29,90';
    const txs = parseCSV(csv);
    expect(txs).toHaveLength(2);
    expect(txs[0]).toMatchObject({ transaction_date: '2026-07-15', amount: 1450, transaction_type: 'credit' });
    expect(txs[1]).toMatchObject({ transaction_date: '2026-07-16', amount: 29.9, transaction_type: 'debit' });
  });

  it('usa a coluna de identificador quando o banco a exporta', () => {
    const csv = 'Data,Descrição,Valor,Identificador\n2026-07-15,PIX,100.00,abc-123';
    expect(parseCSV(csv)[0].bank_ref_id).toBe('abc-123');
  });

  it('lê valores com separador de milhar nas duas convenções', () => {
    const br = parseCSV('Data;Descrição;Valor\n15/07/2026;A;1.450,00');
    const us = parseCSV('Data,Descrição,Valor\n2026-07-15,A,"1,450.00"');
    expect(br[0].amount).toBe(1450);
    expect(us[0].amount).toBe(1450);
  });

  it('preserva colunas quando a descrição entre aspas contém o delimitador', () => {
    const csv = 'Data,Descrição,Valor\n2026-07-15,"PAGAMENTO, PARCELA 2",250.00';
    const txs = parseCSV(csv);
    expect(txs).toHaveLength(1);
    expect(txs[0].description).toBe('PAGAMENTO, PARCELA 2');
    expect(txs[0].amount).toBe(250);
  });

  it('ignora linhas com data inválida', () => {
    const csv = 'Data;Descrição;Valor\nsaldo anterior;X;10,00\n15/07/2026;PIX;100,00';
    expect(parseCSV(csv)).toHaveLength(1);
  });
});

describe('detectFileSource / parseFile', () => {
  it('identifica fatura de cartão pelo nome do arquivo', () => {
    expect(detectFileSource('fatura-julho.ofx', '')).toBe('credit_card');
    expect(detectFileSource('extrato.ofx', '')).toBe('bank');
  });

  it('deduplica o arquivo já na leitura', () => {
    const { transactions, source_type } = parseFile(ofxSGML + ofxSGML, 'extrato.ofx');
    expect(transactions).toHaveLength(2);
    expect(source_type).toBe('bank');
  });
});

describe('nome da contraparte a partir do histórico', () => {
  // Existe porque o banco manda o CNPJ e deixa o nome vazio em parte das transações — o
  // nome costuma estar no próprio histórico, mas só quando ele não é a narração da
  // operação. Confundir os dois encheria o cadastro de "TRANSF ENVIADA PIX".
  it('aceita nome de pessoa e razão social', () => {
    expect(nomeNoHistorico('ACRISIO LOPES CANCADO FILHO')).toBe('ACRISIO LOPES CANCADO FILHO');
    expect(nomeNoHistorico('KAMELL COMERCIO GLOBAL LTDA')).toBe('KAMELL COMERCIO GLOBAL LTDA');
  });

  it('recusa a narração da operação', () => {
    for (const d of [
      'TRANSF ENVIADA PIX', 'PGTO FATURA CARTAO C6', 'CDB C6 LIM.GARANT.',
      'TARIFA MENSAL', 'IOF LIMITE CONTA', 'TRIBUTOS FEDERAIS DARF NUMERADO',
      'Vendas', 'Sem descrição', 'PAGAMENTO RECEBIDO',
    ]) {
      expect(nomeNoHistorico(d)).toBeNull();
    }
  });

  it('tira o rabicho de terminal de cartão', () => {
    expect(nomeNoHistorico('PREMEL - ITAJAI        ITAJAI        BRA')).toBe('PREMEL - ITAJAI');
    expect(nomeNoHistorico('LOJAS TAMOYO LTDA      ITAJAI        BRA')).toBe('LOJAS TAMOYO LTDA');
  });

  it('recusa vazio e ruído curto', () => {
    expect(nomeNoHistorico(null)).toBeNull();
    expect(nomeNoHistorico('  ')).toBeNull();
    expect(nomeNoHistorico('AB')).toBeNull();
  });
});
