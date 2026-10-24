// Agenda de Produção, Fase 1 (P5): as 4 ferramentas da agenda (agenda-producao.ts) com o banco falso.
//   · chamam a RPC certa, com p_autor = quem fala e p_canal pelo canal (painel × WhatsApp);
//   · erro do banco LANÇA (nunca vira "nada marcado");
//   · {ok:false, pergunta} passa adiante como pergunta, sem id;
//   · só o admin; nenhuma recebe id nem data calculada; as três de escrita exigem o trecho;
//   · as descrições dizem o que NÃO fazem (não grava, não agenda, não cria OC).
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/agenda-producao_test.ts
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { agendaProducaoTools } from "./agenda-producao.ts";
import { allTools } from "./index.ts";
import type { ToolDef } from "./registry.ts";

const porNome = (n: string) => agendaProducaoTools.find((t) => t.name === n)!;
const ADMIN = "aa000000-0000-4000-8000-000000000001";

type Chamada = { nome: string; params: Record<string, unknown> };

function sbFalso(resposta: (c: Chamada) => { data: unknown; error: unknown }) {
  const chamadas: Chamada[] = [];
  return {
    chamadas,
    sb: {
      rpc(nome: string, params: Record<string, unknown>) {
        const c = { nome, params };
        chamadas.push(c);
        return Promise.resolve(resposta(c));
      },
      from() {
        throw new Error("a ferramenta da agenda não lê tabela: chama uma RPC só");
      },
    },
  };
}

const ctx = (sb: unknown, extra: Record<string, unknown> = {}) =>
  ({ sb, admin: sb, userId: ADMIN, userRole: "admin", jwt: "", appOrigin: "", settings: {}, ...extra }) as never;

Deno.test("as 8 estão em allTools, risco low, só admin", () => {
  for (const nome of [
    "agenda_ver", "os_planejar", "material_informar", "equipe_disponibilidade",
    "agenda_propor", "agenda_aplicar", "agenda_desfazer", "os_registrar_andamento",
  ]) {
    const t = allTools.find((x) => x.name === nome);
    assert(t, `${nome} fora de allTools`);
    assertEquals(t!.risk, "low", nome);
    assertEquals(t!.roles, ["admin"], nome);
  }
});

Deno.test("agenda_ver: chama agenda_ver com p_autor e devolve o texto pronto + a instrução, sem os dados", async () => {
  const { sb, chamadas } = sbFalso(() => ({
    data: { ok: true, texto: "Hoje (sex 23/10): nada marcado.", rota: "o_que_fazer", dados: { oss: [] } },
    error: null,
  }));
  const r = await porNome("agenda_ver").execute({ foco: "o_que_fazer" }, ctx(sb)) as Record<string, unknown>;
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].nome, "agenda_ver");
  assertEquals(chamadas[0].params.p_autor, ADMIN);
  assertEquals(chamadas[0].params.p_foco, "o_que_fazer");
  assertEquals("p_hoje" in chamadas[0].params, false, "em produção o dia é o do banco");
  assertEquals(r.texto, "Hoje (sex 23/10): nada marcado.");
  assertEquals(r.instrucao, "Repita o texto; pode encurtar o fim, nunca mude número, data ou nome.");
  assertEquals("dados" in r, false);
});

Deno.test("as três de escrita: a RPC do rascunho, p_canal = painel no painel e whatsapp fora dele", async () => {
  const casos: Array<[string, Record<string, unknown>, string]> = [
    ["os_planejar", { os: "Lenine", dias: 2, trecho: "Lenine dois dias" }, "agenda_rascunho_planejar"],
    ["material_informar", { os: "Nelson", itens: ["painel"], situacao: "a_caminho", quando: "dia 3", trecho: "o painel chega dia 3" },
      "agenda_rascunho_material"],
    ["equipe_disponibilidade", { pessoa: "Roberto", situacao: "nao_vem", dias: "terça", trecho: "o Roberto não vem terça" },
      "agenda_rascunho_disponibilidade"],
  ];
  for (const [nome, args, rpc] of casos) {
    for (const [canal, esperado] of [["panel", "painel"], ["whatsapp", "whatsapp"], [undefined, "whatsapp"]] as const) {
      const { sb, chamadas } = sbFalso(() => ({
        data: { ok: true, item: "x", releitura: "Entendi assim, confere?\n• x.\nResponda *grava* ou corrija o que estiver errado." },
        error: null,
      }));
      const r = await porNome(nome).execute(args, ctx(sb, canal ? { canal } : {})) as Record<string, unknown>;
      assertEquals(chamadas.map((c) => c.nome), [rpc], nome);
      assertEquals(chamadas[0].params.p_autor, ADMIN, nome);
      assertEquals(chamadas[0].params.p_canal, esperado, `${nome} ${canal}`);
      assertEquals(r.ok, true);
      assertStringIncludes(String(r.texto), "Entendi assim, confere?");
      assertEquals(r.instrucao, "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.");
    }
  }
});

