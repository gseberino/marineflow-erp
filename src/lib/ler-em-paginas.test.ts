// O servidor corta em 1.000 linhas sem avisar; a lista tem de vir inteira.
import { describe, it, expect, vi } from 'vitest';
import { lerEmPaginas, TAMANHO_DA_PAGINA } from './ler-em-paginas';

describe('lerEmPaginas', () => {
  it('junta as páginas até a última vir incompleta', async () => {
    const total = TAMANHO_DA_PAGINA * 2 + 7;
    const pagina = vi.fn(async (de: number, ate: number) => ({
      data: Array.from({ length: Math.max(0, Math.min(ate, total - 1) - de + 1) }, (_, i) => de + i),
      error: null,
    }));
    const tudo = await lerEmPaginas(pagina);
    expect(tudo).toHaveLength(total);
    expect(pagina).toHaveBeenCalledTimes(3);
    expect(tudo[total - 1]).toBe(total - 1);
  });

  it('erro de qualquer página vira erro — nada de lista pela metade', async () => {
    const pagina = vi.fn()
      .mockResolvedValueOnce({ data: Array(TAMANHO_DA_PAGINA).fill(1), error: null })
      .mockResolvedValueOnce({ data: null, error: new Error('caiu') });
    await expect(lerEmPaginas(pagina)).rejects.toThrow('caiu');
  });
});
