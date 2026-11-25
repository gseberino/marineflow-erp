// Pacote 1 do assistente, S1 (24/11/2026): send_whatsapp_message e schedule_whatsapp_message pedem PIN por quem recebe
// de fato e pelo que o texto diz, decidido no servidor, e mandam SEMPRE ao número que o cartão mostrou.
//
// Como era: PIN só com client_id; com to_phone (que a própria descrição manda usar para responder conversa), só "sim",
// mesmo indo a cliente. E com client_id E to_phone o envio ia ao to_phone, com o cartão mostrando o número do cadastro.
// O que se fixa aqui, pelas ferramentas de verdade e pelo executor do agente, com banco falso e dados inventados:
//   · fornecedor com texto neutro: só o "sim"; com valor, data ou promessa: PIN;
//   · número de cliente por to_phone/phone, número sem cadastro, leitura que falha: PIN, com o motivo no cartão;
//   · client_id com outro número junto, cliente sem número ou que não existe: recusa que ensina, sem cartão;
//   · o envio usa o mesmo número do cartão; o que não fecha não sai.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/tools/mensagem-livre-pin_test.ts
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bancoFalso, ctxDe, type Linha } from "./banco-falso-fakes_test.ts";
import { FALHA_AO_CONFERIR_O_DESTINO, numeroDoEnvio, recusaDoDestino } from "./agendamento.ts";
import { whatsappTools } from "./whatsapp.ts";
import { purchasingTools } from "./purchasing.ts";
import { registryCrudTools } from "./registry-crud.ts";
import { contactTools } from "./contacts.ts";
import { executarChamadaDeTool, resumoQueRecusa } from "../agent.ts";
import { autonomyKey, NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import type { ToolDef } from "./registry.ts";

const enviar = whatsappTools.find((t) => t.name === "send_whatsapp_message")!;
const agendar = whatsappTools.find((t) => t.name === "schedule_whatsapp_message")!;

const CLIENTE = "5547999159654";
const FORNECEDOR = "5547988887777";
const TECNICO = "5547977776666";
const DESCONHECIDO = "5511955554444";
const NEUTRO = "Bom dia! Pode me mandar a foto da peça?";
const QUANDO = "2030-10-08T09:00";
/** Cadastro antigo (como o banco devolve as datas): só o de mais de 24 horas vale "fornecedor" ou "equipe". */
const ANTIGO = { created_at: "2026-03-02T12:00:00.123456+00:00", updated_at: "2026-05-20T09:30:00.654321+00:00" };

function cadastros(muda: (t: Record<string, Linha[]>) => void = () => {}) {
  const tabelas: Record<string, Linha[]> = {
    clients: [
      { id: "c1", name: "Cliente Inventado", display_name: null, whatsapp: "(47) 99915-9654", phone: "4733331234" },
      { id: "c2", name: "Sem Numero", display_name: null, whatsapp: null, phone: null },
    ],
    suppliers: [{ id: "s1", name: "Fornecedor Inventado", phone: "(47) 98888-7777", active: true, ...ANTIGO }],
    payees: [{ id: "p1", name: "Técnico Inventado", phone: "47 97777-6666", active: true, app_user_id: null, ...ANTIGO }],
    app_users: [{ id: "dono-1", full_name: "Dono Inventado", phone: null, phone_normalized: "5547966665555", active: true }],
    parceiro_numeros: [],
    whatsapp_leads: [],
    whatsapp_messages: [],
    whatsapp_scheduled_sends: [],
  };
  muda(tabelas);
  return tabelas;
}
const semParceiroDeFora = { parceiro_numeros_fora_da_ia: () => ({ data: [], error: null }) };
const banco = (muda?: (t: Record<string, Linha[]>) => void, falhas: Record<string, string> = {}) => bancoFalso(cadastros(muda), falhas, semParceiroDeFora);

function aVista(tool: ToolDef, db: unknown, extra: Record<string, unknown> = {}) {
  return { toolsByName: { [tool.name]: tool }, alcancaveisPelaRede: {}, toolCtx: ctxDe(db, extra), sessionId: "sessao-s1", channel: "whatsapp" as const };
}
const pendencias = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_pending_actions ?? [];
const ultimaLinha = (resumo: unknown) => String(resumo).split("\n").at(-1);

/** Roda com o whatsapp-send simulado e devolve os corpos que chegaram a ele. */
async function comEnvio<T>(corpo: () => Promise<T>): Promise<{ resultado: T; enviados: Array<Record<string, unknown>> }> {
  const enviados: Array<Record<string, unknown>> = [];
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = ((entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (!url.endsWith("/functions/v1/whatsapp-send")) throw new Error(`fetch inesperado: ${url}`);
    enviados.push(JSON.parse(String(init?.body)));
    return Promise.resolve(new Response(JSON.stringify({ success: true, messageId: "WA-1" })));
  }) as typeof fetch;
  try {
    return { resultado: await corpo(), enviados };
  } finally {
    globalThis.fetch = original;
  }
}

// ─── O número que vai receber (uma regra só para o cartão, o risco e o envio) ───────────────────

Deno.test("S1 número: só o número vale o número; só o client_id vale o do cadastro", async () => {
  const b = banco();
  assertEquals(await numeroDoEnvio(b.db, { telefone: "47 98888-7777" }, "to_phone"), { ok: true, telefone: FORNECEDOR, cliente: null });
  assertEquals(await numeroDoEnvio(b.db, { client_id: "c1" }, "to_phone"), { ok: true, telefone: CLIENTE, cliente: { id: "c1", nome: "Cliente Inventado" } });
  // Sem WhatsApp no cadastro, vale o telefone do cadastro (a mesma conta do cartão).
  const soTelefone = banco((t) => { t.clients[0].whatsapp = null; t.clients[0].phone = "(47) 9915-9654"; });
  assertEquals((await numeroDoEnvio(soTelefone.db, { client_id: "c1" }, "to_phone") as { telefone: string }).telefone, CLIENTE);
  // Número inválido ou de grupo, sem client_id.
  for (const ruim of ["123", "", "120363025246125483@g.us"]) {
    const r = await numeroDoEnvio(b.db, { telefone: ruim }, "to_phone");
    assertEquals(r.ok, false, ruim);
    assertStringIncludes((r as { erro: string }).erro, "inválido");
  }
  // "Tem client_id" é a mesma conta do cartão e do risco pelos argumentos: vazio, nulo e zero não são cliente (vale o
  // número); texto só com espaços É um client_id (que não existe), e não cai calado no número.
  for (const semCliente of ["", null, undefined, 0, false]) {
    assertEquals(await numeroDoEnvio(b.db, { client_id: semCliente, telefone: "47 98888-7777" }, "to_phone"),
      { ok: true, telefone: FORNECEDOR, cliente: null }, String(semCliente));
  }
  const soEspacos = await numeroDoEnvio(b.db, { client_id: "   ", telefone: "47 98888-7777" }, "to_phone") as { ok: false; erro: string };
  assertEquals(soEspacos.ok, false);
  assertStringIncludes(soEspacos.erro, "Não achei cliente");
});

Deno.test("S1 número: client_id E número só passam se forem o mesmo; diferentes é recusa que ensina, nunca escolha calada", async () => {
  const b = banco();
  // O mesmo número, escrito de outro jeito (sem DDI, sem o nono dígito): vale o do cadastro.
  for (const igual of ["47 99915-9654", "5547999159654", "(47) 9915-9654", "+55 47 99915 9654"]) {
    assertEquals(await numeroDoEnvio(b.db, { client_id: "c1", telefone: igual }, "to_phone"), { ok: true, telefone: CLIENTE, cliente: { id: "c1", nome: "Cliente Inventado" } }, igual);
  }
  const outro = await numeroDoEnvio(b.db, { client_id: "c1", telefone: "47 98888-7777" }, "to_phone") as { ok: false; erro: string };
  assertEquals(outro.ok, false);
  assertEquals(outro.erro,
    'Vieram client_id e to_phone, e eles apontam números diferentes: o cadastro de Cliente Inventado tem +55 (47) 99915-9654 e o to_phone é "47 98888-7777". ' +
    "Nada foi enviado. Mande só o client_id para usar o número do cadastro, ou só o to_phone para mandar a outro número.");
  // No agendamento o campo é `phone`, e a frase diz que nada foi agendado.
  const noAgendamento = await numeroDoEnvio(b.db, { client_id: "c1", telefone: "47 98888-7777" }, "phone") as { ok: false; erro: string };
  assertStringIncludes(noAgendamento.erro, "Vieram client_id e phone");
  assertStringIncludes(noAgendamento.erro, "Nada foi agendado. Mande só o client_id para usar o número do cadastro, ou só o phone para mandar a outro número.");
  // Número torto junto do client_id também é "outro": não some calado.
  assertEquals((await numeroDoEnvio(b.db, { client_id: "c1", telefone: "abc" }, "to_phone")).ok, false);
  // Mesmo DDD e mesmo final, outro DDD: é outro número.
  assertEquals((await numeroDoEnvio(b.db, { client_id: "c1", telefone: "11 99915-9654" }, "to_phone")).ok, false);
});

Deno.test("S1 número: cliente sem número e cliente que não existe são erro claro; leitura que falha LANÇA", async () => {
  const b = banco();
  const semNumero = await numeroDoEnvio(b.db, { client_id: "c2" }, "to_phone") as { ok: false; erro: string };
  assertEquals(semNumero.erro,
    "O cliente Sem Numero não tem WhatsApp nem telefone válido no cadastro. Nada foi enviado. " +
    "Peça o número ao usuário e mande só o to_phone (sem client_id), ou corrija o cadastro antes.");
  // Com um número junto, NÃO cai nele calado (era o que o agendamento fazia).
  assertEquals((await numeroDoEnvio(b.db, { client_id: "c2", telefone: "47 98888-7777" }, "phone")).ok, false);
  // Número do cadastro que não serve para mandar (curto demais).
  const curto = banco((t) => { t.clients[0].whatsapp = "9654"; t.clients[0].phone = null; });
  assertEquals((await numeroDoEnvio(curto.db, { client_id: "c1" }, "to_phone")).ok, false);

  const naoExiste = await numeroDoEnvio(b.db, { client_id: "c-que-nao-existe" }, "to_phone") as { ok: false; erro: string };
  assertStringIncludes(naoExiste.erro, 'Não achei cliente com o client_id "c-que-nao-existe" no cadastro. Nada foi enviado.');
  // O id que nem é uuid (o Postgres responde 22P02): não é falha do banco, é cliente que não existe.
  const idTorto = { from: () => { const q: any = { select: () => q, eq: () => q, maybeSingle: () => Promise.resolve({ data: null, error: { code: "22P02", message: "invalid input syntax for type uuid" } }) }; return q; } };
  assertStringIncludes((await numeroDoEnvio(idTorto, { client_id: "Fulano" }, "to_phone") as { erro: string }).erro, "Não achei cliente");

  await assertRejects(() => numeroDoEnvio(banco(undefined, { "select:clients": "banco fora" }).db, { client_id: "c1" }, "to_phone"), Error, "leitura do cliente falhou");
});

Deno.test("S1 número: no cartão, o destino que não fecha vira UMA linha de recusa; sem client_id o resumo segue como sempre", async () => {
  const b = banco();
  assertEquals(await recusaDoDestino(b.db, { telefone: "47 98888-7777" }, "to_phone"), null);
  assertEquals(await recusaDoDestino(b.db, { telefone: "123" }, "to_phone"), null, "o número dito é conferido antes do cartão (preValidar)");
  assertEquals(await recusaDoDestino(b.db, { client_id: "c1" }, "to_phone"), null);
  const linha = await recusaDoDestino(b.db, { client_id: "c1", telefone: "47 98888-7777" }, "to_phone");
  assert(linha && linha.startsWith("⚠️ Vieram client_id e to_phone") && !linha.includes("\n"), String(linha));
  assert(resumoQueRecusa("send_whatsapp_message", linha!), "é recusa ao modelo, não pendência");
  assert(resumoQueRecusa("schedule_whatsapp_message", linha!));
  // Nem deu para ler o cadastro: sem o número conferido não há cartão.
  const falhou = await recusaDoDestino(banco(undefined, { "select:clients": "banco fora" }).db, { client_id: "c1" }, "to_phone");
  assertEquals(falhou, FALHA_AO_CONFERIR_O_DESTINO);
  assert(resumoQueRecusa("send_whatsapp_message", falhou!));
});

// ─── send_whatsapp_message pelo executor do agente ──────────────────────────────────────────────

Deno.test("S1 mensagem livre: as duas ferramentas conferem o risco no servidor; o cálculo pelos argumentos continua como piso", () => {
  assertEquals(typeof enviar.riscoNoServidor, "function");
  assertEquals(typeof agendar.riscoNoServidor, "function");
  assertEquals(enviar.computeRisk!({ client_id: "c1" }), "high");
  assertEquals(enviar.computeRisk!({ to_phone: CLIENTE }), "medium", "pelos argumentos, to_phone ainda é só o sim: quem sobe é o servidor");
  assertEquals(agendar.computeRisk!({ service_order_id: "os-1", phone: FORNECEDOR }), "high");
  // E nenhuma das duas roda sozinha (S2).
  assert(NEVER_AUTONOMOUS.has("send_whatsapp_message") && NEVER_AUTONOMOUS.has("schedule_whatsapp_message"));
});

Deno.test("S1 mensagem livre: a fornecedor, texto neutro pede só o sim; com valor, data ou promessa pede PIN", async () => {
  const b = banco();
  const r = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: "47 98888-7777", message: NEUTRO } }, aVista(enviar, b.db));
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "medium");
  assert(!("risk_reason" in p));
  assertEquals(String(p.summary).includes("🔒"), false);
  assertStringIncludes(p.summary, "WhatsApp: +55 (47) 98888-7777");

  const casos: Array<[string, string]> = [
    ["Pode entregar o cabo amanhã? Pago R$ 350 no Pix.", "o texto cita valor e data"],
    ["Fechado por dois mil, pode separar.", "o texto cita valor"],
    ["Passo aí na sexta para pegar.", "o texto cita data"],
    ["Pode deixar que te mando o comprovante.", "o texto cita promessa"],
  ];
  for (const [mensagem, motivo] of casos) {
    const bb = banco();
    const rr = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: mensagem } }, aVista(enviar, bb.db));
    assertEquals(rr.proposal?.risk_level, "high", mensagem);
    assertEquals(pendencias(bb)[0].risk_reason, motivo, mensagem);
    assertEquals(ultimaLinha(pendencias(bb)[0].summary), `🔒 No WhatsApp, pede PIN: ${motivo}.`, mensagem);
  }
});

