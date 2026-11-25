// Pacote 1 do assistente, S1 (24/11/2026): mensagem de texto livre pede PIN por QUEM RECEBE e pelo QUE O TEXTO DIZ.
//
// Regra do dono: PIN quando vai a cliente ou quando o texto cita valor, data ou promessa; para fornecedor e equipe só o
// "sim"; destinatário sem cadastro conta como cliente. Desde 25/11/2026 (cartão IA-19), a fornecedor, equipe e ao próprio
// dono o PIN é só quando o texto fala de dinheiro: data, hora, prazo e promessa saem com o "sim". O que se fixa aqui:
//   · quemRecebe: o número conferido contra os cadastros, em qualquer formato digitado, pelos 8 últimos dígitos;
//   · tudo o que não dá para conferir cai no PIN: leitura que falha, lista grande demais, número em dois cadastros,
//     equipe que saiu (inativa), número inválido;
//   · a regra pura (destino × conteúdo) com o texto exato que o dono lê no cartão;
//   · o conteúdo: as listas do validador do retorno, mais valor por extenso e data relativa;
//   · (cartão IA-20, 25/11/2026) fornecedor ativo e antigo cujo número também está no cadastro de clientes, sem
//     orçamento nem OS, conta só como fornecedor.
// Banco falso em memória (com o filtro ilike de verdade); dados inventados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/envio-livre_test.ts
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDaFraseDoAssistente, CADASTRO_FEITO_HA_POUCO, CADASTRO_RECENTE_MS, conteudoQuePedePin, CONTEUDO_PARA_FORNECEDOR_E_EQUIPE, type Destino,
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
 * Banco falso que FILTRA como o PostgREST: `.or("a.ilike.P,b.ilike.P")`, `.ilike(col, P)`, `.eq`, `.in`, `.limit`, e
 * devolve só as colunas do `.select()`. Guarda os filtros pedidos, para o teste conferir que a consulta não depende do
 * formato digitado, e os limites pedidos. `falhas[tabela]` = erro.
 */
function banco(tabelas: Record<string, Linha[]>, falhas: Record<string, string> = {}) {
  const consultas: Array<{ tabela: string; filtro: string }> = [];
  const limites: Array<{ tabela: string; limite: number }> = [];
  const db = {
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      let limite: number | null = null;
      let unico = false;
      let colunas: string[] | null = null;
      const executar = () => {
        if (falhas[tabela]) return { data: null, error: { message: falhas[tabela] } };
        let linhas = (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
        if (limite !== null) linhas = linhas.slice(0, limite);
        // Só as colunas pedidas voltam, como no PostgREST: coluna esquecida no .select() chega vazia à regra.
        const pedidas = colunas;
        if (pedidas) linhas = linhas.map((l) => Object.fromEntries(pedidas.filter((c) => c in l).map((c) => [c, l[c]])));
        return unico ? { data: linhas[0] ?? null, error: null } : { data: linhas, error: null };
      };
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: (lista?: string) => { colunas = lista && lista.trim() !== "*" ? lista.split(",").map((c) => c.trim()) : null; return q; },
        eq: (c: string, v: unknown) => { consultas.push({ tabela, filtro: `${c}=${v}` }); filtros.push((l) => l[c] === v); return q; },
        ilike: (c: string, p: string) => { consultas.push({ tabela, filtro: `${c}.ilike.${p}` }); filtros.push((l) => ilike(l[c], p)); return q; },
        or: (expr: string) => {
          consultas.push({ tabela, filtro: expr });
          const partes = expr.split(",").map((p) => { const [c, , ...resto] = p.split("."); return { c, p: resto.join(".") }; });
          filtros.push((l) => partes.some(({ c, p }) => ilike(l[c], p)));
          return q;
        },
        in: (c: string, vs: unknown[]) => { consultas.push({ tabela, filtro: `${c} in ${vs.join("|")}` }); filtros.push((l) => vs.includes(l[c])); return q; },
        limit: (n: number) => { limite = n; limites.push({ tabela, limite: n }); return q; },
        maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
        then: (ok: (v: unknown) => unknown, nao?: (e: unknown) => unknown) => Promise.resolve(executar()).then(ok, nao),
      };
      return q;
    },
  };
  return { db, consultas, limites };
}

const DONO = "dono-1";
const NUMERO = "5547999159654"; // como o WhatsApp manda: DDI + DDD + nono dígito

