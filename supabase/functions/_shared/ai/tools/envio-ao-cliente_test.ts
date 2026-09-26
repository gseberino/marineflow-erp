import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  CARGOS_DO_PDF_AO_CLIENTE,
  enviarDocumentoWhatsapp,
  formatoDoEnvio,
  LIMITE_DA_MENSAGEM,
  lerPendenciaDoEnvio,
  mascararTelefone,
  oQueMudouDesdeOPedido,
  resumirEnvioAoCliente,
  whatsappTools,
} from "./whatsapp.ts";
import { impressaoDigitalDoDocumento } from "../../pdf/gerar-e-guardar.ts";
import { hashCurto } from "../../whatsapp/idempotencia.ts";
import { autonomyKey, isAutonomyGranted, NEVER_AUTONOMOUS, NEVER_AUTONOMOUS_WHEN } from "../autonomy-policy.ts";
import { ressalvaDoResultado, runAgentLoop } from "../agent.ts";

// Frente D (26/09/2026): o assistente passa a mandar ao CLIENTE o ARQUIVO PDF, com o link na
// legenda, em vez de só o link. O que estes testes protegem, em ordem de gravidade:
//
//  1. O DESTINO. O PDF leva preço, dados bancários e a chave PIX: vai SÓ para o WhatsApp do
//     cadastro do cliente da ordem. Nenhum telefone dos argumentos é lido.
//  2. A CONFIRMAÇÃO. O formato PDF (o padrão) nunca roda sozinho, nem com autonomia 'auto'
//     gravada para a tool. O 'link' continua liberável (Confiança Graduada).
//  3. O CARGO. PDF: admin, financeiro e vendedor. Vendedor externo só manda o link.
//  4. FALHOU O PDF, NADA SAI. Sem anexo não se manda "só o texto" por conta própria: volta
//     erro e a oferta de mandar só o link (nova confirmação).
//  5. O VÍNCULO. Os dois formatos levam context ('quote' para orçamento, 'service_order'
//     para OS) e service_order_id — é o que deixa a edge marcar 'sent' quando foi mesmo ao
//     cliente e amarra o audit_log à ordem.
//  6. O ANTI-DUPLICADO pelo conteúdo do documento (não pelo updated_at, não pelo relógio do
//     rodapé "Emitido em").

const tool = whatsappTools.find((t) => t.name === "send_service_order_link")!;

const CLIENTE = {
  id: "c1",
  name: "Cliente Exemplo Silva",
  display_name: null,
  whatsapp: "5547999990000",
  phone: "4733331234",
  opt_out_whatsapp: false,
};

const ORC = {
  id: "11111111-1111-4111-8111-111111111111",
  service_order_number: "ORÇ-00086",
  status: "draft",
  share_token: "22222222-2222-4222-8222-222222222222",
  client_id: "c1",
  updated_at: "2026-09-25T12:00:00.000Z",
  created_at: "2026-09-25T02:30:00.000Z",
  quote_validity_days: 7,
  grand_total: 18450.5,
  labor_cost_total: 6000,
  parts_cost_total: 13000,
  travel_cost_total: 0,
  discount_amount: 0,
  tax_amount: 0,
  operational_cost_total: 0,
  problem_description: "Instalar sistema solar",
  clients: { name: "Cliente Exemplo Silva", phone: "4733331234" },
  vessels: { name: "Lancha Azul" },
  marinas: null,
  service_order_services: [{ name_snapshot: "Instalação", quantity: 1, unit_price_snapshot: 6000, line_total: 6000, billing_unit_snapshot: "unit" }],
  service_order_parts: [{ products: { name: "Inversor" }, quantity: 1, unit_sale_snapshot: 13000, line_total_sale: 13000 }],
  service_surveys: [],
  service_order_expenses: [],
  service_order_photos: [],
  payment_condition_presets: null,
};
const OS = { ...ORC, id: "33333333-3333-4333-8333-333333333333", service_order_number: "OS-00087", status: "in_progress" };
const CANCELADA = { ...ORC, id: "44444444-4444-4444-8444-444444444444", service_order_number: "ORÇ-00090", status: "cancelled" };

/** 11h em Brasília: dentro da janela 8h–20h do portão de comunicação. */
const ONZE_DA_MANHA = new Date("2026-09-26T14:00:00.000Z");

// ─── Banco simulado: filtra de verdade, registra inserts e o "liberar" da chave ───────────
type Linha = Record<string, unknown>;

function montarBanco(tabelas: Record<string, Linha[]>, erros: Record<string, string> = {}) {
  const inseridos: Record<string, Linha[]> = {};
  const liberadas: unknown[] = [];
  let seq = 0;
  function consulta(nome: string) {
    let resultado = [...(tabelas[nome] ?? [])];
    let unico = false;
    let limite: number | null = null;
    const q: any = {
      select: () => q,
      // Estrito: filtro em coluna que a linha não tem NÃO casa.
      eq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { resultado = resultado.filter((l) => vs.includes(l[c])); return q; },
      not: () => q,
      order: () => q,
      limit: (n: number) => { limite = n; return q; },
      single: () => { unico = true; return q; },
      maybeSingle: () => { unico = true; return q; },
      insert: (linha: Linha) => {
        (inseridos[nome] ??= []).push(linha);
        const novo = { id: `novo-${++seq}`, ...linha };
        return {
          select: () => ({ single: () => Promise.resolve({ data: novo, error: null }) }),
          then: (resolve: (v: unknown) => void) => resolve({ data: null, error: null }),
        };
      },
      delete: () => ({ eq: (_c: string, v: unknown) => { liberadas.push(v); return Promise.resolve({ error: null }); } }),
      then: (resolve: (v: unknown) => void) => {
        if (erros[nome]) return resolve({ data: null, error: { message: erros[nome] } });
        const lista = limite === null ? resultado : resultado.slice(0, limite);
        resolve({ data: unico ? (lista[0] ?? null) : lista, error: null });
      },
    };
    return q;
  }
  return { consulta, inseridos, liberadas };
}

