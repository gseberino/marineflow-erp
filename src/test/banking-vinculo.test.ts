// Vínculo de uma linha do extrato com o que ela paga — casos de 25/09/2026.
import { describe, it, expect } from 'vitest';
import { sugerirVinculo, vinculoAutomatico, exigeDecisao } from '../../supabase/functions/_shared/banking/vinculo';
import type { BankTx, Candidate } from '../../supabase/functions/_shared/banking/types';

const entrada = (v: number, data: string, extra: Partial<BankTx> = {}): BankTx => ({
  id: 't', transaction_date: data, description: 'PIX RECEBIDO', amount: v, transaction_type: 'credit', ...extra,
});

describe('sugerirVinculo', () => {
  it('sinal já lançado à mão vira "casar", não receita nova (ORÇ-00084, R$ 591,41)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg1', label: 'Pagamento já lançado: Sinal — ORÇ-00084', amount: 591.41,
      direction: 'credit', dueDate: '2026-08-21', clientId: 'c-robson', clientName: 'ROBSON', receivableId: 'r84',
      serviceOrderId: 'os84', documentNumber: 'ORÇ-00084',
    }];
    const v = sugerirVinculo(entrada(591.41, '2026-08-20', { counterparty_name: 'POWER LOG LTDA', counterparty_document: '08878680000152' }), cands);
    expect(v?.principal).toMatchObject({ tipo: 'existing_payment', lancamentoId: 'r84', lado: 'receivable', jaLancado: true });
    // Valor exato, mas o pagador não é o cliente do orçamento: não decide sozinho…
    expect(vinculoAutomatico(v)).toBeNull();
    // …e por isso a aprovação às cegas é barrada: criaria a receita em dobro.
    expect(exigeDecisao(v)).toBe(true);
  });

  it('documento do cliente + valor exato é certeza e vale sozinho', () => {
    const cands: Candidate[] = [{
      kind: 'receivable', id: 'r1', label: 'Saldo — OS-00045', amount: 1650, direction: 'credit',
      dueDate: '2026-09-05', clientId: 'c-mp', clientName: 'MP MOTOR HOMES', clientDocument: '44.051.448/0001-00',
    }];
    const v = sugerirVinculo(entrada(1650, '2026-09-05', { counterparty_document: '44051448000100' }), cands);
    expect(v?.principal.nivel).toBe('certain');
    expect(vinculoAutomatico(v)?.lancamentoId).toBe('r1');
    expect(exigeDecisao(v)).toBe(false);
  });

  it('sinal de orçamento nunca é automático, nem com certeza', () => {
    const cands: Candidate[] = [{
      kind: 'quote_deposit', id: 'orc', label: 'Sinal do ORÇ-00104', amount: 2000, direction: 'credit',
      referenceDate: '2026-04-20', clientId: 'c', clientName: 'Cliente', clientDocument: '11122233344', convertsQuote: true,
    }];
    const v = sugerirVinculo(entrada(2000, '2026-04-30', { counterparty_document: '11122233344' }), cands);
    expect(v?.principal.converteOrcamento).toBe(true);
    expect(vinculoAutomatico(v)).toBeNull();
  });

  it('cliente reconhecido pelo histórico sobe na lista', () => {
    const cands: Candidate[] = [
      { kind: 'service_order_balance', id: 'os-a', label: 'Saldo da OS-1', amount: 3947.48, direction: 'credit', referenceDate: '2026-01-20', clientId: 'c-outro', clientName: 'Outro' },
      { kind: 'service_order_balance', id: 'os-b', label: 'Saldo da OS-2', amount: 3947.48, direction: 'credit', referenceDate: '2026-01-20', clientId: 'c-acrisio', clientName: 'Acrisio' },
    ];
    const v = sugerirVinculo(entrada(3947.48, '2026-02-06', { counterparty_name: 'EQUIT ADMINISTRACAO' }), cands, { id: 'c-acrisio', nome: 'Acrisio' });
    expect(v?.principal.id).toBe('os-b');
    expect(v?.principal.motivos.join(' ')).toMatch(/cliente reconhecido \(Acrisio\)/);
  });

  it('saída não casa com entrada, e cobrança avulsa não é vínculo acionável', () => {
    const cands: Candidate[] = [
      { kind: 'receivable', id: 'r', label: 'x', amount: 100, direction: 'credit' },
      { kind: 'collection', id: 'c', label: 'y', amount: 100, direction: 'credit' },
    ];
    expect(sugerirVinculo({ ...entrada(100, '2026-09-01'), transaction_type: 'debit' }, cands)).toBeNull();
    expect(sugerirVinculo(entrada(100, '2026-09-01'), [cands[1]])).toBeNull();
  });

  it('possível duplicata que o motor não reconhece (ORÇ-00077: R$ 2.520 lançado, R$ 2.498 no banco)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg77', label: 'Pagamento já lançado: Sinal — ORÇ-00077', amount: 2520,
      direction: 'credit', dueDate: '2026-08-11', clientId: 'c-final', clientName: 'Cliente Final', receivableId: 'r77',
    }];
    const v = sugerirVinculo(entrada(2498, '2026-08-06', { counterparty_name: 'EDSON LUIS KREUSCH', counterparty_document: '17635478000190' }), cands);
    expect(v?.principal).toMatchObject({ tipo: 'existing_payment', lancamentoId: 'r77', jaLancado: true });
    expect(v?.principal.motivos.join(' ')).toMatch(/possível duplicata/);
    expect(exigeDecisao(v)).toBe(true);
  });

  it('pagamento já lançado de um ano depois não é o mesmo dinheiro (STONE)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg61', label: 'Pagamento já lançado: Sinal — ORÇ-00061', amount: 5000,
      direction: 'credit', dueDate: '2026-07-01', receivableId: 'r61',
    }];
    expect(sugerirVinculo(entrada(5000, '2025-08-07', { counterparty_name: 'STONE CONFECCOES LTDA' }), cands)).toBeNull();
  });

  it('valor exato já lançado por terceiro barra a aprovação no escuro (ORÇ-00075)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg75', label: 'Pagamento já lançado: Sinal — ORÇ-00075', amount: 500,
      direction: 'credit', dueDate: '2026-08-12', clientId: 'c-lu', clientName: 'LUCENIRA MARIA DE MELO', clientDocument: '12345678901', receivableId: 'r75',
    }];
    const v = sugerirVinculo(entrada(500, '2026-08-16', { counterparty_name: 'MP MOTORHOMES', counterparty_document: '44051448000100' }), cands);
    expect(v?.principal.jaLancado).toBe(true);
    expect(exigeDecisao(v)).toBe(true);
  });
});
