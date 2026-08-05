// Smoke do material sugerido pelo levantamento.
//
// A regra que mais importa: linha COM ALERTA não vem marcada. A quantidade sai
// de uma conta feita sobre texto digitado em campo — "2,5 m até o inversor e
// 2 m até o quadro" tem dois números e o motor lê o primeiro. Marcar tudo por
// padrão faria do aviso um enfeite, e o erro entraria numa proposta assinada.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { SuggestedMaterialsPanel } from './SuggestedMaterialsPanel';

const { estado, aplicados } = vi.hoisted(() => ({
  estado: { itens: [] as any[] },
  aplicados: [] as any[],
}));

vi.mock('@/hooks/use-survey-material-rules', async (orig) => {
  const real = await orig<any>();
  return {
    ...real,
    useSuggestedMaterials: () => ({ data: estado.itens, isLoading: false }),
    useApplySurveyMaterials: () => ({
      mutate: (args: any, opts: any) => {
        aplicados.push(args);
        opts?.onSuccess?.({ ok: true, mensagem: 'lançado' });
      },
      isPending: false,
    }),
  };
});

const limpo = {
  rule_id: 'r1', product_id: 'p1', product_name: 'Cabo flexível 35 mm²', unit: 'M',
  question: 'Qual a distância?', answer: '2,5 metros', quantity: 6,
  unit_sale: 145.16, unit_cost: 0, line_total: 870.96,
  rationale: 'ida e volta', alerta: null,
};
const comAlerta = {
  ...limpo, rule_id: 'r2', product_id: 'p2', product_name: 'Kit Mangueira',
  quantity: 2, line_total: 693,
  alerta: 'a resposta tem mais de um número: usei o primeiro (2.5)',
};

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <SuggestedMaterialsPanel surveyId="s1" serviceOrderId="os1" />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  estado.itens = [];
  aplicados.length = 0;
});

describe('material sugerido pelo levantamento', () => {
  it('sem sugestão, não ocupa espaço na tela', () => {
    const { container } = renderPanel();
    expect(container).toBeEmptyDOMElement();
  });

  it('mostra a quantidade calculada e de qual resposta ela saiu', () => {
    estado.itens = [limpo];
    renderPanel();
    expect(screen.getByText('Cabo flexível 35 mm²')).toBeInTheDocument();
    expect(screen.getByText(/6 M/)).toBeInTheDocument();
    expect(screen.getByText(/2,5 metros/)).toBeInTheDocument();
  });

  it('linha com alerta mostra o aviso e NÃO vem marcada', () => {
    estado.itens = [limpo, comAlerta];
    renderPanel();

    expect(screen.getByText(/mais de um número/)).toBeInTheDocument();
    const caixas = screen.getAllByRole('checkbox');
    expect(caixas[0]).toBeChecked();      // limpa
    expect(caixas[1]).not.toBeChecked();  // com alerta
  });

  it('lança apenas o que está marcado', async () => {
    estado.itens = [limpo, comAlerta];
    renderPanel();

    await userEvent.click(screen.getByRole('button', { name: /lançar no orçamento/i }));
    expect(aplicados).toHaveLength(1);
    expect(aplicados[0].ruleIds).toEqual(['r1']);
  });

  // Quem leu o aviso pode assumir a linha — o aviso é freio, não bloqueio.
  it('permite marcar a linha com alerta depois de ler', async () => {
    estado.itens = [limpo, comAlerta];
    renderPanel();

    await userEvent.click(screen.getAllByRole('checkbox')[1]);
    await userEvent.click(screen.getByRole('button', { name: /lançar no orçamento/i }));
    expect(aplicados[0].ruleIds).toEqual(['r1', 'r2']);
  });

  it('sem quantidade calculável, a linha não pode ser marcada', () => {
    estado.itens = [{ ...limpo, quantity: null, line_total: null, alerta: 'a resposta não tem número' }];
    renderPanel();
    expect(screen.getByRole('checkbox')).toBeDisabled();
  });
});