function montarAmbiente(opcoes: {
  ordens?: Linha[];
  cliente?: Partial<typeof CLIENTE>;
  respostaPdf?: () => Response | Promise<Response>;
  respostaEnvio?: () => Response | Promise<Response>;
  settings?: Record<string, string>;
  erros?: Record<string, string>;
  falhaUpload?: boolean;
} = {}) {
  const chamadas = { pdf: [] as Request[], envio: [] as any[], upload: [] as string[], removidos: [] as string[], openrouter: 0 };
  const banco = montarBanco({
    service_orders: opcoes.ordens ?? [ORC, OS, CANCELADA],
    clients: [{ ...CLIENTE, ...(opcoes.cliente ?? {}) }],
    app_settings: [{ key: "company_name", value: "HBR" }],
    app_users: [
      { id: "u1", full_name: "Gustavo Dono", role: "admin" },
      { id: "u9", full_name: "Paulo Externo", role: "external_seller" },
    ],
    receivables: [],
    payments: [],
  }, opcoes.erros);
  const admin = {
    from: (t: string) => banco.consulta(t),
    storage: {
      from: (bucket: string) => ({
        upload: (caminho: string) => {
          if (opcoes.falhaUpload) return Promise.resolve({ data: null, error: { message: "bucket fora" } });
          chamadas.upload.push(`${bucket}/${caminho}`);
          return Promise.resolve({ data: {}, error: null });
        },
        createSignedUrl: (caminho: string, s: number) => Promise.resolve({ data: { signedUrl: `https://sb.example/storage/v1/object/sign/${bucket}/${caminho}?exp=${s}` }, error: null }),
        remove: (caminhos: string[]) => { chamadas.removidos.push(...caminhos.map((c) => `${bucket}/${c}`)); return Promise.resolve({ data: [], error: null }); },
      }),
    },
  };
  const pdfValido = () => new Response(new Uint8Array([...new TextEncoder().encode("%PDF-1.7\n"), ...new Uint8Array(3000)]), { headers: { "content-type": "application/pdf" } });
  const fetchFalso = async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (url.endsWith("/api/pdf")) {
      chamadas.pdf.push(new Request(url, init));
      return await (opcoes.respostaPdf ?? pdfValido)();
    }
    if (url.endsWith("/functions/v1/whatsapp-send")) {
      chamadas.envio.push(JSON.parse(String(init?.body)));
      return await (opcoes.respostaEnvio ?? (() => new Response(JSON.stringify({ success: true, messageId: "m1" }))))();
    }
    throw new Error(`fetch inesperado: ${url}`);
  };
  const ctx = (role = "admin", userId = role === "external_seller" ? "u9" : "u1") => ({
    sb: admin, admin, userId, userRole: role as any, jwt: "", appOrigin: "",
    settings: { app_public_url: "https://erp.example", quote_validity_days: "3", ...(opcoes.settings ?? {}) },
  });
  return { chamadas, ctx, fetchFalso, admin, banco };
}

/** Roda com fetch simulado e relógio parado (o portão de horário e o dia da chave dependem dele). */
async function comFetch<T>(f: typeof fetch, corpo: () => Promise<T>, agora: Date = ONZE_DA_MANHA): Promise<T> {
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = f as typeof fetch;
  const relogio = new FakeTime(agora);
  try { return await corpo(); } finally { relogio.restore(); globalThis.fetch = original; }
}

async function executar(amb: ReturnType<typeof montarAmbiente>, args: Record<string, unknown>, role = "admin", agora?: Date) {
  return await comFetch(amb.fetchFalso as any, () => tool.execute(args, amb.ctx(role)), agora) as any;
}

// ─── Formato padrão ──────────────────────────────────────────────────────────────────────
Deno.test("sem formato, vai o ARQUIVO PDF com número, total e link /view na legenda", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.formato, "pdf_e_link");
  assertEquals(amb.chamadas.pdf.length, 1, "o PDF é renderizado uma vez");
  assertEquals(amb.chamadas.envio.length, 1);
  const corpo = amb.chamadas.envio[0];
  assertEquals(corpo.kind, "document");
  assertEquals(corpo.document_filename, "Orcamento_ORC-00086_Cliente-Exemplo-Silva_Lancha-Azul.pdf");
  const legenda: string = corpo.document_caption;
  assertStringIncludes(legenda, "Orçamento ORÇ-00086 — Total R$");
  assertStringIncludes(legenda, "18.450,50");
  assertStringIncludes(legenda, `Para ver online e aprovar: https://erp.example/view/${ORC.share_token}`);
  // O documento é o do Baixar: validade do próprio orçamento (7), não o padrão (3).
  const html = (await amb.chamadas.pdf[0].json()).html;
  assertStringIncludes(html, "Válido por 7 dias");
});

Deno.test("OS sai como Ordem de Serviço, com o mesmo link na legenda", async () => {
  const amb = montarAmbiente();
  await executar(amb, { service_order_id: "OS-00087" });
  assertStringIncludes(amb.chamadas.envio[0].document_caption, "Ordem de Serviço OS-00087 — Total");
  assertStringIncludes(amb.chamadas.envio[0].document_caption, "Para ver online e aprovar:");
});

Deno.test("mensagem personalizada abre a legenda, mas número, total e link vêm sempre", async () => {
  const amb = montarAmbiente();
  await executar(amb, { service_order_id: ORC.id, custom_message: "Bom dia! Conforme conversamos:" });
  const legenda: string = amb.chamadas.envio[0].document_caption;
  assert(legenda.startsWith("Bom dia! Conforme conversamos:"));
  assertStringIncludes(legenda, "Orçamento ORÇ-00086 — Total");
  assertStringIncludes(legenda, "/view/");
});

Deno.test("formato desconhecido é recusado — não adivinha", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertStringIncludes(r.error, "não existe");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
});

// ─── 1. Destino ──────────────────────────────────────────────────────────────────────────
Deno.test("destino: só o WhatsApp do cadastro do cliente, ignorando telefone nos argumentos", async () => {
  const amb = montarAmbiente();
  await executar(amb, { service_order_id: ORC.id, to_phone: "5511000000000", phone: "5511000000000", client_id: "outro" });
  assertEquals(amb.chamadas.envio[0].phone, CLIENTE.whatsapp);
});

Deno.test("destino: sem WhatsApp no cadastro, usa o telefone do cadastro", async () => {
  const amb = montarAmbiente({ cliente: { whatsapp: null as any } });
  await executar(amb, { service_order_id: ORC.id, to_phone: "5511000000000" });
  assertEquals(amb.chamadas.envio[0].phone, CLIENTE.phone);
});

