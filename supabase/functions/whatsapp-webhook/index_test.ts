// Testes de autenticação do whatsapp-webhook (MF-AUD-053).
//
// O que estes testes protegem: a função roda com verify_jwt=false — o segredo
// compartilhado é a ÚNICA autenticação. Antes desta correção, um GET anônimo
// devolvia telefone e corpo das últimas mensagens recebidas, e outro GET
// disparava um DELETE em whatsapp_leads.
//
// Os casos de recusa não tocam o banco de propósito: a verificação acontece
// antes de qualquer I/O, então o handler pode ser exercitado sem Supabase.

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const SEGREDO = "segredo-de-teste-nao-real";
const URL_FN = "https://exemplo.supabase.co/functions/v1/whatsapp-webhook";

Deno.env.set("EVOLUTION_WEBHOOK_TOKEN", SEGREDO);
// Valores de fachada: os testes de recusa param antes de usar o client.
Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-fachada");

const { verificarSegredo, handler } = await import("./index.ts");

Deno.test("POST sem segredo é recusado com 401", async () => {
  const res = await handler(new Request(URL_FN, { method: "POST", body: "{}" }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
});

Deno.test("POST com segredo errado é recusado com 401", async () => {
  const res = await handler(
    new Request(`${URL_FN}?token=chute`, { method: "POST", body: "{}" }),
  );
  assertEquals(res.status, 401);
});

Deno.test("GET anônimo no healthcheck é recusado com 401 (não vaza mensagem)", async () => {
  const res = await handler(new Request(`${URL_FN}?healthcheck=1`, { method: "GET" }));
  assertEquals(res.status, 401);
  const corpo = await res.text();
  assertEquals(corpo.includes("recent_messages"), false);
  assertEquals(corpo.includes("phone"), false);
});

Deno.test("GET anônimo sem parâmetro é recusado com 401 (não apaga lead)", async () => {
  const res = await handler(new Request(URL_FN, { method: "GET" }));
  assertEquals(res.status, 401);
});

Deno.test("segredo correto passa pela verificação — por query string", () => {
  const req = new Request(`${URL_FN}?token=${SEGREDO}`, { method: "POST", body: "{}" });
  assertEquals(verificarSegredo(req), null);
});

Deno.test("segredo correto passa pela verificação — por cabeçalho", () => {
  const req = new Request(URL_FN, {
    method: "POST",
    body: "{}",
    headers: { "x-webhook-token": SEGREDO },
  });
  assertEquals(verificarSegredo(req), null);
});

Deno.test("requisição legítima ultrapassa a autenticação e chega ao processamento", async () => {
  // Payload vazio: passa da auth e é recusado pela validação de conteúdo (400),
  // o que prova que a autenticação não é mais o ponto de parada.
  const res = await handler(
    new Request(`${URL_FN}?token=${SEGREDO}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "nao-e-json",
    }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "No payload");
});

Deno.test("OPTIONS (preflight CORS) continua respondendo sem segredo", async () => {
  const res = await handler(new Request(URL_FN, { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("sem o secret configurado, rejeita tudo com 500 (fail-closed)", async () => {
  const anterior = Deno.env.get("EVOLUTION_WEBHOOK_TOKEN")!;
  Deno.env.delete("EVOLUTION_WEBHOOK_TOKEN");
  try {
    const res = await handler(new Request(`${URL_FN}?token=qualquer`, { method: "POST", body: "{}" }));
    assertEquals(res.status, 500);
    assertStringIncludes(await res.text(), "not_configured");
  } finally {
    Deno.env.set("EVOLUTION_WEBHOOK_TOKEN", anterior);
  }
});

// ─── A emenda dos comprovantes (F1, 11/10/2026), no nível do handler ──────────────────────────
// O webhook é o caminho de todo o WhatsApp: com o interruptor em "off", a foto do dono vai ao
// ai-agent exatamente uma vez, nada vai ao comprovantes-whatsapp, a resposta à Evolution sai antes
// do despacho terminar (waitUntil) e texto (ou mensagem que não foi gravada) não lê app_settings.
// O banco (PostgREST) e as funções são um fetch falso que registra cada chamada.

const ADMIN_ID = "0d0d0d0d-0000-4000-8000-0000000000aa";
const MSG_GRAVADA = "11111111-0000-4000-8000-0000000000aa";

function payloadDoDono(message: Record<string, unknown>, waId: string) {
  return {
    event: "messages.upsert",
    data: {
      key: { id: waId, remoteJid: "5547999990000@s.whatsapp.net", fromMe: false },
      pushName: "Dono",
      message,
      messageTimestamp: 1760140857,
    },
  };
}

function bancoEFuncoesFalsos(op: {
  modo?: string;
  insertFalha?: boolean;
  segurarAgente?: Promise<void>;
  role?: string;
  /** F2: o pergunta_rotear (sem ele, a RPC responde erro = conversa desligada). */
  rotear?: unknown;
  /** F2: a resposta do comprovantes-whatsapp. */
  comprovantes?: { status: number; corpo: unknown };
  transcricao?: string | null;
} = {}) {
  const chamadas: Array<{ metodo: string; caminho: string; corpo?: unknown }> = [];
  const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });
  const f = async (entrada: Request | URL | string, init?: RequestInit): Promise<Response> => {
    const req = new Request(entrada, init);
    const u = new URL(req.url);
    const texto = req.method === "POST" ? await req.text().catch(() => "") : "";
    let corpo: unknown = undefined;
    try {
      corpo = texto ? JSON.parse(texto) : undefined;
    } catch { /* não é JSON */ }
    chamadas.push({ metodo: req.method, caminho: u.pathname, corpo });
    if (u.pathname === "/rest/v1/whatsapp_messages" && req.method === "GET") return json([]); // dedup: nova
    if (u.pathname === "/rest/v1/app_users") return json([{ id: ADMIN_ID, role: op.role ?? "admin" }]);
    if (u.pathname === "/rest/v1/whatsapp_messages" && req.method === "POST") {
      return op.insertFalha ? json({ code: "23505", message: "falhou" }, 409) : json({ id: MSG_GRAVADA }, 201);
    }
    if (u.pathname === "/rest/v1/app_settings") return json([{ value: op.modo ?? "off" }]);
    if (u.pathname === "/rest/v1/rpc/pergunta_rotear") {
      return op.rotear ? json(op.rotear) : json({ code: "PGRST202", message: "sem a função" }, 404);
    }
    if (u.pathname === "/rest/v1/rpc/pergunta_interromper") return json(true);
    if (u.pathname === "/functions/v1/comprovantes-whatsapp") {
      return json(op.comprovantes?.corpo ?? { tratada: true }, op.comprovantes?.status ?? 200);
    }
    if (u.pathname === "/functions/v1/whatsapp-transcribe-audio") {
      return json(op.transcricao ? { ok: true, text: op.transcricao } : { ok: false });
    }
    if (u.pathname === "/functions/v1/whatsapp-send") return json({ success: true, messageId: "WA-OUT" });
    if (u.pathname === "/functions/v1/ai-agent") {
      await op.segurarAgente;
      return json({ ok: true });
    }
    return json({ inesperado: u.pathname }, 500);
  };
  const conta = (caminho: string, metodo?: string) =>
    chamadas.filter((c) => c.caminho === caminho && (!metodo || c.metodo === metodo)).length;
  const corpos = (caminho: string) => chamadas.filter((c) => c.caminho === caminho).map((c) => c.corpo as Record<string, unknown>);
  return { f, chamadas, conta, corpos };
}

/** Roda o handler com o fetch falso e um EdgeRuntime.waitUntil que guarda a promessa. */
async function comHandlerFalso(
  falso: ReturnType<typeof bancoEFuncoesFalsos>,
  payload: unknown,
  depois: (res: Response, emSegundoPlano: Promise<unknown>[]) => Promise<void>,
) {
  const g = globalThis as unknown as { fetch: typeof fetch; EdgeRuntime?: unknown };
  const fetchOriginal = g.fetch;
  const runtimeOriginal = g.EdgeRuntime;
  const emSegundoPlano: Promise<unknown>[] = [];
  Deno.env.set("EVOLUTION_API_URL", "https://evo.exemplo.test");
  Deno.env.set("EVOLUTION_API_KEY", "chave-de-fachada");
  Deno.env.set("EVOLUTION_INSTANCE", "hbr-local");
  Deno.env.set("AI_INTERNAL_SECRET", "interno-de-fachada");
  g.fetch = falso.f as typeof fetch;
  g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => emSegundoPlano.push(p) };
  try {
    const res = await handler(new Request(`${URL_FN}?token=${SEGREDO}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    }));
    await depois(res, emSegundoPlano);
    await Promise.all(emSegundoPlano);
  } finally {
    g.fetch = fetchOriginal;
    g.EdgeRuntime = runtimeOriginal;
  }
}

Deno.test("comprovantes com off: foto do dono → 1 ai-agent, 0 comprovantes-whatsapp, resposta antes do despacho", async () => {
  let soltar: () => void = () => {};
  const segurarAgente = new Promise<void>((ok) => { soltar = ok; });
  const falso = bancoEFuncoesFalsos({ modo: "off", segurarAgente });
  await comHandlerFalso(falso, payloadDoDono({ imageMessage: { mimetype: "image/jpeg" } }, "WAID-HANDLER-1"), async (res, fundo) => {
    assertEquals(res.status, 200);
    assertEquals((await res.json()).routed, "ai_operator");
    assertEquals(fundo.length, 1);
    let terminou = false;
    fundo[0].then(() => { terminou = true; });
    await new Promise((ok) => setTimeout(ok, 20));
    assertEquals(terminou, false, "a resposta saiu antes do despacho terminar");
    soltar();
    await fundo[0];
  });
  assertEquals(falso.conta("/functions/v1/ai-agent", "POST"), 1);
  assertEquals(falso.conta("/functions/v1/comprovantes-whatsapp"), 0);
  assertEquals(falso.conta("/rest/v1/app_settings"), 1, "com off a mídia lê só a chave");
});

Deno.test("comprovantes: texto do dono não lê app_settings (F2: 1 RPC, o pergunta_rotear); insert que falha cai no despacho de hoje, uma vez", async () => {
  const texto = bancoEFuncoesFalsos({ modo: "dono" });
  await comHandlerFalso(texto, payloadDoDono({ conversation: "quanto ficou a OS 123?" }, "WAID-HANDLER-2"), async () => {});
  assertEquals(texto.conta("/functions/v1/ai-agent", "POST"), 1);
  assertEquals(texto.conta("/rest/v1/app_settings"), 0);
  assertEquals(texto.conta("/rest/v1/rpc/pergunta_rotear", "POST"), 1, "a única leitura nova do texto do admin");
  assertEquals(texto.conta("/functions/v1/comprovantes-whatsapp"), 0);

  const semLinha = bancoEFuncoesFalsos({ modo: "dono", insertFalha: true });
  await comHandlerFalso(semLinha, payloadDoDono({ imageMessage: { mimetype: "image/jpeg" } }, "WAID-HANDLER-3"), async () => {});
  assertEquals(semLinha.conta("/functions/v1/ai-agent", "POST"), 1);
  assertEquals(semLinha.conta("/rest/v1/app_settings"), 0, "sem o id da mensagem nem consulta o modo");
  assertEquals(semLinha.conta("/functions/v1/comprovantes-whatsapp"), 0);
});

Deno.test("confirmação do agendamento: só a mensagem RECEBIDA e curta chega à RPC do SIM", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const bloco = fonte.slice(fonte.indexOf("if (!event.fromMe && body) {"), fonte.indexOf("if (leadId) {"));
  assertStringIncludes(bloco, "registrar_confirmacao_do_cliente");
  assertStringIncludes(bloco, "body.trim().length <= 60");
  // Fire-and-forget: a RPC nunca derruba nem atrasa o webhook.
  assertStringIncludes(bloco, ".then(() => {}, () => {})");
});

