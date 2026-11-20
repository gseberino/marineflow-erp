// "Agrupar para o cliente" F2: render de verdade da janela de aprovar (tsc/build não pegam TDZ), o plano vindo do banco
// (ensaio), o sinal de cada orçamento pela lib e a aprovação só dos marcados.
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const rpc = vi.fn();
const tabelas: Record<string, unknown[]> = {};
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpc(...a),
    from: (t: string) => ({
      select: () => ({ in: async () => ({ data: tabelas[t] ?? [], error: null }) }),
    }),
  },
}));
const { toast } = vi.hoisted(() => ({ toast: { success: vi.fn(), info: vi.fn(), error: vi.fn() } }));
vi.mock('sonner', () => ({ toast }));

import { AprovarConjuntoDialog } from './AprovarConjuntoDialog';
import { normalizarConjunto } from '@/lib/conjunto';

const conjunto = normalizarConjunto({
  id: 'c1', nome: 'OS-00104 + ORÇ-00140 + ORÇ-00141', ativo: true, principal_id: 'a',
  documentos: [
    { id: 'a', numero: 'OS-00104', tipo: 'os', status: 'scheduled', ativo: true, assinado: true, aprovavel: false },
    { id: 'b', numero: 'ORÇ-00140', tipo: 'orcamento', status: 'draft', quote_status: 'sent', ativo: true, aprovavel: true },
    { id: 'c', numero: 'ORÇ-00141', tipo: 'orcamento', status: 'draft', quote_status: 'draft', ativo: true, aprovavel: true },
  ],
})!;

function plano(ids: string[], ensaio: boolean) {
  const b = ids.includes('b');
  const c = ids.includes('c');
  return {
    ok: true, ensaio, conjunto_id: 'c1', nome: conjunto.nome, complementa: { id: 'a', numero: 'OS-00104' },
    aprovados: Number(b) + Number(c), viraram_os: Number(c), aguardando_sinal: Number(b),
    documentos: [
      { id: 'a', numero: 'OS-00104', numero_depois: 'OS-00104', situacao: 'assinado', acao: 'nao_muda', texto: 'OS-00104 já foi assinado: não muda.' },
      { id: 'b', numero: 'ORÇ-00140', numero_depois: 'ORÇ-00140', situacao: 'aprovar', acao: b ? 'aguardar_sinal' : 'nao_muda',
        texto: b ? 'ORÇ-00140 fica aprovado: vira OS própria quando o sinal dele for pago. Complementa a OS-00104.' : 'ORÇ-00140 fica como está (não marcado).' },
      { id: 'c', numero: 'ORÇ-00141', numero_depois: c ? 'OS-00141' : 'ORÇ-00141', situacao: 'aprovar', acao: c ? 'virar_os' : 'nao_muda',
        texto: c ? 'ORÇ-00141 vira a OS-00141 agora.' : 'ORÇ-00141 fica como está (não marcado).' },
    ],
    conjunto: null,
  };
}

function abrir() {
  rpc.mockImplementation(async (nome: string, args: { p_ids: string[]; p_ensaio: boolean }) => {
    if (nome === 'aprovar_conjunto') return { data: plano(args.p_ids, args.p_ensaio), error: null };
    return { data: null, error: null };
  });
  tabelas.service_orders = [
    { id: 'b', labor_cost_total: 1000, parts_cost_total: 500, payment_condition_preset_id: null, custom_payment_installments: null },
    { id: 'c', labor_cost_total: 800, parts_cost_total: 0, payment_condition_preset_id: null,
      custom_payment_installments: [{ tipo: 'entrega', services_pct: 100 }] },
  ];
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const onFechar = vi.fn();
  render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <AprovarConjuntoDialog aberto onFechar={onFechar} conjunto={conjunto} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return { onFechar };
}

beforeEach(() => {
  rpc.mockReset();
  toast.success.mockReset();
});

describe('AprovarConjuntoDialog', () => {
  it('mostra o plano do banco, o sinal do complemento e aprova os dois', async () => {
    const { onFechar } = abrir();
    expect(await screen.findByText('OS-00104 já foi assinado: não muda.')).toBeInTheDocument();
    expect(screen.getByText('Aguarda o sinal')).toBeInTheDocument();
    expect(screen.getByText('Vira OS agora')).toBeInTheDocument();
    expect(await screen.findByText('R$ 1.000,00')).toBeInTheDocument();
    expect(screen.getByText(/condição padrão/)).toBeInTheDocument();
    expect(screen.getByText(/complementa a OS-00104/)).toBeInTheDocument();
    expect(rpc).toHaveBeenCalledWith('aprovar_conjunto', { p_conjunto: 'c1', p_ids: ['b', 'c'], p_ensaio: true });
    await userEvent.click(screen.getByRole('button', { name: 'Aprovar 2' }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('aprovar_conjunto', { p_conjunto: 'c1', p_ids: ['b', 'c'], p_ensaio: false }));
    expect(toast.success).toHaveBeenCalledWith(expect.stringContaining('virou OS (OS-00141)'));
    expect(onFechar).toHaveBeenCalled();
  });

  it('desmarcar um: o banco refaz o plano e aprova só o marcado', async () => {
    abrir();
    await screen.findByText('Vira OS agora');
    await userEvent.click(screen.getByRole('checkbox', { name: 'Aprovar ORÇ-00141' }));
    expect(await screen.findByText('ORÇ-00141 fica como está (não marcado).')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('button', { name: 'Aprovar 1' })).toBeEnabled());
    await userEvent.click(screen.getByRole('button', { name: 'Aprovar 1' }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('aprovar_conjunto', { p_conjunto: 'c1', p_ids: ['b'], p_ensaio: false }));
  });

  it('nenhum marcado: não deixa aprovar', async () => {
    abrir();
    await screen.findByText('Vira OS agora');
    await userEvent.click(screen.getByRole('checkbox', { name: 'Aprovar ORÇ-00140' }));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Aprovar ORÇ-00141' }));
    expect(await screen.findByText('Marque pelo menos um orçamento para aprovar.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Aprovar' })).toBeDisabled();
  });
});