Deno.test("cliente sem telefone nenhum: não gera PDF nem envia", async () => {
  const amb = montarAmbiente({ cliente: { whatsapp: null as any, phone: null as any } });
  const r = await executar(amb, { service_order_id: ORC.id, to_phone: "5511000000000" });
  assertStringIncludes(r.error, "sem WhatsApp");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
});

Deno.test("opt-out continua valendo no PDF", async () => {
  const amb = montarAmbiente({ cliente: { opt_out_whatsapp: true } });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertStringIncludes(r.error, "opt-out");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
});

Deno.test("ordem cancelada é recusada nos dois formatos, antes de gerar qualquer coisa", async () => {
  for (const formato of [undefined, "pdf_e_link", "link"]) {
    const amb = montarAmbiente();
    const r = await executar(amb, { service_order_id: "ORÇ-00090", ...(formato ? { formato } : {}) });
    assertStringIncludes(r.error, "CANCELADA");
    assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0, `formato ${formato}`);
  }
});

Deno.test("fora da janela 8h–20h: bloqueia antes de renderizar o PDF", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id }, "admin", new Date("2026-09-27T00:30:00.000Z")); // 21h30 em Brasília
  assertStringIncludes(r.error, "fora do horário");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
  assertEquals(amb.banco.inseridos.ai_comms_log?.[0]?.status, "blocked");
});

// ─── 5. Vínculo: context + service_order_id ──────────────────────────────────────────────
Deno.test("orçamento vai com context='quote' e service_order_id, nos dois formatos", async () => {
  for (const formato of ["pdf_e_link", "link"]) {
    const amb = montarAmbiente();
    await executar(amb, { service_order_id: "ORÇ-00086", formato });
    assertEquals(amb.chamadas.envio[0].context, "quote", formato);
    assertEquals(amb.chamadas.envio[0].service_order_id, ORC.id, formato);
  }
});

Deno.test("OS vai com context='service_order' (só o vínculo; não é orçamento para marcar)", async () => {
  for (const formato of ["pdf_e_link", "link"]) {
    const amb = montarAmbiente();
    await executar(amb, { service_order_id: OS.id, formato });
    assertEquals(amb.chamadas.envio[0].context, "service_order", formato);
    assertEquals(amb.chamadas.envio[0].service_order_id, OS.id, formato);
  }
});

Deno.test("a proteção da tool para si continua: enviarDocumentoWhatsapp recusa context='quote'", async () => {
  const r = await enviarDocumentoWhatsapp({ phone: "5547999990000", url: "https://x", filename: "a.pdf", caption: "", context: "quote", jwt: "" });
  assertEquals(r.ok, false);
});

// ─── 3. Cargo ────────────────────────────────────────────────────────────────────────────
Deno.test("vendedor externo: o PDF é recusado antes de ler qualquer coisa; o link passa", async () => {
  const amb = montarAmbiente();
  for (const args of [{ service_order_id: ORC.id }, { service_order_id: ORC.id, formato: "pdf_e_link" }]) {
    const r = await executar(amb, args, "external_seller");
    assertStringIncludes(r.error, "formato 'link'");
  }
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
  const r = await executar(amb, { service_order_id: ORC.id, formato: "link" }, "external_seller");
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.chamadas.envio[0].kind, "text");
});

Deno.test("vendedor e financeiro mandam o PDF; técnico não manda nada", async () => {
  for (const cargo of ["seller", "financial"]) {
    const amb = montarAmbiente();
    const r = await executar(amb, { service_order_id: ORC.id }, cargo);
    assertEquals(r.ok, true, `${cargo}: ${JSON.stringify(r)}`);
  }
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id }, "technician");
  assert(r.error);
  assertEquals(amb.chamadas.envio.length, 0);
});

Deno.test("a lista de cargos do PDF é explícita e não tem vendedor externo", () => {
  assertEquals(CARGOS_DO_PDF_AO_CLIENTE, ["admin", "financial", "seller"]);
});

// ─── 4. Falhou o PDF, nada sai ───────────────────────────────────────────────────────────
for (const [nome, opcoes] of [
  ["503 do /api/pdf", { respostaPdf: () => new Response("desligado", { status: 503 }) }],
  ["HTML no lugar do PDF", { respostaPdf: () => new Response("<html>erro</html>", { headers: { "content-type": "text/html" } }) }],
  ["dados do documento ilegíveis", { erros: { receivables: "banco fora" } }],
  ["bucket recusou o arquivo", { falhaUpload: true }],
] as Array<[string, Parameters<typeof montarAmbiente>[0]]>) {
  Deno.test(`${nome}: nada é enviado e a tool oferece mandar só o link`, async () => {
    const amb = montarAmbiente(opcoes);
    const r = await executar(amb, { service_order_id: ORC.id });
    assertStringIncludes(r.error, "Nada foi enviado ao cliente");
    // Depois do "sim" o dono só vê o texto do error (o ai-agent responde sem o modelo): a
    // oferta de mandar só o link tem de estar nele.
    assertStringIncludes(r.error, "mando só o link");
    assertStringIncludes(r.error, "nova confirmação");
    assertEquals(r.nada_enviado, true);
    assertStringIncludes(r.orientacao, "formato='link'");
    assertStringIncludes(r.orientacao, "nova confirmação");
    assertEquals(amb.chamadas.envio.length, 0, "sem anexo, nem o texto sai");
    assertEquals(amb.chamadas.removidos, amb.chamadas.upload, "o que subiu é apagado");
    assertEquals(amb.banco.inseridos.ai_comms_log?.[0]?.status, "failed");
  });
}

Deno.test("WhatsApp recusou o envio (502): NÃO mexe na chave (a edge já liberou), apaga o arquivo e diz que nada foi", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ error: "Connection Closed" }), { status: 502 }) });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertStringIncludes(r.error, "Connection Closed");
  assertEquals(r.nada_enviado, true);
  assertEquals(amb.banco.liberadas, []);
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
});

// Revisão adversarial de 26/09/2026: 400/401/500 a edge devolve ANTES de reservar. Se a chave
// existe, é de um envio anterior JÁ CONCLUÍDO — liberar aqui deixaria o mesmo PDF sair de
// novo ao cliente no pedido seguinte.
for (const status of [400, 401, 500]) {
  Deno.test(`resposta definitiva HTTP ${status}: a reserva de um envio anterior fica de pé`, async () => {
    const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ error: `recusado ${status}` }), { status }) });
    const r = await executar(amb, { service_order_id: ORC.id });
    assertStringIncludes(r.error, `recusado ${status}`);
    assertEquals(r.nada_enviado, true);
    assertEquals(amb.banco.liberadas, []);
  });
}

