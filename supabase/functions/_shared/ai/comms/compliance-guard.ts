// Guardrails de conformidade (Brasil, CDC/LGPD) — o medo nº 1 do dono.
// Diferente do linter (advisory/fail-open), estas são TRAVAS DURAS: quando disparam, o envio
// NÃO acontece. São poucas, claras e detectáveis, para não bloquear trabalho legítimo por engano.
//
// Base: CDC art. 42 (cobrança não pode expor o consumidor a ridículo/constrangimento) e boa
// prática de horário; LGPD (dado ao interlocutor certo); anti-golpe (identidade do destino).

import type { Audiencia, Canal } from "./voice-profiles.ts";

export interface ComplianceCtx {
  tipo: "cobranca" | "cotacao" | "os_link" | "agendamento" | "generico";
  audiencia: Audiencia;
  canal: Canal;
  /** Hora local de Brasília (0-23). Se ausente, calcula de agora. */
  horaBrasilia?: number;
  /** O número de destino está vinculado a um cliente/fornecedor conhecido? */
  destinatarioIdentificado?: boolean;
  /** Texto final da mensagem (para checagens textuais, ex.: preço a técnico). */
  texto?: string;
}

export interface Violacao {
  codigo: string;
  motivo: string;
}

const H_INICIO = 8; // 08:00
const H_FIM = 20; // até 19:59

/**
 * Retorno F0a-2 (05/11/2026): o telefone do cadastro genérico "Cliente Final" é de um terceiro que ninguém
 * identificou. Nada que leve dado de um cliente vai para lá, nem a pedido do dono: o resumo do "sim" já avisa.
 */
export const RECUSA_CLIENTE_FINAL =
  'Este é o cadastro genérico "Cliente Final": o telefone dele é de um terceiro. Nada foi enviado. Ligue o documento ao cliente de verdade e peça de novo.';

// Retorno F0a-2 (05/11/2026): hora que não se sabe é null, nunca um valor "neutro". Antes virava 12h,
// e a trava de horário passava calada justamente quando não dava para conferir.
function horaAgoraBrasilia(): number | null {
  try {
    const s = new Date().toLocaleString("en-US", { timeZone: "America/Sao_Paulo", hour: "2-digit", hour12: false });
    const h = parseInt(s.match(/\d{1,2}/)?.[0] ?? "", 10);
    return isNaN(h) ? null : h % 24;
  } catch {
    return null;
  }
}

/** A mensagem vai a quem é de fora (cliente ou fornecedor, pelo WhatsApp)? */
export function ehDeFora(ctx: Pick<ComplianceCtx, "canal" | "audiencia">): boolean {
  return ctx.canal === "whatsapp" && (ctx.audiencia === "cliente" || ctx.audiencia === "fornecedor");
}

/**
 * Retorna a PRIMEIRA violação encontrada, ou null se está tudo conforme.
 * O chamador que receber uma violação deve ABORTAR o envio e explicar.
 */
export function checarConformidade(ctx: ComplianceCtx): Violacao | null {
  const externo = ehDeFora(ctx);

  // 1) Horário permitido — não perturbar cliente/fornecedor fora de 8h–20h (Brasília).
  if (externo) {
    const h = ctx.horaBrasilia ?? horaAgoraBrasilia();
    if (h === null) {
      return { codigo: "hora_indisponivel", motivo: `Não deu para conferir a hora de Brasília: nada foi enviado a ${ctx.audiencia}. Tente de novo em instantes.` };
    }
    if (h < H_INICIO || h >= H_FIM) {
      return { codigo: "fora_de_horario", motivo: `Envio a ${ctx.audiencia} fora do horário permitido (${h}h; janela ${H_INICIO}–${H_FIM}h). Agende para o próximo horário comercial.` };
    }
  }

  // 2) Cobrança a número NÃO identificado — risco de cobrar a pessoa errada / expor a terceiro.
  if (ctx.tipo === "cobranca" && ctx.destinatarioIdentificado === false) {
    return { codigo: "destinatario_nao_identificado", motivo: "Cobrança a um contato não vinculado a um cliente. Identifique o contato (identify_contact/link_contact_to_entity) antes de cobrar — cobrar a pessoa errada expõe a dívida a terceiro (CDC)." };
  }

  // 3) Audiência errada — preço/custo/margem para TÉCNICO.
  if (ctx.audiencia === "tecnico" && ctx.texto) {
    const norm = ctx.texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    if (/r\$\s?\d|\bpreco\b|\bcusto\b|\bmargem\b/.test(norm)) {
      return { codigo: "preco_a_tecnico", motivo: "Mensagem a técnico contém preço/custo/margem — técnico não deve ver valores." };
    }
  }

  return null;
}
