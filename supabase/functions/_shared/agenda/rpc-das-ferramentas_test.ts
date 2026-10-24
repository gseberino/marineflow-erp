// Agenda de Produção, Fase 1 (P5): o mapeamento puro argumento → RPC e RPC → modelo
// (_shared/agenda/rpc-das-ferramentas.ts), o mesmo das ferramentas e dos evals.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/agenda/rpc-das-ferramentas_test.ts
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canalDaRpc,
  INSTRUCAO_LEITURA,
  INSTRUCAO_RASCUNHO,
  INSTRUCAO_RASCUNHO_RECUSA,
  paraAgendaVer,
  paraDisponibilidade,
  paraMaterial,
  paraPlanejar,
  resultadoDaLeitura,
  resultadoDoRascunho,
} from "./rpc-das-ferramentas.ts";

const CTX = { autor: "aa000000-0000-4000-8000-000000000001", canal: "whatsapp" as const };
const UUID_QUALQUER = "05000000-0000-4000-8000-000000000112";

function params(r: ReturnType<typeof paraAgendaVer>) {
  if (!r.ok) throw new Error(`esperava ok, veio: ${r.error}`);
  return r;
}
function erro(r: ReturnType<typeof paraAgendaVer>): string {
  if (r.ok) throw new Error(`esperava recusa, veio ${JSON.stringify(r.params)}`);
  return r.error;
}

// ───────── o canal ─────────

Deno.test("canalDaRpc: painel só com ctx.canal = panel; ausente = WhatsApp", () => {
  assertEquals(canalDaRpc("panel"), "painel");
  assertEquals(canalDaRpc("whatsapp"), "whatsapp");
  assertEquals(canalDaRpc(undefined), "whatsapp");
});

// ───────── agenda_ver ─────────

Deno.test("agenda_ver: todos os parâmetros, com nulos no que não veio (sem p_hoje em produção)", () => {
  const r = params(paraAgendaVer({ foco: "o_que_fazer", pessoa: "eu" }, CTX));
  assertEquals(r.rpc, "agenda_ver");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_periodo: null, p_pessoa: "eu", p_foco: "o_que_fazer", p_os: null, p_simular: null,
    p_simular_aprovacao: false,
  });
});

Deno.test("agenda_ver: p_hoje só quando o contexto traz (evals)", () => {
  const r = params(paraAgendaVer({}, { ...CTX, hoje: "2026-10-23" }));
  assertEquals(r.params.p_hoje, "2026-10-23");
});

Deno.test("agenda_ver: simular {dias, com_quem, dono} e simular_aprovacao com os", () => {
  assertEquals(params(paraAgendaVer({ simular: { dias: 2, com_quem: ["eu", "Roberto"] } }, CTX)).params.p_simular,
    { dias: 2, com_quem: ["eu", "Roberto"] });
  assertEquals(params(paraAgendaVer({ simular: { dias: "1,5", com_quem: [{ pessoa: "eu" }], dono: "sempre" } }, CTX)).params.p_simular,
    { dias: 1.5, com_quem: ["eu"], dono: "sempre" });
  const r = params(paraAgendaVer({ os: "César", simular_aprovacao: true }, CTX));
  assertEquals([r.params.p_os, r.params.p_simular_aprovacao], ["César", true]);
});

Deno.test("agenda_ver: foco fora da lista, id no lugar da OS, data calculada e aprovação sem OS voltam ao modelo", () => {
  assert(erro(paraAgendaVer({ foco: "semana" }, CTX)).startsWith("'foco' aceita só: tudo, livre, o_que_fazer"));
  assert(erro(paraAgendaVer({ os: UUID_QUALQUER }, CTX)).includes("não o id"));
  assert(erro(paraAgendaVer({ periodo: "2026-10-26" }, CTX)).includes("sem calcular"));
  assert(erro(paraAgendaVer({ simular_aprovacao: true }, CTX)).includes("falta 'os'"));
  assert(erro(paraAgendaVer({ simular: { dias: 0 } }, CTX)).includes("simular.dias"));
  assert(erro(paraAgendaVer({ pessoa: "aa000000-0000-4000-8000-000000000002" }, CTX)).includes("não o id"));
  assert(erro(paraAgendaVer({ foco: "semana" }, CTX)).endsWith("Nada foi chamado."));
});

