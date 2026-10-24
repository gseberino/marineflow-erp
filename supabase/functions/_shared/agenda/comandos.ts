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
//   esqueci → o código LCI. <quando>: hoje, ontem, anteontem, segunda…sábado, dd/mm. <alvo>: o nome do cliente, o
//   número da OS ou "semana", até 40 caracteres, resolvido no banco (a mesma resolução da Fase 1; ambíguo = pergunta).
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
  | { comando: "desfazer"; alvo: string | null };

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

function quandoDito(s: string | undefined): string | null | undefined {
  if (s === undefined || s === "") return null;
  return QUANDO.test(s) ? s : undefined;
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
    const nome = alvo.replace(/^(?:o|a|do|da) /, "");
    return nome.replace(/ /g, "").length >= 2 ? { comando: "desfazer", alvo: nome } : null;
  }
  return null;
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
