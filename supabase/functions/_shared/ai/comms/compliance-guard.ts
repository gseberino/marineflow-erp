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

function horaAgoraBrasilia(): number {
  try {
    const s = new Date().toLocaleString("en-US", { timeZone: "America/Sao_Paulo", hour: "2-digit", hour12: false });
    const h = parseInt(s.match(/\d{1,2}/)?.[0] || "12", 10);
    return isNaN(h) ? 12 : h % 24;
  } catch {
    return 12; // fail-safe neutro (dentro do horário)
  }
}

/**
 * Retorna a PRIMEIRA violação encontrada, ou null se está tudo conforme.
 * O chamador que receber uma violação deve ABORTAR o envio e explicar.
 */
export function checarConformidade(ctx: ComplianceCtx): Violacao | null {
  const externo = ctx.canal === "whatsapp" && (ctx.audiencia === "cliente" || ctx.audiencia === "fornecedor");

  // 1) Horário permitido — não perturbar cliente/fornecedor fora de 8h–20h (Brasília).
  if (externo) {
    const h = ctx.horaBrasilia ?? horaAgoraBrasilia();
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
