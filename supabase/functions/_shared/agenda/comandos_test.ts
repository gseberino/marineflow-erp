// Agenda de Produção, Fase 1 (P6): as palavras curtas da agenda — o que é lido (a tabela da spec §7.2) e, o principal,
// o que NÃO pode colidir: a confirmação do assistente (sim/ok/1 · não/2), as letras e os comandos do secretário, os
// comandos e as respostas dos comprovantes e o registro de pergunta ativa.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ComandoDaAgenda, frasesDaAgenda, lerComandoDaAgenda } from "./comandos.ts";
import { ehComandoDaAgendaLigada } from "./executar.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerPedidoDePdf } from "../ai/atalho-pdf.ts";
import { type DependenciasDoTexto, rotearTextoDoDono } from "../comprovantes/webhook.ts";
import {
  type EstadoDoTelefone,
  lerNumero,
  lerSimNao,
  normalizarResposta,
  pareceRespostaCurta,
  quemResponde,
  travaDaConfirmacao,
} from "../whatsapp/pergunta-ativa.ts";

const semana: ComandoDaAgenda = { comando: "ver", periodo: "semana", foco: "tudo", pessoa: null };
const hoje: ComandoDaAgenda = { comando: "ver", periodo: "hoje", foco: "tudo", pessoa: null };
const amanha: ComandoDaAgenda = { comando: "ver", periodo: "amanha", foco: "tudo", pessoa: null };
const proxima: ComandoDaAgenda = { comando: "ver", periodo: "proxima_semana", foco: "tudo", pessoa: null };
const livre: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "livre", pessoa: null };
const atrasos: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "atrasos", pessoa: null };
const oQueFazer: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "o_que_fazer", pessoa: "eu" };
const gravar: ComandoDaAgenda = { comando: "gravar" };
const descartar: ComandoDaAgenda = { comando: "descartar" };

// A tabela da spec §7.2, escrita como o dono escreve (acento, maiúscula, negrito, ponto, interrogação, o 🎤 do áudio).
const TABELA: Array<[string, ComandoDaAgenda]> = [
  ["agenda", semana],
  ["Agenda", semana],
  ["*agenda*", semana],
  ["A agenda", semana],
  ["Minha agenda", hoje],
  ["agenda da semana", semana],
  ["Agenda dessa semana?", semana],
  ["agenda desta semana", semana],
  ["🎤 Agenda.", semana],
  ["agenda hoje", hoje],
  ["Agenda de hoje", hoje],
  ["agenda pra hoje", hoje],
  ["agenda amanhã", amanha],
  ["Agenda de amanhã?", amanha],
  ["agenda pra amanhã", amanha],
  ["O que tem pra amanhã?", amanha],
  ["o que tem para amanhã", amanha],
  ["agenda semana que vem", proxima],
  ["Agenda da semana que vem", proxima],
  ["agenda próxima semana", proxima],
  ["agenda da próxima semana", proxima],
  ["livre", livre],
  ["Livre?", livre],
  ["quando fica livre?", livre],
  ["Quando fico livre", livre],
  ["quando a gente fica livre?", livre],
  ["atrasado", atrasos],
  ["Atrasados", atrasos],
  ["atrasadas", atrasos],
  ["O que está atrasado?", atrasos],
  ["o que tá atrasado", atrasos],
  ["o que eu tenho que fazer", oQueFazer],
  ["O que eu tenho que fazer hoje?", oQueFazer],
  ["o que tenho que fazer", oQueFazer],
  ["o que eu tenho pra fazer", oQueFazer],
  ["o que tenho pra fazer hoje", oQueFazer],
  ["O que eu tenho para fazer?", oQueFazer],
  ["o que eu tenho de fazer", oQueFazer],
  ["o que tem pra fazer", oQueFazer],
  ["o que tem pra fazer hoje?", oQueFazer],
  ["🎤 O que eu tenho que fazer hoje.", oQueFazer],
  ["grava", gravar],
  ["*grava*", gravar],
  ["Grava.", gravar],
  ["gravar", gravar],
  ["grave", gravar],
  ["Pode gravar", gravar],
  ["grava tudo", gravar],
  ["pode gravar tudo!", gravar],
  ["🎤 Grava.", gravar],
  ["descarta", descartar],
  ["*descarta*", descartar],
  ["descartar", descartar],
  ["descarte", descartar],
  ["Descarta tudo", descartar],
];

