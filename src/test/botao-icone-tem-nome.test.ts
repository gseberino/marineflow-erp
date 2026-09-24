// Botão só de ícone precisa de nome acessível.
//
// POR QUE ISTO É UMA VARREDURA e não um teste de componente: o defeito não mora numa tela,
// mora no hábito. Um `<Button size="icon">` com `title="Excluir"` parece resolvido — mas
// `title` só aparece no hover do MOUSE. No celular ele nunca aparece, e o dono usa o
// sistema no iPhone: ali o botão vira um desenho sem legenda. Leitor de tela também o
// ignora, então uma lista de vinte linhas anuncia vinte botões chamados "botão".
//
// O que conta como nome: `aria-label`, `aria-labelledby` ou um `<span className="sr-only">`.
//
// SOBRE A DETECÇÃO — três tentativas erradas antes desta, e vale registrar por quê:
//
//  1ª (70 achados): apagava toda expressão `{...}` antes de procurar texto, e com isso
//     contava como "só ícone" botão cujo rótulo é dinâmico: `{t.imports.continueAuto}`,
//     `{entry.actionLabel}`, `{busy ? 'Salvando…' : 'Salvar'}`.
//  2ª (12 achados): passou a procurar texto entre `>` e `<`, mas o corpo do botão era
//     recortado com `/^<Button[\s\S]*?>/` — regex preguiçosa que para no PRIMEIRO `>`.
//     Em `onClick={() => x()}` esse `>` é o da seta, então metade dos atributos entrava
//     no "corpo" e virava texto falso.
//  3ª: sem sentinela na frente, texto ANTES do ícone não era visto — `Abrir Documento
//     <ArrowRight/>` passava por botão mudo.
//
// Daí a versão atual ler a tag de abertura caractere a caractere, ciente de aspas e de
// chaves, em vez de confiar em regex. E o teto ser ZERO: um número que sobra vira ruído
// de fundo e ninguém mais olha.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = process.cwd();
const PASTAS = ['src/pages', 'src/components', 'src/v2'];

function arquivosTsx(dir: string): string[] {
  const saida: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) saida.push(...arquivosTsx(p));
    else if (e.name.endsWith('.tsx') && !/\.test\.|\.smoke\./.test(e.name)) saida.push(p);
  }
  return saida;
}

export type Botao = { inicio: number; abertura: string; corpo: string };

/**
 * Acha onde a tag de abertura termina, respeitando aspas e chaves.
 *
 * É o que uma regex não faz: `onClick={() => setOpen(true)}` tem um `>` que não fecha
 * tag nenhuma, e `className="a>b"` também não.
 */
