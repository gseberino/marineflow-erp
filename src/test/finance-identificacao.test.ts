// Identificação da linha do Extrato com a regra de ENTRADA — "o Pix do CPF/CNPJ X é do cliente Y"
// (resposta 18 do dono, 26/09/2026): o cliente da regra vence o dono do documento, com a prova
// "regra sua", e continua sugestão.
import { describe, it, expect } from 'vitest';
import { identificarLinha, type ContextoDeIdentificacao } from '../../supabase/functions/finance-review/identificacao';
import { indexarContrapartes } from '../../supabase/functions/_shared/banking/contraparte';

const ctx: ContextoDeIdentificacao = {
  indice: indexarContrapartes({
    fornecedores: [], favorecidos: [], historico: [],
    clientes: [
      { id: 'c-joao', name: 'João da Silva', cpf_cnpj: '999.888.777-66' },
      { id: 'c-maria', name: 'MARIA SILVA', cpf_cnpj: '123.456.789-01' },
    ],
  }),
  candidatos: [],
  categoriaDoFavorecido: new Map(),
  drePorCategoria: new Map(),
};

// A Maria paga pelo barco do marido, o João.
const pixDaMaria = {
  id: 't1', transaction_date: '2026-09-24', description: 'PIX RECEBIDO', amount: 800,
  transaction_type: 'credit' as const, counterparty_name: 'MARIA SILVA', counterparty_document: '12345678901',
};
const proposta = {
  kind: 'create_receivable', suggestedCategory: 'Serviços prestados', dreGroup: 'receita',
  confidence: 95, appliedRuleId: 'r-in', suggestedSupplierId: null,
};

describe('regra de entrada na identificação', () => {
  it('o cliente da regra vence o dono do CPF, com a prova "regra sua"', () => {
    const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: 'c-joao' }, ctx);
    expect(l.clientId).toBe('c-joao');
    expect((l.evidencia as any).cliente).toMatchObject({ id: 'c-joao', nome: 'João da Silva', por: 'regra' });
    expect(l.frases.join(' · ')).toContain('Regra sua: este CPF/CNPJ é do cliente João da Silva');
  });

  it('sem regra, o CPF identifica quem pagou', () => {
    const l = identificarLinha(pixDaMaria, { ...proposta, appliedRuleId: null }, ctx);
    expect(l.clientId).toBe('c-maria');
    expect((l.evidencia as any).cliente).toMatchObject({ por: 'documento' });
  });

  it('cliente da regra que não existe mais não entra — vale o que o documento diz', () => {
    const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: 'c-apagado' }, ctx);
    expect(l.clientId).toBe('c-maria');
  });

  it('na saída, a regra de entrada não dá cliente a ninguém', () => {
    const l = identificarLinha({ ...pixDaMaria, transaction_type: 'debit' },
      { ...proposta, kind: 'create_payable', suggestedClientId: 'c-joao' }, ctx);
    expect(l.clientId).not.toBe('c-joao');
  });

  it('sem o contexto (leitura falhou), o cliente da regra ainda chega à entrada', () => {
    const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: 'c-joao' }, null);
    expect(l.clientId).toBe('c-joao');
  });
});
