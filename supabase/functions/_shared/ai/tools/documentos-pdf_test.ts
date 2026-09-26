import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  BUCKET_DO_PDF,
  CONTEXTO_DO_ENVIO,
  documentoPdfTools,
  interpretarDocumento,
  limitarNomeDoArquivo,
  localizarOrdem,
} from "./documentos-pdf.ts";

// O que estes testes protegem, em ordem de gravidade:
//
//  1. O STATUS DO ORÇAMENTO. Com context='quote' + service_order_id, o whatsapp-send marca o
//     orçamento como ENVIADO AO CLIENTE — e daí vêm a expiração automática, a tarefa de
//     follow-up e o briefing tratando como enviado. O dono pedir o PDF para si não pode
//     disparar nada disso.
//  2. O DESTINO. O PDF leva preço, PIX e dados do cliente: vai só para o telefone de quem
//     pediu, lido do cadastro, nunca de um argumento.
//  3. O CARGO. Admin e financeiro. Técnico, vendedor e vendedor externo, não.
//  4. A CREDENCIAL DO /api/pdf. Só o token do link; com Authorization junto, o /api/pdf dá
//     preferência ao Bearer e recusa a chave de serviço sem olhar o token.
//  5. O ARQUIVO NÃO FICA. Bucket privado, apagado no sucesso e na falha.

const tool = documentoPdfTools.find((t) => t.name === "send_document_pdf_to_self")!;

const ORDEM = {
  id: "11111111-1111-4111-8111-111111111111",
  service_order_number: "ORÇ-00086",
  status: "draft",
  share_token: "22222222-2222-4222-8222-222222222222",
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
  clients: { name: "Cliente Exemplo", phone: "4799990000" },
  vessels: { name: "Lancha Azul" },
  marinas: null,
  service_order_services: [{ name_snapshot: "Instalação", quantity: 1, unit_price_snapshot: 6000, line_total: 6000, billing_unit_snapshot: "unit" }],
  service_order_parts: [{ products: { name: "Inversor" }, quantity: 1, unit_sale_snapshot: 13000, line_total_sale: 13000 }],
  service_surveys: [],
  service_order_expenses: [],
  service_order_photos: [],
  payment_condition_presets: null,
};

const OS = { ...ORDEM, id: "33333333-3333-4333-8333-333333333333", service_order_number: "OS-00086", status: "in_progress", created_at: "2026-09-20T12:00:00.000Z" };

// ─── Banco simulado: filtra de verdade (eq/neq/in/order/limit) ───────────────────────────
type Linha = Record<string, unknown>;
function consulta(linhas: Linha[]) {
  let resultado = [...linhas];
  let unico = false;
  let limite: number | null = null;
  const q: any = {
    select: () => q,
    // Estrito: filtro em coluna que a linha não tem NÃO casa. Ignorar deixaria passar um
    // .eq("user_id", …) errado ou um .limit(1) no lugar do filtro por quem pediu.
    eq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] === v); return q; },
    neq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] !== v); return q; },
    in: (c: string, vs: unknown[]) => { resultado = resultado.filter((l) => vs.includes(l[c])); return q; },
    not: () => q,
    order: (c: string, o?: { ascending?: boolean }) => {
      resultado.sort((a, b) => String(a[c] ?? "").localeCompare(String(b[c] ?? "")) * (o?.ascending === false ? -1 : 1));
      return q;
    },
    limit: (n: number) => { limite = n; return q; },
    single: () => { unico = true; return q; },
    maybeSingle: () => { unico = true; return q; },
    then: (resolve: (v: unknown) => void) => {
      const lista = limite === null ? resultado : resultado.slice(0, limite);
      resolve({ data: unico ? (lista[0] ?? null) : lista, error: null });
    },
  };
  return q;
}