// ───────── os_planejar ─────────

Deno.test("os_planejar: só os campos ditos vão em p_dados; turnos padrão = dia; canal e trecho", () => {
  const r = params(paraPlanejar({
    os: "Lenine", dias: 2, com_quem: [{ pessoa: "Roberto" }, { pessoa: "João", turnos: "tarde" }], dono: "abre_e_fecha",
    trecho: "Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.",
  }, { ...CTX, canal: "painel" }));
  assertEquals(r.rpc, "agenda_rascunho_planejar");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "painel", p_os: "Lenine",
    p_dados: { dias: 2, com_quem: [{ pessoa: "Roberto", turnos: "dia" }, { pessoa: "João", turnos: "tarde" }], dono: "abre_e_fecha" },
    p_trecho: "Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.",
  });
});

Deno.test("os_planejar: datas como o dono disse, textos, prioridade e os booleanos", () => {
  const r = params(paraPlanejar({
    os: "112", bem_livre_em: "dia 3", precisa_ate: "sexta", nao_antes_de: "dia 5", nao_antes_motivo: "estaleiro",
    escopo_decidido: "só a primeira parte", congelar_ate: "dia 10", prioridade: 1, sem_material: true,
    aceitar_sugestao: true, trecho: "…",
  }, CTX));
  assertEquals(r.params.p_os, "112");
  assertEquals(r.params.p_dados, {
    precisa_ate: "sexta", bem_livre_em: "dia 3", nao_antes_de: "dia 5", congelar_ate: "dia 10",
    nao_antes_motivo: "estaleiro", escopo_decidido: "só a primeira parte", prioridade: 1, sem_material: true,
    aceitar_sugestao: true,
  });
  // "com_quem" como lista de nomes também serve.
  assertEquals(params(paraPlanejar({ os: "Lenine", com_quem: ["eu"], trecho: "eu vou" }, CTX)).params.p_dados,
    { com_quem: [{ pessoa: "eu", turnos: "dia" }] });
});

Deno.test("os_planejar: sem trecho, sem nada a mudar, data calculada, id, turno ou prioridade inválidos → erro, nada chamado", () => {
  assert(erro(paraPlanejar({ os: "Lenine", dias: 2 }, CTX)).includes("falta 'trecho'"));
  assert(erro(paraPlanejar({ os: "Lenine", trecho: "nada" }, CTX)).includes("diga o que mudou"));
  assert(erro(paraPlanejar({ os: "Lenine", precisa_ate: "2026-11-20", trecho: "dia 20" }, CTX)).includes("sem calcular"));
  assert(erro(paraPlanejar({ os: UUID_QUALQUER, dias: 2, trecho: "dois dias" }, CTX)).includes("não o id"));
  assert(erro(paraPlanejar({ os: "Lenine", com_quem: [{ pessoa: "Roberto", turnos: "noite" }], trecho: "x" }, CTX))
    .includes("turnos' aceita só: dia, manha, tarde"));
  assert(erro(paraPlanejar({ os: "Lenine", prioridade: 5, trecho: "x" }, CTX)).includes("1, 2 ou 3"));
  assert(erro(paraPlanejar({ os: "Lenine", dias: "dois", trecho: "dois dias" }, CTX)).includes("'dias' tem de ser número"));
  assert(erro(paraPlanejar({ dias: 2, trecho: "dois dias" }, CTX)).includes("falta 'os'"));
  assert(erro(paraPlanejar({ os: "Lenine", dias: 2, trecho: "x".repeat(1600) }, CTX)).includes("passa de 1500"));
});

// ───────── material_informar ─────────