Deno.test("S1 mensagem livre: número de cliente por to_phone pede PIN (antes era só o sim); sem cadastro vale como cliente", async () => {
  const b = banco();
  // É o caminho que a descrição da ferramenta ensina para responder uma conversa: to_phone, sem client_id.
  const r = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: "5547999159654", message: NEUTRO } }, aVista(enviar, b.db));
  assertEquals(r.proposal?.risk_level, "high");
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "high", "é o risk_level gravado que cobra o PIN no sim");
  assertEquals(p.risk_reason, "vai a cliente");
  assertEquals(ultimaLinha(p.summary), "🔒 No WhatsApp, pede PIN: vai a cliente.");
  assertStringIncludes(p.summary, "Para: *Cliente Inventado* (cliente do cadastro)");
  assertEquals(p.payload, { to_phone: "5547999159654", message: NEUTRO }, "o pedido gravado não muda");

  const semCadastro = banco();
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: DESCONHECIDO, message: NEUTRO } }, aVista(enviar, semCadastro.db));
  assertEquals(pendencias(semCadastro)[0].risk_level, "high");
  assertEquals(ultimaLinha(pendencias(semCadastro)[0].summary), "🔒 No WhatsApp, pede PIN: o número não tem cadastro (vale como cliente).");

  // Equipe (favorecido ativo): só o sim com texto neutro.
  const equipe = banco();
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: TECNICO, message: NEUTRO } }, aVista(enviar, equipe.db));
  assertEquals(pendencias(equipe)[0].risk_level, "medium");
  // Quem saiu da equipe (favorecido inativo) é de fora: PIN.
  const saiu = banco((t) => { t.payees[0].active = false; });
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: TECNICO, message: NEUTRO } }, aVista(enviar, saiu.db));
  assertEquals(pendencias(saiu)[0].risk_level, "high");
});

