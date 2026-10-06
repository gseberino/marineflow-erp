// Mensagem agendada pelo assistente (05/10/2026). O que se protege: "08:00" sem fuso é 08:00 de
// Brasília (antes saía às 05:00); fora de 8h–20h e no passado é recusado antes da pendência; o
// número ganha o 55 e o nono dígito; a confirmação mostra nome, número inteiro, dia por extenso e
// a mensagem; contato novo vira o nome da conversa; e agendar nunca roda sem confirmação.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cadastrarContatoDoAgendamento, horarioDoAgendamento, quandoPorExtenso, resumirAgendamento,
  telefoneLegivel, telefoneParaEnvio, validarAgendamento,
} from "./agendamento.ts";
import { whatsappTools } from "./whatsapp.ts";
import { isAutonomyGranted, autonomyKey, NEVER_AUTONOMOUS } from "../autonomy-policy.ts";

// Domingo 05/10/2026, 22:30 em Brasília — "depois do horário comercial".
const AGORA = new Date("2026-10-06T01:30:00.000Z");

Deno.test("horário sem fuso é Brasília: 'amanhã 08:00' sai às 08:00, não às 05:00", () => {
  const h = horarioDoAgendamento("2026-10-06T08:00", AGORA);
  assertEquals(h, { iso: "2026-10-06T11:00:00.000Z" });
  assertEquals(quandoPorExtenso("2026-10-06T11:00:00.000Z"), "terça, 06/10 às 08:00");
  // Só a data: 08:00 de Brasília.
  assertEquals(horarioDoAgendamento("2026-10-06", AGORA), { iso: "2026-10-06T11:00:00.000Z" });
});

Deno.test("fora de 8h–20h e no passado: recusado, com sugestão", () => {
  assertStringIncludes((horarioDoAgendamento("2026-10-06T06:00", AGORA) as any).error, "fora do horário comercial");
  assertStringIncludes((horarioDoAgendamento("2026-10-06T20:30", AGORA) as any).error, "fora do horário comercial");
  assertEquals("iso" in horarioDoAgendamento("2026-10-06T20:00", AGORA), true, "20:00 em ponto ainda vale");
  assertStringIncludes((horarioDoAgendamento("2026-10-05T10:00", AGORA) as any).error, "já passou");
  assertStringIncludes((horarioDoAgendamento("amanhã", AGORA) as any).error, "não entendida");
});

Deno.test("número: completa o 55 e o nono dígito; inválido não passa", () => {
  assertEquals(telefoneParaEnvio("47 99915-9654"), "5547999159654");
  assertEquals(telefoneParaEnvio("(47) 9915-9654"), "5547999159654");
  assertEquals(telefoneParaEnvio("+351 966 776 422"), "351966776422");
  assertEquals(telefoneParaEnvio("9654"), null);
  assertEquals(telefoneLegivel("5547999159654"), "+55 (47) 99915-9654");
});

function banco(opcoes: { cliente?: Record<string, unknown>; lead?: Record<string, unknown> | null } = {}) {
  const gravado = { inserts: [] as Array<[string, Record<string, unknown>]>, updates: [] as Array<[string, Record<string, unknown>]> };
  const admin = {
    from(t: string) {
      const q: any = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve({ data: t === "clients" ? (opcoes.cliente ?? null) : t === "whatsapp_leads" ? (opcoes.lead ?? null) : null, error: null }),
        update: (v: Record<string, unknown>) => { gravado.updates.push([t, v]); return { eq: () => Promise.resolve({ error: null }) }; },
        insert: (v: Record<string, unknown>) => {
          gravado.inserts.push([t, v]);
          const criado = { id: "s1", ...v };
          return { select: () => ({ single: () => Promise.resolve({ data: criado, error: null }) }), then: (ok: (r: unknown) => unknown) => Promise.resolve({ error: null }).then(ok) };
        },
      };
      return q;
    },
  };
  return { admin, gravado };
}

