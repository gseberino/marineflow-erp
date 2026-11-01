// Agenda de Produção, Fase 1 (P5): o mapeamento puro argumento → RPC e RPC → modelo
// (_shared/agenda/rpc-das-ferramentas.ts), o mesmo das ferramentas e dos evals.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/agenda/rpc-das-ferramentas_test.ts
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canalDaRpc,
  DUPLAS,
  FOCOS,
  INSTRUCAO_CLIENTE,
  paraCliente,
  resultadoDaMensagemAoCliente,
  RPC_CLIENTE_PREPARAR,
  TIPOS_DA_MENSAGEM_AO_CLIENTE,
  ESCOPOS_DA_PROPOSTA,
  EVENTOS_DO_ANDAMENTO,
  INSTRUCAO_AGENDA_DESLIGADA,
  INSTRUCAO_LEITURA,
  INSTRUCAO_PROPOSTA_ABERTA,
  INSTRUCAO_RASCUNHO,
  INSTRUCAO_RASCUNHO_RECUSA,
  INSTRUCAO_SIMULACAO,
  MODALIDADES_DO_FORNECEDOR,
  MOTIVOS_DO_ANDAMENTO,
  paraAgendaVer,
  paraAndamento,
  paraAplicar,
  paraDesfazer,
  paraDisponibilidade,
  paraFornecedor,
  paraMaterial,
  paraPlanejar,
  paraPropor,
  resultadoDaLeitura,
  resultadoDaProposta,
  resultadoDoRascunho,
  SINONIMOS_DO_ANDAMENTO,
  UNIDADES_DO_PRAZO,
  // Fase 7c (P4)
  EXIGENCIAS,
  MEIOS,
  O_QUE_FAZ,
  paraHabilidade,
  RPC_HABILIDADE,
  UMA_COISA_POR_VEZ,
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

Deno.test("os_planejar: limpar (o que o dono desfez) vai como lista sem repetição; valor fora da lista volta ao modelo", () => {
  assertEquals(params(paraPlanejar({ os: "Lenine", limpar: ["espera", "espera"], trecho: "o Lenine pode voltar" }, CTX)).params.p_dados,
    { limpar: ["espera"] });
  assertEquals(params(paraPlanejar({ os: "Lenine", limpar: "prazo", trecho: "o cliente não tem mais prazo" }, CTX)).params.p_dados,
    { limpar: ["prazo"] });
  assertEquals(params(paraPlanejar({ os: "Lenine", limpar: ["nao_antes", "escopo"], trecho: "x" }, CTX)).params.p_dados,
    { limpar: ["nao_antes", "escopo"] });
  assert(erro(paraPlanejar({ os: "Lenine", limpar: ["tudo"], trecho: "x" }, CTX)).includes("aceita só: espera, nao_antes, prazo, escopo"));
  assert(erro(paraPlanejar({ os: "Lenine", limpar: { espera: true }, trecho: "x" }, CTX)).includes("'limpar' tem de ser a lista"));
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

// Fase 4 (P3): o aviso — a nota, o Pix ou a mensagem que a agenda perguntou, como o dono disse.
Deno.test("material_informar (Fase 4): com aviso, p_aviso vai junto; sem ele, os parâmetros da Fase 1 (p_aviso nem aparece)", () => {
  const r = params(paraMaterial({ os: "Nelson", itens: ["Cerbo"], situacao: "a_caminho", aviso: " a nota  da Kamell ",
    trecho: "a nota da Kamell é do Nelson, o Cerbo" }, CTX));
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: "Nelson", p_itens: ["Cerbo"], p_situacao: "a_caminho", p_quando: null,
    p_fornecedor: null, p_quantidade: null, p_novo: false, p_trecho: "a nota da Kamell é do Nelson, o Cerbo",
    p_aviso: "a nota da Kamell",
  });
  assertEquals("p_aviso" in params(paraMaterial({ os: "Nelson", itens: ["painel"], situacao: "na_mao", trecho: "chegou" }, CTX)).params,
    false);
});

Deno.test("material_informar (Fase 4): nao_e_de_servico só com o aviso; dispensa a OS e os itens (nunca manda itens)", () => {
  const r = params(paraMaterial({ situacao: "nao_e_de_servico", aviso: "a nota da Correa", itens: ["tudo"],
    trecho: "essa nota da Correa não é de serviço" }, CTX));
  assertEquals(r.rpc, "agenda_rascunho_material");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: null, p_itens: null, p_situacao: "nao_e_de_servico",
    p_trecho: "essa nota da Correa não é de serviço", p_aviso: "a nota da Correa",
  });
  assert(erro(paraMaterial({ situacao: "nao_e_de_servico", trecho: "não é de serviço" }, CTX)).includes("precisa do 'aviso'"));
  assert(erro(paraMaterial({ situacao: "nao_e_de_servico", aviso: "o Pix" }, CTX)).includes("falta 'trecho'"));
  // Fora de nao_e_de_servico, a OS e os itens continuam obrigatórios.
  assert(erro(paraMaterial({ situacao: "na_mao", aviso: "o Pix da Premel", itens: ["tudo"], trecho: "já tá aqui" }, CTX))
    .includes("falta 'os'"));
  assert(erro(paraMaterial({ os: "Vanderlei", situacao: "na_mao", aviso: "o Pix da Premel", trecho: "já tá aqui" }, CTX))
    .includes("'itens'"));
  assert(erro(paraMaterial({ os: "Vanderlei", itens: ["tudo"], situacao: "na_mao", aviso: "x".repeat(121), trecho: "t" }, CTX))
    .includes("'aviso' passa de 120"));
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

