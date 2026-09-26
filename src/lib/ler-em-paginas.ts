/**
 * Lê TODAS as linhas de uma consulta, em páginas.
 *
 * O servidor entrega no máximo 1.000 linhas por pedido e corta o resto sem avisar: uma
 * lista truncada tem a mesma cara de uma lista completa. Foi assim que Contas a Pagar
 * apareceu vazia (as 5 em aberto estavam nas posições 1.683 a 1.706 de 1.706) e que o DRE
 * de 2026 perdeu ~35 despesas sem aviso (26/09/2026).
 *
 * A consulta PRECISA ter ordem estável (terminar em uma coluna única, como `id`): paginar
 * sem ordem faz uma linha aparecer em duas páginas e outra em nenhuma.
 */
export const TAMANHO_DA_PAGINA = 1000;

export async function lerEmPaginas<T>(
  pagina: (de: number, ate: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
  teto = 50_000,
): Promise<T[]> {
  const tudo: T[] = [];
  for (let de = 0; de < teto; de += TAMANHO_DA_PAGINA) {
    const { data, error } = await pagina(de, de + TAMANHO_DA_PAGINA - 1);
    if (error) throw error;
    const lote = data ?? [];
    tudo.push(...lote);
    if (lote.length < TAMANHO_DA_PAGINA) break;
  }
  return tudo;
}
