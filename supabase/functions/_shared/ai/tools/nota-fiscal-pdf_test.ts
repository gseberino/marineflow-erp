// PDF da nota fiscal pelo WhatsApp (07/10/2026). O que estes testes protegem:
//  1. A NOTA CERTA: pela OS, pelo número ou pelo cliente (a mais recente); OS com NF-e e NFS-e é
//     pergunta; só autorizada de produção, com o PDF arquivado.
//  2. O DESTINO: para si, o telefone de quem pediu (cadastro); ao cliente, o WhatsApp do cadastro
//     do cliente DA NOTA — nunca um argumento. Opt-out e telefone trocado depois do pedido barram.
//  3. O ARQUIVO: a URL assinada do PDF arquivado em fiscal-xml (o mesmo do botão PDF da tela), com
//     context 'nfe' ao cliente e nunca 'quote'.
//  4. LEITURA QUE FALHA não vira "não achei" — e nada sai.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { hashCurto } from "../../whatsapp/idempotencia.ts";
import { localizarNota, notaFiscalPdfTools, resumirEnvioDaNota, tipoDaNotaDito } from "./nota-fiscal-pdf.ts";
import { NEVER_AUTONOMOUS } from "../autonomy-policy.ts";

type Linha = Record<string, unknown>;

/** Banco de mentira que filtra de verdade; tabelas em `falham` respondem erro na leitura. */
function bancoFalso(tabelas: Record<string, Linha[]>, falham: string[] = []) {
  const escritas: Array<{ tabela: string; op: string; valores: unknown }> = [];
  const assinadas: string[] = [];
  const from = (tabela: string) => {
    let op = "select";
    let valores: unknown = null;
    const filtros: Array<(l: Linha) => boolean> = [];
    let ordem: [string, boolean] | null = null;
    let limite: number | null = null;
    let unico = false;
    const run = () => {
      const linhas = (tabelas[tabela] ??= []);
      if (op === "select") {
        if (falham.includes(tabela)) return { data: null, error: { message: `falha em ${tabela}` } };
        let r = linhas.filter((l) => filtros.every((f) => f(l)));
        if (ordem) {
          const [c, asc] = ordem;
          r = [...r].sort((a, b) => String(a[c] ?? "").localeCompare(String(b[c] ?? "")) * (asc ? 1 : -1));
        }
        if (limite != null) r = r.slice(0, limite);
        return { data: unico ? (r[0] ?? null) : r, error: null };
      }
      escritas.push({ tabela, op, valores });
      if (op === "insert") {
        const arr = (Array.isArray(valores) ? valores : [valores]) as Linha[];
        linhas.push(...arr);
        return { data: unico ? arr[0] : arr, error: null };
      }
      if (op === "delete") {
        const fora = linhas.filter((l) => filtros.every((f) => f(l)));
        tabelas[tabela] = linhas.filter((l) => !fora.includes(l));
        return { data: fora, error: null };
      }
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q,
      insert: (v: unknown) => { op = "insert"; valores = v; return q; },
      update: (v: unknown) => { op = "update"; valores = v; return q; },
      delete: () => { op = "delete"; return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: (c: string, o?: { ascending?: boolean }) => { ordem = [c, o?.ascending !== false]; return q; },
      limit: (n: number) => { limite = n; return q; },
      single: () => { unico = true; return q; },
      maybeSingle: () => { unico = true; return q; },
      then: (ok: (v: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(run()).then(ok, erro),
    };
    return q;
  };
  const admin = {
    from,
    storage: {
      from: (bucket: string) => ({
        createSignedUrl: (caminho: string, s: number) => {
          assinadas.push(`${bucket}/${caminho}`);
          return Promise.resolve({ data: { signedUrl: `https://sb.example/sign/${bucket}/${caminho}?exp=${s}` }, error: null });
        },
      }),
    },
  };
  return { admin, escritas, assinadas, tabelas };
}

const OS98 = { id: "11111111-1111-4111-8111-111111111198", service_order_number: "OS-00098", status: "completed", share_token: "t", updated_at: null };
const OS105 = { id: "11111111-1111-4111-8111-111111111105", service_order_number: "OS-00105", status: "completed", share_token: "t", updated_at: null };

const nota = (x: Linha) => ({
  document_type: "nfe", origin_type: "service_order", origin_id: OS98.id, client_id: "c-nelson", environment: "producao",
  series: 2, status: "authorized", pdf_storage_path: "producao/nfe/x.pdf", request_payload: { recipient: { name: "NELSON SILVA" } },
  authorized_at: "2026-09-01T12:00:00Z", created_at: "2026-09-01T12:00:00Z", ...x,
});

function ambiente(extra: Record<string, Linha[]> = {}, falham: string[] = []) {
  return bancoFalso({
    service_orders: [OS98, OS105],
    issued_fiscal_documents: [
      nota({ id: "n-nfe-98", number: 29 }),
      nota({ id: "n-nfse-98", document_type: "nfse", series: 1, number: 5, pdf_storage_path: "producao/nfse/y.pdf", authorized_at: "2026-09-02T12:00:00Z", created_at: "2026-09-02T12:00:00Z" }),
      nota({ id: "22222222-2222-4222-8222-222222222105", number: 30, origin_id: OS105.id, client_id: "c-miguel", request_payload: { recipient: { name: "MIGUEL SOUZA" } }, created_at: "2026-09-10T12:00:00Z", authorized_at: "2026-09-10T12:00:00Z" }),
      nota({ id: "n-miguel-velha", number: 20, origin_id: null, origin_type: "manual", client_id: "c-miguel", created_at: "2026-08-10T12:00:00Z", authorized_at: "2026-08-10T12:00:00Z" }),
      nota({ id: "n-cancelada", number: 31, status: "cancelled", origin_id: null, origin_type: "manual", client_id: "c-ana", created_at: "2026-09-11T12:00:00Z" }),
      nota({ id: "n-homolog", number: 1, environment: "homologacao", origin_id: null, origin_type: "manual", client_id: "c-ana", created_at: "2026-07-01T12:00:00Z" }),
    ],
    clients: [
      { id: "c-nelson", name: "NELSON SILVA", display_name: null, whatsapp: "(47) 99915-9654", phone: null, opt_out_whatsapp: false },
      { id: "c-miguel", name: "MIGUEL SOUZA", display_name: "Miguel", whatsapp: "47988887777", phone: null, opt_out_whatsapp: false },
      { id: "c-ana", name: "ANA LIMA", display_name: null, whatsapp: "47977776666", phone: null, opt_out_whatsapp: true },
    ],
    app_users: [{ id: "u-admin", phone_normalized: "5547911112222" }],
    ...extra,
  }, falham);
}

const ONZE_DA_MANHA = new Date("2026-10-07T14:00:00.000Z");

async function rodar(nome: string, args: Record<string, unknown>, amb = ambiente(), role = "admin", settings: Record<string, string> = {}) {
  const envios: Array<{ corpo: Record<string, unknown> }> = [];
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = (async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (!url.endsWith("/functions/v1/whatsapp-send")) throw new Error(`fetch inesperado: ${url}`);
    envios.push({ corpo: JSON.parse(String(init?.body)) });
    return new Response(JSON.stringify({ success: true, messageId: "m1" }));
  }) as typeof fetch;
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    const tool = notaFiscalPdfTools.find((t) => t.name === nome)!;
    const ctx = { sb: amb.admin, admin: amb.admin, userId: "u-admin", userRole: role, jwt: "", appOrigin: "", settings } as never;
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute(args, ctx) as any;
    return { r, envios, amb };
  } finally {
    relogio.restore();
    globalThis.fetch = original;
  }
}

Deno.test("tipo dito: 'nota de serviço' é NFS-e; DANFE/produto é NF-e", () => {
  assertEquals(tipoDaNotaDito("nota de serviço"), "nfse");
  assertEquals(tipoDaNotaDito("NFS-e"), "nfse");
  assertEquals(tipoDaNotaDito("danfe"), "nfe");
  assertEquals(tipoDaNotaDito(""), null);
});

Deno.test("para si: OS com NF-e e NFS-e sem tipo é pergunta; com tipo, o PDF arquivado vai para quem pediu", async () => {
  const pergunta = await rodar("send_fiscal_pdf_to_self", { os: "OS-00098" });
  assert(pergunta.r.error, JSON.stringify(pergunta.r));
  assertEquals(pergunta.r.opcoes.sort(), ["NF-e 2/29", "NFS-e 1/5"]);
  assertEquals(pergunta.envios.length, 0);

  const { r, envios, amb } = await rodar("send_fiscal_pdf_to_self", { os: "98", tipo: "nfse" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.nota, "NFS-e 1/5");
  assertEquals(envios.length, 1);
  const corpo = envios[0].corpo;
  assertEquals(corpo.phone, "5547911112222"); // o de quem pediu, do cadastro
  assertEquals(corpo.kind, "document");
  assertEquals(corpo.context, "agente_nota_propria");
  assertEquals(amb.assinadas, ["fiscal-xml/producao/nfse/y.pdf"]);
  assertStringIncludes(String(corpo.document_url), "fiscal-xml/producao/nfse/y.pdf");
  assertEquals(corpo.service_order_id, undefined);
});

Deno.test("ao cliente: 'a nota de serviço do Nelson com a frase' — WhatsApp do cadastro, frase na legenda, context nfe", async () => {
  const { r, envios, amb } = await rodar("send_fiscal_pdf_to_client", { cliente: "Nelson", tipo: "nfse", custom_message: "segue a nota do serviço de ontem" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.nota, "NFS-e 1/5");
  assertEquals(envios.length, 1);
  assertEquals(envios[0].corpo.phone, "5547999159654");
  assertEquals(envios[0].corpo.context, "nfe");
  assertEquals(envios[0].corpo.document_caption, "segue a nota do serviço de ontem");
  // Registro do envio (cadência e aprendizado).
  assert(amb.escritas.some((e) => e.tabela === "ai_comms_log" && (e.valores as Linha).status === "sent"));
});

Deno.test("ao cliente: 'a última nota do Miguel' é a mais recente dele; sem frase vai o texto da tela", async () => {
  const { r, envios } = await rodar("send_fiscal_pdf_to_client", { cliente: "Miguel" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.nota, "NF-e 2/30");
  assertEquals(r.os, "OS-00105");
  assertEquals(envios[0].corpo.document_caption, "Olá Miguel! Segue em anexo o DANFE da NF-e 2/30. Qualquer dúvida, estamos à disposição.");
});

Deno.test("recusas: cancelada, homologação, opt-out, cargo, frase longa — e nada sai", async () => {
  const cancelada = await rodar("send_fiscal_pdf_to_client", { nota: "31" });
  assertStringIncludes(cancelada.r.error, "cancelada");
  const homolog = await rodar("send_fiscal_pdf_to_self", { nota: "2/1" });
  assertStringIncludes(homolog.r.error, "HOMOLOGAÇÃO");
  const vendedor = await rodar("send_fiscal_pdf_to_client", { os: "OS-00105" }, ambiente(), "seller");
  assertStringIncludes(vendedor.r.error, "administrador");
  const financeiro = await rodar("send_fiscal_pdf_to_self", { os: "OS-00105" }, ambiente(), "financial");
  assertStringIncludes(financeiro.r.error, "administrador");
  const longa = await rodar("send_fiscal_pdf_to_client", { os: "OS-00105", custom_message: "x".repeat(1001) });
  assertStringIncludes(longa.r.error, "1000");
  // Opt-out: a nota da Ana existe e está autorizada, mas ela pediu para não receber.
  const amb = ambiente();
  amb.tabelas.issued_fiscal_documents.push(nota({ id: "n-ana", number: 40, origin_id: null, origin_type: "manual", client_id: "c-ana" }));
  const optout = await rodar("send_fiscal_pdf_to_client", { nota: "40" }, amb);
  assertStringIncludes(optout.r.error, "opt-out");
  for (const x of [cancelada, homolog, vendedor, financeiro, longa, optout]) assertEquals(x.envios.length, 0);
});

Deno.test("sem PDF arquivado: diz o caminho da tela, não manda", async () => {
  const amb = ambiente();
  (amb.tabelas.issued_fiscal_documents.find((n) => n.id === "22222222-2222-4222-8222-222222222105")!).pdf_storage_path = null;
  const { r, envios } = await rodar("send_fiscal_pdf_to_client", { os: "OS-00105" }, amb);
  assertStringIncludes(r.error, "Atualizar situação na SEFAZ");
  assertEquals(envios.length, 0);
});

Deno.test("leitura que falha não vira 'não achei': a consulta das notas falhou, e nada sai", async () => {
  const { r, envios } = await rodar("send_fiscal_pdf_to_client", { os: "OS-00105" }, ambiente({}, ["issued_fiscal_documents"]));
  assertStringIncludes(r.error, "consulta das notas falhou");
  assertEquals(envios.length, 0);
  const porCliente = await rodar("send_fiscal_pdf_to_self", { cliente: "Miguel" }, ambiente({}, ["clients"]));
  assertStringIncludes(porCliente.r.error, "consulta dos clientes falhou");
});

Deno.test("retrato: o 'sim' foi sobre ESTA nota e ESTE telefone — telefone trocado depois do pedido não envia", async () => {
  const amb = ambiente();
  const aprovado = { _retrato: { nota_id: "22222222-2222-4222-8222-222222222105", telefone: hashCurto("5547900000000") } };
  const { r, envios } = await rodar("send_fiscal_pdf_to_client", { cliente: "Miguel", ...aprovado }, amb);
  assertStringIncludes(r.error, "mudou");
  assertEquals(envios.length, 0);
  // E a nota é a do retrato, mesmo que "a mais recente" tenha mudado até o "sim".
  amb.tabelas.issued_fiscal_documents.push(nota({ id: "n-nova", number: 99, client_id: "c-miguel", origin_id: null, origin_type: "manual", created_at: "2026-10-01T12:00:00Z", authorized_at: "2026-10-01T12:00:00Z" }));
  const ok = await rodar("send_fiscal_pdf_to_client", { cliente: "Miguel", _retrato: { nota_id: "22222222-2222-4222-8222-222222222105", telefone: hashCurto("5547988887777") } }, amb);
  assertEquals(ok.r.ok, true, JSON.stringify(ok.r));
  assertEquals(ok.r.nota, "NF-e 2/30");
});

Deno.test("resumo da confirmação: nota, OS, cliente e o telefone INTEIRO; nota que não serve vira uma linha ⚠️", async () => {
  const amb = ambiente();
  const resumo = await resumirEnvioDaNota(amb.admin, { os: "OS-00105" });
  assertStringIncludes(resumo, "NF-e 2/30");
  assertStringIncludes(resumo, "OS-00105");
  assertStringIncludes(resumo, "MIGUEL SOUZA");
  assertStringIncludes(resumo, "+55 (47) 98888-7777");
  const ruim = await resumirEnvioDaNota(amb.admin, { nota: "31" });
  assert(ruim.startsWith("⚠️") && !ruim.includes("\n"), ruim);
});

Deno.test("nome parecido não identifica: 'Silva' serve a mais de um cliente com nota → pergunta", async () => {
  const amb = ambiente();
  amb.tabelas.clients.push({ id: "c-outro", name: "JOAO SILVA", display_name: null, whatsapp: "47966665555" });
  amb.tabelas.issued_fiscal_documents.push(nota({ id: "n-joao", number: 41, client_id: "c-outro", origin_id: null, origin_type: "manual" }));
  const r = await localizarNota(amb.admin, { cliente: "Silva" });
  assert("erro" in r && r.opcoes?.length === 2, JSON.stringify(r));
});

Deno.test("ao cliente nunca roda sozinho, mesmo com autonomia gravada", () => {
  assert(NEVER_AUTONOMOUS.has("send_fiscal_pdf_to_client"));
  assertEquals(notaFiscalPdfTools.find((t) => t.name === "send_fiscal_pdf_to_client")!.risk, "high");
});