Deno.test("erro de rede (sem resposta HTTP): libera a chave e NÃO afirma que nada chegou", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => { throw new TypeError("error sending request: connection reset"); } });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertStringIncludes(r.error, "pode ter chegado ou não");
  assertEquals(r.nada_enviado, undefined);
  assertEquals(amb.banco.liberadas, [amb.chamadas.envio[0].dedupe_key]);
});

Deno.test("envio sem resposta (25 s): libera a chave e NÃO afirma que nada chegou", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => { throw new DOMException("cortado", "AbortError"); } });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertStringIncludes(r.error, "pode ter chegado ou não");
  assertStringIncludes(r.error, "Confira a conversa");
  assertStringIncludes(r.orientacao, "get_whatsapp_conversation");
  assertEquals(r.nada_enviado, undefined);
  assertEquals(amb.banco.liberadas, [amb.chamadas.envio[0].dedupe_key]);
});

Deno.test("sucesso: sobe no bucket privado, apaga depois e o resultado não tem URL nem token", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id });
  assertEquals(amb.chamadas.upload.length, 1);
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
  const texto = JSON.stringify(r);
  assert(!texto.includes("http"), texto);
  assert(!texto.includes(ORC.share_token));
  assertStringIncludes(r.enviado_para, "••••0000");
  assertEquals(amb.banco.inseridos.ai_comms_log?.[0]?.status, "sent");
});

/** Modo de teste como a edge desvia de fato: interruptor ligado E número de teste preenchido. */
const MODO_TESTE = { wa_test_mode: "true", wa_test_number: "5547988887777" };

Deno.test("modo de teste ligado: não diz que chegou ao cliente", async () => {
  const amb = montarAmbiente({ settings: MODO_TESTE });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertStringIncludes(r.enviado_para, "TESTE");
  assertStringIncludes(r.observacao, "NÃO para o cliente");
});

// Conferência de 26/09/2026: a edge só desvia com o modo ligado E um número de teste. Ligado
// sem número, o PDF vai ao CLIENTE — e a tool dizia "foi para o número de TESTE".
Deno.test("modo ligado sem número: a edge não desvia, e a tool diz que foi ao cliente", async () => {
  for (const settings of [{ wa_test_mode: "true" }, { wa_test_mode: "true", wa_test_number: "" }] as Record<string, string>[]) {
    const amb = montarAmbiente({ settings });
    const r = await executar(amb, { service_order_id: ORC.id });
    assertEquals(r.ok, true, JSON.stringify(r));
    assertStringIncludes(r.enviado_para, "••••0000", JSON.stringify(settings));
    assert(!r.enviado_para.includes("TESTE"), r.enviado_para);
    assertEquals(r.observacao, "O cliente recebeu o PDF com o link para ver online e aprovar.");
  }
});

// ─── 6. Anti-duplicado pelo conteúdo ─────────────────────────────────────────────────────
async function chaveDoEnvio(ordem: Linha, agora: Date) {
  const amb = montarAmbiente({ ordens: [ordem] });
  await executar(amb, { service_order_id: ordem.id }, "admin", agora);
  const html: string = (await amb.chamadas.pdf[0].json()).html;
  return { chave: amb.chamadas.envio[0].dedupe_key as string, html };
}

Deno.test("mesmo conteúdo, mesmo número, mesmo dia: a mesma chave, mesmo com o rodapé 'Emitido em' diferente", async () => {
  const manha = await chaveDoEnvio(ORC, ONZE_DA_MANHA);
  const tarde = await chaveDoEnvio(ORC, new Date("2026-09-26T18:30:45.000Z"));
  assertNotEquals(manha.html, tarde.html, "o carimbo do rodapé muda com o relógio");
  assertEquals(manha.chave, tarde.chave);
  assert(manha.chave.startsWith("os-pdf:"), manha.chave);
  assertStringIncludes(manha.chave, "5547999990000");
  assertStringIncludes(manha.chave, "2026-09-26");
});

Deno.test("a chave não depende do updated_at: tocar na ordem sem mudar o documento não reenvia", async () => {
  const a = await chaveDoEnvio(ORC, ONZE_DA_MANHA);
  const b = await chaveDoEnvio({ ...ORC, updated_at: "2026-09-26T13:59:00.000Z" }, ONZE_DA_MANHA);
  assertEquals(a.chave, b.chave);
});

Deno.test("mudou o conteúdo (total) ou o dia: chave nova, o envio passa", async () => {
  const base = await chaveDoEnvio(ORC, ONZE_DA_MANHA);
  const outroTotal = await chaveDoEnvio({ ...ORC, grand_total: 19000 }, ONZE_DA_MANHA);
  const outroDia = await chaveDoEnvio(ORC, new Date("2026-09-27T14:00:00.000Z"));
  assertNotEquals(base.chave, outroTotal.chave);
  assertNotEquals(base.chave, outroDia.chave);
});

// Revisão adversarial de 26/09/2026: o envio no modo de teste (que vai ao número de TESTE)
// reservava a mesma chave do envio ao cliente. Desligado o modo no mesmo dia, o envio de
// verdade ouvia "já foi enviado hoje" e o cliente ficava sem nada.
async function chaveComSettings(formato: "pdf_e_link" | "link", settings: Record<string, string>) {
  const amb = montarAmbiente({ settings });
  await executar(amb, { service_order_id: ORC.id, formato });
  return amb.chamadas.envio[0].dedupe_key as string;
}

Deno.test("modo de teste entra na chave do PDF: o envio de teste não bloqueia o de verdade", async () => {
  const real = await chaveComSettings("pdf_e_link", {});
  const teste = await chaveComSettings("pdf_e_link", MODO_TESTE);
  const testeLegado = await chaveComSettings("pdf_e_link", { zapi_test_mode: "true", zapi_test_number: "+55 47 98888-7777" });
  assertNotEquals(real, teste);
  assert(teste.endsWith(":teste"), teste);
  assertEquals(teste, `${real}:teste`, "só a marca muda: mesmo documento, número e dia");
  assertEquals(testeLegado, teste, "a chave antiga (zapi_test_mode) vale igual");
  assert(!real.includes("teste"), real);
  assertEquals(await chaveComSettings("pdf_e_link", { ...MODO_TESTE, wa_test_mode: "false" }), real);
});