Deno.test("material_informar: itens, situação, quando, fornecedor, quantidade e novo", () => {
  const r = params(paraMaterial({
    os: "Vanderlei", itens: ["tudo"], situacao: "vou_comprar", quando: "terça", fornecedor: "Premel",
    trecho: "Vanderlei eu compro na Premel terça",
  }, CTX));
  assertEquals(r.rpc, "agenda_rascunho_material");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: "Vanderlei", p_itens: ["tudo"], p_situacao: "vou_comprar",
    p_quando: "terça", p_fornecedor: "Premel", p_quantidade: null, p_novo: false,
    p_trecho: "Vanderlei eu compro na Premel terça",
  });
  // Um item em texto solto vira lista; item vazio sai.
  assertEquals(params(paraMaterial({ os: "Nelson", itens: "painel", situacao: "na_mao", trecho: "o painel chegou" }, CTX)).params.p_itens,
    ["painel"]);
  assertEquals(params(paraMaterial({ os: "Nelson", itens: ["Cerbo", " ", "Orion"], situacao: "na_mao", quantidade: "2", novo: true,
    trecho: "chegaram 2" }, CTX)).params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: "Nelson", p_itens: ["Cerbo", "Orion"], p_situacao: "na_mao", p_quando: null,
    p_fornecedor: null, p_quantidade: 2, p_novo: true, p_trecho: "chegaram 2",
  });
});

Deno.test("material_informar: situação fora da lista, sem itens, data calculada, quantidade zero → erro", () => {
  assert(erro(paraMaterial({ os: "Nelson", itens: ["painel"], situacao: "chegou", trecho: "x" }, CTX)).includes("'situacao' aceita só"));
  assert(erro(paraMaterial({ os: "Nelson", itens: [], situacao: "na_mao", trecho: "x" }, CTX)).includes("'itens'"));
  assert(erro(paraMaterial({ os: "Nelson", itens: ["  "], situacao: "na_mao", trecho: "x" }, CTX)).includes("veio vazio"));
  assert(erro(paraMaterial({ os: "Nelson", itens: ["painel"], situacao: "a_caminho", quando: "2026-11-03", trecho: "dia 3" }, CTX))
    .includes("sem calcular"));
  assert(erro(paraMaterial({ os: "Nelson", itens: ["painel"], situacao: "na_mao", quantidade: 0, trecho: "x" }, CTX))
    .includes("maior que zero"));
  assert(erro(paraMaterial({ os: "Nelson", itens: ["painel"], situacao: "na_mao" }, CTX)).includes("falta 'trecho'"));
});

// ───────── equipe_disponibilidade ─────────

Deno.test("equipe_disponibilidade: pessoa, situação, dias, padrão (falso por padrão) e trecho", () => {
  const r = params(paraDisponibilidade({
    pessoa: "eu", situacao: "vem", dias: "segunda a sexta", padrao: true,
    trecho: "Eu fico em campo de segunda a sexta; sexta à tarde, escritório.",
  }, CTX));
  assertEquals(r.rpc, "agenda_rascunho_disponibilidade");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_pessoa: "eu", p_situacao: "vem", p_dias: "segunda a sexta", p_padrao: true,
    p_trecho: "Eu fico em campo de segunda a sexta; sexta à tarde, escritório.",
  });
  assertEquals(params(paraDisponibilidade({ pessoa: "Roberto", situacao: "nao_vem", dias: "terça", trecho: "não vem terça" }, CTX))
    .params.p_padrao, false);
});

Deno.test("equipe_disponibilidade: situação fora da lista, sem dias, data calculada, sem pessoa → erro", () => {
  assert(erro(paraDisponibilidade({ pessoa: "Roberto", situacao: "folga", dias: "terça", trecho: "x" }, CTX)).includes("'situacao' aceita só"));
  assert(erro(paraDisponibilidade({ pessoa: "Roberto", situacao: "vem", trecho: "x" }, CTX)).includes("falta 'dias'"));
  assert(erro(paraDisponibilidade({ pessoa: "Roberto", situacao: "vem", dias: "2026-10-27", trecho: "x" }, CTX)).includes("sem calcular"));
  assert(erro(paraDisponibilidade({ situacao: "vem", dias: "terça", trecho: "x" }, CTX)).includes("falta 'pessoa'"));
});

