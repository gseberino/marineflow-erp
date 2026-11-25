// Pacote 1 do assistente, S1 (24/11/2026): mensagem de texto livre pede PIN por QUEM RECEBE e pelo QUE O TEXTO DIZ.
//
// Regra do dono: PIN quando vai a cliente ou quando o texto cita valor, data ou promessa; para fornecedor e equipe só o
// "sim" (com valor, data ou promessa no texto, PIN); destinatário sem cadastro conta como cliente. O que se fixa aqui:
//   · quemRecebe: o número conferido contra os cadastros, em qualquer formato digitado, pelos 8 últimos dígitos;
//   · tudo o que não dá para conferir cai no PIN: leitura que falha, lista grande demais, número em dois cadastros,
//     equipe que saiu (inativa), número inválido;
//   · a regra pura (destino × conteúdo) com o texto exato que o dono lê no cartão;
//   · o conteúdo: as listas do validador do retorno, mais valor por extenso e data relativa.
// Banco falso em memória (com o filtro ilike de verdade); dados inventados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/envio-livre_test.ts
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDaFraseDoAssistente, CADASTRO_FEITO_HA_POUCO, CADASTRO_RECENTE_MS, conteudoQuePedePin, CONTEUDO_VALE_PARA_FORNECEDOR_E_EQUIPE, type Destino,
  FALHA_AO_CONFERIR_QUEM_RECEBE, LIMITE_POR_CADASTRO, NUMERO_QUE_NAO_FECHA, oQueCita, padraoDoNumero, quemRecebe, riscoDaMensagemLivre,
  riscoDoEnvioLivrePorDestino,
} from "./envio-livre.ts";
import { FALHA_AO_CONFERIR_O_RISCO } from "./agent.ts";

type Linha = Record<string, unknown>;

/** O ilike do Postgres: % = qualquer coisa; sem diferença de maiúscula. */
function ilike(valor: unknown, padrao: string): boolean {
  if (typeof valor !== "string") return false;
  const re = new RegExp(`^${padrao.split("%").map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`, "i");
  return re.test(valor);
}

/**
 * Banco falso que FILTRA como o PostgREST: `.or("a.ilike.P,b.ilike.P")`, `.ilike(col, P)`, `.eq`, `.limit`. Guarda os
 * filtros pedidos, para o teste conferir que a consulta não depende do formato digitado. `falhas[tabela]` = erro.
 */
function banco(tabelas: Record<string, Linha[]>, falhas: Record<string, string> = {}) {
  const consultas: Array<{ tabela: string; filtro: string }> = [];
  const db = {
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      let limite: number | null = null;
      let unico = false;
      const executar = () => {
        if (falhas[tabela]) return { data: null, error: { message: falhas[tabela] } };
        let linhas = (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
        if (limite !== null) linhas = linhas.slice(0, limite);
        return unico ? { data: linhas[0] ?? null, error: null } : { data: linhas, error: null };
      };
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { consultas.push({ tabela, filtro: `${c}=${v}` }); filtros.push((l) => l[c] === v); return q; },
        ilike: (c: string, p: string) => { consultas.push({ tabela, filtro: `${c}.ilike.${p}` }); filtros.push((l) => ilike(l[c], p)); return q; },
        or: (expr: string) => {
          consultas.push({ tabela, filtro: expr });
          const partes = expr.split(",").map((p) => { const [c, , ...resto] = p.split("."); return { c, p: resto.join(".") }; });
          filtros.push((l) => partes.some(({ c, p }) => ilike(l[c], p)));
          return q;
        },
        limit: (n: number) => { limite = n; return q; },
        maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
        then: (ok: (v: unknown) => unknown, nao?: (e: unknown) => unknown) => Promise.resolve(executar()).then(ok, nao),
      };
      return q;
    },
  };
  return { db, consultas };
}

const DONO = "dono-1";
const NUMERO = "5547999159654"; // como o WhatsApp manda: DDI + DDD + nono dígito

/**
 * As datas de um cadastro antigo, como o banco as devolve. Fornecedor e favorecido só contam com mais de 24 horas
 * (revisão do pacote 1): os dos casos abaixo nascem antigos, a não ser que a linha diga as próprias datas.
 */
const ANTIGO = { created_at: "2026-03-02T12:00:00.123456+00:00", updated_at: "2026-05-20T09:30:00.654321+00:00" };
const antigos = (linhas: Linha[] = []) => linhas.map((l) => ({ ...ANTIGO, ...l }));

