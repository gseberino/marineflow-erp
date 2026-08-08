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
  // Normaliza a quebra de linha ANTES de casar.
  //
  // O `\n` da expressão não encontra nada num arquivo com CRLF, e o git deste repo
  // converte na checkout (core.autocrlf) — então o teste passava em quem o escreveu e
  // falhava em qualquer Windows, lendo ZERO tabelas. Falhar lendo zero é o pior modo:
  // sem tabela conhecida, a checagem de coluna inexistente vira `continue` em tudo e o
  // teste que existe para pegar regressão passa a aprovar qualquer coisa.
  const src = readFileSync(TYPES, 'utf8').replace(/\r\n/g, '\n');
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

/**
 * Quantas chaves estrangeiras ligam duas tabelas, contando as DUAS direções.
 *
 * Quando são duas ou mais, o PostgREST não adivinha qual usar num embed e
 * recusa a query com PGRST201 — o mesmo estrago do nome de coluna errado: a
 * query inteira morre. `service_orders` e `service_surveys` são o caso vivo:
 * a ordem aponta para o levantamento principal (`survey_id`) e o levantamento
 * aponta para a ordem (`service_order_id`).
 */
function relacoesEntre(): Map<string, number> {
  const src = readFileSync(TYPES, 'utf8');
  // Chaves DISTINTAS por par. Contar ocorrências não serve: os tipos gerados
  // repetem a mesma FK uma vez para cada view que referencia a tabela, e isso
  // faria `products` e `product_categories` — ligadas por uma chave só —
  // parecerem ambíguas. Foi o que a primeira versão deste teste acusou, em sete
  // queries que funcionam em produção há meses.
  const porPar = new Map<string, Set<string>>();

  // Recorta o bloco de CADA tabela antes de olhar dentro. Buscar
  // `Relationships:` com `[\s\S]*?` a partir do nome da tabela atravessa para a
  // tabela seguinte quando a atual tem `Relationships: []` — e aí as chaves de
  // uma são atribuídas à outra. Foi assim que a primeira versão deste parser
  // acusou `products → suppliers`, que tem uma chave só.
  const nomes = [...src.matchAll(/^ {6}(\w+): \{$/gm)];
  for (let i = 0; i < nomes.length; i++) {
    const tabela = nomes[i][1];
    const inicio = nomes[i].index!;
    const fim = i + 1 < nomes.length ? nomes[i + 1].index! : src.length;
    const bloco = src.slice(inicio, fim);

    for (const rel of bloco.matchAll(
      /foreignKeyName: "(\w+)"[\s\S]{0,200}?referencedRelation: "(\w+)"/g,
    )) {
      const par = [tabela, rel[2]].sort().join('|');
      if (!porPar.has(par)) porPar.set(par, new Set());
      porPar.get(par)!.add(rel[1]);
    }
  }
  return new Map([...porPar].map(([par, fks]) => [par, fks.size]));
}

/**
 * Embeds de um `.select(...)`, com o PAI de cada um.
 *
 * O pai importa: em `service_orders(… service_order_technicians(app_users(…)))`
 * o `app_users` pende de `service_order_technicians`, não de `service_orders`.
 * Tratar todo embed como filho do `.from()` acusa ambiguidade onde não há —
 * foi o que a primeira versão fez com a query da agenda, que roda em produção.
 */
function embedsDe(
  select: string,
  raiz = '',
): Array<{ tabela: string; pai: string; colunas: string[] }> {
  const achados: Array<{ tabela: string; pai: string; colunas: string[] }> = [];

  function percorrer(trecho: string, pai: string) {
    const re = /(\w+)\s*(?:!\s*\w+\s*)?\(/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(trecho))) {
      const tabela = m[1];
      let nivel = 1, i = re.lastIndex;
      while (i < trecho.length && nivel > 0) {
        if (trecho[i] === '(') nivel++;
        else if (trecho[i] === ')') nivel--;
        i++;
      }
      const dentro = trecho.slice(re.lastIndex, i - 1);

      const colunas = dentro
        .replace(/\w+\s*(?:!\s*\w+\s*)?\([^)]*\)/g, '')
        .split(',')
        .map((c) => c.trim())
        .filter((c) => c && !c.includes(':') && !c.includes('!') && /^\w+$/.test(c));

      achados.push({ tabela, pai, colunas });
      percorrer(dentro, tabela);   // os aninhados pendem DESTE embed
      re.lastIndex = i;            // não reprocessa o que já foi consumido
    }
  }

  percorrer(select, raiz);
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
      for (const m of src.replace(/\r\n/g, '\n').matchAll(/\.select\(\s*[`'"]([\s\S]*?)[`'"]\s*[,)]/g)) {
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

/**
 * A segunda metade do mesmo estrago.
 *
 * Corrigido o nome da coluna, o PDF continuou sem gerar — desta vez por
 * PGRST201: duas chaves estrangeiras ligam service_orders e service_surveys, e
 * sem `!nome_da_fk` o PostgREST recusa a query inteira. Mesmo sintoma, causa
 * diferente. O teste de colunas não pegava, então este cobre o resto.
 */
describe('embeds entre tabelas com mais de uma chave estrangeira', () => {
  const relacoes = relacoesEntre();

  it('os relacionamentos foram lidos dos tipos', () => {
    expect(relacoes.size).toBeGreaterThan(50);
  });

  it('service_orders e service_surveys são o par ambíguo conhecido', () => {
    const par = ['service_orders', 'service_surveys'].sort().join('|');
    expect(relacoes.get(par)).toBeGreaterThan(1);
  });

  it('todo embed de par ambíguo declara qual chave usar', () => {
    const problemas: string[] = [];

    for (const arquivo of arquivosTs(RAIZ)) {
      const src = readFileSync(arquivo, 'utf8');
      for (const m of src.matchAll(/\.from\(\s*['"](\w+)['"]\s*\)([\s\S]{0,400}?)\.select\(\s*[`'"]([\s\S]*?)[`'"]\s*[,)]/g)) {
        const raiz = m[1];
        const select = m[3];
        for (const { tabela, pai } of embedsDe(select, raiz)) {
          const par = [pai, tabela].sort().join('|');
          if ((relacoes.get(par) ?? 0) <= 1) continue;
          // O hint vem colado no nome: `tabela!nome_da_fk(...)`.
          const temHint = new RegExp(`${tabela}\\s*!\\s*\\w+\\s*\\(`).test(select);
          if (!temHint) {
            problemas.push(
              `${arquivo.replace(process.cwd(), '')}: ${pai} → ${tabela}(…) sem ` +
              '`!nome_da_fk` — há mais de uma chave entre as duas tabelas, o PostgREST ' +
              'recusa a query inteira com PGRST201',
            );
          }
        }
      }
    }

    expect(problemas, problemas.join('\n')).toEqual([]);
  });
});
