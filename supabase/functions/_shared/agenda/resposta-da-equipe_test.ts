// A resposta da equipe no webhook (Agenda de Produção, Fase 3, P4 — 24/10/2026): a RPC certa com os parâmetros certos, o
// "consumiu" do banco e nunca lança. O fluxo inteiro do webhook está em whatsapp-webhook/index_test.ts ("equipe P4").
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { RESPOSTA_DA_EQUIPE_MAX, respostaDaEquipe, RPC_RESPOSTA_DA_EQUIPE } from "./resposta-da-equipe.ts";

function admin(resp: { data?: unknown; error?: unknown } | "lança") {
  const chamadas: Array<{ nome: string; args: Record<string, unknown> }> = [];
  return {
    chamadas,
    rpc(nome: string, args: Record<string, unknown>) {
      chamadas.push({ nome, args });
      if (nome === "log_app_error") return Promise.resolve({ data: null, error: null });
      if (resp === "lança") return Promise.reject(new Error("rede caiu"));
      return Promise.resolve({ data: resp.data ?? null, error: resp.error ?? null });
    },
    logs() {
      return chamadas.filter((c) => c.nome === "log_app_error").map((c) => c.args);
    },
  };
}

Deno.test("equipe: consumiu = true só quando o banco diz; os parâmetros vão como chegaram", async () => {
  const a = admin({ data: { consumiu: true, tipo: "ok" } });
  assertEquals(await respostaDaEquipe(a, { phone: "5547900000001", body: "ok", messageId: "WA-1" }), true);
  assertEquals(a.chamadas[0], { nome: RPC_RESPOSTA_DA_EQUIPE, args: { p_phone: "5547900000001", p_body: "ok", p_message_id: "WA-1" } });
  assertEquals(await respostaDaEquipe(admin({ data: { consumiu: false } }), { phone: "5547900000001", body: "ok" }), false);
  assertEquals(await respostaDaEquipe(admin({ data: null }), { phone: "5547900000001", body: "ok" }), false);
});

Deno.test("equipe: texto vazio, longo demais ou sem telefone nem vai ao banco", async () => {
  for (const body of ["", "   ", "x".repeat(RESPOSTA_DA_EQUIPE_MAX + 1), null]) {
    const a = admin({ data: { consumiu: true } });
    assertEquals(await respostaDaEquipe(a, { phone: "5547900000001", body }), false);
    assertEquals(a.chamadas.length, 0);
  }
  const semFone = admin({ data: { consumiu: true } });
  assertEquals(await respostaDaEquipe(semFone, { phone: "", body: "ok" }), false);
  assertEquals(semFone.chamadas.length, 0);
});

Deno.test("equipe: a função ainda não aplicada = false sem registro; outro erro ou exceção = false e app_error_logs", async () => {
  const ausente = admin({ error: { code: "PGRST202", message: "Could not find the function" } });
  assertEquals(await respostaDaEquipe(ausente, { phone: "5547900000001", body: "ok" }), false);
  assertEquals(ausente.logs().length, 0);
  for (const r of [{ error: { code: "57014", message: "statement timeout" } }, "lança" as const]) {
    const a = admin(r);
    assertEquals(await respostaDaEquipe(a, { phone: "5547900000001", body: "ok" }), false);
    const logs = a.logs();
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["whatsapp-webhook", "agenda:equipe"]);
  }
});