function montarAmbiente(opcoes: {
  ordens?: Linha[];
  telefone?: string | null;
  respostaPdf?: () => Response | Promise<Response>;
  respostaEnvio?: () => Response | Promise<Response>;
  settings?: Record<string, string>;
  userId?: string;
} = {}) {
  const chamadas = { pdf: [] as Request[], envio: [] as { headers: Headers; corpo: any }[], upload: [] as string[], removidos: [] as string[], liberadas: [] as unknown[] };
  const tabelas: Record<string, Linha[]> = {
    service_orders: opcoes.ordens ?? [ORDEM, OS],
    app_users: [
      { id: "u0", phone_normalized: "5548988887777" },
      { id: "u1", phone_normalized: opcoes.telefone === undefined ? "5547999159654" : opcoes.telefone },
      { id: "u2", phone_normalized: "5547911112222" },
    ],
    app_settings: [{ key: "company_name", value: "HBR" }],
    receivables: [],
    payments: [],
  };
  const admin = {
    from: (t: string) => t === "whatsapp_send_idempotencia"
      ? { delete: () => ({ eq: (_c: string, v: unknown) => { chamadas.liberadas.push(v); return Promise.resolve({ error: null }); } }) }
      : consulta(tabelas[t] ?? []),
    storage: {
      from: (bucket: string) => ({
        upload: (caminho: string) => { chamadas.upload.push(`${bucket}/${caminho}`); return Promise.resolve({ data: {}, error: null }); },
        createSignedUrl: (caminho: string, s: number) => Promise.resolve({ data: { signedUrl: `https://sb.example/sign/${bucket}/${caminho}?exp=${s}` }, error: null }),
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
      chamadas.envio.push({ headers: new Headers(init?.headers), corpo: JSON.parse(String(init?.body)) });
      return await (opcoes.respostaEnvio ?? (() => new Response(JSON.stringify({ success: true, messageId: "m1" }))))();
    }
    throw new Error(`fetch inesperado: ${url}`);
  };
  const ctx = (role = "admin", userId = opcoes.userId ?? "u1") => ({
    sb: admin, admin, userId, userRole: role as any, jwt: "", appOrigin: "",
    settings: { app_public_url: "https://erp.example", quote_validity_days: "3", ...(opcoes.settings ?? {}) },
  });
  return { chamadas, ctx, fetchFalso };
}

async function comFetch<T>(f: typeof fetch, corpo: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = f as typeof fetch;
  try { return await corpo(); } finally { globalThis.fetch = original; }
}

// ─── 1. Status do orçamento ──────────────────────────────────────────────────────────────
Deno.test("o envio nunca leva context='quote' nem service_order_id", async () => {
  const amb = montarAmbiente();
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.chamadas.envio.length, 1);
  const corpo = amb.chamadas.envio[0].corpo;
  assertEquals(corpo.kind, "document");
  assertEquals(corpo.context, CONTEXTO_DO_ENVIO);
  assert(corpo.context !== "quote");
  assert(!("service_order_id" in corpo), "service_order_id no corpo marcaria o orçamento como enviado");
});

// ─── 2. Destino ──────────────────────────────────────────────────────────────────────────
Deno.test("o PDF vai para o telefone do cadastro de quem pediu, ignorando qualquer outro", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () =>
    tool.execute({ documento: "86", tipo: "orcamento", to_phone: "5511000000000", phone: "5511000000000" }, amb.ctx()));
  assertEquals(amb.chamadas.envio[0].corpo.phone, "5547999159654");
});

Deno.test("sem WhatsApp no cadastro, não gera nada", async () => {
  const amb = montarAmbiente({ telefone: null });
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertStringIncludes(r.error, "WhatsApp cadastrado");
  assertEquals(amb.chamadas.pdf.length, 0);
  assertEquals(amb.chamadas.envio.length, 0);
});

// ─── 3. Cargo ────────────────────────────────────────────────────────────────────────────
for (const cargo of ["technician", "seller", "external_seller", "unknown"]) {
  Deno.test(`cargo ${cargo} é recusado antes de ler qualquer coisa`, async () => {
    const amb = montarAmbiente();
    const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx(cargo)));
    assert(r.error, `${cargo} deveria ser recusado`);
    assertEquals(amb.chamadas.pdf.length, 0);
    assertEquals(amb.chamadas.envio.length, 0);
  });
}

Deno.test("financeiro pode pedir", async () => {
  const amb = montarAmbiente();
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx("financial")));
  assertEquals(r.ok, true);
});

