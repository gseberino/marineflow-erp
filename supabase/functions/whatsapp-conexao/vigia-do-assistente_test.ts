// O vigia do assistente dentro do vigia da conexão (pacote 1, V1, 25/11/2026): a parte que lê e grava. Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/whatsapp-conexao/vigia-do-assistente_test.ts
//
// O que se protege, por ordem de gravidade:
//   1. O vigia da conexão do WhatsApp nunca quebra: chave ausente, tabela que ainda não existe, leitura que falha ou banco
//      que explode = as leituras novas devolvem "desligado" e a rodada termina sem lançar.
//   2. Em sombra NADA sai: nem sino, nem pergunta ao portão, nem linha na fila do WhatsApp. Só o histórico.
//   3. Ligado: o aviso sai uma vez por queda, só com o WhatsApp de pé, 15 minutos depois, e não sai se o dono já leu a
//      causa numa resposta de falha; a volta não repete o que o dono acabou de ver.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { EstadoDoMax, ProgramaDoPc } from "../_shared/ai/max/causa-da-falha.ts";
import { CHAVES_DOS_CONSUMIDORES, CHAVE_VOZ_UNICA } from "../_shared/uma-voz/portao.ts";
import type { RegistroDoVigia } from "./conexao.ts";
import {
  lerCausaDaQuedaDoWhatsApp, olharDoVigia, registrarQuedaDoWhatsApp, rodadaDoVigia, TELA_DO_ASSISTENTE, vigiarOAssistente,
} from "./vigia-do-assistente.ts";

// terça-feira, 24/11/2026, 09:35 em Brasília (dentro da janela do portão)
const T0 = new Date("2026-11-24T12:35:00Z");
const min = (m: number) => new Date(T0.getTime() + m * 60_000);
const iso = (m: number) => min(m).toISOString();
const FONE_DO_DONO = "5547900000001";

const NO_AR: EstadoDoMax = { ultimoSinal: iso(0), semSinal: false, pausa: null, ocupado: false, pcComSinal: true };
const estado = (p: Partial<EstadoDoMax> = {}): EstadoDoMax => ({ ...NO_AR, ...p });
const LOGIN = estado({ pausa: { motivo: "auth_failed", ate: null } });
const CALADO = estado({ semSinal: true, ultimoSinal: iso(-10), pcComSinal: true });

const ABERTO: RegistroDoVigia = { estado: "open", desde: iso(-600), avisado_em: null };

type Linha = Record<string, unknown>;
interface Op {
  tabela: string;
  acao: "select" | "insert" | "update";
  colunas: string | null;
  // deno-lint-ignore no-explicit-any
  valores: any;
  filtros: Array<[string, string, unknown]>;
  cabeca: boolean;
  ordem: [string, boolean] | null;
  limite: number | null;
}

interface Cenario {
  /** app_settings.vigia_assistente: valor, null (a chave não existe) ou "erro" */
  chave?: string | null | "erro";
  programas?: ProgramaDoPc[] | "erro";
  /** as linhas de assistente_quedas no começo */
  quedas?: Linha[];
  /** assistente_quedas ainda não existe (deploy antes da migration) */
  semTabela?: boolean;
  /** todo acesso ao banco lança */
  explode?: boolean;
  jobs?: Array<{ completed_at: string; requested_by: string | null }> | "erro";
  /** linhas de app_error_logs que casam com a consulta do "dono já soube" */
  falhas?: number | "erro";
  vozUnica?: "ligado" | "sombra" | "desligado";
  // deno-lint-ignore no-explicit-any
  portao?: (p: any) => Record<string, unknown> | null;
  situacaoDoAviso?: string;
  /** o relógio do banco (default de criado_em) */
  relogio?: string;
}

