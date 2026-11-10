// Retorno F1 (P13.4): o que o whatsapp-webhook fala com o retorno, com banco falso (contratos C-IDENT e C-ABRIR).
//
// O que estes testes protegem:
//  · identificarCliente: desligado, função ausente, erro ou resposta estranha = o ILIKE de hoje; ligado, o cliente
//    só vem com o papel "cliente", um cliente só e um uuid válido — ambíguo nunca escolhe cliente;
//  · consumidaPelosLeitores: a matriz dos três leitores (cada um sozinho; a revisão "outro" não consome); nada da
//    agenda nem da equipe conta;
//  · abrirNoRetorno: só chama retorno_abrir DEPOIS de resolvidas as promessas dos leitores (promessa controlada),
//    engole erro e função ausente, e o log leva só o código;
//  · noFundo: waitUntil quando existe, e nada solto quando não existe;
//  · index.ts: a ordem e as travas das edições (lida como texto, como em index_test.ts) e o handler inteiro com o
//    banco e as funções num fetch falso (identificação ligada, ambígua e desligada; o eco; o PARAR estreito só para o
//    cliente da identificação nova, e a regra larga de hoje com ela desligada e no fornecedor; o retorno_abrir só
//    depois dos leitores e sem segurar a resposta à Evolution).

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  abrirNoRetorno, consumidaPelosLeitores, identificarCliente, noFundo, RPC_ABRIR, RPC_IDENTIFICAR,
} from "./retorno.ts";

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

const FONE = "5547900009301";
const MSG = "11111111-0000-4000-8000-000000009301";
const CLIENTE_A = "aaaaaaaa-0000-4000-8000-000000009301";
const CLIENTE_B = "bbbbbbbb-0000-4000-8000-000000009302";
const FORNECEDOR = "cccccccc-0000-4000-8000-000000009303";

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

/** Roda `fn` guardando os console.warn (o retorno avisa só com o código do erro). */
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

function controlada<T>() {
  let soltar: (v: T) => void = () => {};
  let falhar: (e: unknown) => void = () => {};
  const promessa = new Promise<T>((ok, nao) => {
    soltar = ok;
    falhar = nao;
  });
  return { promessa, soltar, falhar };
}

const umTique = () => new Promise((ok) => setTimeout(ok, 0));

// ─── identificarCliente (C-IDENT) ──────────────────────────────────────────────────────────────────────────────

Deno.test("identificarCliente: desligado ({nova:false}) = o ILIKE de hoje, e a RPC recebe só o telefone", async () => {
  const banco = bancoFalso(() => ({ data: { nova: false }, error: null }));
  assertEquals(await identificarCliente(banco, FONE), { usar: false, clientId: null });
  assertEquals(banco.chamadas, [{ nome: RPC_IDENTIFICAR, args: { p_fone: FONE } }]);
  assertEquals(RPC_IDENTIFICAR, "retorno_identificar");
});

Deno.test("identificarCliente: erro, função ausente, exceção e resposta estranha = o ILIKE de hoje (nunca lança)", async () => {
  const { avisos } = await comAvisos(async () => {
    for (const resposta of [
      { data: null, error: { code: "57014", message: `timeout lendo ${FONE}` } },
      { data: null, error: { code: "PGRST202", message: "sem a função" } },
      { data: null, error: { code: "42883", message: "function does not exist" } },
      { data: null, error: null },
      { data: { nova: "true", papel: "cliente", client_id: CLIENTE_A }, error: null },
      { data: [{ nova: true }], error: null },
      { data: "nova", error: null },
    ]) {
      assertEquals(await identificarCliente(bancoFalso(() => resposta), FONE), { usar: false, clientId: null }, JSON.stringify(resposta));
    }
    const quebrado = { rpc: () => { throw new TypeError(`sem rede para ${FONE}`); } };
    assertEquals(await identificarCliente(quebrado, FONE), { usar: false, clientId: null });
  });
  // só o erro de verdade e a exceção avisam, e só com o código (nunca o telefone)
  assertEquals(avisos, ["[whatsapp-webhook] retorno_identificar falhou: 57014", "[whatsapp-webhook] retorno_identificar falhou: TypeError"]);
});

Deno.test("identificarCliente: ligado e cliente = usa o cliente do banco", async () => {
  const banco = bancoFalso(() => ({
    data: { nova: true, papel: "cliente", client_id: CLIENTE_A, clientes: [CLIENTE_A] }, error: null,
  }));
  assertEquals(await identificarCliente(banco, FONE), { usar: true, clientId: CLIENTE_A });
});

