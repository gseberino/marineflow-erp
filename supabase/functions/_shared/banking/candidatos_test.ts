// Leitura que falha não vira "sem candidato" (06/10/2026). A busca de candidatos do Extrato lia 11
// tabelas sem conferir o erro: uma falha devolvia lista vazia e a linha aparecia "sem candidato" —
// o mesmo defeito do combustível que respondia R$ 0 (02/10). Agora a falha sobe com o nome da tabela.
import { assert, assertRejects } from "jsr:@std/assert@1";
import { carregarCandidatos } from "./candidatos.ts";

/** Banco de mentira: toda consulta encadeia e responde vazio; a tabela `quebrada` responde erro. */
function banco(quebrada: string) {
  return {
    from(tabela: string) {
      const resposta = tabela === quebrada
        ? { data: null, error: { message: "permission denied" } }
        : { data: [], error: null };
      const q: Record<string, unknown> = {};
      for (const m of ["select", "eq", "neq", "in", "is", "not", "gt", "gte", "lt", "lte", "order", "limit", "or"]) q[m] = () => q;
      q.maybeSingle = async () => ({ data: null, error: resposta.error });
      q.single = async () => resposta;
      q.then = (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resposta).then(ok, erro);
      return q;
    },
  };
}

Deno.test("leitura que falha sobe com o nome da tabela, em vez de lista vazia", async () => {
  for (const tabela of ["receivables", "payables", "payments", "bank_transactions"]) {
    // deno-lint-ignore no-explicit-any
    await assertRejects(() => carregarCandidatos(banco(tabela) as any), Error, tabela);
  }
});

Deno.test("sem falha, banco vazio dá lista vazia", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await carregarCandidatos(banco("nenhuma") as any);
  assert(Array.isArray(r) && r.length === 0);
});