/** Um banco de mentira: assistente_quedas em memória (com o índice de uma aberta por tipo) e o resto com resposta pronta. */
function banco(c: Cenario = {}) {
  const quedas: Linha[] = (c.quedas ?? []).map((q) => ({ ...q }));
  const ops: Op[] = [];
  // deno-lint-ignore no-explicit-any
  const rpcs: Array<{ nome: string; p: any }> = [];
  let seq = 0;

  const casa = (l: Linha, filtros: Op["filtros"]) =>
    filtros.every(([op, col, v]) => {
      const x = l[col];
      if (op === "eq") return x === v;
      if (op === "in") return (v as unknown[]).includes(x);
      if (op === "is") return v === null ? x === null || x === undefined : x === v;
      if (op === "gt") return typeof x === "string" && Date.parse(x) > Date.parse(String(v));
      if (op === "gte") return typeof x === "string" && Date.parse(x) >= Date.parse(String(v));
      return true;
    });

  function executar(op: Op): { data: unknown; error: unknown; count?: number } {
    ops.push(op);
    const ok = (data: unknown) => ({ data, error: null });
    switch (op.tabela) {
      case "assistente_quedas": {
        if (c.semTabela) return { data: null, error: { code: "42P01", message: 'relation "public.assistente_quedas" does not exist' } };
        if (op.acao === "insert") {
          const nova: Linha = {
            id: `q${++seq}`, detalhe: null, ate: null, fechada_por: null, dono_soube: null, avisado_em: null, avisado_por: null, aviso_id: null,
            volta_avisada_em: null, visto_em: c.relogio ?? iso(0), criado_em: c.relogio ?? iso(0), ...op.valores,
          };
          if (nova.ate === null && quedas.some((q) => q.tipo === nova.tipo && q.ate === null)) {
            return { data: null, error: { code: "23505", message: "duplicate key value violates unique constraint" } };
          }
          quedas.push(nova);
          return ok(null);
        }
        const achadas = quedas.filter((q) => casa(q, op.filtros));
        if (op.acao === "update") {
          for (const q of achadas) Object.assign(q, op.valores);
          return ok(achadas.map((q) => ({ id: q.id })));
        }
        if (op.cabeca) return { data: null, error: null, count: achadas.length };
        const ordenadas = op.ordem
          ? [...achadas].sort((a, b) => (op.ordem![1] ? 1 : -1) * String(a[op.ordem![0]]).localeCompare(String(b[op.ordem![0]])))
          : achadas;
        return ok(ordenadas.slice(0, op.limite ?? ordenadas.length).map((q) => ({ ...q })));
      }
      case "app_settings": {
        if (op.filtros.some(([o, col, v]) => o === "eq" && col === "key" && v === "vigia_assistente")) {
          if (c.chave === "erro") return { data: null, error: { message: "permission denied" } };
          return ok(c.chave === undefined || c.chave === null ? null : { value: c.chave });
        }
        // as chaves do portão (lerPortao): a voz única ligada de verdade pede a manhã nova e o fechamento ligado
        return ok([
          { key: CHAVE_VOZ_UNICA, value: c.vozUnica ?? "ligado" },
          { key: CHAVES_DOS_CONSUMIDORES[0], value: "novo" },
          { key: CHAVES_DOS_CONSUMIDORES[1], value: "ligado" },
        ]);
      }
      case "ai_gateway_workers":
        return c.programas === "erro" ? { data: null, error: { message: "x" } } : ok(c.programas ?? []);
      case "ai_jobs": {
        if (c.jobs === "erro") return { data: null, error: { message: "x" } };
        const bons = (c.jobs ?? []).filter((j) => casa(j, op.filtros.filter(([o]) => o === "gt")))
          .sort((a, b) => b.completed_at.localeCompare(a.completed_at));
        return ok(bons.slice(0, op.limite ?? bons.length));
      }
      case "app_error_logs":
        return c.falhas === "erro" ? { data: null, error: { message: "x" } } : ok(Array.from({ length: Math.min(c.falhas ?? 0, op.limite ?? 99) }, () => ({ id: "e" })));
      case "app_users":
        return ok(op.colunas === "id" ? [{ id: "dono-1" }, { id: "admin-2" }] : [{ id: "dono-1", phone_normalized: FONE_DO_DONO }]);
      case "avisos_do_dono":
        return ok({ situacao: c.situacaoDoAviso ?? "acordou" });
      default:
        return ok(null); // app_notifications e whatsapp_send_queue: só anotam
    }
  }

  const db = {
    from(tabela: string) {
      if (c.explode) throw new Error("sem banco");
      const op: Op = { tabela, acao: "select", colunas: null, valores: null, filtros: [], cabeca: false, ordem: null, limite: null };
      const filtro = (nome: string) => (col: string, v: unknown) => { op.filtros.push([nome, col, v]); return q; };
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select(col: string, o?: { head?: boolean }) { if (op.acao === "select") { op.colunas = col; op.cabeca = !!o?.head; } return q; },
        insert(v: unknown) { op.acao = "insert"; op.valores = v; return q; },
        update(v: unknown) { op.acao = "update"; op.valores = v; return q; },
        eq: filtro("eq"), in: filtro("in"), is: filtro("is"), gt: filtro("gt"), gte: filtro("gte"), like: filtro("like"),
        not(col: string, _o: string, v: unknown) { op.filtros.push(["not", col, v]); return q; },
        order(col: string, o?: { ascending?: boolean }) { op.ordem = [col, o?.ascending !== false]; return q; },
        limit(n: number) { op.limite = n; return q; },
        maybeSingle() { return Promise.resolve().then(() => executar(op)); },
        // deno-lint-ignore no-explicit-any
        then(aoResolver: any, aoFalhar: any) { return Promise.resolve().then(() => executar(op)).then(aoResolver, aoFalhar); },
      };
      return q;
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      if (c.explode) return Promise.reject(new Error("sem banco"));
      rpcs.push({ nome, p: args?.p ?? args });
      if (nome === "aviso_registrar") {
        return Promise.resolve({ data: c.portao ? c.portao(args.p) : { ok: true, decisao: "acordar", situacao: "acordou", id: "aviso-1" }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };

  return {
    db, ops, rpcs, quedas,
    sinos: () => ops.filter((o) => o.tabela === "app_notifications" && o.acao === "insert"),
    fila: () => ops.filter((o) => o.tabela === "whatsapp_send_queue" && o.acao === "insert"),
    perguntas: () => rpcs.filter((r) => r.nome === "aviso_registrar"),
    erros: () => rpcs.filter((r) => r.nome === "log_app_error"),
    leu: (tabela: string) => ops.some((o) => o.tabela === tabela),
    gravacoes: () => ops.filter((o) => o.acao !== "select").map((o) => `${o.tabela}:${o.acao}`),
  };
}

/** Uma queda do assistente já gravada (aberta). */
function queda(p: Linha = {}): Linha {
  return {
    id: "q-aberta", tipo: "claude", causa: "login", detalhe: "auth_failed", desde: iso(0), visto_em: iso(0), criado_em: iso(0), ate: null,
    fechada_por: null, dono_soube: null, avisado_em: null, avisado_por: null, aviso_id: null, volta_avisada_em: null, ...p,
  };
}

// ─── 1. O vigia da conexão nunca quebra ──────────────────────────────────────────────────────────────────────────────

Deno.test("olhar: chave ausente ou 'desligado' = desligado, e os programas do PC nem são lidos", async () => {
  for (const chave of [undefined, null, "desligado", "", "qualquer"]) {
    const b = banco({ chave });
    assertEquals(await olharDoVigia(b.db, T0), { modo: "desligado", pc: null }, String(chave));
    assert(!b.leu("ai_gateway_workers"), "não lê os programas do PC");
    assert(!b.leu("assistente_quedas"));
    assertEquals(b.gravacoes(), []);
  }
});

Deno.test("olhar: leitura da chave que falha, ou banco que explode = desligado, sem lançar", async () => {
  assertEquals(await olharDoVigia(banco({ chave: "erro" }).db, T0), { modo: "desligado", pc: null });
  assertEquals(await olharDoVigia(banco({ chave: "ligado", explode: true }).db, T0), { modo: "desligado", pc: null });
});

Deno.test("olhar: sombra e ligado leem os programas do PC com o corte de 180 s; leitura que falha = sem estado (nada se conclui)", async () => {
  const programas: ProgramaDoPc[] = [
    { id: "hbr-pc-1", last_seen_at: iso(-2), estado: { providers: { "claude-local": { available: true } } } }, // 120 s: ainda não é queda
  ];
  const b = banco({ chave: "sombra", programas });
  const o = await olharDoVigia(b.db, T0);
  assertEquals([o.modo, o.pc?.semSinal, o.pc?.pcComSinal], ["sombra", false, true]);
  const leitura = b.ops.find((x) => x.tabela === "ai_gateway_workers")!;
  assertEquals(leitura.colunas, "id, last_seen_at, estado", "nunca o token_hash");
  const calado = await olharDoVigia(banco({ chave: "ligado", programas: [{ ...programas[0], last_seen_at: iso(-4) }] }).db, T0);
  assertEquals([calado.modo, calado.pc?.semSinal], ["ligado", true]);
  assertEquals(await olharDoVigia(banco({ chave: "sombra", programas: "erro" }).db, T0), { modo: "sombra", pc: null });
});

Deno.test("tabela que ainda não existe (deploy antes da migration): a rodada termina sem lançar, anota o erro e não manda nada", async () => {
  for (const modo of ["sombra", "ligado"] as const) {
    for (const aviso of ["caiu", "voltou", null] as const) {
      const b = banco({ semTabela: true });
      const registro: RegistroDoVigia = aviso === "caiu" ? { estado: "inacessivel", desde: iso(-10), avisado_em: iso(0) } : ABERTO;
      const r = await rodadaDoVigia(b.db, { modo, pc: LOGIN, aviso, registro, agora: T0 });
      assertEquals(r.erro, true, `${modo}/${aviso}`);
      assertEquals([r.whatsapp, r.assistente], [null, "nada"]);
      assert(b.erros().length >= 1, "o erro vai para app_error_logs");
      assert(b.erros().every((e) => e.p.p_context === "whatsapp-conexao" && e.p.p_action === "vigiar_assistente"));
      assertEquals([b.sinos().length, b.fila().length, b.perguntas().length], [0, 0, 0], "nada sai para ninguém");
    }
  }
  assertEquals(await lerCausaDaQuedaDoWhatsApp(banco({ semTabela: true }).db), null);
});

Deno.test("banco que explode em toda chamada: a rodada e a leitura da causa não lançam", async () => {
  const b = banco({ explode: true });
  const r = await rodadaDoVigia(b.db, { modo: "ligado", pc: LOGIN, aviso: "caiu", registro: { estado: "inacessivel", desde: iso(-10), avisado_em: iso(0) }, agora: T0 });
  assertEquals([r.erro, r.whatsapp, r.assistente], [true, null, "nada"]);
  assertEquals(await lerCausaDaQuedaDoWhatsApp(b.db), null);
});

Deno.test("sem o estado dos programas do PC (a leitura falhou): não abre, não fecha e não avisa", async () => {
  const b = banco({ quedas: [queda({ criado_em: iso(-30) })] });
  const r = await rodadaDoVigia(b.db, { modo: "ligado", pc: null, aviso: null, registro: ABERTO, agora: T0 });
  assertEquals([r.assistente, r.erro], ["sem_leitura", undefined]);
  assertEquals(b.gravacoes(), []);
});

// ─── 2. Em sombra nada sai ───────────────────────────────────────────────────────────────────────────────────────────

Deno.test("sombra: grava a queda do assistente, mantém, fecha — e nunca toca o sino, o portão nem a fila", async () => {
  const b = banco({ relogio: iso(0) });
  // 09:35 o login caiu: abre
  let r = await rodadaDoVigia(b.db, { modo: "sombra", pc: LOGIN, aviso: null, registro: ABERTO, agora: T0 });
  assertEquals(r, { modo: "sombra", whatsapp: null, assistente: "abriu" });
  assertEquals(b.quedas.map((q) => [q.tipo, q.causa, q.detalhe, q.desde, q.ate]), [["claude", "login", "auth_failed", iso(0), null]]);
  // 09:40 ainda em pausa: marca que viu
  r = await rodadaDoVigia(b.db, { modo: "sombra", pc: LOGIN, aviso: null, registro: ABERTO, agora: min(5) });
  assertEquals([r.assistente, b.quedas[0].visto_em], ["mantida", iso(5)]);
  // 10:00, 25 minutos de queda, a pausa já venceu: em sombra, nem assim avisa (e nem lê o registro de falhas)
  r = await rodadaDoVigia(b.db, { modo: "sombra", pc: NO_AR, aviso: null, registro: ABERTO, agora: min(25) });
  assertEquals([r.assistente, r.avisou, b.quedas[0].ate, b.quedas[0].dono_soube], ["mantida", undefined, null, null]);
  // 10:40 o pedido das 10:37 concluiu: fecha com prova
  const comJob = banco({ quedas: b.quedas, jobs: [{ completed_at: iso(62), requested_by: "dono-1" }] });
  r = await rodadaDoVigia(comJob.db, { modo: "sombra", pc: NO_AR, aviso: null, registro: ABERTO, agora: min(65) });
  assertEquals([r.assistente, r.avisou], ["fechou", undefined]);
  assertEquals([comJob.quedas[0].ate, comJob.quedas[0].fechada_por, comJob.quedas[0].volta_avisada_em], [iso(62), "job_bom", null]);
  for (const x of [b, comJob]) {
    assertEquals([x.sinos().length, x.fila().length, x.perguntas().length, x.erros().length], [0, 0, 0, 0]);
    assert(!x.leu("app_error_logs") && !x.leu("app_settings") && !x.leu("app_users"), "sombra não lê nada do caminho do aviso");
    assert(x.gravacoes().every((g) => g.startsWith("assistente_quedas:")), "só o histórico é gravado");
  }
});

Deno.test("sombra: a queda do WhatsApp entra no histórico com a causa, corrige a causa no meio e fecha na volta, sem mandar nada", async () => {
  const b = banco();
  const fora: RegistroDoVigia = { estado: "inacessivel", desde: iso(-10), avisado_em: iso(0) };
  // o aviso de queda saiu (10 min fora), nenhum programa do PC dá sinal: PC fora
  let r = await rodadaDoVigia(b.db, { modo: "sombra", pc: estado({ semSinal: true, pcComSinal: false }), aviso: "caiu", registro: fora, agora: T0 });
  assertEquals([r.whatsapp, r.assistente], ["abriu", "nada"], "com o WhatsApp fora não se abre queda do assistente");
  assertEquals(b.quedas.map((q) => [q.tipo, q.causa, q.desde, q.avisado_por, q.detalhe]), [["whatsapp", "pc_fora", iso(-10), "sino", "conexao inacessivel"]]);
  assertEquals(await lerCausaDaQuedaDoWhatsApp(b.db), "pc_fora");
  // rodada seguinte: um programa do PC voltou a dar sinal e o WhatsApp continua fora = era o Docker ou o túnel
  r = await rodadaDoVigia(b.db, { modo: "sombra", pc: estado({ semSinal: true, pcComSinal: true }), aviso: null, registro: fora, agora: min(5) });
  assertEquals([r.whatsapp, b.quedas[0].causa], ["causa", "docker_ou_tunel"]);
  // de novo: nada a corrigir
  r = await rodadaDoVigia(b.db, { modo: "sombra", pc: estado({ semSinal: true, pcComSinal: true }), aviso: null, registro: fora, agora: min(10) });
  assertEquals(r.whatsapp, null);
  // voltou
  r = await rodadaDoVigia(b.db, { modo: "sombra", pc: NO_AR, aviso: "voltou", registro: { estado: "open", desde: iso(15), avisado_em: null }, agora: min(15) });
  assertEquals([r.whatsapp, b.quedas[0].ate, b.quedas[0].fechada_por], ["fechou", iso(15), "whatsapp_voltou"]);
  assertEquals(await lerCausaDaQuedaDoWhatsApp(b.db), null, "sem queda aberta");
  assertEquals([b.sinos().length, b.fila().length, b.perguntas().length], [0, 0, 0]);
});

Deno.test("histórico do WhatsApp: sem estado do PC a causa é 'desconhecida'; desconectado e travado; a queda antiga que sobrou fecha sem prova", async () => {
  const b = banco({ quedas: [queda({ id: "velha", tipo: "whatsapp", causa: "pc_fora", desde: iso(-600) })] });
  await registrarQuedaDoWhatsApp(b.db, { aviso: "caiu", registro: { estado: "inacessivel", desde: iso(-10), avisado_em: iso(0) }, pc: null, agora: T0 });
  assertEquals(b.quedas.map((q) => [q.id, q.causa, q.ate, q.fechada_por]), [["velha", "pc_fora", iso(-10), "sem_prova"], ["q1", "desconhecida", null, null]]);
  for (const [estadoDaConexao, causa] of [["close", "desconectado"], ["connecting", "desconectado"], ["travado", "travado"]] as const) {
    const x = banco();
    await registrarQuedaDoWhatsApp(x.db, { aviso: "caiu", registro: { estado: estadoDaConexao, desde: iso(-10), avisado_em: iso(0) }, pc: NO_AR, agora: T0 });
    assertEquals(x.quedas[0].causa, causa);
  }
  // conectado e sem aviso: nada a fazer
  const quieto = banco();
  assertEquals(await registrarQuedaDoWhatsApp(quieto.db, { aviso: null, registro: ABERTO, pc: NO_AR, agora: T0 }), null);
  assertEquals(quieto.ops.length, 0);
});

// ─── 3. Ligado ───────────────────────────────────────────────────────────────────────────────────────────────────────

const TEXTO_DO_LOGIN = "*Seu assistente está fora do ar desde as 09:35:* o login do Claude caiu. " +
  "O WhatsApp e o resto do sistema seguem normais; só as mensagens para o assistente ficam sem resposta.";

Deno.test("ligado: antes dos 15 minutos não avisa; aos 15, sino + portão + fila, uma vez só", async () => {
  const b = banco({ quedas: [queda()] });
  let r = await vigiarOAssistente(b.db, { modo: "ligado", pc: LOGIN, whatsappAberto: true, agora: min(10) });
  assertEquals([r.assistente, r.avisou], ["mantida", undefined]);
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [0, 0, 0]);
  assert(!b.leu("app_error_logs"), "antes dos 15 minutos nem lê o registro de falhas");

  r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) });
  assertEquals([r.assistente, r.avisou], ["mantida", "whatsapp"]);
  // o sino dos administradores
  assertEquals(b.sinos().length, 1);
  assertEquals(b.sinos()[0].valores, [
    { user_id: "dono-1", type: "assistente_caiu", title: "Assistente fora do ar", body: TEXTO_DO_LOGIN.replace(/\*/g, ""), navigate_to: TELA_DO_ASSISTENTE },
    { user_id: "admin-2", type: "assistente_caiu", title: "Assistente fora do ar", body: TEXTO_DO_LOGIN.replace(/\*/g, ""), navigate_to: TELA_DO_ASSISTENTE },
  ]);
  // a pergunta ao portão: fonte e assunto próprios, uma chave por queda, sem fato novo
  const p = b.perguntas()[0].p;
  assertEquals([p.phone, p.modo, p.fonte, p.chave, p.assunto, p.destino, p.novo_fato, p.texto],
    [FONE_DO_DONO, "ligado", "assistente", "assistente:caiu:q-aberta", "assistente", "acorde", false, TEXTO_DO_LOGIN]);
  assertEquals(p.dados, { queda_id: "q-aberta", momento: "caiu", desde: iso(0), causa: "login" });
  // a fila: só para o dono, com o texto do aviso, sem botão
  assertEquals(b.fila().length, 1);
  const linha = b.fila()[0].valores;
  assertEquals([linha.phone_normalized, linha.message, linha.source, linha.dedupe_key], [FONE_DO_DONO, TEXTO_DO_LOGIN, "assistente_caiu", "aviso:aviso-1"]);
  assert(!("buttons" in linha) && !("interactive" in linha), "sem botão");
  assertEquals([b.quedas[0].dono_soube, b.quedas[0].avisado_em, b.quedas[0].avisado_por, b.quedas[0].aviso_id], ["aviso", iso(15), "whatsapp", "aviso-1"]);

  // rodadas seguintes: a mesma queda não avisa de novo
  r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(20) });
  assertEquals(r.avisou, undefined);
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [1, 1, 1]);
});

