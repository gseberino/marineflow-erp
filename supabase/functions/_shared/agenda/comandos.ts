// Agenda de Produção, Fase 1 (P6): as palavras curtas da agenda, lidas ANTES da IA — leitor puro, sem banco.
// Spec: scratchpad agenda-pesquisa/spec-fase1.md §7.2 (decisão d03 do dono: a conversa é o canal, as palavras são atalho).
//
//   agenda · a agenda · agenda da semana · agenda dessa/desta semana                       → a semana
//   minha agenda · agenda hoje · agenda de hoje · agenda pra/para hoje                     → hoje (como a my_agenda:
//                                                     o marcado, as tarefas do dia e as atrasadas, pelo título)
//   agenda amanhã · agenda de amanhã · agenda pra/para amanhã · o que tem pra/para amanhã   → amanhã
//   agenda semana que vem · agenda da semana que vem · agenda (da) próxima semana          → a semana que vem
//   livre · quando fica livre · quando fico livre · quando a gente fica livre              → quando fica livre
//   atrasado(s/as) · o que está atrasado · o que tá atrasado                               → o que passou do prazo
//   o que (eu) tenho que/pra/para/de fazer · o que tem pra/para fazer (+ "hoje" no fim)     → o que eu tenho que fazer
//   grava · gravar · grave · pode gravar · grava tudo · pode gravar tudo                   → grava o rascunho conferido
//   descarta · descartar · descarte · descarta tudo                                        → descarta o rascunho
//
// Fase 2 (P5, 24/10/2026; spec-fase2.md §11) — a conferência do dia e o que a agenda fez sozinha:
//   dia feito [quando]                                     → o dia do plano foi como estava (agenda_conferir_dia)
//   dia nao <motivo> [quando] · dia nao                    → não andou (sem motivo, o banco pede o motivo)
//   dia parcial <motivo> [quando] · dia parcial            → andou em parte
//   choveu [quando]                                        → não andou por causa da chuva (agenda_choveu)
//   desfaz · desfazer · desfaz <alvo> · desfaz (a) semana  → desfaz o que a agenda mudou sozinha (agenda_desfazer_dito:
//                                                            é a ordem exata do dono, executa direto; ambíguo = pergunta)
//   o que mudou · o que voce mudou · agenda mudancas       → agenda_ver foco mudancas
//   agenda pendencias · o que voce precisa de mim          → agenda_ver foco decisoes
//   agenda plano · plano da semana                         → agenda_ver foco plano
//   <motivo> (uma palavra): material, cliente, equipe, anterior, informacao, clima, estimativa, imprevisto, urgencia,
//   esqueci → o código LCI. <quando>: hoje, ontem, anteontem, segunda…sábado, dd/mm. <alvo>: o nome do cliente (até 3
//   palavras, sem "do/da/de" nem as palavras de outras ferramentas: "desfaz o agrupamento do ORÇ-00120", "desfaz a baixa
//   da conta de luz", "desfaz isso" vão ao modelo), o número da OS ou "semana", até 40 caracteres, resolvido no banco (a
//   mesma resolução da Fase 1; ambíguo = pergunta; o nome que não acha nada vai ao modelo).
//   Estas palavras da Fase 2 só valem com a agenda automática fora de 'desligado' (ehPalavraDaFase2).
//
// Fase 3 (P3, 24/10/2026; spec-fase3.md §11) — concluir e entregar (executam direto: agenda_concluir_dito e
// agenda_entregar_dito, pela porta; a saída e as cobranças da condição na mesma transação, desfazível):
//   concluiu · concluiu <alvo> · concluido <alvo> · concluida <alvo>      → conclui (sem alvo: a OS do plano de hoje)
//   entreguei <alvo> · entregue <alvo>                                    → marca a entrega (conclui antes se faltava)
//   O alvo segue a régua do *desfaz*: o nome do cliente (até 3 palavras, sem conectivo nem palavra de outra ferramenta:
//   "concluiu o pagamento" vai ao modelo) ou o número, nunca uma letra ("concluiu b" não é palavra). "entregue" e
//   "entreguei" sozinhos não são palavra (precisa do alvo). Também só com a agenda automática fora de 'desligado'.
//
// Fase 3 (P4, 24/10/2026; spec-fase3.md §11) — a diária que a agenda lançou ou perguntou (agenda_diaria_dita):
//   diaria <nome> inteira|meia|nao [quando] · diaria <nome> dia inteiro [quando] · diaria do/da <nome> …
//   → responde a pergunta da diária aberta, ou corrige (meia/inteira) / apaga (não) a que a agenda lançou; sem nada da
//   agenda, o banco diz nao_achei e o turno segue ao modelo (o registrar_diaria de sempre). O nome é de 1 ou 2 palavras
//   (sem conectivo nem letra solta). Só com a diária automática (agenda_config.modo_diaria) fora de 'desligado'
//   (ehPalavraDaDiaria). "lança a diária do João", "registra a diária do Roberto" e "o João trabalhou meio dia" NÃO são
//   palavra (vão ao modelo e ao registrar_diaria); a agenda não usa "corrige" ("corrigir …" é dos comprovantes).
//
// Só a frase inteira vale (normalizada pelo MESMO normalizarComando do secretário: sem acento, sem negrito, sem
// pontuação no fim, sem o 🎤 do áudio). Qualquer palavra a mais é conversa e vai ao modelo como sempre.
//
// NÃO PODE COLIDIR (provado em comandos_test.ts):
//   · a confirmação do assistente (whatsapp-channel.ts: sim/s/ok/confirmar/1 · não/nao/n/cancelar/2): nenhum comando
//     começa por elas, e nenhum da tabela fixa é número;
//   · o secretário (_shared/secretario/comandos.ts): nenhum comando é letra, nenhum é lido por ele, e nada do que ele lê
//     é lido aqui ("tudo" é dele; "grava tudo" é daqui; "<letra> feito" e "volta X" são dele, "dia feito" e "desfaz X"
//     são daqui; "desfaz <letra>" — "desfaz B", "desfaz a", "desfaz o item C" — é dele: aqui o alvo nunca é uma letra);
//   · os comprovantes (comprovantes/respostas.ts, lerComando) e o registro de pergunta ativa (whatsapp/pergunta-ativa.ts).
//     Exceção conhecida: "grava", "grave" e "pode gravar" já são um "sim" para lerSimNao (o "sim" do CMP). Com a agenda
//     ligada o webhook marca o texto como comando (quemResponde → assistente, como os do secretário), e citar a pergunta
//     do CMP continua mandando ao CMP. O CMP pede "*sim*"; a agenda pede "*grava*".