Deno.test("identificarCliente (F4, P2): parceiro com cadastro de cliente usa o cliente dele; sem cadastro, nulo", async () => {
  // A MP continua com as mensagens gravadas no cadastro dela, como hoje (retorno_identificar devolve o client_id dela).
  const comCadastro = bancoFalso(() => ({
    data: { nova: true, papel: "parceiro", client_id: CLIENTE_A, clientes: [] }, error: null,
  }));
  assertEquals(await identificarCliente(comCadastro, FONE), { usar: true, clientId: CLIENTE_A });
  const semCadastro = bancoFalso(() => ({ data: { nova: true, papel: "parceiro", client_id: null, clientes: [] }, error: null }));
  assertEquals(await identificarCliente(semCadastro, FONE), { usar: true, clientId: null });
  const idInvalido = bancoFalso(() => ({ data: { nova: true, papel: "parceiro", client_id: "abc", clientes: [] }, error: null }));
  assertEquals(await identificarCliente(idInvalido, FONE), { usar: true, clientId: null });
  // Papel parecido não passa: só "cliente" e "parceiro" trazem cliente.
  const parecido = bancoFalso(() => ({
    data: { nova: true, papel: "cliente_parceiro", client_id: CLIENTE_A, clientes: [CLIENTE_A] }, error: null,
  }));
  assertEquals(await identificarCliente(parecido, FONE), { usar: true, clientId: null });
});

Deno.test("identificarCliente: ambíguo nunca escolhe cliente (client_id nulo, ou mesmo preenchido por engano)", async () => {
  const ambiguo = bancoFalso(() => ({
    data: { nova: true, papel: "cliente_ambiguo", client_id: null, clientes: [CLIENTE_A, CLIENTE_B] }, error: null,
  }));
  assertEquals(await identificarCliente(ambiguo, FONE), { usar: true, clientId: null });
  const comId = bancoFalso(() => ({
    data: { nova: true, papel: "cliente_ambiguo", client_id: CLIENTE_A, clientes: [CLIENTE_A, CLIENTE_B] }, error: null,
  }));
  assertEquals(await identificarCliente(comId, FONE), { usar: true, clientId: null });
  const doisNaLista = bancoFalso(() => ({
    data: { nova: true, papel: "cliente", client_id: CLIENTE_A, clientes: [CLIENTE_A, CLIENTE_B] }, error: null,
  }));
  assertEquals(await identificarCliente(doisNaLista, FONE), { usar: true, clientId: null });
});

Deno.test("identificarCliente: uuid inválido = cliente nulo", async () => {
  for (const id of ["abc", "", 123, `${CLIENTE_A}' or 1=1`, null, undefined]) {
    const banco = bancoFalso(() => ({ data: { nova: true, papel: "cliente", client_id: id, clientes: [] }, error: null }));
    assertEquals(await identificarCliente(banco, FONE), { usar: true, clientId: null }, String(id));
  }
});

Deno.test("identificarCliente: equipe, fornecedor, número novo e sem número = ligado, sem cliente (o webhook segue para o lead)", async () => {
  for (const papel of ["equipe", "fornecedor", "novo", "sem_numero"]) {
    const banco = bancoFalso(() => ({ data: { nova: true, papel, client_id: null, clientes: [] }, error: null }));
    assertEquals(await identificarCliente(banco, FONE), { usar: true, clientId: null }, papel);
  }
});

// ─── consumidaPelosLeitores ────────────────────────────────────────────────────────────────────────────────────

Deno.test("consumidaPelosLeitores: a matriz — cada leitor sozinho consome; nenhum, não", () => {
  const nada = { confirmacao: null, conferencia: null, revisao: null };
  assertEquals(consumidaPelosLeitores(nada), false);
  assertEquals(consumidaPelosLeitores({ ...nada, confirmacao: { confirmou: true, os: "OS-00070" } }), true);
  assertEquals(consumidaPelosLeitores({ ...nada, conferencia: { conferiu: true, numero: "REC-1" } }), true);
  for (const intencao of ["sim", "data", "parar"]) {
    assertEquals(consumidaPelosLeitores({ ...nada, revisao: { registrou: true, intencao, cliente: "Fulano" } }), true, intencao);
  }
});