Deno.test("lerComandoDaAgenda: lê cada linha da tabela da spec §7.2 (sem acento, sem negrito, sem pontuação final)", () => {
  for (const [texto, esperado] of TABELA) assertEquals(lerComandoDaAgenda(texto), esperado, texto);
});

Deno.test("lerComandoDaAgenda: quem chama recebe uma cópia (não muda a tabela)", () => {
  const c = lerComandoDaAgenda("agenda") as { foco: string };
  c.foco = "livre";
  assertEquals(lerComandoDaAgenda("agenda"), semana);
});

// Uma palavra a mais é conversa: vai ao modelo, que tem a ferramenta e o resto do contexto.
const CONVERSA = [
  "agenda o Lenine para terça", "agenda a OS 112", "agendar", "agende", "minha agenda de amanhã com o Roberto",
  "o que eu tenho que fazer amanhã", "o que o Roberto faz amanhã?", "como tá a semana?", "quando dá para fazer o do César?",
  "livre amanhã?", "o Roberto está livre?", "atrasado o Flávio?", "por que está atrasado?", "grava isso pra mim", "grava o áudio",
  "não grava", "pode gravar não", "descarta o do Lenine", "gravei", "gravado", "gravação", "agenda livre", "tá livre",
  "o que tem pra amanhã com o Roberto", "", "   ", "a", "g", "1", "2", "ok", "sim", "não",
];

Deno.test("conversa com uma palavra a mais (e o vazio) não é comando", () => {
  for (const t of CONVERSA) assertEquals(lerComandoDaAgenda(t), null, t);
  assertEquals(lerComandoDaAgenda("agenda ".repeat(60)), null, "texto longo nunca é comando");
  assertEquals(lerComandoDaAgenda(undefined as unknown as string), null);
});

// A confirmação do assistente (whatsapp-channel.ts) e o resto do que o dono já manda hoje.
const APROVA = ["sim", "s", "ok", "confirmar", "1"];
const RECUSA = ["não", "nao", "n", "cancelar", "2"];
const NAO_SAO_DA_AGENDA = [
  ...APROVA, ...RECUSA, "Sim", "SIM 1234", "sim, pode", "1 sim", "2 não", "3", "10", "um", "dois", "opção 2", "a 2", "o terceiro",
  // as letras do secretário (o alfabeto do dia) e as letras que pareceriam sim/não
  ..."abcdefghijklmnopqrstuvwxyz".split(""), "É", "é",
  // comprovantes (comprovantes/respostas.ts)
  "pendentes", "pendencias", "comprovantes pendentes", "cmp 12", "CMP-124", "feito cmp 12", "cancela cmp 3 errado", "cancelar esse",
  "pular", "depois", "deixa pra depois", "sair", "pare", "parar", "corrigir valor 70", "corrigir", "obs: compra do Brisa", "lote antigo",
  // respostas do registro de pergunta ativa
  "beleza", "valeu", "👍", "isso", "pix", "debito", "estoque", "empresa", "pessoal", "OS 12", "62,50", "ontem", "hoje", "amanhã",
  "segunda", "certo", "ta bom", "confirmo",
  // o atalho do PDF
  "me manda o pdf do orçamento 117",
];

Deno.test("nada da confirmação, das letras, dos comprovantes, do PDF ou de menu vira comando da agenda", () => {
  for (const t of NAO_SAO_DA_AGENDA) assertEquals(lerComandoDaAgenda(t), null, t);
});

/** Todas as frases da tabela, cruas e como chegam (negrito, maiúscula, ponto). */
function todasAsFormas(): string[] {
  const base = frasesDaAgenda();
  return [...base, ...base.map((f) => `*${f}*`), ...base.map((f) => `${f[0].toUpperCase()}${f.slice(1)}.`), ...TABELA.map(([t]) => t)];
}