Deno.test("S1 mensagem livre: número que é de cliente e de fornecedor vale o mais protegido; com client_id o cartão mostra o número do cadastro", async () => {
  const doisCadastros = banco((t) => { t.suppliers[0].phone = "47 99915-9654"; });
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: CLIENTE, message: NEUTRO } }, aVista(enviar, doisCadastros.db));
  assertEquals(pendencias(doisCadastros)[0].risk_level, "high");
  assertEquals(ultimaLinha(pendencias(doisCadastros)[0].summary), "🔒 No WhatsApp, pede PIN: o número é de cliente e de fornecedor (vale o mais protegido).");

  const b = banco();
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { client_id: "c1", message: "Seu orçamento ficou em R$ 350." } }, aVista(enviar, b.db));
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "high");
  assertStringIncludes(p.summary, "WhatsApp: +55 (47) 99915-9654");
  assertEquals(ultimaLinha(p.summary), "🔒 No WhatsApp, pede PIN: vai a cliente; o texto cita valor.");
  assertEquals(p.risk_reason, "vai a cliente; o texto cita valor");
});

Deno.test("S1 mensagem livre: leitura do cadastro que falha não vira 'só o sim': PIN, dizendo que não deu para conferir", async () => {
  // As cinco leituras de quemRecebe. `clients` entrou no laço no acabamento da leva A (24/11/2026): é a que diz que o
  // número é de cliente, e sem ela conferida o fornecedor do cadastro não pode valer "só o sim".
  for (const tabela of ["clients", "suppliers", "payees", "app_users", "parceiro_numeros"]) {
    const b = banco(undefined, { [`select:${tabela}`]: "banco fora" });
    await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, aVista(enviar, b.db));
    assertEquals(pendencias(b)[0].risk_level, "high", tabela);
    assertEquals(pendencias(b)[0].risk_reason, "não consegui conferir quem recebe", tabela);
    assertEquals(ultimaLinha(pendencias(b)[0].summary), "🔒 No WhatsApp, pede PIN: não consegui conferir quem recebe.", tabela);
  }
});