Deno.test("a lista de cargos da tool não inclui vendedor externo", () => {
  assertEquals(tool.roles, ["admin", "financial"]);
});

// ─── 4. Credencial do /api/pdf ───────────────────────────────────────────────────────────
Deno.test("o /api/pdf recebe só o token do link, sem Authorization", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  const req = amb.chamadas.pdf[0];
  assertEquals(req.url, "https://erp.example/api/pdf");
  assertEquals(req.headers.get("x-share-token"), ORDEM.share_token);
  assertEquals(req.headers.get("authorization"), null);
});

Deno.test("o documento enviado ao /api/pdf é o orçamento do formulário: título, tipo e validade", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  const corpo = await amb.chamadas.pdf[0].json();
  assertStringIncludes(corpo.html, "<title>Orcamento_ORC-00086_Cliente-Exemplo_Lancha-Azul</title>");
  assertStringIncludes(corpo.html, ">Orçamento</h1>");
  // A validade do PRÓPRIO orçamento (7), não o padrão da empresa (3).
  assertStringIncludes(corpo.html, "Válido por 7 dias");
  assertEquals(corpo.filename, "Orcamento_ORC-00086_Cliente-Exemplo_Lancha-Azul.pdf");
  assertEquals(amb.chamadas.envio[0].corpo.document_filename, corpo.filename);
});

// A R19 avisa do vencimento pela data fixa (quote_validity_date) quando ela existe; o PDF do
// assistente dizia "Válido por 7 dias" do mesmo orçamento até 26/09/2026.
Deno.test("orçamento com data fixa sai com 'Válido até' a data — a mesma da R19", async () => {
  const amb = montarAmbiente({ ordens: [{ ...ORDEM, quote_validity_date: "2026-10-10" }, OS] });
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  const corpo = await amb.chamadas.pdf[0].json();
  assertStringIncludes(corpo.html, "Válido até 10/10/2026");
  assert(!corpo.html.includes("Válido por"), "a data fixa vence os dias");
});

// A via de execução nunca é padrão: um pdf_options_service_order gravado com ela não pode
// fazer o dono receber uma OS sem preço (opcoesPadraoDoDocumento força hideFinancials: false).
Deno.test("OS do assistente sai com valores mesmo com via de execução no padrão gravado", async () => {
  const amb = montarAmbiente({ settings: { pdf_options_service_order: JSON.stringify({ hideFinancials: true }) } });
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "OS-00086" }, amb.ctx()));
  const corpo = await amb.chamadas.pdf[0].json();
  assertStringIncludes(corpo.html, ">Ordem de Serviço</h1>");
  assert(!corpo.html.includes("Via de Execução"), "saiu como via de execução");
});

Deno.test("OS sai como Ordem de Serviço (o tipo vem do status, como na tela)", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "OS-00086" }, amb.ctx()));
  const corpo = await amb.chamadas.pdf[0].json();
  assertStringIncludes(corpo.html, ">Ordem de Serviço</h1>");
  assert(!corpo.html.includes("Válido por"), "OS não tem validade de orçamento");
});

Deno.test("a legenda traz número, cliente e total, e nunca o token", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  const legenda: string = amb.chamadas.envio[0].corpo.document_caption;
  assertStringIncludes(legenda, "Orçamento ORÇ-00086 — Cliente Exemplo · Lancha Azul");
  assertStringIncludes(legenda, "18.450,50");
  assert(!legenda.includes(ORDEM.share_token));
});

// ─── 5. O arquivo não fica ───────────────────────────────────────────────────────────────
Deno.test("sucesso: sobe no bucket privado e apaga depois; o resultado não tem URL nem token", async () => {
  const amb = montarAmbiente();
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertEquals(amb.chamadas.upload.length, 1);
  assert(amb.chamadas.upload[0].startsWith(`${BUCKET_DO_PDF}/agente/`));
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
  assert(amb.chamadas.envio[0].corpo.document_url.includes("exp=180"), "URL assinada de 3 minutos");
  const texto = JSON.stringify(r);
  assert(!texto.includes("http"), `o resultado lido pelo modelo não pode ter URL: ${texto}`);
  assert(!texto.includes(ORDEM.share_token));
});

