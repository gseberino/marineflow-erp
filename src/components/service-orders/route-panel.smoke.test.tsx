// Smoke de RENDER do Roteiro de Execução (painel, modo foco e quadro do dia).
// Mesma motivação do AgendaPage.smoke.test.tsx: erro de inicialização (TDZ,
// import circular, ícone inexistente) não aparece em tsc nem no build — só ao
// montar o componente de verdade.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const { steps, reasons, rpcSpy, updateSpy } = vi.hoisted(() => {
  const steps = [
    {
      id: 'p1', service_order_id: 'os1', service_order_service_id: 'l1', template_id: 't1',
      seq: 1, block: 'Preparação', title: 'Desligar o disjuntor geral',
      detail: 'Confirmar ausência de tensão antes de tocar nos terminais',
      kind: 'safety', mode: 'read_do', standard_minutes: 10, is_killer: true,
      requires_photo: false, requires_measure: 'tensao_v', measure_unit: 'V', measure_value: null,
      status: 'pending', na_reason: null, blocked_reason_code: null, blocked_note: null,
      assigned_user_id: null, started_at: null, completed_at: null, actual_minutes: null,
      origin: 'template', notes: null,
    },
    {
      id: 'p2', service_order_id: 'os1', service_order_service_id: 'l1', template_id: 't2',
      seq: 2, block: 'Execução', title: 'Instalar banco de lítio', detail: null,
      kind: 'do', mode: 'do_confirm', standard_minutes: 90, is_killer: false,
      requires_photo: true, requires_measure: null, measure_unit: null, measure_value: null,
      status: 'blocked', na_reason: null, blocked_reason_code: 'falta_peca',
      blocked_note: 'terminal 70mm² não veio', assigned_user_id: null,
      started_at: null, completed_at: null, actual_minutes: 12,
      origin: 'template', notes: null,
    },
  ];
  const reasons = [
    { code: 'falta_peca', label: 'Falta peça ou material', category: 'espera', counts_as_billable: false, sort: 10 },
    { code: 'clima', label: 'Clima ou maré', category: 'externo', counts_as_billable: false, sort: 60 },
  ];
  return { steps, reasons, rpcSpy: vi.fn(), updateSpy: vi.fn() };
});

vi.mock('@/integrations/supabase/client', () => {
  const builder = (table: string): any => {
    const rows =
      table === 'service_order_steps' ? steps
      : table === 'work_stop_reasons' ? reasons
      : table === 'service_orders' ? [{
          id: 'os1', service_order_number: 'OS-00051', status: 'in_progress',
          scheduled_start_at: new Date().toISOString(),
          clients: { name: 'Cliente Teste' }, vessels: { name: 'Motorhome Clóvis' },
          marinas: { name: 'Oficina' },
        }]
      : [];
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'is', 'not', 'or', 'order', 'limit', 'filter']) {
      o[k] = () => o;
    }
    o.update = (payload: unknown) => { updateSpy(table, payload); return o; };
    o.insert = () => o;
    o.delete = () => o;
    o.single = async () => ({ data: rows[0] ?? null, error: null });
    o.maybeSingle = async () => ({ data: rows[0] ?? null, error: null });
    o.then = (res: any) => Promise.resolve({ data: rows, error: null }).then(res);
    return o;
  };
  return {
    supabase: {
      from: (table: string) => builder(table),
      rpc: (...args: unknown[]) => { rpcSpy(...args); return Promise.resolve({ data: 3, error: null }); },
    },
  };
});

import { ServiceRoutePanel } from './ServiceRoutePanel';
import { StepFocusMode } from './StepFocusMode';
import DayBoardPage from '@/pages/DayBoardPage';

function wrap(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{ui}</MemoryRouter>
    </QueryClientProvider>
  );
}

beforeEach(() => {
  rpcSpy.mockClear();
  updateSpy.mockClear();
});