Deno.test("S1 mensagem livre: client_id com to_phone de OUTRO número é recusado antes do cartão, com o erro que ensina", async () => {
  const b = banco();
  // O pior caso: o modelo junta o client_id do cliente com o número de um fornecedor.
  const r = await executarChamadaDeTool(
    { name: "send_whatsapp_message", input: { client_id: "c1", to_phone: "47 98888-7777", message: NEUTRO } }, aVista(enviar, b.db));
  assertEquals(r.proposal, undefined);
  assertEquals(pendencias(b), []);
  const erro = String((r.toolResult as { error: string }).error);
  assertStringIncludes(erro, "apontam números diferentes");
  assertStringIncludes(erro, "Mande só o client_id para usar o número do cadastro, ou só o to_phone para mandar a outro número.");
  assertEquals((r.toolResult as { nada_registrado: boolean }).nada_registrado, true);

  // O MESMO número pelos dois: cartão normal, com PIN, mostrando o número do cadastro.
  const igual = banco();
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { client_id: "c1", to_phone: "(47) 9915-9654", message: NEUTRO } }, aVista(enviar, igual.db));
  assertEquals(pendencias(igual)[0].risk_level, "high");
  assertStringIncludes(pendencias(igual)[0].summary, "WhatsApp: +55 (47) 99915-9654");

  // Cliente sem número e cliente que não existe: recusa, sem cartão que "vai falhar".
  for (const [id, trecho] of [["c2", "não tem WhatsApp nem telefone válido no cadastro"], ["c-que-nao-existe", "Não achei cliente"]]) {
    const bb = banco();
    const rr = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { client_id: id, message: NEUTRO } }, aVista(enviar, bb.db));
    assertStringIncludes(String((rr.toolResult as { error: string }).error), trecho);
    assertEquals(pendencias(bb), [], id);
  }
  // Cadastro do cliente que não deu para ler: recusa, e não um cartão sem número.
  const fora = banco(undefined, { "select:clients": "banco fora" });
  const rf = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { client_id: "c1", message: NEUTRO } }, aVista(enviar, fora.db));
  assertStringIncludes(String((rf.toolResult as { error: string }).error), "Não consegui conferir o cadastro do cliente agora");
  assertEquals(pendencias(fora), []);
});