Deno.test("nenhum comando começa por sim/s/ok/confirmar/1 ou não/nao/n/cancelar/2, nenhum é letra, nenhum tem número", () => {
  const primeiras = new Set([...APROVA, ...RECUSA]);
  for (const f of frasesDaAgenda()) {
    assert(!primeiras.has(f.split(" ")[0]), `começa pela confirmação: ${f}`);
    assert(f.replace(/ /g, "").length > 1, `letra: ${f}`);
    assert(!/\d/.test(f), `número: ${f}`);
  }
});

Deno.test("nenhum comando aprova, recusa ou escolhe opção na confirmação do assistente; nenhum é do atalho do PDF", () => {
  for (const t of todasAsFormas()) {
    assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
    assertEquals(parseOptionReply(t, 9), null, `opção: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
  }
});

Deno.test("nenhum comando da agenda é lido pelo secretário", () => {
  for (const t of todasAsFormas()) assertEquals(lerComandoDoSecretario(t), null, t);
});

/** Os comandos do secretário — a lista do comandos_test.ts dele (lida da fonte, para acompanhar quando ela crescer). */
async function comandosDoSecretario(): Promise<string[]> {
  const fonte = await Deno.readTextFile(new URL("../secretario/comandos_test.ts", import.meta.url));
  const ini = fonte.indexOf("const COMANDOS");
  const fim = fonte.indexOf("];", ini);
  assert(ini > 0 && fim > ini, "a lista COMANDOS do secretário sumiu de comandos_test.ts");
  const bloco = fonte.slice(ini, fim);
  return [...bloco.matchAll(/^\s*\["((?:[^"\\]|\\.)*)",/gm)].map((m) => m[1]);
}

Deno.test("nenhum comando do secretário (a lista do comandos_test.ts dele, mais tarde e papelada) é lido pela agenda", async () => {
  const lista = await comandosDoSecretario();
  assert(lista.length >= 30, `lista do secretário curta demais (${lista.length})`);
  const tarde = [
    "C semana, B tira, G 15 dias", "C semana e B tira", "F cobrar", "F negociar", "F baixa", "ajudou", "pouco", "ajudou pouco",
    "atrapalhou", "a semana ajudou", "lote", "lote sem 3, 7", "lote sem avisos", "lote só despesas", "ver o lote",
  ];
  for (const t of [...lista, ...tarde]) {
    assert(lerComandoDoSecretario(t) !== null, `deixou de ser do secretário: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, t);
  }
});

Deno.test("nenhum comando da agenda é comando dos comprovantes nem número do registro de pergunta ativa", () => {
  for (const t of todasAsFormas()) {
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
    assertEquals(lerNumero(normalizarResposta(t), 99), null, `número: ${t}`);
  }
});

// A exceção conhecida (e por que não colide): "grava", "grave" e "pode gravar" JÁ são um "sim" para lerSimNao — a
// confirmação do CMP aceita "grava" como sim. Por isso o webhook marca a palavra da agenda como comando (quemResponde →
// assistente antes de ler a resposta do CMP) e o CMP continua pedindo *sim*. Se esta lista mudar, revise o roteamento.
const GRAVA_QUE_E_SIM = ["grava", "grave", "pode gravar"];

Deno.test("sim/não/ok do registro: só 'grava', 'grave' e 'pode gravar' são sim (a exceção conhecida); o resto não é resposta curta", () => {
  for (const t of todasAsFormas()) {
    const n = normalizarResposta(t.replace(/[*_~]/g, ""));
    if (GRAVA_QUE_E_SIM.includes(n)) {
      assertEquals(lerSimNao(n), "sim", t);
      continue;
    }
    assertEquals(lerSimNao(n), null, `sim/não/ok: ${t}`);
    assertEquals(pareceRespostaCurta(t), false, `resposta curta: ${t}`);
  }
});

