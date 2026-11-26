// Regras do vigia acompanhar-conversas (06/10/2026) — puras, para testar sem banco.
// plans/marineflow-acompanhar-conversa.md
import { dentroDaJanela } from "./promessa.ts";
import { MARCA_DO_VIGIA } from "./texto-de-fora.ts";
import { MOTIVO_CONTATO_ENCERROU } from "../whatsapp/contato-encerrou.ts";
import { depoisDaJanelaDaManha } from "../uma-voz/janela.ts";

const BRASILIA_MS = 3 * 60 * 60 * 1000;
export const AVISOS_POR_DIA = 3;
/** Até quantos dias para trás uma mensagem do contato pode encerrar o acompanhamento. */
export const DIAS_DO_ENCERRAMENTO = 7;

export interface Acompanhamento {
  id: string;
  phone_normalized: string;
  contato: string | null;
  modo: "acompanhar" | "lembrar_em" | "promessa";
  intervalo_min: number;
  ate: string;
  lembrar_em: string | null;
  promessa: string | null;
  ultimo_aviso_em: string | null;
  avisos_dia: string | null;
  avisos_no_dia: number;
  created_at: string;
}

export interface EstadoDaConversa {
  ultimaRecebida: { em: string; texto: string } | null;
  ultimaEnviadaEm: string | null;
  /**
   * O contato disse, nas últimas recebidas desde janelaDoEncerramento, que fechou com outra empresa
   * ou desistiu (conversaEncerradaPeloContato, regra de palavras sem IA).
   */
  encerrouPeloContato?: boolean;
}

/**
 * Desde quando (ISO) as recebidas contam para "o contato encerrou": os últimos 7 dias, mas nunca
 * antes do acompanhamento nascer — se o dono pediu para acompanhar DEPOIS de o contato dizer que
 * fechou com outra, o pedido dele vale.
 */
export function janelaDoEncerramento(a: Pick<Acompanhamento, "created_at">, agora: Date): string {
  const seteDias = agora.getTime() - DIAS_DO_ENCERRAMENTO * 86_400_000;
  const criado = Date.parse(a.created_at);
  return new Date(Number.isNaN(criado) ? seteDias : Math.max(seteDias, criado)).toISOString();
}

/** O dia em Brasília (AAAA-MM-DD) — o teto de avisos é por dia local. */
export function diaEmBrasilia(agora: Date): string {
  return new Date(agora.getTime() - BRASILIA_MS).toISOString().slice(0, 10);
}

/** Horário de avisar o dono: 8h–20h de Brasília, seg–sáb (o mesmo de dentroDaJanela). */
export function horaDeAvisar(agora: Date): boolean {
  return dentroDaJanela(agora.getTime()) === agora.getTime();
}

/**
 * Janela da manhã (secretário, Passo 4, 15/10/2026): das 07:30 às 09:30 só a manhã pergunta. O aviso de
 * acompanhamento e o lembrete de promessa saem a partir das 09:30 (o que ficar devido espera a rodada
 * das 09:30; nada se perde: a decisão é pelo estado da conversa). O lembrete que o dono pediu com hora
 * ("me lembra às 8h", modo lembrar_em) é o alarme dele: continua das 8h às 20h.
 * Medido (02–15/10): 4 avisos às 08:00 e 1 às 09:30, todos em cima da manhã.
 */
export function podeAvisarNoModo(modo: Acompanhamento["modo"], agora: Date): boolean {
  if (!horaDeAvisar(agora)) return false;
  return modo === "lembrar_em" || depoisDaJanelaDaManha(agora);
}

/** Avisos sobre a MESMA mensagem do contato antes do freio parar (P4.3). */
export const AVISOS_POR_MENSAGEM = 2;
export const MOTIVO_FREIO = "freio";

/**
 * O freio do acompanhamento (secretário, Passo 4, P4.3, 15/10/2026): no máximo `limite` avisos sobre a
 * mesma mensagem do contato. Depois disso o acompanhamento ESPERA (não encerra): quando o contato
 * escrever de novo, a mensagem é outra, a conta zera e o aviso volta. Vale só para o modo acompanhar
 * (lembrete pedido e promessa avisam uma vez). `avisosDestaMensagem` null = não deu para contar: avisa
 * (melhor um aviso a mais que calar por erro de leitura).
 * Caso Miguel (07–10/10): 7 dos 11 avisos repetiam a mesma última mensagem dele.
 */