Deno.test("S1 mensagem livre: a liberação de autonomia não pula o sim nem o PIN; depois de ler um caso do retorno continua PIN", async () => {
  const liberada = { settings: { [autonomyKey("send_whatsapp_message")]: "auto", [autonomyKey("schedule_whatsapp_message")]: "auto" } };
  const b = banco();
  const { resultado: r, enviados } = await comEnvio(() =>
    executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, aVista(enviar, b.db, liberada)));
  assertEquals(r.executou, false);
  assertEquals(enviados, [], "nada sai sem o sim");
  assertEquals(pendencias(b).length, 1);

  // A exceção que já existia e fica (retorno F2): sessão que leu um caso sobe para PIN, sem a linha do motivo.
  const amarrada = banco();
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, aVista(enviar, amarrada.db, { sessaoAmarrada: true }));
  assertEquals(pendencias(amarrada)[0].risk_level, "high");
  assertEquals(String(pendencias(amarrada)[0].summary).includes("🔒"), false);
});

// ─── Revisão do pacote 1 (24/11/2026): cadastro feito na hora não troca o PIN pelo sim ──────────
// O que a revisão provou: número sem cadastro pedia PIN; depois de create_supplier com o mesmo número (risco baixo, roda
// direto, sem cartão), a MESMA mensagem nascia só com o "sim". Igual com update_supplier e com link_contact_to_entity
// num fornecedor sem telefone. Era de novo o modelo escolhendo o risco, agora por uma escrita calada, num turno só.
// O que se fixa: cadastro de fornecedor ou de favorecido criado ou alterado há menos de 24 horas não conta como
// fornecedor nem como equipe; o número segue valendo como cliente (PIN), com o motivo dito no cartão.

const criarFornecedor = purchasingTools.find((t) => t.name === "create_supplier")!;
const corrigirFornecedor = registryCrudTools.find((t) => t.name === "update_supplier")!;
const ligarContato = contactTools.find((t) => t.name === "link_contact_to_entity")!;
const MOTIVO_DO_RECENTE = "o cadastro deste número foi criado ou alterado há menos de 24 horas (vale como cliente)";
const horasAtras = (h: number) => new Date(Date.now() - h * 3600_000).toISOString();

/**
 * O que o banco de verdade faz e o falso não: created_at e updated_at = now() no insert (o padrão das colunas) e
 * updated_at = now() em todo update (gatilhos set_updated_at_suppliers e payees_updated_at, conferidos em produção).
 */
// deno-lint-ignore no-explicit-any
function comRelogioDoBanco<B extends { db: { from: (tabela: string) => any } }>(b: B): B {
  const from = b.db.from;
  const agora = () => new Date().toISOString();
  b.db.from = (tabela: string) => {
    const q = from(tabela);
    if (tabela !== "suppliers" && tabela !== "payees") return q;
    const { insert, update } = q;
    const carimbo = (l: Linha) => ({ created_at: agora(), updated_at: agora(), ...l });
    q.insert = (v: Linha | Linha[]) => insert(Array.isArray(v) ? v.map(carimbo) : carimbo(v));
    q.update = (v: Linha) => update({ ...v, updated_at: agora() });
    return q;
  };
  return b;
}

/** O turno com a mensagem livre, o agendamento e as três escritas de cadastro à vista (como no perfil do admin). */
function turno(db: unknown) {
  const tools = [enviar, agendar, criarFornecedor, corrigirFornecedor, ligarContato];
  return { ...aVista(enviar, db), toolsByName: Object.fromEntries(tools.map((t) => [t.name, t])) };
}

