// Retorno F5 (P11.3): update_quote_status com o motivo da perda. "rejected" quer dizer perdido (o cliente não seguiu) e
// sempre tem motivo (3.4); vencer não é rejeitar. Banco falso; números inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { serviceOrderTools } from "./service-orders.ts";
import type { ToolCtx } from "./registry.ts";
import { ROTULOS_DOS_CAMPOS, ROTULOS_DOS_VALORES } from "../rotulos.ts";
import { ASSUNTO_DAS_ACOES } from "../assunto.ts";
import { buildSystemBlocks } from "../prompt.ts";

const tool = serviceOrderTools.find((t) => t.name === "update_quote_status")!;

function banco(atual: string | null, opcoes: { erroDeLeitura?: boolean } = {}) {
  const updates: Array<Record<string, unknown>> = [];
  const db = {
    from: (_t: string) => {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve(opcoes.erroDeLeitura
          ? { data: null, error: { code: "57014", message: "tempo esgotado" } }
          : { data: { quote_status: atual }, error: null }),
        update: (v: Record<string, unknown>) => {
          updates.push(v);
          return q;
        },
        single: () => Promise.resolve({ data: { id: "os-1", ...updates.at(-1) }, error: null }),
      };
      return q;
    },
  };
  const ctx = { sb: db, admin: db, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  return { ctx, updates };
}

Deno.test("rejeitar sem motivo recusa com a frase fixa e não grava", async () => {
  for (const motivo of [undefined, "", "caro", "sem_motivo_antigo"]) {
    const b = banco("sent");
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute({ id: "os-1", quote_status: "rejected", ...(motivo === undefined ? {} : { motivo_perda: motivo }) }, b.ctx) as any;
    assertEquals(r.error, "Diga o motivo da perda: sumiu, fechou com outro, desistiu, preço, prazo ou outro.", String(motivo));
    assertEquals(b.updates.length, 0);
  }
});

Deno.test("rejeitar com motivo grava o status, o motivo e quem marcou (assistente)", async () => {
  for (const motivo of ["sumiu", "fechou_com_outro", "desistiu", "preco", "prazo", "outro"]) {
    const b = banco("sent");
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute({ id: "os-1", quote_status: "rejected", motivo_perda: motivo }, b.ctx) as any;
    assertEquals(r.ok, true, motivo);
    assertEquals(b.updates, [{ quote_status: "rejected", motivo_perda: motivo, motivo_perda_por: "assistente" }]);
  }
});

Deno.test("as outras transições são as de antes: o motivo, se vier, é ignorado", async () => {
  const b = banco("draft");
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ id: "os-1", quote_status: "sent", motivo_perda: "preco" }, b.ctx) as any;
  assertEquals(r.ok, true);
  assertEquals(b.updates, [{ quote_status: "sent" }]);
  // reabrir (rejected → draft): o gatilho apaga o motivo; a ferramenta manda só o status
  const reabre = banco("rejected");
  await tool.execute({ id: "os-1", quote_status: "draft" }, reabre.ctx);
  assertEquals(reabre.updates, [{ quote_status: "draft" }]);
});

Deno.test("a leitura do status atual que falha não vira 'draft': lança, e nada é gravado", async () => {
  const b = banco("rejected", { erroDeLeitura: true });
  let lancou = false;
  try {
    await tool.execute({ id: "os-1", quote_status: "draft" }, b.ctx);
  } catch {
    lancou = true;
  }
  assert(lancou);
  assertEquals(b.updates.length, 0);
});

Deno.test("o esquema e a descrição ensinam o motivo; rótulo, assunto e a linha do playbook", () => {
  const props = tool.input_schema.properties as Record<string, { enum?: string[] }>;
  assertEquals(props.motivo_perda.enum, ["sumiu", "fechou_com_outro", "desistiu", "preco", "prazo", "outro"]);
  assertStringIncludes(tool.description, "rejected = perdido (o cliente não seguiu); vencer não é rejeitar");
  assertEquals(ROTULOS_DOS_CAMPOS.motivo_perda, "Motivo da perda");
  assertEquals(ROTULOS_DOS_VALORES.motivo_perda.fechou_com_outro, "fechou com outro");
  assert(ASSUNTO_DAS_ACOES.update_quote_status?.includes("motivo_perda"));
  const prompt = buildSystemBlocks({}, { userName: "Teste", userRole: "admin", channel: "whatsapp" }).map((b) => b.text).join(" ");
  assertStringIncludes(prompt, "Para marcar perdido, use update_quote_status com o motivo.");
});
