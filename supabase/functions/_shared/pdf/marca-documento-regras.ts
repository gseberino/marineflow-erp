// Regras de TESTE da marca nos documentos do cliente (26/11/2026), usadas pelo Deno (marca-documento_test.ts) e pelo
// vitest (src/lib/pdf-marca.test.ts). Não entra em documento nenhum: só lê o HTML pronto.

/** O azul da marca: texto pequeno nunca mais claro que ele (o cinza de antes sumia no modo rascunho da impressora). */
export const AZUL_DA_MARCA = '#274A6D';

/**
 * As cores de situação (desconto e "vencido" em vermelho, "pago" em verde, "parcial" em âmbar): são saturadas e saem
 * no rascunho, mas são mais claras que o azul pela luminância. Já escurecidas em 26/11/2026 (eram #dc2626, #16a34a e
 * #d97706). Fora delas, branco (texto sobre faixa marinho) e as próprias da marca.
 */
const CORES_DE_SITUACAO = new Set(['#b91c1c', '#15803d', '#b45309', '#166534']);

function hex6(cor: string): string | null {
  const c = cor.trim().toLowerCase();
  if (/^#[0-9a-f]{6}$/.test(c)) return c;
  if (/^#[0-9a-f]{3}$/.test(c)) return `#${c[1]}${c[1]}${c[2]}${c[2]}${c[3]}${c[3]}`;
  return null;
}

/** Luminância relativa (WCAG) de uma cor #rrggbb. */
export function luminancia(cor: string): number {
  const h = hex6(cor);
  if (!h) return NaN;
  const canal = (i: number) => {
    const v = parseInt(h.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * canal(1) + 0.7152 * canal(3) + 0.0722 * canal(5);
}

/**
 * As cores de TEXTO (`color:`, não `background-color` nem `border-color`) do HTML que são mais claras que o azul da
 * marca. `var(--pdf-…)` é resolvida pelo :root do próprio documento. Devolve a lista das que sobram (vazia = ok).
 */
export function coresDeTextoClarasDemais(html: string): string[] {
  const variaveis = new Map<string, string>();
  for (const m of html.matchAll(/(--pdf-[\w-]+):\s*(#[0-9A-Fa-f]{3,6})\b/g)) variaveis.set(m[1], m[2]);
  const limite = luminancia(AZUL_DA_MARCA) + 0.001;
  const ruins = new Set<string>();
  for (const m of html.matchAll(/(?<![-\w])color\s*:\s*([^;"}]+)/g)) {
    const valor = m[1].trim();
    const v = valor.match(/^var\((--pdf-[\w-]+)\)$/);
    const cor = hex6(v ? variaveis.get(v[1]) ?? '' : valor);
    if (!cor) {
      // inherit, currentColor, transparent: não é cor de texto própria.
      if (/^(inherit|currentcolor|transparent)$/i.test(valor)) continue;
      ruins.add(`${valor} (não resolvida)`);
      continue;
    }
    if (cor === '#ffffff' || CORES_DE_SITUACAO.has(cor)) continue;
    if (luminancia(cor) > limite) ruins.add(v ? `${valor} = ${cor}` : cor);
  }
  return [...ruins];
}

/** Os caracteres do TEXTO do documento (fora de <style>, <svg> e das tags) que a Open Sans do servidor não desenha. */
export function caracteresForaDaFonteDoServidor(html: string, faixas: ReadonlyArray<readonly [number, number]>): string[] {
  const texto = html
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<svg[\s\S]*?<\/svg>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&[#\w]+;/g, ' ');
  const tem = (c: number) => faixas.some(([a, b]) => c >= a && c <= b);
  const fora = new Set<string>();
  for (const ch of texto) {
    const c = ch.codePointAt(0)!;
    if (c > 0x7e && !tem(c)) fora.add(`${ch} U+${c.toString(16).toUpperCase().padStart(4, '0')}`);
  }
  return [...fora];
}
