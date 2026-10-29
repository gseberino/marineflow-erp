// O "mesmo assunto" por ação (aprovação em lote, Fase 1, 29/10/2026). Os casos abaixo são os 9 cancelamentos por
// "pedido corrigido" dos 90 dias até 29/10, com a FORMA real do payload (as chaves de produção) e valores sintéticos no
// lugar de telefone e id. Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/assunto_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ASSUNTO_DAS_ACOES, mesmoAssunto } from "./assunto.ts";
import { allTools } from "./tools/index.ts";
import { NOME_DA_TOOL_DO_LOTE } from "../papelada/texto.ts";

const FLAVIO = "+55 47 99999-0001";
const OUTRO = "5547999990002";
const CLIENTE_A = "00000000-0000-4000-8000-00000000000a";

const casosReais: Array<{ quando: string; velha: { action_name: string; payload: unknown }; nova: { action_name: string; payload: unknown }; mesmo: boolean }> = [
  // correção legítima: "sem o link" do mesmo orçamento
  { quando: "05/10 09:45", velha: { action_name: "send_service_order_link", payload: { service_order_id: "ORÇ-00112", formato: "pdf_e_link" } },
    nova: { action_name: "send_service_order_link", payload: { service_order_id: "ORÇ-00112", formato: "pdf" } }, mesmo: true },
  // ações diferentes: guarda (desde 27/10)
  { quando: "06/10 21:37", velha: { action_name: "send_whatsapp_message", payload: { to_phone: FLAVIO, message: "a" } },
    nova: { action_name: "anotar_transacao_do_banco", payload: { quem: "Antonio", valor: 800, data: "06/10" } }, mesmo: false },
  // O DEFEITO: mensagem a uma pessoa cancelada por mensagem a OUTRA pessoa
  { quando: "08/10 11:04", velha: { action_name: "send_whatsapp_message", payload: { to_phone: FLAVIO, message: "a" } },
    nova: { action_name: "send_whatsapp_message", payload: { to_phone: OUTRO, message: "b" } }, mesmo: false },
  { quando: "14/10 16:12", velha: { action_name: "enviar_lembrete_de_revisao", payload: { embarcacao: "e1", planos: [], toque: 0 } },
    nova: { action_name: "registrar_diaria", payload: { data: "18/09", freelancer: "Mickael", jornada: "manter" } }, mesmo: false },
  // correção legítima: mesmo destino, texto novo
  { quando: "22/10 16:45", velha: { action_name: "send_whatsapp_message", payload: { to_phone: OUTRO, message: "a" } },
    nova: { action_name: "send_whatsapp_message", payload: { to_phone: OUTRO, message: "a corrigida" } }, mesmo: true },
  // O DEFEITO de novo: para o Flávio por número, depois para um cliente pelo cadastro
  { quando: "24/10 09:39", velha: { action_name: "send_whatsapp_message", payload: { to_phone: FLAVIO, message: "a" } },
    nova: { action_name: "send_whatsapp_message", payload: { client_id: CLIENTE_A, message: "b" } }, mesmo: false },
  { quando: "24/10 13:20", velha: { action_name: "registrar_diaria", payload: { freelancer: "Roberto", data: "19/10", data_ate: "22/10", jornada: "inteiro" } },
    nova: { action_name: "send_whatsapp_message", payload: { to_phone: FLAVIO, message: "b" } }, mesmo: false },
  { quando: "28/10 10:29", velha: { action_name: "send_whatsapp_message", payload: { client_id: CLIENTE_A, message: "a" } },
    nova: { action_name: "send_whatsapp_message", payload: { client_id: CLIENTE_A, message: "a2" } }, mesmo: true },
  { quando: "28/10 10:30", velha: { action_name: "send_whatsapp_message", payload: { client_id: CLIENTE_A, message: "a2" } },
    nova: { action_name: "send_whatsapp_message", payload: { client_id: CLIENTE_A, message: "a3" } }, mesmo: true },
];

for (const c of casosReais) {
  Deno.test(`dado real ${c.quando}: ${c.velha.action_name} → ${c.nova.action_name} ${c.mesmo ? "é correção (cancela)" : "é outro assunto (guarda)"}`, () => {
    assertEquals(mesmoAssunto(c.velha, c.nova), c.mesmo);
  });
}