Deno.test("resultadoDaLeitura: agenda desligada = a instrução de voltar à my_agenda (a agenda de antes)", () => {
  const r = resultadoDaLeitura({ ok: false, rota: "desligada", desligada: true, texto: "A agenda de produção está desligada agora." });
  assertEquals(r, {
    ok: false, texto: "A agenda de produção está desligada agora.", desligada: true, instrucao: INSTRUCAO_AGENDA_DESLIGADA,
  });
  assert(INSTRUCAO_AGENDA_DESLIGADA.includes("my_agenda pela ferramenta_extra"));
  // sem a marca, o ok:false continua sendo o aviso/pergunta de sempre
  assertEquals(resultadoDaLeitura({ ok: false, texto: "Não encontrei a OS-00999." }).desligada, undefined);
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

// ───────── Fase 2 (P6): agenda_propor, agenda_aplicar, agenda_desfazer, os_registrar_andamento ─────────

Deno.test("paraPropor: todos os parâmetros, simular true por padrão, nulos no que não veio (sem p_hoje em produção)", () => {
  const r = params(paraPropor({ escopo: "semana" }, CTX));
  assertEquals(r.rpc, "agenda_propor_dito");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_escopo: "semana", p_os: null, p_fixar: null, p_tirar: null, p_so_depois_de: null,
    p_acima_da_carga: false, p_simular: true, p_trecho: null,
  });
  assertEquals(params(paraPropor({ escopo: "semana" }, { ...CTX, hoje: "2026-10-29" })).params.p_hoje, "2026-10-29");
  assertEquals(params(paraPropor({ escopo: "semana", simular: false }, CTX)).params.p_simular, false);
});

Deno.test("paraPropor: fixar/tirar/só depois de como o dono disse; OS repetida conta uma vez", () => {
  const r = params(paraPropor({
    escopo: "replano", os: ["Lenine", "Lenine"], fixar: [{ os: "Lenine", quando: "quinta", ate: "sexta", pessoa: "Roberto" }],
    tirar: "Rodrigo", so_depois_de: [{ os: "Nelson", quando: "dia 10" }], trecho: "e se o Lenine for quinta e sexta com o Roberto, o Nelson só depois do dia 10",
  }, CTX));
  assertEquals(r.params.p_os, ["Lenine"]);
  assertEquals(r.params.p_trecho, "e se o Lenine for quinta e sexta com o Roberto, o Nelson só depois do dia 10");
  assertEquals(r.params.p_fixar, [{ os: "Lenine", quando: "quinta", ate: "sexta", pessoa: "Roberto" }]);
  assertEquals(r.params.p_tirar, ["Rodrigo"]);
  assertEquals(r.params.p_so_depois_de, [{ os: "Nelson", quando: "dia 10" }]);
});