const AGORA = new Date("2026-10-23T15:00:00Z");
function estadoComCmpNoConfirmar(): EstadoDoTelefone {
  return {
    conversa: true, dono: true,
    ativa: {
      id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "confirmar",
      opcoes: [], wa_message_id: "WA-P", aberta_em: "2026-10-23T14:59:00Z",
    },
    citada: null,
    pendencia: { tipo: "confirmacao", id: "pend-1", titulo: "Enviar lembrete", desde: "2026-10-23T14:00:00Z" },
    cmp_em_contexto: null,
  };
}

Deno.test("a trava do 'sim' do comprovante não segura nenhum comando da agenda — salvo o 'grava' que é sim (desempate, nada aprovado)", () => {
  for (const t of todasAsFormas()) {
    const trava = travaDaConfirmacao(estadoComCmpNoConfirmar(), t, { pending_confirm_action_id: "pend-1" });
    // (a trava lê o texto cru: o "*grava*" com o negrito do WhatsApp nem parece confirmação para ela)
    const ehSim = GRAVA_QUE_E_SIM.includes(normalizarResposta(t));
    // com uma pendência do assistente E a pergunta do CMP aberta, "grava" pergunta de quem é (citar decide): seguro
    assertEquals(trava.travar, ehSim, t);
  }
});