import { normalizarComando } from "../secretario/comandos.ts";

export type PeriodoDoComando = "semana" | "hoje" | "amanha" | "proxima_semana";
export type FocoDoComando = "tudo" | "livre" | "atrasos" | "o_que_fazer" | "mudancas" | "decisoes" | "plano";
export type ResultadoDoDia = "cumprido" | "parcial" | "nao_cumprido";

export type ComandoDaAgenda =
  /** agenda_ver com o período, o foco e a pessoa ("eu" no "o que eu tenho que fazer") */
  | { comando: "ver"; periodo: PeriodoDoComando | null; foco: FocoDoComando; pessoa: "eu" | null }
  /** agenda_rascunho_gravar: o rascunho que o dono conferiu vira fato */
  | { comando: "gravar" }
  /** agenda_rascunho_descartar */
  | { comando: "descartar" }
  /** (Fase 2) agenda_conferir_dia: o dia do plano foi feito, não andou ou andou em parte (motivo = o código LCI) */
  | { comando: "dia"; resultado: ResultadoDoDia; motivo: string | null; quando: string | null }
  /** (Fase 2) agenda_choveu */
  | { comando: "choveu"; quando: string | null }
  /** (Fase 2) agenda_desfazer_dito: o alvo como o dono disse (null = o que a agenda contou por último) */
  | { comando: "desfazer"; alvo: string | null }
  /** (Fase 3) agenda_concluir_dito: o alvo como o dono disse (null = a OS do plano de hoje, se for uma só) */
  | { comando: "concluir"; alvo: string | null }
  /** (Fase 3) agenda_entregar_dito: o alvo como o dono disse */
  | { comando: "entregar"; alvo: string }
  /** (Fase 3, P4) agenda_diaria_dita: a pessoa como o dono disse, a jornada e o dia (null = o da pergunta ou hoje) */
  | { comando: "diaria"; nome: string; jornada: JornadaDita; quando: string | null };

/** A jornada da palavra *diária*: inteira (também "dia inteiro"), meia ou não (não lançar / apagar). */
export type JornadaDita = "inteira" | "meia" | "nao";

const ver = (periodo: PeriodoDoComando | null, foco: FocoDoComando = "tudo", pessoa: "eu" | null = null): ComandoDaAgenda =>
  ({ comando: "ver", periodo, foco, pessoa });