Deno.test("consumidaPelosLeitores: o que não consome — revisão 'outro', registrou false, falso, texto no lugar do booleano", () => {
  const nada = { confirmacao: null, conferencia: null, revisao: null };
  assertEquals(consumidaPelosLeitores({ ...nada, revisao: { registrou: true, intencao: "outro" } }), false, "revisão outro");
  assertEquals(consumidaPelosLeitores({ ...nada, revisao: { registrou: false, intencao: "sim" } }), false);
  assertEquals(consumidaPelosLeitores({ ...nada, revisao: { registrou: false, motivo: "ja_registrado" } }), false);
  assertEquals(consumidaPelosLeitores({ ...nada, revisao: { registrou: true } }), false);
  assertEquals(consumidaPelosLeitores({ ...nada, confirmacao: { confirmou: false, ambigua: 2 } }), false);
  assertEquals(consumidaPelosLeitores({ ...nada, confirmacao: { confirmou: "true" } }), false);
  assertEquals(consumidaPelosLeitores({ ...nada, conferencia: { conferiu: 1 } }), false);
  assertEquals(consumidaPelosLeitores({ confirmacao: true, conferencia: "conferiu", revisao: ["sim"] }), false);
  assertEquals(consumidaPelosLeitores(undefined as unknown as typeof nada), false);
});

Deno.test("consumidaPelosLeitores: não há campo da agenda nem da equipe ({consumiu} não conta em lugar nenhum)", () => {
  const daAgenda = { consumiu: true, modo: "ligado", efeito: "ao_dono" };
  const daEquipe = { consumiu: true, tipo: "ok" };
  assertEquals(consumidaPelosLeitores({ confirmacao: daAgenda, conferencia: daEquipe, revisao: daAgenda }), false);
  const comCampoAMais = { confirmacao: null, conferencia: null, revisao: null, agenda: daAgenda, equipe: daEquipe };
  assertEquals(consumidaPelosLeitores(comCampoAMais as unknown as Parameters<typeof consumidaPelosLeitores>[0]), false);
});

// ─── abrirNoRetorno (C-ABRIR) ──────────────────────────────────────────────────────────────────────────────────

Deno.test("abrirNoRetorno: só chama retorno_abrir DEPOIS de resolvidas as promessas dos três leitores", async () => {
  const conf = controlada<unknown>();
  const confer = controlada<unknown>();
  const rev = controlada<unknown>();
  const banco = bancoFalso(() => ({ data: { ok: true, acao: "nova" }, error: null }));
  let recebidos: unknown[] | null = null;
  const fim = abrirNoRetorno(banco, {
    msgId: MSG,
    leitores: [conf.promessa, confer.promessa, rev.promessa],
    consumida: (v) => {
      recebidos = v;
      return consumidaPelosLeitores({ confirmacao: v[0], conferencia: v[1], revisao: v[2] });
    },
  });
  await umTique();
  assertEquals(banco.chamadas.length, 0, "chamou antes dos leitores");
  conf.soltar({ confirmou: false });
  confer.soltar(null);
  await umTique();
  assertEquals(banco.chamadas.length, 0, "chamou com a revisão ainda pendente");
  rev.soltar({ registrou: true, intencao: "sim" });
  await fim;
  assertEquals(recebidos, [{ confirmou: false }, null, { registrou: true, intencao: "sim" }]);
  assertEquals(banco.chamadas, [{ nome: RPC_ABRIR, args: { p_msg: MSG, p_consumida: true } }]);
  assertEquals(RPC_ABRIR, "retorno_abrir");
});

Deno.test("abrirNoRetorno: nenhum leitor consumiu = p_consumida false; leitor que rejeitou vale null", async () => {
  const banco = bancoFalso(() => ({ data: { ok: true, acao: "ignorada" }, error: null }));
  let recebidos: unknown[] | null = null;
  await abrirNoRetorno(banco, {
    msgId: MSG,
    leitores: [Promise.resolve(null), Promise.reject(new Error("falhou")), Promise.resolve({ registrou: true, intencao: "outro" })],
    consumida: (v) => {
      recebidos = v;
      return consumidaPelosLeitores({ confirmacao: v[0], conferencia: v[1], revisao: v[2] });
    },
  });
  assertEquals(recebidos, [null, null, { registrou: true, intencao: "outro" }]);
  assertEquals(banco.chamadas, [{ nome: RPC_ABRIR, args: { p_msg: MSG, p_consumida: false } }]);
});

Deno.test("abrirNoRetorno: função ausente (PGRST202, 42883) = silêncio; outro erro = aviso só com o código; nunca lança", async () => {
  const { avisos } = await comAvisos(async () => {
    for (const code of ["PGRST202", "42883"]) {
      const banco = bancoFalso(() => ({ data: null, error: { code, message: "sem a função" } }));
      await abrirNoRetorno(banco, { msgId: MSG, leitores: [], consumida: () => false });
      assertEquals(banco.chamadas.length, 1);
    }
    const lento = bancoFalso(() => ({ data: null, error: { code: "57014", message: `timeout no ${FONE}: "quero orçamento"` } }));
    await abrirNoRetorno(lento, { msgId: MSG, leitores: [], consumida: () => false });
    // o banco que devolve ok false já gravou o erro (log_app_error dentro do retorno_abrir): sem aviso aqui
    const okFalse = bancoFalso(() => ({ data: { ok: false, erro: `falhou com ${FONE}` }, error: null }));
    await abrirNoRetorno(okFalse, { msgId: MSG, leitores: [], consumida: () => false });
  });
  assertEquals(avisos, ["[whatsapp-webhook] retorno_abrir falhou: 57014"]);
  assert(!avisos.join(" ").includes(FONE), "o telefone foi parar no log");
});

