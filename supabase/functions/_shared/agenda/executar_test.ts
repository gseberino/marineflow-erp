// Agenda de Produção, Fase 1 (P6): as palavras da agenda com o banco de mentira — a RPC certa com os parâmetros
// certos, o texto do banco repassado sem mexer, nunca lança (erro vira frase + app_error_logs), o modo desligado não
// intercepta e o que não é do dono segue ao modelo.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ComandoDaAgenda, frasesDaAgenda, lerComandoDaAgenda } from "./comandos.ts";
import {
  camadaDaAgenda,
  chamadaDoComando,
  type DependenciasDaCamada,
  ehComandoDaAgendaLigada,
  executarComandoDaAgenda,
  lerModoDaLeitura,
  modoDaDiariaNoBanco,
  modoDaLeituraNoBanco,
  modoDoClienteNoBanco,
  rascunhoAbertoNoBanco,
  modoDaPropostaNoBanco,
  modosDaAgendaNoBanco,
  RPC_CHOVEU,
  RPC_CLIENTE_DITO,
  RPC_CONCLUIR_DITO,
  RPC_CONFERIR_DIA,
  RPC_DESCARTAR,
  RPC_DESFAZER_DITO,
  RPC_DIARIA_DITA,
  RPC_ENTREGAR_DITO,
  RPC_GRAVAR,
  TEXTO_SEM_AGENDA,
  TEXTO_SEM_CLIENTE,
  TEXTO_SEM_ANOTAR,
  TEXTO_SEM_CONCLUIR,
  TEXTO_SEM_DESCARTAR,
  TEXTO_SEM_DESFAZER,
  TEXTO_SEM_DIARIA,
  TEXTO_SEM_ENTREGAR,
  TEXTO_SEM_GRAVAR,
  TEXTO_SO_ADMIN,
} from "./executar.ts";
import { RPC_AGENDA_VER } from "./rpc-das-ferramentas.ts";

const AUTOR = "00000000-0000-4000-8000-000000000001";

// Os textos de verdade (supabase/tests/agenda_fase1_leituras.sql e _rascunho.sql, fixture de 23/10).
const TEXTO_SEMANA = "Esta semana (seg 19/10 a sáb 24/10) não tem nada marcado, e nenhuma diária foi lançada depois de sáb 17/10: …";
const TEXTO_GRAVADO = "Gravado. Agora:\n• Lenine: falta você dizer se tem peça a comprar.";

type Resposta = { data?: unknown; error?: unknown; lanca?: boolean };

/** Um cliente de mentira: rpc com respostas por nome (ou função), o registro das chamadas e o log_app_error. */
function cliente(respostas: Record<string, Resposta> = {}) {
  const chamadas: Array<{ nome: string; args: Record<string, unknown> }> = [];
  return {
    chamadas,
    rpc(nome: string, args: Record<string, unknown>) {
      chamadas.push({ nome, args });
      if (nome === "log_app_error") return Promise.resolve({ data: null, error: null });
      const r = respostas[nome] ?? { data: null, error: null };
      if (r.lanca) throw new Error("rede caiu");
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    logs() {
      return chamadas.filter((c) => c.nome === "log_app_error").map((c) => c.args);
    },
  };
}

Deno.test("lerModoDaLeitura: sombra e ligado; qualquer outra coisa é desligado", () => {
  assertEquals(lerModoDaLeitura("sombra"), "sombra");
  assertEquals(lerModoDaLeitura(" Ligado "), "ligado");
  for (const v of ["desligado", "", "on", null, undefined, 1, { modo: "ligado" }]) assertEquals(lerModoDaLeitura(v), "desligado", String(v));
});

function adminDoModo(
  r: { data?: unknown; error?: unknown; lanca?: boolean },
  rascunho: { linhas?: unknown[]; error?: unknown; lanca?: boolean } = {},
) {
  const lidas: string[] = [];
  const filtros: string[] = [];
  return {
    lidas,
    filtros,
    from(t: string) {
      lidas.push(t);
      if (t === "agenda_rascunho") {
        if (rascunho.lanca) throw new Error("rede");
        const q = {
          select: () => q,
          eq: (c: string, v: unknown) => (filtros.push(`${c}=${v}`), q),
          gt: (c: string) => (filtros.push(`${c}>agora`), q),
          limit: () => Promise.resolve({ data: rascunho.error ? null : rascunho.linhas ?? [], error: rascunho.error ?? null }),
        };
        return q;
      }
      if (r.lanca) throw new Error("rede");
      const q = { select: () => q, maybeSingle: () => Promise.resolve({ data: r.data ?? null, error: r.error ?? null }) };
      return q;
    },
  };
}

Deno.test("modoDaLeituraNoBanco: a linha de agenda_config; erro, tabela ausente, sem linha ou exceção = desligado", async () => {
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ data: { modo_leitura: "sombra" } })), "sombra");
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ data: { modo_leitura: "ligado" } })), "ligado");
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ data: { modo_leitura: "desligado" } })), "desligado");
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ error: { code: "42P01" } })), "desligado");
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ data: null })), "desligado");
  assertEquals(await modoDaLeituraNoBanco(adminDoModo({ lanca: true })), "desligado");
  const a = adminDoModo({ data: { modo_leitura: "sombra" } });
  await modoDaLeituraNoBanco(a);
  assertEquals(a.lidas, ["agenda_config"]);
});

Deno.test("ehComandoDaAgendaLigada (webhook): a chave só é lida quando o texto é comando", async () => {
  const a = adminDoModo({ data: { modo_leitura: "sombra" } });
  assertEquals(await ehComandoDaAgendaLigada(a, "oi, tudo bem?"), false);
  assertEquals(await ehComandoDaAgendaLigada(a, "sim"), false);
  assertEquals(a.lidas, []);
  assertEquals(await ehComandoDaAgendaLigada(a, "grava"), true);
  assertEquals(a.lidas, ["agenda_config"]);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo({ data: { modo_leitura: "desligado" } }), "grava"), false);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo({ error: { code: "XX000" } }), "agenda"), false);
});

Deno.test("ehComandoDaAgendaLigada: desligada, só o grava/descarta com rascunho aberto vai à agenda (o resto, como antes)", async () => {
  const desligado = { data: { modo_leitura: "desligado" } };
  const comRascunho = { linhas: [{ id: "r1" }] };
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo(desligado, comRascunho), "grava"), true);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo(desligado, comRascunho), "descarta"), true);
  // a leitura não passa: desligada, "agenda" segue ao modelo (que volta à my_agenda)
  const a = adminDoModo(desligado, comRascunho);
  assertEquals(await ehComandoDaAgendaLigada(a, "agenda"), false);
  assertEquals(a.lidas, ["agenda_config"], "sem grava/descarta o rascunho nem é lido");
  // sem rascunho (ou erro ao ler), o "grava" segue como antes (o "sim" do CMP continua dele)
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo(desligado, { linhas: [] }), "grava"), false);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo(desligado, { error: { code: "42P01" } }), "grava"), false);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo(desligado, { lanca: true }), "grava"), false);
});

