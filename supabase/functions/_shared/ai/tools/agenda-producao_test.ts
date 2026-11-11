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

// (Fase 7c, P4) eram 10; + equipe_habilidade = 11; (Fase 7c, P8) + servico_etapa = 12
Deno.test("as 12 estão em allTools, risco low, só admin", () => {
  for (const nome of [
    "agenda_ver", "os_planejar", "material_informar", "equipe_disponibilidade",
    "agenda_propor", "agenda_aplicar", "agenda_desfazer", "os_registrar_andamento",
    // Fase 4 (P1)
    "fornecedor_prazo",
    // Fase 5 (P5)
    "cliente_avisar",
    // Fase 7c (P4)
    "equipe_habilidade",
    // Fase 7c (P8)
    "servico_etapa",
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

Deno.test("erro do banco LANÇA nas dez (nunca vira agenda vazia nem 'anotado')", async () => {
  const args: Record<string, Record<string, unknown>> = {
    agenda_ver: { foco: "atrasos" },
    os_planejar: { os: "Lenine", dias: 2, trecho: "dois dias" },
    material_informar: { os: "Nelson", itens: ["painel"], situacao: "na_mao", trecho: "chegou" },
    equipe_disponibilidade: { pessoa: "eu", situacao: "vem", dias: "segunda a sexta", padrao: true, trecho: "segunda a sexta" },
    agenda_propor: { escopo: "semana", tirar: ["Rodrigo"] },
    agenda_aplicar: { decisao: "1", opcao: "1", trecho: "pode atrasar o Nelson" },
    agenda_desfazer: { alvo: "Nelson", trecho: "desfaz o Nelson" },
    os_registrar_andamento: { os: "Vanderlei", evento: "trabalhou", quem: ["Roberto"], dia: "hoje", trecho: "hoje o Roberto trabalhou" },
    fornecedor_prazo: { fornecedor: "Kamell", prazo: 4, unidade: "uteis", trecho: "a Kamell chega em 4 dias úteis" },
    // Fase 5 (P5)
    cliente_avisar: { os: "Nelson", tipo: "material_chegou", trecho: "avisa o Nelson que a peça chegou" },
    // Fase 7c (P4)
    equipe_habilidade: { pessoa: "Roberto", o_que_faz: "instala_sozinho", trecho: "o Roberto instala sozinho" },
    // Fase 7c (P8)
    servico_etapa: { os: "Lenine", etapa: "porta fusíveis", estado: "feita", trecho: "no Lenine os porta-fusíveis já estão instalados" },
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

Deno.test("as sete de rascunho exigem o trecho; a leitura não exige nada; a simulação só o escopo", () => {
  for (const nome of ["os_planejar", "material_informar", "equipe_disponibilidade", "agenda_aplicar", "agenda_desfazer", "os_registrar_andamento",
    "fornecedor_prazo"]) {
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

// ───────── Fase 4 (P1): fornecedor_prazo (rascunho + *grava*) ─────────
Deno.test("Fase 4: fornecedor_prazo chama agenda_rascunho_fornecedor com p_autor e p_canal e devolve a releitura", async () => {
  const releitura = "Entendi assim, confere?\n• Premel (Itajaí/SC): balcão, na mão no mesmo dia (você disse).\n" +
    "Responda *grava* ou corrija o que estiver errado.";
  for (const [canal, esperado] of [["panel", "painel"], ["whatsapp", "whatsapp"]] as const) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura }, error: null }));
    const r = await porNome("fornecedor_prazo").execute(
      { fornecedor: "Premel", modalidade: "balcao", trecho: "a Premel eu pego no balcão" }, ctx(sb, { canal })) as Record<string, unknown>;
    assertEquals(chamadas.map((c) => c.nome), ["agenda_rascunho_fornecedor"]);
    assertEquals(chamadas[0].params, {
      p_autor: ADMIN, p_canal: esperado, p_fornecedor: "Premel", p_modalidade: "balcao", p_prazo: null, p_unidade: null,
      p_mesmo_que: null, p_trecho: "a Premel eu pego no balcão",
    });
    assertEquals([r.ok, r.texto], [true, releitura]);
    assertEquals(r.instrucao, "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.");
  }
  // A pergunta do banco (dois cadastros com o mesmo nome) passa adiante, sem id.
  const pergunta = "Qual Kamell: Kamell (Vila Velha/ES) ou Kamell (Itajaí/SC)?";
  const { sb } = sbFalso(() => ({
    data: { ok: false, motivo: "fornecedor_ambiguo", texto: pergunta, pergunta, opcoes: ["Kamell (Vila Velha/ES)", "Kamell (Itajaí/SC)"] },
    error: null,
  }));
  const r = await porNome("fornecedor_prazo").execute({ fornecedor: "Kamell", prazo: 4, trecho: "a Kamell chega em 4 dias úteis" }, ctx(sb)) as
    Record<string, unknown>;
  assertEquals([r.ok, r.pergunta, r.opcoes], [false, pergunta, ["Kamell (Vila Velha/ES)", "Kamell (Itajaí/SC)"]]);
  assertStringIncludes(String(r.instrucao), "Nada entrou no rascunho");
});

Deno.test("Fase 4: fornecedor_prazo — argumento errado volta como { error } e NADA é chamado", async () => {
  const casos: Array<[Record<string, unknown>, string]> = [
    [{ fornecedor: "Premel", modalidade: "balcao" }, "falta 'trecho'"],
    [{ modalidade: "balcao", trecho: "no balcão" }, "falta 'fornecedor'"],
    [{ fornecedor: "dd000000-0000-4000-8000-000000000001", modalidade: "balcao", trecho: "x" }, "não o id"],
    [{ fornecedor: "Premel", modalidade: "loja", trecho: "x" }, "'modalidade' aceita só"],
    [{ fornecedor: "Toli", prazo: 2.5, trecho: "dois dias e meio" }, "inteiro"],
    [{ fornecedor: "Toli", prazo: 3, unidade: "semanas", trecho: "3 semanas" }, "'unidade' aceita só"],
    [{ fornecedor: "Toli", unidade: "corridos", trecho: "x" }, "só vai junto do 'prazo'"],
    [{ fornecedor: "Kamell de SC", mesmo_que: "Kamell do ES", prazo: 4, trecho: "é a mesma, 4 dias" }, "não passe modalidade nem prazo"],
    [{ fornecedor: "Premel", trecho: "a Premel" }, "diga como o dono compra"],
  ];
  for (const [args, trecho] of casos) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
    const r = await porNome("fornecedor_prazo").execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 0, `chamou o banco com ${JSON.stringify(args)}`);
    assertStringIncludes(String(r.error), trecho, JSON.stringify(args));
  }
});

Deno.test("Fase 4: a descrição de fornecedor_prazo diz o que NÃO faz e a fronteira com material_informar", () => {
  const d = porNome("fornecedor_prazo").description;
  for (const t of ["RASCUNHO", "NÃO grava", "não muda o cadastro", "não manda mensagem ao fornecedor", "*grava*",
    "nunca invente prazo nem modalidade", "material_informar"]) {
    assertStringIncludes(d, t);
  }
  const props = (porNome("fornecedor_prazo").input_schema as { properties: Record<string, { enum?: string[] }> }).properties;
  assertEquals(props.modalidade.enum, ["balcao", "entrega_local", "distribuidor_sc_pr", "outro_estado", "marketplace", "importacao"]);
  assertEquals(props.unidade.enum, ["uteis", "corridos"]);
  assertEquals(porNome("fornecedor_prazo").input_schema.required, ["fornecedor", "trecho"]);
});

// Fase 4 (P3): material_informar com o aviso. O que se protege: o campo existe (texto, nunca id), nao_e_de_servico está no
// enum, a OS e os itens deixam de ser obrigatórios no esquema (o mapeamento cobra fora de nao_e_de_servico) e a descrição
// diz que a ferramenta não liga a nota nem o Pix sozinha; a frase do novo é a da Fase 4 (entra na lista do que comprar).
Deno.test("Fase 4: material_informar ensina o aviso e o nao_e_de_servico, e não liga nada sozinha", () => {
  const t = porNome("material_informar");
  const props = (t.input_schema as { properties: Record<string, { type?: string; enum?: string[] }> }).properties;
  assertEquals(props.aviso?.type, "string");
  assertEquals(props.situacao.enum?.includes("nao_e_de_servico"), true);
  assertEquals(t.input_schema.required, ["situacao", "trecho"]);
  for (const f of ["aviso", "nao_e_de_servico", "não liga a nota ou o Pix sozinho", "entra na lista do que comprar, sem preço",
    "add_service_order_item"]) {
    assertStringIncludes(t.description, f);
  }
  assertEquals(t.description.includes("só avisa a agenda"), false);
});

// ───────── Fase 5 (P5): cliente_avisar (prepara, nunca envia) e o os_planejar com o prometido ─────────
Deno.test("Fase 5: cliente_avisar chama agenda_cliente_preparar (só o tipo e a OS) e devolve o texto do banco com a instrução de que nada saiu", async () => {
  const texto = "Pronto para Flávio, sai agora: \"Olá, Flávio! …\". Para mandar: *manda cliente Flávio*.";
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, status: "preparada", texto, mensagem_id: "m1", modo: "ligado" }, error: null }));
  const r = await porNome("cliente_avisar").execute(
    { os: "Flávio", tipo: "confirmar", trecho: "manda a confirmação pro Flávio" }, ctx(sb)) as Record<string, unknown>;
  assertEquals(chamadas.map((c) => c.nome), ["agenda_cliente_preparar"]);
  assertEquals(chamadas[0].params, {
    p_autor: ADMIN, p_os: "Flávio", p_tipo: "confirmar", p_firme: false, p_trecho: "manda a confirmação pro Flávio",
  });
  assertEquals([r.ok, r.texto], [true, texto]);
  assertStringIncludes(String(r.instrucao), "Nada foi enviado ao cliente");
  assertEquals("mensagem_id" in r, false);
});