// ─── F2: texto e áudio do dono passam pelo registro de perguntas ──────────────────────────────

const ROTEAR_COM_PERGUNTA = {
  conversa: true, dono: true,
  ativa: {
    id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "para_que",
    opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Estoque", valor: "estoque" }],
    wa_message_id: "WA-P", aberta_em: "2026-10-10T22:30:00Z",
  },
  citada: null, pendencia: null, cmp_em_contexto: null,
};

Deno.test("F2: texto de quem não é admin = zero leitura nova (nem o pergunta_rotear)", async () => {
  const falso = bancoEFuncoesFalsos({ role: "technician", rotear: ROTEAR_COM_PERGUNTA });
  await comHandlerFalso(falso, payloadDoDono({ conversation: "1" }, "WAID-F2-1"), async () => {});
  assertEquals(falso.conta("/rest/v1/rpc/pergunta_rotear"), 0);
  assertEquals(falso.conta("/functions/v1/ai-agent", "POST"), 1);
  assertEquals(falso.conta("/functions/v1/comprovantes-whatsapp"), 0);
});

Deno.test("F2: admin com a conversa desligada = 1 RPC e o despacho de hoje (com message_id e citado)", async () => {
  const falso = bancoEFuncoesFalsos({ rotear: { conversa: false, dono: true } });
  const payload = payloadDoDono({ extendedTextMessage: { text: "1", contextInfo: { stanzaId: "WA-CITADA" } } }, "WAID-F2-2");
  await comHandlerFalso(falso, payload, async () => {});
  assertEquals(falso.conta("/rest/v1/rpc/pergunta_rotear", "POST"), 1);
  assertEquals(falso.corpos("/rest/v1/rpc/pergunta_rotear")[0], { p_phone: "5547999990000", p_citado: "WA-CITADA" });
  const [agente] = falso.corpos("/functions/v1/ai-agent");
  assertEquals(agente.text, "1");
  assertEquals(agente.message_id, MSG_GRAVADA);
  assertEquals(agente.citado, "WA-CITADA");
  assertEquals(falso.conta("/functions/v1/comprovantes-whatsapp"), 0);
});