function fimDaAbertura(s: string, i: number): number {
  let chaves = 0;
  let aspa: string | null = null;
  for (let k = i; k < s.length; k++) {
    const c = s[k];
    if (aspa) {
      if (c === aspa) aspa = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { aspa = c; continue; }
    if (c === '{') { chaves++; continue; }
    if (c === '}') { chaves--; continue; }
    if (c === '>' && chaves === 0) return k;
  }
  return -1;
}

/** Todos os `<Button …>…</Button>` do arquivo, com o corpo recortado corretamente. */
export function botoesDe(s: string): Botao[] {
  const saida: Botao[] = [];
  for (const m of s.matchAll(/<Button[\s>]/g)) {
    const inicio = m.index!;
    const fim = fimDaAbertura(s, inicio);
    if (fim < 0) continue;
    if (s[fim - 1] === '/') continue;               // <Button … /> não tem corpo
    const fecha = s.indexOf('</Button>', fim);
    if (fecha < 0) continue;
    saida.push({ inicio, abertura: s.slice(inicio, fim + 1), corpo: s.slice(fim + 1, fecha) });
  }
  return saida;
}

/**
 * Separa o corpo do botão em: o que vira texto na tela, e as expressões filhas.
 *
 * Tem que ser um passo a passo, não regex: o corpo mistura tags (cujos atributos NÃO
 * aparecem na tela), expressões (que aparecem) e texto solto — e tanto `>` quanto `<`
 * ocorrem dentro de expressão (`{n > 0 ? …}`) sem fechar tag nenhuma.
 */
function conteudoDe(corpo: string): { texto: string; exprs: string[] } {
  let texto = '';
  const exprs: string[] = [];
  let i = 0;
  while (i < corpo.length) {
    const c = corpo[i];
    if (c === '<') {
      const fim = fimDaAbertura(corpo, i);
      i = fim < 0 ? corpo.length : fim + 1;
    } else if (c === '{') {
      const fim = fimDaExpressao(corpo, i);
      if (fim < 0) { i = corpo.length; } else { exprs.push(corpo.slice(i, fim + 1)); i = fim + 1; }
    } else {
      texto += c;
      i++;
    }
  }
  return { texto, exprs };
}

/** Fecha a chave contando aninhamento e ignorando o que está entre aspas. */
function fimDaExpressao(s: string, i: number): number {
  let chaves = 0;
  let aspa: string | null = null;
  for (let k = i; k < s.length; k++) {
    const c = s[k];
    if (aspa) {
      if (c === aspa) aspa = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { aspa = c; continue; }
    if (c === '{') { chaves++; continue; }
    if (c === '}') { chaves--; if (chaves === 0) return k; }
  }
  return -1;
}

/**
 * O botão mostra alguma palavra?
 *
 * Texto solto conta direto. Expressão conta quando carrega string literal, chamada de
 * tradução ou caminho `objeto.campo` — as três formas de rótulo dinâmico deste código.
 */
export function mostraTexto(corpo: string): boolean {
  const { texto, exprs } = conteudoDe(corpo);
  if (/[A-Za-zÀ-ÿ]{2,}/.test(texto)) return true;
  for (const expr of exprs) {
    if (/'[^']{2,}'|"[^"]{2,}"|`[^`]{2,}`/.test(expr)) return true;
    if (/\bt\s*[.(]/.test(expr)) return true;
    // Rótulo vindo de um campo: {ft.saveFilter}, {entry.actionLabel}, {item.nome}…
    if (/^\{\s*[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)+\s*\}$/.test(expr.replace(/\s+/g, ' '))) return true;
  }
  return false;
}

describe('botão de ícone tem nome acessível', () => {
  const semNome: Array<{ arquivo: string; linha: number; icone: string }> = [];

  for (const pasta of PASTAS) {
    const dir = path.join(RAIZ, pasta);
    if (!fs.existsSync(dir)) continue;
    for (const arquivo of arquivosTsx(dir)) {
      const s = fs.readFileSync(arquivo, 'utf8');
      for (const b of botoesDe(s)) {
        if (!/<[A-Z]\w*[\s/]/.test(b.corpo)) continue;         // não tem nem ícone
        if (mostraTexto(b.corpo)) continue;                     // tem rótulo visível
        if (/aria-label|sr-only|aria-labelledby/.test(b.abertura + b.corpo)) continue;
        semNome.push({
          arquivo: path.relative(RAIZ, arquivo),
          linha: s.slice(0, b.inicio).split('\n').length,
          icone: (b.corpo.match(/<([A-Z]\w*)/) || [])[1] ?? '?',
        });
      }
    }
  }

  it('todo botão só de ícone declara aria-label (ou sr-only)', () => {
    const lista = semNome.map((a) => `  ${a.arquivo}:${a.linha} (ícone ${a.icone})`).join('\n');
    expect(semNome, `Botão só de ícone sem nome acessível:\n${lista}\n\n` +
      'Acrescente aria-label dizendo o que o clique FAZ — "Remover o comprovante anexado",\n' +
      'não "Fechar". title não serve: some no celular e leitor de tela o ignora.').toEqual([]);
  });
});