Deno.test("Fase 5: cliente_avisar — texto livre e tipo fora da lista voltam como { error } e NADA é chamado; o técnico não alcança", async () => {
  for (const args of [
    { os: "Nelson", tipo: "pode_atrasar", texto: "Nelson, a peça atrasou", trecho: "avisa o Nelson" },
    { os: "Nelson", tipo: "cobranca", trecho: "cobra o Nelson" },
    { os: "Nelson", tipo: "mudanca_no_dia", trecho: "avisa o Nelson" },
  ]) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
    const r = await porNome("cliente_avisar").execute(args, ctx(sb)) as Record<string, unknown>;
    assert(typeof r.error === "string", JSON.stringify(args));
    assertEquals(chamadas.length, 0);
  }
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, texto: "x" }, error: null }));
  const r = await porNome("cliente_avisar").execute({ os: "Nelson", tipo: "pronto", trecho: "x" }, ctx(sb, { userRole: "technician" }));
  assertEquals(r, { error: "Só o administrador mexe na agenda de produção." });
  assertEquals(chamadas.length, 0);
});

Deno.test("Fase 5: a descrição de cliente_avisar diz que NÃO envia, a palavra que manda e a fronteira com a mensagem livre; o os_planejar ensina o prometido", () => {
  const d = porNome("cliente_avisar").description;
  assertStringIncludes(d, "NÃO envia");
  assertStringIncludes(d, "*manda cliente <nome>*");
  assertStringIncludes(d, "Texto livre ao cliente não é aqui");
  assertStringIncludes(d, "Nunca cobrança, valor ou desconto");
  assertEquals(porNome("cliente_avisar").input_schema.required, ["os", "tipo", "trecho"]);
  const props = (porNome("cliente_avisar").input_schema as { properties: Record<string, unknown> }).properties;
  assertEquals(Object.keys(props).sort(), ["firme", "os", "tipo", "trecho"]);
  const plan = porNome("os_planejar");
  assertStringIncludes(plan.description, "é prometido = \"dia 3\"");
  const pp = (plan.input_schema as { properties: Record<string, unknown> }).properties;
  assert("prometido" in pp && "servico_cliente" in pp);
  const foco = (porNome("agenda_ver").input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  assert(foco.includes("clientes"));
  assertStringIncludes(porNome("agenda_ver").description, "(foco clientes");
});

// Fase 6 (P8, spec-fase6.md §7): o foco aprendizado em agenda_ver (no enum e na descrição); nenhuma ferramenta nova e nenhuma
// que escreva parâmetro.
Deno.test("Fase 6 (P8) — agenda_ver tem o foco aprendizado (enum e descrição: só lê; mudar é decisão do dono)", () => {
  const foco = (porNome("agenda_ver").input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  assert(foco.includes("aprendizado"));
  const d = porNome("agenda_ver").description;
  assertStringIncludes(d, "o que a agenda aprendeu com o que aconteceu (foco aprendizado");
  assertStringIncludes(d, "mudar é decisão do dono pelas perguntas da agenda");
  // Fase 7e (P8, spec-fase7e.md §7, R7.3-1): a margem no foco aprendizado, e o prazo real só para o dono (AG7-32)
  assertStringIncludes(d, "e a margem: quanto as OS passam da estimativa pelo orçamento, a folga da semana, o prazo real só para o dono (ao cliente não digo data de pronto) e o tempo de compra");
  // nenhuma ferramenta da agenda recebe parâmetro de agenda_config nem item do aprendizado para mudar
  for (const t of agendaProducaoTools) {
    const props = Object.keys((t.input_schema as { properties?: Record<string, unknown> }).properties ?? {});
    for (const p of ["modo_aprendizado", "aprendizado_ligados", "estouro_fator", "carga_max", "fator"]) {
      assertEquals(props.includes(p), false, `${t.name} recebe ${p}`);
    }
  }
});

// Fase 7a (P7, spec-fase7a.md §7): o foco gestor em agenda_ver (no enum e na descrição); nenhuma ferramenta nova e nenhuma escreve
// modo, regra ou parâmetro do gestor (ligar é o OK do roteiro; *gestor, só propor* é palavra do dono, antes do modelo).
Deno.test("Fase 7a (P7) — agenda_ver tem o foco gestor (enum e descrição: só lê); nenhuma ferramenta muda o gestor", () => {
  const ver = agendaProducaoTools.find((t) => t.name === "agenda_ver")!;
  const foco = ((ver.input_schema as { properties: { foco: { enum: string[] } } }).properties.foco.enum);
  assert(foco.includes("gestor"));
  assertStringIncludes(ver.description, "o que o gestor da agenda marcou ou marcaria sozinho e por quê (foco gestor");
  for (const t of agendaProducaoTools) {
    const props = Object.keys((t.input_schema as { properties?: Record<string, unknown> }).properties ?? {});
    for (const p of ["modo_marcar_sozinho", "gestor_so_propor", "marcar_regras", "so_propor", "dupla_dita", "modo_vaga_fechamento"]) {
      assert(!props.includes(p), `${t.name}: ${p}`);
    }
  }
  assert(!agendaProducaoTools.some((t) => /gestor|dupla/.test(t.name)), "nenhuma ferramenta nova do gestor");
});

Deno.test("Fase 7b (P5) — os_planejar tem dupla (nao, inicio, fim, todos) e dupla_meios (1 a 20); equipe_disponibilidade tem semana; as descrições ensinam", () => {
  const plan = porNome("os_planejar");
  const pp = (plan.input_schema as { properties: Record<string, { enum?: string[]; type?: string; minimum?: number; maximum?: number }> })
    .properties;
  assertEquals(pp.dupla.enum, ["nao", "inicio", "fim", "todos"]);
  assertEquals([pp.dupla_meios.type, pp.dupla_meios.minimum, pp.dupla_meios.maximum], ["integer", 1, 20]);
  assertStringIncludes(plan.description,
    "\"vai com um só\" = nao; \"precisa de dois o tempo todo\" = todos; \"dois no primeiro dia\" = inicio com dupla_meios 2");
  const disp = porNome("equipe_disponibilidade");
  const dp = disp.input_schema as { properties: Record<string, { type?: string; description?: string }>; required: string[] };
  assertEquals(dp.properties.semana.type, "string");
  assertStringIncludes(dp.properties.semana.description ?? "", "Nunca calcule");
  assert(!dp.required.includes("semana"));
  assertStringIncludes(disp.description, "passe semana como o dono disse");
  assertStringIncludes(disp.description, "é vem, sem padrao e sem semana: só nessas datas");
  // nenhuma ferramenta nova: as 10 de antes (o teto do perfil continua)
  // FASE 7c: (7c P4) + equipe_habilidade (pela rede, fora do perfil: o teto continua): 11; (7c P8) + servico_etapa (idem): 12
  assertEquals(agendaProducaoTools.length, 12);
});

Deno.test("Fase 7b (P5) — os_planejar com a dupla e equipe_disponibilidade com a semana chamam o rascunho de sempre; argumento errado não chama nada", async () => {
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: {}, releitura: "Lenine: vai em dupla nos 2 primeiros meios-dias." }, error: null }));
  await porNome("os_planejar").execute({ os: "Lenine", dupla: "inicio", dupla_meios: 2, trecho: "o Lenine precisa de dois no primeiro dia" }, ctx(sb));
  await porNome("equipe_disponibilidade").execute({
    pessoa: "Rafael", situacao: "vem", dias: "seg e ter", semana: "semana que vem", trecho: "o Rafael só pode seg e ter na semana que vem",
  }, ctx(sb));
  assertEquals(chamadas.map((c) => c.nome), ["agenda_rascunho_planejar", "agenda_rascunho_disponibilidade"]);
  assertEquals(chamadas[0].params.p_dados, { dupla: "inicio", dupla_meios: 2 });
  assertEquals(chamadas[1].params.p_semana, "semana que vem");
  const r = await porNome("os_planejar").execute({ os: "Lenine", dupla: "talvez", trecho: "com dupla" }, ctx(sb)) as Record<string, unknown>;
  assert(typeof r.error === "string");
  assertEquals(chamadas.length, 2);
});