Deno.test("ligado: o dono já leu a causa numa resposta de falha = não manda; a consulta olha só os três registros do WhatsApp", async () => {
  const b = banco({ quedas: [queda()], falhas: 1 });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) });
  assertEquals(r.avisou, "ja_soube");
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [0, 0, 0]);
  assertEquals([b.quedas[0].dono_soube, b.quedas[0].avisado_por, b.quedas[0].avisado_em], ["resposta_de_falha", null, null]);
  const consulta = b.ops.find((o) => o.tabela === "app_error_logs")!;
  assertEquals(consulta.colunas, "id", "nenhum texto de erro é lido");
  assertEquals(consulta.filtros, [
    ["like", "context", "ai-agent@%"],
    ["in", "action", ["max_sem_reserva", "max_fora_sem_reserva", "turno_whatsapp"]],
    ["eq", "level", "error"],
    // 10 minutos antes do início gravado: a falha que abriu a pausa é anterior à rodada que a viu
    ["gte", "last_seen_at", iso(-10)],
  ]);
  // não avisa de novo nas rodadas seguintes
  await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(20) });
  assertEquals(b.ops.filter((o) => o.tabela === "app_error_logs").length, 1);
});

Deno.test("ligado: leitura do registro de falhas que falha = não conclui nada nesta rodada (tenta na próxima), sem mandar e sem marcar", async () => {
  const b = banco({ quedas: [queda()], falhas: "erro" });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) });
  assertEquals(r.avisou, "sem_leitura");
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length, b.quedas[0].dono_soube], [0, 0, 0, null]);
});

