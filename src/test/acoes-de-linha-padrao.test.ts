// Linha de lista não vira fileira de botões.
//
// Pedido do dono, sobre o sistema inteiro: "apenas alguns botões de ações rápidas mais
// comuns para aquele tipo de item", o resto dentro do menu de três pontinhos. A tela de
// notas fiscais era o caso extremo — dez botões lado a lado ocupando metade da largura —
// mas o hábito reaparece em toda lista nova, então a regra mora aqui e não num code review.
//
// Três coisas quebram quando a fileira cresce: a linha fica larga demais para caber no
// celular, o olho não acha a ação que procura no meio das outras, e a ação perigosa
// ("cancelar a nota") ganha o mesmo peso visual da corriqueira ("baixar o PDF").
//
// O teto é DOIS botões soltos por célula. Passando disso, use <AcoesDaLinha>: ela põe as
// comuns à vista e o resto no menu, com o destrutivo isolado no fim.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = process.cwd();
const PASTAS = ['src/pages', 'src/components', 'src/v2'];
const TETO = 2;

function arquivosTsx(dir: string): string[] {
  const saida: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) saida.push(...arquivosTsx(p));
    else if (e.name.endsWith('.tsx') && !/\.test\.|\.smoke\./.test(e.name)) saida.push(p);
  }
  return saida;
}

/** Fim da tag de abertura, ciente de aspas e chaves (`onClick={() => x}` tem um `>`). */
function fimDaAbertura(s: string, i: number): number {
  let chaves = 0;
  let aspa: string | null = null;
  for (let k = i; k < s.length; k++) {
    const c = s[k];
    if (aspa) { if (c === aspa) aspa = null; continue; }
    if (c === '"' || c === "'" || c === '`') { aspa = c; continue; }
    if (c === '{') { chaves++; continue; }
    if (c === '}') { chaves--; continue; }
    if (c === '>' && chaves === 0) return k;
  }
  return -1;
}

/** Conteúdo de cada `<Tag …>…</Tag>`, contando aninhamento da mesma tag. */
function blocos(s: string, tag: string): Array<{ inicio: number; corpo: string }> {
  const saida: Array<{ inicio: number; corpo: string }> = [];
  for (const m of s.matchAll(new RegExp('<' + tag + '[\\s>]', 'g'))) {
    const inicio = m.index!;
    const fim = fimDaAbertura(s, inicio);
    if (fim < 0 || s[fim - 1] === '/') continue;
    let nivel = 1;
    let i = fim + 1;
    while (i < s.length && nivel > 0) {
      const prox = s.slice(i).search(new RegExp('</?' + tag + '[\\s>/]'));
      if (prox < 0) break;
      const at = i + prox;
      if (s[at + 1] === '/') { nivel--; i = at + tag.length + 3; }
      else { nivel++; const f = fimDaAbertura(s, at); i = f < 0 ? s.length : f + 1; }
    }
    saida.push({ inicio, corpo: s.slice(fim + 1, i) });
  }
  return saida;
}

describe('ações de uma linha de lista', () => {
  const fileiras: string[] = [];

  for (const pasta of PASTAS) {
    const dir = path.join(RAIZ, pasta);
    if (!fs.existsSync(dir)) continue;
    for (const arquivo of arquivosTsx(dir)) {
      const s = fs.readFileSync(arquivo, 'utf8');
      for (const tag of ['TableCell', 'td']) {
        for (const b of blocos(s, tag)) {
          const n = (b.corpo.match(/<Button[\s>]/g) ?? []).length;
          if (n <= TETO) continue;
          // Já usa o padrão (o próprio AcoesDaLinha, ou um menu escrito à mão).
          if (/DropdownMenu|AcoesDaLinha|MoreHorizontal|MoreVertical/.test(b.corpo)) continue;
          fileiras.push(
            `  ${path.relative(RAIZ, arquivo)}:${s.slice(0, b.inicio).split('\n').length} — ${n} botões`,
          );
        }
      }
    }
  }

  it('no máximo dois botões soltos por célula; o resto vai para o menu', () => {
    expect(fileiras, `Fileira de botões numa linha de lista:\n${fileiras.join('\n')}\n\n` +
      'Troque por <AcoesDaLinha rotulo="…" rapidas={[…]} menu={[…]} />: até duas ações\n' +
      'comuns ficam à vista e o resto vai para o menu de três pontinhos, com a ação\n' +
      'destrutiva marcada e isolada no fim.').toEqual([]);
  });
});