/** A frase inteira (normalizada) → o comando. Montada uma vez; a ordem não importa (só igualdade). */
const FRASES = new Map<string, ComandoDaAgenda>();

function frases(lista: string[], cmd: ComandoDaAgenda): void {
  for (const f of lista) FRASES.set(f, cmd);
}

frases(["agenda", "a agenda", "agenda da semana", "agenda dessa semana", "agenda desta semana"], ver("semana"));
// "minha agenda" era a my_agenda (o dia: tarefas atrasadas, as do dia e os compromissos): vai ao dia, não à semana.
frases(["minha agenda", "agenda hoje", "agenda de hoje", "agenda pra hoje", "agenda para hoje"], ver("hoje"));
frases(
  ["agenda amanha", "agenda de amanha", "agenda pra amanha", "agenda para amanha", "o que tem pra amanha", "o que tem para amanha"],
  ver("amanha"),
);
frases(
  ["agenda semana que vem", "agenda da semana que vem", "agenda proxima semana", "agenda da proxima semana"],
  ver("proxima_semana"),
);
frases(["livre", "quando fica livre", "quando fico livre", "quando a gente fica livre"], ver(null, "livre"));
frases(
  ["atrasado", "atrasados", "atrasadas", "o que esta atrasado", "o que ta atrasado"],
  ver(null, "atrasos"),
);
// "o que eu tenho que fazer" e as variações (com ou sem "eu"; que / pra / para / de), com ou sem "hoje" no fim
for (const eu of ["o que eu tenho", "o que tenho"]) {
  for (const liga of ["que", "pra", "para", "de"]) {
    frases([`${eu} ${liga} fazer`, `${eu} ${liga} fazer hoje`], ver(null, "o_que_fazer", "eu"));
  }
}
frases(["o que tem pra fazer", "o que tem para fazer", "o que tem pra fazer hoje", "o que tem para fazer hoje"], ver(null, "o_que_fazer", "eu"));
frases(["grava", "gravar", "grave", "pode gravar", "grava tudo", "pode gravar tudo"], { comando: "gravar" });
frases(["descarta", "descartar", "descarte", "descarta tudo"], { comando: "descartar" });
// Fase 2: o que a agenda fez sozinha, o que ela precisa do dono e o plano publicado
frases(["o que mudou", "o que voce mudou", "agenda mudancas", "agenda mudou"], ver(null, "mudancas"));
frases(["agenda pendencias", "o que voce precisa de mim"], ver(null, "decisoes"));
frases(["agenda plano", "plano da semana"], ver(null, "plano"));

/** A maior frase da tabela: texto maior do que isto nunca é comando da tabela (custo zero na conversa comum). */
const MAIOR = Math.max(...[...FRASES.keys()].map((f) => f.length));

/** Todas as frases fixas (normalizadas) que viram comando — para os testes de colisão. */
export function frasesDaAgenda(): string[] {
  return [...FRASES.keys()];
}

// ─── Fase 2: as palavras com complemento (dia feito, dia não + motivo, choveu, desfaz) ─────────────────────

/** A palavra do motivo (uma, sem acento) → o código LCI de agenda_alocacoes.motivo (o banco aceita os dois). */
export const MOTIVOS_DO_DIA: Readonly<Record<string, string>> = Object.freeze({
  material: "material",
  cliente: "cliente_ou_bem",
  equipe: "equipe_faltou",
  anterior: "trabalho_anterior",
  informacao: "informacao",
  clima: "clima",
  estimativa: "estimativa",
  imprevisto: "imprevisto_tecnico",
  urgencia: "urgencia_outra_os",
  esqueci: "esqueci",
});

/** "hoje", "ontem", "anteontem", "segunda" (ou "segunda feira"), …, "sabado", "dd/mm". O banco resolve a data. */
const QUANDO = /^(?:hoje|ontem|anteontem|(?:segunda|terca|quarta|quinta|sexta)(?: feira)?|sabado|\d{1,2}\/\d{1,2})$/;

