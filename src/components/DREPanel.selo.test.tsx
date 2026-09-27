// O selo de confiabilidade do DRE: a única coisa na tela que diz se o número abaixo serve
// para decidir. Um selo errado é pior que selo nenhum — daí o teste de comportamento.
//
// Medido em 22/09/2026: 38% das entradas do ano viraram receita, contra 96% das saídas.
// Desde 27/09/2026 o lado do banco é o fluxo pelo extrato (o mesmo do Resumo do mês) e a
// receita é a mesma da primeira linha do DRE.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { LancamentoDRE } from '@/lib/dre';

const { dados } = vi.hoisted(() => ({
  dados: { lancamentos: [] as unknown[], meses: [] as unknown[] },
}));

vi.mock('@/hooks/use-dre', () => ({
  useLancamentosDRE: () => ({ data: dados.lancamentos, isLoading: false }),
}));

vi.mock('@/hooks/use-fluxo-de-caixa', () => ({
  useFluxoDeCaixa: () => ({ data: { meses: dados.meses, total: {}, deFora: {} }, isLoading: false, error: null }),
}));

vi.mock('@/hooks/use-auth', () => ({
  useAuth: () => ({ user: { id: 'u1', role: 'admin' }, isAdmin: true, loading: false }),
}));

import { I18nProvider } from '@/i18n';
import { DREPanel } from './DREPanel';

const lanc = (valor: number, grupo: LancamentoDRE['grupo'], tipo: LancamentoDRE['tipo'], categoria = 'Serviços'): LancamentoDRE =>
  ({ data: '2026-01-15', valor, categoria, grupo, tipo });

const mesDoExtrato = (mes: string, entrou: number, saiu: number) => ({
  mes, entrou, saiu, liquido: entrou - saiu, quantidade: 1,
  transferencias: { entrou: 0, saiu: 0 }, creditoDoCartao: { entrou: 0, saiu: 0 },
});

/** Um período: receita e despesa lançadas, e o que entrou e saiu pelo extrato. */
function renderPainel(receita: number, entrada: number, despesa: number, saida: number, extra: LancamentoDRE[] = []) {
  dados.lancamentos = [
    ...(receita ? [lanc(receita, 'receita', 'receita')] : []),
    ...(despesa ? [lanc(despesa, 'custo_direto', 'despesa', 'Compras de mercadorias')] : []),
    ...extra,
  ];
  dados.meses = [mesDoExtrato('2026-01', entrada, saida)];
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><DREPanel /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('DRE — selo de confiabilidade', () => {
  it('receita bem abaixo da entrada: avisa que o resultado NÃO fecha e dá o valor que falta', async () => {
    // O ano real de 2026 até setembro: entrou R$ 501.686, lançado R$ 188.489.
    renderPainel(188489, 501686, 495250, 513104);
    expect(await screen.findByText(/Este resultado não fecha/i)).toBeInTheDocument();
    expect(screen.getByText(/38%/)).toBeInTheDocument();
    // O que falta é a diferença, não o total da entrada — é o número que vira tarefa.
    expect(screen.getByText(/313\.197/)).toBeInTheDocument();
    expect(screen.getByText(/parece pior do que é/i)).toBeInTheDocument();
  });

  it('entrada e lançamento batendo: libera o resultado para decidir', async () => {
    renderPainel(95000, 100000, 80000, 82000);
    expect(await screen.findByText(/Resultado confiável/i)).toBeInTheDocument();
    expect(screen.getByText(/95%/)).toBeInTheDocument();
    expect(screen.getByText(/pode ser usado para decidir/i)).toBeInTheDocument();
  });

  it('cobertura intermediária serve para tendência, não para precisão', async () => {
    renderPainel(70000, 100000, 80000, 82000);
    expect(await screen.findByText(/Resultado parcial/i)).toBeInTheDocument();
    expect(screen.getByText(/tendência/i)).toBeInTheDocument();
  });

  it('despesa acima de 100% é explicada como descasamento de data, não escondida', async () => {
    // Agosto real: R$ 23.284 emitidos contra R$ 21.137 que saíram do banco.
    renderPainel(95000, 100000, 23284, 21137);
    expect(await screen.findByText(/contada pela emissão e a saída do banco/i)).toBeInTheDocument();
  });

  it('sem movimento no banco no período, não inventa percentual', async () => {
    renderPainel(0, 0, 0, 0);
    // Nenhum dos veredictos aparece: não há o que comparar.
    expect(screen.queryByText(/Este resultado não fecha/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Resultado confiável/i)).not.toBeInTheDocument();
  });

  it('mostra a conta que sustenta o veredicto, não só o rótulo', async () => {
    renderPainel(188489, 501686, 495250, 513104);
    // O DRE também tem linhas chamadas "Receita"; o que importa é a linha da conta do selo,
    // que traz lançado E o total que passou pelo banco na mesma frase.
    const conta = await screen.findAllByText(/Receita lançada .* de .* que entrou/i);
    expect(conta.length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Despesa lançada .* de .* que saiu/i).length).toBeGreaterThan(0);
  });

  it('a receita do selo é a da primeira linha do DRE: entrada fora do grupo receita não conta', async () => {
    // R$ 50 mil de receita + R$ 45 mil de uma entrada classificada como não operacional
    // (ex.: dinheiro de empréstimo). Contra R$ 100 mil que entraram: 50%, não 95%.
    renderPainel(50000, 100000, 80000, 82000, [lanc(45000, 'nao_operacional', 'receita', 'Empréstimo')]);
    expect(await screen.findByText(/Este resultado não fecha/i)).toBeInTheDocument();
    expect(screen.getByText(/50%/)).toBeInTheDocument();
  });
});
