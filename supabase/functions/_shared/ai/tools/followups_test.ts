// "Deixar a IA acompanhar" com o interruptor desligado (05/10/2026): a missão nascia parada e o
// assistente prometia um rascunho que não vinha. Agora criar recusa antes de chamar o banco.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { followupTools } from "./followups.ts";

const criar = followupTools.find((t) => t.name === "criar_missao_acompanhamento")!;

function ctxCom(ligado: string | null) {
  const chamadas: string[] = [];
  const admin = {
    from: (_t: string) => ({
      select: () => ({
        in: async () => ({ data: ligado === null ? [] : [{ key: "followup_missions_enabled", value: ligado }] }),
      }),
    }),
  };
  const sb = {
    rpc: async (nome: string) => {
      chamadas.push(nome);
      return { data: "00000000-0000-0000-0000-000000000001", error: null };
    },
  };
  // deno-lint-ignore no-explicit-any
  return { ctx: { admin, sb, role: "admin", channel: "whatsapp" } as any, chamadas };
}

Deno.test("criar missão: interruptor desligado recusa sem chamar o banco", async () => {
  const { ctx, chamadas } = ctxCom("false");
  // deno-lint-ignore no-explicit-any
  const r: any = await criar.execute({ origem_tipo: "manual", objetivo: "confirmar a entrega" }, ctx);
  assert(r.error?.includes("desligado"), `esperava recusa, veio ${JSON.stringify(r)}`);
  assertEquals(chamadas, []);
});

Deno.test("criar missão: interruptor ligado (ou sem a chave) segue para o banco", async () => {
  for (const valor of ["true", null]) {
    const { ctx, chamadas } = ctxCom(valor);
    await criar.execute({ origem_tipo: "manual", objetivo: "confirmar a entrega" }, ctx);
    assertEquals(chamadas, ["create_followup_mission"]);
  }
});