Deno.test("paraPropor: recusa escopo fora da lista, OS/replano sem OS, data calculada, id e simular que não é booleano", () => {
  assertEquals(erro(paraPropor({}, CTX)).startsWith("falta 'escopo'"), true);
  assertEquals(erro(paraPropor({ escopo: "mes" }, CTX)).includes("'escopo' aceita só: semana, proxima_semana, os, replano"), true);
  assertEquals(erro(paraPropor({ escopo: "os" }, CTX)).includes("diga de qual serviço"), true);
  assertEquals(erro(paraPropor({ escopo: "replano", fixar: [{ os: "Lenine", quando: "2026-11-05" }], trecho: "x" }, CTX)).includes("sem calcular"), true);
  // (revisão da Fase 2) com fixar ou só depois de, o trecho é obrigatório: o banco confere nele cada dia
  assertEquals(erro(paraPropor({ escopo: "replano", fixar: [{ os: "Lenine", quando: "quinta" }] }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraPropor({ escopo: "replano", so_depois_de: [{ os: "Nelson", quando: "dia 10" }] }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraPropor({ escopo: "semana", tirar: [UUID_QUALQUER] }, CTX)).includes("não o id"), true);
  assertEquals(erro(paraPropor({ escopo: "semana", fixar: [{ os: UUID_QUALQUER, quando: "quinta" }] }, CTX)).includes("não o id"), true);
  assertEquals(erro(paraPropor({ escopo: "semana", simular: "não" }, CTX)).includes("true ou false"), true);
});

Deno.test("paraAplicar: publicar (proposta, os) ou decidir (decisao, opcao), nunca os dois; trecho obrigatório", () => {
  assertEquals(params(paraAplicar({ proposta: "a última", os: ["Lenine", "Flávio"], trecho: "publica só o Lenine e o Flávio" }, CTX)).params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_proposta: "a última", p_os: ["Lenine", "Flávio"], p_decisao: null, p_opcao: null,
    p_trecho: "publica só o Lenine e o Flávio",
  });
  assertEquals(params(paraAplicar({ decisao: "1", opcao: "Nelson", trecho: "pode atrasar o Nelson" }, CTX)).params.p_opcao, "Nelson");
  // O número que a agenda mostrou chega como texto ("1"), do jeito que o dono disse.
  assertEquals(params(paraAplicar({ decisao: 1, opcao: 2, trecho: "na decisão 1, a opção 2" }, CTX)).params.p_decisao, "1");
  // Sem opção dita: vai nulo (o banco devolve a pergunta; ninguém escolhe aqui).
  assertEquals(params(paraAplicar({ decisao: "1", trecho: "resolve aí" }, CTX)).params.p_opcao, null);
  assertEquals(erro(paraAplicar({ decisao: "1", opcao: "1" }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraAplicar({ proposta: "1", decisao: "1", trecho: "x" }, CTX)).includes("a proposta OU a decisão"), true);
  assertEquals(erro(paraAplicar({ os: ["Lenine"], decisao: "1", opcao: "1", trecho: "x" }, CTX)).includes("'os' é só para publicar"), true);
  assertEquals(erro(paraAplicar({ decisao: UUID_QUALQUER, opcao: "1", trecho: "x" }, CTX)).includes("não o id"), true);
});

Deno.test("paraDesfazer: o alvo como o dono disse; sem alvo vai nulo (o banco pergunta qual)", () => {
  assertEquals(params(paraDesfazer({ alvo: "semana", trecho: "desfaz a semana" }, CTX)).params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_alvo: "semana", p_trecho: "desfaz a semana",
  });
  assertEquals(params(paraDesfazer({ trecho: "volta como estava" }, CTX)).params.p_alvo, null);
  assertEquals(erro(paraDesfazer({ alvo: "Nelson" }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraDesfazer({ alvo: UUID_QUALQUER, trecho: "x" }, CTX)).includes("não o id"), true);
});

Deno.test("paraAndamento: os, evento, dia como dito, quem e motivo da lista", () => {
  assertEquals(params(paraAndamento({ os: "Vanderlei", evento: "nao_foi", quem: "João", motivo: "equipe", dia: "hoje", trecho: "hoje o João não foi" }, CTX)).params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: "Vanderlei", p_evento: "nao_foi", p_dia: "hoje", p_quem: ["João"], p_motivo: "equipe",
    p_trecho: "hoje o João não foi",
  });
  assertEquals(params(paraAndamento({ os: "Vanderlei", evento: "comecou", trecho: "o Vanderlei começou" }, CTX)).params.p_quem, null);
  assertEquals(erro(paraAndamento({ os: "Vanderlei", evento: "faltou", trecho: "x" }, CTX)).includes("'evento' aceita só"), true);
  assertEquals(erro(paraAndamento({ os: "Vanderlei", evento: "parou", motivo: "chuva", trecho: "x" }, CTX)).includes("'motivo' aceita só"), true);
  assertEquals(erro(paraAndamento({ os: "Vanderlei", evento: "trabalhou", dia: "2026-11-03", trecho: "x" }, CTX)).includes("sem calcular"), true);
  assertEquals(erro(paraAndamento({ os: "Vanderlei", evento: "trabalhou", quem: [UUID_QUALQUER], trecho: "x" }, CTX)).includes("não o id"), true);
  assertEquals(erro(paraAndamento({ os: "Vanderlei", evento: "trabalhou" }, CTX)).startsWith("falta 'trecho'"), true);
});

// Fase 3 (P3): concluir e entregar pelo andamento — a releitura da saída e das cobranças, e o *grava* do dono. Os
// sinônimos que o modelo manda viram o evento (o banco aceita os mesmos: agenda_rascunho_andamento).
Deno.test("Fase 3: paraAndamento aceita concluiu e entregou; terminou/acabou/finalizou/pronto viram concluiu e entregue, entregou", () => {
  assertEquals(params(paraAndamento({ os: "Lenine", evento: "concluiu", trecho: "o Lenine terminou hoje" }, CTX)).params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_os: "Lenine", p_evento: "concluiu", p_dia: null, p_quem: null, p_motivo: null,
    p_trecho: "o Lenine terminou hoje",
  });
  for (const [dito, evento] of [["terminou", "concluiu"], ["acabou", "concluiu"], ["finalizou", "concluiu"], ["pronto", "concluiu"],
    ["Terminou", "concluiu"], ["concluido", "concluiu"], ["entregue", "entregou"], ["entregou", "entregou"]] as const) {
    assertEquals(params(paraAndamento({ os: "Lenine", evento: dito, trecho: "o Lenine terminou" }, CTX)).params.p_evento, evento, dito);
  }
  // o resto continua: trecho obrigatório, data calculada recusada, evento fora da lista
  assertEquals(erro(paraAndamento({ os: "Lenine", evento: "concluiu" }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraAndamento({ os: "Lenine", evento: "concluiu", dia: "2026-10-29", trecho: "x" }, CTX)).includes("sem calcular"), true);
  assertEquals(erro(paraAndamento({ os: "Lenine", evento: "faturou", trecho: "x" }, CTX)).includes("'evento' aceita só"), true);
});

Deno.test("os enums das ferramentas são os que o banco aceita (spec §8: eventos e motivos do andamento)", () => {
  // FASE 3 (P3): concluiu e entregou entram (a releitura e o *grava* concluem pela porta).
  assertEquals([...EVENTOS_DO_ANDAMENTO], ["trabalhou", "parcial", "nao_foi", "comecou", "parou", "concluiu", "entregou"]);
  for (const evento of Object.values(SINONIMOS_DO_ANDAMENTO)) assertEquals(EVENTOS_DO_ANDAMENTO.includes(evento), true, evento);
  assertEquals([...ESCOPOS_DA_PROPOSTA], ["semana", "proxima_semana", "os", "replano"]);
  assertEquals([...MOTIVOS_DO_ANDAMENTO].sort(), [
    "anterior", "cliente", "clima", "equipe", "esqueci", "estimativa", "imprevisto", "informacao", "material", "urgencia",
  ]);
});

Deno.test("resultadoDaProposta: o texto e as perguntas em texto; simulação × proposta em aberto; recusa = a pergunta", () => {
  const sim = resultadoDaProposta({
    ok: true, simulacao: true, texto: "Semana de 03 a 06/11\n• Vanderlei.\nÉ simulação: não muda nada.", proposta_id: null,
    itens: [{ os: UUID_QUALQUER }], perguntas: [{ texto: "Não cabe tudo até qui 05/11.", opcoes: [{ os: UUID_QUALQUER }] }],
  });
  assertEquals(sim, {
    ok: true, texto: "Semana de 03 a 06/11\n• Vanderlei.\nÉ simulação: não muda nada.", simulacao: true,
    perguntas: ["Não cabe tudo até qui 05/11."], instrucao: INSTRUCAO_SIMULACAO,
  });
  assertEquals(JSON.stringify(sim).includes(UUID_QUALQUER), false);
  assertEquals(resultadoDaProposta({ ok: true, simulacao: false, texto: "x" }).instrucao, INSTRUCAO_PROPOSTA_ABERTA);
  const recusa = resultadoDaProposta({ ok: false, motivo: "os_ambiguo", texto: "Qual Rodrigo?", pergunta: "Qual Rodrigo?", opcoes: ["OS-00076", "OS-00096"] });
  assertEquals(recusa, { ok: false, texto: "Qual Rodrigo?", pergunta: "Qual Rodrigo?", opcoes: ["OS-00076", "OS-00096"], instrucao: INSTRUCAO_RASCUNHO_RECUSA });
  assertThrows(() => resultadoDaProposta({ ok: true }));
  assertThrows(() => resultadoDaProposta(null));
});

// Fase 4 (P1): o prazo do fornecedor — o nome como o dono disse, só o que ele disse, e o banco confere o número no trecho.
Deno.test("Fase 4: paraFornecedor — modalidade, prazo inteiro, unidade e mesmo_que; nulos no que não veio", () => {
  const r = params(paraFornecedor({ fornecedor: "Premel", modalidade: "balcao", trecho: "a Premel eu pego no balcão" }, CTX));
  assertEquals(r.rpc, "agenda_rascunho_fornecedor");
  assertEquals(r.params, {
    p_autor: CTX.autor, p_canal: "whatsapp", p_fornecedor: "Premel", p_modalidade: "balcao", p_prazo: null, p_unidade: null,
    p_mesmo_que: null, p_trecho: "a Premel eu pego no balcão",
  });
  // "5 dias" vira o número; a unidade só como o dono disse (o banco converte os corridos).
  assertEquals(params(paraFornecedor({ fornecedor: "Toli", prazo: "5", unidade: "corridos", trecho: "a Toli chega em 5 dias" }, CTX)).params,
    { p_autor: CTX.autor, p_canal: "whatsapp", p_fornecedor: "Toli", p_modalidade: null, p_prazo: 5, p_unidade: "corridos",
      p_mesmo_que: null, p_trecho: "a Toli chega em 5 dias" });
  // "É a mesma de …": nem modalidade nem prazo (o banco copia do outro cadastro).
  assertEquals(params(paraFornecedor({ fornecedor: "Kamell de SC", mesmo_que: "Kamell do ES", trecho: "a Kamell de SC é a mesma do ES" },
    CTX)).params.p_mesmo_que, "Kamell do ES");
  // No painel o canal é o painel; com o dia fixo dos evals, p_hoje vai junto.
  assertEquals(params(paraFornecedor({ fornecedor: "Mateus", modalidade: "entrega_local", prazo: 1, trecho: "o Mateus entrega em 1 dia" },
    { ...CTX, canal: "painel", hoje: "2026-10-30" })).params.p_hoje, "2026-10-30");
});

Deno.test("Fase 4: paraFornecedor recusa sem trecho, sem fornecedor, id, modalidade e unidade fora da lista, prazo quebrado e mesmo_que com prazo", () => {
  assertEquals(erro(paraFornecedor({ fornecedor: "Premel", modalidade: "balcao" }, CTX)).startsWith("falta 'trecho'"), true);
  assertEquals(erro(paraFornecedor({ modalidade: "balcao", trecho: "x" }, CTX)).startsWith("falta 'fornecedor'"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: UUID_QUALQUER, modalidade: "balcao", trecho: "x" }, CTX)).includes("não o id"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Kamell", mesmo_que: UUID_QUALQUER, trecho: "x" }, CTX)).includes("não o id"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Premel", modalidade: "loja", trecho: "x" }, CTX)).includes("'modalidade' aceita só"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Toli", prazo: 2.5, trecho: "x" }, CTX)).includes("inteiro"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Toli", prazo: -1, trecho: "x" }, CTX)).includes("inteiro"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Toli", prazo: "dois", trecho: "x" }, CTX)).includes("tem de ser número"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Toli", prazo: 3, unidade: "semanas", trecho: "x" }, CTX)).includes("'unidade' aceita só"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Toli", unidade: "uteis", trecho: "x" }, CTX)).includes("só vai junto do 'prazo'"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Kamell", mesmo_que: "Kamell do ES", modalidade: "outro_estado", trecho: "x" }, CTX))
    .includes("não passe modalidade nem prazo"), true);
  assertEquals(erro(paraFornecedor({ fornecedor: "Premel", trecho: "x" }, CTX)).includes("diga como o dono compra"), true);
});

