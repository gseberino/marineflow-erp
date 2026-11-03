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
//
// ═══ O RETORNO TEM PORTÃO PRÓPRIO (Retorno rápido, F1, 16/11/2026) ═══
//
// As origens retorno_* (recibo, coleta, adiamento ao cliente) não passam por decidirSaidaAutomatica:
// quem decide é o banco, por retorno_saida_autorizada(saída, fone), que confere no instante do envio
// o estado da saída, o modo do caso, o telefone, o bloqueio e a janela do retorno (K3: 07:00–21:59
// para a resposta imediata; o adiamento tem a dele). A janela fixa de 8h–20h daqui recusaria o
// recibo das 07:10 que o banco autorizou.
// decidirSaidaDoRetorno só traduz a resposta do banco, falhando FECHADO: erro, resposta nula ou
// "pode" que não é booleano = não envia.
//
// Reverter: apagar decidirSaidaDoRetorno e as três mensagens do retorno em MENSAGENS.
import { mesmoTelefone } from "../ai/phone.ts";
import type { OrigemDoEnvio } from "./registro-do-envio.ts";

export const JANELA_INICIO = 8;
export const JANELA_FIM = 20;

/**
 * O envio é automático? Só a chamada de sistema que não diz ter vindo do assistente ou da tela. As
 * origens do retorno (retorno_*) ficam fora: têm portão próprio (decidirSaidaDoRetorno).
 */
export function ehAutomatica(origem: OrigemDoEnvio, chamadaDeSistema: boolean): boolean {
  return chamadaDeSistema && origem === "sistema";
}

/** DDD de um telefone brasileiro (com 55: 12–13 dígitos; sem: 10–11), ou null. O mesmo de _ddd_do_telefone (SQL). */
export function dddDoTelefone(telefone: string | null | undefined): string | null {
  const d = String(telefone ?? "").replace(/\D/g, "");
  if (/^55\d{10,11}$/.test(d)) return d.slice(2, 4);
  if (/^\d{10,11}$/.test(d)) return d.slice(0, 2);
  return null;
}

/**
 * O destino é alguém da equipe? Pela chave do telefone E pelo mesmo DDD quando os dois têm: isentar
 * é mais perigoso que bloquear, e um estranho com os mesmos 8 dígitos do dono, de outro DDD, não
 * escapa do portão (o mesmo de _mesmo_telefone, SQL).
 */
export function ehDaEquipe(telefone: string, telefonesDaEquipe: Array<string | null | undefined>): boolean {
  const ddd = dddDoTelefone(telefone);
  return telefonesDaEquipe.some((t) => {
    if (!mesmoTelefone(t, telefone)) return false;
    const outro = dddDoTelefone(t);
    return ddd === null || outro === null || ddd === outro;
  });
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

/**
 * A próxima abertura da janela (08:00 de Brasília): hoje, se ainda não deu 8h; senão amanhã. Para o
 * que foi recusado como fora_de_horario esperar, em vez de gastar tentativa. Brasília é UTC−3 fixo
 * (sem horário de verão desde 2019).
 */
export function proximaAberturaDaJanela(agora: Date = new Date()): Date {
  const dia = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(agora);
  const hora = horaDeBrasilia(agora) ?? JANELA_FIM;
  const abertura = new Date(`${dia}T${String(JANELA_INICIO).padStart(2, "0")}:00:00-03:00`);
  if (hora >= JANELA_INICIO) abertura.setUTCDate(abertura.getUTCDate() + 1);
  return abertura;
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
  // Retorno (F1): motivos de retorno_saida_autorizada sem texto próprio caem na mensagem genérica.
  retorno_nao_autorizado: "o banco não autorizou esta saída do retorno.",
  fora_da_janela: "fora da janela de horário do retorno.",
  erro: "a conferência da saída do retorno deu erro no banco.",
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
 * Pode sair a saída do retorno? `aut` é a resposta de retorno_saida_autorizada ({pode, motivo}), ou
 * "erro" quando a chamada falhou. Só `pode === true` envia; resposta nula, sem objeto ou com "pode"
 * que não é booleano recusa como checagem_indisponivel; `pode` falso recusa com o motivo do banco.
 */
export function decidirSaidaDoRetorno(aut: { pode?: unknown; motivo?: unknown } | null | "erro"): DecisaoDaSaida {
  if (aut === "erro" || aut === null || typeof aut !== "object" || Array.isArray(aut) || typeof aut.pode !== "boolean") {
    return recusa("checagem_indisponivel");
  }
  if (aut.pode === true) return { pode: true };
  const motivo = typeof aut.motivo === "string" && aut.motivo.trim() !== "" ? aut.motivo.trim() : "retorno_nao_autorizado";
  return recusa(motivo);
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