/**
 * As datas de um cadastro antigo, como o banco as devolve. Fornecedor e favorecido só contam com mais de 24 horas
 * (revisão do pacote 1): os dos casos abaixo nascem antigos, a não ser que a linha diga as próprias datas.
 */
const ANTIGO = { created_at: "2026-03-02T12:00:00.123456+00:00", updated_at: "2026-05-20T09:30:00.654321+00:00" };
const antigos = (linhas: Linha[] = []) => linhas.map((l) => ({ ...ANTIGO, ...l }));

/**
 * Os cadastros de cada caso; vazio = ninguém tem o número. O fornecedor nasce ATIVO, como a coluna suppliers.active em
 * produção (cartão IA-20), a não ser que a linha diga outra coisa. `service_orders` = os orçamentos e as OS.
 */
function cadastros(t: Partial<Record<"clients" | "suppliers" | "payees" | "app_users" | "parceiro_numeros" | "service_orders", Linha[]>> = {}) {
  return {
    clients: [], app_users: [], parceiro_numeros: [], service_orders: [], ...t,
    suppliers: antigos(t.suppliers).map((l) => ({ active: true, ...l })), payees: antigos(t.payees),
  } as Record<string, Linha[]>;
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
    // Cliente de verdade (tem orçamento): sem isto o fornecedor ativo o tiraria da lista (cartão IA-20, mais abaixo).
    service_orders: [{ id: "os-1", client_id: "c1", status: "orcamento" }],
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
  // Nem na leitura mais solta da regra (fornecedor e equipe sempre só o sim) o cadastro feito há pouco vale o sim.
  assertEquals(riscoDoEnvioLivrePorDestino(recente("sem_cadastro"), nada, "nada").risco, "high");
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

Deno.test("S1 regra: cliente, parceiro e sem cadastro pedem PIN com ou sem conteúdo; fornecedor, equipe e o próprio, só com dinheiro", () => {
  assertEquals(CONTEUDO_PARA_FORNECEDOR_E_EQUIPE, "dinheiro", "a leitura escolhida pelo dono em 25/11/2026 (cartão IA-19)");
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

Deno.test("S1 regra: o motivo junta só o que o texto cita (cliente, parceiro, sem cadastro e mais de um cadastro)", () => {
  const cita = (valor: boolean, data: boolean, promessa: boolean) => riscoDoEnvioLivrePorDestino(q("cliente"), { valor, data, promessa }).motivo;
  assertEquals(cita(true, true, false), "vai a cliente; o texto cita valor e data");
  assertEquals(cita(false, true, false), "vai a cliente; o texto cita data");
  assertEquals(cita(false, false, true), "vai a cliente; o texto cita promessa");
  assertEquals(cita(true, true, true), "vai a cliente; o texto cita valor, data e promessa");
  assertEquals(oQueCita(NADA), null);
  // Parceiro, número sem cadastro e número em mais de um cadastro: igual, depois do motivo do destino.
  const tudo = { valor: true, data: true, promessa: true };
  assertEquals(riscoDoEnvioLivrePorDestino(q("parceiro"), tudo).motivo, "o número é de parceiro; o texto cita valor, data e promessa");
  assertEquals(riscoDoEnvioLivrePorDestino(q("sem_cadastro"), { valor: false, data: true, promessa: true }).motivo,
    "o número não tem cadastro (vale como cliente); o texto cita data e promessa");
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor", "equipe"), { valor: false, data: true, promessa: false }).motivo,
    "o número é de fornecedor e da equipe (vale o mais protegido); o texto cita data");
});

// ─── IA-19 (25/11/2026): a fornecedor, equipe e ao próprio dono, PIN só pelo dinheiro ────────────
// A escolha do dono no cartão: "PIN só quando o texto fala de dinheiro (valor, Pix, pagamento). Data, horário e prazo
// saem só com o 'sim'. Exemplo: o aviso do horário ao Alex sai com 'sim'; 'fecha por R$ 4.200' ao fornecedor pede PIN".

const SO_O_SIM = { risco: "medium", motivo: null };
const PIN_PELO_VALOR = { risco: "high", motivo: "o texto cita valor" };
const DE_UM_SO: Destino[] = ["fornecedor", "equipe", "o_proprio"];

Deno.test("IA-19 regra: a fornecedor, equipe e ao próprio dono, data, hora, prazo e promessa sozinhos saem só com o sim", () => {
  const semDinheiro = [
    { valor: false, data: true, promessa: false },
    { valor: false, data: false, promessa: true },
    { valor: false, data: true, promessa: true },
  ];
  for (const destino of DE_UM_SO) {
    for (const conteudo of semDinheiro) {
      assertEquals(riscoDoEnvioLivrePorDestino(q(destino), conteudo), SO_O_SIM, `${destino} ${JSON.stringify(conteudo)}`);
    }
  }
  // Os outros destinos não mudaram: a mesma data pede PIN, com o motivo de antes.
  const comData = { valor: false, data: true, promessa: false };
  assertEquals(riscoDoEnvioLivrePorDestino(q("cliente"), comData), { risco: "high", motivo: "vai a cliente; o texto cita data" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("parceiro"), comData), { risco: "high", motivo: "o número é de parceiro; o texto cita data" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("sem_cadastro"), comData),
    { risco: "high", motivo: "o número não tem cadastro (vale como cliente); o texto cita data" });
});

Deno.test("IA-19 regra: com dinheiro no texto pede PIN, e o motivo diz só o que disparou (valor), sem data nem promessa", () => {
  const comDinheiro = [
    { valor: true, data: false, promessa: false },
    { valor: true, data: true, promessa: false },
    { valor: true, data: false, promessa: true },
    { valor: true, data: true, promessa: true },
  ];
  for (const destino of DE_UM_SO) {
    for (const conteudo of comDinheiro) {
      assertEquals(riscoDoEnvioLivrePorDestino(q(destino), conteudo), PIN_PELO_VALOR, `${destino} ${JSON.stringify(conteudo)}`);
    }
  }
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

Deno.test("S1 regra: as outras duas leituras (tudo, a de 24/11; nada) são uma palavra da constante; o lado do cliente não muda", () => {
  const comData = { valor: false, data: true, promessa: false };
  const comTudo = { valor: true, data: true, promessa: true };
  // "tudo": a regra de 24/11/2026, com o motivo de então.
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), comData, "tudo"), { risco: "high", motivo: "o texto cita data" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("equipe"), { valor: false, data: false, promessa: true }, "tudo"), { risco: "high", motivo: "o texto cita promessa" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("o_proprio"), comTudo, "tudo"), { risco: "high", motivo: "o texto cita valor, data e promessa" });
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), NADA, "tudo"), SO_O_SIM);
  // "nada": fornecedor e equipe sempre só o sim.
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), COM_VALOR, "nada"), SO_O_SIM);
  assertEquals(riscoDoEnvioLivrePorDestino(q("equipe"), comTudo, "nada"), SO_O_SIM);
  // "dinheiro" dito por extenso é o mesmo que não dizer nada (é o padrão).
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), comTudo, "dinheiro"), riscoDoEnvioLivrePorDestino(q("fornecedor"), comTudo));
  // Leitura que não existe vale a mais protegida ("tudo"), nunca só o sim.
  // deno-lint-ignore no-explicit-any
  assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor"), comData, "qualquer" as any), { risco: "high", motivo: "o texto cita data" });
  // Em nenhuma das três o lado do cliente muda.
  for (const leitura of ["dinheiro", "tudo", "nada"] as const) {
    assertEquals(riscoDoEnvioLivrePorDestino(q("cliente"), NADA, leitura), { risco: "high", motivo: "vai a cliente" }, leitura);
    assertEquals(riscoDoEnvioLivrePorDestino(q("cliente"), comData, leitura), { risco: "high", motivo: "vai a cliente; o texto cita data" }, leitura);
    assertEquals(riscoDoEnvioLivrePorDestino(q("sem_cadastro"), NADA, leitura).risco, "high", leitura);
    assertEquals(riscoDoEnvioLivrePorDestino(q("fornecedor", "equipe"), NADA, leitura).risco, "high", leitura);
  }
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