Deno.test("ligado: com o WhatsApp fora o aviso não sai (nem o sino), por mais velha que a queda seja", async () => {
  const b = banco({ quedas: [queda({ criado_em: iso(-120) })] });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: LOGIN, whatsappAberto: false, agora: T0 });
  assertEquals([r.assistente, r.avisou], ["mantida", undefined]);
  assertEquals(b.gravacoes(), []);
  assertEquals(b.quedas[0].dono_soube, null);
});

Deno.test("ligado: fora da janela o portão guarda = nada na fila, e a queda fica anotada como guardada", async () => {
  const b = banco({ quedas: [queda()], portao: () => ({ ok: true, decisao: "guardar", situacao: "guardado", motivo: "fora_da_janela", id: "aviso-9" }) });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) });
  assertEquals(r.avisou, "guardado");
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [1, 1, 0]);
  assertEquals([b.quedas[0].dono_soube, b.quedas[0].avisado_por, b.quedas[0].aviso_id], ["aviso", "guardado", "aviso-9"]);
});

Deno.test("ligado: portão ilegível ou voz única fora do 'ligado' = só o sino (nunca mensagem por fora do portão)", async () => {
  const ilegivel = banco({ quedas: [queda()], portao: () => null });
  assertEquals((await vigiarOAssistente(ilegivel.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) })).avisou, "sino");
  assertEquals([ilegivel.sinos().length, ilegivel.fila().length, ilegivel.quedas[0].avisado_por], [1, 0, "sino"]);
  for (const vozUnica of ["sombra", "desligado"] as const) {
    const b = banco({ quedas: [queda()], vozUnica });
    assertEquals((await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) })).avisou, "sino", vozUnica);
    assertEquals([b.sinos().length, b.perguntas().length, b.fila().length, b.quedas[0].avisado_por], [1, 0, 0, "sino"]);
  }
});