describe('Painel do Roteiro', () => {
  it('monta e lista os passos com o estado de cada um', async () => {
    render(wrap(<ServiceRoutePanel serviceOrderId="os1" orderNumber="OS-00051" />));
    expect(await screen.findByText('Desligar o disjuntor geral')).toBeInTheDocument();
    expect(screen.getByText('Instalar banco de lítio')).toBeInTheDocument();
    expect(screen.getByText('travado')).toBeInTheDocument();
  });

  it('mostra o motivo da parada em português, não o código do banco', async () => {
    render(wrap(<ServiceRoutePanel serviceOrderId="os1" orderNumber="OS-00051" />));
    expect(await screen.findByText(/Falta peça ou material/)).toBeInTheDocument();
    expect(screen.queryByText(/falta_peca/)).not.toBeInTheDocument();
  });

  it('soma previsto e real no cabeçalho do roteiro', async () => {
    render(wrap(<ServiceRoutePanel serviceOrderId="os1" orderNumber="OS-00051" />));
    // 10 + 90 previstos, 12 reais. O tempo real aparece no resumo e na linha do
    // passo — as duas ocorrências são intencionais.
    expect(await screen.findByText(/1h40/)).toBeInTheDocument();
    expect(screen.getAllByText(/12 min/).length).toBeGreaterThan(0);
  });

  it('chama a geração a partir do catálogo', async () => {
    render(wrap(<ServiceRoutePanel serviceOrderId="os1" orderNumber="OS-00051" />));
    await userEvent.click(await screen.findByRole('button', { name: /Gerar do catálogo/i }));
    await waitFor(() => {
      expect(rpcSpy).toHaveBeenCalledWith('generate_service_order_steps', { p_service_order_id: 'os1' });
    });
  });

  it('não renderiza nada sem OS — a aba pode montar antes do id chegar', () => {
    const { container } = render(wrap(<ServiceRoutePanel serviceOrderId={undefined} />));
    expect(container).toBeEmptyDOMElement();
  });
});

describe('Modo Foco', () => {
  it('mostra um passo por vez, com a posição na fila', async () => {
    render(wrap(<StepFocusMode open onOpenChange={() => {}} steps={steps as any} orderLabel="OS-00051" />));
    expect(await screen.findByText('Desligar o disjuntor geral')).toBeInTheDocument();
    expect(screen.getByText(/passo 1 de 2/)).toBeInTheDocument();
    // O segundo passo não aparece como título — só na prévia "a seguir"
    expect(screen.getByText(/a seguir: Instalar banco de lítio/)).toBeInTheDocument();
  });

  it('destaca passo de segurança e item crítico', async () => {
    render(wrap(<StepFocusMode open onOpenChange={() => {}} steps={steps as any} />));
    expect(await screen.findByText('Segurança')).toBeInTheDocument();
    expect(screen.getByText('crítico')).toBeInTheDocument();
  });

  it('oferece as três saídas: feito, não se aplica e travei', async () => {
    render(wrap(<StepFocusMode open onOpenChange={() => {}} steps={steps as any} />));
    expect(await screen.findByRole('button', { name: /Começar/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Não se aplica/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Travei/i })).toBeInTheDocument();
  });

  it('exige motivo para "não se aplica" — botão fica travado até escrever', async () => {
    render(wrap(<StepFocusMode open onOpenChange={() => {}} steps={steps as any} />));
    await userEvent.click(await screen.findByRole('button', { name: /Não se aplica/i }));
    const confirm = screen.getByRole('button', { name: /Confirmar/i });
    expect(confirm).toBeDisabled();
    await userEvent.type(screen.getByPlaceholderText(/já veio instalado/i), 'já veio pronto');
    expect(confirm).toBeEnabled();
  });

  it('celebra o fim em vez de mostrar tela vazia', async () => {
    const allDone = steps.map((s) => ({ ...s, status: 'done' }));
    render(wrap(<StepFocusMode open onOpenChange={() => {}} steps={allDone as any} />));
    expect(await screen.findByText('Roteiro concluído')).toBeInTheDocument();
  });
});

describe('Quadro do Dia', () => {
  it('monta e distribui as OS em colunas de estado', async () => {
    render(wrap(<DayBoardPage />));
    expect(await screen.findByText('Quadro do dia')).toBeInTheDocument();
    expect(screen.getByText('A começar')).toBeInTheDocument();
    expect(screen.getByText('Em execução')).toBeInTheDocument();
    expect(screen.getByText('Travadas')).toBeInTheDocument();
    expect(screen.getByText('Concluídas')).toBeInTheDocument();
  });

  it('põe a OS com passo travado na coluna certa', async () => {
    render(wrap(<DayBoardPage />));
    const card = await screen.findByText('OS-00051');
    expect(card).toBeInTheDocument();
    expect(screen.getByText(/terminal 70mm²/)).toBeInTheDocument();
  });
});