Deno.test("quemResponde: com o CMP no 'confirmar', 'grava' e 'livre' com a marca vão ao assistente; sem a marca, o caminho de hoje", () => {
  const base = { citado: null, estado: estadoComCmpNoConfirmar(), ehRespostaValida: true, ehComando: null, agora: AGORA };
  for (const texto of ["grava", "livre", "agenda", "atrasado", "o que eu tenho que fazer", "descarta"]) {
    assertEquals(quemResponde({ ...base, texto, ehComandoDoSecretario: true }), { destino: "assistente", motivo: "comando_do_secretario" }, texto);
  }
  // sem a marca (agenda desligada): "grava" é o sim do CMP, como hoje
  assertEquals(quemResponde({ ...base, texto: "grava" }).destino, "comprovante");
  // citar a pergunta do CMP decide: vai ao CMP mesmo sendo palavra da agenda
  const citando = quemResponde({
    ...base, texto: "grava", citado: "WA-P", ehComandoDoSecretario: true,
    estado: { ...estadoComCmpNoConfirmar(), citada: { id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", status: "aberta", passo: "confirmar" } },
  });
  assertEquals(citando.destino, "comprovante");
});

// ─── O roteamento do webhook de ponta a ponta (rotearTextoDoDono), com a dependência como o index.ts monta ────────

const FONE = "5547999990000";

/**
 * Um admin de mentira: agenda_config.modo_leitura (ou erro) e quantas vezes a chave foi lida. fase2 = modo_proposta (a
 * agenda automática; as palavras da Fase 2 só valem fora de 'desligado').
 */
function adminDaAgenda(modo: string | "erro" | "sem_tabela", fase2 = "desligado") {
  const lidas: string[] = [];
  return {
    lidas,
    from(tabela: string) {
      lidas.push(tabela);
      const q = {
        select: () => q,
        maybeSingle: () =>
          Promise.resolve(
            modo === "erro" ? { data: null, error: { code: "XX000" } }
            : modo === "sem_tabela" ? { data: null, error: { code: "42P01", message: "relation \"agenda_config\" does not exist" } }
            : { data: { modo_leitura: modo, modo_proposta: fase2, modo_vigia: "desligado" }, error: null },
          ),
      };
      return q;
    },
  };
}

function depsDoWebhook(modo: string, transcricao?: string, fase2 = "desligado") {
  const admin = adminDaAgenda(modo, fase2);
  const c = { chamar: [] as Array<Record<string, unknown>>, despachos: [] as Array<string | undefined>, admin };
  const estado: EstadoDoTelefone = { ...estadoComCmpNoConfirmar(), pendencia: null, ativa: { ...estadoComCmpNoConfirmar().ativa!, aberta_em: new Date(Date.now() - 60_000).toISOString() } };
  const d: DependenciasDoTexto = {
    estado: () => Promise.resolve(estado),
    transcrever: () => Promise.resolve(transcricao ?? null),
    chamarComprovantes: (corpo) => {
      c.chamar.push(corpo);
      return Promise.resolve({ status: 200, tratada: true });
    },
    despacharAoAgente: (texto) => {
      c.despachos.push(texto);
      return Promise.resolve();
    },
    avisarFalha: () => Promise.resolve(),
    interromper: () => Promise.resolve(),
    // como o whatsapp-webhook/index.ts monta (o secretário com o formato antigo: só a agenda pode marcar)
    comandoDoSecretario: async (t) => (lerComandoDoSecretario(t) !== null && false) || (await ehComandoDaAgendaLigada(admin, t)),
  };
  return { d, c };
}

const TEXTO = (texto: string, tipo = "text") => ({ msgId: "msg-1", phone: FONE, tipo, texto, citado: null });

Deno.test("webhook: com a agenda em sombra ou ligada, 'grava', 'livre' e 'agenda' vão ao assistente (o CMP no 'confirmar' não vira 'sim')", async () => {
  for (const modo of ["sombra", "ligado"]) {
    for (const t of ["grava", "livre", "agenda", "o que eu tenho que fazer hoje?", "descarta"]) {
      const { d, c } = depsDoWebhook(modo);
      assertEquals(await rotearTextoDoDono(TEXTO(t), d), "assistente", `${modo}: ${t}`);
      assertEquals(c.chamar.length, 0, t);
      assertEquals(c.despachos, [t]);
    }
  }
});

Deno.test("webhook: agenda desligada, chave com erro ou tabela ainda não aplicada = o caminho de hoje ('grava' é o sim do CMP)", async () => {
  for (const modo of ["desligado", "erro", "sem_tabela", "qualquer"]) {
    const { d, c } = depsDoWebhook(modo);
    assertEquals(await rotearTextoDoDono(TEXTO("grava"), d), "comprovante", modo);
    assertEquals(c.chamar.length, 1);
    assertEquals(c.despachos.length, 0);
  }
});

Deno.test("webhook: o '1', o 'sim' e o 'não' continuam do CMP com a agenda ligada; a chave da agenda nem é lida", async () => {
  for (const t of ["1", "sim", "não", "2", "ok", "beleza"]) {
    const { d, c } = depsDoWebhook("ligado");
    assertEquals(await rotearTextoDoDono(TEXTO(t), d), "comprovante", t);
    assertEquals(c.despachos.length, 0);
    assertEquals(c.admin.lidas, [], `a chave só é lida quando o texto é comando: ${t}`);
  }
});

Deno.test("webhook: áudio — a palavra da agenda vale pela transcrição", async () => {
  const { d, c } = depsDoWebhook("sombra", "Grava.");
  assertEquals(await rotearTextoDoDono(TEXTO("[audio]", "audio"), d), "assistente");
  assertEquals(c.despachos, ["Grava."]);
});

// ─── Fase 2 (P5, spec-fase2.md §11): a conferência do dia, o desfazer e os focos novos ───────────────────────

const dia = (resultado: "cumprido" | "parcial" | "nao_cumprido", motivo: string | null = null, quando: string | null = null): ComandoDaAgenda =>
  ({ comando: "dia", resultado, motivo, quando });
const mudancas: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "mudancas", pessoa: null };
const decisoes: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "decisoes", pessoa: null };
const plano: ComandoDaAgenda = { comando: "ver", periodo: null, foco: "plano", pessoa: null };

