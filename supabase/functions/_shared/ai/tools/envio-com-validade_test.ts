// Retorno F3 (P9): a validade de 7 dias contados do ENVIO, escrita no PDF e na legenda (K6, rr-k6.json).
// A data fica em quote_validity_date, que o PDF e a R19 já leem, e é refeita a cada tentativa enquanto o orçamento está em
// rascunho: PDF que falha não congela a data. Depois de 'sent' não renova. Nomes e telefones inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { fixarValidadeDoEnvio, whatsappTools } from "./whatsapp.ts";

const tool = whatsappTools.find((t) => t.name === "send_service_order_link")!;

// ─── Banco de mentira só para fixarValidadeDoEnvio ──────────────────────────────────────────
function adminFalso(opcoes: { dias?: unknown; erroUpdate?: string; erroConfig?: string } = {}) {
  const updates: { tabela: string; campos: Record<string, unknown>; coluna: string; valor: unknown }[] = [];
  const leituras: string[] = [];
  const admin = {
    from(tabela: string) {
      if (tabela === "retorno_config") {
        return {
          select: (colunas: string) => {
            leituras.push(colunas);
            return {
              maybeSingle: () =>
                Promise.resolve(
                  opcoes.erroConfig
                    ? { data: null, error: { message: opcoes.erroConfig } }
                    : { data: { validade_orcamento_dias: "dias" in opcoes ? opcoes.dias : 7 }, error: null },
                ),
            };
          },
        };
      }
      if (tabela === "service_orders") {
        return {
          update: (campos: Record<string, unknown>) => ({
            eq: (coluna: string, valor: unknown) => {
              updates.push({ tabela, campos, coluna, valor });
              return Promise.resolve(opcoes.erroUpdate ? { error: { message: opcoes.erroUpdate } } : { error: null });
            },
          }),
        };
      }
      throw new Error(`tabela inesperada: ${tabela}`);
    },
  };
  return { admin, updates, leituras };
}

const SO_RASCUNHO = { id: "os-1", quote_status: "draft", origem: "retorno_previa", quote_validity_date: null };
const AS_23H30_BRT = new Date("2026-12-08T02:30:00.000Z");   // 23:30 de 07/12 em Brasília

Deno.test("com origem e sem data: 7 dias pelo calendário de Brasília, relógio às 23:30 BRT", async () => {
  const { admin, updates } = adminFalso();
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates.length, 1);
  assertEquals(updates[0].campos, { quote_validity_days: 7, quote_validity_date: "2026-12-14" });
  assertEquals(updates[0].coluna, "id");
  assertEquals(updates[0].valor, "os-1");
});

Deno.test("com dataDoCartao e sem origem: grava essa data, com os dias da config", async () => {
  const { admin, updates } = adminFalso({ dias: 10 });
  const r = await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, origem: null }, "2026-12-20", AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates[0].campos, { quote_validity_days: 10, quote_validity_date: "2026-12-20" });
});

Deno.test("sem origem e sem dataDoCartao: nenhum update, nem leitura de config (tela e assistente livre até a F5)", async () => {
  const { admin, updates, leituras } = adminFalso();
  const r = await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, origem: null }, undefined, AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates.length, 0);
  assertEquals(leituras.length, 0);
});

Deno.test("orçamento já enviado (sent): não renova, mesmo com origem ou data do cartão (D13)", async () => {
  const { admin, updates } = adminFalso();
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_status: "sent" }, "2026-12-20", AS_23H30_BRT);
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_status: "sent" }, undefined, AS_23H30_BRT);
  assertEquals(updates.length, 0);
});

Deno.test("rascunho com data de tentativa anterior: refaz a partir de agora", async () => {
  const { admin, updates } = adminFalso();
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_validity_date: "2026-12-10" }, undefined, AS_23H30_BRT);
  assertEquals(updates[0].campos.quote_validity_date, "2026-12-14");
});

Deno.test("validade_orcamento_dias que não serve (0, nulo, texto) cai nos 7 dias", async () => {
  for (const dias of [0, null, "abc", -1]) {
    const { admin, updates } = adminFalso({ dias });
    await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
    assertEquals(updates[0].campos.quote_validity_days, 7, `dias = ${dias}`);
    assertEquals(updates[0].campos.quote_validity_date, "2026-12-14");
  }
});