Deno.test("abrirNoRetorno: rpc que lança, banco sem rpc e erro sem código não derrubam nada", async () => {
  const { avisos } = await comAvisos(async () => {
    await abrirNoRetorno({ rpc: () => { throw new TypeError(`sem rede ${FONE}`); } }, { msgId: MSG, leitores: [], consumida: () => false });
    await abrirNoRetorno({}, { msgId: MSG, leitores: [], consumida: () => false });
    await abrirNoRetorno({ rpc: () => Promise.reject({ message: FONE }) }, { msgId: MSG, leitores: [], consumida: () => false });
    await abrirNoRetorno(bancoFalso(() => ({ data: null, error: { code: `57014 ${FONE}` } })), {
      msgId: MSG, leitores: [], consumida: () => false,
    });
  });
  assertEquals(avisos.length, 4);
  assert(avisos.every((a) => a.startsWith("[whatsapp-webhook] retorno_abrir falhou: ")));
  assert(!avisos.join(" ").includes(FONE), "o telefone foi parar no log");
});

Deno.test("abrirNoRetorno: consumida que lança vale true (falha fecha); sem id da mensagem, nem chama", async () => {
  const banco = bancoFalso(() => ({ data: { ok: true }, error: null }));
  await abrirNoRetorno(banco, { msgId: MSG, leitores: [Promise.resolve(null)], consumida: () => { throw new Error("quebrou"); } });
  assertEquals(banco.chamadas, [{ nome: RPC_ABRIR, args: { p_msg: MSG, p_consumida: true } }]);
  const semId = bancoFalso(() => ({ data: { ok: true }, error: null }));
  await abrirNoRetorno(semId, { msgId: "", leitores: [], consumida: () => false });
  await abrirNoRetorno(semId, { msgId: null as unknown as string, leitores: [], consumida: () => false });
  assertEquals(semId.chamadas.length, 0);
});

// ─── noFundo ───────────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("noFundo: com EdgeRuntime.waitUntil, a promessa vai para ele (e a que rejeita não vira erro solto)", async () => {
  const g = globalThis as unknown as { EdgeRuntime?: unknown };
  const original = g.EdgeRuntime;
  const guardadas: Promise<unknown>[] = [];
  g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => guardadas.push(p) };
  try {
    noFundo(Promise.resolve("feito"));
    noFundo(Promise.reject(new Error("falhou no fundo")));
    assertEquals(guardadas.length, 2);
    assertEquals(await guardadas[0], "feito");
    assertEquals(await guardadas[1], null);
  } finally {
    g.EdgeRuntime = original;
  }
});

Deno.test("noFundo: sem EdgeRuntime, ou com waitUntil que lança, não lança e não deixa rejeição solta", async () => {
  const g = globalThis as unknown as { EdgeRuntime?: unknown };
  const original = g.EdgeRuntime;
  try {
    g.EdgeRuntime = undefined;
    noFundo(Promise.reject(new Error("sem runtime")));
    g.EdgeRuntime = { waitUntil: () => { throw new Error("runtime quebrado"); } };
    noFundo(Promise.reject(new Error("runtime quebrado")));
    g.EdgeRuntime = { waitUntil: "não é função" };
    noFundo(Promise.resolve(1));
    await umTique();
  } finally {
    g.EdgeRuntime = original;
  }
});

// ─── index.ts: as edições do P13.3, lidas como texto ──────────────────────────────────────────────────────────