const TABELA_FASE2: Array<[string, ComandoDaAgenda]> = [
  ["dia feito", dia("cumprido")],
  ["*Dia feito*", dia("cumprido")],
  ["Dia feito.", dia("cumprido")],
  ["🎤 Dia feito.", dia("cumprido")],
  ["dia feito ontem", dia("cumprido", null, "ontem")],
  ["dia feito segunda", dia("cumprido", null, "segunda")],
  ["dia feito segunda-feira", dia("cumprido", null, "segunda feira")],
  ["dia feito 03/11", dia("cumprido", null, "03/11")],
  ["dia não cliente", dia("nao_cumprido", "cliente_ou_bem")],
  ["Dia nao material", dia("nao_cumprido", "material")],
  ["dia não equipe ontem", dia("nao_cumprido", "equipe_faltou", "ontem")],
  ["dia não clima", dia("nao_cumprido", "clima")],
  ["dia não", dia("nao_cumprido")],
  ["dia não ontem", dia("nao_cumprido", null, "ontem")],
  ["dia parcial imprevisto", dia("parcial", "imprevisto_tecnico")],
  ["dia parcial anterior", dia("parcial", "trabalho_anterior")],
  ["dia parcial informação", dia("parcial", "informacao")],
  ["dia parcial estimativa 02/11", dia("parcial", "estimativa", "02/11")],
  ["dia parcial urgência", dia("parcial", "urgencia_outra_os")],
  ["dia parcial esqueci", dia("parcial", "esqueci")],
  ["dia parcial", dia("parcial")],
  ["dia parcial sexta feira", dia("parcial", null, "sexta feira")],
  ["choveu", { comando: "choveu", quando: null }],
  ["Choveu hoje!", { comando: "choveu", quando: "hoje" }],
  ["choveu ontem", { comando: "choveu", quando: "ontem" }],
  ["desfaz", { comando: "desfazer", alvo: null }],
  ["Desfazer", { comando: "desfazer", alvo: null }],
  ["desfaça", { comando: "desfazer", alvo: null }],
  ["desfaz Nelson", { comando: "desfazer", alvo: "nelson" }],
  ["desfaz o Vanderlei", { comando: "desfazer", alvo: "vanderlei" }],
  ["desfaz a semana", { comando: "desfazer", alvo: "semana" }],
  ["desfaz semana", { comando: "desfazer", alvo: "semana" }],
  ["desfaz OS-00112", { comando: "desfazer", alvo: "os-00112" }],
  ["o que mudou?", mudancas],
  ["O que você mudou", mudancas],
  ["agenda mudanças", mudancas],
  ["agenda pendências", decisoes],
  ["o que você precisa de mim?", decisoes],
  ["agenda plano", plano],
  ["Plano da semana", plano],
];

Deno.test("Fase 2 — lerComandoDaAgenda: cada linha da tabela da spec §11 (motivo → código LCI; o dia como o dono disse)", () => {
  for (const [texto, esperado] of TABELA_FASE2) assertEquals(lerComandoDaAgenda(texto), esperado, texto);
});

// Uma palavra a mais, o motivo que não existe, o dia que não é dia, a letra do secretário: conversa (vai ao modelo).
const CONVERSA_FASE2 = [
  "dia", "feito", "dia feito com o Roberto", "dia feito mas faltou o João", "dia não foi bom", "dia nao chuva forte",
  "dia parcial porque choveu", "dia feito amanhã", "dia feito semana que vem", "choveu muito", "choveu no Lenine",
  "desfaz b", "desfaz B", "desfaz a", "desfaz o c", "desfaz item c", "desfaz letra d", "desfaz x", "desfaz o",
  "desfaz " + "x".repeat(45), "o que mudou no Lenine", "o que você mudou ontem?", "agenda plano do Lenine", "plano",
  "pendências", "pendencias", "mudou",
  // revisão da Fase 2: o que o prompt ensina para outras ferramentas (prompt.ts: estornar_pagamento e desagrupar_orcamento)
  // e o "desfaz isso" sem dizer de quê vão ao modelo
  "desfaz o agrupamento do ORÇ-00120", "desfaz a baixa da conta de luz", "desfaz a baixa da conta de luz, ainda não paguei",
  "desfaz isso", "desfaz o último lançamento", "desfaz o pix do Roberto", "desfaz tudo", "desfazer o agrupamento",
  "desfaz a diária do João", "desfaz o pagamento",
];

Deno.test("Fase 2 — conversa (palavra a mais, motivo ou dia desconhecido, letra do secretário) não é comando", () => {
  for (const t of CONVERSA_FASE2) assertEquals(lerComandoDaAgenda(t), null, t);
});