Deno.test("modo de teste entra na chave do link; fora dele a chave é a de sempre", async () => {
  assertEquals(await chaveComSettings("link", {}), `os-link:${ORC.id}:5547999990000:2026-09-26`);
  assertEquals(await chaveComSettings("link", MODO_TESTE), `os-link:${ORC.id}:5547999990000:2026-09-26:teste`);
});

// Modo ligado sem número: a edge manda ao CLIENTE (não desvia). A chave com ":teste" deixava o
// cliente receber o mesmo documento de novo quando o modo fosse desligado no mesmo dia (a chave
// mudava). A chave tem de ser a do cliente — a mesma de sempre.
Deno.test("modo ligado sem número: a chave é a do cliente, sem a marca de teste", async () => {
  const real = await chaveComSettings("pdf_e_link", {});
  assertEquals(await chaveComSettings("pdf_e_link", { wa_test_mode: "true" }), real);
  assertEquals(await chaveComSettings("pdf_e_link", { wa_test_mode: "true", wa_test_number: "" }), real);
  assertEquals(await chaveComSettings("pdf_e_link", { zapi_test_mode: "true" }), real);
  assertEquals(await chaveComSettings("link", { wa_test_mode: "true" }), `os-link:${ORC.id}:5547999990000:2026-09-26`);
});

Deno.test("impressão digital ignora só o carimbo 'Emitido em'", () => {
  const a = "<footer><span>Emitido em 26/09/2026, 11:00:00</span></footer><b>Total R$ 10</b>";
  const b = "<footer><span>Emitido em 26/09/2026, 15:30:45</span></footer><b>Total R$ 10</b>";
  const c = "<footer><span>Emitido em 26/09/2026, 11:00:00</span></footer><b>Total R$ 11</b>";
  assertEquals(impressaoDigitalDoDocumento(a), impressaoDigitalDoDocumento(b));
  assertNotEquals(impressaoDigitalDoDocumento(a), impressaoDigitalDoDocumento(c));
});

Deno.test("a edge reconheceu a chave: avisa sem fingir novo envio", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const r = await executar(amb, { service_order_id: ORC.id });
  assertEquals(r.deduplicated, true);
  assertStringIncludes(r.aviso, "não reenviei");
});

// ─── Formato 'link': o comportamento de antes (mais o vínculo) ──────────────────────────
Deno.test("formato 'link': o mesmo texto e a mesma chave de antes, sem PDF", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "link" });
  assertEquals(r, { ok: true, messageId: "m1" });
  assertEquals(amb.chamadas.pdf.length, 0);
  assertEquals(amb.chamadas.upload.length, 0);
  const corpo = amb.chamadas.envio[0];
  assertEquals(corpo.kind, "text");
  assertEquals(corpo.phone, CLIENTE.whatsapp);
  assertEquals(corpo.message, `Olá Cliente, segue o link da OS ORÇ-00086: https://erp.example/view/${ORC.share_token}`);
  assertEquals(corpo.dedupe_key, `os-link:${ORC.id}:5547999990000:2026-09-26`);
});

Deno.test("formato 'link' repetido no dia: mesma resposta de antes", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "link" });
  assertEquals(r.deduplicated, true);
  assertEquals(r.messageId, null);
  assertStringIncludes(r.aviso, "já tinha sido enviada hoje");
});

// ─── 2. Confirmação: o PDF nunca roda sozinho ────────────────────────────────────────────
const AUTO = { [autonomyKey("send_service_order_link")]: "auto" };

Deno.test("autonomia 'auto': o PDF (explícito ou padrão) continua pedindo confirmação; o link não", () => {
  assertEquals(isAutonomyGranted("send_service_order_link", "high", AUTO, {}), false);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", AUTO, { formato: "pdf_e_link" }), false);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", AUTO, undefined), false, "sem args = pior caso");
  assertEquals(isAutonomyGranted("send_service_order_link", "high", AUTO, { formato: "link" }), true);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", {}, { formato: "link" }), false, "sem 'auto', pede");
});

Deno.test("a trava da autonomia e a tool leem o formato do mesmo jeito", () => {
  for (const formato of [undefined, null, "", "  ", "link", " LINK ", "Link", "pdf_e_link", "PDF_E_LINK", "pdf", "pdf+link", 123]) {
    const args = { formato } as Record<string, unknown>;
    const travado = NEVER_AUTONOMOUS_WHEN.send_service_order_link(args);
    assertEquals(travado, formatoDoEnvio(args) !== "link", `formato=${JSON.stringify(formato)}`);
  }
});

Deno.test("a tool é sempre risco alto, sem computeRisk que a rebaixe, e não está na trava total", () => {
  assertEquals(tool.risk, "high");
  assertEquals(tool.computeRisk, undefined);
  // O link continua liberável: a trava é por argumento, não pela tool inteira.
  assertEquals(NEVER_AUTONOMOUS.has("send_service_order_link"), false);
});

// ─── Resumo da confirmação ───────────────────────────────────────────────────────────────
Deno.test("resumo mostra cliente, telefone mascarado, número, total e formato", async () => {
  const amb = montarAmbiente();
  const pdf = await resumirEnvioAoCliente(amb.admin, { service_order_id: "ORÇ-00086" });
  assert(pdf);
  assertStringIncludes(pdf, "Cliente Exemplo Silva");
  assertStringIncludes(pdf, "••••0000");
  assert(!pdf.includes(CLIENTE.whatsapp), "o telefone inteiro não aparece");
  assertStringIncludes(pdf, "ORÇ-00086");
  assertStringIncludes(pdf, "18.450,50");
  assertStringIncludes(pdf, "PDF anexado");
  const link = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "link" });
  assertStringIncludes(link!, "só o link");
  const cancelada = await resumirEnvioAoCliente(amb.admin, { service_order_id: CANCELADA.id });
  assertStringIncludes(cancelada!, "CANCELADA");
  assertEquals(await resumirEnvioAoCliente(amb.admin, { service_order_id: "ORÇ-09999" }), null);
});

Deno.test("resumo avisa quando o orçamento está marcado como recusado no funil", async () => {
  const recusado = { ...ORC, id: "55555555-5555-4555-8555-555555555555", service_order_number: "ORÇ-00072", quote_status: "rejected" };
  const amb = montarAmbiente({ ordens: [recusado] });
  const resumo = await resumirEnvioAoCliente(amb.admin, { service_order_id: recusado.id }, ONZE_DA_MANHA);
  assertStringIncludes(resumo!, "RECUSADO no funil");
  assert(!resumo!.includes("validade acabou"), "recusado mas dentro da validade: a data não é aviso");
});