/** Os cadastros de cada caso; vazio = ninguém tem o número. */
function cadastros(t: Partial<Record<"clients" | "suppliers" | "payees" | "app_users" | "parceiro_numeros", Linha[]>> = {}) {
  return { clients: [], app_users: [], parceiro_numeros: [], ...t, suppliers: antigos(t.suppliers), payees: antigos(t.payees) } as Record<string, Linha[]>;
}

// ─── quemRecebe ─────────────────────────────────────────────────────────────────────────────────

Deno.test("S1 quem recebe: cada cadastro dá o seu destino; sem cadastro nenhum = sem_cadastro", async () => {
  const casos: Array<[string, Record<string, Linha[]>, Destino[]]> = [
    ["cliente (WhatsApp)", cadastros({ clients: [{ id: "c1", whatsapp: "(47) 99915-9654", phone: null }] }), ["cliente"]],
    ["cliente (telefone)", cadastros({ clients: [{ id: "c1", whatsapp: null, phone: "47 99915-9654" }] }), ["cliente"]],
    ["fornecedor", cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] }), ["fornecedor"]],
    ["parceiro", cadastros({ parceiro_numeros: [{ id: "n1", chave: "99159654" }] }), ["parceiro"]],
    ["outro usuário ativo = equipe", cadastros({ app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: true }] }), ["equipe"]],
    ["o usuário que pede = o próprio", cadastros({ app_users: [{ id: DONO, phone: "47 99915-9654", phone_normalized: null, active: true }] }), ["o_proprio"]],
    ["favorecido ativo = equipe", cadastros({ payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: null }] }), ["equipe"]],
    ["favorecido que é o próprio dono", cadastros({ payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: DONO }] }), ["o_proprio"]],
    ["ninguém", cadastros(), ["sem_cadastro"]],
    // Quem saiu da equipe é de fora: usuário e favorecido INATIVOS não contam, e o número fica sem cadastro (PIN).
    ["usuário inativo", cadastros({ app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: false }] }), ["sem_cadastro"]],
    ["favorecido inativo", cadastros({ payees: [{ id: "p1", phone: "47999159654", active: false, app_user_id: null }] }), ["sem_cadastro"]],
    // Cliente inativo continua cliente: o lado protegido conta sempre.
    ["cliente inativo", cadastros({ clients: [{ id: "c1", whatsapp: "47999159654", phone: null, active: false }] }), ["cliente"]],
  ];
  for (const [nome, tabelas, esperado] of casos) {
    const q = await quemRecebe(banco(tabelas).db, NUMERO, { userId: DONO });
    assertEquals(q, { telefone: NUMERO, destinos: esperado }, nome);
  }
});

Deno.test("S1 quem recebe: casa o número em qualquer formato digitado, e sem o nono dígito", async () => {
  const formatos = ["(47) 99915-9654", "+55 47 99915-9654", "47 9915-9654", "4799159654", "47 9 9915 96 54", "+55 (47) 9.9915.9654", "5547999159654"];
  for (const formato of formatos) {
    const q = await quemRecebe(banco(cadastros({ clients: [{ id: "c1", whatsapp: formato, phone: null }] })).db, NUMERO, { userId: DONO });
    assertEquals(q.destinos, ["cliente"], formato);
    const f = await quemRecebe(banco(cadastros({ suppliers: [{ id: "s1", phone: formato }] })).db, "554799159654", { userId: DONO });
    assertEquals(f.destinos, ["fornecedor"], `${formato} (envio sem o nono dígito)`);
  }
  // Número parecido não casa: outro final, ou os mesmos dígitos no meio.
  const outros = cadastros({ clients: [{ id: "c1", whatsapp: "(47) 99915-9655", phone: "47 99159-6541" }], suppliers: [{ id: "s1", phone: "(11) 91599-6540" }] });
  assertEquals((await quemRecebe(banco(outros).db, NUMERO, { userId: DONO })).destinos, ["sem_cadastro"]);
});

Deno.test("S1 quem recebe: o filtro do banco é pelos 8 dígitos em ordem, e não depende de como o número foi digitado", async () => {
  assertEquals(padraoDoNumero("99159654"), "%9%9%1%5%9%6%5%4%");
  const b = banco(cadastros());
  await quemRecebe(b.db, NUMERO, { userId: DONO });
  const p = "%9%9%1%5%9%6%5%4%";
  assertEquals(b.consultas.sort((x, y) => x.tabela.localeCompare(y.tabela)), [
    { tabela: "app_users", filtro: `phone_normalized.ilike.${p},phone.ilike.${p}` },
    { tabela: "clients", filtro: `whatsapp.ilike.${p},phone.ilike.${p}` },
    { tabela: "parceiro_numeros", filtro: "chave=99159654" },
    { tabela: "payees", filtro: `phone.ilike.${p}` },
    { tabela: "suppliers", filtro: `phone.ilike.${p}` },
  ]);
});