// ───────── Fase 7c (P4, spec-fase7c.md §5.4, §7): equipe_habilidade (rascunho + *grava*) e o foco habilidades ─────────
Deno.test("Fase 7c (P4) — equipe_habilidade chama agenda_rascunho_habilidade (a forma dita, p_autor, p_canal) e devolve a releitura", async () => {
  const casos: Array<[Record<string, unknown>, Record<string, unknown>]> = [
    [{ pessoa: "Roberto", o_que_faz: "instala_sozinho", trecho: "o Roberto instala sozinho" },
      { p_pessoa: "Roberto", p_o_que_faz: "instala_sozinho", p_os: null, p_exige: null, p_meios: null, p_lider: null, p_confirmar: false }],
    [{ os: "Lenine", exige: "altura", meios: "nao", trecho: "o Lenine não precisa de ninguém subindo no teto" },
      { p_pessoa: null, p_o_que_faz: null, p_os: "Lenine", p_exige: "altura", p_meios: "nao", p_lider: null, p_confirmar: false }],
    [{ os: "Lenine", lider: "Roberto", trecho: "no Lenine o responsável é o Roberto" },
      { p_pessoa: null, p_o_que_faz: null, p_os: "Lenine", p_exige: null, p_meios: null, p_lider: "Roberto", p_confirmar: false }],
    [{ confirmar: true, trecho: "está certo o que você marcou da equipe" },
      { p_pessoa: null, p_o_que_faz: null, p_os: null, p_exige: null, p_meios: null, p_lider: null, p_confirmar: true }],
  ];
  for (const [args, esperado] of casos) {
    for (const [canal, c] of [["panel", "painel"], [undefined, "whatsapp"]] as const) {
      const { sb, chamadas } = sbFalso(() => ({
        data: { ok: true, item: "Quem faz o quê: Roberto instala sozinho",
                releitura: "Entendi assim, confere?\n• Quem faz o quê: Roberto instala sozinho.\nResponda *grava* ou corrija o que estiver errado." },
        error: null,
      }));
      const r = await porNome("equipe_habilidade").execute(args, ctx(sb, canal ? { canal } : {})) as Record<string, unknown>;
      assertEquals(chamadas.map((x) => x.nome), ["agenda_rascunho_habilidade"]);
      assertEquals(chamadas[0].params, { p_autor: ADMIN, p_canal: c, ...esperado, p_trecho: args.trecho });
      assertEquals(r.ok, true);
      assertStringIncludes(String(r.texto), "Entendi assim, confere?");
      assertEquals(r.instrucao, "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.");
    }
  }
  // a pergunta do banco (o nome ambíguo, a palavra fora do trecho) passa adiante, sem id
  const { sb } = sbFalso(() => ({
    data: { ok: false, motivo: "fora_do_trecho", pergunta: "Não achei no que você disse o que João faz; me diga de novo.",
            texto: "Não achei no que você disse o que João faz; me diga de novo.", opcoes: [] },
    error: null,
  }));
  const p = await porNome("equipe_habilidade").execute({ pessoa: "João", o_que_faz: "instala_sozinho", trecho: "o João é bom" }, ctx(sb)) as
    Record<string, unknown>;
  assertEquals([p.ok, p.pergunta], [false, "Não achei no que você disse o que João faz; me diga de novo."]);
  assertStringIncludes(String(p.instrucao), "Nada entrou no rascunho");
});

