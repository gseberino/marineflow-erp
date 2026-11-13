// Financeiro › Diárias com o prestador por serviço (o Alex, 12/11/2026): o cartão diz "recebe por
// serviço" e o que espera o cliente pagar; o extrato mostra o serviço e a lista "aguardando o cliente
// pagar"; "Registrar serviço" confere no banco (simula) antes de gravar. Simula só supabase.rpc.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { DiariasPanel } from './DiariasPanel';

const rpc = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpc(...a),
    from: () => ({ select: () => ({
      in: async () => ({ data: [], error: null }),
      eq: () => ({ order: async () => ({ data: [], error: null }) }),
    }) }),
  },
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));
vi.mock('@/hooks/use-payees', () => ({
  useServiceOrdersVinculaveis: () => ({ data: [{ id: 'os119', service_order_number: 'OS-00119', status: 'completed', clients: { name: 'César' } }] }),
  usePayees: () => ({ data: [] }),
}));

const alex = {
  id: 'a', nome: 'Alex Gonçalves Machado', diaria: null, desde: '2026-10-23', dias: 0, trabalhado: 600, pago: 2950, reembolsos: 0,
  ultimo_pagamento: '2026-11-10', saldo_final: -2350, estado: 'adiantado', de: null, ate: null, pago_aguardando_banco: 0,
  pago_falta_aprovar: 2950, modo: 'servico', servicos: 600, n_servicos: 1, aguardando_cliente: 1500,
};
const aguardando = {
  id: 's2', os_id: 'os74', numero: 'OS-00074', cliente: 'Lenine', barco: null, modo: 'percentual', percentual: 30, base: 'mao_de_obra',
  rotulo: '30% da mão de obra', valor: 1500, descricao: 'banco de baterias', data_servico: null, cliente_pagou_em: null,
  situacao: 'aguardando_cliente',
};
const contaDoAlex = {
  favorecido: { id: 'a', nome: 'Alex Gonçalves Machado', desde: '2026-10-23', saldo_inicial: 0, diaria: null, modo: 'servico' },
  de: null, ate: null, saldo_anterior: 0, dias: 0, trabalhado: 600, servicos: 600, pago: 2950, reembolsos: 0,
  pago_aguardando_banco: 0, pago_falta_aprovar: 2950, saldo_final: -2350, estado: 'adiantado',
  aguardando_cliente: 1500, servicos_aguardando_cliente: [aguardando],
  linhas: [
    { data: '2026-10-28', tipo: 'servico', id: 's1', jornada: 'valor combinado', fracao: null, valor_diaria: null, extras: null,
      descontos: null, trabalhado: 600, pago: 0, descricao: 'Serviço OS-00130 — Giancarlo', conta: null, categoria: null,
      observacao: 'revisão elétrica', os: [{ id: 'os130', numero: 'OS-00130' }], saldo: 600, aguardando: false },
  ],
};

beforeEach(() => {
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => {
    switch (nome) {
      case 'resumo_freelancers':
        return { data: { pessoas: [alex], trabalhado: 600, pago: 2950, dias: 0, deve: 0, adiantado: 2350 }, error: null };
      case 'conta_corrente_freelancer':
        return { data: contaDoAlex, error: null };
      case 'servicos_do_prestador':
        return { data: [aguardando, { ...aguardando, id: 's1', os_id: 'os130', numero: 'OS-00130', modo: 'valor', percentual: null,
          base: null, rotulo: 'valor combinado', valor: 600, cliente_pagou_em: '2026-10-28', situacao: 'na_conta' }], error: null };
      case 'registrar_servico_prestador':
        return { data: { ok: true, valor: 800, entra_na_conta: false, simulacao: args.p_simular,
          message: 'Serviço de Alex Gonçalves Machado na OS-00119 (César)\nValor combinado: R$ 800,00' }, error: null };
      default:
        return { data: [], error: null };
    }
  });
});