/** O alvo do *desfaz*: até 40 caracteres, nunca uma letra (com ou sem "o/a", "item", "letra"): "desfaz B" é do secretário. */
const ALVO_MAX = 40;
const ALVO_DE_LETRA = /^(?:(?:o|a) )?(?:(?:item|letra) )?[a-z]$/;
/**
 * O alvo é uma OS (o nome do cliente, até 3 palavras, ou o número): o que o prompt ensina para outras ferramentas
 * ("desfaz o agrupamento do ORÇ-00120" é desagrupar_orcamento; "desfaz a baixa da conta de luz" é estornar_pagamento;
 * "desfaz o último lançamento", "desfaz o pix do Roberto") e o "desfaz isso" sem dizer de quê vão ao modelo. Por isso o
 * alvo não tem conectivo ("do", "da", "de"…) nem estas palavras.
 */
const ALVO_MAX_PALAVRAS = 3;
const CONECTIVOS_DO_ALVO = new Set(["de", "do", "da", "dos", "das", "no", "na", "nos", "nas", "em", "pra", "para", "com", "por", "que"]);
const NAO_E_ALVO = new Set([
  "isso", "isto", "aquilo", "tudo", "ai", "agrupamento", "agrupar", "baixa", "pix", "pagamento", "pagamentos", "lancamento",
  "lancamentos", "estorno", "envio", "conta", "contas", "cobranca", "nota", "compra", "pedido", "orcamento", "item", "tarefa",
  "lembrete", "despesa", "recebimento", "transferencia", "mensagem", "diaria",
]);

/** O nome do alvo (já sem "o/a/do/da") serve? Até 3 palavras, sem conectivo e sem as palavras de outras ferramentas. */
function alvoDeOs(nome: string): boolean {
  const palavras = nome.split(" ").filter(Boolean);
  if (palavras.length === 0 || palavras.length > ALVO_MAX_PALAVRAS) return false;
  if (palavras.some((p) => CONECTIVOS_DO_ALVO.has(p) || NAO_E_ALVO.has(p))) return false;
  return nome.replace(/ /g, "").length >= 2;
}

function quandoDito(s: string | undefined): string | null | undefined {
  if (s === undefined || s === "") return null;
  return QUANDO.test(s) ? s : undefined;
}

/**
 * O alvo de *desfaz*, *concluiu* e *entreguei*: até 40 caracteres, nunca uma letra; "o/a/do/da" na frente sai; o nome
 * passa pela régua de alvoDeOs. undefined = não serve (a frase vai ao modelo).
 */
function alvoDito(alvo: string): string | undefined {
  if (alvo.length > ALVO_MAX || ALVO_DE_LETRA.test(alvo)) return undefined;
  const nome = alvo.replace(/^(?:o|a|do|da) /, "");
  return alvoDeOs(nome) ? nome : undefined;
}

/** "dia feito [quando]", "dia nao|parcial [motivo] [quando]", "choveu [quando]", "desfaz [alvo]" → o comando, ou null. */
function lerPalavraComplemento(t: string): ComandoDaAgenda | null {
  let m = /^dia feito(?: (.+))?$/.exec(t);
  if (m) {
    const quando = quandoDito(m[1]);
    return quando === undefined ? null : { comando: "dia", resultado: "cumprido", motivo: null, quando };
  }
  m = /^dia (nao|parcial)(?: ([a-z]+))?(?: (.+))?$/.exec(t);
  if (m) {
    const resultado: ResultadoDoDia = m[1] === "nao" ? "nao_cumprido" : "parcial";
    let motivo: string | null = null;
    let resto = m[3];
    if (m[2] !== undefined) {
      if (MOTIVOS_DO_DIA[m[2]]) {
        motivo = MOTIVOS_DO_DIA[m[2]];
      } else {
        // sem motivo, mas com o dia ("dia nao ontem", "dia parcial segunda feira"): o banco pede o motivo do dia dito
        const comoDia = [m[2], m[3]].filter((x) => x !== undefined).join(" ");
        if (!QUANDO.test(comoDia)) return null;
        resto = comoDia;
      }
    }
    const quando = quandoDito(resto);
    return quando === undefined ? null : { comando: "dia", resultado, motivo, quando };
  }
  m = /^choveu(?: (.+))?$/.exec(t);
  if (m) {
    const quando = quandoDito(m[1]);
    return quando === undefined ? null : { comando: "choveu", quando };
  }
  m = /^(?:desfaz|desfazer|desfaca)(?: (.+))?$/.exec(t);
  if (m) {
    const alvo = (m[1] ?? "").trim();
    if (!alvo) return { comando: "desfazer", alvo: null };
    if (alvo.length > ALVO_MAX || ALVO_DE_LETRA.test(alvo)) return null;
    // "desfaz a semana", "desfaz semana" → "semana"; "desfaz o Nelson" → "nelson" (o banco resolve o nome)
    if (/^(?:a |da )?semana$/.test(alvo)) return { comando: "desfazer", alvo: "semana" };
    const nome = alvoDito(alvo);
    return nome === undefined ? null : { comando: "desfazer", alvo: nome };
  }
  // Fase 3: concluir (sem alvo só "concluiu") e entregar (sempre com alvo)
  m = /^(concluiu|concluido|concluida)(?: (.+))?$/.exec(t);
  if (m) {
    const alvo = (m[2] ?? "").trim();
    if (!alvo) return m[1] === "concluiu" ? { comando: "concluir", alvo: null } : null;
    const nome = alvoDito(alvo);
    return nome === undefined ? null : { comando: "concluir", alvo: nome };
  }
  m = /^(?:entreguei|entregue) (.+)$/.exec(t);
  if (m) {
    const nome = alvoDito(m[1].trim());
    return nome === undefined ? null : { comando: "entregar", alvo: nome };
  }
  // Fase 3 (P4): *diária <nome> inteira|meia|não [quando]* (também "dia inteiro" e "diária do/da <nome> …")
  m = /^diaria (.+?) (inteira|meia|nao|dia inteiro)(?: (.+))?$/.exec(t);
  if (m) {
    const nome = pessoaDita(m[1]);
    const quando = quandoDito(m[3]);
    if (nome === undefined || quando === undefined) return null;
    const jornada: JornadaDita = m[2] === "meia" ? "meia" : m[2] === "nao" ? "nao" : "inteira";
    return { comando: "diaria", nome, jornada, quando };
  }
  return null;
}