Deno.test("IA-19 conteúdo: pagamento falado sem número conta como valor (pagar, transferir, depositar)", () => {
  const comPagamento = [
    "já paguei", "Já pagamos, pode conferir.", "vou pagar", "o cliente pagou", "está pago", "a conta está paga", "estou pagando agora",
    "pagaremos na entrega", "pode pagar por mim?", "PAGO!", "transferência feita", "Transferencia feita", "vou transferir agora", "já transferi",
    "transfiro assim que chegar", "depósito feito", "depositei", "vou depositar", "faz o pix", "fecha por R$ 4.200",
  ];
  for (const t of comPagamento) assertEquals(conteudoQuePedePin(t).valor, true, t);
  // O pedido comum a fornecedor não fala de dinheiro, e palavra parecida não é pagamento.
  const semPagamento = [
    "Me manda o orçamento?", "Tem em estoque?", "Chega quando?", "Pode me passar a cotação das baterias?", "Confirma a entrega?", "Me manda a nota",
    "Pode apagar a luz do galpão", "Veja a página 2 do catálogo", "O pagode é sábado", "Tem como transportar a lancha?", "Recebi o comprovante, obrigado",
  ];
  for (const t of semPagamento) assertEquals(conteudoQuePedePin(t).valor, false, t);
  // Lado seguro conhecido: "depósito" de guardar peça também acusa.
  assertEquals(conteudoQuePedePin("Tem no depósito?").valor, true);
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
  // (IA-19) A fornecedor o motivo diz só o valor, mesmo com data no texto.
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: "Pode entregar o cabo amanhã? Pago R$ 350 no Pix." }, ctx(banco(fornecedor).db), "to_phone"),
    { risco: "high", motivo: "o texto cita valor" });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(cadastros()).db), "to_phone"),
    { risco: "high", motivo: "o número não tem cadastro (vale como cliente)" });
  // (Revisão) O mesmo fornecedor, cadastrado ou alterado agora: não vale o sim, e o motivo diz por quê.
  const feitoAgora = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654", created_at: new Date().toISOString(), updated_at: new Date().toISOString() }] });
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(feitoAgora).db), "to_phone"), { risco: "high", motivo: CADASTRO_FEITO_HA_POUCO });
  assertEquals(await riscoDaMensagemLivre({ phone: NUMERO, message: "Fechado por R$ 350." }, ctx(banco(feitoAgora).db), "phone"),
    { risco: "high", motivo: `${CADASTRO_FEITO_HA_POUCO}; o texto cita valor` });
});