Deno.test("F2: '1' com pergunta de CMP aberta vai ao responder e NÃO ao ai-agent", async () => {
  const falso = bancoEFuncoesFalsos({ rotear: ROTEAR_COM_PERGUNTA });
  await comHandlerFalso(falso, payloadDoDono({ conversation: "1" }, "WAID-F2-3"), async () => {});
  assertEquals(falso.conta("/functions/v1/ai-agent"), 0);
  assertEquals(falso.corpos("/functions/v1/comprovantes-whatsapp"), [{
    acao: "responder", message_id: MSG_GRAVADA, phone: "5547999990000", texto: "1", citado: null, destino: "comprovante",
  }]);
});

Deno.test("F2: responder que falha → aviso ao dono pelo whatsapp-send e nenhum despacho", async () => {
  const falso = bancoEFuncoesFalsos({ rotear: ROTEAR_COM_PERGUNTA, comprovantes: { status: 500, corpo: { ok: false } } });
  await comHandlerFalso(falso, payloadDoDono({ conversation: "1" }, "WAID-F2-4"), async () => {});
  assertEquals(falso.conta("/functions/v1/ai-agent"), 0);
  const [aviso] = falso.corpos("/functions/v1/whatsapp-send");
  assertEquals(aviso.context, "comprovante");
  assertEquals(aviso.dedupe_key, `cmp:f:${MSG_GRAVADA}`);
});