Deno.test("Fase 7c (P4) — equipe_habilidade: duas formas, a forma pela metade, o id e o valor fora da lista voltam como { error }; nada é chamado; só o admin", async () => {
  for (const args of [
    { pessoa: "Roberto", o_que_faz: "instala_sozinho", os: "Lenine", lider: "Roberto", trecho: "x" },
    { pessoa: "Roberto", trecho: "o Roberto instala sozinho" },
    { os: "Lenine", exige: "altura", trecho: "x" },
    { pessoa: "aa000000-0000-4000-8000-000000000002", o_que_faz: "ajudante", trecho: "x" },
    { pessoa: "Roberto", o_que_faz: "pilota", trecho: "x" },
    { pessoa: "Roberto", o_que_faz: "instala_sozinho" },
  ]) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura: "x" }, error: null }));
    const r = await porNome("equipe_habilidade").execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 0, JSON.stringify(args));
    assert(typeof r.error === "string" && r.error.endsWith("Nada foi chamado."), JSON.stringify(args));
  }
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura: "x" }, error: null }));
  const r = await porNome("equipe_habilidade").execute({ pessoa: "Roberto", o_que_faz: "instala_sozinho", trecho: "x" },
    ctx(sb, { userRole: "technician" })) as Record<string, unknown>;
  assertEquals([chamadas.length, r.error], [0, "Só o administrador mexe na agenda de produção."]);
});

