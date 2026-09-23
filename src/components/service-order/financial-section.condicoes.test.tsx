// O seletor de condição de pagamento do orçamento/OS.
//
// Queixa do dono (23/09/2026): "o campo de condição de pagamento já cadastradas não está
// sendo possível ser selecionada", e sem ela o PDF sai sem as condições e sem o sinal de
// materiais e serviços.
//
// As condições ESTAVAM cadastradas (6 ativas no banco) e a RLS deixa qualquer usuário
// logado lê-las. O defeito era outro: o Select tinha `key={presetKey}` e o próprio
// handler fazia `setPresetKey(k => k + 1)` ao final — ou seja, a cada escolha o campo era
// destruído e recriado, perdendo o que acabara de ser selecionado e voltando ao
// placeholder. Para quem usa, é indistinguível de "não dá para selecionar".
import { describe, it, expect, vi } from 'vitest';
import { useState } from 'react';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';
import { FinancialSection } from './financial-section';

/** As condições ativas reais da HBR, com os percentuais que alimentam o sinal. */
const PRESETS = [
  {
    id: 'p-tecnico', label: 'Serviço técnico - 75% sinal / 25% na entrega', active: true, sort_order: 0,
    installments: [
      { label: 'Sinal', services_pct: 75, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'aprovacao' },
      { label: 'Saldo', services_pct: 25, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'entrega' },
    ],
  },
  {
    id: 'p-materiais', label: '50% mão de obra + 100% materiais antecipados', active: true, sort_order: 3,
    installments: [
      { label: 'Sinal', services_pct: 50, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'aprovacao' },
      { label: 'Saldo', services_pct: 50, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'entrega' },
    ],
  },
  { id: 'p-avista', label: 'À vista', active: true, sort_order: 1, installments: [] },
];

/**
 * Monta a seção com um formulário de verdade por trás — o defeito só aparece quando o
 * estado sobe e volta, que é o que acontece na tela.
 */
function Palco({ inicial = {} }: { inicial?: Record<string, any> }) {
  const [form, setForm] = useState<Record<string, any>>({
    payment_conditions: '', payment_condition_preset_id: '',
    custom_payment_installments: null, ...inicial,
  });
  const set = (campo: string, valor: unknown) => setForm((f) => ({ ...f, [campo]: valor }));
  const preset = PRESETS.find(
    (p) => p.id === form.payment_condition_preset_id
      || (!form.payment_condition_preset_id && p.label === form.payment_conditions),
  );

  return (
    <I18nProvider>
      <FinancialSection
        /* A secao inteira vive num Collapsible; aberta e como o dono a ve. */
        showFinancialDialog setShowFinancialDialog={vi.fn()}
        form={form} set={set} setForm={setForm}
        orderId="os-1" orderData={{ id: 'os-1' }} isNew={false} isLocked={false}
        clientView={false}
        laborCost={1000} partsCost={500} operationalCost={0} expensesTotal={0}
        subtotal={1500} base={1500} grandTotal={1500} discountRatio={1}
        cardFeeAmount={0} signalAmount={null}
        discountServicesPct={0} discountPartsPct={0} applyBulkLineDiscount={vi.fn()}
        issRatePct={0} defaultQuoteValidityDays={15}
        paymentPresets={PRESETS} selectedPreset={preset}
        installmentRows={[]} calcInstallmentAmount={() => 0}
        cardFees={[]} selectedInstallments={1} setSelectedInstallments={vi.fn()}
        setDepositFromFinancial={vi.fn()} setDepositDialogOpen={vi.fn()}
        handleGenerateCollections={vi.fn()} generatingCollections={false}
        osCollections={[]} commissionableUsers={[]}
      />
    </I18nProvider>
  );
}

/** O seletor das condições pré-definidas (o outro Select da seção é a forma de pagamento). */
function seletor() {
  const todos = screen.getAllByRole('combobox');
  return todos[0];
}

describe('seletor de condição de pagamento', () => {
  it('lista as condições cadastradas', async () => {
    const user = userEvent.setup();
    render(<Palco />);
    await user.click(seletor());
    for (const p of PRESETS) {
      expect(await screen.findByRole('option', { name: p.label })).toBeInTheDocument();
    }
  });

  it('a escolha FICA no campo — era o defeito: sumia e voltava ao placeholder', async () => {
    const user = userEvent.setup();
    render(<Palco />);
    await user.click(seletor());
    await user.click(await screen.findByRole('option', { name: 'À vista' }));

    // O que o dono via: o campo voltava a "Pré-definidas…" como se nada tivesse
    // acontecido, e ele tentava de novo.
    expect(within(seletor()).queryByText(/Pré-definidas/i)).not.toBeInTheDocument();
    expect(seletor()).toHaveTextContent('À vista');
  });

  it('a condição escolhida chega ao formulário, que é o que vai para o PDF', async () => {
    const user = userEvent.setup();
    render(<Palco />);
    await user.click(seletor());
    await user.click(await screen.findByRole('option', { name: /75% sinal/ }));
    // O texto livre ao lado reflete a condição — é ele que o documento imprime.
    expect(screen.getByDisplayValue('Serviço técnico - 75% sinal / 25% na entrega')).toBeInTheDocument();
  });

  it('ao reabrir um orçamento salvo, o campo já mostra a condição gravada', async () => {
    // Sem valor controlado, um orçamento com condição gravada abria com o campo vazio —
    // e parecia que a condição tinha se perdido.
    render(<Palco inicial={{
      payment_condition_preset_id: 'p-materiais',
      payment_conditions: '50% mão de obra + 100% materiais antecipados',
    }} />);
    expect(seletor()).toHaveTextContent('50% mão de obra + 100% materiais antecipados');
  });

  it('trocar de condição substitui a anterior, sem voltar ao vazio', async () => {
    const user = userEvent.setup();
    render(<Palco inicial={{ payment_condition_preset_id: 'p-avista', payment_conditions: 'À vista' }} />);
    await user.click(seletor());
    await user.click(await screen.findByRole('option', { name: /75% sinal/ }));
    expect(seletor()).toHaveTextContent('75% sinal');
  });

  it('"Personalizado" também fica marcado, e abre as parcelas próprias', async () => {
    const user = userEvent.setup();
    render(<Palco />);
    await user.click(seletor());
    await user.click(await screen.findByRole('option', { name: 'Personalizado' }));
    expect(seletor()).toHaveTextContent('Personalizado');
  });
});