Deno.test("config que falha ao ler cai nos 7 dias, sem derrubar", async () => {
  const { admin, updates } = adminFalso({ erroConfig: "tabela fora" });
  await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(updates[0].campos.quote_validity_days, 7);
});

Deno.test("erro no update não lança e devolve aviso_validade", async () => {
  const { admin } = adminFalso({ erroUpdate: "update recusado" });
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(r, { aviso_validade: "Não consegui gravar a validade; o PDF saiu com a validade antiga, confira na tela." });
});

Deno.test("exceção de verdade (cliente quebrado): nunca lança", async () => {
  const admin = { from() { throw new Error("cliente quebrado"); } };
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(typeof r.aviso_validade, "string");
});

// ─── O envio inteiro, com banco e fetch simulados ──────────────────────────────────────────
type Linha = Record<string, unknown>;
const CLIENTE = { id: "c1", name: "Cliente Validade Silva", display_name: null, whatsapp: "5547999990123", phone: "4733331234", opt_out_whatsapp: false, generico: false };
const ORC = {
  id: "11111111-1111-4111-8111-111111111111",
  service_order_number: "ORÇ-00123",
  status: "draft",
  quote_status: "draft",
  origem: "retorno_previa",
  share_token: "22222222-2222-4222-8222-222222222222",
  client_id: "c1",
  updated_at: "2026-09-25T12:00:00.000Z",
  created_at: "2026-09-25T02:30:00.000Z",
  quote_validity_days: 3,
  quote_validity_date: null,
  grand_total: 1000,
  labor_cost_total: 0,
  parts_cost_total: 1000,
  travel_cost_total: 0,
  discount_amount: 0,
  tax_amount: 0,
  operational_cost_total: 0,
  problem_description: "Serviço de teste",
  clients: { name: "Cliente Validade Silva", phone: "4733331234" },
  vessels: { name: "Barco Azul" },
  marinas: null,
  service_order_services: [],
  service_order_parts: [],
  service_surveys: [],
  service_order_expenses: [],
  service_order_photos: [],
  payment_condition_presets: null,
};
const ONZE_DA_MANHA = new Date("2026-09-26T14:00:00.000Z");

function montarAmbiente(opcoes: { erroUpdate?: string; respostaEnvio?: () => Response; ordem?: Linha } = {}) {
  const sequencia: string[] = [];
  const updates: { tabela: string; campos: Record<string, unknown> }[] = [];
  const tabelas: Record<string, Linha[]> = {
    service_orders: [opcoes.ordem ?? ORC],
    clients: [CLIENTE],
    app_settings: [{ key: "company_name", value: "HBR" }],
    app_users: [{ id: "u1", full_name: "Gustavo Dono", role: "admin" }],
    receivables: [],
    payments: [],
    retorno_config: [{ validade_orcamento_dias: 7 }],
  };
  const consulta = (nome: string) => {
    let resultado = [...(tabelas[nome] ?? [])];
    let unico = false;
    const q: any = {
      select: (colunas?: string) => { sequencia.push(`select:${nome}:${colunas ?? ""}`); return q; },
      eq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] === v); return q; },
      neq: () => q,
      in: () => q,
      not: () => q,
      order: () => q,
      limit: () => q,
      single: () => { unico = true; return q; },
      maybeSingle: () => { unico = true; return q; },
      insert: () => ({ select: () => ({ single: () => Promise.resolve({ data: { id: "novo" }, error: null }) }), then: (ok: (v: unknown) => void) => ok({ data: null, error: null }) }),
      delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
      update: (campos: Record<string, unknown>) => ({
        eq: (_c: string, _v: unknown) => {
          sequencia.push(`update:${nome}`);
          updates.push({ tabela: nome, campos });
          return Promise.resolve(opcoes.erroUpdate ? { error: { message: opcoes.erroUpdate } } : { error: null });
        },
      }),
      then: (ok: (v: unknown) => void) => ok({ data: unico ? (resultado[0] ?? null) : resultado, error: null }),
    };
    return q;
  };
  const admin = {
    from: (t: string) => consulta(t),
    storage: {
      from: (_bucket: string) => ({
        upload: () => Promise.resolve({ data: {}, error: null }),
        createSignedUrl: (caminho: string) => Promise.resolve({ data: { signedUrl: `https://sb.example/${caminho}` }, error: null }),
        remove: () => Promise.resolve({ data: [], error: null }),
      }),
    },
  };
  const envios: any[] = [];
  const pdfValido = () => new Response(new Uint8Array([...new TextEncoder().encode("%PDF-1.7\n"), ...new Uint8Array(3000)]), { headers: { "content-type": "application/pdf" } });
  const fetchFalso = async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (url.endsWith("/api/pdf")) return pdfValido();
    if (url.endsWith("/functions/v1/whatsapp-send")) {
      sequencia.push("whatsapp-send");
      envios.push(JSON.parse(String(init?.body)));
      return (opcoes.respostaEnvio ?? (() => new Response(JSON.stringify({ success: true, messageId: "m1" }))))();
    }
    throw new Error(`fetch inesperado: ${url}`);
  };
  const ctx = {
    sb: admin, admin, userId: "u1", userRole: "admin" as const, jwt: "", appOrigin: "",
    settings: { app_public_url: "https://erp.example", quote_validity_days: "3" },
  };
  return { sequencia, updates, envios, fetchFalso, ctx };
}

