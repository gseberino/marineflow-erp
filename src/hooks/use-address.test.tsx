// useAddress (04/10/2026). O que se protege: as buscas no IBGE respondem depois — a resposta de
// um estado antigo não sobrescreve as cidades do estado escolhido por último. (A outra metade da
// correção — não atualizar nada depois que a tela fecha, que no CI derrubava a suíte com "window
// is not defined" — só se manifesta com o ambiente de teste desmontado e não dá para reproduzir
// aqui.) Sem rede: o fetch é falso e cada resposta é liberada na ordem que o teste escolher.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { act, renderHook, waitFor } from '@testing-library/react';
import { useAddress } from './use-address';

type Pendente = { url: string; responder: (corpo: unknown) => void };

function fetchControlado() {
  const pendentes: Pendente[] = [];
  const fn = vi.fn((url: string) => new Promise<Response>((ok) => {
    pendentes.push({ url, responder: (corpo) => ok({ json: async () => corpo } as Response) });
  }));
  return { fn, pendentes, achar: (trecho: string) => pendentes.find((p) => p.url.includes(trecho))! };
}

afterEach(() => vi.unstubAllGlobals());

describe('useAddress', () => {
  it('trocar de estado rápido: só valem as cidades do último estado escolhido', async () => {
    const f = fetchControlado();
    vi.stubGlobal('fetch', f.fn);
    const { result } = renderHook(() => useAddress());

    act(() => result.current.setSelectedState('SP'));
    act(() => result.current.setSelectedState('RJ'));

    await act(async () => f.achar('/estados/RJ/').responder([{ nome: 'Rio de Janeiro' }]));
    await act(async () => f.achar('/estados/SP/').responder([{ nome: 'São Paulo' }]));

    await waitFor(() => expect(result.current.citiesLoading).toBe(false));
    expect(result.current.selectedState).toBe('RJ');
    expect(result.current.cities).toEqual(['Rio de Janeiro']);
  });

  it('limpar o estado limpa as cidades e uma resposta atrasada não as traz de volta', async () => {
    const f = fetchControlado();
    vi.stubGlobal('fetch', f.fn);
    const { result } = renderHook(() => useAddress());

    act(() => result.current.setSelectedState('SC'));
    act(() => result.current.setSelectedState(''));
    await act(async () => f.achar('/estados/SC/').responder([{ nome: 'Florianópolis' }]));

    expect(result.current.cities).toEqual([]);
    expect(result.current.citiesLoading).toBe(false);
  });
});
