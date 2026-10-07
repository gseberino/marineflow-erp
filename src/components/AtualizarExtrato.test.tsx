// "Atualizar extrato" no cabeçalho do Financeiro (06/10/2026): o botão e a idade do dado do banco.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { BankConnection } from '@/hooks/use-bank-connections';

const estado = vi.hoisted(() => ({ conexoes: [] as unknown[], chamadas: [] as unknown[] }));
vi.mock('@/hooks/use-bank-connections', () => ({
  useBankConnections: () => ({ data: estado.conexoes }),
  useSyncBank: () => ({
    isPending: false,
    mutateAsync: async (input: unknown) => {
      estado.chamadas.push(input);
      return { ok: true, message: '3 transação(ões) nova(s)', resultados: [] };
    },
  }),
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), warning: vi.fn(), error: vi.fn() } }));

import { AtualizarExtrato, conexoesBuscaveis, dadoMaisVelho, estaAtrasado, quandoFoi } from './AtualizarExtrato';

const conexao = (p: Partial<BankConnection>): BankConnection => ({
  id: 'c', provider: 'pluggy', external_id: 'x', label: 'C6', institution: null, account_kind: 'bank', active: true,
  last_synced_at: null, last_sync_status: 'ok', last_sync_message: null, last_sync_imported: 0, last_transaction_date: null, ...p,
});

describe('AtualizarExtrato', () => {
  beforeEach(() => { estado.conexoes = []; estado.chamadas = []; });

  it('sem conta de banco (só o Caixa), não aparece', () => {
    estado.conexoes = [conexao({ provider: 'caixa', label: 'Caixa' })];
    const { container } = render(<AtualizarExtrato />);
    expect(container.textContent).toBe('');
  });

  it('com conta de banco, mostra o botão e busca todas', async () => {
    estado.conexoes = [conexao({ provider_updated_at: '2026-10-06T12:00:00Z' })];
    render(<AtualizarExtrato />);
    await userEvent.click(screen.getByRole('button', { name: /Atualizar extrato/ }));
    expect(estado.chamadas).toEqual([{}]);
    expect(screen.getByTestId('idade-do-extrato').textContent).toContain('Bancos: dado de');
  });

  it('o selo usa o dado mais VELHO (é ele que diz o que pode faltar) e prefere a data do Pluggy', () => {
    const lista = [
      conexao({ label: 'C6', last_synced_at: '2026-10-06T18:00:00Z', provider_updated_at: '2026-10-05T09:00:00Z' }),
      conexao({ label: 'Nubank', last_synced_at: '2026-10-06T18:00:00Z', provider_updated_at: '2026-10-06T09:00:00Z' }),
      conexao({ label: 'Antiga', active: false, last_synced_at: '2026-01-01T00:00:00Z' }),
    ];
    expect(dadoMaisVelho(conexoesBuscaveis(lista))).toEqual({ iso: '2026-10-05T09:00:00Z', conta: 'C6' });
  });

  it('quandoFoi: hoje, ontem, amanhã e data', () => {
    const agora = new Date('2026-10-06T15:00:00Z');
    expect(quandoFoi('2026-10-06T12:00:00Z', agora)).toBe('hoje às 09:00');
    expect(quandoFoi('2026-10-05T12:00:00Z', agora)).toBe('ontem às 09:00');
    expect(quandoFoi('2026-10-07T12:00:00Z', agora)).toBe('amanhã às 09:00');
    expect(quandoFoi('2026-10-01T12:00:00Z', agora)).toBe('01/10 às 09:00');
    expect(quandoFoi(null, agora)).toBeNull();
  });

  it('mais de 36 h sem dado novo do banco = atrasado (aviso amarelo, também no celular)', () => {
    const agora = new Date('2026-10-07T12:00:00Z');
    expect(estaAtrasado('2026-10-06T12:00:00Z', agora)).toBe(false);
    expect(estaAtrasado('2026-10-05T23:00:00Z', agora)).toBe(true);
    expect(estaAtrasado(null, agora)).toBe(false);
    estado.conexoes = [conexao({ label: 'Nubank', provider_updated_at: '2026-09-30T12:00:00Z' })];
    render(<AtualizarExtrato />);
    const selo = screen.getByTestId('idade-do-extrato');
    expect(selo.getAttribute('data-atrasado')).toBe('sim');
    expect(selo.textContent).toContain('Nubank: sem dado novo desde');
  });
});