Deno.test("S1 quem recebe: número em mais de um cadastro devolve todos, do mais protegido para o menos", async () => {
  const tudo = cadastros({
    clients: [{ id: "c1", whatsapp: "47 99915-9654", phone: null }],
    suppliers: [{ id: "s1", phone: "(47) 99915-9654" }],
    payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: null }],
    app_users: [{ id: DONO, phone: null, phone_normalized: "5547999159654", active: true }],
    parceiro_numeros: [{ id: "n1", chave: "99159654" }],
  });
  assertEquals((await quemRecebe(banco(tudo).db, NUMERO, { userId: DONO })).destinos, ["cliente", "parceiro", "fornecedor", "equipe", "o_proprio"]);
  // Técnico que também é favorecido: um destino só (equipe), não dois.
  const tecnico = cadastros({
    payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: "tec-1" }],
    app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: true }],
  });
  assertEquals((await quemRecebe(banco(tecnico).db, NUMERO, { userId: DONO })).destinos, ["equipe"]);
});

Deno.test("S1 quem recebe: com client_id é cliente mesmo sem achar o número, e os outros cadastros ainda contam", async () => {
  const soFornecedor = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] });
  assertEquals((await quemRecebe(banco(soFornecedor).db, NUMERO, { userId: DONO, clienteId: "c1" })).destinos, ["cliente", "fornecedor"]);
  assertEquals((await quemRecebe(banco(cadastros()).db, NUMERO, { userId: DONO, clienteId: "c1" })).destinos, ["cliente"]);
});

Deno.test("S1 quem recebe: sem número não há destino; leitura que falha e lista grande demais LANÇAM", async () => {
  assertEquals(await quemRecebe(banco(cadastros()).db, null, { userId: DONO }), { telefone: null, destinos: [] });
  assertEquals(await quemRecebe(banco(cadastros()).db, "1234", { userId: DONO }), { telefone: null, destinos: [] });
  for (const tabela of ["clients", "suppliers", "payees", "app_users", "parceiro_numeros"]) {
    await assertRejects(() => quemRecebe(banco(cadastros(), { [tabela]: "banco fora" }).db, NUMERO, { userId: DONO }), Error, "falhou", tabela);
  }
  // No limite não dá para afirmar que nenhuma linha é o número: lança (e o risco vai para o PIN).
  const muitos = Array.from({ length: LIMITE_POR_CADASTRO }, (_, i) => ({ id: `s${i}`, phone: "(47) 99915-9654" }));
  await assertRejects(() => quemRecebe(banco(cadastros({ suppliers: muitos })).db, NUMERO, { userId: DONO }), Error, "linhas demais");
  // Resposta que não é lista (banco torto) também.
  const torto = { from: () => { const q: any = { select: () => q, or: () => q, ilike: () => q, eq: () => q, limit: () => Promise.resolve({ data: null, error: null }) }; return q; } };
  await assertRejects(() => quemRecebe(torto, NUMERO, { userId: DONO }), Error, "sem resposta");
});

// ─── Revisão do pacote 1 (24/11/2026): cadastro feito há pouco não conta ────────────────────────
// A revisão provou que cadastrar o número como fornecedor (create_supplier, update_supplier: risco baixo, sem cartão)
// trocava o PIN pelo "sim" na mensagem seguinte. O que se fixa: fornecedor e favorecido criados ou alterados há menos
// de 24 horas são pulados; o que não dá para datar também; os outros cadastros do número contam como sempre.

const AGORA = new Date("2026-11-24T18:00:00Z");
const ha = (horas: number, minutos = 0) => new Date(AGORA.getTime() - horas * 3600_000 - minutos * 60_000).toISOString();
const datas = (criado: unknown, alterado: unknown = criado) => ({ created_at: criado, updated_at: alterado });
const RECENTE = { telefone: NUMERO, destinos: ["sem_cadastro"], cadastroRecente: true };

