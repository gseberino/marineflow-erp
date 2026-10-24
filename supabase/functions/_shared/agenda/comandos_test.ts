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

/** Um admin de mentira: agenda_config.modo_leitura (ou erro) e quantas vezes a chave foi lida. */
function adminDaAgenda(modo: string | "erro" | "sem_tabela") {
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
            : { data: { modo_leitura: modo }, error: null },
          ),
      };
      return q;
    },
  };
}

function depsDoWebhook(modo: string, transcricao?: string) {
  const admin = adminDaAgenda(modo);
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