const fonteDoWebhook = async () => (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");

Deno.test("index.ts: a identificação nova vem antes, e o ILIKE de hoje só quando ela não vale", async () => {
  const fonte = await fonteDoWebhook();
  const ident = fonte.indexOf("const ident = await identificarCliente(admin, phone);");
  const usar = fonte.indexOf("if (ident.usar) {", ident);
  const nulo = fonte.indexOf("client = ident.clientId ? { id: ident.clientId } : null;", usar);
  const senao = fonte.indexOf("} else {", nulo);
  const ilike = fonte.indexOf(".or(`phone.ilike.%${phone}%,whatsapp.ilike.%${phone}%`)", senao);
  assert(ident > 0 && usar > ident && nulo > usar && senao > nulo && ilike > senao, `${ident} ${usar} ${nulo} ${senao} ${ilike}`);
  // vale para a recebida e para o eco: vem antes do insert, fora do bloco do funcionário
  assert(ident > fonte.indexOf('return jr({ ok: true, routed: "ai_operator"'));
  assert(ident < fonte.indexOf('direction: event.fromMe ? "outbound" : "inbound"'));
  assertEquals(fonte.split("identificarCliente(").length - 1, 1, "uma identificação só");
});

Deno.test("index.ts: o PARAR estreito só para o cliente da identificação nova; desligada e no fornecedor, a regra de hoje", async () => {
  const fonte = await fonteDoWebhook();
  const ini = fonte.indexOf("async function manejarRespostaAutomatica(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assert(fn.includes("identificacaoNova = false,"), "sem a identificação nova, a regra larga de hoje é o padrão");
  assert(fn.includes('const estreito = tabela === "clients" && identificacaoNova === true;'));
  assert(fn.includes('if (r.intencao === "opt_out" && (!estreito || ehPedidoDeParar(texto))) {'));
  assertEquals(fn.includes('if (r.intencao === "opt_out") {'), false, "a regra larga voltou para todos");
  // o ai_comms_log continua marcado com a intenção do classificarResposta, como antes
  assert(fn.includes("reply_intent: r.intencao"));
  assert(fonte.includes('import { ehPedidoDeParar } from "../_shared/whatsapp/parar.ts";'));
  // o cliente leva a identificação desta mensagem; o fornecedor não leva nada (regra de hoje)
  const doCliente = 'manejarRespostaAutomatica(admin, "clients", clientId, body, ident.usar).catch(() => {});';
  const doFornecedor = 'await manejarRespostaAutomatica(admin, "suppliers", sup.id, body);';
  assertEquals(fonte.split(doCliente).length - 1, 1, "a chamada do cliente");
  assertEquals(fonte.split(doFornecedor).length - 1, 1, "a chamada do fornecedor");
  assertEquals(fonte.split("manejarRespostaAutomatica(admin,").length - 1, 2, "só as duas chamadas");
  // e o opt-out de hoje continua antes da equipe (a trava de index_test.ts procura a chamada sem o 5º argumento)
  const bloco = fonte.slice(fonte.indexOf("if (!event.fromMe && body) {"), fonte.indexOf("if (leadId) {"));
  const manejo = bloco.indexOf(doCliente);
  assert(manejo > 0 && manejo < bloco.indexOf("const daEquipe = await respostaDaEquipe(admin,"), `${manejo}`);
});

Deno.test("index.ts: os três leitores guardam o resultado sem await, e o retorno_abrir vem depois deles, no fundo", async () => {
  const fonte = await fonteDoWebhook();
  const bloco = fonte.slice(fonte.indexOf("if (!event.fromMe && body) {"), fonte.indexOf("if (leadId) {"));
  assertEquals(bloco.split(".then((r) => r?.data ?? null, () => null)").length - 1, 3, "os três leitores guardam o resultado");
  for (const rpc of ["registrar_confirmacao_do_cliente", "registrar_conferencia_do_freelancer", "registrar_resposta_da_revisao"]) {
    assert(!bloco.includes(`await admin.rpc("${rpc}"`), `${rpc} passou a ser esperado no caminho principal`);
  }
  const equipe = bloco.indexOf("const daEquipe = await respostaDaEquipe(admin,");
  const cliente = bloco.indexOf("const doCliente = !daEquipe &&");
  const confirmacao = bloco.indexOf('pConfirmacao = admin.rpc("registrar_confirmacao_do_cliente"');
  const conferencia = bloco.indexOf('pConferencia = admin.rpc("registrar_conferencia_do_freelancer"');
  const revisao = bloco.indexOf('pRevisao = admin.rpc("registrar_resposta_da_revisao"');
  const guarda = bloco.indexOf("if (msg?.id) {", revisao);
  const abrir = bloco.indexOf("noFundo(abrirNoRetorno(admin, {", guarda);
  assert(
    equipe > 0 && cliente > equipe && confirmacao > cliente && conferencia > confirmacao && revisao > conferencia &&
      guarda > revisao && abrir > guarda,
    `ordem: ${equipe} ${cliente} ${confirmacao} ${conferencia} ${revisao} ${guarda} ${abrir}`,
  );
  assert(bloco.includes("leitores: [pConfirmacao, pConferencia, pRevisao],"));
  // F4 (P13): o callback soma o leitor do parceiro antes dos três (parceiro_test.ts confere a ordem dele).
  assert(bloco.includes(
    "consumida: (v) => doParceiro.consumida || consumidaPelosLeitores({ confirmacao: v[0], conferencia: v[1], revisao: v[2] }),",
  ));
  assertEquals(fonte.includes("await abrirNoRetorno("), false, "a resposta à Evolution não pode esperar o retorno");
  assertEquals(fonte.includes("await noFundo("), false);
  // as travas de hoje (o "ok" tem um dono só) continuam
  assert(bloco.includes("if (body.trim().length <= 60 && !daEquipe && !doCliente) {"));
  assert(bloco.includes("if (body.trim().length <= 500 && !doCliente) {"));
});

Deno.test("retorno.ts não importa nada congelado (_shared/ai/, _shared/agenda/)", async () => {
  const fonte = await Deno.readTextFile(new URL("./retorno.ts", import.meta.url));
  const imports = [...fonte.matchAll(/^\s*import\s[^;]*?from\s+["']([^"']+)["']/gm)].map((m) => m[1]);
  assertEquals(imports.filter((i) => i.includes("_shared/ai/") || i.includes("_shared/agenda/")), []);
  const parar = await Deno.readTextFile(new URL("../_shared/whatsapp/parar.ts", import.meta.url));
  assertEquals(/^\s*import\s/m.test(parar), false, "parar.ts é só a regra, sem import");
});

// ─── O handler inteiro, com o banco e as funções num fetch falso ───────────────────────────────────────────────

type ChamadaHttp = { metodo: string; caminho: string; busca: string; corpo?: Record<string, unknown> };

function webhookFalso(op: {
  /** A resposta de retorno_identificar; sem ela, a função "não existe" (PGRST202). */
  identificar?: unknown;
  /** O que o ILIKE de hoje acha em clients. */
  ilike?: unknown[];
  /** Segura a RPC de confirmação até o teste soltar. */
  segurarConfirmacao?: Promise<void>;
  confirmacao?: unknown;
  /** O id que o ILIKE de hoje acha em suppliers (sem ele, nenhum fornecedor). */
  fornecedor?: string;
} = {}) {
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
    chamadas.push({ metodo: req.method, caminho: u.pathname, busca: decodeURIComponent(u.search), corpo });
    const p = u.pathname;
    if (p === "/rest/v1/whatsapp_messages") return req.method === "GET" ? json([]) : json({ id: MSG }, 201);
    if (p === "/rest/v1/app_users") return json([]); // o número não é login
    if (p === "/rest/v1/rpc/retorno_identificar") {
      return op.identificar === undefined ? json({ code: "PGRST202", message: "sem a função" }, 404) : json(op.identificar);
    }
    if (p === "/rest/v1/clients") return json(req.method === "GET" ? (op.ilike ?? []) : []);
    if (p === "/rest/v1/whatsapp_leads") return json(req.method === "GET" ? [{ id: "lead-1" }] : []);
    if (p === "/rest/v1/suppliers") return json(req.method === "GET" && op.fornecedor ? [{ id: op.fornecedor }] : []);
    if (p === "/rest/v1/ai_comms_log" || p === "/rest/v1/app_settings") return json([]);
    if (p === "/rest/v1/rpc/followup_registrar_resposta") return json(null);
    if (p === "/rest/v1/rpc/agenda_resposta_da_equipe") return json({ consumiu: false });
    if (p === "/rest/v1/rpc/agenda_resposta_do_cliente") return json({ consumiu: false, modo: "sombra" });
    if (p === "/rest/v1/rpc/registrar_confirmacao_do_cliente") {
      await op.segurarConfirmacao;
      return json(op.confirmacao ?? { confirmou: false });
    }
    if (p === "/rest/v1/rpc/registrar_conferencia_do_freelancer") return json({ conferiu: false });
    if (p === "/rest/v1/rpc/registrar_resposta_da_revisao") return json({ registrou: false });
    if (p === "/rest/v1/rpc/retorno_abrir") return json({ ok: true, acao: "nova", nivel: "recibo" });
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
      pushName: "Cliente de Teste",
      message: { conversation: texto },
      messageTimestamp: 1762210800,
    },
  };
}