Deno.test("Fase 7c (P4) — equipe_habilidade: o esquema (os 14 o_que_faz, exige, meios; só o trecho obrigatório) e a descrição dizem o que NÃO faz; agenda_ver tem o foco habilidades", () => {
  const t = porNome("equipe_habilidade");
  assertEquals([t.risk, t.roles], ["low", ["admin"]]);
  const props = (t.input_schema as { properties: Record<string, { enum?: string[]; type?: string }> }).properties;
  assertEquals(Object.keys(props).sort(), ["confirmar", "exige", "lider", "meios", "o_que_faz", "os", "pessoa", "trecho"]);
  assertEquals(props.o_que_faz.enum?.length, 14);
  assertEquals(props.exige.enum, ["energizado", "comissionamento", "altura", "diagnostico"]);
  assertEquals(props.meios.enum, ["todos", "ultimo", "nao"]);
  assertEquals(props.confirmar.type, "boolean");
  assertEquals(t.input_schema.required, ["trecho"]);
  assertStringIncludes(t.description, "Anota num RASCUNHO quem faz o quê na equipe");
  assertStringIncludes(t.description, "Uma chamada por pessoa e por coisa dita, com trecho = as palavras dele.");
  assertStringIncludes(t.description, "NÃO escolhe quem vai a um serviço (quem escala é a agenda) e não grava");
  assertStringIncludes(t.description, "só o *grava* do dono grava");
  const ver = porNome("agenda_ver");
  const foco = (ver.input_schema as { properties: { foco: { enum: string[] } } }).properties.foco.enum;
  assert(foco.includes("habilidades"));
  assert(foco.includes("locais"));
  assertStringIncludes(ver.description, "onde é cada serviço, o que combinar com o cliente e a marina e as regras dos locais (foco locais");
  assertStringIncludes(ver.description, "quem faz o quê na equipe e o que cada OS pede (foco habilidades:");
  assertStringIncludes(ver.description, "o que a agenda teria mudado em teste e as medidas; só lê)");
});