Deno.test("Fase 4: as modalidades e as unidades são as que o banco aceita (suppliers_modalidade_check)", () => {
  assertEquals([...MODALIDADES_DO_FORNECEDOR], ["balcao", "entrega_local", "distribuidor_sc_pr", "outro_estado", "marketplace", "importacao"]);
  assertEquals([...UNIDADES_DO_PRAZO], ["uteis", "corridos"]);
});

Deno.test("paraPlanejar (Fase 2): adiantavel_patio como o dono disse e limpar patio; fora do intervalo volta", () => {
  const r = params(paraPlanejar({ os: "Giancarlo", adiantavel_patio: "1", trecho: "dá para adiantar um dia no pátio" }, CTX));
  assertEquals(r.params.p_dados, { adiantavel_patio: 1 });
  assertEquals(params(paraPlanejar({ os: "Giancarlo", limpar: ["patio"], trecho: "no pátio não dá" }, CTX)).params.p_dados,
    { limpar: ["patio"] });
  assertEquals(erro(paraPlanejar({ os: "Giancarlo", adiantavel_patio: 0, trecho: "x" }, CTX)).includes("'adiantavel_patio'"), true);
  assertEquals(erro(paraPlanejar({ os: "Giancarlo", adiantavel_patio: "dois", trecho: "x" }, CTX)).includes("tem de ser número"), true);
});

