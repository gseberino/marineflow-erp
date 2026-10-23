// Recebimento (leva 8, 22/10/2026): o histórico de pagamentos diz quem pagou pela linha do banco — "Pago por X
// (cônjuge) · pelo extrato"; cliente sem documento, "confira" — e cada pagamento confirmado tem o seu recibo.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({
  pagoPorPedido: [] as Array<string | null | undefined>,
  recibos: [] as Array<[unknown, unknown]>,
}));

vi.mock('@/hooks/use-financial', () => ({
  usePayments: (rec?: string) => ({
    data: rec
      ? [
        { id: 'p1', payment_date: '2026-10-20T12:00:00', payment_method: 'pix', amount: 1000, status: 'confirmed' },
        { id: 'p2', payment_date: '2026-10-18T12:00:00', payment_method: 'pix', amount: 500, status: 'confirmed' },
        { id: 'p3', payment_date: '2026-10-15T12:00:00', payment_method: 'pix', amount: 200, status: 'cancelled', cancellation_reason: 'duplicado' },
      ]
      : [{ id: 'd1', payment_date: '2026-10-20T12:00:00', payment_method: 'pix', amount: 80, status: 'confirmed' }],
  }),
  useRegisterPayment: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useCancelPayment: () => ({ isPending: false, mutateAsync: vi.fn() }),
}));
vi.mock('@/hooks/use-card-fees', () => ({ useCardFees: () => ({ data: [] }) }));
vi.mock('@/hooks/use-pagadores-do-cliente', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-pagadores-do-cliente')>()),
  usePagamentosComPagador: (id: string | null | undefined) => {
    estado.pagoPorPedido.push(id);
    return {
      data: id
        ? [
          { payment_id: 'p1', receivable_id: 'r1', client_id: 'c1', bank_transaction_id: 'b1', pagador_nome: 'MARIA SOUZA', pagador_documento: '12345678901', relacao: 'conjuge', situacao: 'terceiro' },
          { payment_id: 'p2', receivable_id: 'r1', client_id: 'c1', bank_transaction_id: 'b2', pagador_nome: 'JOAO', pagador_documento: '98765432100', relacao: null, situacao: 'indefinido' },
          { payment_id: 'p3', receivable_id: 'r1', client_id: 'c1', bank_transaction_id: 'b3', pagador_nome: 'ACME LTDA', pagador_documento: '04754513000149', relacao: null, situacao: 'terceiro' },
        ]
        : undefined,
    };
  },
}));
vi.mock('@/v2/lib/receipt', () => ({
  generateReceivableReceipt: async (r: unknown, id: unknown) => { estado.recibos.push([r, id]); return true; },
}));

import { PaymentDialog } from './PaymentDialog';
// A frase mora com o hook da view (uma fonte só); o mock acima repassa a real.
import { fraseDoPagoPor } from '@/hooks/use-pagadores-do-cliente';

const CONTA = { id: 'r1', description: 'Sinal OS-00900', amount: 2000, paid_amount: 1500, balance_amount: 500, client_id: 'c1' };

beforeEach(() => {
  estado.pagoPorPedido = [];
  estado.recibos = [];
});

function abrir(props: { receivable?: unknown; payable?: unknown }) {
  return render(
    <I18nProvider>
      <PaymentDialog open onOpenChange={() => {}} {...props} />
    </I18nProvider>,
  );
}

describe('PaymentDialog — "Pago por" e recibo de cada pagamento', () => {
  it('terceiro: "Pago por X (relação) · pelo extrato"; cliente sem documento: "confira"', () => {
    abrir({ receivable: CONTA });
    expect(screen.getByText('Pago por MARIA SOUZA (cônjuge) · pelo extrato')).toBeInTheDocument();
    expect(screen.getByText('Pago por JOAO · cliente sem CPF/CNPJ no cadastro, confira')).toBeInTheDocument();
    expect(estado.pagoPorPedido).toContain('r1');
    // o documento de quem pagou não aparece no recebimento
    expect(document.body).not.toHaveTextContent('12345678901');
  });

  it('"Recibo deste pagamento" só nos confirmados, e gera o recibo daquele pagamento', async () => {
    const user = userEvent.setup();
    abrir({ receivable: CONTA });
    const botoes = screen.getAllByRole('button', { name: /Recibo deste pagamento/ });
    expect(botoes).toHaveLength(2);
    await user.click(botoes[1]);
    expect(estado.recibos).toEqual([[CONTA, 'p2']]);
  });

  it('conta a pagar: nem "Pago por" nem recibo, e a view nem é consultada', () => {
    abrir({ payable: { id: 'd', description: 'Despesa', amount: 80, paid_amount: 80, balance_amount: 0 } });
    expect(screen.queryByText(/Pago por/)).toBeNull();
    expect(screen.queryByRole('button', { name: /Recibo deste pagamento/ })).toBeNull();
    expect(estado.pagoPorPedido.every((x) => x === undefined)).toBe(true);
  });
});

describe('fraseDoPagoPor', () => {
  const base = { payment_id: 'p', receivable_id: 'r', client_id: 'c', bank_transaction_id: 'b', pagador_documento: null, relacao: null } as const;
  it('terceiro sem relação: sem parênteses', () => {
    expect(fraseDoPagoPor({ ...base, pagador_nome: 'ACME LTDA', situacao: 'terceiro' })).toEqual({ texto: 'Pago por ACME LTDA · pelo extrato', confira: false });
  });
  it('sem nome: o documento mascarado', () => {
    expect(fraseDoPagoPor({ ...base, pagador_nome: null, pagador_documento: '12345678901', situacao: 'terceiro' })?.texto)
      .toBe('Pago por ***.456.789-** · pelo extrato');
  });
  it('nome que o banco escreveu com o CPF dentro: mascarado (terceiro e "confira")', () => {
    expect(fraseDoPagoPor({ ...base, pagador_nome: '12345678901-MARIA SOUZA', relacao: 'conjuge', situacao: 'terceiro' })?.texto)
      .toBe('Pago por ***.456.789-**-MARIA SOUZA (cônjuge) · pelo extrato');
    expect(fraseDoPagoPor({ ...base, pagador_nome: 'JOAO 123.456.789-01', situacao: 'indefinido' })?.texto)
      .toBe('Pago por JOAO ***.456.789-** · cliente sem CPF/CNPJ no cadastro, confira');
  });
  it('cliente, sem_dado e nada: nenhuma frase', () => {
    expect(fraseDoPagoPor({ ...base, pagador_nome: 'X', situacao: 'cliente' })).toBeNull();
    expect(fraseDoPagoPor({ ...base, pagador_nome: 'X', situacao: 'sem_dado' })).toBeNull();
    expect(fraseDoPagoPor(undefined)).toBeNull();
  });
});
