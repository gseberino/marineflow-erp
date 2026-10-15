// Uma voz só (secretário, Passo 4, 15/10/2026): o que cada fonte pede ao portão — chave, assunto e
// destino —, puro e testável. A tabela da spec (§2) em código.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md (§2, §3.1, §4)
//
// Destinos: acorde (até 2 por dia, 08–20h) · proxima_fixa (manhã ou fechamento, o que vier antes) ·
// hoje (linha "Hoje" da manhã) · escritorio (linha do escritório no fechamento) · deixar (fica como está:
// pedido do dono, mensagem fixa própria) · acaba (uma mensagem fixa já leva).
// Assunto: o que conta como "o mesmo assunto" para o acorde (um por dia). Todo aviso de sistema
// (WhatsApp que voltou, manhã que não chegou) é o assunto "sistema": a queda que derrubou a manhã e a
// volta do WhatsApp são um acorde só.

import type { Acompanhamento } from "../ai/acompanhar.ts";
import { segundaDaSemana } from "./janela.ts";
import type { AvisoDaFonte, RegrasDaVozUnica } from "./portao.ts";

// ── vigia do negócio (ai-business-monitor) ──────────────────────────────────────────────────────

export type SinalDoVigia =
  | "vence_hoje"
  | "orcamentos_parados"
  | "saldo_divergente"
  | "estoque_divergente"
  | "cota_fiscal"
  | "nfe_rejeitada";

/** O destino de cada sinal do vigia (spec §2): o que a manhã já mostra acaba; papelada vai ao escritório. */
export const DESTINO_DO_VIGIA: Readonly<Record<SinalDoVigia, AvisoDaFonte["destino"]>> = Object.freeze({
  // a manhã já tem a linha "Hoje" com o que vence (secretario-texto.ts)
  vence_hoje: "acaba",
  // a manhã lista os orçamentos parados e a revisão de segunda os retoma
  orcamentos_parados: "acaba",
  saldo_divergente: "escritorio",
  estoque_divergente: "escritorio",
  cota_fiscal: "escritorio",
  // P4.2 troca a contagem por dia por um aviso por nota (chave nfe:<id>)
  nfe_rejeitada: "acorde",
});

/** Um sinal do vigia. `ref` distingue sinais do mesmo tipo no dia (a conexão do banco do saldo). */
export function avisoDoVigia(sinal: SinalDoVigia, dia: string, texto: string, ref?: string): AvisoDaFonte {
  const sufixo = ref ? `${ref}:${dia}` : dia;
  return {
    fonte: "vigia_negocio",
    chave: `${sinal}:${sufixo}`,
    assunto: sinal === "nfe_rejeitada" ? "fiscal:nfe_rejeitada" : `${sinal}${ref ? `:${ref}` : ""}`,
    destino: DESTINO_DO_VIGIA[sinal],
    texto,
    dados: { sinal, ...(ref ? { ref } : {}) },
  };
}

/** Certificado A1: ≤ 7 dias acorda (uma vez por validade); 8–30 dias vai na linha "Hoje" uma vez por semana. */
export function avisoDoCertificado(validade: string, dias: number, dia: string, texto: string): AvisoDaFonte {
  if (dias <= 7) {
    return { fonte: "vigia_negocio", chave: `cert:${validade}:7d`, assunto: `fiscal:cert:${validade}`, destino: "acorde", texto, dados: { dias, validade } };
  }
  return {
    fonte: "vigia_negocio", chave: `cert:${validade}:${segundaDaSemana(dia)}`, assunto: `fiscal:cert:${validade}`,
    destino: "hoje", texto, dados: { dias, validade },
  };
}

/** Consentimento do banco: ≤ 7 dias na linha "Hoje" (todo dia); 8–30 dias no escritório (uma vez por semana). */
export function avisoDoConsentimento(conexao: string, dias: number, dia: string, texto: string): AvisoDaFonte {
  if (dias <= 7) {
    return { fonte: "vigia_negocio", chave: `consent:${conexao}:${dia}`, assunto: `banco:consent:${conexao}`, destino: "hoje", texto, dados: { dias } };
  }
  return {
    fonte: "vigia_negocio", chave: `consent:${conexao}:${segundaDaSemana(dia)}`, assunto: `banco:consent:${conexao}`,
    destino: "escritorio", texto, dados: { dias },
  };
}

/** A manhã que não chegou (WhatsApp fora do ar): acorde de sistema, um por dia. */
export function avisoResumoNaoChegou(dia: string, texto: string): AvisoDaFonte {
  return { fonte: "vigia_negocio", chave: `sistema:resumo_nao_chegou:${dia}`, assunto: "sistema", destino: "acorde", texto };
}

// ── saldos a cobrar (balance-reminders) ─────────────────────────────────────────────────────────

/** O resumo de saldos das 08:30 acaba: a manhã cobre (cobrança grande, marcos), 30 dias vai à revisão. */
export function avisoDosSaldos(dia: string, itens: number, texto: string): AvisoDaFonte {
  return { fonte: "saldos", chave: `saldos:${dia}`, assunto: "saldos", destino: "acaba", texto, dados: { itens } };
}

// ── e-mail urgente (email-imap) ────────────────────────────────────────────────────────────────

