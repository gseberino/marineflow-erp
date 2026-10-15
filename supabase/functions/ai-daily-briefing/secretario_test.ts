import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { contarPropostas, itensParaGravar, type ManhaNova, montarDosDados, registrarManha } from "./secretario.ts";
import { candidatosDoDia } from "./secretario-candidatos.ts";
import { selecionar } from "./secretario-selecao.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";

const ESCRITORIO = { propostas: { saidas: 46, entradas: 4, transferencias: 1, outras: 0 }, alertas: 15, regras: 103, debitosSemLoja: 6, entradas: null };

function manha(hoje = HOJE_1510, agora = AGORA_1510): ManhaNova {
  return montarDosDados({ hoje, agora, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(), escritorio: ESCRITORIO });
}

// Os CHECKs de resumo_itens (migration 20261015200000): o que a montagem grava tem de passar neles.
const TIPOS = new Set([
  "cobranca_grande", "cobranca_marco", "cobranca_fora_do_marco", "cobranca_antiga", "cliente_sem_resposta", "cliente_recente",
  "contato_pedindo_preco", "contato_sem_cadastro", "fornecedor", "orcamento_parado", "orcamento_vencendo", "orcamento_nao_enviado",
  "orcamento_na_lista", "os_esperando_compra", "os_sem_cobranca", "os_parada",
]);

Deno.test("os itens a gravar passam nos CHECKs do banco (letra, tipo, tamanhos, nome_busca, detalhe)", () => {
  const m = manha();
  assert(m.itens.length > 0);
  for (const i of m.itens) {
    assert(/^[A-DF-HJ-MP-RT-Z]$/.test(i.letra), `letra ${i.letra}`);
    assert(TIPOS.has(i.tipo), i.tipo);
    assert(["cobranca", "cliente", "contato", "orcamento", "os"].includes(i.familia), i.familia);
    assert(["dinheiro", "clientes", "obras", "contatos"].includes(i.secao), i.secao);
    assert(["manha", "lista"].includes(i.posicao));
    assert(i.referencia.length >= 3 && i.referencia.length <= 120 && i.assunto.length >= 3 && i.assunto.length <= 120);
    assert(i.nome.length >= 1 && i.nome.length <= 120);
    assert(/^[a-z0-9 ]{0,120}$/.test(i.nome_busca), i.nome_busca);
    assert(i.fato.length >= 1 && i.fato.length <= 300);
    assert(i.titulo.length >= 1 && i.titulo.length <= 600);
    assert(i.motivo.length >= 1 && i.motivo.length <= 600);
    assert(!i.motivo.includes("{L}") && !i.titulo.includes("{L}"), "o {L} foi trocado pela letra");
    assert((i.recomendacao ?? "").length <= 300 && (i.pedido ?? "").length <= 1000);
    assert(new TextEncoder().encode(JSON.stringify(i.detalhe)).length <= 8192);
  }
  // uma letra principal por dia (o índice único resumo_itens_letra_do_dia)
  const principais = m.itens.filter((i) => i.principal).map((i) => i.letra);
  assertEquals(new Set(principais).size, principais.length);
  assertEquals([m.itensManha, m.itensLista, m.semLetra], [3, 14, 0]);
  assert(m.itensLista <= 21);
  // o item de manhã grava a linha que o dono viu
  assertStringIncludes(m.itens.find((i) => i.letra === "A" && i.principal)!.titulo, "*A.* *Jorge Girardon*");
  assertStringIncludes(m.itens.find((i) => i.letra === "B" && i.principal)!.titulo, "*B.* *2 orçamentos montados e ainda não enviados*");
  assertStringIncludes(m.itens.find((i) => i.letra === "C" && i.principal)!.titulo, "*C.* *Marcelo Marco Bertoldi*");
});

Deno.test("domingo: uma linha, e os itens do dia ficam todos na lista (a *lista* funciona)", () => {
  const m = manha("2026-10-18", new Date("2026-10-18T10:30:00Z"));
  assertEquals(m.texto, "Bom dia! Domingo: nada precisa de você hoje. *lista* se quiser ver.");
  assertEquals(m.tipoDoDia, "domingo");
  assertEquals(m.itensManha, 0);
  assert(m.itens.every((i) => i.posicao === "lista"));
  assertEquals(m.itens.find((i) => i.principal)!.letra, "A");
  assertStringIncludes(m.itens.find((i) => i.tipo === "cobranca_grande")!.motivo, "domingo, nada sobe de manhã");
});

Deno.test("feriado (Finados, segunda): uma linha com o nome do feriado", () => {
  const m = manha("2026-11-02", new Date("2026-11-02T10:30:00Z"));
  assertEquals(m.texto, "Bom dia! Feriado (Finados): nada precisa de você hoje. *lista* se quiser ver.");
});