Deno.test("Revisão S1 quem recebe: fornecedor ou favorecido criado ou alterado há menos de 24 horas não conta", async () => {
  assertEquals(CADASTRO_RECENTE_MS, 24 * 3600_000, "a validade do cartão de confirmação");
  const fornecedor = (d: Linha) => cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654", ...d }] });
  const favorecido = (d: Linha, dono: string | null = null) => cadastros({ payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: dono, ...d }] });
  const casos: Array<[string, Record<string, Linha[]>, unknown]> = [
    ["fornecedor criado agora", fornecedor(datas(ha(0))), RECENTE],
    ["fornecedor criado há 23 h 59", fornecedor(datas(ha(23, 59))), RECENTE],
    ["fornecedor antigo, alterado há 1 minuto (telefone trocado)", fornecedor(datas(ANTIGO.created_at, ha(0, 1))), RECENTE],
    ["fornecedor criado há 24 h em ponto", fornecedor(datas(ha(24))), { telefone: NUMERO, destinos: ["fornecedor"] }],
    ["fornecedor criado e alterado há 25 h", fornecedor(datas(ha(30), ha(25))), { telefone: NUMERO, destinos: ["fornecedor"] }],
    ["as datas como o banco devolve (microssegundos e fuso)", fornecedor(datas("2026-11-23T17:59:59.999999+00:00")), { telefone: NUMERO, destinos: ["fornecedor"] }],
    ["a mesma hora noutro fuso", fornecedor(datas("2026-11-24T14:30:00-03:00")), RECENTE],
    ["favorecido criado há 2 h", favorecido(datas(ha(2))), RECENTE],
    ["favorecido antigo alterado há 2 h", favorecido(datas(ANTIGO.created_at, ha(2))), RECENTE],
    ["favorecido de quem pede, feito há 2 h (não vira 'o próprio')", favorecido(datas(ha(2)), DONO), RECENTE],
    ["favorecido alterado há 25 h", favorecido(datas(ANTIGO.created_at, ha(25))), { telefone: NUMERO, destinos: ["equipe"] }],
    // Sem data, data ilegível, data que não é texto ou data no futuro: não dá para afirmar que é antigo.
    ["fornecedor sem as datas", fornecedor(datas(undefined)), RECENTE],
    ["fornecedor sem a data da alteração", fornecedor(datas(ANTIGO.created_at, null)), RECENTE],
    ["fornecedor com data ilegível", fornecedor(datas("ontem")), RECENTE],
    ["fornecedor com data que não é texto", fornecedor(datas(1700000000000)), RECENTE],
    ["fornecedor com data no futuro", fornecedor(datas(ANTIGO.created_at, "2027-01-01T00:00:00Z")), RECENTE],
    // Favorecido inativo já não contava: continua "sem cadastro", sem falar em cadastro recente.
    ["favorecido inativo e recente", cadastros({ payees: [{ id: "p1", phone: "47999159654", active: false, app_user_id: null, ...datas(ha(1)) }] }),
      { telefone: NUMERO, destinos: ["sem_cadastro"] }],
    // Número parecido num cadastro recente não é este número.
    ["outro número num cadastro recente", cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9655", ...datas(ha(1)) }] }), { telefone: NUMERO, destinos: ["sem_cadastro"] }],
  ];
  for (const [nome, tabelas, esperado] of casos) {
    assertEquals(await quemRecebe(banco(tabelas).db, NUMERO, { userId: DONO }, AGORA), esperado, nome);
  }
});

Deno.test("Revisão S1 quem recebe: o cadastro recente é só pulado; os outros cadastros do número contam como sempre", async () => {
  const novo = { id: "s9", phone: "47 99915-9654", ...datas(ha(1)) };
  // Também é cliente: é cliente (o lado protegido conta sempre).
  const comCliente = cadastros({ clients: [{ id: "c1", whatsapp: "(47) 99915-9654", phone: null }], suppliers: [novo] });
  assertEquals(await quemRecebe(banco(comCliente).db, NUMERO, { userId: DONO }, AGORA), { telefone: NUMERO, destinos: ["cliente"], cadastroRecente: true });
  // Já era de um fornecedor antigo: o cadastro novo com o mesmo número não tira o "sim" do antigo.
  const comAntigo = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }, novo] });
  assertEquals(await quemRecebe(banco(comAntigo).db, NUMERO, { userId: DONO }, AGORA), { telefone: NUMERO, destinos: ["fornecedor"], cadastroRecente: true });
  // Usuário do sistema não entra na regra (o assistente não escreve em app_users): equipe, com ou sem data.
  const usuario = cadastros({ app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: true, ...datas(ha(1)) }], suppliers: [novo] });
  assertEquals(await quemRecebe(banco(usuario).db, NUMERO, { userId: DONO }, AGORA), { telefone: NUMERO, destinos: ["equipe"], cadastroRecente: true });
  // Sem a hora do teste vale o relógio: o cadastro de março é antigo, o de agora é recente.
  assertEquals((await quemRecebe(banco(cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] })).db, NUMERO, { userId: DONO })).destinos, ["fornecedor"]);
  const deAgora = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654", ...datas(new Date().toISOString()) }] });
  assertEquals(await quemRecebe(banco(deAgora).db, NUMERO, { userId: DONO }), RECENTE);
});