Deno.test("erro do banco LANÇA nas oito (nunca vira agenda vazia nem 'anotado')", async () => {
  const args: Record<string, Record<string, unknown>> = {
    agenda_ver: { foco: "atrasos" },
    os_planejar: { os: "Lenine", dias: 2, trecho: "dois dias" },
    material_informar: { os: "Nelson", itens: ["painel"], situacao: "na_mao", trecho: "chegou" },
    equipe_disponibilidade: { pessoa: "eu", situacao: "vem", dias: "segunda a sexta", padrao: true, trecho: "segunda a sexta" },
    agenda_propor: { escopo: "semana", tirar: ["Rodrigo"] },
    agenda_aplicar: { decisao: "1", opcao: "1", trecho: "pode atrasar o Nelson" },
    agenda_desfazer: { alvo: "Nelson", trecho: "desfaz o Nelson" },
    os_registrar_andamento: { os: "Vanderlei", evento: "trabalhou", quem: ["Roberto"], dia: "hoje", trecho: "hoje o Roberto trabalhou" },
  };
  for (const t of agendaProducaoTools) {
    const { sb } = sbFalso(() => ({ data: null, error: { message: "permission denied", code: "42501" } }));
    await assertRejects(() => t.execute(args[t.name], ctx(sb)), t.name);
    const vazio = sbFalso(() => ({ data: null, error: null }));
    await assertRejects(() => t.execute(args[t.name], ctx(vazio.sb)), Error, "respondeu sem texto", t.name);
  }
});

Deno.test("{ok:false, pergunta} passa adiante: o modelo faz a pergunta; opções sem id", async () => {
  const { sb } = sbFalso(() => ({
    data: {
      ok: false, motivo: "os_ambiguo", texto: "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?",
      pergunta: "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?", opcoes: ["OS-00076 (Starlink…)", "OS-00096 (Visita técnica…)"],
    },
    error: null,
  }));
  const r = await porNome("os_planejar").execute({ os: "Rodrigo", dias: 0.5, trecho: "o do Rodrigo é meio dia, só eu" }, ctx(sb)) as
    Record<string, unknown>;
  assertEquals(r.ok, false);
  assertEquals(r.pergunta, "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?");
  assertEquals(r.opcoes, ["OS-00076 (Starlink…)", "OS-00096 (Visita técnica…)"]);
  assertStringIncludes(String(r.instrucao), "Nada entrou no rascunho");
});

Deno.test("agenda desligada (modo_leitura): agenda_ver manda à my_agenda; as três de escrita repassam a recusa, sem *grava*", async () => {
  // A resposta de agenda_ver com a agenda desligada (supabase/tests/agenda_fase1_leituras.sql, B6b).
  const { sb: sbVer } = sbFalso(() => ({
    data: { ok: false, rota: "desligada", desligada: true, texto: "A agenda de produção está desligada agora." },
    error: null,
  }));
  const ver = await porNome("agenda_ver").execute({ foco: "o_que_fazer" }, ctx(sbVer)) as Record<string, unknown>;
  assertEquals(ver.ok, false);
  assertEquals(ver.desligada, true);
  assertStringIncludes(String(ver.instrucao), "my_agenda pela ferramenta_extra");
  // A recusa das RPCs de rascunho com a agenda desligada (supabase/tests/agenda_fase1_rascunho.sql, M1).
  const recusa = "A agenda de produção está desligada agora: não anotei nada.";
  const casos: Array<[string, Record<string, unknown>]> = [
    ["os_planejar", { os: "Lenine", dias: 2, trecho: "Lenine dois dias" }],
    ["material_informar", { os: "Nelson", itens: ["painel"], situacao: "na_mao", trecho: "o painel chegou" }],
    ["equipe_disponibilidade", { pessoa: "Roberto", situacao: "nao_vem", dias: "terça", trecho: "o Roberto não vem terça" }],
  ];
  for (const [nome, args] of casos) {
    const { sb, chamadas } = sbFalso(() => ({
      data: { ok: false, motivo: "desligada", texto: recusa, pergunta: recusa, opcoes: [] },
      error: null,
    }));
    const r = await porNome(nome).execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 1, nome);
    assertEquals([r.ok, r.texto], [false, recusa], nome);
    assertEquals(String(r.texto).includes("*grava*"), false, nome);
  }
});

