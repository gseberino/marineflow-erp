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
 * O que a varredura lê: todo o front e a montagem do PDF, que mora em _shared/pdf desde
 * 25/09/2026 para o assistente do WhatsApp gerar o mesmo documento. Foi a consulta DELA
 * que motivou este teste — sair de src/ não pode tirá-la da vigilância.
 */
const PDF_COMPARTILHADO = join(process.cwd(), 'supabase', 'functions', '_shared', 'pdf');
/**
 * Todas as funções do servidor, não só o PDF (02/10/2026): a ferramenta do assistente
 * gastos_por_categoria pedia `payees(name)` de `payables`, que tem DUAS chaves para payees
 * (payee_id e beneficiario_id). O PostgREST recusava a consulta, a ferramenta engolia o erro e
 * o assistente respondeu ao dono "não há nenhuma despesa em setembro". Fora da varredura,
 * ninguém via.
 */
const FUNCOES = join(process.cwd(), 'supabase', 'functions');
function arquivosVarridos(): string[] {
  return [...arquivosTs(RAIZ), ...arquivosTs(FUNCOES).filter((f) => !/_test\.ts$/.test(f))];
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
  // Mesma normalização de `colunasPorTabela`, e pelo mesmo motivo: `^ {6}(\w+): \{$` não
  // casa nada num arquivo com CRLF, porque o `\r` fica entre o `{` e o fim da linha. Sem
  // isso este parser devolve ZERO relações no Windows — e um verificador de ambiguidade
  // que não encontra relação nenhuma aprova qualquer query, que é justamente o modo de
  // falha contra o qual este arquivo inteiro foi escrito.
  const src = readFileSync(TYPES, 'utf8').replace(/\r\n/g, '\n');
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
  it('a montagem do PDF está na varredura', () => {
    expect(arquivosVarridos().some((f) => f.endsWith(join('_shared', 'pdf', 'dados.ts')))).toBe(true);
  });

  it('service_surveys tem answered_at e NÃO tem closed_at', () => {
    const cols = tabelas.get('service_surveys')!;
    expect(cols.has('answered_at')).toBe(true);
    expect(cols.has('closed_at')).toBe(false);
  });

  it('nenhum .select() cita coluna inexistente', () => {
    const problemas: string[] = [];

    for (const arquivo of arquivosVarridos()) {
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

  // As colunas do PRIMEIRO nível também (02/10/2026): o teste de cima só olhava dentro dos
  // embeds. Coluna errada na tabela principal recusa a consulta do mesmo jeito — e, numa
  // ferramenta do assistente que engole o erro, vira "não há nada" dito como fato.
  it('nenhum .select() cita coluna inexistente na tabela do .from()', () => {
    const problemas: string[] = [];
    // Exceções conhecidas, cada uma com o motivo. Não é para crescer: conserte a consulta.
    const EXCECOES = new Set([
      // Manutenção de 2026 (conserto de acentos importados errado): nada a chama, e os nomes de
      // coluna são de um esquema antigo. Consertar antes de rodar de novo (02/10/2026).
      join('supabase', 'functions', 'fix-db-encoding', 'index.ts'),
    ]);
    for (const arquivo of arquivosVarridos()) {
      if ([...EXCECOES].some((e) => arquivo.endsWith(e))) continue;
      const src = readFileSync(arquivo, 'utf8');
      for (const { raiz, literais } of chamadasDeSelect(src, false)) {
        const conhecidas = raiz ? tabelas.get(raiz) : undefined;
        if (!conhecidas) continue;
        for (const select of literais) {
          if (select.includes('${')) continue;  // montado em tempo de execução
          for (const col of colunasDoTopo(select)) {
            if (!conhecidas.has(col)) {
              problemas.push(`${arquivo.replace(process.cwd(), '')}: ${raiz}.${col} — coluna não existe`);
            }
          }
        }
      }
    }
    expect(problemas, problemas.join('\n')).toEqual([]);
  });
});

/** As colunas simples do primeiro nível de um select (sem embeds, aliases, casts nem `*`). */
function colunasDoTopo(select: string): string[] {
  let nivel = 0;
  let topo = '';
  for (const ch of select) {
    if (ch === '(') { nivel++; if (nivel === 1) topo += '('; continue; }
    if (ch === ')') { nivel--; continue; }
    if (nivel === 0) topo += ch;
  }
  return topo.split(',')
    .map((c) => c.trim())
    .filter((c) => c && !c.includes('(') && /^\w+$/.test(c));
}

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

    for (const arquivo of arquivosVarridos()) {
      const src = readFileSync(arquivo, 'utf8');
      for (const { raiz, literais } of chamadasDeSelect(src)) {
        for (const select of literais) {
          for (const { tabela, pai } of embedsDe(select, raiz ?? '')) {
            // O hint vem colado no nome: `tabela!nome_da_fk(...)`.
            const temHint = new RegExp(`${tabela}\\s*!\\s*\\w+\\s*\\(`).test(select);
            // Tabela dinâmica (`.from(tabela)`): não dá para saber o par, então todo embed
            // do primeiro nível diz a chave — foi esse o formato de gastos_por_categoria.
            if (!pai) {
              if (raiz === null && !temHint) {
                problemas.push(
                  `${arquivo.replace(process.cwd(), '')}: .from(variável) → ${tabela}(…) sem ` +
                  '`!nome_da_fk` — com a tabela numa variável, diga a chave em todo embed',
                );
              }
              continue;
            }
            const par = [pai, tabela].sort().join('|');
            if ((relacoes.get(par) ?? 0) <= 1) continue;
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
    }

    expect(problemas, problemas.join('\n')).toEqual([]);
  });

  it('pega o formato que derrubou gastos_por_categoria (02/10/2026)', () => {
    const codigo = `const { data } = await ctx.sb.from(tabela)
      .select(receita ? "amount, category, clients(name)" : "amount, expense_category, suppliers(name), payees(name)")
      .neq("status", "cancelled");`;
    const [chamada] = chamadasDeSelect(codigo);
    expect(chamada.raiz).toBeNull();
    expect(chamada.literais).toHaveLength(2);
    expect(embedsDe(chamada.literais[1], '').map((e) => e.tabela)).toEqual(['suppliers', 'payees']);
    // E o par em si é ambíguo nos tipos do banco: payee_id e beneficiario_id.
    expect(relacoes.get(['payables', 'payees'].sort().join('|'))).toBeGreaterThan(1);
  });
});

/**
 * Cada `.select(...)` do arquivo com a tabela do `.from()` que vem antes (null quando a tabela
 * está numa variável) e TODOS os textos entre os parênteses — inclusive os dois lados de um
 * `cond ? "a" : "b"`, que a leitura antiga (só o primeiro literal) não via.
 */
function chamadasDeSelect(fonte: string, soComEmbed = true): Array<{ raiz: string | null; literais: string[] }> {
  const src = fonte.replace(/\r\n/g, '\n');
  const achados: Array<{ raiz: string | null; literais: string[] }> = [];
  for (const m of src.matchAll(/\.select\(/g)) {
    let nivel = 1, i = m.index! + m[0].length;
    const inicio = i;
    let aspas: string | null = null;
    while (i < src.length && nivel > 0) {
      const ch = src[i];
      if (aspas) {
        if (ch === '\\') i++;
        else if (ch === aspas) aspas = null;
      } else if (ch === '"' || ch === "'" || ch === '`') aspas = ch;
      else if (ch === '(') nivel++;
      else if (ch === ')') nivel--;
      i++;
    }
    // Só o primeiro argumento: o segundo é `{ count: 'exact', head: true }`, não coluna.
    let args = src.slice(inicio, i - 1);
    {
      let prof = 0; let q: string | null = null;
      for (let k = 0; k < args.length; k++) {
        const ch = args[k];
        if (q) { if (ch === '\\') k++; else if (ch === q) q = null; continue; }
        if (ch === '"' || ch === "'" || ch === '`') q = ch;
        else if (ch === '(' || ch === '{' || ch === '[') prof++;
        else if (ch === ')' || ch === '}' || ch === ']') prof--;
        else if (ch === ',' && prof === 0) { args = args.slice(0, k); break; }
      }
    }
    const literais = [...args.matchAll(/`([^`]*)`|"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/g)]
      .map((l) => l[1] ?? l[2] ?? l[3] ?? '')
      .filter((l) => !soComEmbed || /\w\s*(?:!\s*\w+\s*)?\(/.test(l));   // só o que tem embed
    if (literais.length === 0) continue;
    // O .from() mais próximo antes do .select(), na mesma expressão (até 400 caracteres).
    const antes = src.slice(Math.max(0, m.index! - 400), m.index!);
    // `.from('x')`, `.from(tabela)` e `(supabase.from as any)('view_fora_dos_tipos')`.
    const froms = [...antes.matchAll(/\.from(?:\s+as\s+\w+\s*\))?\(\s*(?:['"](\w+)['"]|([A-Za-z_$][\w$.]*))[^)]*\)/g)];
    const ultimo = froms[froms.length - 1];
    if (!ultimo) continue;
    achados.push({ raiz: ultimo[1] ?? null, literais });
  }
  return achados;
}