Deno.test("IA-19 gancho: horário, data, prazo e promessa a fornecedor e à equipe saem só com o sim; dinheiro pede PIN e o motivo diz só valor", async () => {
  const fornecedor = cadastros({ suppliers: [{ id: "s1", phone: "(47) 99915-9654" }] });
  const usuario = cadastros({ app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: true }] });
  const favorecido = cadastros({ payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: null }] });
  const cliente = cadastros({ clients: [{ id: "c1", whatsapp: "(47) 99915-9654", phone: null }] });
  const risco = (tabelas: Record<string, Linha[]>, message: string) => riscoDaMensagemLivre({ to_phone: NUMERO, message }, ctx(banco(tabelas).db), "to_phone");

  // O aviso do horário ao técnico, o pedido de entrega ao fornecedor: nada de dinheiro, só o "sim".
  const semDinheiro = [
    "Alex, amanhã começamos às 8h na marina.",
    "Pode entregar na sexta?",
    "Preciso das baterias em 5 dias úteis.",
    "Pode deixar que eu te aviso quando o barco subir.",
    "Te mando a lista de material hoje à tarde.",
  ];
  for (const message of semDinheiro) {
    const c = conteudoQuePedePin(message);
    assert(c.data || c.promessa, `o texto tem de citar data ou promessa, senão o caso não prova nada: ${message}`);
    assertEquals(c.valor, false, message);
    for (const [nome, tabelas] of [["fornecedor", fornecedor], ["usuário da equipe", usuario], ["favorecido da equipe", favorecido]] as const) {
      assertEquals(await risco(tabelas, message), SO_O_SIM, `${nome}: ${message}`);
    }
    // A cliente a mesma mensagem continua pedindo PIN, com o motivo de antes.
    const aCliente = await risco(cliente, message);
    assertEquals(aCliente.risco, "high", message);
    assertEquals(aCliente.motivo, `vai a cliente; o texto cita ${oQueCita(c)}`, message);
  }
  assertEquals(await risco(cliente, "A descida do barco é na sexta às 10h."), { risco: "high", motivo: "vai a cliente; o texto cita data" });
  assertEquals(await risco(fornecedor, "A descida do barco é na sexta às 10h."), SO_O_SIM);

  // Dinheiro: valor escrito, Pix e pagamento falado. O motivo diz só o valor, mesmo com data ou promessa junto.
  const comDinheiro = [
    "Fecha por R$ 4.200?",
    "Já paguei, pode liberar.",
    "Faz o pix que eu confirmo.",
    "Transferência feita.",
    "Já paguei hoje cedo, te mando o comprovante.",
    "Deposito amanhã às 9h, pode deixar.",
  ];
  for (const message of comDinheiro) {
    for (const [nome, tabelas] of [["fornecedor", fornecedor], ["usuário da equipe", usuario], ["favorecido da equipe", favorecido]] as const) {
      assertEquals(await risco(tabelas, message), PIN_PELO_VALOR, `${nome}: ${message}`);
    }
  }
  assertEquals(await risco(cliente, "Já paguei hoje cedo, te mando o comprovante."), { risco: "high", motivo: "vai a cliente; o texto cita valor, data e promessa" });

  // O pedido comum a fornecedor segue só com o "sim".
  for (const message of ["Me manda o orçamento?", "Tem em estoque?", "Chega quando?"]) {
    assertEquals(await risco(fornecedor, message), SO_O_SIM, message);
  }
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

