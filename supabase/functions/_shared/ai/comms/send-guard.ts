// Guarda de envio — o ponto único que as tools de WhatsApp chamam antes de disparar.
// Une as duas camadas: compliance (BLOQUEIA) + linter de estilo (AVISA, fail-open).
// Assim toda mensagem externa passa pelo mesmo portão, sem duplicar regra por tool.

import { checarConformidade, type ComplianceCtx, type Violacao } from "./compliance-guard.ts";
import { revisarMensagem } from "./message-linter.ts";
import { perfilDeVoz } from "./voice-profiles.ts";

export interface DecisaoEnvio {
  /** true = NÃO enviar (violação de conformidade). */
  bloqueado: boolean;
  /** Motivo do bloqueio (quando bloqueado). */
  motivo?: string;
  codigoBloqueio?: string;
  /** Avisos de estilo (advisory) — logar, não bloqueiam. */
  avisos: string[];
}

export function guardaDeEnvio(texto: string, ctx: ComplianceCtx): DecisaoEnvio {
  // 1) Conformidade (dura).
  let violacao: Violacao | null = null;
  try { violacao = checarConformidade(ctx); } catch { violacao = null; /* fail-safe: não bloqueia por erro do guard */ }
  if (violacao) {
    return { bloqueado: true, motivo: violacao.motivo, codigoBloqueio: violacao.codigo, avisos: [] };
  }
  // 2) Estilo (advisory).
  const perfil = perfilDeVoz(ctx.audiencia, ctx.canal);
  const lint = revisarMensagem(texto, perfil);
  const avisos = lint.problemas.map((p) => `${p.codigo}: ${p.detalhe}`);
  return { bloqueado: false, avisos };
}