async function executar(amb: ReturnType<typeof montarAmbiente>, args: Record<string, unknown>, ctxExtra: Record<string, unknown> = {}) {
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = amb.fetchFalso as typeof fetch;
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    return await tool.execute(args, { ...amb.ctx, ...ctxExtra } as any) as any;
  } finally {
    relogio.restore();
    globalThis.fetch = original;
  }
}

Deno.test("execute: o update roda antes de montarDocumentoDaOrdem, e so não é relido", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates.length, 1);
  assertEquals(amb.updates[0].campos.quote_validity_days, 7);
  const posUpdate = amb.sequencia.indexOf("update:service_orders");
  const posMontar = amb.sequencia.findIndex((s) => s.startsWith("select:service_orders:") && s.includes("clients(*)"));
  assert(posUpdate >= 0, "sem update");
  assert(posMontar > posUpdate, `montar veio antes do update: ${amb.sequencia.join(" > ")}`);
  const relidas = amb.sequencia.filter((s) => s.startsWith("select:service_orders:") && s.includes("cancellation_reason"));
  assertEquals(relidas.length, 1, "o so do envio não é relido");
});

Deno.test("execute: com dataDoCartao no contexto, grava essa data mesmo sem origem", async () => {
  const amb = montarAmbiente({ ordem: { ...ORC, origem: null } });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" }, { validadeDoCartao: "2026-10-03" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates[0].campos.quote_validity_date, "2026-10-03");
});

Deno.test("execute: sem origem e sem data do cartão não mexe na validade", async () => {
  const amb = montarAmbiente({ ordem: { ...ORC, origem: null } });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates.length, 0);
  assertEquals(r.aviso_validade, undefined);
});

Deno.test("execute: ok e deduplicated levam destino_chave8 (os 8 últimos dígitos do telefone real)", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.destino_chave8, "99990123");
  const dup = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const rDup = await executar(dup, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(rDup.ok, true, JSON.stringify(rDup));
  assertEquals(rDup.deduplicated, true);
  assertEquals(rDup.destino_chave8, "99990123");
});

Deno.test("execute: erro no update não derruba o envio e o aviso_validade vai nos dois resultados ok", async () => {
  const amb = montarAmbiente({ erroUpdate: "fora do ar" });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertStringIncludes(r.aviso_validade, "Não consegui gravar a validade");
  assertEquals(amb.envios.length, 1, "o PDF saiu mesmo assim");
  const dup = montarAmbiente({ erroUpdate: "fora do ar", respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const rDup = await executar(dup, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(rDup.deduplicated, true);
  assertStringIncludes(rDup.aviso_validade, "Não consegui gravar a validade");
});
