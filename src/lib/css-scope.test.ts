import { describe, it, expect } from 'vitest';
import { scopeCss } from './css-scope';

const R = '.pdf-root';
const limpo = (s: string) => s.replace(/\s+/g, ' ').trim();

/**
 * O CSS do documento vazava para o app durante a captura do PDF: por um
 * segundo a tela do ERP perdia as margens (`* { margin: 0 }`), encolhia a
 * fonte (`body { font-size: 11px }`) e ficava caixa-alta nos títulos. Estes
 * testes travam o escopo — e, com ele, as regras que mais estragavam.
 */
describe('escopo do CSS do documento', () => {
  it('a regra universal deixa de valer para a página toda', () => {
    expect(limpo(scopeCss('* { margin:0; }', R))).toBe('.pdf-root * { margin:0; }');
  });

  it('body e :root viram a própria raiz', () => {
    expect(limpo(scopeCss('body { font-size: 11px; }', R))).toBe('.pdf-root { font-size: 11px; }');
    expect(limpo(scopeCss(':root { --pdf-primary: #002B5B; }', R)))
      .toBe('.pdf-root { --pdf-primary: #002B5B; }');
  });

  it('seletor de elemento passa a valer só dentro da raiz', () => {
    expect(limpo(scopeCss('h1, h2, h3 { text-transform: uppercase; }', R)))
      .toBe('.pdf-root h1, .pdf-root h2, .pdf-root h3 { text-transform: uppercase; }');
  });

  it('descendente de body não empilha body', () => {
    expect(limpo(scopeCss('body table { width: 100%; }', R)))
      .toBe('.pdf-root table { width: 100%; }');
  });

  // @media descreve elementos: o conteúdo tem que ser escopado por dentro.
  it('escopa o que está dentro de @media', () => {
    const r = limpo(scopeCss('@media print { .container { padding: 0; } }', R));
    expect(r).toBe('@media print { .pdf-root .container { padding: 0; } }');
  });

  // @page descreve a PÁGINA, não um elemento. Escopar quebraria a margem do
  // papel — e é ela que dá os 12mm do documento impresso.
  it('NÃO escopa @page', () => {
    const r = limpo(scopeCss('@page { margin: 12mm; size: A4; }', R));
    expect(r).toBe('@page { margin: 12mm; size: A4; }');
  });

  it('@page dentro de @media também fica intacta', () => {
    const r = limpo(scopeCss('@media print { @page { margin: 12mm; } .x { color: red; } }', R));
    expect(r).toContain('@page { margin: 12mm; }');
    expect(r).toContain('.pdf-root .x');
  });

  it('preserva @import, que precisa continuar no topo da folha', () => {
    const css = "@import url('https://fonts.googleapis.com/css2?family=Inter');\nh1 { color: red; }";
    const r = scopeCss(css, R);
    expect(r.trimStart().startsWith('@import')).toBe(true);
    expect(limpo(r)).toContain('.pdf-root h1');
  });

  it('não confunde chave dentro de comentário', () => {
    const r = limpo(scopeCss('/* nota { com chave } */ p { margin: 4px; }', R));
    expect(r).toContain('.pdf-root p');
    expect(r).toContain('/* nota { com chave } */');
  });

  it('aguenta regra aninhada em vários níveis sem perder o fecho', () => {
    const r = scopeCss('@media print { @media (min-width: 1px) { .a { color: red; } } }', R);
    expect((r.match(/\{/g) || []).length).toBe((r.match(/\}/g) || []).length);
    expect(limpo(r)).toContain('.pdf-root .a');
  });

  it('CSS vazio não vira lixo', () => {
    expect(scopeCss('', R)).toBe('');
  });
});

// Vírgula nem sempre separa seletor: dentro de :is()/:not()/:where() ou de um
// valor de atributo ela é parte dele, e a raiz tem de ficar do lado de fora.
// Antes saía `.pdf-root :is(h1, .pdf-root h2)` — silencioso, só deixava de aplicar.
describe('vírgula dentro de parênteses, colchetes e aspas', () => {
  it(':is(h1, h2) recebe a raiz uma vez, do lado de fora', () => {
    expect(limpo(scopeCss(':is(h1, h2) { margin: 0; }', R)))
      .toBe('.pdf-root :is(h1, h2) { margin: 0; }');
  });

  it(':not() com lista — o que alguém escreve ao ajustar espaçamento de tabela', () => {
    expect(limpo(scopeCss('tr:not(:last-child, .total) td { border-bottom: 1px solid; }', R)))
      .toBe('.pdf-root tr:not(:last-child, .total) td { border-bottom: 1px solid; }');
  });

  it('parênteses aninhados contam profundidade, não só o primeiro nível', () => {
    expect(limpo(scopeCss(':where(:not(.a, .b), .c) { color: red; }', R)))
      .toBe('.pdf-root :where(:not(.a, .b), .c) { color: red; }');
  });

  it('vírgula entre aspas de atributo não divide', () => {
    expect(limpo(scopeCss('[title="a,b"] { color: red; }', R)))
      .toBe('.pdf-root [title="a,b"] { color: red; }');
    expect(limpo(scopeCss("[title='a,b'] { color: red; }", R)))
      .toBe(".pdf-root [title='a,b'] { color: red; }");
  });

  it('parêntese dentro de aspas não abre nível', () => {
    // Um `(` literal no valor deixaria o nível aberto e engoliria a vírgula seguinte.
    expect(limpo(scopeCss('[data-x="(a"], h2 { color: red; }', R)))
      .toBe('.pdf-root [data-x="(a"], .pdf-root h2 { color: red; }');
  });

  it('lista simples continua virando um seletor escopado por item', () => {
    expect(limpo(scopeCss('h1, :is(h2, h3), h4 { margin: 0; }', R)))
      .toBe('.pdf-root h1, .pdf-root :is(h2, h3), .pdf-root h4 { margin: 0; }');
  });

  it('body dentro de :is() não vira a raiz — a troca é por seletor inteiro', () => {
    expect(limpo(scopeCss(':is(body, h1) { margin: 0; }', R)))
      .toBe('.pdf-root :is(body, h1) { margin: 0; }');
  });
});