Deno.test("argumento errado volta como { error } e NADA é chamado (trecho, enum, id, data calculada)", async () => {
  const casos: Array<[string, Record<string, unknown>, string]> = [
    ["os_planejar", { os: "Lenine", dias: 2 }, "falta 'trecho'"],
    ["material_informar", { os: "Nelson", itens: ["painel"], situacao: "chegou", trecho: "chegou" }, "'situacao' aceita só"],
    ["material_informar", { os: "Nelson", itens: ["painel"], situacao: "a_caminho", quando: "2026-11-03", trecho: "dia 3" }, "sem calcular"],
    ["equipe_disponibilidade", { pessoa: "aa000000-0000-4000-8000-000000000002", situacao: "vem", dias: "terça", trecho: "x" }, "não o id"],
    ["agenda_ver", { os: "05000000-0000-4000-8000-000000000112" }, "não o id"],
    ["agenda_ver", { foco: "semana" }, "'foco' aceita só"],
  ];
  for (const [nome, args, trecho] of casos) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
    const r = await porNome(nome).execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 0, `${nome} chamou o banco com argumento errado`);
    assertStringIncludes(String(r.error), trecho, nome);
  }
});

Deno.test("só o admin: técnico, financeiro e vendedor recebem recusa sem chamar o banco (WhatsApp roda com service role)", async () => {
  for (const cargo of ["technician", "financial", "seller", "external_seller", "unknown"]) {
    for (const t of agendaProducaoTools) {
      const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
      const r = await t.execute({ os: "Lenine", foco: "tudo", trecho: "x" }, ctx(sb, { userRole: cargo })) as Record<string, unknown>;
      assertEquals(chamadas.length, 0, `${t.name} chamou o banco para ${cargo}`);
      assertEquals(r.error, "Só o administrador mexe na agenda de produção.");
    }
  }
});

/** Todas as propriedades (com as aninhadas) de um input_schema. */
function propriedades(schema: Record<string, unknown>, prefixo = ""): Array<[string, Record<string, unknown>]> {
  const props = (schema.properties ?? {}) as Record<string, Record<string, unknown>>;
  return Object.entries(props).flatMap(([k, v]) => [
    [prefixo + k, v] as [string, Record<string, unknown>],
    ...(v.properties ? propriedades(v, `${prefixo}${k}.`) : []),
    ...((v.items as Record<string, unknown> | undefined)?.properties
      ? propriedades(v.items as Record<string, unknown>, `${prefixo}${k}[].`)
      : []),
  ]);
}

Deno.test("nenhuma recebe id nem data/hora calculada: sem campo *_id/id, sem format date/date-time", () => {
  for (const t of agendaProducaoTools) {
    for (const [campo, def] of propriedades(t.input_schema)) {
      assertEquals(/(^|\.)id$|_id$/.test(campo), false, `${t.name}.${campo} recebe id`);
      assertEquals(["date", "date-time"].includes(String(def.format ?? "")), false, `${t.name}.${campo} recebe data calculada`);
    }
  }
});

Deno.test("as seis de rascunho exigem o trecho; a leitura não exige nada; a simulação só o escopo", () => {
  for (const nome of ["os_planejar", "material_informar", "equipe_disponibilidade", "agenda_aplicar", "agenda_desfazer", "os_registrar_andamento"]) {
    assert((porNome(nome).input_schema.required as string[]).includes("trecho"), nome);
  }
  assertEquals(porNome("agenda_ver").input_schema.required, undefined);
  assertEquals(porNome("agenda_propor").input_schema.required, ["escopo"]);
});