/** As formas da Fase 2 como chegam (a tabela, com negrito e com ponto). */
function formasFase2(): string[] {
  const base = TABELA_FASE2.map(([t]) => t);
  return [...base, ...base.map((t) => `*${t}*`), ...base.map((t) => `${t}.`)];
}

Deno.test("Fase 2 — nenhuma palavra nova é lida pelo secretário, pela confirmação, pelo menu, pelo PDF ou pelos comprovantes", () => {
  for (const t of formasFase2()) {
    assertEquals(lerComandoDoSecretario(t), null, `secretário: ${t}`);
    assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
    assertEquals(parseOptionReply(t, 9), null, `opção: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
  }
});

Deno.test("Fase 2 — nenhuma palavra nova é sim/não/ok, número de menu ou resposta curta para a pergunta ativa", () => {
  for (const t of formasFase2()) {
    const n = normalizarResposta(t.replace(/[*_~]/g, ""));
    assertEquals(lerSimNao(n), null, `sim/não: ${t}`);
    assertEquals(lerNumero(n, 99), null, `número: ${t}`);
    assertEquals(pareceRespostaCurta(t), false, `resposta curta: ${t}`);
    const trava = travaDaConfirmacao(estadoComCmpNoConfirmar(), t, { pending_confirm_action_id: "pend-1" });
    assertEquals(trava.travar, false, `trava do CMP: ${t}`);
  }
});

Deno.test("Fase 2 — o secretário continua dono do '<letra> feito', do 'volta X' e do 'desfaz <letra>'; a agenda não lê nenhum", () => {
  for (const t of ["b feito", "B feito", "volta Flávio", "volta b", "desfaz b", "desfazer c", "desfaz o c", "desfaz item c", "tudo"]) {
    assert(lerComandoDoSecretario(t) !== null, `deixou de ser do secretário: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, t);
  }
});

Deno.test("Fase 2 — as frases fixas novas também não começam pela confirmação, não são letra nem número", () => {
  const primeiras = new Set([...APROVA, ...RECUSA]);
  for (const f of ["o que mudou", "o que voce mudou", "agenda mudancas", "agenda pendencias", "o que voce precisa de mim", "agenda plano", "plano da semana"]) {
    assert(frasesDaAgenda().includes(f), `fora da tabela: ${f}`);
    assert(!primeiras.has(f.split(" ")[0]), f);
    assert(!/\d/.test(f), f);
  }
});

Deno.test("Fase 2 — webhook: com a agenda em sombra ou ligada, 'dia feito' e 'desfaz Nelson' vão ao assistente (o CMP não os lê)", async () => {
  for (const modo of ["sombra", "ligado"]) {
    for (const t of ["dia feito", "desfaz Nelson", "choveu", "dia não cliente", "o que mudou?"]) {
      const { d, c } = depsDoWebhook(modo, undefined, "sombra");
      assertEquals(await rotearTextoDoDono(TEXTO(t), d), "assistente", `${modo}: ${t}`);
      assertEquals(c.chamar.length, 0, t);
    }
  }
});

// ─── Fase 3 (P3): *concluiu* e *entreguei* (spec-fase3.md §11) ────────────────────────────────────────────────────

const concluir = (alvo: string | null): ComandoDaAgenda => ({ comando: "concluir", alvo });
const entregar = (alvo: string): ComandoDaAgenda => ({ comando: "entregar", alvo });

const TABELA_FASE3: Array<[string, ComandoDaAgenda]> = [
  ["concluiu", concluir(null)],
  ["Concluiu.", concluir(null)],
  ["*concluiu*", concluir(null)],
  ["concluiu Lenine", concluir("lenine")],
  ["Concluiu o Lenine", concluir("lenine")],
  ["concluiu o Vanderlei!", concluir("vanderlei")],
  ["concluído Lenine", concluir("lenine")],
  ["concluida a Maria", concluir("maria")],
  ["concluiu OS-00074", concluir("os-00074")],
  ["concluiu a OS-00074", concluir("os-00074")],
  ["🎤 Concluiu o Lenine.", concluir("lenine")],
  ["entreguei Lenine", entregar("lenine")],
  ["Entreguei o Lenine", entregar("lenine")],
  ["entregue Vanderlei", entregar("vanderlei")],
  ["entreguei OS-00074", entregar("os-00074")],
];

