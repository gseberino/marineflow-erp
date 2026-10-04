// sugerir_conciliacao (03/10/2026): roda o cálculo direto (montarSugestoes), sem ir por HTTP à
// banking-reconcile. Caso real: pelo Claude Max (sem sessão do navegador, jwt="") a ferramenta
// respondia que "só funciona na sessão do app". O que se protege: funciona sem JWT, não faz
// chamada de rede, técnico continua barrado e o resumo vem no formato que o modelo conhece.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bankingTools } from "./banking.ts";

const sugerir = bankingTools.find((t) => t.name === "sugerir_conciliacao")!;

function adminVazio() {
  const b: Record<string, unknown> = {};
  for (const m of ["select", "eq", "order", "limit", "in", "not"]) b[m] = () => b;
  b.maybeSingle = () => Promise.resolve({ data: null, error: null });
  b.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok);
  return { from: () => b };
}

const ctxDe = (userRole: string, jwt = "") =>
  ({ sb: {}, admin: adminVazio(), userId: "u", userRole, jwt, appOrigin: "", settings: {} }) as never;

async function semRede(fn: () => Promise<void>) {
  const original = globalThis.fetch;
  let chamou = false;
  globalThis.fetch = (() => {
    chamou = true;
    return Promise.reject(new Error("não devia chamar a rede"));
  }) as typeof fetch;
  try {
    await fn();
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(chamou, false);
}

Deno.test("sem sessão do navegador (WhatsApp/Claude Max): sugere sem rede e sem JWT", async () => {
  await semRede(async () => {
    const r = await sugerir.execute({}, ctxDe("admin")) as Record<string, unknown>;
    assertEquals(r, {
      resumo: { pendentes: 0, sugeridas: 0, sem_candidato: 0, candidatos_avaliados: 0, transferencias_internas: 0 },
      itens: [],
    });
  });
});

Deno.test("técnico continua barrado", async () => {
  await semRede(async () => {
    const r = await sugerir.execute({}, ctxDe("technician", "jwt")) as Record<string, unknown>;
    assertEquals(typeof r.error, "string");
  });
});
