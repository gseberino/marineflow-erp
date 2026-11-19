// Banco falso em memória para os testes dos "fakes do assistente" (19/11/2026): filtra de verdade, grava em
// memória e devolve o que o PostgREST devolveria (inclusive [] num update que não achou linha, com .select()).
// Só para teste: nenhum código de produção importa este arquivo.

// deno-lint-ignore no-explicit-any
export type Linha = Record<string, any>;
type Filtro = (l: Linha) => boolean;

export interface Falhas {
  /** `${op}:${tabela}` → mensagem de erro (op = select | insert | update | delete). */
  [chave: string]: string;
}

export function bancoFalso(
  tabelas: Record<string, Linha[]>,
  falhas: Falhas = {},
  rpcs: Record<string, (args: Linha) => { data: unknown; error: { message: string } | null }> = {},
) {
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown; filtros?: string[] }> = [];
  const chamadas: Array<[string, Linha]> = [];
  const armazem: Record<string, Map<string, { bytes: Uint8Array; contentType?: string }>> = {};
  const falhasDoArmazem: { upload?: string } = {};
  let seq = 0;

  function consulta(tabela: string) {
    const filtros: Filtro[] = [];
    const descricao: string[] = [];
    let op: "select" | "update" | "insert" | "delete" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico = false;
    let devolve = false;
    let limite: number | null = null;
    let faixa: [number, number] | null = null;
    const linhas = () => (tabelas[tabela] ??= []);
    const executar = () => {
      const erro = falhas[`${op}:${tabela}`];
      if (erro) return { data: null, error: { message: erro } };
      let resultado: Linha[];
      if (op === "insert") {
        const novas = (Array.isArray(valor) ? valor : [valor]).map((v: Linha) => ({ id: `${tabela}-novo-${++seq}`, ...v }));
        linhas().push(...novas);
        gravacoes.push({ op, tabela, valor });
        resultado = novas;
      } else {
        const alvo = linhas().filter((l) => filtros.every((f) => f(l)));
        if (op === "update") {
          alvo.forEach((l) => Object.assign(l, valor));
          gravacoes.push({ op, tabela, valor, filtros: descricao });
        }
        if (op === "delete") {
          tabelas[tabela] = linhas().filter((l) => !alvo.includes(l));
          gravacoes.push({ op, tabela, valor: alvo.map((l) => l.id), filtros: descricao });
        }
        resultado = alvo.map((l) => ({ ...l }));
        if (faixa) resultado = resultado.slice(faixa[0], faixa[1] + 1);
        if (limite != null) resultado = resultado.slice(0, limite);
      }
      if (unico) return { data: resultado[0] ?? null, error: null };
      return { data: op === "select" || devolve ? resultado : null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => { if (op !== "select") devolve = true; return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); descricao.push(`${c}=${v}`); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, v: unknown[]) => { filtros.push((l) => v.includes(l[c])); descricao.push(`${c} in ${v.join("|")}`); return q; },
      is: (c: string, v: unknown) => { filtros.push((l) => (l[c] ?? null) === v); return q; },
      gte: (c: string, v: unknown) => { filtros.push((l) => l[c] != null && String(l[c]) >= String(v)); return q; },
      gt: (c: string, v: unknown) => { filtros.push((l) => l[c] != null && String(l[c]) > String(v)); return q; },
      lte: (c: string, v: unknown) => { filtros.push((l) => l[c] != null && String(l[c]) <= String(v)); return q; },
      lt: (c: string, v: unknown) => { filtros.push((l) => l[c] != null && String(l[c]) < String(v)); return q; },
      like: (c: string, padrao: string) => {
        const re = new RegExp(`^${padrao.split("%").map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`);
        filtros.push((l) => re.test(String(l[c] ?? "")));
        return q;
      },
      not: () => q, or: () => q, ilike: () => q, order: () => q,
      limit: (n: number) => { limite = n; return q; },
      range: (a: number, b: number) => { faixa = [a, b]; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      delete: () => { op = "delete"; return q; },
      maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
      single: () => { unico = true; return Promise.resolve(executar()); },
      then: (ok: (v: unknown) => unknown, nao?: (e: unknown) => unknown) => Promise.resolve(executar()).then(ok, nao),
    };
    return q;
  }

  const db = {
    from: consulta,
    rpc: (fn: string, args: Linha = {}) => {
      chamadas.push([fn, args]);
      const r = rpcs[fn];
      return Promise.resolve(r ? r(args) : { data: null, error: null });
    },
    storage: {
      from: (bucket: string) => ({
        upload: (caminho: string, bytes: Uint8Array, opts?: { contentType?: string }) => {
          if (falhasDoArmazem.upload) return Promise.resolve({ data: null, error: { message: falhasDoArmazem.upload } });
          (armazem[bucket] ??= new Map()).set(caminho, { bytes, contentType: opts?.contentType });
          return Promise.resolve({ data: { path: caminho }, error: null });
        },
        remove: (caminhos: string[]) => {
          for (const c of caminhos) armazem[bucket]?.delete(c);
          return Promise.resolve({ data: null, error: null });
        },
      }),
    },
  };
  return { db, tabelas, gravacoes, chamadas, armazem, falhasDoArmazem };
}

// deno-lint-ignore no-explicit-any
export const ctxDe = (db: unknown, extra: Record<string, unknown> = {}): any =>
  ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {}, ...extra });
