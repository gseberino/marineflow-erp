import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * O CSS do documento não pode disputar nomes com o CSS do app.
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * O PDF baixado saía sem várias cores, enquanto o impresso saía perfeito. A
 * diferença entre os dois caminhos explica tudo:
 *
 *  · IMPRIMIR abre uma janela nova e escreve o HTML lá. Só o CSS do documento
 *    existe naquele contexto.
 *  · BAIXAR insere o HTML no DOM DO APP para o html2canvas capturar. Ali o CSS
 *    do app está presente — e ele define `--primary`, `--secondary` e
 *    `--border`, os mesmos nomes que o documento usava.
 *
 * Os formatos são incompatíveis: o app guarda `36 48% 59%` (números soltos, o
 * padrão do shadcn, para uso dentro de `hsl(...)`), e o documento esperava
 * `#002B5B`. Quando o valor do app vencia, `color: var(--primary)` virava
 * `color: 36 48% 59%` — declaração inválida, descartada em silêncio, elemento
 * sem cor.
 *
 * Nada disso aparece em teste de unidade do gerador (o HTML sai correto como
 * string) nem no tsc. Só na captura, e só quando o app está por perto.
 */

const GERADOR = join(process.cwd(), 'src', 'lib', 'pdf-generator.ts');
const CSS_DO_APP = join(process.cwd(), 'src', 'index.css');

/** Nomes de variável definidos pelo app — o território proibido. */
function variaveisDoApp(): Set<string> {
  const src = readFileSync(CSS_DO_APP, 'utf8');
  const nomes = new Set<string>();
  for (const m of src.matchAll(/^\s*(--[\w-]+):/gm)) nomes.add(m[1]);
  return nomes;
}

/** Nomes de variável que o gerador de PDF usa. */
function variaveisDoPdf(): Set<string> {
  const src = readFileSync(GERADOR, 'utf8');
  const nomes = new Set<string>();
  for (const m of src.matchAll(/var\((--[\w-]+)\)/g)) nomes.add(m[1]);
  for (const m of src.matchAll(/^\s*(--[\w-]+):\s*#/gm)) nomes.add(m[1]);
  return nomes;
}

describe('isolamento do CSS do documento', () => {
  const doApp = variaveisDoApp();
  const doPdf = variaveisDoPdf();

  it('leu os dois conjuntos de variáveis', () => {
    expect(doApp.size).toBeGreaterThan(10);
    expect(doPdf.size).toBeGreaterThan(5);
  });

  it('o app realmente define os nomes genéricos', () => {
    // Se um dia o app parar de usar estes nomes, o teste abaixo perde o
    // sentido — e é bom que alguém perceba lendo este aqui.
    expect(doApp.has('--primary')).toBe(true);
    expect(doApp.has('--border')).toBe(true);
  });

  it('NENHUMA variável do PDF colide com o app', () => {
    const colisoes = [...doPdf].filter((v) => doApp.has(v));
    expect(
      colisoes,
      `O CSS do PDF usa ${colisoes.join(', ')}, que o app também define com ` +
      'outro formato. Ao baixar, o documento é inserido no DOM do app e a cor ' +
      'se perde. Use o prefixo --pdf-.',
    ).toEqual([]);
  });

  it('as variáveis do PDF são prefixadas', () => {
    const semPrefixo = [...doPdf].filter((v) => !v.startsWith('--pdf-'));
    expect(semPrefixo, `sem prefixo: ${semPrefixo.join(', ')}`).toEqual([]);
  });

  // Cada var() precisa de uma definição, senão a cor some do mesmo jeito —
  // agora por falta de valor em vez de por conflito.
  it('toda variável usada está definida no :root do documento', () => {
    const src = readFileSync(GERADOR, 'utf8');
    const definidas = new Set(
      [...src.matchAll(/^\s*(--pdf-[\w-]+):\s*#/gm)].map((m) => m[1]),
    );
    const usadas = [...src.matchAll(/var\((--pdf-[\w-]+)\)/g)].map((m) => m[1]);
    const orfas = [...new Set(usadas)].filter((v) => !definidas.has(v));
    expect(orfas, `usadas sem definição: ${orfas.join(', ')}`).toEqual([]);
  });
});