Deno.test("as descrições dizem o que NÃO fazem e ensinam a fronteira com as vizinhas", () => {
  const d = (n: string) => porNome(n).description;
  for (const nome of ["os_planejar", "material_informar", "equipe_disponibilidade"]) {
    assertStringIncludes(d(nome), "RASCUNHO", nome);
    assertStringIncludes(d(nome), "NÃO grava", nome);
    assertStringIncludes(d(nome), "*grava*", nome);
  }
  assertStringIncludes(d("agenda_ver"), "Só lê");
  assertStringIncludes(d("agenda_ver"), "create_task");
  assertStringIncludes(d("agenda_ver"), "schedule_service_order");
  for (const vizinha of ["os_planejar", "material_informar", "equipe_disponibilidade"]) {
    assertStringIncludes(d("agenda_ver"), vizinha);
  }
  assertStringIncludes(d("material_informar"), "get_purchase_needs");
  assertStringIncludes(d("material_informar"), "ordem de compra");
  assertStringIncludes(d("os_planejar"), "Não agenda OS");
  // As vizinhas que parecem a mesma coisa: o dia que já aconteceu (registrar_diaria) e a peça que entra na OS
  // (add_service_order_item).
  assertStringIncludes(d("equipe_disponibilidade"), "registrar_diaria");
  assertStringIncludes(d("material_informar"), "add_service_order_item");
});