Deno.test("rascunhoAbertoNoBanco: aberto, dentro da validade e do autor; erro ou exceção = false", async () => {
  const a = adminDoModo({}, { linhas: [{ id: "r1" }] });
  assertEquals(await rascunhoAbertoNoBanco(a, AUTOR), true);
  assertEquals(a.lidas, ["agenda_rascunho"]);
  assertEquals(a.filtros, ["estado=aberto", "expira_em>agora", `autor=${AUTOR}`]);
  assertEquals(await rascunhoAbertoNoBanco(adminDoModo({}, { linhas: [] }), AUTOR), false);
  assertEquals(await rascunhoAbertoNoBanco(adminDoModo({}, { error: { code: "XX000" } }), AUTOR), false);
  assertEquals(await rascunhoAbertoNoBanco(adminDoModo({}, { lanca: true }), AUTOR), false);
});

Deno.test("chamadaDoComando: cada palavra vira a RPC certa, com o mesmo mapeamento da ferramenta agenda_ver", () => {
  const ver = (t: string) => chamadaDoComando(lerComandoDaAgenda(t)!, AUTOR);
  const base = { p_autor: AUTOR, p_os: null, p_simular: null, p_simular_aprovacao: false };
  assertEquals(ver("agenda"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "semana", p_pessoa: null, p_foco: "tudo" } });
  assertEquals(ver("agenda de hoje"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "hoje", p_pessoa: null, p_foco: "tudo" } });
  assertEquals(ver("agenda amanhã"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "amanha", p_pessoa: null, p_foco: "tudo" } });
  assertEquals(ver("agenda semana que vem"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "proxima_semana", p_pessoa: null, p_foco: "tudo" } });
  assertEquals(ver("livre"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_pessoa: null, p_foco: "livre" } });
  assertEquals(ver("atrasado"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_pessoa: null, p_foco: "atrasos" } });
  assertEquals(ver("o que eu tenho que fazer hoje?"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_pessoa: "eu", p_foco: "o_que_fazer" } });
  assertEquals(ver("grava"), { rpc: RPC_GRAVAR, params: { p_autor: AUTOR } });
  assertEquals(ver("descarta tudo"), { rpc: RPC_DESCARTAR, params: { p_autor: AUTOR } });
  // o dia fixo só em teste/eval
  assertEquals(chamadaDoComando({ comando: "gravar" }, AUTOR, "2026-10-23").params, { p_autor: AUTOR, p_hoje: "2026-10-23" });
  assertEquals(chamadaDoComando(lerComandoDaAgenda("livre")!, AUTOR, "2026-10-23").params.p_hoje, "2026-10-23");
});

Deno.test("chamadaDoComando: toda frase da tabela tem parâmetros válidos (nenhuma vira erro)", () => {
  for (const f of frasesDaAgenda()) {
    const c = chamadaDoComando(lerComandoDaAgenda(f)!, AUTOR);
    assert([RPC_AGENDA_VER, RPC_GRAVAR, RPC_DESCARTAR].includes(c.rpc), f);
    assertEquals(c.params.p_autor, AUTOR, f);
  }
});

Deno.test("executar: o texto do banco vai como veio (agenda_ver, grava, descarta), e a RPC recebe p_autor", async () => {
  const c = cliente({
    agenda_ver: { data: { ok: true, texto: TEXTO_SEMANA, rota: "semana", dados: { grande: true } } },
    agenda_rascunho_gravar: { data: { ok: true, gravados: 1, texto: TEXTO_GRAVADO } },
    agenda_rascunho_descartar: { data: { ok: true, descartados: 2, texto: "Descartei. Nada foi gravado." } },
  });
  assertEquals(await executarComandoDaAgenda(c, lerComandoDaAgenda("agenda")!, { autor: AUTOR }), { ok: true, texto: TEXTO_SEMANA });
  assertEquals(await executarComandoDaAgenda(c, { comando: "gravar" }, { autor: AUTOR }), { ok: true, texto: TEXTO_GRAVADO });
  assertEquals(await executarComandoDaAgenda(c, { comando: "descartar" }, { autor: AUTOR }), { ok: true, texto: "Descartei. Nada foi gravado." });
  assertEquals(c.chamadas.map((x) => [x.nome, x.args.p_autor]), [
    ["agenda_ver", AUTOR], ["agenda_rascunho_gravar", AUTOR], ["agenda_rascunho_descartar", AUTOR],
  ]);
  assertEquals(c.logs(), []);
});

Deno.test("executar: resposta do banco que não é 'ok' também é resposta (Não encontrei, Não gravei nada, nada esperando)", async () => {
  const naoGravei = "Não gravei nada: Não achei \"dia 3\" no que você disse; me diga de novo. (Nelson). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.";
  const c = cliente({
    agenda_rascunho_gravar: { data: { ok: false, gravados: 0, erro: "x", texto: naoGravei } },
    agenda_ver: { data: { ok: false, rota: "pessoa", pergunta: "Qual Rodrigo? OS-00096 ou OS-00076?" } },
  });
  assertEquals((await executarComandoDaAgenda(c, { comando: "gravar" }, { autor: AUTOR })).texto, naoGravei);
  assertEquals((await executarComandoDaAgenda(c, lerComandoDaAgenda("livre")!, { autor: AUTOR })).texto, "Qual Rodrigo? OS-00096 ou OS-00076?");
  assertEquals(c.logs(), []);
});

Deno.test("executar nunca lança: erro do banco, rede caída ou resposta sem texto viram a frase ao dono e uma linha em app_error_logs", async () => {
  const casos: Array<[string, Resposta, string]> = [
    ["agenda", { error: { code: "XX000", message: "deu ruim" } }, TEXTO_SEM_AGENDA],
    ["livre", { lanca: true }, TEXTO_SEM_AGENDA],
    ["atrasado", { data: { ok: true } }, TEXTO_SEM_AGENDA], // leitura sem texto nunca vira "nada atrasado"
    ["o que eu tenho que fazer", { data: null }, TEXTO_SEM_AGENDA],
    ["grava", { error: { code: "40001", message: "serialização" } }, TEXTO_SEM_GRAVAR],
    ["descarta", { lanca: true }, TEXTO_SEM_DESCARTAR],
    ["grava", { error: { code: "42501", message: "Só o administrador mexe na agenda." } }, TEXTO_SO_ADMIN],
  ];
  for (const [t, r, frase] of casos) {
    const cmd = lerComandoDaAgenda(t)!;
    const rpc = cmd.comando === "gravar" ? RPC_GRAVAR : cmd.comando === "descartar" ? RPC_DESCARTAR : RPC_AGENDA_VER;
    const c = cliente({ [rpc]: r });
    const log = cliente();
    const res = await executarComandoDaAgenda(c, cmd, { autor: AUTOR, log, canal: "whatsapp" });
    assertEquals(res, { ok: false, texto: frase }, t);
    const [l] = log.logs();
    assert(l, `sem log: ${t}`);
    assertEquals([l.p_context, l.p_action, l.p_level, l.p_source], ["agenda", `comando:${cmd.comando}`, "error", "edge"], t);
    assertEquals((l.p_details as Record<string, unknown>).rpc, rpc, t);
    assertEquals(c.logs(), [], "o log vai para o cliente do log, não para o do canal");
  }
});