Deno.test("falha no envio: apaga o arquivo e devolve o link interno, não o público", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ error: "Connection Closed" }), { status: 502 }) });
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertStringIncludes(r.error, "Connection Closed");
  assertEquals(r.link_interno, `https://erp.example/service-orders/${ORDEM.id}`);
  assert(!JSON.stringify(r).includes("/view/"));
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
});

for (const [nome, resposta] of [
  ["503 do /api/pdf", () => new Response("desligado", { status: 503 })],
  ["HTML no lugar do PDF", () => new Response("<html>erro</html>", { headers: { "content-type": "text/html" } })],
  ["PDF vazio", () => new Response(new Uint8Array(100), { headers: { "content-type": "application/pdf" } })],
] as Array<[string, () => Response]>) {
  Deno.test(`${nome}: nada é guardado nem enviado`, async () => {
    const amb = montarAmbiente({ respostaPdf: resposta });
    const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
    assert(r.error);
    assert(r.link_interno);
    assertEquals(amb.chamadas.upload.length, 0);
    assertEquals(amb.chamadas.envio.length, 0);
  });
}

Deno.test("pedido repetido em 2 minutos: a edge deduplica e a tool avisa sem fingir novo envio", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertEquals(r.deduplicated, true);
  assertStringIncludes(r.aviso, "não reenviei");
  assert(amb.chamadas.envio[0].corpo.dedupe_key.startsWith("agente-pdf:"));
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
});

// ─── Localizar o documento ───────────────────────────────────────────────────────────────
Deno.test("interpreta os jeitos de dizer o número", () => {
  assertEquals(interpretarDocumento("ORÇ-00086"), { digitos: "86", prefixo: "ORÇ" });
  assertEquals(interpretarDocumento("orc 86"), { digitos: "86", prefixo: "ORÇ" });
  assertEquals(interpretarDocumento("orçamento 86"), { digitos: "86", prefixo: "ORÇ" });
  assertEquals(interpretarDocumento("OS-00075"), { digitos: "75", prefixo: "OS" });
  assertEquals(interpretarDocumento("os 75"), { digitos: "75", prefixo: "OS" });
  assertEquals(interpretarDocumento("86"), { digitos: "86", prefixo: null });
  assertEquals(interpretarDocumento("86", "os"), { digitos: "86", prefixo: "OS" });
  // O que está escrito vence o tipo.
  assertEquals(interpretarDocumento("OS-75", "orcamento"), { digitos: "75", prefixo: "OS" });
  assertEquals(interpretarDocumento("sem número"), null);
});

Deno.test("número solto que existe como ORÇ e OS: pergunta em vez de escolher", async () => {
  const amb = montarAmbiente();
  const r: any = await localizarOrdem(amb.ctx().admin, "86");
  assertEquals(r.opcoes, ["ORÇ-00086", "OS-00086"]);
});

Deno.test("número solto com tipo resolve sozinho", async () => {
  const amb = montarAmbiente();
  const r: any = await localizarOrdem(amb.ctx().admin, "86", "orcamento");
  assertEquals(r.ordem.service_order_number, "ORÇ-00086");
});

Deno.test("número que não existe diz o que procurou", async () => {
  const amb = montarAmbiente();
  const r: any = await localizarOrdem(amb.ctx().admin, "ORÇ-00999");
  assertStringIncludes(r.erro, "ORÇ-00999");
});

Deno.test("'ultimo' pega o mais recente não cancelado, do tipo pedido", async () => {
  const cancelado = { ...ORDEM, id: "44444444-4444-4444-8444-444444444444", service_order_number: "ORÇ-00090", status: "cancelled", created_at: "2026-09-26T00:00:00.000Z" };
  const expirado = { ...ORDEM, id: "55555555-5555-4555-8555-555555555555", service_order_number: "ORÇ-00089", created_at: "2026-09-25T20:00:00.000Z" };
  const amb = montarAmbiente({ ordens: [ORDEM, OS, cancelado, expirado] });
  const r: any = await localizarOrdem(amb.ctx().admin, "o último", "orcamento");
  assertEquals(r.ordem.service_order_number, "ORÇ-00089");
  const r2: any = await localizarOrdem(amb.ctx().admin, "ultimo", "os");
  assertEquals(r2.ordem.service_order_number, "OS-00086");
});

