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

Deno.test("as 4 estão em allTools, risco low, só admin", () => {
  for (const nome of ["agenda_ver", "os_planejar", "material_informar", "equipe_disponibilidade"]) {
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

Deno.test("erro do banco LANÇA nas quatro (nunca vira agenda vazia nem 'anotado')", async () => {
  const args: Record<string, Record<string, unknown>> = {
    agenda_ver: { foco: "atrasos" },
    os_planejar: { os: "Lenine", dias: 2, trecho: "dois dias" },
    material_informar: { os: "Nelson", itens: ["painel"], situacao: "na_mao", trecho: "chegou" },
    equipe_disponibilidade: { pessoa: "eu", situacao: "vem", dias: "segunda a sexta", padrao: true, trecho: "segunda a sexta" },
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

Deno.test("as três de escrita exigem o trecho; a leitura não exige nada", () => {
  for (const nome of ["os_planejar", "material_informar", "equipe_disponibilidade"]) {
    assert((porNome(nome).input_schema.required as string[]).includes("trecho"), nome);
  }
  assertEquals(porNome("agenda_ver").input_schema.required, undefined);
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
});

Deno.test("cada execute chama UMA RPC e não lê tabela (o texto é do banco)", () => {
  for (const t of agendaProducaoTools as ToolDef[]) {
    const corpo = String(t.execute);
    assertEquals(/\.from\(/.test(corpo), false, `${t.name} lê tabela direto`);
  }
});