// ─── Fase 5 (P5): cliente_avisar e o os_planejar com o que foi dito ao cliente ───────────────────────────────


const CTX5 = { autor: "00000000-0000-4000-8000-000000000001", canal: "whatsapp" as const, hoje: "2026-10-30" };

Deno.test("Fase 5: paraCliente — a OS, o tipo, o firme e o trecho; nenhum texto ao cliente vai daqui", () => {
  const c = paraCliente({ os: "Nelson", tipo: "material_chegou", trecho: "avisa o Nelson que a peça chegou" }, CTX5);
  assertEquals(c, {
    ok: true, rpc: RPC_CLIENTE_PREPARAR,
    params: { p_autor: CTX5.autor, p_os: "Nelson", p_tipo: "material_chegou", p_firme: false,
              p_trecho: "avisa o Nelson que a peça chegou", p_hoje: "2026-10-30" },
  });
  const f = paraCliente({ os: "Flávio", tipo: "pode_atrasar", firme: true, trecho: "pode dizer que é terça" }, CTX5);
  assertEquals(f.ok && f.params.p_firme, true);
});

Deno.test("Fase 5: paraCliente recusa o texto livre, o id, o tipo fora da lista (a mudança no dia é sozinha), o firme fora do atraso e sem trecho", () => {
  const recusas: Array<[Record<string, unknown>, string]> = [
    [{ os: "Nelson", tipo: "pode_atrasar", texto: "Nelson, vai atrasar", trecho: "avisa" }, "'texto' não existe"],
    [{ os: "Nelson", tipo: "pode_atrasar", mensagem: "oi", trecho: "avisa" }, "'mensagem' não existe"],
    [{ os: "05000000-0000-4000-8000-000000000112", tipo: "pronto", trecho: "avisa" }, "não o id"],
    [{ os: "Nelson", tipo: "mudanca_no_dia", trecho: "avisa" }, "'tipo' aceita só"],
    [{ os: "Nelson", tipo: "cobranca", trecho: "cobra o Nelson" }, "'tipo' aceita só"],
    [{ os: "Nelson", tipo: "confirmar", firme: true, trecho: "avisa" }, "'firme' só vale no tipo pode_atrasar"],
    [{ os: "Nelson", tipo: "confirmar" }, "falta 'trecho'"],
    [{ tipo: "confirmar", trecho: "avisa" }, "falta 'os'"],
  ];
  for (const [args, msg] of recusas) {
    const c = paraCliente(args, CTX5);
    assertEquals(c.ok, false, JSON.stringify(args));
    if (!c.ok) assert(c.error.includes(msg), `${JSON.stringify(args)}: ${c.error}`);
  }
  assertEquals((TIPOS_DA_MENSAGEM_AO_CLIENTE as readonly string[]).includes("mudanca_no_dia"), false);
  assertEquals(TIPOS_DA_MENSAGEM_AO_CLIENTE.length, 10);
});