/** Roda o handler com o fetch falso e um waitUntil que guarda as promessas; espera o fundo antes de devolver o fetch. */
async function rodarWebhook(
  falso: ReturnType<typeof webhookFalso>,
  payload: unknown,
  durante: (res: Response, fundo: Promise<unknown>[]) => Promise<void> = async () => {},
) {
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
    await durante(res, fundo);
    await Promise.all(fundo);
    // o manejarRespostaAutomatica e o followup não são aguardados nem vão ao waitUntil (como hoje)
    await new Promise((ok) => setTimeout(ok, 30));
  } finally {
    g.fetch = fetchOriginal;
    g.EdgeRuntime = runtimeOriginal;
  }
}

const IDENTIFICADO = { nova: true, papel: "cliente", client_id: CLIENTE_A, clientes: [CLIENTE_A] };

Deno.test("handler: identificação ligada e cliente = o cliente do banco, sem o ILIKE nem o lead", async () => {
  const falso = webhookFalso({ identificar: IDENTIFICADO, ilike: [{ id: CLIENTE_B }] });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Bom dia, preciso de um orçamento", "WAID-P13-1")));
  assertEquals(falso.de("/rest/v1/rpc/retorno_identificar").map((c) => c.corpo), [{ p_fone: FONE }]);
  assertEquals(falso.de("/rest/v1/clients", "GET").length, 0, "o ILIKE rodou com a identificação ligada");
  assertEquals(falso.de("/rest/v1/whatsapp_leads").length, 0, "cliente identificado não vira lead");
  const [gravada] = falso.de("/rest/v1/whatsapp_messages", "POST").map((c) => c.corpo!);
  assertEquals([gravada.client_id, gravada.lead_id, gravada.direction], [CLIENTE_A, null, "inbound"]);
});

