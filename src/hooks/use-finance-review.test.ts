// A outra perna da transferência (pedido do dono, 28/09/2026): a linha diz "saiu da X, entrou
// na Y". A leitura é à parte e pode falhar sem derrubar a fila — a linha só perde o destino.
import { describe, it, expect } from 'vitest';
import { idsDasOutrasPernas, juntarOutraPerna, type PropostaFinanceira } from './use-finance-review';

const proposta = (id: string, kind: string, related: string | null) =>
  ({ id, kind, related_transaction_id: related }) as unknown as PropostaFinanceira;

describe('outra perna da transferência', () => {
  it('pede só as pernas das transferências, sem repetir', () => {
    const fila = [
      proposta('a', 'internal_transfer', 't2'),
      proposta('b', 'internal_transfer', 't2'),
      proposta('c', 'internal_transfer', 't9'),
      proposta('d', 'create_payable', 't7'),
      proposta('e', 'internal_transfer', null),
    ];
    expect(idsDasOutrasPernas(fila)).toEqual(['t2', 't9']);
  });

  it('pendura a perna lida; a que não veio fica sem destino; outras linhas não mudam', () => {
    const fila = [
      proposta('a', 'internal_transfer', 't2'),
      proposta('c', 'internal_transfer', 't9'),
      proposta('d', 'create_payable', 't7'),
    ];
    juntarOutraPerna(fila, [
      { id: 't2', source_type: 'bank', card_last_digits: null, bank_connection_id: 'nu', transaction_type: 'credit' },
      { id: 't7', source_type: 'bank', card_last_digits: null, bank_connection_id: 'c6', transaction_type: 'debit' },
    ]);
    expect(fila[0].outra_perna).toMatchObject({ bank_connection_id: 'nu', transaction_type: 'credit' });
    expect(fila[1].outra_perna).toBeNull();
    expect(fila[2].outra_perna).toBeUndefined();
  });
});