export function aplicarFreio(
  d: Decisao,
  a: Pick<Acompanhamento, "modo">,
  avisosDestaMensagem: number | null,
  limite = AVISOS_POR_MENSAGEM,
): Decisao {
  if (d.acao !== "avisar" || a.modo !== "acompanhar" || avisosDestaMensagem === null) return d;
  return avisosDestaMensagem >= limite ? { acao: "esperar", motivo: MOTIVO_FREIO } : d;
}

/** A conversa está esperando resposta da HBR: a última mensagem é do contato. */
export function esperandoResposta(c: EstadoDaConversa): boolean {
  if (!c.ultimaRecebida) return false;
  return !c.ultimaEnviadaEm || Date.parse(c.ultimaRecebida.em) > Date.parse(c.ultimaEnviadaEm);
}

export type Decisao = { acao: "avisar" } | { acao: "encerrar"; motivo: string } | { acao: "esperar"; motivo?: string };

/** O que fazer com um acompanhamento agora. */
export function decidir(a: Acompanhamento, c: EstadoDaConversa, agora: Date): Decisao {
  const t = agora.getTime();
  // Primeiro de tudo, em qualquer modo: quem fechou com outra empresa ou desistiu não espera
  // resposta nem promessa. Caso Miguel (07/10/2026): 7 avisos depois de ele dizer que fechou.
  if (c.encerrouPeloContato) return { acao: "encerrar", motivo: MOTIVO_CONTATO_ENCERROU };
  if (a.modo === "lembrar_em" || a.modo === "promessa") {
    return a.lembrar_em && Date.parse(a.lembrar_em) <= t ? { acao: "avisar" } : { acao: "esperar" };
  }
  if (Date.parse(a.ate) <= t) return { acao: "encerrar", motivo: "prazo" };
  if (!esperandoResposta(c)) return { acao: "esperar" };
  const intervalo = a.intervalo_min * 60_000;
  if (t - Date.parse(c.ultimaRecebida!.em) < intervalo) return { acao: "esperar" };
  // Desde o último aviso: ou passou o intervalo, ou chegou mensagem nova dele depois do aviso.
  if (a.ultimo_aviso_em && t - Date.parse(a.ultimo_aviso_em) < intervalo) return { acao: "esperar" };
  const hoje = diaEmBrasilia(agora);
  if (a.avisos_dia === hoje && a.avisos_no_dia >= AVISOS_POR_DIA) return { acao: "esperar" };
  return { acao: "avisar" };
}

/** "3h", "45 min", "2 dias" — quanto tempo ele espera. */
export function tempoEsperando(desde: string, agora: Date): string {
  const min = Math.max(0, Math.round((agora.getTime() - Date.parse(desde)) / 60_000));
  if (min < 60) return `${min} min`;
  const h = Math.round(min / 60);
  if (h < 48) return `${h}h`;
  return `${Math.round(h / 24)} dias`;
}