Deno.test("executar: sem cliente de log, registra no próprio cliente; frase de erro sem jargão", async () => {
  const c = cliente({ agenda_ver: { error: { code: "XX000" } } });
  await executarComandoDaAgenda(c, lerComandoDaAgenda("agenda")!, { autor: AUTOR });
  assertEquals(c.logs().length, 1);
  for (const f of [TEXTO_SEM_AGENDA, TEXTO_SEM_GRAVAR, TEXTO_SEM_DESCARTAR, TEXTO_SO_ADMIN]) {
    assert(!/erro|error|rpc|ferramenta|pend[eê]ncia|registro/i.test(f), f);
  }
});

// ─── A camada (o que o ai-agent chama) ───────────────────────────────────────────────────────────

function deps(p: {
  dono?: boolean | "lanca";
  modo?: "desligado" | "sombra" | "ligado" | "lanca";
  texto?: string;
  rascunho?: boolean | "lanca";
  /** (Fase 2) modo_proposta; ausente = sombra (a agenda automática em teste); "sem" = a dependência não existe */
  fase2?: "desligado" | "sombra" | "ligado" | "lanca" | "sem";
  resposta?: { ok: boolean; texto: string; seguirAoModelo?: boolean };
}) {
  const c = { dono: 0, modo: 0, executar: [] as string[], rascunho: 0, fase2: 0 };
  const d: DependenciasDaCamada = {
    ehDoDono: () => {
      c.dono++;
      if (p.dono === "lanca") throw new Error("rede");
      return Promise.resolve(p.dono ?? true);
    },
    modo: () => {
      c.modo++;
      if (p.modo === "lanca") return Promise.reject(new Error("rede"));
      return Promise.resolve(p.modo ?? "sombra");
    },
    executar: (cmd) => {
      c.executar.push(cmd.comando);
      return Promise.resolve(p.resposta ?? { ok: true, texto: p.texto ?? "texto do banco" });
    },
    ...(p.fase2 === "sem" ? {} : {
      modosDaFase2: () => {
        c.fase2++;
        if (p.fase2 === "lanca") return Promise.reject(new Error("rede"));
        return Promise.resolve({ proposta: (p.fase2 ?? "sombra") as "desligado" | "sombra" | "ligado", vigia: "desligado" as const });
      },
    }),
    ...(p.rascunho === undefined ? {} : {
      rascunhoAberto: () => {
        c.rascunho++;
        if (p.rascunho === "lanca") return Promise.reject(new Error("rede"));
        return Promise.resolve(p.rascunho === true);
      },
    }),
  };
  return { d, c };
}

Deno.test("camada: o que não é comando volta null sem ler nada (custo zero na conversa)", async () => {
  for (const t of ["oi", "sim", "1", "A", "lista", "como tá a semana?", "me manda o pdf do orçamento 117"]) {
    const { d, c } = deps({});
    assertEquals(await camadaDaAgenda(t, d), null, t);
    assertEquals([c.dono, c.modo, c.executar.length], [0, 0, 0], t);
  }
});

Deno.test("camada: comando do dono com a agenda em sombra ou ligada responde sem o modelo", async () => {
  for (const modo of ["sombra", "ligado"] as const) {
    const { d, c } = deps({ modo, texto: TEXTO_GRAVADO });
    assertEquals(await camadaDaAgenda("grava", d), { comando: { comando: "gravar" }, texto: TEXTO_GRAVADO, ok: true });
    assertEquals(c.executar, ["gravar"]);
  }
});

Deno.test("camada: quem não é o dono segue ao modelo (nem a chave é lida); desligado não intercepta", async () => {
  for (const dono of [false, "lanca"] as const) {
    const { d, c } = deps({ dono });
    assertEquals(await camadaDaAgenda("agenda", d), null, String(dono));
    assertEquals([c.modo, c.executar.length], [0, 0]);
  }
  for (const modo of ["desligado", "lanca"] as const) {
    const { d, c } = deps({ modo });
    assertEquals(await camadaDaAgenda("o que eu tenho que fazer", d), null, modo);
    assertEquals(c.executar.length, 0);
  }
});

Deno.test("camada: desligada, o grava/descarta do rascunho que ficou aberto ainda responde (sem laço com o modelo)", async () => {
  for (const t of ["grava", "descarta"]) {
    const { d, c } = deps({ modo: "desligado", rascunho: true, texto: "Descartei. Nada foi gravado." });
    assertEquals((await camadaDaAgenda(t, d))?.ok, true, t);
    assertEquals([c.rascunho, c.executar.length], [1, 1], t);
  }
  // sem rascunho aberto (ou sem como saber), desligada continua sem interceptar
  for (const rascunho of [false, "lanca", undefined] as const) {
    const { d, c } = deps({ modo: "desligado", rascunho });
    assertEquals(await camadaDaAgenda("grava", d), null, String(rascunho));
    assertEquals(c.executar.length, 0);
  }
  // a leitura não passa (nem pergunta pelo rascunho)
  const { d, c } = deps({ modo: "desligado", rascunho: true });
  assertEquals(await camadaDaAgenda("agenda", d), null);
  assertEquals([c.rascunho, c.executar.length], [0, 0]);
});

Deno.test("camada: um executar que lance ainda vira a frase ao dono (o turno não cai)", async () => {
  const d: DependenciasDaCamada = {
    ehDoDono: () => true,
    modo: () => Promise.resolve("sombra"),
    executar: () => Promise.reject(new Error("bug")),
  };
  assertEquals(await camadaDaAgenda("grava", d), { comando: { comando: "gravar" }, texto: TEXTO_SEM_GRAVAR, ok: false });
  assertEquals((await camadaDaAgenda("agenda", d))?.texto, TEXTO_SEM_AGENDA);
});

// ─── Fase 2 (P5): dia feito, dia não/parcial + motivo, choveu, desfaz e os focos novos ──────────────────────────

