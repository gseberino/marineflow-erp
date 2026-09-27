// A raiz do CNPJ da empresa: uma leitura por sessão; se falhar, o fluxo falha junto (conferência
// final de 27/09/2026 — seguir sem ela mudava os números em silêncio).
import { describe, it, expect, vi, beforeEach } from 'vitest';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc } }));

describe('raiz do CNPJ da empresa', () => {
  beforeEach(() => {
    rpc.mockReset();
    vi.resetModules();
  });

  it('falha de leitura rejeita (a tela diz que não conseguiu ler) e a próxima chamada tenta de novo', async () => {
    const { lerRaizDaEmpresa } = await import('./use-fluxo-de-caixa');
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'sem rede' } });
    await expect(lerRaizDaEmpresa()).rejects.toMatchObject({ message: 'sem rede' });
    rpc.mockResolvedValueOnce({ data: '50057049', error: null });
    await expect(lerRaizDaEmpresa()).resolves.toBe('50057049');
    // Depois de ler, fica guardada: não chama o banco de novo.
    await expect(lerRaizDaEmpresa()).resolves.toBe('50057049');
    expect(rpc).toHaveBeenCalledTimes(2);
  });

  it('empresa sem CNPJ cadastrado não é erro: segue sem a raiz', async () => {
    const { lerRaizDaEmpresa } = await import('./use-fluxo-de-caixa');
    rpc.mockResolvedValueOnce({ data: null, error: null });
    await expect(lerRaizDaEmpresa()).resolves.toBeNull();
  });

  it('duas leituras ao mesmo tempo usam a mesma chamada', async () => {
    const { lerRaizDaEmpresa } = await import('./use-fluxo-de-caixa');
    rpc.mockResolvedValue({ data: '50057049', error: null });
    const [a, b] = await Promise.all([lerRaizDaEmpresa(), lerRaizDaEmpresa()]);
    expect([a, b]).toEqual(['50057049', '50057049']);
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});
