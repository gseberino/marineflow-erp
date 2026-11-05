// Guarda de envio — o ponto único que as tools de WhatsApp chamam antes de disparar.
// Une as duas camadas: compliance (BLOQUEIA) + linter de estilo (AVISA, fail-open).
// Assim toda mensagem externa passa pelo mesmo portão, sem duplicar regra por tool.

import { checarConformidade, type ComplianceCtx, ehDeFora, type Violacao } from "./compliance-guard.ts";
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

/** Na dúvida sobre quem recebe, conta como de fora: isentar é mais perigoso que segurar. */
function pareceDeFora(ctx: ComplianceCtx): boolean {
  try {
    return ehDeFora(ctx);
  } catch {
    return true;
  }
}

export function guardaDeEnvio(texto: string, ctx: ComplianceCtx): DecisaoEnvio {
  // 1) Conformidade (dura).
  // Retorno F0a-2 (05/11/2026): a checagem que quebra falha FECHADA para quem é de fora. Antes a exceção
  // virava "tudo certo" e a mensagem saía sem conferência nenhuma. Para a conversa interna, segue aberta.
  let violacao: Violacao | null = null;
  try {
    violacao = checarConformidade(ctx);
  } catch {
    if (pareceDeFora(ctx)) {
      return {
        bloqueado: true,
        motivo: "Não deu para conferir as regras de envio: nada foi enviado. Tente de novo em instantes.",
        codigoBloqueio: "guarda_indisponivel",
        avisos: [],
      };
    }
    violacao = null;
  }
  if (violacao) {
    return { bloqueado: true, motivo: violacao.motivo, codigoBloqueio: violacao.codigo, avisos: [] };
  }
  // 2) Estilo (advisory).
  const perfil = perfilDeVoz(ctx.audiencia, ctx.canal);
  const lint = revisarMensagem(texto, perfil);
  const avisos = lint.problemas.map((p) => `${p.codigo}: ${p.detalhe}`);
  return { bloqueado: false, avisos };
}