Deno.test("Fase 2 — chamadaDoComando: cada palavra vai à RPC dela, como o dono disse (o banco resolve o dia e o alvo)", () => {
  const c = (t: string, canal?: "whatsapp" | "painel") => chamadaDoComando(lerComandoDaAgenda(t)!, AUTOR, undefined, canal);
  assertEquals(c("dia feito"), {
    rpc: RPC_CONFERIR_DIA,
    params: { p_autor: AUTOR, p_resultado: "cumprido", p_motivo: null, p_quando: null, p_canal: "whatsapp" },
  });
  assertEquals(c("Dia não cliente ontem", "painel"), {
    rpc: RPC_CONFERIR_DIA,
    params: { p_autor: AUTOR, p_resultado: "nao_cumprido", p_motivo: "cliente_ou_bem", p_quando: "ontem", p_canal: "painel" },
  });
  assertEquals(c("dia parcial"), {
    rpc: RPC_CONFERIR_DIA,
    params: { p_autor: AUTOR, p_resultado: "parcial", p_motivo: null, p_quando: null, p_canal: "whatsapp" },
  });
  assertEquals(c("choveu ontem"), { rpc: RPC_CHOVEU, params: { p_autor: AUTOR, p_quando: "ontem", p_canal: "whatsapp" } });
  assertEquals(c("desfaz Nelson"), { rpc: RPC_DESFAZER_DITO, params: { p_autor: AUTOR, p_alvo: "nelson", p_canal: "whatsapp" } });
  assertEquals(c("desfaz a semana").params.p_alvo, "semana");
  assertEquals(c("desfaz").params.p_alvo, null);
  const base = { p_autor: AUTOR, p_periodo: null, p_pessoa: null, p_os: null, p_simular: null, p_simular_aprovacao: false };
  assertEquals(c("o que mudou?"), { rpc: RPC_AGENDA_VER, params: { ...base, p_foco: "mudancas" } });
  assertEquals(c("agenda pendências"), { rpc: RPC_AGENDA_VER, params: { ...base, p_foco: "decisoes" } });
  assertEquals(c("plano da semana"), { rpc: RPC_AGENDA_VER, params: { ...base, p_foco: "plano" } });
  // o dia fixo só em teste/eval
  assertEquals(chamadaDoComando(lerComandoDaAgenda("dia feito")!, AUTOR, "2026-11-03").params.p_hoje, "2026-11-03");
});

Deno.test("Fase 2 — executar: o texto do banco volta como veio, o canal vai junto; o modo fora de 'ligado' é resposta, não erro", async () => {
  const anotado = "Anotado, hoje (ter 03/11): Vanderlei (OS-00069) feito, com você e Roberto. Vanderlei agora está em andamento.";
  const emTeste = "Ainda não tenho plano publicado: a agenda automática está em teste.";
  const pede = "Me diga o motivo junto: *dia parcial imprevisto* (ou material, cliente, equipe, clima, anterior, informação, estimativa, urgência, esqueci).";
  const c = cliente({
    agenda_conferir_dia: { data: { ok: true, mudou: true, texto: anotado } },
    agenda_choveu: { data: { ok: false, mudou: false, texto: emTeste } },
    agenda_desfazer_dito: { data: { ok: false, status: "ambiguo", texto: "Qual? Nelson (…) ou Vanderlei (…)? Diga *desfaz* e o nome." } },
  });
  assertEquals(await executarComandoDaAgenda(c, lerComandoDaAgenda("dia feito")!, { autor: AUTOR, canal: "painel" }), { ok: true, texto: anotado });
  assertEquals(await executarComandoDaAgenda(c, lerComandoDaAgenda("choveu")!, { autor: AUTOR }), { ok: true, texto: emTeste });
  assertEquals((await executarComandoDaAgenda(c, lerComandoDaAgenda("desfaz")!, { autor: AUTOR })).texto,
    "Qual? Nelson (…) ou Vanderlei (…)? Diga *desfaz* e o nome.");
  assertEquals(c.chamadas.map((x) => [x.nome, x.args.p_canal]), [
    ["agenda_conferir_dia", "painel"], ["agenda_choveu", "whatsapp"], ["agenda_desfazer_dito", "whatsapp"],
  ]);
  const p = cliente({ agenda_conferir_dia: { data: { ok: false, mudou: false, pede: "motivo", texto: pede } } });
  assertEquals((await executarComandoDaAgenda(p, lerComandoDaAgenda("dia parcial")!, { autor: AUTOR })).texto, pede);
  assertEquals([c.logs(), p.logs()], [[], []]);
});

Deno.test("Fase 2 — executar nunca lança: o erro do *dia feito*, do *choveu* e do *desfaz* vira a frase certa e o log", async () => {
  const casos: Array<[string, string, Resposta, string]> = [
    ["dia feito", RPC_CONFERIR_DIA, { error: { code: "XX000", message: "deu ruim" } }, TEXTO_SEM_ANOTAR],
    ["dia nao cliente", RPC_CONFERIR_DIA, { lanca: true }, TEXTO_SEM_ANOTAR],
    ["choveu", RPC_CHOVEU, { data: { ok: true } }, TEXTO_SEM_ANOTAR],
    ["desfaz nelson", RPC_DESFAZER_DITO, { error: { code: "40001" } }, TEXTO_SEM_DESFAZER],
    ["desfaz", RPC_DESFAZER_DITO, { error: { code: "42501", message: "Só o administrador mexe na agenda." } }, TEXTO_SO_ADMIN],
    ["o que mudou", RPC_AGENDA_VER, { lanca: true }, TEXTO_SEM_AGENDA],
  ];
  for (const [t, rpc, r, frase] of casos) {
    const cmd = lerComandoDaAgenda(t)!;
    const c = cliente({ [rpc]: r });
    const log = cliente();
    assertEquals(await executarComandoDaAgenda(c, cmd, { autor: AUTOR, log, canal: "whatsapp" }), { ok: false, texto: frase }, t);
    const [l] = log.logs();
    assertEquals([l.p_context, l.p_action, (l.p_details as Record<string, unknown>).rpc], ["agenda", `comando:${cmd.comando}`, rpc], t);
  }
  for (const f of [TEXTO_SEM_ANOTAR, TEXTO_SEM_DESFAZER]) assert(!/erro|error|rpc|ferramenta|pend[eê]ncia|registro/i.test(f), f);
});

Deno.test("Fase 2 — camada: *dia feito* do dono com a agenda em sombra ou ligada responde sem o modelo; desligada não intercepta", async () => {
  for (const modo of ["sombra", "ligado"] as const) {
    const { d, c } = deps({ modo, texto: "Anotado." });
    assertEquals((await camadaDaAgenda("dia feito", d))?.comando, { comando: "dia", resultado: "cumprido", motivo: null, quando: null });
    assertEquals(c.executar, ["dia"]);
  }
  for (const t of ["dia feito", "choveu", "desfaz Nelson", "o que mudou"]) {
    const { d, c } = deps({ modo: "desligado", rascunho: true });
    assertEquals(await camadaDaAgenda(t, d), null, t);
    assertEquals([c.rascunho, c.executar.length], [0, 0], t);
  }
  // quem não é o dono segue ao modelo
  const { d, c } = deps({ dono: false });
  assertEquals(await camadaDaAgenda("desfaz semana", d), null);
  assertEquals(c.executar.length, 0);
});

Deno.test("Fase 2 — modosDaAgendaNoBanco: proposta e vigia num SELECT; erro, coluna ausente, sem linha ou exceção = desligado", async () => {
  assertEquals(await modosDaAgendaNoBanco(adminDoModo({ data: { modo_proposta: "ligado", modo_vigia: "sombra" } })),
    { proposta: "ligado", vigia: "sombra" });
  assertEquals(await modosDaAgendaNoBanco(adminDoModo({ data: { modo_proposta: " Sombra ", modo_vigia: "xis" } })),
    { proposta: "sombra", vigia: "desligado" });
  for (const r of [{ error: { code: "42703" } }, { data: null }, { lanca: true }]) {
    assertEquals(await modosDaAgendaNoBanco(adminDoModo(r)), { proposta: "desligado", vigia: "desligado" }, JSON.stringify(r));
  }
  assertEquals(await modoDaPropostaNoBanco(adminDoModo({ data: { modo_proposta: "ligado" } })), "ligado");
  assertEquals(await modoDaPropostaNoBanco(adminDoModo({ error: { code: "42P01" } })), "desligado");
});