Deno.test("Revisão S1 regra: número só em cadastro feito há pouco pede PIN e o cartão diz por quê; com outro cadastro, vale o outro", () => {
  assertEquals(CADASTRO_FEITO_HA_POUCO, "o cadastro deste número foi criado ou alterado há menos de 24 horas (vale como cliente)");
  const recente = (...destinos: Destino[]) => ({ telefone: NUMERO, destinos, cadastroRecente: true });
  const nada = { valor: false, data: false, promessa: false };
  const comValor = { valor: true, data: false, promessa: false };
  assertEquals(riscoDoEnvioLivrePorDestino(recente("sem_cadastro"), nada), { risco: "high", motivo: CADASTRO_FEITO_HA_POUCO });
  assertEquals(riscoDoEnvioLivrePorDestino(recente("sem_cadastro"), comValor), { risco: "high", motivo: `${CADASTRO_FEITO_HA_POUCO}; o texto cita valor` });
  // Nem na outra leitura da regra (fornecedor e equipe sempre só o sim) o cadastro feito há pouco vale o sim.
  assertEquals(riscoDoEnvioLivrePorDestino(recente("sem_cadastro"), nada, false).risco, "high");
  // Sobrou outro cadastro: a regra é a dele.
  assertEquals(riscoDoEnvioLivrePorDestino(recente("cliente"), nada), { risco: "high", motivo: "vai a cliente" });
  assertEquals(riscoDoEnvioLivrePorDestino(recente("fornecedor"), nada), { risco: "medium", motivo: null });
  assertEquals(riscoDoEnvioLivrePorDestino(recente("cliente", "fornecedor"), nada).motivo, "o número é de cliente e de fornecedor (vale o mais protegido)");
  // Sem a marca, "sem cadastro" segue com a frase de sempre.
  assertEquals(riscoDoEnvioLivrePorDestino({ telefone: NUMERO, destinos: ["sem_cadastro"] }, nada).motivo, "o número não tem cadastro (vale como cliente)");
});

// ─── A regra pura: destino × conteúdo ───────────────────────────────────────────────────────────

const NADA = { valor: false, data: false, promessa: false };
const COM_VALOR = { valor: true, data: false, promessa: false };
const q = (...destinos: Destino[]) => ({ telefone: NUMERO, destinos });

Deno.test("S1 regra: cliente, parceiro e sem cadastro pedem PIN com ou sem conteúdo; fornecedor, equipe e o próprio, só com conteúdo", () => {
  assertEquals(CONTEUDO_VALE_PARA_FORNECEDOR_E_EQUIPE, true, "a leitura confirmada pelo dono em 24/11/2026");
  const tabela: Array<[Destino, typeof NADA, "high" | "medium", string | null]> = [
    ["cliente", NADA, "high", "vai a cliente"],
    ["cliente", COM_VALOR, "high", "vai a cliente; o texto cita valor"],
    ["parceiro", NADA, "high", "o número é de parceiro"],
    ["parceiro", COM_VALOR, "high", "o número é de parceiro; o texto cita valor"],
    ["sem_cadastro", NADA, "high", "o número não tem cadastro (vale como cliente)"],
    ["sem_cadastro", COM_VALOR, "high", "o número não tem cadastro (vale como cliente); o texto cita valor"],
    ["fornecedor", NADA, "medium", null],
    ["fornecedor", COM_VALOR, "high", "o texto cita valor"],
    ["equipe", NADA, "medium", null],
    ["equipe", COM_VALOR, "high", "o texto cita valor"],
    ["o_proprio", NADA, "medium", null],
    ["o_proprio", COM_VALOR, "high", "o texto cita valor"],
  ];
  for (const [destino, conteudo, risco, motivo] of tabela) {
    assertEquals(riscoDoEnvioLivrePorDestino(q(destino), conteudo), { risco, motivo }, `${destino} ${conteudo.valor ? "com" : "sem"} conteúdo`);
  }
});