/**
 * A pessoa da palavra *diária*: "do/da/de" na frente sai; 1 ou 2 palavras de letras, cada uma com 2+ letras, sem conectivo
 * nem palavra de outra ferramenta ("diária do pix meia" vai ao modelo). undefined = não serve.
 */
function pessoaDita(dito: string): string | undefined {
  const nome = dito.trim().replace(/^(?:do|da|de) /, "");
  const palavras = nome.split(" ").filter(Boolean);
  if (palavras.length === 0 || palavras.length > 2) return undefined;
  if (palavras.some((p) => p.length < 2 || !/^[a-z]+$/.test(p) || CONECTIVOS_DO_ALVO.has(p) || NAO_E_ALVO.has(p))) return undefined;
  return palavras.join(" ");
}

/**
 * (Fase 3, P4) A palavra da diária automática: só vale com agenda_config.modo_diaria fora de 'desligado' (antes disso não
 * há diária da agenda para responder nem corrigir, e "diária …" é do registrar_diaria pelo modelo).
 */
export function ehPalavraDaDiaria(cmd: ComandoDaAgenda): boolean {
  return cmd.comando === "diaria";
}

/**
 * (Fase 2) As palavras da agenda que se monta sozinha: a conferência do dia, o *choveu*, o *desfaz* e os focos novos
 * ("o que mudou", "agenda pendências", "agenda plano"). Só valem com a agenda automática (modo_proposta ou modo_vigia)
 * fora de 'desligado': antes disso não há plano nem mudança dela, e "desfaz …" é de outras ferramentas.
 * (Fase 3) *concluiu* e *entreguei* também (spec-fase3 §11: "lida com modo_proposta ou modo_vigia ≠ desligado").
 */
export function ehPalavraDaFase2(cmd: ComandoDaAgenda): boolean {
  if (cmd.comando === "dia" || cmd.comando === "choveu" || cmd.comando === "desfazer") return true;
  if (cmd.comando === "concluir" || cmd.comando === "entregar") return true;
  return cmd.comando === "ver" && (cmd.foco === "mudancas" || cmd.foco === "decisoes" || cmd.foco === "plano");
}

/** O comando, ou null (não é comando: segue para o assistente como sempre). */
export function lerComandoDaAgenda(texto: string): ComandoDaAgenda | null {
  if (typeof texto !== "string" || texto.length > 200) return null;
  const t = normalizarComando(texto);
  if (!t) return null;
  if (t.length <= MAIOR) {
    const cmd = FRASES.get(t);
    // cópia: quem chama não muda a tabela
    if (cmd) return { ...cmd };
  }
  // Fase 2: as palavras com complemento (curtas: "desfaz" + até 40 caracteres é a maior)
  if (t.length > ALVO_MAX + 12) return null;
  return lerPalavraComplemento(t);
}