// ─── Revisão da Fase 2: as palavras novas só com a agenda automática, e o *desfaz <nome>* que não é dela ──────────

Deno.test("Fase 2 (revisão) — camada: com a leitura ligada e a agenda automática desligada, as palavras da Fase 2 seguem ao modelo", async () => {
  for (const fase2 of ["desligado", "lanca", "sem"] as const) {
    for (const t of ["dia feito", "choveu", "dia não cliente", "desfaz Nelson", "desfaz", "o que mudou", "agenda pendências", "agenda plano"]) {
      const { d, c } = deps({ modo: "ligado", fase2 });
      assertEquals(await camadaDaAgenda(t, d), null, `${fase2}: ${t}`);
      assertEquals(c.executar.length, 0, `${fase2}: ${t}`);
    }
    // as palavras da Fase 1 continuam (e nem leem o modo da Fase 2)
    const { d, c } = deps({ modo: "ligado", fase2 });
    assertEquals((await camadaDaAgenda("agenda", d))?.ok, true, fase2);
    assertEquals(c.fase2, 0, fase2);
  }
  // com a agenda automática em sombra (ou ligada), respondem
  const { d, c } = deps({ modo: "sombra", fase2: "ligado", texto: "Anotado." });
  assertEquals((await camadaDaAgenda("choveu", d))?.texto, "Anotado.");
  assertEquals([c.fase2, c.executar], [1, ["choveu"]]);
});

Deno.test("Fase 2 (revisão) — camada: *desfaz <nome>* que o banco não liga a mudança da agenda segue ao modelo; ambíguo e semana ficam", async () => {
  const naoAchei = { ok: true, texto: "Não encontrei Fulano.", seguirAoModelo: true };
  const { d, c } = deps({ modo: "ligado", resposta: naoAchei });
  assertEquals(await camadaDaAgenda("desfaz Fulano", d), null);
  assertEquals(c.executar, ["desfazer"]);
  const amb = deps({ modo: "ligado", resposta: { ok: true, texto: "Qual? Nelson (…) ou Vanderlei (…)?" } });
  assertEquals((await camadaDaAgenda("desfaz Nelson", amb.d))?.texto, "Qual? Nelson (…) ou Vanderlei (…)?");
});

Deno.test("Fase 2 (revisão) — executar: status nao_achei/nenhuma do *desfaz <nome>* marca seguirAoModelo; semana, sem nome e ambíguo não", async () => {
  const resp = (status: string, texto: string) => ({ data: { ok: false, mudou: false, status, texto } });
  const casos: Array<[string, Resposta, boolean]> = [
    ["desfaz Fulano", resp("nao_achei", "Não encontrei Fulano."), true],
    ["desfaz Nelson", resp("nenhuma", "Não tenho mudança minha no Nelson para desfazer agora."), true],
    ["desfaz Vanderlei", resp("fora_da_carteira", "A OS-00069 está concluída."), true],
    ["desfaz Nelson", resp("ambiguo", "Qual Nelson?"), false],
    ["desfaz semana", resp("nenhuma", "Não tenho publicação da semana para desfazer agora."), false],
    ["desfaz", resp("nenhuma", "Não tenho mudança minha para desfazer agora."), false],
    ["desfaz Nelson", { data: { ok: true, mudou: true, texto: "Desfeito." } }, false],
  ];
  for (const [t, r, segue] of casos) {
    const c = cliente({ [RPC_DESFAZER_DITO]: r });
    const res = await executarComandoDaAgenda(c, lerComandoDaAgenda(t)!, { autor: AUTOR });
    assertEquals(res.ok, true, t);
    assertEquals(res.seguirAoModelo === true, segue, `${t}: ${JSON.stringify(r)}`);
  }
});

Deno.test("Fase 2 (revisão) — ehComandoDaAgendaLigada: as palavras da Fase 2 só com modo_proposta ou modo_vigia fora de 'desligado'", async () => {
  const leitura = (fase2: Record<string, unknown>) => adminDoModo({ data: { modo_leitura: "ligado", ...fase2 } });
  for (const t of ["dia feito", "choveu", "desfaz Nelson", "o que mudou?"]) {
    assertEquals(await ehComandoDaAgendaLigada(leitura({ modo_proposta: "desligado", modo_vigia: "desligado" }), t), false, t);
    assertEquals(await ehComandoDaAgendaLigada(leitura({}), t), false, `sem as colunas: ${t}`);
    assertEquals(await ehComandoDaAgendaLigada(leitura({ modo_proposta: "sombra", modo_vigia: "desligado" }), t), true, t);
    assertEquals(await ehComandoDaAgendaLigada(leitura({ modo_proposta: "desligado", modo_vigia: "ligado" }), t), true, t);
  }
  // as da Fase 1 continuam pela leitura, com uma leitura só
  const a = leitura({ modo_proposta: "desligado" });
  assertEquals(await ehComandoDaAgendaLigada(a, "grava"), true);
  assertEquals(a.lidas, ["agenda_config"]);
});

// ─── Fase 3 (P3): *concluiu* e *entreguei* ────────────────────────────────────────────────────────────────────────

Deno.test("Fase 3 — chamadaDoComando: *concluiu* e *entreguei* vão às RPCs delas, com o alvo como o dono disse e o canal", () => {
  assertEquals(chamadaDoComando({ comando: "concluir", alvo: "lenine" }, AUTOR, "2026-10-29", "painel"), {
    rpc: RPC_CONCLUIR_DITO, params: { p_autor: AUTOR, p_alvo: "lenine", p_canal: "painel", p_hoje: "2026-10-29" },
  });
  assertEquals(chamadaDoComando({ comando: "concluir", alvo: null }, AUTOR), {
    rpc: RPC_CONCLUIR_DITO, params: { p_autor: AUTOR, p_alvo: null, p_canal: "whatsapp" },
  });
  assertEquals(chamadaDoComando({ comando: "entregar", alvo: "os-00074" }, AUTOR), {
    rpc: RPC_ENTREGAR_DITO, params: { p_autor: AUTOR, p_alvo: "os-00074", p_canal: "whatsapp" },
  });
});

