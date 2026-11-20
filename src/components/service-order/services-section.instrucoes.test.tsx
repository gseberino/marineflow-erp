// Via v2, F2 (canal A): na seção de serviços, o número do serviço (Q1 do dono), o botão "Rascunhar instruções" só para o
// admin e OS gravada, a faixa "N esperam sua aprovação" e o "Aprovar todas" com o texto de cada cartão.
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ServicesSection } from './services-section';
import type { RetratoDasInstrucoes } from '@/lib/instrucoes-sugeridas';

const h = vi.hoisted(() => ({
  papel: 'admin' as string,
  retrato: undefined as RetratoDasInstrucoes | undefined,
  pedir: vi.fn(),
  decidir: vi.fn(),
  cancelar: vi.fn(),
  osPedida: [] as Array<string | undefined>,
}));

vi.mock('@/hooks/use-auth', async (orig) => ({
  ...(await orig<any>()),
  useOptionalAuth: () => ({ user: { id: 'u1', role: h.papel } }),
}));
vi.mock('@/hooks/use-instrucoes-sugeridas', () => ({
  useInstrucoesSugeridas: (os: string | undefined) => { h.osPedida.push(os); return { data: os ? h.retrato : undefined }; },
  usePedirInstrucoes: () => ({ mutate: h.pedir, isPending: false }),
  useDecidirInstrucoes: () => ({ mutate: h.decidir, isPending: false }),
  useCancelarPedidoDeInstrucoes: () => ({ mutate: h.cancelar, isPending: false }),
}));
vi.mock('@/hooks/use-service-steps', async (orig) => ({
  ...(await orig<any>()),
  useServiceOrderSteps: () => ({ data: [], isLoading: false }),
}));
vi.mock('@/hooks/use-service-systems', async (orig) => ({
  ...(await orig<any>()),
  useLinesMissingSystem: () => ({ data: [], isLoading: false }),
}));
vi.mock('@/hooks/use-payees', () => ({ usePayees: () => ({ data: [] }) }));
vi.mock('@/components/ServiceTimer', () => ({ ServiceTimer: () => <span>timer</span> }));

const noop = () => {};
const linha = (id: string, nome: string) => ({
  id, name_snapshot: nome, description_snapshot: null, billing_unit_snapshot: 'unit', quantity: 1, unit_price_snapshot: 100,
  line_total: 100, discount_pct: 0, discount_amount: 0, started_at: null, finished_at: null, elapsed_minutes: 0,
  technician_instructions: null,
});

function secao(isNew = false) {
  return (
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <ServicesSection
          isNew={isNew}
          orderId={isNew ? undefined : 'os1'}
          services={[]}
          soServices={[linha('l1', 'Instalação do inversor'), linha('l2', 'Deslocamento'), linha('l3', 'Instalação da antena de TV')]}
          appUsers={[]}
          servicesItemCount={3}
          laborCost={300}
          billableHours={0}
          draftServices={[]}
          setDraftServices={noop}
          editingSvc={{}}
          setEditingSvc={noop}
          openNewSvcCards={[]}
          setOpenNewSvcCards={noop}
          setShowNewServiceDialog={noop}
          addNewSvcCard={noop}
          cancelSvcCard={noop}
          handleConfirmNewSvcCard={noop}
          handleConfirmEditSvc={noop}
          startEditPersisted={noop}
          applyQuickDiscountToService={noop}
          updateSvcLine={{ isPending: false }}
          removeService={{ mutate: noop }}
          addService={{ mutate: noop }}
        />
      </I18nProvider>
    </QueryClientProvider>
  );
}

const comPendentes = (): RetratoDasInstrucoes => ({
  service_order_id: 'os1', documento: 'ORÇ-00999', em_uso: true, elegiveis: 0, job: null,
  pendentes: [
    { id: 's1', linha_id: 'l1', numero: 1, nome: 'Instalação do inversor', texto: 'Fixação do inversor, ligação dos cabos e teste de carga.', origem: 'ia', fonte_rotulo: null, criado_em: 'x' },
    { id: 's3', linha_id: 'l3', numero: 3, nome: 'Instalação da antena de TV', texto: 'Fixação da antena, ligação do coaxial e teste de imagem.', origem: 'reuso', fonte_rotulo: 'igual à do ORÇ-00131 · serviço 4', criado_em: 'x' },
  ],
});

