// Retorno F4 (P13): o leitor do parceiro no whatsapp-webhook, com banco falso (contrato C-LER).
//
// O que estes testes protegem:
//  · lerNoParceiro: consumida só com {consumida: true} do banco; função ausente (42883, PGRST202) é silêncio e o caminho
//    de hoje; outro erro, um aviso só com o código; exceção e resposta estranha nunca lançam; sem id da mensagem, nem chama;
//    a RPC recebe só o id da mensagem (nunca o texto nem o telefone);
//  · index.ts (lido como texto): o leitor vem logo depois de gravar a recebida, antes de manejarRespostaAutomatica,
//    respostaDaEquipe e respostaDoCliente; a consumida pula todos os leitores de baixo; o callback do abrirNoRetorno soma
//    doParceiro.consumida;
//  · o handler inteiro, com o banco e as funções num fetch falso: consumida = nenhum leitor roda e o retorno_abrir recebe
//    p_consumida verdadeiro; função ausente ou erro = o caminho de hoje; o eco nunca chama o leitor.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerNoParceiro, RPC_LER } from "./parceiro.ts";

const SEGREDO = "segredo-de-teste-nao-real";
const URL_FN = "https://exemplo.supabase.co/functions/v1/whatsapp-webhook";
Deno.env.set("EVOLUTION_WEBHOOK_TOKEN", SEGREDO);
// Valores de fachada: todo I/O do handler passa pelo fetch falso abaixo.
Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-fachada");
Deno.env.set("EVOLUTION_API_URL", "https://evo.exemplo.test");
Deno.env.set("EVOLUTION_API_KEY", "chave-de-fachada");
Deno.env.set("EVOLUTION_INSTANCE", "hbr-local");
Deno.env.set("AI_INTERNAL_SECRET", "interno-de-fachada");
const { handler } = await import("./index.ts");

// Número e id inventados (7391): nada aqui é de cliente real.
const FONE = "5547900007391";
const MSG = "11111111-0000-4000-8000-000000007391";
const CLIENTE = "aaaaaaaa-0000-4000-8000-000000007391";

type Chamada = { nome: string; args: Record<string, unknown> };

/** Banco falso: só rpc, que registra a chamada e devolve o que o teste mandar ({data, error}, como o supabase-js). */
function bancoFalso(resposta: (nome: string, args: Record<string, unknown>) => unknown) {
  const chamadas: Chamada[] = [];
  return {
    chamadas,
    rpc(nome: string, args: Record<string, unknown>) {
      chamadas.push({ nome, args });
      return Promise.resolve(resposta(nome, args));
    },
  };
}

/** Roda `fn` guardando os console.warn (o leitor avisa só com o código do erro). */
async function comAvisos<T>(fn: () => Promise<T>): Promise<{ valor: T; avisos: string[] }> {
  const original = console.warn;
  const avisos: string[] = [];
  console.warn = (...a: unknown[]) => {
    avisos.push(a.map(String).join(" "));
  };
  try {
    return { valor: await fn(), avisos };
  } finally {
    console.warn = original;
  }
}

// ─── lerNoParceiro (C-LER) ─────────────────────────────────────────────────────────────────────────────────────

Deno.test("lerNoParceiro: o nome da RPC é o do contrato, e ela recebe só o id da mensagem", async () => {
  assertEquals(RPC_LER, "parceiro_ler_mensagem");
  const banco = bancoFalso(() => ({ data: { consumida: true, acao: "patio", motivo: "cartao" }, error: null }));
  const r = await lerNoParceiro(banco, { msgId: MSG });
  assertEquals(banco.chamadas, [{ nome: "parceiro_ler_mensagem", args: { p_msg: MSG } }]);
  assertEquals(r, { consumida: true, acao: "patio" });
});

