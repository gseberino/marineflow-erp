// Banco falso (supabase-js de mentira) para os testes da impressão. Fora de *_test.ts para ser importado sem rodar testes.
type Chamada = { tabela: string; op: string; filtros: Array<[string, string, unknown]>; valor?: unknown };
type Responder = (c: Chamada) => { data?: unknown; error?: { message: string } | null; count?: number };

/** supabase-js de mentira: encadeia, grava a chamada e responde pelo `responder` quando é aguardado. */
export function bancoFalso(responder: Responder) {
  const chamadas: Chamada[] = [];
  const from = (tabela: string) => {
    const c: Chamada = { tabela, op: "select", filtros: [] };
    let gravada = false;
    const fim = () => {
      if (!gravada) { chamadas.push(c); gravada = true; }
      const r = responder(c);
      return { data: r.data ?? null, error: r.error ?? null, count: r.count };
    };
    const b: Record<string, unknown> = {};
    const filtro = (nome: string) => (col: string, v: unknown) => { c.filtros.push([nome, col, v]); return b; };
    Object.assign(b, {
      select: () => b,
      insert: (v: unknown) => { c.op = "insert"; c.valor = v; return b; },
      update: (v: unknown) => { c.op = "update"; c.valor = v; return b; },
      eq: filtro("eq"), in: filtro("in"), gte: filtro("gte"), neq: filtro("neq"), not: (col: string, _o: string, v: unknown) => { c.filtros.push(["not", col, v]); return b; },
      order: () => b, limit: () => b,
      single: () => Promise.resolve(fim()),
      maybeSingle: () => Promise.resolve(fim()),
      then: (ok: (v: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(fim()).then(ok, erro),
    });
    return b;
  };
  return { admin: { from }, chamadas };
}