// ORC: emitido 24/09 às 23h30 de Brasília (25/09 02h30 UTC), 7 dias → último dia 01/10/2026.
Deno.test("validade: o resumo avisa quando o PDF sairia vencido, pela mesma conta do documento", async () => {
  const amb = montarAmbiente();
  const dentro = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id }, new Date("2026-10-01T22:00:00.000Z"));
  assert(!dentro!.includes("validade acabou"), "no último dia ainda vale");
  // 23h30 de 01/10 em Brasília já é 02/10 em UTC: o dia que conta é o de Brasília.
  const virada = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id }, new Date("2026-10-02T02:30:00.000Z"));
  assert(!virada!.includes("validade acabou"), "o fuso não antecipa o vencimento");
  const vencido = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id }, new Date("2026-10-02T12:00:00.000Z"));
  assertStringIncludes(vencido!, "⚠️ A validade acabou em 01/10/2026");
});

Deno.test("validade: data fixa manda; OS não tem validade para avisar", async () => {
  const comData = { ...ORC, quote_validity_date: "2026-09-20" };
  const amb = montarAmbiente({ ordens: [comData, OS] });
  const r = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id }, ONZE_DA_MANHA);
  assertStringIncludes(r!, "A validade acabou em 20/09/2026");
  const os = await resumirEnvioAoCliente(amb.admin, { service_order_id: OS.id }, new Date("2027-01-01T12:00:00.000Z"));
  assert(!os!.includes("validade acabou"));
});

Deno.test("validade: sem dias no orçamento, vale o padrão da empresa (mesma ordem do PDF)", async () => {
  const semDias = { ...ORC, quote_validity_days: null };
  const amb = montarAmbiente({ ordens: [semDias] });
  const ajustes = montarBanco({ app_settings: [{ key: "quote_validity_days", value: "3" }] });
  const admin = { ...amb.admin, from: (t: string) => t === "app_settings" ? ajustes.consulta(t) : amb.admin.from(t) };
  // 24/09 + 3 = 27/09: no dia 28 já venceu.
  const r = await resumirEnvioAoCliente(admin, { service_order_id: ORC.id }, new Date("2026-09-28T15:00:00.000Z"));
  assertStringIncludes(r!, "A validade acabou em 27/09/2026");
});

// ─── Mensagem personalizada: inteira na confirmação, recusada acima do limite ───────────
Deno.test("resumo mostra a mensagem personalizada INTEIRA (antes cortava em 200)", async () => {
  const amb = montarAmbiente();
  const longa = "Bom dia! " + "Detalhe combinado na visita. ".repeat(20) + "FIM-DA-MENSAGEM";
  assert(longa.length > 200 && longa.length <= LIMITE_DA_MENSAGEM.pdf_e_link);
  const r = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, custom_message: longa }, ONZE_DA_MANHA);
  assertStringIncludes(r!, longa);
});

Deno.test("mensagem acima do limite: recusada antes da pendência e no execute; o resumo avisa", async () => {
  const amb = montarAmbiente();
  const enorme = "x".repeat(LIMITE_DA_MENSAGEM.pdf_e_link + 1);
  const pre = tool.preValidar!({ service_order_id: ORC.id, custom_message: enorme }, amb.ctx() as any);
  assertStringIncludes(String(pre?.error), "cabem até 800");
  const r = await executar(amb, { service_order_id: ORC.id, custom_message: enorme });
  assertStringIncludes(r.error, "cabem até 800");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
  const resumo = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, custom_message: enorme }, ONZE_DA_MANHA);
  assertStringIncludes(resumo!, "o envio será recusado");
  // No 'link' o texto é a mensagem inteira: o mesmo tamanho passa.
  assertEquals(tool.preValidar!({ service_order_id: ORC.id, formato: "link", custom_message: enorme }, amb.ctx() as any), null);
});

Deno.test("formato 'link' com mensagem sem o link: o link vai no fim, e o resumo diz isso", async () => {
  const amb = montarAmbiente();
  const args = { service_order_id: ORC.id, formato: "link", custom_message: "Oi! Segue o orçamento que combinamos." };
  const resumo = await resumirEnvioAoCliente(amb.admin, args, ONZE_DA_MANHA);
  assertStringIncludes(resumo!, "ele vai no fim");
  await executar(amb, args);
  assertEquals(amb.chamadas.envio[0].message, `Oi! Segue o orçamento que combinamos.\n\nhttps://erp.example/view/${ORC.share_token}`);
});

Deno.test("formato 'link' com mensagem que já traz o link: vai como está", async () => {
  const amb = montarAmbiente();
  const msg = `Oi! Veja aqui: https://erp.example/view/${ORC.share_token} — qualquer dúvida me chama.`;
  const resumo = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "link", custom_message: msg }, ONZE_DA_MANHA);
  assert(!resumo!.includes("ele vai no fim"));
  await executar(amb, { service_order_id: ORC.id, formato: "link", custom_message: msg });
  assertEquals(amb.chamadas.envio[0].message, msg);
});

Deno.test("máscara do telefone mostra só os 4 últimos dígitos", () => {
  assertEquals(mascararTelefone("+55 (47) 99999-1234"), "••••1234");
  assertEquals(mascararTelefone(null), "••••");
});

// ─── No loop do agente, de ponta a ponta ─────────────────────────────────────────────────
function respostaDoModelo(conteudo: { texto?: string; ferramenta?: { nome: string; args: unknown } }) {
  return {
    id: "gen_test",
    choices: [{
      message: {
        role: "assistant",
        content: conteudo.texto ?? null,
        ...(conteudo.ferramenta
          ? { tool_calls: [{ id: "toolu_1", type: "function", function: { name: conteudo.ferramenta.nome, arguments: JSON.stringify(conteudo.ferramenta.args) } }] }
          : {}),
      },
      finish_reason: conteudo.ferramenta ? "tool_calls" : "stop",
    }],
    usage: { prompt_tokens: 10, completion_tokens: 5 },
  };
}

