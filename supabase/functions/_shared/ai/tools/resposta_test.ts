// Responder uma conversa (06/10/2026). O que se protege: a confirmação mostra para quem, o número
// inteiro, a ÚLTIMA mensagem que a pessoa mandou (com mídia legível) e a resposta inteira; mensagem
// vazia e número inválido são recusados antes de pedir a confirmação; o envio usa o número normalizado.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resumirMensagem, ultimaMensagemRecebida, validarMensagem } from "./resposta.ts";
import { whatsappTools } from "./whatsapp.ts";

function banco(opcoes: { cliente?: Record<string, unknown> | null; lead?: Record<string, unknown> | null; recebidas?: Record<string, unknown>[] } = {}) {
  const filtros: Array<[string, string, unknown]> = [];
  const admin = {
    from(t: string) {
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { filtros.push([t, c, v]); return q; },
        order: () => q,
        limit: () => Promise.resolve({ data: t === "whatsapp_messages" ? (opcoes.recebidas ?? []) : [], error: null }),
        maybeSingle: () => Promise.resolve({ data: t === "clients" ? (opcoes.cliente ?? null) : t === "whatsapp_leads" ? (opcoes.lead ?? null) : null, error: null }),
      };
      return q;
    },
  };
  return { admin, filtros };
}

Deno.test("confirmação da resposta: para quem, número, a última mensagem dele e a resposta", async () => {
  const { admin, filtros } = banco({
    lead: { name: "Juliano Jds" },
    recebidas: [{ body: "E o display, chega quando?", occurred_at: "2026-10-06T13:12:00.000Z" }],
  });
  const r = await resumirMensagem(admin, { to_phone: "47 99123-4567", message: "Oi Juliano! O display chega quinta." });
  assertStringIncludes(r, "Para: *Juliano Jds* (conversa do WhatsApp)");
  assertStringIncludes(r, "WhatsApp: +55 (47) 99123-4567");
  assertStringIncludes(r, 'Última mensagem dele (06/10 10:12): "E o display, chega quando?"');
  assertStringIncludes(r, 'Resposta: "Oi Juliano! O display chega quinta."');
  // A última mensagem é a RECEBIDA, daquele número.
  const daConversa = filtros.filter(([t]) => t === "whatsapp_messages");
  assertEquals(daConversa, [["whatsapp_messages", "phone_normalized", "5547991234567"], ["whatsapp_messages", "direction", "inbound"]]);
});

Deno.test("cliente do cadastro e mídia sem texto", async () => {
  const { admin } = banco({ cliente: { name: "Nelson - S.I. 7.8", whatsapp: "47991455678" }, recebidas: [{ body: "[audio]", occurred_at: "2026-10-06T12:00:00.000Z" }] });
  const r = await resumirMensagem(admin, { client_id: "c1", message: "Recebido, Nelson!" });
  assertStringIncludes(r, "*Nelson - S.I. 7.8* (cliente do cadastro)");
  assertStringIncludes(r, '"🎤 áudio"');
  assertEquals(await ultimaMensagemRecebida(banco().admin, "5547991455678"), null);
});

Deno.test("antes da confirmação: mensagem vazia e número inválido são recusados", () => {
  assertStringIncludes(validarMensagem({ to_phone: "47991234567", message: "  " })!.error, "vazia");
  assertStringIncludes(validarMensagem({ to_phone: "123", message: "Oi" })!.error, "inválido");
  assertEquals(validarMensagem({ client_id: "c1", message: "Oi" }), null);
  const tool = whatsappTools.find((t) => t.name === "send_whatsapp_message")!;
  assertStringIncludes(tool.preValidar!({ to_phone: "123", message: "Oi" }, {} as never)!.error, "inválido");
  assertEquals(tool.preValidar!({ to_phone: "47 99123-4567", message: "Oi" }, {} as never), null);
});