// ───────── Fase 7c (P8, spec-fase7c.md §16.5.6, §16.7): servico_etapa (rascunho + *grava*) ─────────
Deno.test("Fase 7c (P8) — servico_etapa chama agenda_rascunho_etapa (a forma dita, p_autor, p_canal) e devolve a releitura", async () => {
  const casos: Array<[Record<string, unknown>, Record<string, unknown>]> = [
    [{ os: "Lenine", etapa: "porta fusíveis", estado: "feita", trecho: "no Lenine os porta-fusíveis já estão instalados" },
      { p_os: "Lenine", p_etapa: "porta fusíveis", p_estado: "feita", p_texto: null, p_partes: null }],
    [{ os: "Flávio", texto: "Trocar a bomba d'água", trecho: "acrescenta no Flávio: trocar a bomba d'água" },
      { p_os: "Flávio", p_etapa: null, p_estado: null, p_texto: "Trocar a bomba d'água", p_partes: null }],
    [{ os: "Vanderlei", etapa: "instalação do novo sistema", partes: ["Fixar o banco de baterias", "Passar os cabos", "Montar o quadro"],
       trecho: "divide a instalação do Vanderlei em 3: fixar o banco de baterias, passar os cabos e montar o quadro" },
      { p_os: "Vanderlei", p_etapa: "instalação do novo sistema", p_estado: null, p_texto: null,
        p_partes: ["Fixar o banco de baterias", "Passar os cabos", "Montar o quadro"] }],
  ];
  for (const [args, esperado] of casos) {
    for (const [canal, c] of [["panel", "painel"], [undefined, "whatsapp"]] as const) {
      const { sb, chamadas } = sbFalso(() => ({
        data: { ok: true, item: "Lenine: porta-fusíveis feita",
                releitura: "Entendi assim, confere?\n• Lenine (OS-97192): \"Instalação de porta fusíveis - distribuição de energia 12v\" já está feita.\nResponda *grava* ou corrija o que estiver errado." },
        error: null,
      }));
      const r = await porNome("servico_etapa").execute(args, ctx(sb, canal ? { canal } : {})) as Record<string, unknown>;
      assertEquals(chamadas.map((x) => x.nome), ["agenda_rascunho_etapa"]);
      assertEquals(chamadas[0].params, { p_autor: ADMIN, p_canal: c, ...esperado, p_trecho: args.trecho });
      assertEquals(r.ok, true);
      assertStringIncludes(String(r.texto), "Entendi assim, confere?");
      assertEquals(r.instrucao, "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.");
    }
  }
  // a pergunta do banco (o número da lista, a etapa ambígua) passa adiante, sem id
  const { sb } = sbFalso(() => ({
    data: { ok: false, motivo: "so_numero",
            pergunta: "Me diga pelo nome: no Lenine faltam Substituição baterias - chumbo para litio e Passagem e crimpagem de cabos de bateria.",
            texto: "Me diga pelo nome: no Lenine faltam Substituição baterias - chumbo para litio e Passagem e crimpagem de cabos de bateria.",
            opcoes: [] },
    error: null,
  }));
  const p = await porNome("servico_etapa").execute({ os: "Lenine", etapa: "2", estado: "falta", trecho: "no Lenine falta a 2" }, ctx(sb)) as
    Record<string, unknown>;
  assertEquals(p.ok, false);
  assertStringIncludes(String(p.pergunta ?? p.texto), "Me diga pelo nome");
});