Deno.test("cada execute chama UMA RPC e não lê tabela (o texto é do banco)", () => {
  for (const t of agendaProducaoTools as ToolDef[]) {
    const corpo = String(t.execute);
    assertEquals(/\.from\(/.test(corpo), false, `${t.name} lê tabela direto`);
  }
});

// ───────── Fase 2 (P6): agenda_propor, agenda_aplicar, agenda_desfazer, os_registrar_andamento ─────────

const RELEITURA = { ok: true, item: "x", releitura: "Entendi assim, confere?\n• x.\nResponda *grava* ou corrija o que estiver errado." };

Deno.test("Fase 2: cada uma chama a RPC certa, com p_autor e p_canal (painel × WhatsApp)", async () => {
  const casos: Array<[string, Record<string, unknown>, string, unknown]> = [
    ["agenda_propor", { escopo: "semana", tirar: ["Rodrigo"] }, "agenda_propor_dito",
      { ok: true, texto: "Semana de 03 a 06/11\nNada a mudar.\nÉ simulação: não muda nada.", simulacao: true, itens: [], perguntas: [] }],
    ["agenda_aplicar", { decisao: "1", opcao: "1", trecho: "pode atrasar o Nelson" }, "agenda_rascunho_aplicar", RELEITURA],
    ["agenda_desfazer", { alvo: "Nelson", trecho: "desfaz o Nelson" }, "agenda_rascunho_desfazer", RELEITURA],
    ["os_registrar_andamento", { os: "Vanderlei", evento: "trabalhou", quem: ["Roberto"], trecho: "o Roberto fez o dia todo" },
      "agenda_rascunho_andamento", RELEITURA],
  ];
  for (const [nome, args, rpc, resposta] of casos) {
    for (const [canal, esperado] of [["panel", "painel"], ["whatsapp", "whatsapp"], [undefined, "whatsapp"]] as const) {
      const { sb, chamadas } = sbFalso(() => ({ data: resposta, error: null }));
      const r = await porNome(nome).execute(args, ctx(sb, canal ? { canal } : {})) as Record<string, unknown>;
      assertEquals(chamadas.map((c) => c.nome), [rpc], nome);
      assertEquals(chamadas[0].params.p_autor, ADMIN, nome);
      assertEquals(chamadas[0].params.p_canal, esperado, `${nome} ${canal}`);
      assertEquals("p_hoje" in chamadas[0].params, false, `${nome}: em produção o dia é o do banco`);
      assertEquals("p_agora" in chamadas[0].params, false, `${nome}: a hora é a do banco (o modelo nunca manda timestamptz)`);
      assertEquals(r.ok, true, nome);
    }
  }
});

Deno.test("agenda_propor: simular é true por padrão; só o false explícito grava a proposta em aberto", async () => {
  const { sb, chamadas } = sbFalso(() => ({
    data: { ok: true, texto: "Semana de 03 a 06/11\n• Vanderlei (OS-00069): ter 03 a qui 05/11.\nÉ simulação: não muda nada.", simulacao: true },
    error: null,
  }));
  const r = await porNome("agenda_propor").execute({ escopo: "proxima_semana" }, ctx(sb)) as Record<string, unknown>;
  assertEquals(chamadas[0].params.p_simular, true);
  assertEquals(chamadas[0].params.p_escopo, "proxima_semana");
  assertEquals(chamadas[0].params.p_acima_da_carga, false);
  assertEquals(r.simulacao, true);
  assertStringIncludes(String(r.texto), "É simulação: não muda nada.");
  assertStringIncludes(String(r.instrucao), "É simulação: nada mudou");
  assertStringIncludes(String(r.instrucao), "não diga que marcou");

  const aberta = sbFalso(() => ({ data: { ok: true, texto: "Semana de 03 a 06/11\n• x.", simulacao: false }, error: null }));
  const r2 = await porNome("agenda_propor").execute({ escopo: "semana", simular: false }, ctx(aberta.sb)) as Record<string, unknown>;
  assertEquals(aberta.chamadas[0].params.p_simular, false);
  assertEquals(r2.simulacao, false);
  assertStringIncludes(String(r2.instrucao), "não vale para ninguém");
  assertStringIncludes(String(r2.instrucao), "*grava*");
});

Deno.test("agenda_propor: ao modelo vai só o texto e as perguntas em texto — nada de itens, alocações nem ids", async () => {
  const { sb } = sbFalso(() => ({
    data: {
      ok: true, simulacao: true, proposta_id: null, texto: "Semana de 03 a 06/11\n• Vanderlei.\nÉ simulação: não muda nada.",
      itens: [{ os: "05000000-0000-4000-8000-000000000069", alocacoes: [{ payee_id: "bb000000-0000-4000-8000-000000000002" }] }],
      perguntas: [{ tipo: "nao_cabe", texto: "Não cabe tudo até qui 05/11. Qual aceita atrasar?", opcoes: [{ n: 1, os: "05000000-0000-4000-8000-000000000112" }] }],
    },
    error: null,
  }));
  const r = await porNome("agenda_propor").execute({ escopo: "semana" }, ctx(sb)) as Record<string, unknown>;
  assertEquals(r.perguntas, ["Não cabe tudo até qui 05/11. Qual aceita atrasar?"]);
  for (const campo of ["itens", "proposta_id", "alocacoes", "carga", "pontuacao"]) assertEquals(campo in r, false, campo);
  assertEquals(/[0-9a-f]{8}-[0-9a-f]{4}-/.test(JSON.stringify(r)), false, "id vazou para o modelo");
});

Deno.test("agenda_propor: o que o dono testa vira o parâmetro como ele disse (fixar, tirar, só depois de)", async () => {
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x", simulacao: true }, error: null }));
  await porNome("agenda_propor").execute({
    escopo: "os", os: ["Lenine"], fixar: [{ os: "Lenine", quando: "quinta que vem" }], tirar: "Rodrigo",
    so_depois_de: [{ os: "Nelson", quando: "dia 10" }], acima_da_carga: true,
    trecho: "e se o Lenine for quinta que vem, sem o Rodrigo, e o Nelson só depois do dia 10, mesmo acima da carga?",
  }, ctx(sb));
  const p = chamadas[0].params;
  assertEquals(p.p_os, ["Lenine"]);
  assertEquals(p.p_fixar, [{ os: "Lenine", quando: "quinta que vem" }]);
  assertEquals(p.p_tirar, ["Rodrigo"]);
  assertEquals(p.p_so_depois_de, [{ os: "Nelson", quando: "dia 10" }]);
  assertEquals(p.p_acima_da_carga, true);
  assertEquals(p.p_trecho, "e se o Lenine for quinta que vem, sem o Rodrigo, e o Nelson só depois do dia 10, mesmo acima da carga?");
});

Deno.test("agenda_propor (revisão da Fase 2): fixar ou só depois de sem o trecho do dono = recusa, nada chamado", async () => {
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x", simulacao: true }, error: null }));
  const r = await porNome("agenda_propor").execute({ escopo: "os", fixar: [{ os: "Lenine", quando: "quinta" }] }, ctx(sb)) as Record<string, unknown>;
  assertEquals(String(r.error).startsWith("falta 'trecho'"), true);
  assertEquals(chamadas.length, 0);
});

Deno.test("agenda_aplicar: sem opção dita, NADA é escolhido aqui — vai nulo e a pergunta do banco volta", async () => {
  const pergunta = "Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa…; 2) Deixo o Nelson fora…";
  const { sb, chamadas } = sbFalso(() => ({
    data: { ok: false, motivo: "sem_opcao", texto: pergunta, pergunta, opcoes: ["1) Nelson (OS-00112) atrasa…", "2) Deixo o Nelson fora…"] },
    error: null,
  }));
  const r = await porNome("agenda_aplicar").execute({ decisao: "1", trecho: "resolve aí do jeito que achar melhor" }, ctx(sb)) as
    Record<string, unknown>;
  assertEquals(chamadas[0].params.p_opcao, null);
  assertEquals(chamadas[0].params.p_decisao, "1");
  assertEquals(r.ok, false);
  assertEquals(r.pergunta, pergunta);
  assertEquals(r.opcoes, ["1) Nelson (OS-00112) atrasa…", "2) Deixo o Nelson fora…"]);
  assertStringIncludes(String(r.instrucao), "Faça esta pergunta ao dono como está");
});

Deno.test("Fase 2: argumento errado volta como { error } e NADA é chamado", async () => {
  const casos: Array<[string, Record<string, unknown>, string]> = [
    ["agenda_propor", { escopo: "mes" }, "'escopo' aceita só"],
    ["agenda_propor", {}, "falta 'escopo'"],
    ["agenda_propor", { escopo: "os" }, "diga de qual serviço"],
    ["agenda_propor", { escopo: "os", fixar: [{ os: "Lenine", quando: "2026-11-05" }] }, "sem calcular"],
    ["agenda_propor", { escopo: "os", fixar: [{ os: "Lenine" }] }, "falta 'fixar[0].quando'"],
    ["agenda_propor", { escopo: "semana", tirar: ["05000000-0000-4000-8000-000000000096"] }, "não o id"],
    ["agenda_propor", { escopo: "semana", simular: "sim" }, "'simular' tem de ser true ou false"],
    ["agenda_aplicar", { decisao: "1", opcao: "1" }, "falta 'trecho'"],
    ["agenda_aplicar", { proposta: "a última", decisao: "1", trecho: "x" }, "a proposta OU a decisão"],
    ["agenda_aplicar", { decisao: "df23fd81-0d86-4a86-ae86-5ad982b07ef9", opcao: "1", trecho: "x" }, "não o id"],
    ["agenda_desfazer", { alvo: "Nelson" }, "falta 'trecho'"],
    // FASE 3 (P3): concluir deixou de ser recusa (vira rascunho com a releitura); sem o trecho, continua recusado aqui.
    ["os_registrar_andamento", { os: "Vanderlei", evento: "concluiu" }, "falta 'trecho'"],
    ["os_registrar_andamento", { os: "Vanderlei", evento: "faltou", trecho: "x" }, "'evento' aceita só"],
    ["os_registrar_andamento", { os: "Vanderlei", evento: "nao_foi", motivo: "doença", trecho: "x" }, "'motivo' aceita só"],
    ["os_registrar_andamento", { os: "Vanderlei", evento: "trabalhou", dia: "2026-11-03", trecho: "x" }, "sem calcular"],
    ["os_registrar_andamento", { evento: "trabalhou", trecho: "x" }, "falta 'os'"],
  ];
  for (const [nome, args, trecho] of casos) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
    const r = await porNome(nome).execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 0, `${nome} chamou o banco com argumento errado (${JSON.stringify(args)})`);
    assertStringIncludes(String(r.error), trecho, `${nome} ${JSON.stringify(args)}`);
  }
});

