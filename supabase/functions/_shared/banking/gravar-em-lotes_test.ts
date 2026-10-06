import { assertEquals } from "jsr:@std/assert@1";
import { avisoDeFalhas, gravarEmLotes } from "./gravar-em-lotes.ts";

const linhas = (n: number) => Array.from({ length: n }, (_, i) => ({ bank_ref_id: `t${i}` }));

/** Banco de mentira: recusa qualquer insert que contenha uma linha ruim (como o Postgres faz). */
function banco(ruins: Record<string, { code?: string; message: string }>) {
  const gravadas: string[] = [];
  const inserir = async (lote: { bank_ref_id: string }[]) => {
    const ruim = lote.find((l) => ruins[l.bank_ref_id]);
    if (ruim) return { error: ruins[ruim.bank_ref_id] };
    gravadas.push(...lote.map((l) => l.bank_ref_id));
    return { error: null };
  };
  return { inserir, gravadas };
}

Deno.test("sem erro, grava tudo em lotes", async () => {
  const b = banco({});
  const r = await gravarEmLotes(linhas(450), b.inserir);
  assertEquals(r, { gravadas: 450, jaExistiam: 0, falhas: [] });
  assertEquals(b.gravadas.length, 450);
});

Deno.test("uma linha ruim não derruba as outras do lote", async () => {
  const b = banco({ t7: { code: "22P02", message: "invalid input syntax for type numeric" } });
  const r = await gravarEmLotes(linhas(250), b.inserir);
  assertEquals(r.gravadas, 249);
  assertEquals(r.falhas, [{ bank_ref_id: "t7", erro: "invalid input syntax for type numeric" }]);
  assertEquals(b.gravadas.includes("t7"), false);
  assertEquals(b.gravadas.length, 249);
});

Deno.test("linha que já estava (índice único) conta como já existia, não como falha", async () => {
  const b = banco({ t3: { code: "23505", message: "duplicate key value" } });
  const r = await gravarEmLotes(linhas(10), b.inserir);
  assertEquals(r, { gravadas: 9, jaExistiam: 1, falhas: [] });
});

Deno.test("avisoDeFalhas: nada quando não falhou; conta e motivo quando falhou", () => {
  assertEquals(avisoDeFalhas([]), null);
  assertEquals(
    avisoDeFalhas([{ bank_ref_id: "a", erro: "x" }, { bank_ref_id: "b", erro: "y" }]),
    "2 não gravada(s) (x) — a próxima sincronização tenta de novo",
  );
});