Deno.test("handler: identificação ligada e ambígua = nenhum cliente (nunca um dos dois) e o caminho do lead", async () => {
  const falso = webhookFalso({
    identificar: { nova: true, papel: "cliente_ambiguo", client_id: null, clientes: [CLIENTE_A, CLIENTE_B] },
    ilike: [{ id: CLIENTE_B }],
  });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Oi, tudo bem?", "WAID-P13-2")));
  assertEquals(falso.de("/rest/v1/clients", "GET").length, 0);
  const [gravada] = falso.de("/rest/v1/whatsapp_messages", "POST").map((c) => c.corpo!);
  assertEquals([gravada.client_id, gravada.lead_id], [null, "lead-1"]);
});

Deno.test("handler: identificação desligada ou sem a função = o ILIKE de hoje, sem aviso", async () => {
  for (const identificar of [{ nova: false }, undefined]) {
    const falso = webhookFalso({ identificar, ilike: [{ id: CLIENTE_B }] });
    const { avisos } = await comAvisos(() => rodarWebhook(falso, payloadDe("Oi, tudo bem?", "WAID-P13-3")));
    const ilike = falso.de("/rest/v1/clients", "GET");
    assertEquals(ilike.length, 1, JSON.stringify(identificar));
    assert(ilike[0].busca.includes(`phone.ilike.%${FONE}%,whatsapp.ilike.%${FONE}%`), ilike[0].busca);
    const [gravada] = falso.de("/rest/v1/whatsapp_messages", "POST").map((c) => c.corpo!);
    assertEquals(gravada.client_id, CLIENTE_B);
    assertEquals(avisos.filter((a) => a.includes("retorno_identificar")), [], "desligado ou ausente não é erro");
  }
});

Deno.test("handler: o eco (fromMe) também é identificado, e o retorno_abrir é só da recebida", async () => {
  const falso = webhookFalso({ identificar: IDENTIFICADO });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Bom dia! Já vejo e te retorno.", "WAID-P13-4", true)));
  assertEquals(falso.de("/rest/v1/rpc/retorno_identificar").length, 1);
  const [gravada] = falso.de("/rest/v1/whatsapp_messages", "POST").map((c) => c.corpo!);
  assertEquals([gravada.client_id, gravada.direction], [CLIENTE_A, "outbound"]);
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").length, 0);
});

Deno.test("handler: retorno_abrir só depois dos três leitores, sem segurar a resposta, com a confirmação que consumiu", async () => {
  let soltar: () => void = () => {};
  const segurarConfirmacao = new Promise<void>((ok) => {
    soltar = ok;
  });
  const falso = webhookFalso({ identificar: IDENTIFICADO, segurarConfirmacao, confirmacao: { confirmou: true, os: "OS-00070" } });
  await comAvisos(() =>
    rodarWebhook(falso, payloadDe("Sim", "WAID-P13-5"), async (res, fundo) => {
      assertEquals((await res.json()).message_id, MSG, "a resposta à Evolution saiu com a confirmação ainda pendente");
      assertEquals(fundo.length, 1, "o retorno vai ao waitUntil");
      await new Promise((ok) => setTimeout(ok, 20));
      assertEquals(falso.de("/rest/v1/rpc/registrar_confirmacao_do_cliente").length, 1);
      assertEquals(falso.de("/rest/v1/rpc/registrar_conferencia_do_freelancer").length, 1);
      assertEquals(falso.de("/rest/v1/rpc/registrar_resposta_da_revisao").length, 1);
      assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").length, 0, "o retorno não esperou a confirmação");
      soltar();
    })
  );
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").map((c) => c.corpo), [{ p_msg: MSG, p_consumida: true }]);
  const caminhos = falso.chamadas.map((c) => c.caminho);
  const abrir = caminhos.indexOf("/rest/v1/rpc/retorno_abrir");
  for (
    const leitor of [
      "agenda_resposta_da_equipe",
      "agenda_resposta_do_cliente",
      "registrar_confirmacao_do_cliente",
      "registrar_conferencia_do_freelancer",
      "registrar_resposta_da_revisao",
    ]
  ) {
    const i = caminhos.indexOf(`/rest/v1/rpc/${leitor}`);
    assert(i >= 0 && i < abrir, `${leitor} (${i}) antes do retorno_abrir (${abrir})`);
  }
});

