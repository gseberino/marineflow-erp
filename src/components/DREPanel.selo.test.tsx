// O selo de confiabilidade do DRE: a única coisa na tela que diz se o número abaixo serve
// para decidir. Um selo errado é pior que selo nenhum — daí o teste de comportamento.
//
// Medido em 22/09/2026: 38% das entradas do ano viraram receita, contra 96% das saídas.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const { rpcMock } = vi.hoisted(() => ({ rpcMock: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => {
  const builder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'gte', 'lte', 'order', 'in', 'is', 'not', 'limit']) o[k] = () => o;
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  return { supabase: { from: () => builder(), rpc: rpcMock } };
});

vi.mock('@/hooks/use-auth', () => ({
  useAuth: () => ({ user: { id: 'u1', role: 'admin' }, isAdmin: true, loading: false }),
}));

import { I18nProvider } from '@/i18n';
import { DREPanel } from './DREPanel';

/** Um mês de cobertura, no formato que a função `dre_cobertura` devolve. */
function mesDe(mes: number, receita: number, entrada: number, despesa: number, saida: number) {
  return { mes, receita_lancada: receita, entrada_banco: entrada, despesa_lancada: despesa, saida_banco: saida };
}

function renderPainel(linhas: ReturnType<typeof mesDe>[]) {
  rpcMock.mockReset();
  rpcMock.mockResolvedValue({ data: linhas, error: null });
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
    renderPainel([mesDe(1, 188489, 501686, 495250, 513104)]);
    expect(await screen.findByText(/Este resultado não fecha/i)).toBeInTheDocument();
    expect(screen.getByText(/38%/)).toBeInTheDocument();
    // O que falta é a diferença, não o total da entrada — é o número que vira tarefa.
    expect(screen.getByText(/313\.197/)).toBeInTheDocument();
    expect(screen.getByText(/parece pior do que é/i)).toBeInTheDocument();
  });

  it('entrada e lançamento batendo: libera o resultado para decidir', async () => {
    renderPainel([mesDe(1, 95000, 100000, 80000, 82000)]);
    expect(await screen.findByText(/Resultado confiável/i)).toBeInTheDocument();
    expect(screen.getByText(/95%/)).toBeInTheDocument();
    expect(screen.getByText(/pode ser usado para decidir/i)).toBeInTheDocument();
  });

  it('cobertura intermediária serve para tendência, não para precisão', async () => {
    renderPainel([mesDe(1, 70000, 100000, 80000, 82000)]);
    expect(await screen.findByText(/Resultado parcial/i)).toBeInTheDocument();
    expect(screen.getByText(/tendência/i)).toBeInTheDocument();
  });

  it('despesa acima de 100% é explicada como descasamento de data, não escondida', async () => {
    // Agosto real: R$ 23.284 emitidos contra R$ 21.137 que saíram do banco.
    renderPainel([mesDe(1, 95000, 100000, 23284, 21137)]);
    expect(await screen.findByText(/contada pela emissão e a saída do banco/i)).toBeInTheDocument();
  });

  it('sem movimento no banco no período, não inventa percentual', async () => {
    renderPainel([mesDe(1, 0, 0, 0, 0)]);
    // Nenhum dos veredictos aparece: não há o que comparar.
    expect(screen.queryByText(/Este resultado não fecha/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Resultado confiável/i)).not.toBeInTheDocument();
  });

  it('mostra a conta que sustenta o veredicto, não só o rótulo', async () => {
    renderPainel([mesDe(1, 188489, 501686, 495250, 513104)]);
    // O DRE também tem linhas chamadas "Receita"; o que importa é a linha da conta do selo,
    // que traz lançado E o total que passou pelo banco na mesma frase.
    const conta = await screen.findAllByText(/Receita lançada .* de .* que entrou/i);
    expect(conta.length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Despesa lançada .* de .* que saiu/i).length).toBeGreaterThan(0);
  });
});