Deno.test("nome do arquivo cabe no limite do whatsapp-send sem perder o .pdf", () => {
  const longo = `Orcamento_ORC-00086_${"Nome-Muito-Comprido-".repeat(4)}_${"Embarcacao-Com-Nome-Grande-".repeat(3)}.pdf`;
  const cortado = limitarNomeDoArquivo(longo);
  assert(cortado.length <= 120, `${cortado.length}`);
  assert(cortado.endsWith(".pdf"));
  assert(!/[-_]\.pdf$/.test(cortado));
  assertEquals(limitarNomeDoArquivo("Orcamento_ORC-00086.pdf"), "Orcamento_ORC-00086.pdf");
});

// ─── Achados da revisão adversarial de 25/09/2026 ────────────────────────────────────────
Deno.test("dois usuários: cada um recebe no próprio telefone, mesmo não sendo o primeiro da tabela", async () => {
  for (const [userId, telefone] of [["u1", "5547999159654"], ["u2", "5547911112222"]]) {
    const amb = montarAmbiente({ userId });
    await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
    assertEquals(amb.chamadas.envio[0].corpo.phone, telefone);
  }
});

Deno.test("a chave anti-duplicado inclui o destinatário: o segundo usuário não ouve 'já mandei'", async () => {
  const chaves: string[] = [];
  for (const userId of ["u1", "u2", "u1"]) {
    const amb = montarAmbiente({ userId });
    await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
    chaves.push(amb.chamadas.envio[0].corpo.dedupe_key);
  }
  assert(chaves[0] !== chaves[1], "admin e financeiro pedindo o mesmo PDF não podem compartilhar a chave");
  assertEquals(chaves[0], chaves[2], "o mesmo usuário pedindo de novo na janela usa a mesma chave");
});

Deno.test("envio sem resposta (tempo esgotado): a tool libera a chave para o próximo pedido", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => { throw new DOMException("cortado", "AbortError"); } });
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assert(r.error);
  assertEquals(amb.chamadas.liberadas, [amb.chamadas.envio[0].corpo.dedupe_key]);
  assertEquals(amb.chamadas.removidos, amb.chamadas.upload);
});

Deno.test("envio que falhou na Evolution também libera a chave", async () => {
  const amb = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ error: "Connection Closed" }), { status: 502 }) });
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertEquals(amb.chamadas.liberadas, [amb.chamadas.envio[0].corpo.dedupe_key]);
});

Deno.test("envio que deu certo NÃO libera a chave", async () => {
  const amb = montarAmbiente();
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertEquals(amb.chamadas.liberadas, []);
});

Deno.test("sempre a via do cliente, com valores, mesmo com padrão gravado pedindo a via de execução", async () => {
  const padrao = JSON.stringify({ hideFinancials: true, showServicePrices: true, showPartsPrices: true });
  const amb = montarAmbiente({ settings: { pdf_options_service_order: padrao, pdf_options_quote: padrao } });
  await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "OS-00086" }, amb.ctx()));
  const corpo = await amb.chamadas.pdf[0].json();
  assert(!corpo.html.includes("Via de Execução"), "saiu a via do técnico");
  assertStringIncludes(corpo.html, "VALOR TOTAL");
  assert(!corpo.filename.includes("Via-Execucao"));
});

Deno.test("modo de teste do WhatsApp ligado: a tool não diz que chegou para quem pediu", async () => {
  const amb = montarAmbiente({ settings: { wa_test_mode: "true" } });
  const r: any = await comFetch(amb.fetchFalso as any, () => tool.execute({ documento: "ORÇ-00086" }, amb.ctx()));
  assertStringIncludes(r.enviado_para, "TESTE");
  assertStringIncludes(r.observacao, "número de teste");
});