function falsoAdmin(resposta: { data?: unknown; error?: unknown }) {
  const chamadas: Array<{ nome: string; args: { p: Record<string, unknown> } }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: { p: Record<string, unknown> }) {
        chamadas.push({ nome, args });
        return Promise.resolve(resposta);
      },
    },
  };
}

Deno.test("registrarManha: manda o dia inteiro à resumo_registrar e devolve o texto GRAVADO", async () => {
  const m = manha();
  const f = falsoAdmin({ data: { ok: true, novo: false, texto_novo: "o texto da primeira vez", modo: "novo" } });
  const r = await registrarManha(f.admin, { hoje: HOJE_1510, dono: { id: "u1", phone: "5547999990000" }, modo: "novo", manha: m, textoAntigo: "☀️ antigo" });
  assertEquals(r, { ok: true, novo: false, texto: "o texto da primeira vez" });
  const p = f.chamadas[0].args.p;
  assertEquals(f.chamadas[0].nome, "resumo_registrar");
  assertEquals([p.dia, p.phone, p.app_user_id, p.modo, p.enviado, p.tipo_do_dia], [HOJE_1510, "5547999990000", "u1", "novo", true, "util"]);
  assertEquals(p.texto_antigo, "☀️ antigo");
  assertEquals((p.itens as unknown[]).length, m.itens.length);
  assertStringIncludes(String(p.escritorio), "46 saídas");
});

Deno.test("registrarManha: erro, ok=false ou o dia gravado em outro modo = não serve para enviar", async () => {
  const dono = { id: "u1", phone: "5547999990000" };
  assertEquals((await registrarManha(falsoAdmin({ error: { code: "42501" } }).admin, { hoje: HOJE_1510, dono, modo: "novo", manha: manha(), textoAntigo: "" })).ok, false);
  assertEquals((await registrarManha(falsoAdmin({ data: { ok: false } }).admin, { hoje: HOJE_1510, dono, modo: "novo", manha: manha(), textoAntigo: "" })).ok, false);
  assertEquals((await registrarManha(falsoAdmin({ data: { ok: true, novo: false, texto_novo: "x", modo: "sombra" } }).admin,
    { hoje: HOJE_1510, dono, modo: "novo", manha: manha(), textoAntigo: "" })).ok, false);
  // sombra: grava sem enviar
  const f = falsoAdmin({ data: { ok: true, novo: true, texto_novo: "y", modo: "sombra" } });
  await registrarManha(f.admin, { hoje: HOJE_1510, dono, modo: "sombra", manha: manha(), textoAntigo: "" });
  assertEquals(f.chamadas[0].args.p.enviado, false);
});

Deno.test("itensParaGravar: o grupo grava todos os membros com a mesma letra (o primeiro é o principal)", () => {
  const sel = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  const itens = itensParaGravar(sel);
  // G = o ORÇ-00095 da MP, com as duas cobranças antigas da MP
  const doG = itens.filter((i) => i.letra === "G");
  assertEquals(doG.map((i) => [i.principal, i.tipo]), [[true, "orcamento_parado"], [false, "cobranca_antiga"], [false, "cobranca_antiga"]]);
  assertEquals(doG[1].motivo, "Ficou na lista: vencida há 85 dias (30 ou mais vão para a revisão do mês).");
  // o nome curto vai junto (o "também" da *lista*)
  assertEquals(doG[1].detalhe.rotulo, "MP MOTOR HOMES (R$ 1.650,00, venceu 22/07)");
});

Deno.test("itensParaGravar: o pacote grava cada orçamento com o seu fato; o principal leva o nome e a linha curta do pacote", () => {
  const sel = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  const doB = itensParaGravar(sel).filter((i) => i.letra === "B");
  assertEquals(doB.map((i) => [i.principal, i.referencia, i.tipo]), [
    [true, "os:q-117", "orcamento_nao_enviado"], [false, "os:q-118", "orcamento_nao_enviado"],
  ]);
  assertEquals(doB[0].nome, "2 orçamentos não enviados: ORÇ-00117, ORÇ-00118");
  assertEquals(doB[0].nome_busca, "2 orcamentos nao enviados orc 00117 orc 00118");
  assertEquals(doB[0].detalhe.curto, "2 orçamentos montados, não enviados (R$ 141 mil): ORÇ-00117, ORÇ-00118");
  assertEquals(doB[0].detalhe.faco, "te mostro os 2");
  // cada membro guarda o próprio fato (a repetição é por orçamento) e o próprio nome
  assertEquals(doB[1].nome, "ORÇ-00118 Cliente Final");
  assertEquals(new Set(doB.map((i) => i.fato)).size, 2);
});

Deno.test("contarPropostas: por tipo, sem o alerta do vigilante", () => {
  assertEquals(contarPropostas([{ kind: "create_payable" }, { kind: "create_payable" }, { kind: "create_receivable" }, { kind: "internal_transfer" }, { kind: "anomaly" }, { kind: "x" }]),
    { saidas: 2, entradas: 1, transferencias: 1, outras: 1 });
});