// ───────── o que volta ao modelo ─────────

Deno.test("resultadoDaLeitura: o texto pronto e a instrução; nunca os dados grandes", () => {
  const r = resultadoDaLeitura({ ok: true, texto: "Hoje (sex 23/10): nada marcado.", rota: "o_que_fazer", dados: { oss: [1, 2, 3] } });
  assertEquals(r, { ok: true, texto: "Hoje (sex 23/10): nada marcado.", rota: "o_que_fazer", instrucao: INSTRUCAO_LEITURA });
});

Deno.test("resultadoDaLeitura: referência que não existe e pergunta passam adiante, opções só em texto (sem id)", () => {
  assertEquals(resultadoDaLeitura({ ok: false, texto: "Não encontrei a OS-00999.", rota: "os" }).texto, "Não encontrei a OS-00999.");
  const r = resultadoDaLeitura({
    ok: false, texto: "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?", pergunta: "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?",
    opcoes: [{ numero: "OS-00076", id: UUID_QUALQUER, texto: "OS-00076 (Starlink, esperando o cliente)" }],
  });
  assertEquals(r.pergunta, "Qual Rodrigo: OS-00076 (…) ou OS-00096 (…)?");
  assertEquals(r.opcoes, ["OS-00076 (Starlink, esperando o cliente)"]);
  assertEquals(JSON.stringify(r).includes(UUID_QUALQUER), false);
});

Deno.test("resultadoDaLeitura: resposta sem texto LANÇA (nunca vira agenda vazia)", () => {
  assertThrows(() => resultadoDaLeitura(null));
  assertThrows(() => resultadoDaLeitura({ ok: true }));
  assertThrows(() => resultadoDaLeitura("ok"));
});

Deno.test("resultadoDoRascunho: ok devolve a releitura e diz que nada foi gravado; recusa devolve a pergunta", () => {
  const ok = resultadoDoRascunho({
    ok: true, item: "Lenine (OS-00074): 2 dias", releitura: "Entendi assim, confere?\n• Lenine (OS-00074): 2 dias.\nResponda *grava*…",
  });
  assertEquals(ok, {
    ok: true, texto: "Entendi assim, confere?\n• Lenine (OS-00074): 2 dias.\nResponda *grava*…", item: "Lenine (OS-00074): 2 dias",
    instrucao: INSTRUCAO_RASCUNHO,
  });
  assertEquals(INSTRUCAO_RASCUNHO, "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.");
  const recusa = resultadoDoRascunho({ ok: false, motivo: "item_ambiguo", pergunta: "Qual peça do Nelson: A, B ou C?", opcoes: ["A", "B", "C"] });
  assertEquals(recusa, {
    ok: false, texto: "Qual peça do Nelson: A, B ou C?", pergunta: "Qual peça do Nelson: A, B ou C?", opcoes: ["A", "B", "C"],
    instrucao: INSTRUCAO_RASCUNHO_RECUSA,
  });
  assertThrows(() => resultadoDoRascunho({}));
});

Deno.test("o módulo é puro: nada de Deno, nada de import (o runner dos evals roda em Node)", async () => {
  const fonte = await Deno.readTextFile(new URL("./rpc-das-ferramentas.ts", import.meta.url));
  assertEquals(/^\s*import\s/m.test(fonte), false, "import no módulo puro");
  assertEquals(/\bDeno\./.test(fonte), false, "Deno no módulo puro");
  // Só sintaxe que o Node apaga sem transformar (sem enum, namespace ou propriedade de parâmetro).
  assertEquals(
    /^\s*(export\s+)?(declare\s+)?(const\s+)?enum\s+\w+\s*\{|^\s*(export\s+)?namespace\s+\w+\s*\{|constructor\s*\(\s*(public|private|protected|readonly)\s/m
      .test(fonte),
    false,
  );
});