Deno.test("confirmação de contato NOVO: nome, número inteiro, dia por extenso e a mensagem", async () => {
  const { admin } = banco();
  const r = await resumirAgendamento(admin, { phone: "47 99915-9654", contact_name: "Carlos da Marina", scheduled_at: "2026-10-06T08:00", message: "Bom dia, Carlos! Aqui é o Gustavo da HBR." }, AGORA);
  assertStringIncludes(r, "Para: *Carlos da Marina* — contato NOVO");
  assertStringIncludes(r, "WhatsApp: +55 (47) 99915-9654");
  assertStringIncludes(r, "Quando: *terça, 06/10 às 08:00* (horário de Brasília)");
  assertStringIncludes(r, 'Mensagem: "Bom dia, Carlos! Aqui é o Gustavo da HBR."');
});

Deno.test("confirmação de cliente e de conversa existente; horário ruim aparece na confirmação", async () => {
  const cliente = await resumirAgendamento(banco({ cliente: { name: "Nelson - S.I. 7.8", whatsapp: "47991455678" } }).admin, { client_id: "c1", scheduled_at: "2026-10-06T09:00", message: "Oi" }, AGORA);
  assertStringIncludes(cliente, "*Nelson - S.I. 7.8* (cliente do cadastro)");
  assertStringIncludes(cliente, "+55 (47) 99145-5678");
  const conversa = await resumirAgendamento(banco({ lead: { name: "Miguel" } }).admin, { phone: "351966776422", scheduled_at: "2026-10-06T06:00", message: "Oi" }, AGORA);
  assertStringIncludes(conversa, "*Miguel* (conversa que já existe no WhatsApp)");
  assertStringIncludes(conversa, "⚠️");
});

Deno.test("validação antes da pendência: mensagem vazia, número inválido, horário fora", () => {
  assertStringIncludes(validarAgendamento({ phone: "47999159654", scheduled_at: "2026-10-06T08:00", message: " " }, AGORA)!.error, "vazia");
  assertStringIncludes(validarAgendamento({ phone: "1234", scheduled_at: "2026-10-06T08:00", message: "Oi" }, AGORA)!.error, "inválido");
  assertEquals(validarAgendamento({ phone: "47999159654", scheduled_at: "2026-10-06T08:00", message: "Oi" }, AGORA), null);
});

Deno.test("contato novo vira o nome da conversa; conversa com nome não muda", async () => {
  const novo = banco();
  assertEquals(await cadastrarContatoDoAgendamento(novo.admin, "5547999159654", "Carlos da Marina"), "criado");
  assertEquals(novo.gravado.inserts[0][0], "whatsapp_leads");
  assertEquals(novo.gravado.inserts[0][1].name, "Carlos da Marina");
  assertEquals(novo.gravado.inserts[0][1].message_count, 0);
  const semNome = banco({ lead: { id: "l1", name: null } });
  assertEquals(await cadastrarContatoDoAgendamento(semNome.admin, "5547999159654", "Carlos"), "nomeado");
  const comNome = banco({ lead: { id: "l1", name: "Carlos Marina" } });
  assertEquals(await cadastrarContatoDoAgendamento(comNome.admin, "5547999159654", "Outro"), "ja_tinha");
  assertEquals(comNome.gravado.updates.length, 0);
});

Deno.test("a tool grava o número normalizado e a hora em Brasília, e cadastra o contato novo", async () => {
  const { admin, gravado } = banco();
  const tool = whatsappTools.find((t) => t.name === "schedule_whatsapp_message")!;
  const ctx = { sb: admin, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as never;
  const r = await tool.execute({ phone: "47 99915-9654", contact_name: "Carlos da Marina", scheduled_at: "2030-10-08T08:00", message: "Bom dia!" }, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  const agendada = gravado.inserts.find(([t]) => t === "whatsapp_scheduled_sends")![1];
  assertEquals(agendada.phone, "5547999159654");
  assertEquals(agendada.scheduled_at, "2030-10-08T11:00:00.000Z");
  assertEquals(r.quando, "terça, 08/10 às 08:00 (Brasília)");
  assertStringIncludes(r.contato, "Carlos da Marina");
  assert(tool.preValidar!({ phone: "47999159654", scheduled_at: "2030-10-08T05:00", message: "Oi" }, ctx), "fora da janela barra antes da pendência");
});

Deno.test("agendar mensagem nunca roda sozinho, mesmo com autonomia gravada", () => {
  assert(NEVER_AUTONOMOUS.has("schedule_whatsapp_message"));
  assertEquals(isAutonomyGranted("schedule_whatsapp_message", "medium", { [autonomyKey("schedule_whatsapp_message")]: "auto" }), false);
});
