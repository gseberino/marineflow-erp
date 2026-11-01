// Retorno F0b (06/11/2026): o envio da fila entra na conversa como automático ("fila:<fonte>"),
// menos as linhas da agenda e a conversa com o assistente; e o gravador nunca muda o desfecho do envio.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { criarRegistroNaConversa } from "./conversa.ts";
import { enviarLote, type ItemDaFila } from "./enviar.ts";
import { filaGravaNaConversa, linhaDaMensagemDaFila } from "../_shared/whatsapp/registro-do-envio.ts";

function bancoFalso(op: { assistente?: string[]; erroDoAssistente?: boolean; erroDoInsert?: string } = {}) {
  const inseridas: Array<Record<string, unknown>> = [];
  let leiturasDoAssistente = 0;
  const cadeia = (resultado: unknown) => {
    const c: Record<string, unknown> = {};
    for (const m of ["select", "eq", "not", "or", "order", "limit"]) c[m] = () => c;
    c.maybeSingle = () => Promise.resolve(resultado);
    c.then = (ok: (r: unknown) => unknown, falha?: (e: unknown) => unknown) => Promise.resolve(resultado).then(ok, falha);
    return c;
  };
  return {
    inseridas,
    get leiturasDoAssistente() { return leiturasDoAssistente; },
    from(tabela: string) {
      if (tabela === "app_users") {
        leiturasDoAssistente++;
        return cadeia(op.erroDoAssistente
          ? { data: null, error: { message: "fora do ar" } }
          : { data: (op.assistente ?? []).map((p) => ({ phone_normalized: p })), error: null });
      }
      if (tabela === "whatsapp_messages") {
        const c = cadeia({ data: { client_id: "c1", lead_id: null, supplier_id: null }, error: null });
        c.insert = (linha: Record<string, unknown>) => {
          inseridas.push(linha);
          return Promise.resolve({ error: op.erroDoInsert ? { code: op.erroDoInsert, message: "x" } : null });
        };
        return c;
      }
      if (tabela === "whatsapp_send_queue") {
        return { update: () => ({ eq: () => Promise.resolve({ error: null }) }) };
      }
      throw new Error(`tabela inesperada: ${tabela}`);
    },
  };
}

const item = (source: string, phone = "5547900008001"): ItemDaFila => ({ id: `f-${source}`, phone_normalized: phone, message: "Oi", source });

Deno.test("regra: agenda fica de fora; a conversa com o assistente também", () => {
  const assistente = ["5547999990000"];
  assert(filaGravaNaConversa({ fonte: "ai_agent", telefone: "5547900008001", telefonesDoAssistente: assistente }));
  assert(filaGravaNaConversa({ fonte: null, telefone: "5547900008001", telefonesDoAssistente: assistente }));
  for (const fonte of ["agenda-cliente", "agenda-confirmacao", "agenda-equipe", "agenda-dono", "agenda-fornecedor"]) {
    assert(!filaGravaNaConversa({ fonte, telefone: "5547900008001", telefonesDoAssistente: assistente }), fonte);
  }
  assert(!filaGravaNaConversa({ fonte: "ai_briefing", telefone: "47999990000", telefonesDoAssistente: assistente }));
});

Deno.test("linha: automática pela origem, com o id do provedor e o vínculo da conversa", () => {
  const l = linhaDaMensagemDaFila({ id: "f1", phone_normalized: "5547900008001", message: "Oi", source: "ai_agent" }, "WA1", { client_id: "c1" });
  assertEquals(l.direction, "outbound");
  assertEquals(l.sent_by, null);
  assertEquals(l.wa_message_id, "WA1");
  assertEquals(l.client_id, "c1");
  assertEquals(l.raw_payload, { origem: "fila:ai_agent", contexto: null, via: "whatsapp-queue-worker", fila_id: "f1" });
});

Deno.test("gravador: grava a de fora, pula agenda e assistente, lê o assistente uma vez por lote", async () => {
  const db = bancoFalso({ assistente: ["5547999990000"] });
  const registrar = criarRegistroNaConversa(db);
  await registrar(item("ai_agent"), "WA1");
  await registrar(item("agenda-cliente"), "WA2");
  await registrar(item("ai_briefing", "5547999990000"), "WA3");
  await registrar(item("balance_escalation", "5547900008002"), "WA4");
  assertEquals(db.inseridas.map((l) => l.wa_message_id), ["WA1", "WA4"]);
  assertEquals(db.leiturasDoAssistente, 1);
});

Deno.test("gravador: sem saber quem é o assistente, não grava; erro no insert não lança", async () => {
  const semAssistente = bancoFalso({ erroDoAssistente: true });
  await criarRegistroNaConversa(semAssistente)(item("ai_agent"), "WA1");
  assertEquals(semAssistente.inseridas, []);
  const comErro = bancoFalso({ erroDoInsert: "42501" });
  await criarRegistroNaConversa(comErro)(item("ai_agent"), "WA1");
  assertEquals(comErro.inseridas.length, 1);
});

Deno.test("enviarLote: grava só depois do envio confirmado, e o gravador que lança não muda o resultado", async () => {
  const db = bancoFalso();
  const gravados: string[] = [];
  const provedor = {
    sendText: (phone: string) => Promise.resolve(phone.endsWith("1") ? { ok: true, providerMessageId: "WA1" } : { ok: false, error: "recusado" }),
  };
  const r = await enviarLote(db, provedor, [item("ai_agent", "5547900008001"), item("ai_agent", "5547900008002")], {
    delayMs: 0,
    registrar: (i) => { gravados.push(i.phone_normalized); return Promise.reject(new Error("falhou")); },
  });
  assertEquals(r.map((x) => x.ok), [true, false]);
  assertEquals(gravados, ["5547900008001"]);
});
