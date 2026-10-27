// A resposta do cliente no webhook (Agenda de Produção, Fase 5, P4 — 27/10/2026): a RPC certa com a intenção e a expressão
// que o leitor achou, o "consumiu" do banco e nunca lança. O fluxo inteiro do webhook está em whatsapp-webhook/index_test.ts
// ("cliente P4"); o leitor, em _shared/ai/comms/reply-router_test.ts.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { RESPOSTA_DO_CLIENTE_MAX, respostaDoCliente, RPC_RESPOSTA_DO_CLIENTE, tipoDaMensagem } from "./resposta-do-cliente.ts";

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

const FONE = "5547900000304";
const MSG = "11111111-0000-4000-8000-0000000000c1";

Deno.test("cliente: consumiu = true só quando o banco diz; a intenção e a expressão do leitor vão junto", async () => {
  const a = admin({ data: { consumiu: true, efeito: "replanejou" } });
  assertEquals(await respostaDoCliente(a, { phone: FONE, body: "Não posso terça, pode ser sexta?", messageId: MSG }), true);
  assertEquals(a.chamadas[0], {
    nome: RPC_RESPOSTA_DO_CLIENTE,
    args: {
      p_phone: FONE, p_body: "Não posso terça, pode ser sexta?", p_message_id: MSG, p_tipo_msg: "text",
      p_intencao: "data", p_expressao: "sexta",
    },
  });
  const sim = admin({ data: { consumiu: false, modo: "sombra" } });
  assertEquals(await respostaDoCliente(sim, { phone: FONE, body: "Sim" }), false);
  assertEquals([sim.chamadas[0].args.p_intencao, sim.chamadas[0].args.p_expressao, sim.chamadas[0].args.p_message_id],
               ["acordo", null, null]);
  assertEquals(await respostaDoCliente(admin({ data: null }), { phone: FONE, body: "ok" }), false);
});

Deno.test("cliente: o áudio também vai (tipo audio, sem ler o corpo: o banco o leva ao dono e nunca confirma)", async () => {
  const a = admin({ data: { consumiu: true, efeito: "ao_dono" } });
  assertEquals(await respostaDoCliente(a, { phone: FONE, body: "[audio]", messageId: MSG, tipo: "audio" }), true);
  assertEquals([a.chamadas[0].args.p_tipo_msg, a.chamadas[0].args.p_intencao, a.chamadas[0].args.p_expressao, a.chamadas[0].args.p_body],
               ["audio", "outro", null, "[audio]"]);
  // mesmo com "sim" no corpo, o áudio não é lido como SIM
  const b = admin({ data: { consumiu: true } });
  await respostaDoCliente(b, { phone: FONE, body: "sim", tipo: "audio" });
  assertEquals(b.chamadas[0].args.p_intencao, "outro");
  assertEquals([tipoDaMensagem("image"), tipoDaMensagem("sticker"), tipoDaMensagem(null), tipoDaMensagem("video")],
               ["image", "outro", "outro", "video"]);
});

Deno.test("cliente: texto vazio ou sem telefone nem vai ao banco; o texto longo vai cortado (o leitor leu inteiro)", async () => {
  for (const body of ["", "   ", null]) {
    const a = admin({ data: { consumiu: true } });
    assertEquals(await respostaDoCliente(a, { phone: FONE, body }), false);
    assertEquals(a.chamadas.length, 0);
  }
  const semFone = admin({ data: { consumiu: true } });
  assertEquals(await respostaDoCliente(semFone, { phone: "", body: "ok" }), false);
  assertEquals(semFone.chamadas.length, 0);
  const longo = admin({ data: { consumiu: false } });
  await respostaDoCliente(longo, { phone: FONE, body: "a chave fica na portaria. " + "x".repeat(RESPOSTA_DO_CLIENTE_MAX) });
  assertEquals((longo.chamadas[0].args.p_body as string).length, RESPOSTA_DO_CLIENTE_MAX);
  assertEquals(longo.chamadas[0].args.p_intencao, "acesso");
});

Deno.test("cliente: a função ainda não aplicada = false sem registro; outro erro ou exceção = false e app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const ausente = admin({ error: { code, message: "Could not find the function" } });
    assertEquals(await respostaDoCliente(ausente, { phone: FONE, body: "ok" }), false);
    assertEquals(ausente.logs().length, 0);
  }
  for (const r of [{ error: { code: "57014", message: "statement timeout" } }, "lança" as const]) {
    const a = admin(r);
    assertEquals(await respostaDoCliente(a, { phone: FONE, body: "ok" }), false);
    const logs = a.logs();
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["whatsapp-webhook", "agenda:cliente"]);
  }
});