// ─── IA-20 (25/11/2026): fornecedor ativo que também está no cadastro de clientes ───────────────
// A escolha do dono no cartão: "Contar como fornecedor quando o cadastro de cliente desse número nunca teve orçamento nem
// OS. Os 26 passam a sair só com o 'sim'; se um deles virar cliente de verdade, volta a pedir PIN sozinho".
// Medido em produção em 25/11/2026 (só contagem): 26 números de fornecedor ativo também são de cliente, nenhum deles com
// orçamento ou OS; com fornecedor inativo são 307, 5 deles com orçamento ou OS (para esses nada muda).
// O que se fixa: as três condições juntas (fornecedor ativo e antigo; nenhum cadastro de cliente do número com linha em
// service_orders; envio sem client_id), a leitura nova só nesse caso, e o lado seguro quando ela falha.

const C1 = { id: "c1", whatsapp: "(47) 99915-9654", phone: null };
const S1 = { id: "s1", phone: "47 99915-9654", active: true };
const SO_FORNECEDOR = { telefone: NUMERO, destinos: ["fornecedor"] };
const CLIENTE_E_FORNECEDOR = { telefone: NUMERO, destinos: ["cliente", "fornecedor"] };
const PIN_DOS_DOIS_CADASTROS = { risco: "high", motivo: "o número é de cliente e de fornecedor (vale o mais protegido)" };
const leuOsOrcamentos = (b: { consultas: Array<{ tabela: string; filtro: string }> }) => b.consultas.filter((c) => c.tabela === "service_orders");
const noGancho = (tabelas: Record<string, Linha[]>, message = NEUTRO, falhas: Record<string, string> = {}) =>
  riscoDaMensagemLivre({ to_phone: NUMERO, message }, ctx(banco(tabelas, falhas).db), "to_phone");

Deno.test("IA-20 quem recebe: fornecedor ativo e antigo + cliente sem orçamento nem OS conta só como fornecedor", async () => {
  const b = banco(cadastros({ clients: [C1], suppliers: [S1] }));
  assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), SO_FORNECEDOR);
  // A pergunta ao banco: os orçamentos e as OS do cliente casado, sem filtro de status, e uma linha basta.
  assertEquals(leuOsOrcamentos(b), [{ tabela: "service_orders", filtro: "client_id in c1" }]);
  assertEquals(b.limites.filter((l) => l.tabela === "service_orders"), [{ tabela: "service_orders", limite: 1 }]);

  const variantes: Array<[string, Record<string, Linha[]>]> = [
    ["o número no telefone do cliente, sem o nono dígito", cadastros({ clients: [{ id: "c1", whatsapp: null, phone: "47 9915-9654" }], suppliers: [S1] })],
    ["cliente inativo", cadastros({ clients: [{ ...C1, active: false }], suppliers: [S1] })],
    ["o orçamento que existe é de OUTRO cliente", cadastros({ clients: [C1], suppliers: [S1], service_orders: [{ id: "os-9", client_id: "c9", status: "orcamento" }] })],
    ["dois fornecedores com o número, um inativo e um ativo", cadastros({ clients: [C1], suppliers: [{ id: "s0", phone: "(47) 99915-9654", active: false }, S1] })],
    ["o fornecedor ativo fez 24 horas agora", cadastros({ clients: [C1], suppliers: [{ ...S1, ...datas(ha(24)) }] })],
  ];
  for (const [nome, tabelas] of variantes) {
    assertEquals(await quemRecebe(banco(tabelas).db, NUMERO, { userId: DONO }, AGORA), SO_FORNECEDOR, nome);
  }

  // Daí em diante vale a regra do fornecedor (cartão IA-19): só o "sim", e PIN quando o texto fala de dinheiro.
  const t = cadastros({ clients: [C1], suppliers: [S1] });
  assertEquals(await noGancho(t), SO_O_SIM);
  assertEquals(await noGancho(t, "Amanhã começamos às 8h na marina."), SO_O_SIM);
  assertEquals(await noGancho(t, "Fecha por R$ 4.200?"), PIN_PELO_VALOR);
  assertEquals(await riscoDaMensagemLivre({ phone: "47 9915-9654", message: NEUTRO }, ctx(banco(t).db), "phone"), SO_O_SIM, "no agendamento também");
});