Deno.test("Revisão S1: cadastrar o número como fornecedor na hora não troca o PIN pelo sim (mensagem e agendamento)", async () => {
  const b = comRelogioDoBanco(banco());
  const amb = turno(b.db);
  // Antes do cadastro: número sem cadastro, PIN.
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: DESCONHECIDO, message: NEUTRO } }, amb);
  assertEquals(pendencias(b)[0].risk_reason, "o número não tem cadastro (vale como cliente)");

  // O cadastro roda direto, sem cartão (pedir o "sim" nessa escrita é decisão do dono: NOVO-p1-s1-04).
  const cadastro = await executarChamadaDeTool({ name: "create_supplier", input: { name: "João", phone: "11 95555-4444" } }, amb);
  assertEquals(cadastro.executou, true);
  assertEquals(pendencias(b).length, 1, "o cadastro não pede nada");
  assertEquals(b.tabelas.suppliers.length, 2);

  // A MESMA mensagem, no mesmo turno: continua PIN, e o cartão diz por quê.
  const r = await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: DESCONHECIDO, message: NEUTRO } }, amb);
  assertEquals(r.proposal?.risk_level, "high");
  const p = pendencias(b)[1];
  assertEquals(p.risk_level, "high", "é o risk_level gravado que cobra o PIN no sim");
  assertEquals(p.risk_reason, MOTIVO_DO_RECENTE);
  assertEquals(ultimaLinha(p.summary), `🔒 No WhatsApp, pede PIN: ${MOTIVO_DO_RECENTE}.`);

  // O agendamento usa a mesma conferência.
  await executarChamadaDeTool({ name: "schedule_whatsapp_message", input: { phone: "11 95555-4444", scheduled_at: QUANDO, message: NEUTRO } }, amb);
  assertEquals([pendencias(b)[2].risk_level, pendencias(b)[2].risk_reason], ["high", MOTIVO_DO_RECENTE]);

  // O fornecedor antigo (mais de 24 horas, sem mexer) segue só com o "sim".
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, amb);
  assertEquals(pendencias(b)[3].risk_level, "medium");
  assert(!("risk_reason" in pendencias(b)[3]));
});

Deno.test("Revisão S1: trocar o telefone de um fornecedor, ou ligar o número a um fornecedor sem telefone, também não troca o PIN pelo sim", async () => {
  // update_supplier: o número novo entra num cadastro antigo.
  const b = comRelogioDoBanco(banco());
  const amb = turno(b.db);
  const troca = await executarChamadaDeTool({ name: "update_supplier", input: { supplier_id: "s1", phone: "11 95555-4444" } }, amb);
  assertEquals(troca.executou, true);
  assertEquals(pendencias(b), [], "a troca roda direto, sem cartão");
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: DESCONHECIDO, message: NEUTRO } }, amb);
  assertEquals([pendencias(b)[0].risk_level, pendencias(b)[0].risk_reason], ["high", MOTIVO_DO_RECENTE]);
  assertEquals(ultimaLinha(pendencias(b)[0].summary), `🔒 No WhatsApp, pede PIN: ${MOTIVO_DO_RECENTE}.`);
  // O número antigo saiu do cadastro: é número sem cadastro.
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, amb);
  assertEquals(pendencias(b)[1].risk_reason, "o número não tem cadastro (vale como cliente)");

  // link_contact_to_entity: grava o número no fornecedor que não tinha telefone (risco baixo, roda direto).
  const semFone = comRelogioDoBanco(banco((t) => { t.suppliers.push({ id: "s2", name: "Fornecedor Sem Fone", phone: null, active: true, ...ANTIGO }); }));
  const amb2 = turno(semFone.db);
  const liga = await executarChamadaDeTool({ name: "link_contact_to_entity", input: { phone: DESCONHECIDO, supplier_id: "s2" } }, amb2);
  assertEquals(liga.executou, true);
  assertEquals((liga.toolResult as { numero_no_cadastro: string }).numero_no_cadastro, "gravado (phone)");
  assertEquals(pendencias(semFone), []);
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: DESCONHECIDO, message: NEUTRO } }, amb2);
  assertEquals([pendencias(semFone)[0].risk_level, pendencias(semFone)[0].risk_reason], ["high", MOTIVO_DO_RECENTE]);

  // Lado seguro conhecido: mexer em QUALQUER campo do fornecedor faz o número dele pedir PIN por 24 horas.
  const outroCampo = comRelogioDoBanco(banco());
  const amb3 = turno(outroCampo.db);
  await executarChamadaDeTool({ name: "update_supplier", input: { supplier_id: "s1", notes: "entrega às terças" } }, amb3);
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: FORNECEDOR, message: NEUTRO } }, amb3);
  assertEquals([pendencias(outroCampo)[0].risk_level, pendencias(outroCampo)[0].risk_reason], ["high", MOTIVO_DO_RECENTE]);
});