Deno.test("lerNoParceiro: consumida só com o booleano verdadeiro (veto, retido, pátio, pausar, retomar)", async () => {
  for (const acao of ["veto", "retido", "patio", "pausar", "retomar"]) {
    const banco = bancoFalso(() => ({ data: { consumida: true, acao, motivo: "x" }, error: null }));
    assertEquals(await lerNoParceiro(banco, { msgId: MSG }), { consumida: true, acao }, acao);
  }
  for (const data of [{ consumida: false, acao: "nada" }, { consumida: "true" }, { consumida: 1 }, null, "texto", [true], {}]) {
    const banco = bancoFalso(() => ({ data, error: null }));
    const r = await lerNoParceiro(banco, { msgId: MSG });
    assertEquals(r.consumida, false, JSON.stringify(data));
  }
});

Deno.test("lerNoParceiro: a ação que não é texto curto não volta (nunca um texto do banco no log nem adiante)", async () => {
  const banco = bancoFalso(() => ({ data: { consumida: true, acao: "uma frase qualquer com espaço" }, error: null }));
  assertEquals(await lerNoParceiro(banco, { msgId: MSG }), { consumida: true });
});

Deno.test("lerNoParceiro: função ausente (42883, PGRST202) = silêncio e não consumida", async () => {
  for (const code of ["42883", "PGRST202"]) {
    const banco = bancoFalso(() => ({ data: null, error: { code, message: "sem a função" } }));
    const { valor, avisos } = await comAvisos(() => lerNoParceiro(banco, { msgId: MSG }));
    assertEquals(valor, { consumida: false }, code);
    assertEquals(avisos, [], code);
  }
});

Deno.test("lerNoParceiro: outro erro = aviso só com o código (nunca o texto da mensagem nem o telefone)", async () => {
  const banco = bancoFalso(() => ({ data: null, error: { code: "57014", message: `statement timeout ${FONE} NÃO MP` } }));
  const { valor, avisos } = await comAvisos(() => lerNoParceiro(banco, { msgId: MSG }));
  assertEquals(valor, { consumida: false });
  assertEquals(avisos.length, 1);
  assert(avisos[0].includes("57014"), avisos[0]);
  assert(!avisos[0].includes(FONE) && !avisos[0].includes("NÃO MP"), avisos[0]);
});

Deno.test("lerNoParceiro: rpc que lança, banco sem rpc e erro sem código não derrubam nada", async () => {
  const lanca = { rpc: () => Promise.reject(new TypeError("rede caiu " + FONE)) };
  const a = await comAvisos(() => lerNoParceiro(lanca, { msgId: MSG }));
  assertEquals(a.valor, { consumida: false });
  assert(a.avisos.every((x) => !x.includes(FONE)), a.avisos.join("|"));
  const semRpc = await comAvisos(() => lerNoParceiro({}, { msgId: MSG }));
  assertEquals(semRpc.valor, { consumida: false });
  const semCodigo = bancoFalso(() => ({ data: null, error: { message: "algo" } }));
  const b = await comAvisos(() => lerNoParceiro(semCodigo, { msgId: MSG }));
  assertEquals(b.valor, { consumida: false });
  assertEquals(b.avisos.length, 1);
});

Deno.test("lerNoParceiro: sem id da mensagem, nem chama", async () => {
  for (const msgId of ["", undefined, null]) {
    const banco = bancoFalso(() => ({ data: { consumida: true }, error: null }));
    // deno-lint-ignore no-explicit-any
    assertEquals(await lerNoParceiro(banco, { msgId: msgId as any }), { consumida: false });
    assertEquals(banco.chamadas.length, 0);
  }
});

Deno.test("parceiro.ts não importa nada congelado (_shared/ai/, _shared/agenda/)", async () => {
  const fonte = await Deno.readTextFile(new URL("./parceiro.ts", import.meta.url));
  const imports = [...fonte.matchAll(/^\s*import\s[^;]*?from\s+["']([^"']+)["']/gm)].map((m) => m[1]);
  assertEquals(imports.filter((i) => i.includes("_shared/ai/") || i.includes("_shared/agenda/")), []);
});