async function rodarNoAgente(args: Record<string, unknown>, opcoes: { role?: string; settings?: Record<string, string> } = {}) {
  const amb = montarAmbiente({ settings: opcoes.settings ?? AUTO });
  const respostas = [respostaDoModelo({ ferramenta: { nome: "send_service_order_link", args } }), respostaDoModelo({ texto: "feito" })];
  const fetchComModelo = async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (url.includes("openrouter.ai")) return new Response(JSON.stringify(respostas[Math.min(amb.chamadas.openrouter++, 1)]), { headers: { "content-type": "application/json" } });
    return await amb.fetchFalso(entrada, init);
  };
  Deno.env.set("OPENROUTER_API_KEY", "chave-de-teste");
  const resultado = await comFetch(fetchComModelo as any, () =>
    runAgentLoop({
      system: [{ type: "text", text: "teste" }],
      messages: [{ role: "user", content: [{ type: "text", text: "manda o orçamento 86 pro cliente" }] }],
      tools: [tool],
      toolCtx: amb.ctx(opcoes.role ?? "admin"),
      sessionId: "sessao-teste",
    }));
  return { amb, resultado };
}

Deno.test("no agente, com autonomia 'auto' gravada: o PDF vira pendência com resumo completo e não envia", async () => {
  const { amb, resultado } = await rodarNoAgente({ service_order_id: ORC.id });
  assertEquals(amb.chamadas.envio.length, 0, "nada sai sem o 'sim'");
  assertEquals(amb.chamadas.pdf.length, 0);
  const pendencia = amb.banco.inseridos.ai_operator_pending_actions?.[0];
  assert(pendencia, "a pendência foi gravada");
  assertEquals(pendencia.title, "Enviar orçamento/OS ao cliente (WhatsApp)");
  const resumo = String(pendencia.summary);
  for (const trecho of ["Cliente Exemplo Silva", "••••0000", "ORÇ-00086", "18.450,50", "PDF anexado"]) {
    assertStringIncludes(resumo, trecho);
  }
  // Quem pediu vai no resumo (o admin que aprova no painel vê de quem é o pedido) e no
  // payload (a execução revalida com o cargo dele).
  assertStringIncludes(resumo, "Pedido por: *Gustavo Dono* (Administrador)");
  // E o retrato do que foi aprovado: telefone (em hash) e total.
  assertEquals(pendencia.payload, {
    service_order_id: ORC.id,
    _solicitante: { user_id: "u1", nome: "Gustavo Dono", cargo: "admin" },
    _retrato: { telefone: hashCurto(CLIENTE.whatsapp), total: 18450.5 },
  });
  assert(!JSON.stringify(pendencia.payload).includes(CLIENTE.whatsapp), "o número não fica no payload");
  assert(resultado.proposal, "o turno devolve a proposta para o usuário confirmar");
});

Deno.test("no agente: _retrato vindo do modelo é trocado pelo lido do banco", async () => {
  const { amb } = await rodarNoAgente({ service_order_id: ORC.id, _retrato: { telefone: "forjado", total: 1 } });
  const pendencia = amb.banco.inseridos.ai_operator_pending_actions?.[0];
  assertEquals((pendencia!.payload as any)._retrato, { telefone: hashCurto(CLIENTE.whatsapp), total: 18450.5 });
  assert(!String(pendencia!.summary).includes("forjado"), "o resumo é montado sem o retrato");
});

// ─── 8. O "sim" é sobre o retrato: telefone ou total mudou até a aprovação, não envia ─────
Deno.test("execução: retrato igual ao de agora, envia", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, _retrato: { telefone: hashCurto(CLIENTE.whatsapp), total: 18450.5 } });
  assertEquals(r.ok, true, JSON.stringify(r));
});

Deno.test("execução: o total mudou desde o pedido — nada sai, e diz de quanto para quanto", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, _retrato: { telefone: hashCurto(CLIENTE.whatsapp), total: 15000 } });
  assertStringIncludes(r.error, "o total mudou");
  assertStringIncludes(r.error, "15.000,00");
  assertStringIncludes(r.error, "18.450,50");
  assertEquals(r.nada_enviado, true);
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
});

Deno.test("execução: o WhatsApp do cadastro mudou desde o pedido — nada sai, nos dois formatos", async () => {
  for (const formato of [undefined, "link"]) {
    const amb = montarAmbiente({ cliente: { whatsapp: "5547988887777" } });
    const r = await executar(amb, {
      service_order_id: ORC.id,
      ...(formato ? { formato } : {}),
      _retrato: { telefone: hashCurto(CLIENTE.whatsapp), total: 18450.5 },
    });
    assertStringIncludes(r.error, "WhatsApp do cliente no cadastro mudou");
    assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
  }
});

Deno.test("retrato torto não recusa à toa: total que não é número é ignorado", () => {
  assertEquals(oQueMudouDesdeOPedido({ total: "abc" }, { digitos: "1", total: 10 }), null);
  assertEquals(oQueMudouDesdeOPedido({}, { digitos: "1", total: 10 }), null);
});

// ─── 6. Pendência gravada antes do PDF: vale o que o dono aprovou (só o link) ────────────
Deno.test("pendência antiga (sem _solicitante e sem formato) é lida como 'só o link'", () => {
  assertEquals(tool.lerPendencia, lerPendenciaDoEnvio);
  assertEquals(lerPendenciaDoEnvio({ service_order_id: ORC.id }), { service_order_id: ORC.id, formato: "link" });
  assertEquals(lerPendenciaDoEnvio({ service_order_id: ORC.id, formato: "" }).formato, "link");
  // Pendência nova (tem _solicitante): o padrão novo vale, sem formato é o PDF.
  const nova = { service_order_id: ORC.id, _solicitante: { user_id: "u1", nome: null, cargo: "admin" } };
  assertEquals(lerPendenciaDoEnvio(nova), nova);
  // Formato explícito é respeitado sempre.
  assertEquals(lerPendenciaDoEnvio({ service_order_id: ORC.id, formato: "pdf_e_link" }).formato, "pdf_e_link");
});

