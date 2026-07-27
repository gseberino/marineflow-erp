// Smoke de RENDER do diálogo "Receber sinal" — erro de inicialização (TDZ, hook order,
// acesso a undefined) NÃO aparece em tsc/build. Renderiza o diálogo aberto no modo "por
// categoria" com uma condição que tem saldo, exercitando os hooks novos (useMemo do schedule,
// useRef do comprovante) e o caminho da prévia do saldo (computeScheduleFromParts real).
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RegisterDepositDialog } from './RegisterDepositDialog';

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({ update: () => ({ eq: async () => ({ error: null }) }) }),
    rpc: async () => ({ data: { payment_id: 'p1' }, error: null }),
    storage: { from: () => ({ upload: async () => ({ error: null }), getPublicUrl: () => ({ data: { publicUrl: '' } }), remove: async () => ({ error: null }) }) },
  },
}));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: () => {} }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: {} }) }));
vi.mock('@/hooks/use-payment-conditions', () => ({
  usePaymentConditionPresets: () => ({
    data: [{ id: 'c1', label: '50% entrada + saldo 30d', installments: [
      { tipo: 'aprovacao', services_pct: 50, parts_pct: 100, days_after_approval: 0 },
      { tipo: 'prazo', services_pct: 50, parts_pct: 0, days_after_approval: 30 },
    ] }],
  }),
}));
// Evita puxar a árvore do passo de estoque (não é renderizado com o diálogo fechado, mas o import existe).
vi.mock('@/components/StockConfirmationDialog', () => ({ StockConfirmationDialog: () => null }));

function renderDialog() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <RegisterDepositDialog
          open
          onOpenChange={() => {}}
          serviceOrderId="so-1"
          serviceOrderNumber="ORÇ-00060"
          grandTotal={20000}
          laborCost={4110}
          partsCost={16450.67}
          discountRatio={20000 / 20560.67}
          expensesTotal={0}
          presetServicesPct={50}
          presetPartsPct={100}
          installments={[
            { tipo: 'aprovacao', services_pct: 50, parts_pct: 100, days_after_approval: 0 },
            { tipo: 'prazo', services_pct: 50, parts_pct: 0, days_after_approval: 30 },
          ]}
        />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('RegisterDepositDialog — smoke de render', () => {
  it('renderiza aberto sem crashar, no modo por categoria', () => {
    renderDialog();
    expect(screen.getByText('Registrar pagamento do sinal')).toBeTruthy();
    expect(screen.getByText('Condição de pagamento')).toBeTruthy();
  });

  it('mostra a prévia do saldo (parcela futura da condição)', () => {
    renderDialog();
    expect(screen.getByText('Saldo após o sinal')).toBeTruthy();
    // saldo = 50% dos serviços com desconto ≈ 1.998,96 (aparece na parcela e no total)
    expect(screen.getAllByText(/1\.998,96/).length).toBeGreaterThan(0);
  });
});
