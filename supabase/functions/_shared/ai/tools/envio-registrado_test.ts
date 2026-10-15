// O que as tools mandam ao whatsapp-send para o envio entrar na conversa (15/10/2026): `origem:
// "assistente"` em todo corpo e `sent_by` = quem confirmou (ctx.userId), só quando é id de usuário —
// um sent_by estranho nunca chega à edge (e lá não barraria o envio, ver whatsapp-send/index_test.ts).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sendWhatsapp, whatsappTools } from "./whatsapp.ts";

const DONO = "6f1c1f0e-1111-4c4c-9a9a-0a0a0a0a0a0a";

async function corposEnviados(corpo: () => Promise<unknown>): Promise<Array<Record<string, unknown>>> {
  const enviados: Array<Record<string, unknown>> = [];
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = ((entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (!url.endsWith("/functions/v1/whatsapp-send")) throw new Error(`fetch inesperado: ${url}`);
    enviados.push(JSON.parse(String(init?.body)));
    return Promise.resolve(new Response(JSON.stringify({ success: true, messageId: "WA-1" })));
  }) as typeof fetch;
  try { await corpo(); } finally { globalThis.fetch = original; }
  return enviados;
}

Deno.test("sendWhatsapp: origem do assistente sempre; sent_by só quando é id de usuário", async () => {
  const [comId] = await corposEnviados(() => sendWhatsapp("351966776422", "Bom dia, Miguel!", "", "chave-1", DONO));
  assertEquals(comId, { phone: "351966776422", message: "Bom dia, Miguel!", kind: "text", dedupe_key: "chave-1", sent_by: DONO, origem: "assistente" });
  const [semId] = await corposEnviados(() => sendWhatsapp("351966776422", "Oi", "", undefined, "u1"));
  assertEquals(semId, { phone: "351966776422", message: "Oi", kind: "text", origem: "assistente" });
});

Deno.test("send_whatsapp_message manda quem confirmou (ctx.userId) como sent_by", async () => {
  const tool = whatsappTools.find((t) => t.name === "send_whatsapp_message")!;
  const ctx = { sb: {}, admin: {}, userId: DONO, userRole: "admin", jwt: "", appOrigin: "", settings: {} } as never;
  const [corpo] = await corposEnviados(() => tool.execute({ to_phone: "+351 966 776 422", message: "Miguel, você tem razão." }, ctx));
  assertEquals([corpo.phone, corpo.sent_by, corpo.origem], ["351966776422", DONO, "assistente"]);
});
