// Smoke de render do painel de Cartões.
//
// O que se testa não é layout: é que a tela conta a verdade sobre o cartão. Ela nasceu de um
// pedido ("cartões é totalmente separado") e de uma descoberta que só apareceu quando o dado
// foi olhado — a fatura vem sendo paga em parte, e isso cobra juros.
//
// Se um dia alguém "melhorar" o casamento fatura ↔ pagamento afrouxando a tolerância, o
// saldo em aberto some da tela e a empresa perde de vista o rotativo que está pagando.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { CartoesPanel } from './CartoesPanel';

const { estado } = vi.hoisted(() => ({
  estado: {
    erro: null as Error | null,
    faturas: [
      {
        bill_id: 'b1', provider_account_id: 'acc1', compras: 41, compras_parceladas: 3,
        primeira_compra: '2026-06-18', ultima_compra: '2026-07-04',
        total: 4751.59, cartoes: '9395, 7130',
        pagamento_id: null, pagamento_data: null, pagamento_valor: null, pagamento_descricao: null,
      },
      {
        bill_id: 'b2', provider_account_id: 'acc1', compras: 64, compras_parceladas: 0,
        primeira_compra: '2026-04-17', ultima_compra: '2026-05-17',
        total: 7883.33, cartoes: '9395',
        pagamento_id: 'pg1', pagamento_data: '2026-05-25', pagamento_valor: 7883.33,
        pagamento_descricao: 'PGTO FATURA CARTAO C6',
      },
    ],
    // Pago a MENOS que o faturado: é o rotativo que a tela precisa denunciar.
    pagamentos: [
      { id: 'pg1', transaction_date: '2026-05-25', description: 'PGTO FATURA CARTAO C6', amount: 7883.33 },
      { id: 'pg2', transaction_date: '2026-07-28', description: 'PGTO FAT CARTAO C6', amount: 1000 },
    ],
    compras: [
      {
        id: 'c1', transaction_date: '2026-07-02', description: 'POSTO PAULINHO NAVEGANTE',
        amount: 250.4, counterparty_name: 'POSTO PAULINHO', payee_mcc: '5541',
        provider_category: 'Gas stations', card_last_digits: '9395', installment_label: null,
      },
    ],
  },
}));

vi.mock('@/hooks/use-cartoes', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-cartoes')>();
  return {
    ...real,
    useFaturasDoCartao: () => ({ data: estado.faturas, isLoading: false, error: estado.erro }),
    usePagamentosDeFatura: () => ({ data: estado.pagamentos, isLoading: false, error: null }),
    useEncargosDoCartao: () => ({ data: { quantidade: 42, total: 1830.55 }, isLoading: false, error: null }),
    useComprasSemFatura: () => ({ data: [{ id: 'x' }], isLoading: false, error: null }),
    useComprasDaFatura: () => ({ data: estado.compras, isLoading: false, error: null }),
  };
});

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><CartoesPanel /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('painel de cartões', () => {
  afterEach(() => { estado.erro = null; });

  it('abre com conteúdo, não em branco', async () => {
    renderPanel();
    expect(await screen.findByText('Cartões')).toBeInTheDocument();
  });

  it('diz que compra é despesa e fatura é o que se deve', async () => {
    // A distinção que o gestor pediu. Se a tela parar de afirmar isso, a confusão volta.
    renderPanel();
    expect(await screen.findByText(/é o que se deve/)).toBeInTheDocument();
  });

  it('mostra o SALDO EM ABERTO — faturado menos pago', async () => {
    // 4.751,59 + 7.883,33 = 12.634,92 faturado; 7.883,33 + 1.000 = 8.883,33 pago.
    // Sobram 3.751,59, que é o rotativo. Este número é a razão de a tela existir.
    renderPanel();
    expect(await screen.findByText('Saldo em aberto')).toBeInTheDocument();
    expect(screen.getByText(/3.751,59/)).toBeInTheDocument();
  });

  it('avisa que a fatura vem sendo paga em parte, e liga isso aos juros', async () => {
    renderPanel();
    expect(await screen.findByText(/fechou pelo valor exato/)).toBeInTheDocument();
    expect(screen.getByText(/42 lançamentos de juros/)).toBeInTheDocument();
  });

  it('separa fatura paga de fatura sem pagamento identificado', async () => {
    renderPanel();
    expect(await screen.findByText(/pagamento não identificado/)).toBeInTheDocument();
    expect(screen.getByText(/paga em/)).toBeInTheDocument();
  });

  it('abre a fatura e mostra a identificação que a compra de cartão TEM', async () => {
    // CNPJ não vem em compra de cartão — vem o ramo (MCC), a categoria do provedor e o
    // final do cartão. Foi exatamente a ausência disso que o gestor chamou de "péssimo".
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    // Pelo TOTAL da fatura, que é único. O período aparece em vários lugares da tela.
    const total = await screen.findByText(/4\.751,59/);
    await user.click(total.closest('button')!);
    expect(await screen.findByText('POSTO PAULINHO')).toBeInTheDocument();
    // Ramo (MCC) · categoria do provedor · cartão, tudo numa linha só — é a identificação
    // que existe em compra de cartão. O CNPJ não vem, e isso não é defeito: a bandeira não
    // repassa o documento do estabelecimento.
    expect(screen.getByText('Posto de combustível · Gas stations · cartão ····9395'))
      .toBeInTheDocument();
  });

  it('mostra o ERRO em vez de fingir que não há faturas', async () => {
    estado.erro = new Error('PGRST301: falha de permissão');
    renderPanel();
    expect(await screen.findByText(/Não deu para carregar as faturas/)).toBeInTheDocument();
    expect(screen.getByText(/PGRST301/)).toBeInTheDocument();
  });
});
