// Agenda de Produção, Fase 1 (P6): as palavras da agenda com o banco de mentira — a RPC certa com os parâmetros
// certos, o texto do banco repassado sem mexer, nunca lança (erro vira frase + app_error_logs), o modo desligado não
// intercepta e o que não é do dono segue ao modelo.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { frasesDaAgenda, lerComandoDaAgenda } from "./comandos.ts";
import {
  camadaDaAgenda,
  chamadaDoComando,
  type DependenciasDaCamada,
  ehComandoDaAgendaLigada,
  executarComandoDaAgenda,
  lerModoDaLeitura,
  modoDaLeituraNoBanco,
  rascunhoAbertoNoBanco,
  RPC_DESCARTAR,
  RPC_GRAVAR,
  TEXTO_SEM_AGENDA,
  TEXTO_SEM_DESCARTAR,
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
}) {
  const c = { dono: 0, modo: 0, executar: [] as string[], rascunho: 0 };
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
      return Promise.resolve({ ok: true, texto: p.texto ?? "texto do banco" });
    },
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
