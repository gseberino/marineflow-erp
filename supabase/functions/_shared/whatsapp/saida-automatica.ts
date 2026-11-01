// O portão do envio AUTOMÁTICO a quem é de fora, no whatsapp-send.
//
// ═══ POR QUE EXISTE (Retorno rápido ao cliente, F0a-1, 05/11/2026) ═══
//
// O whatsapp-send mandava tudo o que chegava: sem janela de horário, sem opt-out e sem olhar o
// "Cliente Final" (o cadastro genérico guarda o telefone de um terceiro que ninguém identificou).
// E as duas guardas que existiam falhavam ABERTAS: o send-guard engole a exceção do checador
// (`catch { violacao = null }`) e a hora de Brasília vira 12h quando não dá para calculá-la; a
// reserva de idempotência, quando o banco não responde, deixa enviar sem proteção.
//
// Aqui vale o contrário, e só para o automático a quem é de fora:
//  - automático = chamada de sistema (service-role) com origem "sistema". O que o dono pede, pela
//    tela ou pelo assistente, não passa por este portão (o cartão avisa; quem decide é ele);
//  - de fora = não é telefone da equipe (app_users ativo). O aviso ao dono nunca é barrado aqui;
//  - na dúvida, NÃO envia: checagem que falhou, hora que não se sabe, reserva que não se fez.
//
// As guardas de _shared/ai/comms ficam como estão até a 7b da agenda estar verde (aquela pasta
// vai junto com o ai-agent); a janela é a mesma delas, 08:00–19:59 de Brasília.
import { mesmoTelefone } from "../ai/phone.ts";
import type { OrigemDoEnvio } from "./registro-do-envio.ts";

export const JANELA_INICIO = 8;
export const JANELA_FIM = 20;

/** O envio é automático? Só a chamada de sistema que não diz ter vindo do assistente ou da tela. */
export function ehAutomatica(origem: OrigemDoEnvio, chamadaDeSistema: boolean): boolean {
  return chamadaDeSistema && origem === "sistema";
}

/** O destino é alguém da equipe? */
export function ehDaEquipe(telefone: string, telefonesDaEquipe: Array<string | null | undefined>): boolean {
  return telefonesDaEquipe.some((t) => mesmoTelefone(t, telefone));
}

/** Hora de Brasília (0–23), ou null quando não deu para saber. Nunca um valor "neutro". */
export function horaDeBrasilia(agora: Date = new Date()): number | null {
  try {
    const texto = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Sao_Paulo",
      hour: "2-digit",
      hourCycle: "h23",
    }).format(agora);
    const hora = parseInt(texto, 10);
    return Number.isInteger(hora) && hora >= 0 && hora <= 23 ? hora : null;
  } catch {
    return null;
  }
}

export type DecisaoDaSaida =
  | { pode: true }
  | { pode: false; codigo: string; mensagem: string };

const MENSAGENS: Record<string, string> = {
  cliente_final: 'o número é o do cadastro genérico "Cliente Final", de um terceiro não identificado.',
  bloqueado: "o número está na lista de bloqueio.",
  opt_out: "o contato pediu para não receber mensagens automáticas.",
  checagem_indisponivel: "não deu para conferir se o número pode receber (banco sem resposta).",
  hora_indisponivel: "não deu para conferir a hora de Brasília.",
};

function recusa(codigo: string, detalhe?: string): DecisaoDaSaida {
  const motivo = detalhe ?? MENSAGENS[codigo] ?? `o número não pode receber mensagem automática (${codigo}).`;
  return { pode: false, codigo, mensagem: `Envio automático recusado: ${motivo}` };
}

/**
 * Pode sair? `bloqueio` é a resposta de canal_bloqueado (motivo ou null), ou "erro" quando a
 * consulta falhou. `daEquipe` "erro" = não deu para saber: segue como de fora.
 */
export function decidirSaidaAutomatica(p: {
  daEquipe: boolean | "erro";
  bloqueio: string | null | "erro";
  hora: number | null;
}): DecisaoDaSaida {
  if (p.daEquipe === true) return { pode: true };
  if (p.bloqueio === "erro") return recusa("checagem_indisponivel");
  if (p.bloqueio) return recusa(p.bloqueio);
  if (p.hora === null) return recusa("hora_indisponivel");
  if (p.hora < JANELA_INICIO || p.hora >= JANELA_FIM) {
    return recusa("fora_de_horario", `fora do horário (${p.hora}h; a janela é das ${JANELA_INICIO}h às ${JANELA_FIM}h de Brasília).`);
  }
  return { pode: true };
}

/**
 * A reserva de idempotência não se fez (banco sem resposta): o automático a quem é de fora não
 * envia. Antes seguia "sem proteção", e com o banco lento o mesmo texto podia sair 2 ou 3 vezes.
 */
export function reservaImpedeEnvio(reserva: string, automaticaDeFora: boolean): boolean {
  return automaticaDeFora && reserva === "erro";
}

/**
 * O provedor falhou sem certeza de que a mensagem não saiu (tempo esgotado, conexão caída no
 * meio): o automático a quem é de fora MANTÉM a reserva, e a próxima tentativa com a mesma chave
 * ouve "em andamento" em vez de mandar de novo. Falha certa (recusa do WhatsApp, túnel fora)
 * libera a chave, como antes.
 */
export function manterReservaNaFalha(incerto: boolean | undefined, automaticaDeFora: boolean): boolean {
  return automaticaDeFora && incerto === true;
}