// ─── index.ts: a ordem dos leitores, lida como texto ──────────────────────────────────────────────────────────

const fonteDoWebhook = async () => (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");

Deno.test("index.ts: o leitor do parceiro vem logo depois de gravar a recebida e antes dos outros leitores", async () => {
  const fonte = await fonteDoWebhook();
  const gravou = fonte.indexOf('if (insErr) return jr({ error: "db_error", details: insErr.message }, 500);');
  const leitor = fonte.indexOf(
    "const doParceiro = !event.fromMe ? await lerNoParceiro(admin, { msgId: msg?.id }) : { consumida: false };",
  );
  const bloco = fonte.indexOf("if (!event.fromMe && body) {");
  const pula = fonte.indexOf("if (!doParceiro.consumida) {", bloco);
  const manejo = fonte.indexOf('manejarRespostaAutomatica(admin, "clients", clientId, body, ident.usar).catch(() => {});');
  const equipe = fonte.indexOf("const daEquipe = await respostaDaEquipe(admin,");
  const cliente = fonte.indexOf("const doCliente = !daEquipe &&");
  const acompanhar = fonte.indexOf('admin.rpc("followup_registrar_resposta"');
  assert(gravou > 0 && leitor > gravou, `${gravou} ${leitor}`);
  assert(bloco > leitor && pula > bloco, `${bloco} ${pula}`);
  for (const [nome, pos] of [["manejo", manejo], ["equipe", equipe], ["cliente", cliente], ["acompanhar", acompanhar]] as const) {
    assert(pos > pula, `${nome} (${pos}) depois do if (!doParceiro.consumida) (${pula})`);
  }
  assertEquals(fonte.split("lerNoParceiro(").length - 1, 1, "uma leitura só");
  assert(fonte.includes('import { lerNoParceiro } from "./parceiro.ts";'));
});

Deno.test("index.ts: a consumida pelo parceiro pula os leitores, e o retorno_abrir ainda registra com ela", async () => {
  const fonte = await fonteDoWebhook();
  const bloco = fonte.slice(fonte.indexOf("if (!event.fromMe && body) {"), fonte.indexOf("if (leadId) {"));
  const pula = bloco.indexOf("if (!doParceiro.consumida) {");
  const revisao = bloco.indexOf('pRevisao = admin.rpc("registrar_resposta_da_revisao"');
  const guarda = bloco.indexOf("if (msg?.id) {", revisao);
  // o if (!doParceiro.consumida) fecha antes do retorno_abrir: o caso abre (ou estende) mesmo com a mensagem consumida
  const fecha = bloco.lastIndexOf("\n      }\n", guarda);
  assert(pula > 0 && revisao > pula && fecha > revisao && guarda > fecha, `${pula} ${revisao} ${fecha} ${guarda}`);
  assert(
    bloco.includes(
      "consumida: (v) => doParceiro.consumida || consumidaPelosLeitores({ confirmacao: v[0], conferencia: v[1], revisao: v[2] }),",
    ),
  );
  assertEquals(fonte.includes("await abrirNoRetorno("), false);
});

// ─── O handler inteiro, com o banco e as funções num fetch falso ───────────────────────────────────────────────

type ChamadaHttp = { metodo: string; caminho: string; corpo?: Record<string, unknown> };

function webhookFalso(op: { parceiro?: unknown; parceiroStatus?: number } = {}) {
  const chamadas: ChamadaHttp[] = [];
  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });
  const f = async (entrada: Request | URL | string, init?: RequestInit): Promise<Response> => {
    const req = new Request(entrada, init);
    const u = new URL(req.url);
    const texto = req.method === "GET" ? "" : await req.text().catch(() => "");
    let corpo: Record<string, unknown> | undefined;
    try {
      corpo = texto ? JSON.parse(texto) : undefined;
    } catch { /* não é JSON */ }
    chamadas.push({ metodo: req.method, caminho: u.pathname, corpo });
    const p = u.pathname;
    if (p === "/rest/v1/whatsapp_messages") return req.method === "GET" ? json([]) : json({ id: MSG }, 201);
    if (p === "/rest/v1/app_users") return json([]); // o número não é login
    if (p === "/rest/v1/rpc/retorno_identificar") {
      return json({ nova: true, papel: "cliente", client_id: CLIENTE, clientes: [CLIENTE] });
    }
    if (p === "/rest/v1/rpc/parceiro_ler_mensagem") {
      if (op.parceiro === undefined) return json({ code: "PGRST202", message: "sem a função" }, 404);
      return json(op.parceiro, op.parceiroStatus ?? 200);
    }
    if (p === "/rest/v1/clients") return json([]);
    if (p === "/rest/v1/whatsapp_leads") return json([]);
    if (p === "/rest/v1/suppliers") return json([]);
    if (p === "/rest/v1/ai_comms_log" || p === "/rest/v1/app_settings") return json([]);
    if (p === "/rest/v1/rpc/followup_registrar_resposta") return json(null);
    if (p === "/rest/v1/rpc/agenda_resposta_da_equipe") return json({ consumiu: false });
    if (p === "/rest/v1/rpc/agenda_resposta_do_cliente") return json({ consumiu: false, modo: "sombra" });
    if (p === "/rest/v1/rpc/registrar_confirmacao_do_cliente") return json({ confirmou: false });
    if (p === "/rest/v1/rpc/registrar_conferencia_do_freelancer") return json({ conferiu: false });
    if (p === "/rest/v1/rpc/registrar_resposta_da_revisao") return json({ registrou: false });
    if (p === "/rest/v1/rpc/retorno_abrir") return json({ ok: true, acao: "nova", nivel: "nada" });
    return json({ inesperado: p }, 500);
  };
  const de = (caminho: string, metodo?: string) =>
    chamadas.filter((c) => c.caminho === caminho && (!metodo || c.metodo === metodo));
  return { f, chamadas, de };
}

