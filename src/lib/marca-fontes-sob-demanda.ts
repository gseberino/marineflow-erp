// As fontes da marca na TELA chegam sob demanda (26/11/2026). As duas em base64 (~93 KB,
// supabase/functions/_shared/pdf/marca-fontes.ts) iam no pedaço compartilhado de toda tela de embarcação e de OS, porque
// o módulo da via (que importa marca.ts) é usado por elas mesmo sem montar folha nenhuma.
//
// Como: no build e no `vite dev`, o vite.config.ts troca o `./marca-fontes.ts` que o marca.ts importa por ESTE arquivo.
// Aqui as duas começam vazias e `carregarFontesDaMarca()` busca o arquivo de verdade por import dinâmico (pedaço próprio)
// e as preenche — o marca.ts lê os mesmos nomes (ligação viva do ES module), então a folha montada DEPOIS do carregamento
// sai com as fontes. Quem monta folha na tela espera o carregamento antes (printRouteSheet). Vazias, o marca.ts não
// emite @font-face e a folha sai na letra de reserva da pilha (Open Sans/Arial) — nunca quebra.
//
// O servidor (Deno) e o vitest não passam pelo vite.config.ts: usam o marca-fontes.ts de verdade, nada muda lá.

export let ARCHIVO_WOFF2_BASE64 = '';
export let HANKEN_GROTESK_WOFF2_BASE64 = '';

let carregando: Promise<void> | null = null;

/** Busca as fontes da marca (uma vez só; se falhar, a próxima chamada tenta de novo). */
export function carregarFontesDaMarca(): Promise<void> {
  carregando ??= import('../../supabase/functions/_shared/pdf/marca-fontes').then(
    (m) => {
      ARCHIVO_WOFF2_BASE64 = m.ARCHIVO_WOFF2_BASE64;
      HANKEN_GROTESK_WOFF2_BASE64 = m.HANKEN_GROTESK_WOFF2_BASE64;
    },
    (erro) => {
      carregando = null;
      throw erro;
    },
  );
  return carregando;
}