Deno.test("Fase 5: resultadoDaMensagemAoCliente — o texto pronto e a instrução de que nada saiu; a recusa = o que falta", () => {
  const ok = resultadoDaMensagemAoCliente({ ok: true, status: "preparada", texto: "Pronto para Flávio, sai agora: \"…\". Para mandar: *manda cliente Flávio*.", mensagem_id: "x" });
  assertEquals([ok.ok, ok.instrucao], [true, INSTRUCAO_CLIENTE]);
  assert(!("mensagem_id" in ok));
  const nao = resultadoDaMensagemAoCliente({ ok: false, motivo: "sem_prometido", pergunta: "Não há data dita para Giancarlo…", texto: "Não há data dita para Giancarlo…" });
  assertEquals([nao.ok, nao.texto], [false, "Não há data dita para Giancarlo…"]);
  assertThrows(() => resultadoDaMensagemAoCliente(null), Error, "respondeu sem texto");
});

Deno.test("Fase 5: paraPlanejar leva prometido (como o dono disse; ISO volta) e servico_cliente; agenda_ver aceita o foco clientes", () => {
  const c = paraPlanejar({ os: "Flávio", prometido: "dia 3", trecho: "falei pro Flávio que fica pra dia 3" }, CTX5);
  assertEquals(c.ok && c.params.p_dados, { prometido: "dia 3" });
  const s = paraPlanejar({ os: "Nelson", servico_cliente: "a instalação do painel", trecho: "pro cliente é a instalação do painel" }, CTX5);
  assertEquals(s.ok && s.params.p_dados, { servico_cliente: "a instalação do painel" });
  const iso = paraPlanejar({ os: "Flávio", prometido: "2026-11-03", trecho: "dia 3" }, CTX5);
  assertEquals(iso.ok, false);
  assertEquals((FOCOS as readonly string[]).includes("clientes"), true);
  const v = paraAgendaVer({ foco: "clientes", os: "Nelson" }, CTX5);
  assertEquals(v.ok && [v.params.p_foco, v.params.p_os], ["clientes", "Nelson"]);
});

// ───────── Fase 7b (P5): a dupla dita e a semana ─────────
const CTX7B = { autor: "00000000-0000-4000-8000-000000000001", canal: "whatsapp" as const, hoje: "2026-11-05" };

Deno.test("Fase 7b: paraPlanejar leva a dupla dita (nao, todos, inicio/fim com dupla_meios) só quando dita", () => {
  assertEquals([...DUPLAS], ["nao", "inicio", "fim", "todos"]);
  const um = paraPlanejar({ os: "Lenine", dupla: "nao", trecho: "o Lenine vai com uma pessoa só" }, CTX7B);
  assertEquals(um.ok && um.params.p_dados, { dupla: "nao" });
  const todos = paraPlanejar({ os: "Lenine", dupla: "todos", trecho: "o Lenine precisa de dois o tempo todo" }, CTX7B);
  assertEquals(todos.ok && todos.params.p_dados, { dupla: "todos" });
  const ini = paraPlanejar({ os: "Vanderlei", dupla: "inicio", dupla_meios: 2, trecho: "pro Vanderlei precisa de dois no primeiro dia" }, CTX7B);
  assertEquals(ini.ok && ini.params.p_dados, { dupla: "inicio", dupla_meios: 2 });
  assertEquals(ini.ok && [ini.params.p_os, ini.params.p_hoje], ["Vanderlei", "2026-11-05"]);
  // sem os meios-dias: vai só a dupla (o banco pergunta quantos)
  const semMeios = paraPlanejar({ os: "Vanderlei", dupla: "fim", trecho: "no fim precisa de dois" }, CTX7B);
  assertEquals(semMeios.ok && semMeios.params.p_dados, { dupla: "fim" });
  // a dupla junto do resto do que o dono disse
  const junto = paraPlanejar({ os: "Lenine", dias: 3, dupla: "todos", trecho: "são 3 dias, os dois o tempo todo" }, CTX7B);
  assertEquals(junto.ok && junto.params.p_dados, { dias: 3, dupla: "todos" });
  // sem a dupla, nada da dupla vai (a chamada é a de antes)
  const antes = paraPlanejar({ os: "Lenine", dias: 3, trecho: "são 3 dias" }, CTX7B);
  assertEquals(antes.ok && Object.keys(antes.params.p_dados as Record<string, unknown>), ["dias"]);
});

Deno.test("Fase 7b: paraPlanejar recusa a dupla fora da lista e dupla_meios sem inicio/fim, quebrado ou fora de 1 a 20", () => {
  assert(erro(paraPlanejar({ os: "Lenine", dupla: "dupla", trecho: "com dupla" }, CTX7B)).includes("aceita só: nao, inicio, fim, todos"));
  assert(erro(paraPlanejar({ os: "Lenine", dupla: "todos", dupla_meios: 2, trecho: "dois o tempo todo" }, CTX7B)).includes("só vai com dupla inicio ou fim"));
  assert(erro(paraPlanejar({ os: "Lenine", dupla_meios: 2, trecho: "dois no primeiro dia" }, CTX7B)).includes("só vai com dupla inicio ou fim"));
  for (const n of [1.5, 21, 0]) {
    assert(erro(paraPlanejar({ os: "Lenine", dupla: "inicio", dupla_meios: n, trecho: "dois no começo" }, CTX7B)).includes("de 1 a 20"), String(n));
  }
});