Deno.test("Fase 2: em teste (modo_proposta fora de ligado) a recusa do banco passa adiante, sem *grava*", async () => {
  const recusa = "A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.";
  const casos: Array<[string, Record<string, unknown>]> = [
    ["agenda_aplicar", { proposta: "a última", trecho: "pode publicar" }],
    ["agenda_desfazer", { alvo: "semana", trecho: "desfaz a semana" }],
    ["os_registrar_andamento", { os: "Vanderlei", evento: "trabalhou", trecho: "o Vanderlei andou hoje" }],
  ];
  for (const [nome, args] of casos) {
    const { sb } = sbFalso(() => ({ data: { ok: false, motivo: "em_teste", texto: recusa, pergunta: recusa, opcoes: [] }, error: null }));
    const r = await porNome(nome).execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals([r.ok, r.texto], [false, recusa], nome);
    assertEquals(String(r.texto).includes("*grava*"), false, nome);
  }
});

Deno.test("Fase 2: as descrições dizem o que NÃO fazem e a fronteira com as vizinhas", () => {
  const d = (n: string) => porNome(n).description;
  assertStringIncludes(d("agenda_propor"), "NÃO publica");
  assertStringIncludes(d("agenda_propor"), "simular = true (o padrão) não grava nada");
  assertStringIncludes(d("agenda_propor"), "não decide qual OS atrasa");
  for (const nome of ["agenda_aplicar", "agenda_desfazer", "os_registrar_andamento"]) {
    assertStringIncludes(d(nome), "RASCUNHO", nome);
    assertStringIncludes(d(nome), "*grava*", nome);
  }
  assertStringIncludes(d("agenda_aplicar"), "NÃO grava");
  assertStringIncludes(d("agenda_aplicar"), "Nunca escolha a opção pelo dono");
  assertStringIncludes(d("agenda_desfazer"), "NÃO desfaz");
  // FASE 3 (P3): o andamento conclui e entrega (a releitura diz a saída e as cobranças); a descrição diz o que ele não é.
  assertStringIncludes(d("os_registrar_andamento"), "concluir gera a saída e as cobranças da");
  assertStringIncludes(d("os_registrar_andamento"), "nada sai sem o *grava* do dono");
  assertStringIncludes(d("os_registrar_andamento"), "update_service_order_status");
  // As vizinhas que parecem a mesma coisa (spec §12, riscos): marcar num dia, a diária e a chegada do técnico.
  const fronteiras: Array<[string, string]> = [
    ["agenda_propor", "schedule_service_order"], ["agenda_propor", "agenda_aplicar"], ["agenda_aplicar", "schedule_service_order"],
    ["agenda_aplicar", "agenda_ver foco decisoes"], ["os_registrar_andamento", "registrar_diaria"],
    ["os_registrar_andamento", "check_in_service_order"], ["os_registrar_andamento", "concluiu"],
  ];
  for (const [nome, vizinha] of fronteiras) assertStringIncludes(d(nome), vizinha, `${nome} → ${vizinha}`);
  // E as vizinhas citadas existem de verdade.
  for (const t of ["schedule_service_order", "registrar_diaria", "check_in_service_order"]) {
    assert(allTools.some((x) => x.name === t), `${t} não é ferramenta`);
  }
});