Deno.test("Fase 7c (P8) — servico_etapa: duas formas, a forma pela metade, sem a OS, o id, as partes fora da regra e o estado fora da lista voltam como { error }; nada é chamado; só o admin", async () => {
  for (const args of [
    { os: "Lenine", etapa: "cabos", estado: "feita", partes: ["Passar os cabos", "Crimpar os cabos"], trecho: "x" },
    { os: "Flávio", etapa: "bomba", texto: "Trocar a bomba d'água", trecho: "x" },
    { os: "Lenine", estado: "feita", trecho: "x" },
    { os: "Lenine", etapa: "cabos", trecho: "x" },
    { etapa: "cabos", estado: "feita", trecho: "x" },
    { os: "aa000000-0000-4000-8000-000000000002", etapa: "cabos", estado: "feita", trecho: "x" },
    { os: "Lenine", etapa: "aa000000-0000-4000-8000-000000000002", estado: "feita", trecho: "x" },
    { os: "Lenine", etapa: "cabos", partes: ["Passar os cabos"], trecho: "x" },
    { os: "Lenine", etapa: "cabos", partes: ["Passar os cabos", "passar os cabos"], trecho: "x" },
    { os: "Lenine", etapa: "cabos", partes: ["Passar os cabos", "ok"], trecho: "x" },
    { os: "Lenine", etapa: "cabos", estado: "pronta", trecho: "x" },
    { os: "Lenine", etapa: "cabos", estado: "feita" },
  ]) {
    const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura: "x" }, error: null }));
    const r = await porNome("servico_etapa").execute(args, ctx(sb)) as Record<string, unknown>;
    assertEquals(chamadas.length, 0, JSON.stringify(args));
    assert(typeof r.error === "string" && r.error.endsWith("Nada foi chamado."), JSON.stringify(args));
  }
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura: "x" }, error: null }));
  const r = await porNome("servico_etapa").execute({ os: "Lenine", etapa: "cabos", estado: "feita", trecho: "x" },
    ctx(sb, { userRole: "technician" })) as Record<string, unknown>;
  assertEquals([chamadas.length, r.error], [0, "Só o administrador mexe na agenda de produção."]);
});

Deno.test("Fase 7c (P8) — servico_etapa: o esquema (os e trecho obrigatórios; o estado em 3; as partes em lista) e a descrição dizem o que NÃO faz", () => {
  const t = porNome("servico_etapa");
  assertEquals([t.risk, t.roles], ["low", ["admin"]]);
  const props = (t.input_schema as { properties: Record<string, { enum?: string[]; type?: string }> }).properties;
  assertEquals(Object.keys(props).sort(), ["estado", "etapa", "os", "partes", "texto", "trecho"]);
  assertEquals(props.estado.enum, ["feita", "falta", "nao_se_aplica"]);
  assertEquals(props.partes.type, "array");
  assertEquals(t.input_schema.required, ["os", "trecho"]);
  assertStringIncludes(t.description, "Anota num RASCUNHO o que o dono disse das etapas de um serviço (OS)");
  assertStringIncludes(t.description, "Uma chamada por coisa dita, com trecho = as palavras dele.");
  assertStringIncludes(t.description, "NÃO distribui etapa por pessoa nem por dia, não muda a ordem e não manda nada à equipe");
  assertStringIncludes(t.description, "só o *grava* do dono grava");
});