Deno.test("IA-20 quem recebe: com uma linha em service_orders, de qualquer status, o número continua de cliente e de fornecedor (PIN)", async () => {
  for (const status of ["orcamento", "rascunho", "cancelada", "concluida", null]) {
    const t = cadastros({ clients: [C1], suppliers: [S1], service_orders: [{ id: "os-1", client_id: "c1", status }] });
    assertEquals(await quemRecebe(banco(t).db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR, String(status));
    assertEquals(await noGancho(t), PIN_DOS_DOIS_CADASTROS, String(status));
  }
  // "Volta a pedir PIN sozinho": o mesmo cadastro, antes e depois do primeiro orçamento.
  const t = cadastros({ clients: [C1], suppliers: [S1] });
  assertEquals(await noGancho(t), SO_O_SIM);
  t.service_orders.push({ id: "os-1", client_id: "c1", status: "orcamento" });
  assertEquals(await noGancho(t), PIN_DOS_DOIS_CADASTROS);
  // Cliente com muitas OS: uma linha basta, e a leitura não esbarra no limite de conferência das outras listas.
  const muitas = Array.from({ length: LIMITE_POR_CADASTRO + 10 }, (_, i) => ({ id: `os-${i}`, client_id: "c1", status: "concluida" }));
  assertEquals(await quemRecebe(banco(cadastros({ clients: [C1], suppliers: [S1], service_orders: muitas })).db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR);
});

Deno.test("IA-20 quem recebe: dois cadastros de cliente com o número e um deles com orçamento ou OS: é cliente", async () => {
  const C2 = { id: "c2", whatsapp: null, phone: "(47) 9915-9654" };
  for (const dono of ["c1", "c2"]) {
    const b = banco(cadastros({ clients: [C1, C2], suppliers: [S1], service_orders: [{ id: "os-1", client_id: dono, status: "concluida" }] }));
    assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR, `o orçamento é do ${dono}`);
    assertEquals(leuOsOrcamentos(b), [{ tabela: "service_orders", filtro: "client_id in c1|c2" }], "pergunta pelos dois cadastros");
  }
  // Nenhum dos dois com orçamento nem OS: só fornecedor.
  assertEquals(await quemRecebe(banco(cadastros({ clients: [C1, C2], suppliers: [S1] })).db, NUMERO, { userId: DONO }, AGORA), SO_FORNECEDOR);
  // Cliente de número PARECIDO (o filtro do banco traz, a conferência linha a linha recusa): a OS dele não é deste número.
  const parecido = { id: "c3", whatsapp: "47 99159-6541", phone: null };
  const b = banco(cadastros({ clients: [C1, parecido], suppliers: [S1], service_orders: [{ id: "os-3", client_id: "c3", status: "concluida" }] }));
  assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), SO_FORNECEDOR);
  assertEquals(leuOsOrcamentos(b), [{ tabela: "service_orders", filtro: "client_id in c1" }]);
});

Deno.test("IA-20 quem recebe: fornecedor INATIVO que também é cliente continua valendo os dois, sem ler os orçamentos", async () => {
  // Só `true` é ativo: falso, vazio ou valor torto não solta o PIN.
  for (const active of [false, null, undefined, "true", 1]) {
    const t = cadastros({ clients: [C1], suppliers: [{ ...S1, active }] });
    const b = banco(t);
    assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR, String(active));
    assertEquals(leuOsOrcamentos(b), [], String(active));
    assertEquals(await noGancho(t), PIN_DOS_DOIS_CADASTROS, String(active));
  }
});