Deno.test("Fase 3 — executar: o texto do banco volta como veio; nao_achei com alvo segue ao modelo; o resto fica", async () => {
  const concluiu = "Concluí o Lenine (OS-00074) hoje (qui 29/10, 16:30). Saíram as cobranças da condição: Entrada 50% R$ 2.280,00 " +
    "(vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje). *desfaz OS-00074* volta como estava.";
  const c1 = cliente({ [RPC_CONCLUIR_DITO]: { data: { ok: true, mudou: true, status: "ok", texto: concluiu } } });
  assertEquals(await executarComandoDaAgenda(c1, { comando: "concluir", alvo: "lenine" }, { autor: AUTOR }), { ok: true, texto: concluiu });
  // alvo que o banco não acha ("concluiu a instalação"): nada mudou e o pedido é de outra coisa — o turno segue ao modelo
  const naoAchei = { ok: false, mudou: false, status: "nao_achei", texto: "Não encontrei \"Instalação\" entre os serviços da carteira." };
  const c2 = cliente({ [RPC_CONCLUIR_DITO]: { data: naoAchei } });
  assertEquals((await executarComandoDaAgenda(c2, { comando: "concluir", alvo: "instalacao" }, { autor: AUTOR })).seguirAoModelo, true);
  const c3 = cliente({ [RPC_ENTREGAR_DITO]: { data: naoAchei } });
  assertEquals((await executarComandoDaAgenda(c3, { comando: "entregar", alvo: "pedido" }, { autor: AUTOR })).seguirAoModelo, true);
  // ambíguo, já concluída, orçamento, levantamento e a recusa da porta são a resposta: ficam com a agenda
  for (const status of ["ambiguo", "ja_concluida", "orcamento", "recusada", "levantamento"]) {
    const c = cliente({ [RPC_CONCLUIR_DITO]: { data: { ok: status === "ja_concluida", mudou: false, status, texto: `texto ${status}` } } });
    const r = await executarComandoDaAgenda(c, { comando: "concluir", alvo: "lenine" }, { autor: AUTOR });
    assertEquals([r.texto, r.seguirAoModelo], [`texto ${status}`, undefined], status);
  }
  // sem alvo, "nenhuma" no plano de hoje também é a resposta (a palavra sozinha é só da agenda)
  const c4 = cliente({ [RPC_CONCLUIR_DITO]: { data: { ok: false, mudou: false, status: "nenhuma",
    texto: "Hoje não tem serviço no plano para concluir. Diga *concluiu* e o nome do cliente." } } });
  assertEquals((await executarComandoDaAgenda(c4, { comando: "concluir", alvo: null }, { autor: AUTOR })).seguirAoModelo, undefined);
});

Deno.test("Fase 3 — executar nunca lança: o erro do *concluiu* e do *entreguei* vira a frase certa e o log", async () => {
  const casos: Array<[ComandoDaAgenda, string, string]> = [
    [{ comando: "concluir", alvo: "lenine" }, RPC_CONCLUIR_DITO, TEXTO_SEM_CONCLUIR],
    [{ comando: "entregar", alvo: "lenine" }, RPC_ENTREGAR_DITO, TEXTO_SEM_ENTREGAR],
  ];
  for (const [cmd, rpc, frase] of casos) {
    const c = cliente({ [rpc]: { error: { message: "rede", code: "XX000" } } });
    const r = await executarComandoDaAgenda(c, cmd, { autor: AUTOR });
    assertEquals([r.ok, r.texto], [false, frase], rpc);
    assertEquals(c.logs().length, 1, rpc);
  }
});

Deno.test("Fase 3 — camada: *concluiu Lenine* só com a agenda automática fora de 'desligado'; nao_achei segue ao modelo", async () => {
  const deps = (proposta: "desligado" | "sombra", data: unknown): DependenciasDaCamada => ({
    ehDoDono: () => true,
    modo: () => Promise.resolve("sombra"),
    modosDaFase2: () => Promise.resolve({ proposta, vigia: "desligado" }),
    executar: (cmd) => executarComandoDaAgenda(cliente({ [RPC_CONCLUIR_DITO]: { data } }), cmd, { autor: AUTOR }),
  });
  const ok = { ok: true, mudou: true, status: "ok", texto: "Concluí o Lenine (OS-00074) hoje." };
  assertEquals((await camadaDaAgenda("concluiu Lenine", deps("sombra", ok)))?.texto, "Concluí o Lenine (OS-00074) hoje.");
  assertEquals(await camadaDaAgenda("concluiu Lenine", deps("desligado", ok)), null);
  assertEquals(await camadaDaAgenda("concluiu instalação", deps("sombra", { ok: false, status: "nao_achei", texto: "Não encontrei." })), null);
});

// ─── Fase 3 (P4): *diária <nome> inteira|meia|não [quando]* ─────────────────────────────────────────────────────

Deno.test("Fase 3 (P4) — chamadaDoComando: *diária* vai a agenda_diaria_dita com a pessoa, a jornada e o dia como o dono disse", () => {
  assertEquals(chamadaDoComando({ comando: "diaria", nome: "roberto", jornada: "meia", quando: null }, AUTOR, "2026-11-03", "painel"), {
    rpc: RPC_DIARIA_DITA,
    params: { p_autor: AUTOR, p_nome: "roberto", p_jornada: "meia", p_quando: null, p_canal: "painel", p_hoje: "2026-11-03" },
  });
  assertEquals(chamadaDoComando({ comando: "diaria", nome: "joao", jornada: "nao", quando: "ontem" }, AUTOR).params,
               { p_autor: AUTOR, p_nome: "joao", p_jornada: "nao", p_quando: "ontem", p_canal: "whatsapp" });
});

Deno.test("Fase 3 (P4) — executar: o texto do banco volta; nao_achei (nada da agenda) segue ao modelo e ao registrar_diaria", async () => {
  const meia: ComandoDaAgenda = { comando: "diaria", nome: "roberto", jornada: "meia", quando: null };
  const corrigido = "Corrigido: Roberto, ter 03/11, meia diária (era dia inteiro).";
  const c1 = cliente({ [RPC_DIARIA_DITA]: { data: { ok: true, mudou: true, texto: corrigido } } });
  assertEquals(await executarComandoDaAgenda(c1, meia, { autor: AUTOR }), { ok: true, texto: corrigido });
  const c2 = cliente({ [RPC_DIARIA_DITA]: { data: { ok: false, status: "nao_achei", texto: "Não tenho diária da agenda do Roberto para ter 03/11." } } });
  assertEquals((await executarComandoDaAgenda(c2, meia, { autor: AUTOR })).seguirAoModelo, true);
  // ambíguo, a opção que não existe e o dia que não serve são a resposta: ficam com a agenda
  for (const status of ["ambiguo", "opcao", "data"]) {
    const c = cliente({ [RPC_DIARIA_DITA]: { data: { ok: false, status, texto: `texto ${status}` } } });
    const r = await executarComandoDaAgenda(c, meia, { autor: AUTOR });
    assertEquals([r.texto, r.seguirAoModelo], [`texto ${status}`, undefined], status);
  }
  // nunca lança: o erro vira a frase da diária e o log
  const c3 = cliente({ [RPC_DIARIA_DITA]: { error: { message: "rede", code: "XX000" } } });
  const r3 = await executarComandoDaAgenda(c3, meia, { autor: AUTOR });
  assertEquals([r3.ok, r3.texto, c3.logs().length], [false, TEXTO_SEM_DIARIA, 1]);
});

