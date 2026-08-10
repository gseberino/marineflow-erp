/**
 * Prende o CSS de um documento a uma raiz, para ele não vazar na página.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * Para baixar o PDF, o html2canvas exige o conteúdo renderizado no DOM — não
 * dá para capturar o que não foi desenhado. O jeito de fazer isso era jogar o
 * HTML do documento dentro de uma div do app, e junto ia o `<style>` dele:
 *
 *     * { margin: 0; padding: 0; }
 *     body { font-size: 11px; ... }
 *     h1, h2, h3 { text-transform: uppercase; ... }
 *
 * Regra global aplica ao documento inteiro. Durante a captura, a tela do ERP
 * perdia todas as margens, encolhia a fonte e virava caixa-alta nos títulos —
 * um solavanco visual de um segundo, que o dono descreveu como "distorce tudo
 * e depois baixa". Não era impressão dele: era o CSS do PDF pintando o app.
 *
 * Escopar resolve na origem, sem depender de iframe nem de truque de
 * posicionamento: cada seletor passa a valer só dentro da raiz do documento.
 */

/** Regras que NÃO podem ser escopadas — são de página ou de folha, não de elemento. */
const AT_RULES_SEM_ESCOPO = /^@(import|charset|namespace|page|font-face|keyframes|-webkit-keyframes)/i;

/**
 * Prefixa cada seletor com `root`.
 *
 * `:root`, `html` e `body` viram a própria raiz — dentro do documento embutido
 * é ela que faz esse papel. `*` vira `root *`, e não `root, root *`, porque a
 * raiz já recebe o que precisa pela regra de body.
 */
function prefixarSeletores(seletores: string, root: string): string {
  return seletores
    .split(',')
    .map((s) => {
      const sel = s.trim();
      if (!sel) return '';
      if (/^(:root|html|body)$/i.test(sel)) return root;
      if (sel === '*') return `${root} *`;
      // `body h1` e afins: troca o body pela raiz em vez de empilhar.
      if (/^(html|body)\s+/i.test(sel)) return `${root} ${sel.replace(/^(html|body)\s+/i, '')}`;
      return `${root} ${sel}`;
    })
    .filter(Boolean)
    .join(', ');
}

/**
 * Devolve o CSS com todos os seletores presos a `root`.
 *
 * Trata blocos aninhados (`@media { ... }`) recursivamente e deixa intactas as
 * at-rules que não descrevem elementos — `@page` continua valendo para a página
 * impressa, e escopá-la a quebraria.
 */
export function scopeCss(css: string, root: string): string {
  let saida = '';
  let i = 0;

  while (i < css.length) {
    // Comentário: copia inteiro.
    if (css.startsWith('/*', i)) {
      const fim = css.indexOf('*/', i + 2);
      const ate = fim < 0 ? css.length : fim + 2;
      saida += css.slice(i, ate);
      i = ate;
      continue;
    }

    // Acha o próximo `{` ou `;` — o que vier primeiro delimita a regra.
    const abre = css.indexOf('{', i);
    const pontoVirgula = css.indexOf(';', i);

    // At-rule sem corpo (`@import ...;`): copia como está.
    if (pontoVirgula >= 0 && (abre < 0 || pontoVirgula < abre)) {
      saida += css.slice(i, pontoVirgula + 1);
      i = pontoVirgula + 1;
      continue;
    }
    if (abre < 0) { saida += css.slice(i); break; }

    const prelude = css.slice(i, abre).trim();
    const espacos = css.slice(i, abre).match(/^\s*/)?.[0] ?? '';

    // Recorta o corpo respeitando aninhamento.
    let nivel = 1, j = abre + 1;
    while (j < css.length && nivel > 0) {
      if (css[j] === '{') nivel++;
      else if (css[j] === '}') nivel--;
      j++;
    }
    const corpo = css.slice(abre + 1, j - 1);

    if (AT_RULES_SEM_ESCOPO.test(prelude)) {
      saida += `${espacos}${prelude} {${corpo}}`;
    } else if (prelude.startsWith('@')) {
      // @media, @supports: o que vale é o conteúdo — escopa por dentro.
      saida += `${espacos}${prelude} {${scopeCss(corpo, root)}}`;
    } else {
      saida += `${espacos}${prefixarSeletores(prelude, root)} {${corpo}}`;
    }
    i = j;
  }

  return saida;
}