Deno.test("F2: áudio do admin com a conversa ligada transcreve uma vez só e a resposta vai ao responder", async () => {
  const falso = bancoEFuncoesFalsos({ rotear: ROTEAR_COM_PERGUNTA, transcricao: "Opção dois." });
  await comHandlerFalso(falso, payloadDoDono({ audioMessage: { mimetype: "audio/ogg" } }, "WAID-F2-5"), async () => {});
  assertEquals(falso.conta("/functions/v1/whatsapp-transcribe-audio"), 1, "uma transcrição só (a do roteador)");
  assertEquals(falso.conta("/functions/v1/ai-agent"), 0);
  assertEquals(falso.corpos("/functions/v1/comprovantes-whatsapp")[0].texto, "Opção dois.");
});

// Revisão de 11/10/2026: texto livre com a pergunta de um CMP aberta vai ao assistente e a pergunta
// fica "interrompida" (o próximo "sim"/número sem citar não vale para o CMP sem reapresentar a pergunta).
Deno.test("F2: texto livre com pergunta de CMP aberta → pergunta_interromper e depois o ai-agent", async () => {
  const falso = bancoEFuncoesFalsos({ rotear: ROTEAR_COM_PERGUNTA });
  await comHandlerFalso(falso, payloadDoDono({ conversation: "quanto ficou a OS 123?" }, "WAID-F2-6"), async () => {});
  assertEquals(falso.conta("/rest/v1/rpc/pergunta_interromper"), 1);
  assertEquals(falso.conta("/functions/v1/ai-agent", "POST"), 1);
  assertEquals(falso.conta("/functions/v1/comprovantes-whatsapp"), 0);
  const ordem = falso.chamadas.map((c) => c.caminho).filter((c) => c === "/rest/v1/rpc/pergunta_interromper" || c === "/functions/v1/ai-agent");
  assertEquals(ordem, ["/rest/v1/rpc/pergunta_interromper", "/functions/v1/ai-agent"]);
});

// Lead do site (15/10/2026): a lista de destinatários tinha perdido a barra invertida (`/[,s]+/` cortava na
// letra "s", `/D/g` apagava só a letra "D"). Agora é destinatariosDoAviso (testada em
// _shared/whatsapp/lead-do-site_test.ts). E, com a voz única em sombra, o aviso que saiu é registrado no
// portão DEPOIS do envio (desligado: nada é registrado — as chaves vêm no mesmo SELECT de antes).
Deno.test("lead do site: sem a regex quebrada; destinatários por destinatariosDoAviso; portão só depois do envio", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(fonte.includes(".split(/[,s]+/)"), false, "a regex sem a barra voltou");
  assertEquals(fonte.includes('.replace(/D/g, "")'), false, "a regex sem a barra voltou");
  const ini = fonte.indexOf("async function avisarLeadDoSite(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, "destinatariosDoAviso(sMap.whatsapp_reminder_recipients, phone)");
  const envio = fn.indexOf("provider.sendText(to, texto)");
  const registro = fn.indexOf("registrarParaTodos(");
  assertEquals(envio > 0 && registro > envio, true, "o registro vem depois do envio");
  assertStringIncludes(fn, "if (portao.modo)");
  assertStringIncludes(fn, "CHAVE_VOZ_UNICA, CHAVE_REGRAS, CHAVE_FREIO");
});