Deno.test("ligado: já saíram 2 mensagens deste vigia hoje = só o sino, sem perguntar ao portão", async () => {
  const hoje = [
    queda({ id: "a", tipo: "gateway", desde: iso(-300), ate: iso(-200), avisado_por: "whatsapp", avisado_em: iso(-280), volta_avisada_em: iso(-200), dono_soube: "aviso" }),
    queda(),
  ];
  const b = banco({ quedas: hoje });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) });
  assertEquals(r.avisou, "limite");
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [1, 0, 0]);
  assertEquals([b.quedas[1].dono_soube, b.quedas[1].avisado_por], ["aviso", "limite"]);
  // a mensagem de ontem não conta
  const ontem = banco({ quedas: [queda({ id: "a", tipo: "gateway", desde: iso(-2000), ate: iso(-1900), avisado_por: "whatsapp", avisado_em: iso(-1990), volta_avisada_em: iso(-1900) }), queda()] });
  assertEquals((await vigiarOAssistente(ontem.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(15) })).avisou, "whatsapp");
});

Deno.test("ligado: o limite da assinatura leva o horário de liberação que o programa publica", async () => {
  const b = banco({ quedas: [queda({ causa: "limite" })] });
  const limite = estado({ pausa: { motivo: "rate_limited", ate: "2026-11-26T05:00:00.000Z" } });
  await vigiarOAssistente(b.db, { modo: "ligado", pc: limite, whatsappAberto: true, agora: min(15) });
  assertEquals(b.fila()[0].valores.message,
    "*Seu assistente está fora do ar desde as 09:35:* acabou o limite da assinatura. Libera qui 26/11 às 02:00. " +
    "O WhatsApp e o resto do sistema seguem normais; só as mensagens para o assistente ficam sem resposta.");
});