/** Golpe: acorda uma vez por remetente, para sempre. Urgente sem golpe: D1 (padrão: próxima fixa). */
export function avisoDoEmail(
  e: { emailId: string; endereco: string; fraude: boolean },
  regras: Pick<RegrasDaVozUnica, "email_sem_golpe">,
  texto: string,
): AvisoDaFonte {
  const endereco = (e.endereco || "").trim().toLowerCase() || "sem_remetente";
  if (e.fraude) {
    return { fonte: "email", chave: `golpe:${endereco}`, assunto: `golpe:${endereco}`, destino: "acorde", texto, referencia: `email:${e.emailId}` };
  }
  return {
    fonte: "email", chave: `email:${e.emailId}`, assunto: `email:${endereco}`, destino: regras.email_sem_golpe, texto,
    referencia: `email:${e.emailId}`,
  };
}

// ── lead do formulário do site (whatsapp-webhook) ──────────────────────────────────────────────

/** Sem acento, minúsculo. */
function semAcento(t: string): string {
  return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

/** O lead pede para hoje ou com urgência ("hoje", "urgente", "o quanto antes", "agora"). */
export function pedeHojeOuUrgente(texto: string | null | undefined): boolean {
  if (!texto) return false;
  return /\b(hoje|urgente|urgencia|o quanto antes|com pressa|agora mesmo|imediato)\b/.test(semAcento(texto));
}

/** Lead do site: D6 (padrão: próxima fixa), salvo se pedir hoje/urgente (acorda). Um por telefone e dia. */
export function avisoDoLeadDoSite(
  l: { phone: string; dia: string; mensagem: string | null },
  regras: Pick<RegrasDaVozUnica, "lead_site">,
  texto: string,
): AvisoDaFonte {
  const urgente = pedeHojeOuUrgente(l.mensagem);
  return {
    fonte: "lead_site", chave: `lead_site:${l.phone}:${l.dia}`, assunto: `contato:${l.phone}`,
    destino: urgente ? "acorde" : regras.lead_site, texto, dados: { urgente },
  };
}

// ── conexão do WhatsApp (whatsapp-conexao) ─────────────────────────────────────────────────────

/** Minutos fora do ar a partir dos quais a volta acorda o dono (§3.1-d). */
export const QUEDA_QUE_ACORDA_MIN = 30;

/** A volta do WhatsApp: a queda de 30 min ou mais acorda (assunto "sistema"); a curta acaba (fica no sino). */
export function avisoDaVoltaDoWhatsApp(queda: { desde: string; ate: string }, texto: string): AvisoDaFonte {
  const min = Math.max(0, Math.round((Date.parse(queda.ate) - Date.parse(queda.desde)) / 60_000));
  return {
    fonte: "conexao", chave: `sistema:whatsapp:${queda.desde}`, assunto: "sistema",
    destino: min >= QUEDA_QUE_ACORDA_MIN ? "acorde" : "acaba", texto, dados: { minutos_fora: min, desde: queda.desde, ate: queda.ate },
  };
}

// ── lembretes de revisão (lembretes-de-revisao) ────────────────────────────────────────────────

/** A rodada das 09:35 (ter–qui) é a sua própria mensagem fixa: fica como está. */
export function avisoDosLembretesDeRevisao(dia: string, propostas: number, texto: string): AvisoDaFonte {
  return { fonte: "lembretes_revisao", chave: `lembretes_revisao:${dia}`, assunto: "lembretes_revisao", destino: "deixar", texto, dados: { propostas } };
}

// ── acompanhamento, promessa e lembrete pedido (acompanhar-conversas) ──────────────────────────

/** A referência do freio: o acompanhamento e a última mensagem do contato que o aviso cobre. */
export function referenciaDoAcompanhamento(id: string, ultimaRecebidaEm: string | null): string {
  return `acomp:${id}:${ultimaRecebidaEm ?? "sem_mensagem"}`;
}

/**
 * O aviso do acompanhar-conversas:
 *   acompanhar  → acorde (D3: conta no limite; com acompanhar_conta_no_limite=false, deixar), assunto o contato;
 *   promessa    → D5 (padrão: próxima fixa: a manhã/o fechamento mostram a promessa ainda aberta);
 *   lembrar_em  → deixar: é o alarme do próprio dono ("me lembra às 15h"), fora do limite e da janela.
 * `n` = o número deste aviso sobre a mesma mensagem do contato (1, 2…): entra na chave.
 */
export function avisoDoAcompanhamento(
  a: Pick<Acompanhamento, "id" | "phone_normalized" | "modo">,
  ultimaRecebidaEm: string | null,
  n: number,
  regras: Pick<RegrasDaVozUnica, "acompanhar_conta_no_limite" | "promessa">,
  texto: string,
): AvisoDaFonte {
  const assunto = `contato:${a.phone_normalized}`;
  if (a.modo === "promessa") {
    return { fonte: "promessa", chave: `promessa:${a.id}`, assunto, destino: regras.promessa, texto, referencia: `acomp:${a.id}` };
  }
  if (a.modo === "lembrar_em") {
    return { fonte: "lembrete_pedido", chave: `lembrete:${a.id}`, assunto, destino: "deixar", texto, referencia: `acomp:${a.id}` };
  }
  const referencia = referenciaDoAcompanhamento(a.id, ultimaRecebidaEm);
  return {
    fonte: "acompanhar", chave: `${referencia}:${n}`, assunto,
    destino: regras.acompanhar_conta_no_limite ? "acorde" : "deixar", texto, referencia, dados: { n },
  };
}
