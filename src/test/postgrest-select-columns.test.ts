import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * As colunas citadas em embed do PostgREST existem mesmo?
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * O PDF do sistema inteiro parou de ser gerado por causa de UMA palavra: o
 * embed em use-pdf.ts pedia `service_surveys(closed_at, ...)` e a coluna se
 * chama `answered_at`. O PostgREST não devolve o campo nulo nesse caso — ele
 * recusa a QUERY INTEIRA com 400. Como todos os botões de PDF são
 * `disabled={!pdfData}`, eles simplesmente pararam de funcionar, sem mensagem.
 *
 * Nada pegava isso: `tsc` não lê string, `vite build` não lê string, e os
 * testes de PDF usam dados montados à mão, sem tocar no banco. O erro só
 * aparecia em produção, e mesmo assim como botão morto.
 *
 * Este teste lê os `.select()` do código, extrai os embeds `tabela(colunas)` e
 * confere cada nome contra os tipos gerados do banco.
 */

const RAIZ = join(process.cwd(), 'src');
const TYPES = join(RAIZ, 'integrations', 'supabase', 'types.ts');

function arquivosTs(dir: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(dir)) {
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) {
      if (nome !== 'node_modules') arquivosTs(caminho, achados);
    } else if (/\.(ts|tsx)$/.test(nome) && !/\.test\.tsx?$/.test(nome)) {
      achados.push(caminho);
    }
  }
  return achados;
}

/**
 * Colunas de cada tabela/view, lidas do types.ts gerado.
 *
 * Parse por texto em vez de importar o tipo: os nomes precisam existir em
 * tempo de execução para serem comparados, e `Database` some na compilação.
 */
function colunasPorTabela(): Map<string, Set<string>> {
  const src = readFileSync(TYPES, 'utf8');
  const mapa = new Map<string, Set<string>>();
  // Cada entrada é `nome_da_tabela: { Row: { col: tipo ... } ... }`
  const re = /^ {6}(\w+): \{\n {8}Row: \{\n([\s\S]*?)\n {8}\}/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src))) {
    const cols = new Set<string>();
    for (const linha of m[2].split('\n')) {
      const c = linha.match(/^ {10}(\w+)\??:/);
      if (c) cols.add(c[1]);
    }
    if (cols.size) mapa.set(m[1], cols);
  }
  return mapa;
}

/** Embeds `tabela(col, col2, outra(col3))` dentro de um `.select(...)`. */
function embedsDe(select: string): Array<{ tabela: string; colunas: string[] }> {
  const achados: Array<{ tabela: string; colunas: string[] }> = [];
  const re = /(\w+)\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(select))) {
    const tabela = m[1];
    // Recorta o conteúdo dos parênteses respeitando aninhamento.
    let nivel = 1, i = re.lastIndex;
    while (i < select.length && nivel > 0) {
      if (select[i] === '(') nivel++;
      else if (select[i] === ')') nivel--;
      i++;
    }
    const dentro = select.slice(re.lastIndex, i - 1);
    // Só o primeiro nível: os aninhados vêm nas próximas voltas do laço.
    const colunas = dentro
      .replace(/\w+\s*\([^)]*\)/g, '')
      .split(',')
      .map((c) => c.trim())
      .filter((c) => c && !c.includes(':') && !c.includes('!') && /^\w+$/.test(c));
    achados.push({ tabela, colunas });
  }
  return achados;
}

describe('colunas usadas em embed do PostgREST existem no banco', () => {
  const tabelas = colunasPorTabela();

  it('os tipos gerados foram lidos', () => {
    expect(tabelas.size).toBeGreaterThan(50);
    expect(tabelas.get('service_surveys')).toBeDefined();
  });

  // A regressão exata que derrubou o PDF. Fica explícita para quem vier depois
  // entender de onde saiu o teste genérico abaixo.
  it('service_surveys tem answered_at e NÃO tem closed_at', () => {
    const cols = tabelas.get('service_surveys')!;
    expect(cols.has('answered_at')).toBe(true);
    expect(cols.has('closed_at')).toBe(false);
  });

  it('nenhum .select() cita coluna inexistente', () => {
    const problemas: string[] = [];

    for (const arquivo of arquivosTs(RAIZ)) {
      const src = readFileSync(arquivo, 'utf8');
      // `.select(\`...\`)` e `.select('...')`
      for (const m of src.matchAll(/\.select\(\s*[`'"]([\s\S]*?)[`'"]\s*[,)]/g)) {
        for (const { tabela, colunas } of embedsDe(m[1])) {
          const conhecidas = tabelas.get(tabela);
          if (!conhecidas) continue;  // função, alias ou hint — fora do escopo
          for (const col of colunas) {
            if (!conhecidas.has(col)) {
              problemas.push(
                `${arquivo.replace(process.cwd(), '')}: ${tabela}(${col}) — coluna não existe`,
              );
            }
          }
        }
      }
    }

    expect(problemas, problemas.join('\n')).toEqual([]);
  });
});