function renderizar(aba: 'resumo' | 'extrato') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <DiariasPanel aba={aba} filtro={{ periodo: 'tudo', de: '', ate: '', favorecidoId: aba === 'extrato' ? 'a' : null, mes: '2026-11' }}
                      onFiltro={vi.fn()} onVerExtrato={vi.fn()} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const chamadas = (nome: string) => rpc.mock.calls.filter(([n]) => n === nome).map(([, a]) => a as Record<string, unknown>);

describe('Diárias com o prestador por serviço', () => {
  it('o cartão diz que ele recebe por serviço, quantos serviços e o que espera o cliente pagar', async () => {
    renderizar('resumo');
    expect(await screen.findByText(/Recebe por serviço/)).toBeInTheDocument();
    expect(screen.getByText('Serviços')).toBeInTheDocument();
    expect(screen.getByText(/Aguardando o cliente pagar a OS/)).toBeInTheDocument();
    // a ação rápida é registrar serviço, não dia
    expect(screen.getAllByRole('button', { name: /Registrar serviço/ }).length).toBeGreaterThan(0);
  });

  it('o extrato mostra o serviço na conta e a lista do que espera o cliente, sem o bloco de recibo de diárias', async () => {
    renderizar('extrato');
    expect(await screen.findByText('Serviço')).toBeInTheDocument();
    expect(screen.getByText(/Aguardando o cliente pagar/)).toBeInTheDocument();
    expect(screen.getAllByText(/OS-00074/).length).toBeGreaterThan(0);
    expect(screen.getByText('Serviços (OS pagas)')).toBeInTheDocument();
    expect(screen.queryByText(/Acertos/)).not.toBeInTheDocument();
  });

  it('registrar serviço confere no banco (simula) e só então grava', async () => {
    const user = userEvent.setup();
    renderizar('resumo');
    await user.click((await screen.findAllByRole('button', { name: /Registrar serviço/ }))[0]);
    // prestador único já vem escolhido; escolhe a OS e o valor
    await user.click(screen.getByLabelText('OS do serviço'));
    await user.click(await screen.findByRole('option', { name: /OS-00119/ }));
    await user.type(screen.getByLabelText('Valor combinado (R$)'), '800');
    await user.click(screen.getByRole('button', { name: 'Conferir' }));
    expect(await screen.findByText(/Valor combinado: R\$ 800,00/)).toBeInTheDocument();
    expect(chamadas('registrar_servico_prestador')[0]).toMatchObject({ p_favorecido_id: 'a', p_os_id: 'os119', p_simular: true, p_percentual: null });
    await user.click(screen.getByRole('button', { name: 'Registrar' }));
    await waitFor(() => expect(chamadas('registrar_servico_prestador')).toHaveLength(2));
    expect(chamadas('registrar_servico_prestador')[1]).toMatchObject({ p_simular: false, p_os_id: 'os119' });
  });

  // 13/11/2026: o "Registrar pagamento" da tela dava "Freelancer de diária não encontrado" para o Alex.
  it('registrar pagamento ao prestador: sem proposta de reembolso, descrição "Pagamento de serviços"', async () => {
    const user = userEvent.setup();
    renderizar('resumo');
    await user.click((await screen.findAllByRole('button', { name: /Registrar pagamento/ }))[0]);
    const dialogo = await screen.findByRole('dialog');
    await user.type(within(dialogo).getByLabelText('Valor (R$)'), '50000'); // o MoneyInput lê centavos
    const botao = within(dialogo).getByRole('button', { name: 'Registrar pagamento' });
    await waitFor(() => expect(botao).toBeEnabled());
    await user.click(botao);
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(1));
    expect(chamadas('registrar_pagamento_do_freelancer')[0]).toMatchObject({
      p_favorecido_id: 'a', p_valor: 500, p_forma: 'pix', p_reembolsos: [], p_descricao: 'Pagamento de serviços — Alex',
    });
    expect(chamadas('proposta_de_divisao_do_pagamento')).toHaveLength(0);
  });
});