Deno.test("Fase 3 — lerComandoDaAgenda: *concluiu* (com ou sem alvo) e *entreguei <alvo>*", () => {
  for (const [texto, esperado] of TABELA_FASE3) assertEquals(lerComandoDaAgenda(texto), esperado, texto);
});

// Conversa: palavra a mais, o alvo de outra ferramenta, a letra do secretário, "entregue"/"entreguei" sozinhos.
const CONVERSA_FASE3 = [
  "concluido", "concluida", "entregue", "entreguei", "concluiu o pagamento", "concluiu o pagamento?", "concluiu a cobrança",
  "concluiu b", "concluiu a", "concluiu o item c", "entreguei b", "concluiu o serviço do Lenine", "concluiu a instalação do inversor",
  "entreguei o barco do Lenine", "o Lenine concluiu", "já concluiu?", "concluiu " + "x".repeat(45), "entreguei a nota fiscal",
  "concluiu tudo", "concluiu isso", "entregue o pedido", "concluiu o lançamento",
];

Deno.test("Fase 3 — conversa (alvo de outra ferramenta, letra, sem alvo, palavra a mais) não é comando", () => {
  for (const t of CONVERSA_FASE3) assertEquals(lerComandoDaAgenda(t), null, t);
});

function formasFase3(): string[] {
  const base = TABELA_FASE3.map(([t]) => t);
  return [...base, ...base.map((t) => `*${t}*`), ...base.map((t) => `${t}.`)];
}

Deno.test("Fase 3 — *concluiu*/*entreguei* não são do secretário, da confirmação, do menu, do PDF nem dos comprovantes", () => {
  for (const t of formasFase3()) {
    assertEquals(lerComandoDoSecretario(t), null, `secretário: ${t}`);
    assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
    assertEquals(parseOptionReply(t, 9), null, `opção: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
  }
});

Deno.test("Fase 3 — *concluiu*/*entreguei* não são sim/não/ok, número de menu nem resposta curta à pergunta ativa", () => {
  for (const t of formasFase3()) {
    const n = normalizarResposta(t.replace(/[*_~]/g, ""));
    assertEquals(lerSimNao(n), null, `sim/não: ${t}`);
    assertEquals(lerNumero(n, 99), null, `número: ${t}`);
    assertEquals(pareceRespostaCurta(t), false, `resposta curta: ${t}`);
    const trava = travaDaConfirmacao(estadoComCmpNoConfirmar(), t, { pending_confirm_action_id: "pend-1" });
    assertEquals(trava.travar, false, `trava do CMP: ${t}`);
  }
});

Deno.test("Fase 3 — o secretário continua dono do '<letra> feito/pronto'; a agenda não lê o 'concluiu <letra>'", () => {
  for (const t of ["b feito", "B pronto", "c resolvido"]) {
    assert(lerComandoDoSecretario(t) !== null, `deixou de ser do secretário: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, t);
  }
  for (const t of ["concluiu b", "concluiu c", "entreguei d"]) assertEquals(lerComandoDaAgenda(t), null, t);
});

Deno.test("Fase 3 — webhook: com a agenda em sombra ou ligada, *concluiu Lenine* e *entreguei Lenine* vão ao assistente", async () => {
  for (const modo of ["sombra", "ligado"]) {
    for (const t of ["concluiu Lenine", "concluiu", "entreguei Lenine"]) {
      const { d, c } = depsDoWebhook(modo, undefined, "sombra");
      assertEquals(await rotearTextoDoDono(TEXTO(t), d), "assistente", `${modo}: ${t}`);
      assertEquals(c.chamar.length, 0, t);
    }
  }
});