Deno.test("Revisão S1: o cadastro volta a valer só o sim depois de 24 horas; vale para fornecedor e para favorecido", async () => {
  const casos: Array<[string, (t: Record<string, Linha[]>) => void, string, "high" | "medium"]> = [
    ["fornecedor criado há 23 h", (t) => { Object.assign(t.suppliers[0], { created_at: horasAtras(23), updated_at: horasAtras(23) }); }, FORNECEDOR, "high"],
    ["fornecedor criado há 25 h", (t) => { Object.assign(t.suppliers[0], { created_at: horasAtras(25), updated_at: horasAtras(25) }); }, FORNECEDOR, "medium"],
    ["fornecedor antigo alterado há 1 h", (t) => { t.suppliers[0].updated_at = horasAtras(1); }, FORNECEDOR, "high"],
    ["favorecido criado há 2 h", (t) => { Object.assign(t.payees[0], { created_at: horasAtras(2), updated_at: horasAtras(2) }); }, TECNICO, "high"],
    ["favorecido antigo alterado há 2 h", (t) => { t.payees[0].updated_at = horasAtras(2); }, TECNICO, "high"],
    ["favorecido alterado há 25 h", (t) => { t.payees[0].updated_at = horasAtras(25); }, TECNICO, "medium"],
    // Sem as datas não dá para afirmar que o cadastro é antigo: PIN.
    ["fornecedor sem as datas", (t) => { t.suppliers[0] = { id: "s1", name: "Fornecedor Inventado", phone: "(47) 98888-7777", active: true }; }, FORNECEDOR, "high"],
  ];
  for (const [nome, muda, numero, risco] of casos) {
    const b = banco(muda);
    await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: numero, message: NEUTRO } }, aVista(enviar, b.db));
    assertEquals(pendencias(b)[0].risk_level, risco, nome);
    if (risco === "high") assertEquals(pendencias(b)[0].risk_reason, MOTIVO_DO_RECENTE, nome);
    else assert(!("risk_reason" in pendencias(b)[0]), nome);
  }
  // Número que também é de cliente: vale "vai a cliente", como sempre (o cadastro novo não muda o motivo).
  const cliente = banco((t) => { t.suppliers.push({ id: "s9", name: "Novo", phone: "47 99915-9654", created_at: horasAtras(1), updated_at: horasAtras(1) }); });
  await executarChamadaDeTool({ name: "send_whatsapp_message", input: { to_phone: CLIENTE, message: NEUTRO } }, aVista(enviar, cliente.db));
  assertEquals(pendencias(cliente)[0].risk_reason, "vai a cliente");
});

// ─── send_whatsapp_message: o envio depois do sim ───────────────────────────────────────────────

Deno.test("S1 envio: com client_id vai ao número do cadastro, normalizado; só com to_phone, ao número dito", async () => {
  const b = banco();
  const porId = await comEnvio(() => enviar.execute({ client_id: "c1", message: "Oi" }, ctxDe(b.db)));
  assertEquals(porId.enviados.map((c) => c.phone), [CLIENTE]);
  const iguais = await comEnvio(() => enviar.execute({ client_id: "c1", to_phone: "(47) 9915-9654", message: "Oi de novo" }, ctxDe(b.db)));
  assertEquals(iguais.enviados.map((c) => c.phone), [CLIENTE]);
  const porNumero = await comEnvio(() => enviar.execute({ to_phone: "47 98888-7777", message: "Oi" }, ctxDe(b.db)));
  assertEquals(porNumero.enviados.map((c) => c.phone), [FORNECEDOR]);
});

Deno.test("S1 envio: o que não fecha não sai (outro número junto do client_id, cliente sem número, cadastro que não leu)", async () => {
  const b = banco();
  // Antes: ia ao to_phone, e o cartão tinha mostrado o número do cadastro.
  const outro = await comEnvio(() => enviar.execute({ client_id: "c1", to_phone: "47 98888-7777", message: "Oi" }, ctxDe(b.db)));
  assertEquals(outro.enviados, []);
  assertStringIncludes(String((outro.resultado as { error: string }).error), "apontam números diferentes");
  assertEquals((outro.resultado as { nada_enviado: boolean }).nada_enviado, true);

  const semNumero = await comEnvio(() => enviar.execute({ client_id: "c2", message: "Oi" }, ctxDe(b.db)));
  assertEquals(semNumero.enviados, []);
  assertStringIncludes(String((semNumero.resultado as { error: string }).error), "não tem WhatsApp nem telefone válido");

  const fora = banco(undefined, { "select:clients": "banco fora" });
  const semLeitura = await comEnvio(() => enviar.execute({ client_id: "c1", message: "Oi" }, ctxDe(fora.db)));
  assertEquals(semLeitura.enviados, []);
  assertEquals(semLeitura.resultado, { error: "Não consegui conferir o cadastro do cliente agora. Nada foi enviado; tente de novo.", nada_enviado: true });
});