function payloadDe(texto: string, waId: string, fromMe = false) {
  return {
    event: "messages.upsert",
    data: {
      key: { id: waId, remoteJid: `${FONE}@s.whatsapp.net`, fromMe },
      pushName: "Contato de Teste",
      message: { conversation: texto },
      messageTimestamp: 1762210800,
    },
  };
}

async function rodarWebhook(falso: ReturnType<typeof webhookFalso>, payload: unknown) {
  const g = globalThis as unknown as { fetch: typeof fetch; EdgeRuntime?: unknown };
  const fetchOriginal = g.fetch;
  const runtimeOriginal = g.EdgeRuntime;
  const fundo: Promise<unknown>[] = [];
  g.fetch = falso.f as typeof fetch;
  g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => fundo.push(p) };
  try {
    const res = await handler(new Request(`${URL_FN}?token=${SEGREDO}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    }));
    assertEquals(res.status, 200);
    await Promise.all(fundo);
    await new Promise((ok) => setTimeout(ok, 30));
  } finally {
    g.fetch = fetchOriginal;
    g.EdgeRuntime = runtimeOriginal;
  }
}

const LEITORES = [
  "/rest/v1/rpc/followup_registrar_resposta",
  "/rest/v1/rpc/agenda_resposta_da_equipe",
  "/rest/v1/rpc/agenda_resposta_do_cliente",
  "/rest/v1/rpc/registrar_confirmacao_do_cliente",
  "/rest/v1/rpc/registrar_conferencia_do_freelancer",
  "/rest/v1/rpc/registrar_resposta_da_revisao",
];

Deno.test("handler: consumida pelo parceiro = nenhum outro leitor vê a mensagem, e o retorno_abrir recebe p_consumida true", async () => {
  const falso = webhookFalso({ parceiro: { consumida: true, acao: "veto", motivo: "veto" } });
  await comAvisos(() => rodarWebhook(falso, payloadDe("NÃO MP", "WAID-F4-P13-1")));
  assertEquals(falso.de("/rest/v1/rpc/parceiro_ler_mensagem").map((c) => c.corpo), [{ p_msg: MSG }]);
  for (const leitor of LEITORES) assertEquals(falso.de(leitor).length, 0, leitor);
  // o opt-out de hoje (manejarRespostaAutomatica grava em clients) também não roda; o frescor do cliente, sim (como hoje)
  assertEquals(falso.de("/rest/v1/clients", "PATCH").filter((c) => c.corpo && "opt_out_whatsapp" in c.corpo).length, 0);
  assertEquals(falso.de("/rest/v1/ai_comms_log").length, 0, "o manejo da resposta não rodou");
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").map((c) => c.corpo), [{ p_msg: MSG, p_consumida: true }]);
  // o leitor do parceiro vem antes do retorno_abrir
  const caminhos = falso.chamadas.map((c) => c.caminho);
  assert(caminhos.indexOf("/rest/v1/rpc/parceiro_ler_mensagem") < caminhos.indexOf("/rest/v1/rpc/retorno_abrir"));
});

Deno.test("handler: não consumida = o caminho de hoje, todos os leitores, e o leitor do parceiro antes deles", async () => {
  const falso = webhookFalso({ parceiro: { consumida: false, acao: "nada", motivo: "nada" } });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Bom dia, tudo certo?", "WAID-F4-P13-2")));
  const caminhos = falso.chamadas.map((c) => c.caminho);
  const ler = caminhos.indexOf("/rest/v1/rpc/parceiro_ler_mensagem");
  assert(ler >= 0);
  for (const leitor of LEITORES) {
    const i = caminhos.indexOf(leitor);
    assert(i > ler, `${leitor} (${i}) depois do leitor do parceiro (${ler})`);
  }
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").map((c) => c.corpo), [{ p_msg: MSG, p_consumida: false }]);
});

Deno.test("handler: função ausente segue o caminho de hoje, sem aviso", async () => {
  const falso = webhookFalso();
  const { avisos } = await comAvisos(() => rodarWebhook(falso, payloadDe("Quanto fica a revisão?", "WAID-F4-P13-3")));
  for (const leitor of LEITORES) assertEquals(falso.de(leitor).length, 1, leitor);
  assertEquals(avisos.filter((a) => a.includes("parceiro_ler_mensagem")), []);
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").map((c) => c.corpo), [{ p_msg: MSG, p_consumida: false }]);
});

Deno.test("handler: erro do leitor do parceiro não derruba nada (aviso só com o código) e segue o caminho de hoje", async () => {
  const falso = webhookFalso({ parceiro: { code: "57014", message: "statement timeout" }, parceiroStatus: 500 });
  const { avisos } = await comAvisos(() => rodarWebhook(falso, payloadDe("NÃO MP", "WAID-F4-P13-4")));
  for (const leitor of LEITORES) assertEquals(falso.de(leitor).length, 1, leitor);
  const doParceiro = avisos.filter((a) => a.includes("parceiro_ler_mensagem"));
  assertEquals(doParceiro.length, 1);
  assert(doParceiro[0].includes("57014") && !doParceiro[0].includes(FONE), doParceiro[0]);
});

Deno.test("handler: o eco (fromMe) nunca passa pelo leitor do parceiro", async () => {
  const falso = webhookFalso({ parceiro: { consumida: true, acao: "patio" } });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Bom dia! Já vejo e te retorno.", "WAID-F4-P13-5", true)));
  assertEquals(falso.de("/rest/v1/rpc/parceiro_ler_mensagem").length, 0);
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").length, 0);
});