Deno.test("handler: nenhum leitor consumiu = p_consumida false (a agenda é lida pelo banco, não por aqui)", async () => {
  const falso = webhookFalso({ identificar: IDENTIFICADO });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Quanto fica a revisão do motor?", "WAID-P13-6")));
  assertEquals(falso.de("/rest/v1/rpc/retorno_abrir").map((c) => c.corpo), [{ p_msg: MSG, p_consumida: false }]);
});

Deno.test("handler: identificação nova ligada = o opt-out do cliente só no PARAR estreito ('nunca mais' e 'me tira' não calam)", async () => {
  const optOuts = (falso: ReturnType<typeof webhookFalso>) =>
    falso.de("/rest/v1/clients", "PATCH").filter((c) => c.corpo && "opt_out_whatsapp" in c.corpo);
  // a regra larga diz opt_out, a estreita não: o cliente continua podendo receber. O PARAR por extenso também fica
  // sem opt-out aqui: ele só chega ao dono pelo parar_largo (P2) e pelo "Para conferir" (P9/P14), de 16/11 em diante
  for (
    const [i, texto] of ["Nunca mais vou atrasar o pagamento, prometo", "me tira uma dúvida sobre a bateria", "Pare de me mandar mensagem"]
      .entries()
  ) {
    const falso = webhookFalso({ identificar: IDENTIFICADO });
    await comAvisos(() => rodarWebhook(falso, payloadDe(texto, `WAID-P13-7${i}`)));
    assertEquals(optOuts(falso).length, 0, texto);
  }
  // as duas regras dizem que sim: o opt-out é gravado no cliente, como hoje
  for (const [i, texto] of ["Descadastrar", "Não quero mais receber mensagens"].entries()) {
    const falso = webhookFalso({ identificar: IDENTIFICADO });
    await comAvisos(() => rodarWebhook(falso, payloadDe(texto, `WAID-P13-8${i}`)));
    const gravados = optOuts(falso);
    assertEquals(gravados.map((c) => c.corpo), [{ opt_out_whatsapp: true }], texto);
    assert(gravados[0].busca.includes(`id=eq.${CLIENTE_A}`), gravados[0].busca);
  }
});

Deno.test("handler: identificação desligada (ou sem a função) e fornecedor = a regra larga de hoje, sem mudança", async () => {
  const optOuts = (falso: ReturnType<typeof webhookFalso>, tabela: "clients" | "suppliers") =>
    falso.de(`/rest/v1/${tabela}`, "PATCH").filter((c) => c.corpo && "opt_out_whatsapp" in c.corpo);
  // desligada: o cliente do ILIKE ganha o opt-out com o PARAR por extenso, como hoje (a rede do parar_largo ainda não
  // existe antes de 16/11, e sem a chave nada muda)
  for (const [i, identificar] of [{ nova: false }, undefined].entries()) {
    const falso = webhookFalso({ identificar, ilike: [{ id: CLIENTE_B }] });
    await comAvisos(() => rodarWebhook(falso, payloadDe("Pare de me mandar mensagem", `WAID-P13-9${i}`)));
    const gravados = optOuts(falso, "clients");
    assertEquals(gravados.map((c) => c.corpo), [{ opt_out_whatsapp: true }], JSON.stringify(identificar));
    assert(gravados[0].busca.includes(`id=eq.${CLIENTE_B}`), gravados[0].busca);
  }
  // fornecedor: a identificação nova não o acha nem o muda; a regra larga de hoje vale mesmo com ela ligada
  const falso = webhookFalso({
    identificar: { nova: true, papel: "fornecedor", client_id: null, clientes: [] },
    fornecedor: FORNECEDOR,
  });
  await comAvisos(() => rodarWebhook(falso, payloadDe("Não me mande mais essas cotações", "WAID-P13-95")));
  assertEquals(optOuts(falso, "clients").length, 0);
  const doFornecedor = optOuts(falso, "suppliers");
  assertEquals(doFornecedor.map((c) => c.corpo), [{ opt_out_whatsapp: true }]);
  assert(doFornecedor[0].busca.includes(`id=eq.${FORNECEDOR}`), doFornecedor[0].busca);
});