// ─── schedule_whatsapp_message ──────────────────────────────────────────────────────────────────

Deno.test("S1 agendamento: a mesma regra pelo número em `phone`: fornecedor neutro só o sim; cliente e conteúdo, PIN", async () => {
  const fornecedor = banco();
  await executarChamadaDeTool({ name: "schedule_whatsapp_message", input: { phone: "47 98888-7777", scheduled_at: QUANDO, message: NEUTRO } }, aVista(agendar, fornecedor.db));
  assertEquals(pendencias(fornecedor)[0].risk_level, "medium");
  assertEquals(String(pendencias(fornecedor)[0].summary).includes("🔒"), false);

  const comValor = banco();
  await executarChamadaDeTool(
    { name: "schedule_whatsapp_message", input: { phone: FORNECEDOR, scheduled_at: QUANDO, message: "Bom dia! Fechamos em R$ 1.200, pode faturar." } }, aVista(agendar, comValor.db));
  assertEquals(pendencias(comValor)[0].risk_level, "high");
  assertEquals(ultimaLinha(pendencias(comValor)[0].summary), "🔒 No WhatsApp, pede PIN: o texto cita valor.");

  const cliente = banco();
  await executarChamadaDeTool({ name: "schedule_whatsapp_message", input: { phone: "47 99915-9654", scheduled_at: QUANDO, message: NEUTRO } }, aVista(agendar, cliente.db));
  assertEquals(pendencias(cliente)[0].risk_level, "high");
  assertEquals(pendencias(cliente)[0].risk_reason, "vai a cliente");

  // Com OS (envio do link), o PIN vem do cálculo pelos argumentos, como sempre: o gancho não rebaixa.
  const comOs = banco();
  await executarChamadaDeTool(
    { name: "schedule_whatsapp_message", input: { phone: FORNECEDOR, scheduled_at: QUANDO, message: NEUTRO, service_order_id: "11111111-1111-4111-8111-111111111111" } },
    aVista(agendar, comOs.db));
  assertEquals(pendencias(comOs)[0].risk_level, "high");
});

Deno.test("S1 agendamento: client_id com phone de outro número é recusado antes do cartão; o mesmo número passa", async () => {
  const b = banco();
  const r = await executarChamadaDeTool(
    { name: "schedule_whatsapp_message", input: { client_id: "c1", phone: "47 98888-7777", scheduled_at: QUANDO, message: NEUTRO } }, aVista(agendar, b.db));
  assertEquals(pendencias(b), []);
  assertStringIncludes(String((r.toolResult as { error: string }).error), "Mande só o client_id para usar o número do cadastro, ou só o phone para mandar a outro número.");

  const igual = banco();
  await executarChamadaDeTool(
    { name: "schedule_whatsapp_message", input: { client_id: "c1", phone: "47 99915-9654", scheduled_at: QUANDO, message: NEUTRO } }, aVista(agendar, igual.db));
  assertEquals(pendencias(igual)[0].risk_level, "high");
  assertStringIncludes(pendencias(igual)[0].summary, "WhatsApp: +55 (47) 99915-9654");
});

Deno.test("S1 agendamento: grava o número do cadastro; cliente sem número NÃO cai calado no phone dos argumentos", async () => {
  const b = banco();
  const ok = await agendar.execute({ client_id: "c1", scheduled_at: QUANDO, message: "Bom dia!" }, ctxDe(b.db)) as Record<string, unknown>;
  assertEquals(ok.ok, true, JSON.stringify(ok));
  assertEquals(b.tabelas.whatsapp_scheduled_sends.map((s) => [s.phone, s.client_id]), [[CLIENTE, "c1"]]);

  // Antes: o cartão dizia "o agendamento será recusado" e o envio era gravado para o phone dos argumentos.
  const semNumero = banco();
  const r = await agendar.execute({ client_id: "c2", phone: "47 98888-7777", scheduled_at: QUANDO, message: "Bom dia!" }, ctxDe(semNumero.db)) as { error: string };
  assertStringIncludes(r.error, "não tem WhatsApp nem telefone válido no cadastro. Nada foi agendado.");
  assertEquals(semNumero.tabelas.whatsapp_scheduled_sends, []);

  const outro = banco();
  const r2 = await agendar.execute({ client_id: "c1", phone: "47 98888-7777", scheduled_at: QUANDO, message: "Bom dia!" }, ctxDe(outro.db)) as { error: string };
  assertStringIncludes(r2.error, "apontam números diferentes");
  assertEquals(outro.tabelas.whatsapp_scheduled_sends, []);

  const fora = banco(undefined, { "select:clients": "banco fora" });
  assertEquals(await agendar.execute({ client_id: "c1", scheduled_at: QUANDO, message: "Bom dia!" }, ctxDe(fora.db)),
    { error: "Não consegui conferir o cadastro do cliente agora. Nada foi agendado; tente de novo." });
  assertEquals(fora.tabelas.whatsapp_scheduled_sends, []);
});