// ─── 5. Depois do "sim": o "executado" leva a ressalva da tool ───────────────────────────
Deno.test("ressalva da aprovação: modo de teste e 'já enviado hoje' aparecem; envio normal não acrescenta nada", async () => {
  const teste = montarAmbiente({ settings: { wa_test_mode: "true", wa_test_number: "5547900000000" } });
  const rTeste = await executar(teste, { service_order_id: ORC.id });
  assertStringIncludes(ressalvaDoResultado(rTeste), "número de TESTE");
  const repetido = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const rRepetido = await executar(repetido, { service_order_id: ORC.id });
  assertStringIncludes(ressalvaDoResultado(rRepetido), "já foi enviado hoje");
  const normal = montarAmbiente();
  assertEquals(ressalvaDoResultado(await executar(normal, { service_order_id: ORC.id })), "");
  assertEquals(ressalvaDoResultado(null), "");
  assertEquals(ressalvaDoResultado({ aviso: ["não", "é", "texto"] }), "");
});

// ─── 3b. Cargo de QUEM PEDIU (revisão adversarial de 26/09/2026) ─────────────────────────
// Antes: a pendência do vendedor externo dizia "PDF anexado" e só falhava depois do "sim"; e
// um admin que a aprovasse no painel mandava o PDF com o cargo DELE.
Deno.test("no agente: vendedor externo pedindo o PDF é recusado ANTES da pendência — nada no sino, nada enviado", async () => {
  for (const args of [{ service_order_id: ORC.id }, { service_order_id: ORC.id, formato: "pdf_e_link" }]) {
    const { amb, resultado } = await rodarNoAgente(args, { role: "external_seller", settings: {} });
    assertEquals(amb.banco.inseridos.ai_operator_pending_actions, undefined, JSON.stringify(args));
    assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
    assertEquals(resultado.proposal, undefined);
    const r = resultado.toolEvents[0].result as any;
    assertStringIncludes(r.error, "formato 'link'");
    assertEquals(r.nada_enviado, true);
  }
});

Deno.test("no agente: vendedor externo pedindo SÓ o link vira pendência com quem pediu", async () => {
  const { amb } = await rodarNoAgente({ service_order_id: ORC.id, formato: "link" }, { role: "external_seller", settings: {} });
  const pendencia = amb.banco.inseridos.ai_operator_pending_actions?.[0];
  assert(pendencia, "o link continua podendo ser pedido");
  assertEquals((pendencia.payload as any)._solicitante, { user_id: "u9", nome: "Paulo Externo", cargo: "external_seller" });
  assertStringIncludes(String(pendencia.summary), "só o link");
  assertStringIncludes(String(pendencia.summary), "Pedido por: *Paulo Externo* (Vendedor Externo)");
  assertEquals(amb.chamadas.envio.length, 0);
});

Deno.test("formato inexistente também é recusado antes da pendência", async () => {
  const { amb, resultado } = await rodarNoAgente({ service_order_id: ORC.id, formato: "pdf" }, { settings: {} });
  assertEquals(amb.banco.inseridos.ai_operator_pending_actions, undefined);
  assertStringIncludes((resultado.toolEvents[0].result as any).error, "não existe");
});

Deno.test("execução: pendência do vendedor externo aprovada por um admin NÃO manda o PDF", async () => {
  const amb = montarAmbiente();
  const payload = { service_order_id: ORC.id, _solicitante: { user_id: "u9", nome: "Paulo Externo", cargo: "external_seller" } };
  const r = await executar(amb, payload, "admin"); // ctx = quem confirma (admin, u1)
  assertStringIncludes(r.error, "O cargo de quem pediu (Paulo Externo)");
  assertStringIncludes(r.error, "formato 'link'");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
  // O link do mesmo vendedor externo, aprovado pelo admin, sai normalmente.
  const link = await executar(amb, { ...payload, formato: "link" }, "admin");
  assertEquals(link.ok, true, JSON.stringify(link));
  assertEquals(amb.chamadas.envio[0].kind, "text");
});

Deno.test("execução: pendência do vendedor, aprovada por um admin, manda o PDF", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, _solicitante: { user_id: "u5", nome: "Vendedor", cargo: "seller" } }, "admin");
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.chamadas.envio[0].kind, "document");
});

Deno.test("execução: _solicitante forjado nos argumentos não amplia o cargo de quem executa", async () => {
  const amb = montarAmbiente();
  const forjado = { service_order_id: ORC.id, _solicitante: { user_id: "u1", nome: "Admin", cargo: "admin" } };
  const r = await executar(amb, forjado, "external_seller");
  assertStringIncludes(r.error, "formato 'link'");
  // Cargo torto (ou ausente) no payload nega em vez de liberar.
  const torto = await executar(amb, { service_order_id: ORC.id, _solicitante: { user_id: "u5", cargo: "dono" } }, "admin");
  assertStringIncludes(torto.error, "formato 'link'");
  const semCargo = await executar(amb, { service_order_id: ORC.id, _solicitante: { user_id: "u5" } }, "admin");
  assertStringIncludes(semCargo.error, "formato 'link'");
  assertEquals(amb.chamadas.pdf.length + amb.chamadas.envio.length, 0);
});

Deno.test("execução: pendência ANTIGA, sem _solicitante, vale o cargo de quem executa (por isso a conferência de deploy)", async () => {
  // Pendências gravadas antes desta versão não sabem quem pediu. Não há como revalidar o cargo
  // de quem pediu — o passo de produção exige 0 pendências de send_service_order_link abertas.
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id }, "admin");
  assertEquals(r.ok, true, JSON.stringify(r));
});

Deno.test("preValidar da tool e execute usam a mesma checagem", () => {
  const pv = tool.preValidar!;
  const ctx = (userRole: string, userId = "u1") => ({ userRole, userId }) as any;
  assert(pv({ service_order_id: ORC.id }, ctx("external_seller", "u9")));
  assert(pv({ service_order_id: ORC.id, formato: "pdf_e_link" }, ctx("external_seller", "u9")));
  assertEquals(pv({ service_order_id: ORC.id, formato: "link" }, ctx("external_seller", "u9")), null);
  assertEquals(pv({ service_order_id: ORC.id }, ctx("seller")), null);
  assertStringIncludes(pv({ service_order_id: ORC.id, formato: "pdf" }, ctx("admin"))!.error, "não existe");
  assertEquals(tool.gravarSolicitante, true);
});

Deno.test("no agente, com autonomia 'auto' gravada: o link roda direto (Confiança Graduada mantida)", async () => {
  const { amb } = await rodarNoAgente({ service_order_id: ORC.id, formato: "link" });
  assertEquals(amb.banco.inseridos.ai_operator_pending_actions, undefined);
  assertEquals(amb.chamadas.envio.length, 1);
  assertEquals(amb.chamadas.envio[0].kind, "text");
});