Deno.test("S1 regra: o motivo junta só o que o texto cita", () => {
  const cita = (valor: boolean, data: boolean, promessa: boolean) => riscoDoEnvioLivrePorDestino(q("fornecedor"), { valor, data, promessa }).motivo;
  assertEquals(cita(true, true, false), "o texto cita valor e data");
  assertEquals(cita(false, true, false), "o texto cita data");
  assertEquals(cita(false, false, true), "o texto cita promessa");
  assertEquals(cita(true, true, true), "o texto cita valor, data e promessa");
  assertEquals(oQueCita(NADA), null);
});

Deno.test("S1 regra: número em mais de um cadastro pede PIN, mesmo sem cliente entre eles", () => {
  assertEquals(riscoDoEnvioLivrePorDestino(q("cliente", "fornecedor"), NADA),
    { risco: "high", motivo: "o número é de cliente e de fornecedor (vale o mais protegido)" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("cliente", "equipe"), COM_VALOR),
    { risco: "high", motivo: "o número é de cliente e da equipe (vale o mais protegido); o texto cita valor" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor", "equipe"), NADA),
    { risco: "high", motivo: "o número é de fornecedor e da equipe (vale o mais protegido)" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("cliente", "fornecedor", "o_proprio"), NADA).motivo,
    "o número é de cliente, de fornecedor e seu (vale o mais protegido)");
  // Destino repetido não é "mais de um cadastro".
  assertEquals(riscoDoEnvioLivrePorDestino(q("equipe", "equipe"), NADA), { risco: "medium", motivo: null });
});

Deno.test("S1 regra: sem número conferido ou sem destino nenhum = PIN", () => {
  assertEquals(riscoDoEnvioLivrePorDestino({ telefone: null, destinos: [] }, NADA), { risco: "high", motivo: NUMERO_QUE_NAO_FECHA });
  assertEquals(riscoDoEnvioLivrePorDestino({ telefone: null, destinos: ["fornecedor"] }, NADA).risco, "high");
  assertEquals(riscoDoEnvioLivrePorDestino({ telefone: NUMERO, destinos: [] }, NADA).risco, "high");
});

Deno.test("S1 regra: a outra leitura (fornecedor e equipe sempre só o sim) é uma constante; o lado do cliente não muda", () => {
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), COM_VALOR, false), { risco: "medium", motivo: null });
  assertEquals(riscoDoEnvioLivrePorDestino(q("equipe"), COM_VALOR, false), { risco: "medium", motivo: null });
  assertEquals(riscoDoEnvioLivrePorDestino(q("cliente"), NADA, false).risco, "high");
  assertEquals(riscoDoEnvioLivrePorDestino(q("sem_cadastro"), NADA, false).risco, "high");
});

// ─── O conteúdo ─────────────────────────────────────────────────────────────────────────────────

Deno.test("S1 conteúdo: valor em número, abreviado, por extenso e depois de verbo de preço", () => {
  const comValor = [
    "Fica R$ 350", "o total é 350,00", "uns 2 mil", "sai por 1,5 mil", "consigo por 2k", "dois mil e quinhentos", "trezentos cada",
    "o cabo sai 350", "custa 1200 a unidade", "faço por 300", "50 conto", "cinquenta conto", "paga no pix", "me passa o preço",
    "10% de desconto", "valor de 80", "cem reais", "mil e duzentos",
  ];
  for (const t of comValor) assertEquals(conteudoQuePedePin(t).valor, true, t);
  const semValor = ["Bom dia, tudo bem? Pode me mandar a foto da peça?", "O barco é o de 32 pés", "chegaram os 2 filtros", "milímetros de folga", "5 kg de cabo"];
  for (const t of semValor) assertEquals(conteudoQuePedePin(t).valor, false, t);
});

Deno.test("S1 conteúdo: data marcada e data relativa contam", () => {
  const comData = [
    "amanhã às 10h", "dia 12/12", "fica pronto sexta", "passo aí hoje", "na semana que vem", "próxima semana eu vejo", "até o dia 5",
    "em 5 dias úteis", "daqui a duas semanas", "depois de amanhã", "no fim do mês", "às 14:30", "em março", "segunda cedo",
  ];
  for (const t of comData) assertEquals(conteudoQuePedePin(t).data, true, t);
  const semData = ["Bom dia, tudo bem? Pode me mandar a foto da peça?", "Boa tarde! Recebi, obrigado.", "O dia foi corrido"];
  for (const t of semData) assertEquals(conteudoQuePedePin(t).data, false, t);
});

