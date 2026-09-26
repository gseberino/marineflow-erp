// O campo "Validade do orçamento (dias)" do formulário.
//
// O onChange era `parseInt(x) || padrão`: -1 e 99999 eram GRAVADOS no orçamento. O PDF, a R19
// e o assistente descartam esses números (inteiro de 1 a 3650, em dias-de-validade.ts) e usam
// o padrão da empresa — então o formulário mostrava um prazo e o documento e o aviso de
// vencimento usavam outro. Agora o campo passa pela mesma regra (primeiraValidade).
import { describe, it, expect, vi } from 'vitest';
import { useState } from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { I18nProvider } from '@/i18n';
import { FinancialSection } from './financial-section';

/** O que o formulário guardou, para o teste ler depois de cada digitação. */
const gravado: { form: Record<string, any> } = { form: {} };

function Palco() {
  const [form, setForm] = useState<Record<string, any>>({
    payment_conditions: '', payment_condition_preset_id: '',
    custom_payment_installments: null, quote_validity_days: 7,
  });
  gravado.form = form;
  const set = (campo: string, valor: unknown) => setForm((f) => ({ ...f, [campo]: valor }));
  return (
    <I18nProvider>
      <FinancialSection
        showFinancialDialog setShowFinancialDialog={vi.fn()}
        form={form} set={set} setForm={setForm}
        orderId="os-1"
        orderData={{ id: 'os-1', converted_to_os_at: null, payment_conditions: null }}
        isNew={false} isLocked={false}
        clientView={false}
        laborCost={1000} partsCost={500} operationalCost={0} expensesTotal={0}
        subtotal={1500} base={1500} grandTotal={1500} discountRatio={1}
        cardFeeAmount={0} signalAmount={null}
        discountServicesPct={0} discountPartsPct={0} applyBulkLineDiscount={vi.fn()}
        issRatePct={0} defaultQuoteValidityDays={3}
        paymentPresets={[]} selectedPreset={undefined}
        installmentRows={[]} calcInstallmentAmount={() => 0}
        cardFees={[]} selectedInstallments={1} setSelectedInstallments={vi.fn()}
        setDepositFromFinancial={vi.fn()} setDepositDialogOpen={vi.fn()}
        handleGenerateCollections={vi.fn()} generatingCollections={false}
        osCollections={[]} commissionableUsers={[]}
      />
    </I18nProvider>
  );
}

const campo = () => screen.getByLabelText(/Validade do orçamento \(dias\)/) as HTMLInputElement;

describe('formulário — validade do orçamento (dias)', () => {
  it('o campo pede inteiro de 1 a 3650 (min, max, step)', () => {
    render(<Palco />);
    expect(campo().value).toBe('7');
    expect(campo().min).toBe('1');
    expect(campo().max).toBe('3650');
    expect(campo().step).toBe('1');
  });

  it.each([
    ['-1', 3],
    ['0', 3],
    ['99999', 3],
    ['1e9', 3],
    ['', 3],
    ['2.5', 2],
    ['30', 30],
  ])('digitar %j grava %i no orçamento (o padrão da empresa quando não serve)', (digitado, fica) => {
    render(<Palco />);
    fireEvent.change(campo(), { target: { value: digitado } });
    expect(gravado.form.quote_validity_days).toBe(fica);
    expect(campo().value).toBe(String(fica));
  });
});