Deno.test("Fase 7d (P7) — os_planejar: os 8 campos no esquema, sem id nem data calculada, com as listas do banco; o limpar novo; continua pedindo só os e trecho", () => {
  const t = porNome("os_planejar");
  const props = (t.input_schema as { properties: Record<string, { enum?: string[]; type?: string; items?: { enum?: string[]; type?: string }; description?: string }> }).properties;
  for (const campo of ["local", "bem_onde", "bem_exige", "descer_quem", "chega_em", "sai_em", "viagem", "autorizados"]) {
    assert(props[campo], `${campo} fora do esquema`);
    assert((props[campo].description ?? "").length > 0, `${campo} sem descrição`);
  }
  assertEquals(props.bem_onde.enum, ["agua", "seco", "garagem_seca", "patio", "com_cliente"]);
  assertEquals(props.bem_exige.enum, ["agua", "seco", "tanto_faz"]);
  assertEquals(props.viagem.enum, ["regional", "bate_volta", "pernoite"]);
  assertEquals([props.autorizados.type, props.autorizados.items?.type], ["array", "string"]);
  assertEquals(props.limpar.items?.enum, ["espera", "nao_antes", "prazo", "escopo", "patio", "local", "entrada", "retirada", "viagem", "autorizados"]);
  assertEquals(t.input_schema.required, ["os", "trecho"]);
  assertStringIncludes(t.description, "só o que ele disse e com as palavras dele");
  assertStringIncludes(t.description, "Regra de marina ou de pátio não muda por aqui.");
  assertStringIncludes(props.chega_em.description ?? "", "Nunca calcule.");
  assertStringIncludes(props.local.description ?? "", "Nunca invente");
});

Deno.test("Fase 7d (P7) — os_planejar: uma RPC só, com o que o dono disse como veio, e a recusa do banco (local ambíguo) volta como pergunta", async () => {
  const { sb, chamadas } = sbFalso(() => ({ data: { ok: true, item: "x", releitura: "Entendi assim, confere?" }, error: null }));
  await porNome("os_planejar").execute(
    { os: "Nelson", local: "Marina Itajaí", chega_em: "dia 5", autorizados: ["eu"], trecho: "na Marina Itajaí, chega dia 5, eu autorizado" }, ctx(sb));
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].nome, "agenda_rascunho_planejar");
  assertEquals(chamadas[0].params.p_dados, { local: "Marina Itajaí", chega_em: "dia 5", autorizados: ["eu"] });
  const { sb: sb2 } = sbFalso(() => ({
    data: { ok: false, motivo: "local_ambiguo", pergunta: "Qual deles: Kalmar Estaleiro (Itajaí) ou Marina Itajaí (Itajaí)?", opcoes: ["Kalmar Estaleiro", "Marina Itajaí"] },
    error: null,
  }));
  const r = await porNome("os_planejar").execute({ os: "Nelson", local: "Itajaí", trecho: "em Itajaí" }, ctx(sb2)) as Record<string, unknown>;
  assertEquals(r.pergunta, "Qual deles: Kalmar Estaleiro (Itajaí) ou Marina Itajaí (Itajaí)?");
  assertEquals(JSON.stringify(r).includes("gravado"), false);
});

// Fase 7f (P7; spec-fase7f.md §7): a descrição do foco decisoes diz que cada pergunta traz o que fica sem resposta e até quando (o prazo vem do banco). Nenhuma
// ferramenta nova (a palavra *agenda espera* é do dono, antes do modelo), e o foco continua só de leitura.
Deno.test("Fase 7f (P7) — agenda_ver: o foco decisoes diz o que fica sem resposta e até quando; nenhuma ferramenta nova", () => {
  const ver = porNome("agenda_ver");
  assertStringIncludes(ver.description, "(foco decisoes: as decisões numeradas, com as opções e a recomendação; cada pergunta diz o que fica se o dono não responder e até quando)");
  assertEquals(agendaProducaoTools.some((t) => /veto|espera/.test(t.name)), false);
  assertEquals(ver.description.includes("agenda fica"), false);
  assertStringIncludes(ver.description, "Só lê: não marca nada");
});