Deno.test("S1 conteúdo: promessa do validador e promessa do dono (te mando, vou enviar, deixa comigo)", () => {
  const comPromessa = ["te mando o orçamento", "Vou enviar a nota.", "deixa comigo", "pode deixar", "garanto que resolve", "fica pronto sexta", "assim que chegar te aviso"];
  for (const t of comPromessa) assertEquals(conteudoQuePedePin(t).promessa, true, t);
  const semPromessa = ["Bom dia, tudo bem? Pode me mandar a foto da peça?", "Você me manda a nota?", "Recebido, obrigado."];
  for (const t of semPromessa) assertEquals(conteudoQuePedePin(t).promessa, false, t);
});

Deno.test("S1 conteúdo: texto neutro não acusa nada; texto vazio ou estranho não lança; o que explode vale tudo", () => {
  assertEquals(conteudoQuePedePin("Bom dia, tudo bem? Pode me mandar a foto da peça?"), NADA);
  assertEquals(conteudoQuePedePin(""), NADA);
  assertEquals(conteudoQuePedePin(undefined), NADA);
  assertEquals(conteudoQuePedePin(null), NADA);
  assertEquals(conteudoQuePedePin(350).valor, false, "número solto não é valor (lacuna conhecida)");
  const explode = { toString() { throw new Error("texto que explode"); } };
  assertEquals(conteudoQuePedePin(explode), { valor: true, data: true, promessa: true });
});

Deno.test("S1 legenda do PDF/link: o aviso só aparece quando a frase do assistente cita algo", () => {
  // "antes de aprovar", e não "antes do PIN": o cartão aparece também no chat do app, onde a aprovação é por botão
  assertEquals(avisoDaFraseDoAssistente("Segue o orçamento, total de R$ 350."), "⚠️ A frase da legenda foi escrita pelo assistente e cita valor. Confira antes de aprovar.");
  assertEquals(avisoDaFraseDoAssistente("Válido até 30/11, R$ 350."), "⚠️ A frase da legenda foi escrita pelo assistente e cita valor e data. Confira antes de aprovar.");
  assertEquals(avisoDaFraseDoAssistente("Fica pronto sexta."), "⚠️ A frase da legenda foi escrita pelo assistente e cita data e promessa. Confira antes de aprovar.");
  assertEquals(String(avisoDaFraseDoAssistente("Total de R$ 350.")).includes("PIN"), false, "o aviso não fala em PIN");
  for (const neutra of ["Segue o orçamento.", "Bom dia! Conforme conversamos:", "", "   ", undefined, null, 42]) {
    assertEquals(avisoDaFraseDoAssistente(neutra), null, String(neutra));
  }
  // O link que a frase traz não é data (o código do compartilhamento tem números com traço); o resto da frase conta.
  const link = "https://erp.example/view/22222222-2222-4222-8222-222222222222";
  assertEquals(conteudoQuePedePin(link).data, true, "na mensagem livre o link segue contando (lado seguro)");
  assertEquals(avisoDaFraseDoAssistente(`Veja aqui: ${link} — qualquer dúvida me chama.`), null);
  assertEquals(avisoDaFraseDoAssistente(`Veja aqui: ${link} — vale até 30/11.`), "⚠️ A frase da legenda foi escrita pelo assistente e cita data. Confira antes de aprovar.");
});

// ─── O gancho das duas ferramentas ──────────────────────────────────────────────────────────────

const ctx = (db: unknown, userId = DONO) => ({ admin: db, userId });
const NEUTRO = "Bom dia! Pode me mandar a foto da peça?";