Deno.test("IA-20 quem recebe: fornecedor ativo criado ou alterado há menos de 24 horas não tira o cliente", async () => {
  const recentes: Array<[string, Linha]> = [
    ["criado há 1 hora", datas(ha(1))],
    ["antigo, alterado há 1 minuto", datas(ANTIGO.created_at, ha(0, 1))],
    ["criado há 23 h 59", datas(ha(23, 59))],
    ["sem as datas", datas(undefined)],
  ];
  for (const [nome, d] of recentes) {
    const b = banco(cadastros({ clients: [C1], suppliers: [{ ...S1, ...d }] }));
    assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), { telefone: NUMERO, destinos: ["cliente"], cadastroRecente: true }, nome);
    assertEquals(leuOsOrcamentos(b), [], nome);
  }
  // Pelo gancho, com o relógio de verdade: cadastrar o número de um cliente sem orçamento como fornecedor não solta o PIN.
  const feitoAgora = cadastros({ clients: [C1], suppliers: [{ ...S1, ...datas(new Date().toISOString()) }] });
  assertEquals(await noGancho(feitoAgora), { risco: "high", motivo: "vai a cliente" });
  // Um fornecedor ativo recente e outro antigo inativo: nenhum dos dois vale a condição; o inativo segue contando.
  const misturado = cadastros({ clients: [C1], suppliers: [{ ...S1, ...datas(ha(1)) }, { id: "s0", phone: "(47) 99915-9654", active: false }] });
  assertEquals(await quemRecebe(banco(misturado).db, NUMERO, { userId: DONO }, AGORA), { ...CLIENTE_E_FORNECEDOR, cadastroRecente: true });
});

Deno.test("IA-20 quem recebe: com client_id o envio continua sendo a cliente, sem ler os orçamentos", async () => {
  const t = cadastros({ clients: [{ ...C1, name: "Cliente Inventado" }], suppliers: [S1] });
  const b = banco(t);
  assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO, clienteId: "c1" }, AGORA), CLIENTE_E_FORNECEDOR);
  assertEquals(leuOsOrcamentos(b), []);
  // Pelo gancho: o MESMO número, por client_id pede PIN; só pelo número, vale o fornecedor.
  assertEquals(await riscoDaMensagemLivre({ client_id: "c1", message: NEUTRO }, ctx(banco(t).db), "to_phone"), PIN_DOS_DOIS_CADASTROS);
  assertEquals(await riscoDaMensagemLivre({ client_id: "c1", to_phone: NUMERO, message: NEUTRO }, ctx(banco(t).db), "to_phone"), PIN_DOS_DOIS_CADASTROS);
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(banco(t).db), "to_phone"), SO_O_SIM);
  // client_id vazio não é client_id (a mesma conta de numeroDoEnvio).
  for (const vazio of ["", null, undefined]) {
    assertEquals(await quemRecebe(banco(t).db, NUMERO, { userId: DONO, clienteId: vazio }, AGORA), SO_FORNECEDOR, String(vazio));
  }
});

Deno.test("IA-20 quem recebe: leitura dos orçamentos que falha LANÇA, e o gancho pede PIN dizendo que não conseguiu conferir", async () => {
  const t = cadastros({ clients: [C1], suppliers: [S1] });
  await assertRejects(() => quemRecebe(banco(t, { service_orders: "banco fora" }).db, NUMERO, { userId: DONO }, AGORA), Error, "leitura de orçamentos e ordens de serviço falhou");
  assertEquals(await noGancho(t, NEUTRO, { service_orders: "banco fora" }), { risco: "high", motivo: FALHA_AO_CONFERIR_QUEM_RECEBE });
  assertEquals(FALHA_AO_CONFERIR_QUEM_RECEBE, "não consegui conferir quem recebe");
  // Resposta que não é lista (banco torto só nessa tabela).
  const inteiro = banco(t).db;
  // deno-lint-ignore no-explicit-any
  const semLista: any = { select: () => semLista, in: () => semLista, eq: () => semLista, limit: () => Promise.resolve({ data: null, error: null }) };
  const torto = { from: (tabela: string) => (tabela === "service_orders" ? semLista : inteiro.from(tabela)) };
  await assertRejects(() => quemRecebe(torto, NUMERO, { userId: DONO }, AGORA), Error, "leitura de orçamentos e ordens de serviço sem resposta");
  assertEquals(await riscoDaMensagemLivre({ to_phone: NUMERO, message: NEUTRO }, ctx(torto), "to_phone"), { risco: "high", motivo: FALHA_AO_CONFERIR_QUEM_RECEBE });
  // Cadastro de cliente sem id legível: não dá para perguntar pelos orçamentos dele. Continua cliente, sem leitura.
  for (const id of [undefined, null, "", "   ", 7]) {
    const b = banco(cadastros({ clients: [{ ...C1, id }], suppliers: [S1] }));
    assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR, String(id));
    assertEquals(leuOsOrcamentos(b), [], String(id));
  }
  // Um cadastro com id e outro sem: também não dá para afirmar que nenhum tem orçamento.
  const umSemId = banco(cadastros({ clients: [C1, { id: null, whatsapp: "47 99915-9654", phone: null }], suppliers: [S1] }));
  assertEquals(await quemRecebe(umSemId.db, NUMERO, { userId: DONO }, AGORA), CLIENTE_E_FORNECEDOR);
});