Deno.test("Fase 3 (P4) — camada: *diária Roberto meia* só com modo_diaria fora de desligado (ausente ou erro = desligado)", async () => {
  type Modo = "desligado" | "sombra" | "ligado";
  const deps = (diaria: (() => Promise<Modo>) | undefined, data: unknown): DependenciasDaCamada => ({
    ehDoDono: () => true,
    modo: () => Promise.resolve("sombra"),
    modosDaFase2: () => Promise.resolve({ proposta: "desligado", vigia: "desligado" }),
    ...(diaria ? { modoDaDiaria: diaria } : {}),
    executar: (cmd) => executarComandoDaAgenda(cliente({ [RPC_DIARIA_DITA]: { data } }), cmd, { autor: AUTOR }),
  });
  const ok = { ok: true, mudou: true, texto: "Corrigido: Roberto, ter 03/11, meia diária (era dia inteiro)." };
  assertEquals((await camadaDaAgenda("diária Roberto meia", deps(() => Promise.resolve("sombra"), ok)))?.texto, ok.texto);
  assertEquals((await camadaDaAgenda("diária Roberto meia", deps(() => Promise.resolve("ligado"), ok)))?.texto, ok.texto);
  assertEquals(await camadaDaAgenda("diária Roberto meia", deps(() => Promise.resolve("desligado"), ok)), null);
  assertEquals(await camadaDaAgenda("diária Roberto meia", deps(undefined, ok)), null);
  assertEquals(await camadaDaAgenda("diária Roberto meia", deps(() => Promise.reject(new Error("rede")), ok)), null);
  assertEquals(await camadaDaAgenda("diária Roberto meia",
                                    deps(() => Promise.resolve("sombra"), { ok: false, status: "nao_achei", texto: "x" })), null);
});

Deno.test("Fase 3 (P4) — modoDaDiariaNoBanco: um SELECT só da coluna; erro, coluna ausente ou exceção = desligado", async () => {
  assertEquals(await modoDaDiariaNoBanco(adminDoModo({ data: { modo_diaria: " Ligado " } })), "ligado");
  assertEquals(await modoDaDiariaNoBanco(adminDoModo({ data: { modo_diaria: "sombra" } })), "sombra");
  assertEquals(await modoDaDiariaNoBanco(adminDoModo({ error: { code: "42703", message: "column modo_diaria does not exist" } })), "desligado");
  assertEquals(await modoDaDiariaNoBanco(adminDoModo({ data: null })), "desligado");
  assertEquals(await modoDaDiariaNoBanco(adminDoModo({ lanca: true })), "desligado");
});

Deno.test("Fase 3 (P4) — ehComandoDaAgendaLigada: *diária* só com modo_diaria fora de desligado (e a leitura ligada)", async () => {
  const leitura = (extra: Record<string, unknown>) => adminDoModo({ data: { modo_leitura: "ligado", ...extra } });
  assertEquals(await ehComandoDaAgendaLigada(leitura({ modo_diaria: "sombra" }), "diária Roberto meia"), true);
  assertEquals(await ehComandoDaAgendaLigada(leitura({ modo_diaria: "desligado" }), "diária Roberto meia"), false);
  assertEquals(await ehComandoDaAgendaLigada(leitura({}), "diária Roberto meia"), false);
  assertEquals(await ehComandoDaAgendaLigada(adminDoModo({ data: { modo_leitura: "desligado", modo_diaria: "ligado" } }), "diária Roberto meia"),
               false);
});

// Fase 3 (P6): *agenda ppc*, *agenda equipe* e *comissão [mês]* são agenda_ver (o mesmo mapeamento da ferramenta); o mês
// vai em p_periodo como o dono disse (o banco resolve: _agenda_mes_dito).
Deno.test("Fase 3 (P6) — chamadaDoComando: ppc, equipe e comissão vão à agenda_ver; o mês da comissão em p_periodo, como dito", () => {
  const ver = (t: string) => chamadaDoComando(lerComandoDaAgenda(t)!, AUTOR);
  const base = { p_autor: AUTOR, p_os: null, p_simular: null, p_simular_aprovacao: false, p_pessoa: null };
  assertEquals(ver("agenda ppc"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "ppc" } });
  assertEquals(ver("como foi a semana?"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "ppc" } });
  assertEquals(ver("agenda equipe"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "equipe" } });
  assertEquals(ver("comissão"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "comissao" } });
  assertEquals(ver("*comissão outubro*"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "outubro", p_foco: "comissao" } });
  assertEquals(ver("comissão do mês passado"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: "mes passado", p_foco: "comissao" } });
});

Deno.test("Fase 4 (P6) — chamadaDoComando: *agenda compras* e *agenda fornecedores* vão à agenda_ver, foco compras e fornecedores", () => {
  const ver = (t: string) => chamadaDoComando(lerComandoDaAgenda(t)!, AUTOR);
  const base = { p_autor: AUTOR, p_os: null, p_simular: null, p_simular_aprovacao: false, p_pessoa: null };
  assertEquals(ver("agenda compras"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "compras" } });
  assertEquals(ver("Agenda compras?"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "compras" } });
  assertEquals(ver("*agenda fornecedores*"), { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "fornecedores" } });
});

// ─── Fase 5 (P5): *manda cliente* / *segura cliente* e *agenda clientes* ─────────────────────────────────────


Deno.test("Fase 5 (P5) — chamadaDoComando: *manda/segura cliente* → agenda_cliente_decidir_dito com a ação, o nome e o canal; *agenda clientes* → agenda_ver foco clientes", () => {
  assertEquals(chamadaDoComando({ comando: "cliente", acao: "manda", alvo: "nelson" }, AUTOR, "2026-10-30", "whatsapp"), {
    rpc: RPC_CLIENTE_DITO, params: { p_autor: AUTOR, p_acao: "manda", p_alvo: "nelson", p_canal: "whatsapp", p_hoje: "2026-10-30" },
  });
  assertEquals(chamadaDoComando({ comando: "cliente", acao: "segura", alvo: null }, AUTOR, undefined, "painel"), {
    rpc: RPC_CLIENTE_DITO, params: { p_autor: AUTOR, p_acao: "segura", p_alvo: null, p_canal: "painel" },
  });
  const ver = chamadaDoComando(lerComandoDaAgenda("agenda clientes") as ComandoDaAgenda, AUTOR);
  assertEquals([ver.rpc, ver.params.p_foco], [RPC_AGENDA_VER, "clientes"]);
});