function curto(t: string, n = 300): string {
  const s = t.replace(/\s+/g, " ").trim();
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

/**
 * O pedido que o vigia faz ao assistente, como se fosse o dono — o assistente lê a conversa, sugere
 * a resposta e chama send_whatsapp_message (a confirmação que o dono recebe). A marca 🤖 no começo
 * deixa claro, no histórico, que não foi o dono que escreveu.
 */
export function textoDoAviso(a: Acompanhamento, c: EstadoDaConversa, agora: Date, telefoneLegivel: string): string {
  const quem = `${a.contato || "o contato"} (${telefoneLegivel})`;
  const ler = `Leia a conversa com get_whatsapp_conversation (phone ${a.phone_normalized}, poucos dias)`;
  const sugerir = `sugira a resposta chamando send_whatsapp_message com to_phone ${a.phone_normalized} — a confirmação vai para mim. Se não houver o que responder, diga isso em uma linha.`;
  if (a.modo === "promessa") {
    return `🤖 Lembrete de promessa (detectado numa mensagem sua): você escreveu a ${quem}: "${curto(a.promessa ?? "")}". ` +
      `${ler} e veja se já foi cumprido. Se já foi, diga em uma linha. Se não, diga em uma linha o que falta e, se couber, ${sugerir}`;
  }
  const ultima = c.ultimaRecebida
    ? ` Última mensagem dele, há ${tempoEsperando(c.ultimaRecebida.em, agora)}: "${curto(c.ultimaRecebida.texto)}".`
    : "";
  const abertura = a.modo === "lembrar_em"
    ? `🤖 Lembrete que você pediu: responder ${quem}.`
    : `🤖 Acompanhamento (pedido seu): ${quem} está esperando resposta.`;
  return `${abertura}${ultima} ${ler}, me diga em uma linha o que ele quer e ${sugerir}`;
}

// ═══ O ASSISTENTE QUE NÃO PODE ATENDER O PEDIDO DO VIGIA (revisão da leva B do pacote 1, 25/11/2026) ═══
//
// O pedido do vigia chega ao ai-agent pelo mesmo caminho de uma mensagem do dono, mas o dono não mandou nada. Com o
// Claude da assinatura fora e a reserva desligada, o ai-agent respondia a esse pedido como responde ao dono ("⚠️ Não
// consegui responder: o PC da oficina está sem sinal… Confira o PC e mande de novo.") e devolvia HTTP 200. O vigia lia o
// 200 como "aviso dado": o lembrete com hora e o de promessa eram ENCERRADOS, e o dono ficava com um "mande de novo"
// sem saber do quê. Com N lembretes vencidos na rodada, N avisos iguais.
//
// As três pontas do combinado moram aqui, para não se desencontrarem:
//   · ORIGEM_DO_VIGIA: o vigia diz, no pedido, que o turno é dele (`origem`);
//   · turnoAbertoPeloVigia: o ai-agent reconhece o pedido do vigia e, se não puder atender, não manda nada ao dono e
//     não grava nada na conversa; devolve `calado: true` (fica o registro em app_error_logs);
//   · assistenteCalou: o vigia lê `calado: true` e NÃO marca o aviso como dado. O lembrete volta na rodada seguinte.
// As duas funções podem ser publicadas em qualquer ordem. O ai-agent só se cala para quem mandou a origem (o vigia que
// já sabe ler o `calado`), e o vigia só reabre com `calado: true`. Uma ponta nova com a outra velha = como antes: o
// aviso sai e conta como dado. A frase para quem não é o titular da assinatura também segue como antes.

/** O que o vigia das conversas põe em `origem`, no pedido ao ai-agent: "este turno é meu, não do dono". */
export const ORIGEM_DO_VIGIA = "acompanhar-conversas";

/**
 * O turno foi aberto pelo vigia das conversas, e não por uma mensagem do dono? (pura) São duas condições juntas: o
 * pedido diz que veio do vigia (`origem`, que só ele manda; o pedido é autenticado pelo segredo interno) E o texto
 * começa com a marca do vigia (🤖, a de textoDoAviso). A mensagem que o dono escreve chega pelo webhook, sem origem:
 * se ele mesmo começar uma mensagem com 🤖, ela continua sendo dele, e a falha é dita a ele como sempre.
 */
export function turnoAbertoPeloVigia(origem: unknown, texto: unknown): boolean {
  return origem === ORIGEM_DO_VIGIA && typeof texto === "string" && texto.trimStart().startsWith(MARCA_DO_VIGIA);
}

/**
 * A resposta do ai-agent diz que ele não pôde atender o pedido do vigia e não mandou nada ao dono? (pura)
 * Só o `calado: true` exato vale: corpo ilegível, resposta comum ou aviso que saiu = false (o aviso conta como dado).
 */
export function assistenteCalou(corpo: unknown): boolean {
  return !!corpo && typeof corpo === "object" && !Array.isArray(corpo) && (corpo as Record<string, unknown>).calado === true;
}