// ─── A volta ─────────────────────────────────────────────────────────────────────────────────────────────────────────

const AVISADA = { dono_soube: "aviso", avisado_em: iso(15), avisado_por: "whatsapp", aviso_id: "aviso-1" };

Deno.test("volta: o programa voltou a dar sinal (queda avisada) = fecha, sino e portão com fato novo, uma linha na fila", async () => {
  const b = banco({ quedas: [queda({ tipo: "gateway", causa: "programa_parado", desde: iso(-10), ...AVISADA })], portao: () => ({ ok: true, decisao: "acordar", situacao: "acordou", id: "aviso-2" }) });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(40) });
  assertEquals([r.assistente, r.avisou], ["fechou", "whatsapp"]);
  assertEquals([b.quedas[0].ate, b.quedas[0].fechada_por, b.quedas[0].volta_avisada_em], [iso(40), "batimento", iso(40)]);
  const texto = "*Seu assistente voltou às 10:15* (estava fora desde as 09:25). Pode mandar de novo o que ficou sem resposta.";
  assertEquals(b.sinos()[0].valores[0], { user_id: "dono-1", type: "assistente_voltou", title: "Assistente de volta", body: texto.replace(/\*/g, ""), navigate_to: TELA_DO_ASSISTENTE });
  const p = b.perguntas()[0].p;
  assertEquals([p.chave, p.assunto, p.novo_fato, p.texto], ["assistente:voltou:q-aberta", "assistente", true, texto]);
  assertEquals(p.dados, { queda_id: "q-aberta", momento: "voltou", desde: iso(-10), causa: "programa_parado", ate: iso(40) });
  assertEquals([b.fila()[0].valores.message, b.fila()[0].valores.source, b.fila()[0].valores.dedupe_key], [texto, "assistente_voltou", "aviso:aviso-2"]);
});