Deno.test("o mesmo telefone escrito de dois jeitos é o mesmo destino", () => {
  assertEquals(mesmoAssunto(
    { action_name: "send_whatsapp_message", payload: { to_phone: "+55 (47) 99999-0001" } },
    { action_name: "send_whatsapp_message", payload: { to_phone: "5547999990001" } },
  ), true);
  assertEquals(mesmoAssunto(
    { action_name: "schedule_whatsapp_message", payload: { phone: "47 99999-0001", scheduled_at: "a" } },
    { action_name: "schedule_whatsapp_message", payload: { phone: "4799999-0001", scheduled_at: "b" } },
  ), true);
});

Deno.test("cadastro de serviço: o nome é o assunto (dois serviços diferentes nunca se cancelam)", () => {
  const a = { action_name: "create_service", payload: { name: "Realocação do banco de baterias", billing_unit: "unit", default_price: 1135 } };
  const b = { action_name: "create_service", payload: { name: "Realocação e ligação dos controladores solares", billing_unit: "unit", default_price: 920 } };
  assertEquals(mesmoAssunto(a, b), false);
  assertEquals(mesmoAssunto(a, { action_name: "create_service", payload: { name: "realocação do banco de baterias ", billing_unit: "visit", default_price: 1135 } }), true);
});

Deno.test("baixa: a conta a receber é o assunto (as 6 baixas de 21/08 não se cancelam entre si)", () => {
  const baixa = (id: string, amount: number) => ({ action_name: "register_payment", payload: { receivable_id: id, amount, payment_method: "pix" } });
  assertEquals(mesmoAssunto(baixa("r1", 756), baixa("r2", 1650)), false);
  assertEquals(mesmoAssunto(baixa("r1", 756), baixa("r1", 750)), true);
});

Deno.test("ação sem declaração nunca é 'o mesmo pedido': guarda, nunca cancela", () => {
  assertEquals(ASSUNTO_DAS_ACOES["emit_fiscal_service_note"], undefined);
  assertEquals(mesmoAssunto({ action_name: "emit_fiscal_service_note", payload: { service_order_id: "x" } },
    { action_name: "emit_fiscal_service_note", payload: { service_order_id: "x" } }), false);
  // declarada, mas sem nenhum campo de assunto preenchido: não dá para dizer que é o mesmo
  assertEquals(mesmoAssunto({ action_name: "send_whatsapp_message", payload: { message: "a" } },
    { action_name: "send_whatsapp_message", payload: { message: "b" } }), false);
  assertEquals(mesmoAssunto({ action_name: null }, { action_name: null }), false);
});

Deno.test("o lote da papelada: um lote novo substitui o anterior (a própria ação é o assunto)", () => {
  assertEquals(NOME_DA_TOOL_DO_LOTE, "aprovar_lote_da_papelada");
  assertEquals(mesmoAssunto({ action_name: NOME_DA_TOOL_DO_LOTE, payload: { lote_id: "l-1" } }, { action_name: NOME_DA_TOOL_DO_LOTE, payload: { lote_id: "l-2" } }), true);
});

Deno.test("diárias (27/10): 'Roberto de 19 a 24' e 'Roberto dia 20' são pedidos diferentes; a correção da jornada é o mesmo", () => {
  const semana = { action_name: "registrar_diaria", payload: { freelancer: "Roberto", data: "19/10", data_ate: "24/10" } };
  assertEquals(mesmoAssunto(semana, { action_name: "registrar_diaria", payload: { freelancer: "roberto ", data: "19/10", data_ate: "24/10", jornada: "meio" } }), true);
  assertEquals(mesmoAssunto(semana, { action_name: "registrar_diaria", payload: { freelancer: "Roberto", data: "20/10" } }), false);
  assertEquals(mesmoAssunto(semana, { action_name: "registrar_diaria", payload: { freelancer: "João" } }), false);
});

Deno.test("toda ação declarada existe (tool ou o lote da papelada), e todo campo declarado está no esquema dela", () => {
  const porNome = new Map(allTools.map((t) => [t.name, t]));
  const problemas: string[] = [];
  for (const [acao, campos] of Object.entries(ASSUNTO_DAS_ACOES)) {
    if (acao === NOME_DA_TOOL_DO_LOTE) continue;
    const t = porNome.get(acao);
    if (!t) {
      problemas.push(`${acao}: não existe`);
      continue;
    }
    const props = Object.keys((t.input_schema as { properties?: Record<string, unknown> }).properties ?? {});
    for (const c of campos) if (!props.includes(c)) problemas.push(`${acao}.${c}: fora do esquema`);
  }
  assertEquals(problemas, []);
});
