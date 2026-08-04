// Smoke de render e das regras do lançamento da folha.
//
// A regra que mais importa aqui: campo em branco significa "não fiz", nunca
// "fiz em zero minuto". Passo com tempo zero não gera apontamento de hora nem
// caso utilizável — lançar zero seria pior que não lançar, porque entraria na
// base com cara de execução real.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { SheetEntryDialog } from './SheetEntryDialog';

const { passos, completou } = vi.hoisted(() => {
  const completou: any[] = [];
  const base = {
    service_order_id: 'os1', service_order_service_id: 'l1', template_id: null,
    block: '1 · Antes de mexer — Gás GLP', block_key: 'abertura:gas', block_note: null,
    detail: null, kind: 'do', mode: 'do_confirm', is_killer: false,
    requires_photo: false, requires_measure: null, measure_unit: null, measure_value: null,
    status: 'pending', na_reason: null, blocked_reason_code: null, blocked_note: null,
    assigned_user_id: null, started_at: null, completed_at: null, actual_minutes: null,
    origin: 'composed', notes: null, ai_confidence: null, ai_source: null, approved_at: null,
  };
  const passos = [
    { ...base, id: 'p1', seq: 1, title: 'Fechar o registro do cilindro', standard_minutes: 5 },
    { ...base, id: 'p2', seq: 2, title: 'Confirmar ausência de tensão', standard_minutes: 10,
      requires_measure: 'tensao_v', measure_unit: 'V' },
    { ...base, id: 'p3', seq: 3, title: 'Fotografar a ligação atual', standard_minutes: 10 },
  ];
  return { passos, completou };
});

vi.mock('@/hooks/use-service-steps', async (orig) => {
  const real = await orig<any>();
  return {
    ...real,
    useServiceOrderSteps: () => ({ data: passos, isLoading: false }),
    useCompleteStep: () => ({
      mutateAsync: async (args: any) => { completou.push(args); },
      isPending: false,
    }),
  };
});

function renderDialog() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <SheetEntryDialog serviceOrderId="os1" orderNumber="OS-00069" open onOpenChange={() => {}} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('SheetEntryDialog — lançamento da folha preenchida à mão', () => {
  it('lista os passos pendentes com o tempo previsto', () => {
    renderDialog();
    expect(screen.getByText(/Lançar folha/)).toBeTruthy();
    expect(screen.getByText('Fechar o registro do cilindro')).toBeTruthy();
    // Dois passos previstos em 10 min, um em 5.
    expect(screen.getAllByText('previsto 10 min').length).toBe(2);
    expect(screen.getByText('previsto 5 min')).toBeTruthy();
  });

  it('só conta o passo que recebeu minutos — em branco fica pendente', async () => {
    const user = userEvent.setup();
    renderDialog();

    const campos = screen.getAllByPlaceholderText('min');
    await user.type(campos[0], '12');

    // Um de três, e o total reflete só o preenchido.
    expect(screen.getByText(/1 de 3 passos/)).toBeTruthy();
    expect(screen.getByRole('button', { name: /Lançar 1 passo/ })).toBeTruthy();
  });

  it('não deixa lançar passo de medição sem o valor anotado', async () => {
    const user = userEvent.setup();
    renderDialog();

    // p2 pede medição de tensão
    const campos = screen.getAllByPlaceholderText('min');
    await user.type(campos[1], '15');

    expect(screen.getByText('1 sem medição')).toBeTruthy();
  });

  it('aceita quando a medição da folha é transcrita junto', async () => {
    const user = userEvent.setup();
    renderDialog();

    const campos = screen.getAllByPlaceholderText('min');
    await user.type(campos[1], '15');
    await user.type(screen.getByPlaceholderText('medição V'), '12.8');

    expect(screen.queryByText('1 sem medição')).toBeNull();
    expect(screen.getByRole('button', { name: /Lançar 1 passo/ })).toBeTruthy();
  });
});