beforeEach(() => {
  h.papel = 'admin';
  h.retrato = undefined;
  h.osPedida = [];
  h.pedir.mockReset();
  h.decidir.mockReset();
});

describe('ServicesSection — instruções sugeridas (via v2, F2)', () => {
  it('número do serviço antes do nome, num elemento à parte (a cobrança conta: o 3º é o 3)', () => {
    render(secao());
    expect(screen.getByText('Instalação do inversor')).toBeTruthy();
    expect(screen.getByText('1 ·')).toBeTruthy();
    expect(screen.getByText('2 ·')).toBeTruthy();
    expect(screen.getByText('3 ·')).toBeTruthy();
  });

  it('carregando → carregado: sem retrato nada aparece; com elegíveis, o botão "Rascunhar instruções (N)" pede', () => {
    const { rerender } = render(secao());
    expect(screen.queryByRole('button', { name: /Rascunhar instruções/ })).toBeNull();
    h.retrato = { service_order_id: 'os1', documento: 'ORÇ-00999', em_uso: true, pendentes: [], elegiveis: 2, job: null };
    rerender(secao());
    fireEvent.click(screen.getByRole('button', { name: 'Rascunhar instruções (2)' }));
    expect(h.pedir).toHaveBeenCalledTimes(1);
  });

  it('pedido aberto: mostra "Rascunhando…" e "Cancelar", sem o botão', () => {
    h.retrato = { service_order_id: 'os1', documento: 'ORÇ-00999', em_uso: true, pendentes: [], elegiveis: 2,
      job: { id: 'j1', status: 'processing', criado_em: 'x', iniciado_em: 'y', terminado_em: null, error_code: null, error: null, linhas: 2, recebidos: null, sem_sugestao: null } };
    render(secao());
    expect(screen.getByText('Rascunhando 2 instruções…')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: /Rascunhar instruções/ })).toBeNull();
  });

  it('pedido falhou: diz o motivo e oferece "Tentar de novo"', () => {
    h.retrato = { service_order_id: 'os1', documento: 'ORÇ-00999', em_uso: true, pendentes: [], elegiveis: 1,
      job: { id: 'j1', status: 'failed', criado_em: 'x', iniciado_em: null, terminado_em: 'y', error_code: 'timeout', error: null, linhas: 1, recebidos: null, sem_sugestao: null } };
    render(secao());
    expect(screen.getByText(/O pedido de instruções não terminou/)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Tentar de novo (1)' })).toBeTruthy();
  });

  it('faixa conta as pendentes; cada linha ganha o cartão; "Aprovar todas" manda o texto de cada cartão (editado ou não)', () => {
    h.retrato = comPendentes();
    render(secao());
    expect(screen.getByText(/2 instruções sugeridas pelo assistente esperam sua aprovação/)).toBeTruthy();
    const caixas = screen.getAllByRole('textbox').filter((e) => e.tagName === 'TEXTAREA') as HTMLTextAreaElement[];
    expect(caixas).toHaveLength(2);
    fireEvent.change(caixas[0], { target: { value: 'Fixação do inversor e teste.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar todas' }));
    expect(h.decidir).toHaveBeenCalledWith(
      [
        { id: 's1', acao: 'aprovar', texto: 'Fixação do inversor e teste.' },
        { id: 's3', acao: 'aprovar', texto: 'Fixação da antena, ligação do coaxial e teste de imagem.' },
      ],
      expect.anything(),
    );
  });

  it('quem não é admin: nem consulta, nem botão, nem faixa (o número continua)', () => {
    h.papel = 'technician';
    h.retrato = comPendentes();
    render(secao());
    expect(h.osPedida.every((os) => os === undefined)).toBe(true);
    expect(screen.queryByText(/esperam sua aprovação/)).toBeNull();
    expect(screen.queryByRole('button', { name: /Rascunhar/ })).toBeNull();
    expect(screen.getByText('1 ·')).toBeTruthy();
  });

  it('OS nova: não consulta', () => {
    render(secao(true));
    expect(h.osPedida.every((os) => os === undefined)).toBe(true);
  });
});