// ───────── Fase 3 (P3): os_registrar_andamento conclui e entrega (rascunho + *grava*) ─────────
Deno.test("Fase 3: os_registrar_andamento concluiu/entregou vai ao rascunho com o evento (sinônimo → concluiu) e devolve a releitura", async () => {
  const releitura = "Entendi assim, confere?\n• Concluo o Lenine (OS-00074) hoje (qui 29/10): fica registrada a saída, e saem as " +
    "cobranças da condição: Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje).\n" +
    "Responda *grava* ou corrija o que estiver errado.";
  for (const [dito, evento] of [["terminou", "concluiu"], ["concluiu", "concluiu"], ["entregue", "entregou"]] as const) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura }, error: null }));
    const r = await porNome("os_registrar_andamento").execute({ os: "Lenine", evento: dito, trecho: "o Lenine terminou hoje" }, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.map((c) => c.nome), ["agenda_rascunho_andamento"], dito);
    assertEquals(chamadas[0].params.p_evento, evento, dito);
    assertEquals(chamadas[0].params.p_trecho, "o Lenine terminou hoje", dito);
    assertEquals([r.ok, r.texto], [true, releitura], dito);
    assertStringIncludes(String(r.instrucao), "Só o *grava* dele grava", dito);
  }
  const enumDoEvento = (porNome("os_registrar_andamento").input_schema as { properties: { evento: { enum: string[] } } }).properties.evento.enum;
  for (const e of ["concluiu", "entregou"]) assertEquals(enumDoEvento.includes(e), true, e);
});

Deno.test("Fase 3: a recusa do banco ao concluir (orçamento, levantamento, dia que não é hoje) passa adiante como pergunta", async () => {
  const pergunta = "Para concluir, responda o levantamento de: Revisão do sistema elétrico. Esses serviços estão marcados como \"exige levantamento\".";
  const { sb } = sbFalso(() => ({ data: { ok: false, motivo: "levantamento", texto: pergunta, pergunta, opcoes: [] }, error: null }));
  const r = await porNome("os_registrar_andamento").execute({ os: "Lenine", evento: "concluiu", trecho: "o Lenine terminou" }, ctx(sb)) as Record<string, unknown>;
  assertEquals([r.ok, r.texto, r.pergunta], [false, pergunta, pergunta]);
  assertEquals(String(r.texto).includes("*grava*"), false);
});