Deno.test("volta: o pedido que provou a volta foi do próprio dono = só o sino (ele acabou de receber a resposta)", async () => {
  const b = banco({ quedas: [queda(AVISADA)], jobs: [{ completed_at: iso(62), requested_by: "dono-1" }] });
  const r = await vigiarOAssistente(b.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(65) });
  assertEquals([r.assistente, r.avisou], ["fechou", "dono_viu"]);
  assertEquals([b.sinos().length, b.perguntas().length, b.fila().length], [1, 0, 0]);
  assertEquals([b.quedas[0].ate, b.quedas[0].fechada_por, b.quedas[0].volta_avisada_em], [iso(62), "job_bom", null]);
  // de ai_jobs só a hora e quem pediu: nenhum texto de pedido nem de resposta
  const leitura = b.ops.find((o) => o.tabela === "ai_jobs")!;
  assertEquals(leitura.colunas, "completed_at, requested_by");
  assertEquals(leitura.filtros, [["eq", "provider", "claude-local"], ["eq", "status", "completed"], ["gt", "completed_at", iso(0)]]);
  // pedido de outra pessoa: o dono não viu, então o portão é perguntado
  const outro = banco({ quedas: [queda(AVISADA)], jobs: [{ completed_at: iso(62), requested_by: "admin-2" }] });
  assertEquals((await vigiarOAssistente(outro.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(65) })).avisou, "whatsapp");
  assertEquals(outro.perguntas()[0].p.chave, "assistente:voltou:q-aberta");
});