Deno.test("IA-20 quem recebe: número só de cliente, sem orçamento nem OS, continua cliente; o caso comum não ganha leitura", async () => {
  const comuns: Array<[string, Record<string, Linha[]>, Destino[]]> = [
    ["só cliente, sem orçamento nem OS", cadastros({ clients: [C1] }), ["cliente"]],
    ["só cliente, com OS", cadastros({ clients: [C1], service_orders: [{ id: "os-1", client_id: "c1", status: "concluida" }] }), ["cliente"]],
    ["só fornecedor ativo", cadastros({ suppliers: [S1] }), ["fornecedor"]],
    ["só fornecedor inativo", cadastros({ suppliers: [{ ...S1, active: false }] }), ["fornecedor"]],
    ["ninguém", cadastros(), ["sem_cadastro"]],
    ["cliente sem orçamento que também é da equipe", cadastros({ clients: [C1], app_users: [{ id: "tec-1", phone: null, phone_normalized: "5547999159654", active: true }] }), ["cliente", "equipe"]],
    ["cliente sem orçamento que também é parceiro", cadastros({ clients: [C1], parceiro_numeros: [{ id: "n1", chave: "99159654" }] }), ["cliente", "parceiro"]],
  ];
  for (const [nome, tabelas, esperado] of comuns) {
    const b = banco(tabelas);
    assertEquals(await quemRecebe(b.db, NUMERO, { userId: DONO }, AGORA), { telefone: NUMERO, destinos: esperado }, nome);
    assertEquals(leuOsOrcamentos(b), [], nome);
  }
  assertEquals(await noGancho(cadastros({ clients: [C1] })), { risco: "high", motivo: "vai a cliente" });
});

Deno.test("IA-20 quem recebe: as outras regras seguem valendo sobre o que sobra (parceiro, equipe, o próprio)", async () => {
  const base = { clients: [C1], suppliers: [S1] };
  // Também parceiro: sobra parceiro e fornecedor, que é mais de um cadastro.
  const parceiro = cadastros({ ...base, parceiro_numeros: [{ id: "n1", chave: "99159654" }] });
  assertEquals((await quemRecebe(banco(parceiro).db, NUMERO, { userId: DONO }, AGORA)).destinos, ["parceiro", "fornecedor"]);
  assertEquals(await noGancho(parceiro), { risco: "high", motivo: "o número é de parceiro e de fornecedor (vale o mais protegido)" });
  // Também da equipe (em 24/11/2026, 1 dos 5 números da equipe era de cliente e de fornecedor): continua PIN.
  const equipe = cadastros({ ...base, payees: [{ id: "p1", phone: "47999159654", active: true, app_user_id: null }] });
  assertEquals((await quemRecebe(banco(equipe).db, NUMERO, { userId: DONO }, AGORA)).destinos, ["fornecedor", "equipe"]);
  assertEquals(await noGancho(equipe), { risco: "high", motivo: "o número é de fornecedor e da equipe (vale o mais protegido)" });
  // Também do próprio dono.
  const proprio = cadastros({ ...base, app_users: [{ id: DONO, phone: null, phone_normalized: "5547999159654", active: true }] });
  assertEquals((await quemRecebe(banco(proprio).db, NUMERO, { userId: DONO }, AGORA)).destinos, ["fornecedor", "o_proprio"]);
  assertEquals(await noGancho(proprio), { risco: "high", motivo: "o número é de fornecedor e seu (vale o mais protegido)" });
});