Deno.test("S1 gancho: decide pelo número que vai receber, não pelo argumento que o modelo escolheu", async () => {
  const cliente = cadastros({ clients: [{ id: "c1", name: "Cliente Inventado", whatsapp: "(47) 99915-9654", phone: null }] });
  // O MESMO cliente, pelos dois argumentos: o mesmo risco e o mesmo motivo.
  assertEquals(await riscoDaMensagemLivre({ to_phone: "47 99915-9654", message: NEUTRO }, ctx(banco(cliente).db), "to_phone"), { risco: "high", motivo: "vai a cliente" });
  assertEquals(await riscoDaMensagemLivre({ client_id: "c1", message: NEUTRO }, ctx(banco(cliente).db), "to_phone"), { risco: "high", motivo: "vai a cliente" });
  // No agendamento o número vem em `phone`.
  assertEquals(await riscoDaMensagemLivre({ phone: "47 99915-9654", message: NEUTRO }, ctx(banco(cliente).db), "phone"), { risco: "high", motivo: "vai a cliente" });

  const fornecedor = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(fornecedor).db), "to_phone"), { risco: "medium", motivo: null });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: "Pode entregar o cabo amanhã? Pago R$ 350 no Pix." }, ctx(banco(fornecedor).db), "to_phone"),
    { risco: "high", motivo: "o texto cita valor e data" });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(cadastros()).db), "to_phone"),
    { risco: "high", motivo: "o número não tem cadastro (vale como cliente)" });
  // (Revisão) O mesmo fornecedor, cadastrado ou alterado agora: não vale o sim, e o motivo diz por quê.
  const feitoAgora = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654", created_at: new Date().toISOString(), updated_at: new Date().toISOString() }] });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(feitoAgora).db), "to_phone"), { risco: "high", motivo: CADASTRO_FEITO_HA_POUCO });
  assertEquals(await riscoDaMensagemLivre({ phone: NUMERO, message: "Fechado por R$ 350." }, ctx(banco(feitoAgora).db), "phone"),
    { risco: "high", motivo: `${CADASTRO_FEITO_HA_POUCO}; o texto cita valor` });
});

Deno.test("S1 gancho: nunca lança e nunca devolve menos que o sim; o que não confere vale PIN", async () => {
  assertEquals(FALHA_AO_CONFERIR_QUEM_RECEBE, FALHA_AO_CONFERIR_O_RISCO, "uma frase só para a falha, aqui e no executor");
  const fornecedor = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] });
  // Uma leitura que falha (qualquer das cinco) derruba a conferência inteira: PIN.
  for (const tabela of ["clients", "suppliers", "payees", "app_users", "parceiro_numeros"]) {
    assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(fornecedor, { [tabela]: "banco fora" }).db), "to_phone"),
      { risco: "high", motivo: "não consegui conferir quem recebe" }, tabela);
  }
  // Banco que nem responde, contexto torto, argumentos estranhos.
  // deno-lint-ignore no-explicit-any
  assertEquals((await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, { admin: {}, userId: DONO } as any, "to_phone")).risco, "high");
  // deno-lint-ignore no-explicit-any
  assertEquals((await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, null as any, "to_phone")).risco, "high");
  for (const estranho of [undefined, null, {}, { to_phone: "123" }, { to_phone: "120363025246125483@g.us", message: "oi" }, { client_id: "c-que-nao-existe" }]) {
    // deno-lint-ignore no-explicit-any
    const r = await riscoDaMensagemLivre(estranho as any, ctx(banco(fornecedor).db), "to_phone");
    assertEquals(r.risco, "high", JSON.stringify(estranho));
    assert(r.motivo, JSON.stringify(estranho));
  }
  // Número inválido ou de grupo: sem número conferido, vale como cliente.
  assertEquals((await riscoDaMensagemLivre({ to_phone: "120363025246125483@g.us", message: NEUTRO }, ctx(banco(fornecedor).db), "to_phone")).motivo, NUMERO_QUE_NAO_FECHA);
});

Deno.test("S1 gancho: client_id com outro número junto, ou cliente sem número, não fecha: risco alto (e o cartão nem nasce)", async () => {
  const tabelas = cadastros({
    clients: [{ id: "c1", name: "Cliente Inventado", whatsapp: "(47) 99915-9654", phone: null }, { id: "c2", name: "Sem Numero", whatsapp: null, phone: null }],
    suppliers: [{ id: "s1", phone: "(47) 98888-7777" }],
  });
  // O modelo manda o client_id E o número de um fornecedor: não vale "fornecedor, só o sim".
  assertEquals(await riscoDaMensagemLivre({ client_id: "c1", to_phone: "47 98888-7777", message: NEUTRO }, ctx(banco(tabelas).db), "to_phone"),
    { risco: "high", motivo: NUMERO_QUE_NAO_FECHA });
  assertEquals((await riscoDaMensagemLivre({ client_id: "c2", message: NEUTRO }, ctx(banco(tabelas).db), "to_phone")).risco, "high");
  // Os dois apontando o MESMO número: é o cliente.
  assertEquals(await riscoDaMensagemLivre({ client_id: "c1", to_phone: "5547999159654", message: NEUTRO }, ctx(banco(tabelas).db), "to_phone"),
    { risco: "high", motivo: "vai a cliente" });
});
