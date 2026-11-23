// "Lançados sozinhos" com a baixa pelo boleto (22/11/2026): a conta a desfazer é a casada com a linha do banco.
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import { comContaBaixada, type LancadoSozinho } from './use-extrato-conta';

const linha = (id: string, automatica: LancadoSozinho['automatica'], tx: string | null, criada: string | null = null): LancadoSozinho => ({
  id, title: `Despesa ${id}`, suggested_amount: 10, suggested_category: null, suggested_date: '2026-11-17',
  decided_at: '2026-11-22T10:00:00Z', decision_note: null, automatica, created_payable_id: criada, created_receivable_id: null,
  bank_transaction_id: tx,
});

describe('comContaBaixada', () => {
  it('a baixa pelo boleto ganha a conta casada com a linha do banco; as outras ficam como estavam', () => {
    const r = comContaBaixada(
      [linha('q1', 'boleto', 't1'), linha('q2', 'confianca', 't2', 'p2'), linha('q3', 'regra', 't3', 'p3')],
      [{ id: 'conta-1', bank_transaction_id: 't1' }],
    );
    expect(r.map((l) => [l.id, l.conta_baixada_id ?? null, l.created_payable_id])).toEqual([
      ['q1', 'conta-1', null], ['q2', null, 'p2'], ['q3', null, 'p3'],
    ]);
  });

  it('baixa já desfeita (nenhuma conta casada com a linha) sai da lista', () => {
    const r = comContaBaixada(
      [linha('q1', 'boleto', 't1'), linha('q2', 'boleto', 't-desfeita'), linha('q3', 'boleto', null)],
      [{ id: 'conta-1', bank_transaction_id: 't1' }, { id: 'solta', bank_transaction_id: null }],
    );
    expect(r.map((l) => l.id)).toEqual(['q1']);
  });
});