Deno.test("Fase 7b: paraDisponibilidade leva a semana como o dono disse (só quando dita); quem vem sob demanda é vem sem padrão nem semana", () => {
  const s = paraDisponibilidade({
    pessoa: "Rafael", situacao: "vem", dias: "segunda e terça", semana: "semana que vem",
    trecho: "o Rafael só pode segunda e terça na semana que vem",
  }, CTX7B);
  assertEquals(s.ok && s.params, {
    p_autor: CTX7B.autor, p_canal: "whatsapp", p_pessoa: "Rafael", p_situacao: "vem", p_dias: "segunda e terça", p_padrao: false,
    p_trecho: "o Rafael só pode segunda e terça na semana que vem", p_semana: "semana que vem", p_hoje: "2026-11-05",
  });
  const eu = paraDisponibilidade({
    pessoa: "eu", situacao: "vem", dias: "segunda e quarta", semana: "semana de 16/11",
    trecho: "fico em campo segunda e quarta na semana de 16/11",
  }, CTX7B);
  assertEquals(eu.ok && [eu.params.p_pessoa, eu.params.p_semana], ["eu", "semana de 16/11"]);
  // "o Mateus vem quarta e quinta": sem semana, a chamada é a de antes (8 argumentos; o banco lê as datas)
  const mateus = paraDisponibilidade({ pessoa: "Mateus", situacao: "vem", dias: "quarta e quinta", trecho: "o Mateus vem quarta e quinta" }, CTX7B);
  assertEquals(mateus.ok && "p_semana" in mateus.params, false);
  assertEquals(mateus.ok && mateus.params.p_padrao, false);
});

Deno.test("Fase 7b: paraDisponibilidade recusa a semana calculada (ISO) e a semana junto do padrão (toda semana × uma semana)", () => {
  assert(erro(paraDisponibilidade({ pessoa: "Rafael", situacao: "vem", dias: "seg", semana: "2026-11-16", trecho: "seg" }, CTX7B))
    .includes("sem calcular"));
  assert(erro(paraDisponibilidade({
    pessoa: "Rafael", situacao: "vem", dias: "seg a sex", semana: "semana que vem", padrao: true, trecho: "seg a sex",
  }, CTX7B)).includes("passe um dos dois"));
});

// ─── Fase 7c (P4, spec-fase7c.md §5.4, §7): paraHabilidade (quem faz o quê, o que a OS pede, o responsável, o "está certo") ───
const CTX7C = { autor: "00000000-0000-4000-8000-000000000001", canal: "whatsapp" as const, hoje: "2026-11-04" };
const NADA7C = { p_pessoa: null, p_o_que_faz: null, p_os: null, p_exige: null, p_meios: null, p_lider: null, p_confirmar: false };

Deno.test("Fase 7c (P4): paraHabilidade — as 4 formas (pessoa + o_que_faz; os + exige + meios; os + lider; confirmar), com o trecho e nulos no que não veio", () => {
  const base = { p_autor: CTX7C.autor, p_canal: "whatsapp", p_hoje: "2026-11-04" };
  const a = params(paraHabilidade({ pessoa: "Roberto", o_que_faz: "instala_sozinho", trecho: "o Roberto instala sozinho" }, CTX7C));
  assertEquals(a.rpc, "agenda_rascunho_habilidade");
  assertEquals(a.params, { ...base, ...NADA7C, p_pessoa: "Roberto", p_o_que_faz: "instala_sozinho", p_trecho: "o Roberto instala sozinho" });
  assertEquals(params(paraHabilidade({ os: "Lenine", exige: "altura", meios: "nao", trecho: "o Lenine não precisa de ninguém no teto" }, CTX7C))
    .params, { ...base, ...NADA7C, p_os: "Lenine", p_exige: "altura", p_meios: "nao", p_trecho: "o Lenine não precisa de ninguém no teto" });
  assertEquals(params(paraHabilidade({ os: "OS-00074", lider: "Roberto", trecho: "no Lenine o responsável é o Roberto" }, CTX7C)).params,
    { ...base, ...NADA7C, p_os: "OS-00074", p_lider: "Roberto", p_trecho: "no Lenine o responsável é o Roberto" });
  // "ninguém" é o responsável que sai (o banco limpa); o confirmar é o "está certo"
  assertEquals(params(paraHabilidade({ os: "Lenine", lider: "ninguém", trecho: "o Lenine fica sem responsável" }, CTX7C)).params.p_lider,
    "ninguém");
  assertEquals(params(paraHabilidade({ confirmar: true, trecho: "está certo o que você marcou" }, CTX7C)).params,
    { ...base, ...NADA7C, p_confirmar: true, p_trecho: "está certo o que você marcou" });
  // o dono ("eu") e o painel
  assertEquals(params(paraHabilidade({ pessoa: "eu", o_que_faz: "nao_sobe_no_teto", trecho: "eu não subo no teto" },
    { ...CTX7C, canal: "painel" })).params.p_canal, "painel");
  // o confirmar false não conta como forma
  assertEquals(params(paraHabilidade({ pessoa: "João", o_que_faz: "ajudante", confirmar: false, trecho: "o João é ajudante" }, CTX7C))
    .params.p_confirmar, false);
});