Deno.test("Fase 5 (P5) — executar: o texto do banco vale (também o 'Não achei…', que não segue ao modelo); erro = frase + log", async () => {
  const manda: ComandoDaAgenda = { comando: "cliente", acao: "manda", alvo: "nelson" };
  const ok = cliente({ [RPC_CLIENTE_DITO]: { data: { ok: true, status: "ok", texto: "Mando para Nelson amanhã às 09:01." } } });
  assertEquals(await executarComandoDaAgenda(ok, manda, { autor: AUTOR }), { ok: true, texto: "Mando para Nelson amanhã às 09:01." });
  const nao = cliente({ [RPC_CLIENTE_DITO]: { data: { ok: false, status: "nao_achei", texto: "Não achei mensagem esperando para \"orçamento\"." } } });
  const r = await executarComandoDaAgenda(nao, { comando: "cliente", acao: "manda", alvo: "orcamento" }, { autor: AUTOR });
  assertEquals([r.ok, r.texto, r.seguirAoModelo], [true, "Não achei mensagem esperando para \"orçamento\".", undefined]);
  const erro = cliente({ [RPC_CLIENTE_DITO]: { error: { message: "rede", code: "XX000" } } });
  const r2 = await executarComandoDaAgenda(erro, manda, { autor: AUTOR });
  assertEquals([r2.ok, r2.texto, erro.logs().length], [false, TEXTO_SEM_CLIENTE, 1]);
  assertEquals(erro.logs()[0].p_action, "comando:cliente");
  const so = cliente({ [RPC_CLIENTE_DITO]: { error: { message: "Só o administrador mexe na agenda.", code: "42501" } } });
  assertEquals((await executarComandoDaAgenda(so, manda, { autor: AUTOR })).texto, TEXTO_SO_ADMIN);
});

Deno.test("Fase 5 (P5) — camada: as palavras do cliente só com modo_cliente fora de desligado (ausente ou erro = desligado)", async () => {
  type Modo = "desligado" | "sombra" | "ligado";
  const deps = (mc: (() => Promise<Modo>) | undefined): DependenciasDaCamada => ({
    ehDoDono: () => true,
    modo: () => Promise.resolve("sombra"),
    modosDaFase2: () => Promise.resolve({ proposta: "ligado", vigia: "ligado" }),
    ...(mc ? { modoDoCliente: mc } : {}),
    executar: (cmd) => executarComandoDaAgenda(cliente({
      [RPC_CLIENTE_DITO]: { data: { ok: false, status: "em_teste", texto: "As mensagens ao cliente estão em teste: nada sai ainda." } },
      [RPC_AGENDA_VER]: { data: { ok: true, texto: "Mensagens ao cliente (em teste: nada sai ainda):" } },
    }), cmd, { autor: AUTOR }),
  });
  for (const t of ["manda cliente Nelson", "segura cliente", "agenda clientes"]) {
    assert((await camadaDaAgenda(t, deps(() => Promise.resolve("sombra"))))?.texto, t);
    assert((await camadaDaAgenda(t, deps(() => Promise.resolve("ligado"))))?.texto, t);
    assertEquals(await camadaDaAgenda(t, deps(() => Promise.resolve("desligado"))), null, t);
    assertEquals(await camadaDaAgenda(t, deps(undefined)), null, t);
    assertEquals(await camadaDaAgenda(t, deps(() => Promise.reject(new Error("rede")))), null, t);
  }
  assertEquals((await camadaDaAgenda("manda cliente Nelson", deps(() => Promise.resolve("sombra"))))?.texto,
               "As mensagens ao cliente estão em teste: nada sai ainda.");
  // os pedidos normais nem chegam a ler o modo
  let lidas = 0;
  const contando = deps(() => { lidas++; return Promise.resolve("ligado"); });
  for (const t of ["manda pro cliente o PDF", "manda o orçamento do Brisa", "manda cliente o orçamento"]) {
    assertEquals(await camadaDaAgenda(t, contando), null, t);
  }
  assertEquals(lidas, 0);
});

Deno.test("Fase 5 (P5) — modoDoClienteNoBanco: um SELECT só da coluna; erro, coluna ausente ou exceção = desligado", async () => {
  assertEquals(await modoDoClienteNoBanco(adminDoModo({ data: { modo_cliente: "ligado" } })), "ligado");
  assertEquals(await modoDoClienteNoBanco(adminDoModo({ data: { modo_cliente: "sombra" } })), "sombra");
  assertEquals(await modoDoClienteNoBanco(adminDoModo({ error: { code: "42703" } })), "desligado");
  assertEquals(await modoDoClienteNoBanco(adminDoModo({ data: null })), "desligado");
  assertEquals(await modoDoClienteNoBanco(adminDoModo({ lanca: true })), "desligado");
});

// ─── Fase 6 (P8): *agenda aprendizado* e *desfaz aprendizado* ───────────────────────────────────────────────────────

Deno.test("Fase 6 (P8) — chamadaDoComando: *agenda aprendizado* → agenda_ver foco aprendizado; *desfaz aprendizado* → agenda_desfazer_dito com o alvo", () => {
  const base = { p_autor: AUTOR, p_os: null, p_simular: null, p_simular_aprovacao: false, p_pessoa: null };
  assertEquals(chamadaDoComando(lerComandoDaAgenda("agenda aprendizado") as ComandoDaAgenda, AUTOR),
               { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "aprendizado" } });
  assertEquals(chamadaDoComando(lerComandoDaAgenda("Agenda aprendizado?") as ComandoDaAgenda, AUTOR, "2026-10-30"),
               { rpc: RPC_AGENDA_VER, params: { ...base, p_periodo: null, p_foco: "aprendizado", p_hoje: "2026-10-30" } });
  assertEquals(chamadaDoComando(lerComandoDaAgenda("desfaz aprendizado") as ComandoDaAgenda, AUTOR, "2026-10-30", "whatsapp"),
               { rpc: RPC_DESFAZER_DITO, params: { p_autor: AUTOR, p_alvo: "aprendizado", p_canal: "whatsapp", p_hoje: "2026-10-30" } });
});

Deno.test("Fase 6 (P8) — executar: o texto do foco e o do *desfaz aprendizado* vêm do banco; erro = frase + log", async () => {
  const ver = lerComandoDaAgenda("agenda aprendizado") as ComandoDaAgenda;
  const ok = cliente({ [RPC_AGENDA_VER]: { data: { ok: true, texto: "O que a agenda aprendeu com o que aconteceu (em teste: nada disto muda o plano ainda):" } } });
  assertEquals(await executarComandoDaAgenda(ok, ver, { autor: AUTOR }),
               { ok: true, texto: "O que a agenda aprendeu com o que aconteceu (em teste: nada disto muda o plano ainda):" });
  const desfaz = lerComandoDaAgenda("desfaz aprendizado") as ComandoDaAgenda;
  const nada = cliente({ [RPC_DESFAZER_DITO]: { data: { ok: false, status: "nenhuma", texto: "Não tenho mudança do aprendizado para desfazer agora." } } });
  const r = await executarComandoDaAgenda(nada, desfaz, { autor: AUTOR });
  assertEquals([r.ok, r.texto], [true, "Não tenho mudança do aprendizado para desfazer agora."]);
  const erro = cliente({ [RPC_AGENDA_VER]: { error: { message: "rede", code: "XX000" } } });
  const r2 = await executarComandoDaAgenda(erro, ver, { autor: AUTOR });
  assertEquals([r2.ok, r2.texto, erro.logs().length], [false, TEXTO_SEM_AGENDA, 1]);
  const so = cliente({ [RPC_AGENDA_VER]: { error: { message: "O que a agenda aprendeu é com o administrador ou o financeiro.", code: "42501" } } });
  assertEquals((await executarComandoDaAgenda(so, ver, { autor: AUTOR })).texto, TEXTO_SO_ADMIN);
});