Deno.test("volta: sem aviso de queda não há aviso de volta; fechada sem prova, também não", async () => {
  // queda curta, o dono nunca soube: fecha calada
  const curta = banco({ quedas: [queda({ tipo: "gateway", causa: "programa_parado", desde: iso(-10) })] });
  const r = await vigiarOAssistente(curta.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(5) });
  assertEquals([r.assistente, r.avisou], ["fechou", undefined]);
  assertEquals(curta.gravacoes(), ["assistente_quedas:update"]);
  // 24 h sem ver o problema e sem pedido bom: fecha sem prova e sem aviso, mesmo com a queda avisada
  const semProva = banco({ quedas: [queda(AVISADA)] });
  const s = await vigiarOAssistente(semProva.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(24 * 60) });
  assertEquals([s.assistente, s.avisou, semProva.quedas[0].fechada_por], ["fechou", undefined, "sem_prova"]);
  assertEquals([semProva.sinos().length, semProva.perguntas().length], [0, 0]);
});

Deno.test("volta: o aviso da queda ainda guardado (o dono não leu) = a volta não vira mensagem; já lido, vira", async () => {
  const guardada = { dono_soube: "aviso", avisado_em: iso(15), avisado_por: "guardado", aviso_id: "aviso-9" };
  const naoLeu = banco({ quedas: [queda({ tipo: "gateway", causa: "sem_rede", desde: iso(-10), ...guardada })], situacaoDoAviso: "guardado" });
  assertEquals((await vigiarOAssistente(naoLeu.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(40) })).avisou, "queda_nao_lida");
  assertEquals([naoLeu.perguntas().length, naoLeu.fila().length, naoLeu.quedas[0].volta_avisada_em], [0, 0, null]);
  const leu = banco({ quedas: [queda({ tipo: "gateway", causa: "sem_rede", desde: iso(-10), ...guardada })], situacaoDoAviso: "entregue" });
  assertEquals((await vigiarOAssistente(leu.db, { modo: "ligado", pc: NO_AR, whatsappAberto: true, agora: min(40) })).avisou, "whatsapp");
});

Deno.test("duas rodadas ao mesmo tempo: a segunda que tenta abrir a mesma queda não lança (vale a primeira)", async () => {
  const b = banco();
  // a leitura não vê a queda (a outra rodada ainda não tinha gravado), mas o insert esbarra no índice de uma aberta por tipo
  b.quedas.push(queda({ id: "da-outra", tipo: "gateway", causa: "programa_parado" }));
  const semVer = { ...b.db, from: (t: string) => {
    const q = b.db.from(t);
    const select = q.select;
    // deno-lint-ignore no-explicit-any
    q.select = (...a: any[]) => { const r = select(...a); if (t === "assistente_quedas") r.in = () => ({ is: () => ({ order: () => ({ limit: () => Promise.resolve({ data: [], error: null }) }) }) }); return r; };
    return q;
  } };
  const r = await vigiarOAssistente(semVer, { modo: "sombra", pc: CALADO, whatsappAberto: true, agora: T0 });
  assertEquals(r.assistente, "abriu");
  assertEquals(b.quedas.length, 1, "nenhuma segunda linha aberta");
});