Deno.test("Fase 7c (P4): paraHabilidade recusa duas formas, a forma pela metade, o id, os valores fora da lista e sem trecho (nada chamado)", () => {
  const umaCoisa = "Diga uma coisa por vez: o que a pessoa faz, o que a OS pede, quem é o responsável ou que está certo.";
  for (const args of [
    { pessoa: "Roberto", o_que_faz: "instala_sozinho", os: "Lenine", exige: "altura", meios: "todos", trecho: "x" },
    { os: "Lenine", exige: "altura", meios: "todos", lider: "Roberto", trecho: "x" },
    { pessoa: "Roberto", o_que_faz: "instala_sozinho", confirmar: true, trecho: "x" },
    { os: "Lenine", lider: "Roberto", confirmar: true, trecho: "x" },
  ]) {
    assertEquals(erro(paraHabilidade(args, CTX7C)), `${umaCoisa}. Nada foi chamado.`, JSON.stringify(args));
  }
  assert(erro(paraHabilidade({ pessoa: "Roberto", trecho: "x" }, CTX7C)).startsWith("falta 'o_que_faz'"));
  assert(erro(paraHabilidade({ o_que_faz: "ajudante", trecho: "x" }, CTX7C)).startsWith("falta 'pessoa'"));
  assert(erro(paraHabilidade({ pessoa: "Roberto", o_que_faz: "ajudante", os: "Lenine", trecho: "x" }, CTX7C)).includes("vale para todo serviço"));
  assert(erro(paraHabilidade({ exige: "altura", meios: "todos", trecho: "x" }, CTX7C)).startsWith("falta 'os'"));
  assert(erro(paraHabilidade({ os: "Lenine", exige: "altura", trecho: "x" }, CTX7C)).startsWith("falta 'meios'"));
  assert(erro(paraHabilidade({ os: "Lenine", meios: "todos", trecho: "x" }, CTX7C)).startsWith("falta 'exige'"));
  assert(erro(paraHabilidade({ lider: "Roberto", trecho: "x" }, CTX7C)).startsWith("falta 'os'"));
  assert(erro(paraHabilidade({ confirmar: true, os: "Lenine", trecho: "x" }, CTX7C)).includes("sem 'os'"));
  assert(erro(paraHabilidade({ os: "Lenine", trecho: "x" }, CTX7C)).includes("diga o que ela pede"));
  assert(erro(paraHabilidade({ trecho: "x" }, CTX7C)).startsWith("diga o que a pessoa faz"));
  assert(erro(paraHabilidade({ pessoa: "Roberto", o_que_faz: "instala_sozinho" }, CTX7C)).startsWith("falta 'trecho'"));
  assert(erro(paraHabilidade({ pessoa: UUID_QUALQUER, o_que_faz: "ajudante", trecho: "x" }, CTX7C)).includes("não o id"));
  assert(erro(paraHabilidade({ os: "Lenine", lider: UUID_QUALQUER, trecho: "x" }, CTX7C)).includes("não o id"));
  assert(erro(paraHabilidade({ os: UUID_QUALQUER, exige: "altura", meios: "todos", trecho: "x" }, CTX7C)).includes("não o id"));
  assert(erro(paraHabilidade({ pessoa: "Roberto", o_que_faz: "pilota_barco", trecho: "x" }, CTX7C)).includes("'o_que_faz' aceita só"));
  assert(erro(paraHabilidade({ os: "Lenine", exige: "solda", meios: "todos", trecho: "x" }, CTX7C)).includes("'exige' aceita só"));
  assert(erro(paraHabilidade({ os: "Lenine", exige: "altura", meios: "metade", trecho: "x" }, CTX7C)).includes("'meios' aceita só"));
  assert(erro(paraHabilidade({ confirmar: "sim", trecho: "x" }, CTX7C)).includes("true ou false"));
});

Deno.test("Fase 7c (P4): os valores são os do banco (§3.2 e o CHECK de exigencias_ditas); agenda_ver aceita o foco habilidades", () => {
  assertEquals([...O_QUE_FAZ], [
    "instala_com_alguem", "instala_sozinho", "instala_e_ensina", "novo", "ajudante", "quase_instala", "nao_comissiona",
    "acompanha_comissionamento", "diagnostica", "comissiona", "nao_sobe_no_teto", "sobe_acompanhado", "sobe_no_teto", "sobe_e_orienta",
  ]);
  assertEquals([...EXIGENCIAS], ["energizado", "comissionamento", "altura", "diagnostico"]);
  assertEquals([...MEIOS], ["todos", "ultimo", "nao"]);
  assertEquals(RPC_HABILIDADE, "agenda_rascunho_habilidade");
  assertEquals(UMA_COISA_POR_VEZ, "Diga uma coisa por vez: o que a pessoa faz, o que a OS pede, quem é o responsável ou que está certo.");
  assertEquals((FOCOS as readonly string[]).includes("habilidades"), true);
  const v = paraAgendaVer({ foco: "habilidades", os: "Lenine" }, CTX7C);
  assertEquals(v.ok && [v.params.p_foco, v.params.p_os], ["habilidades", "Lenine"]);
});
