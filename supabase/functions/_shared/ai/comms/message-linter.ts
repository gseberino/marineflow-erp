// Portão de Qualidade (módulo E) — "linter de comunicação".
// Revisa o TEXTO FINAL de uma mensagem contra as proibições do perfil de voz e o teto de
// tamanho. É ADVISORY (fail-open): nunca lança e nunca bloqueia sozinho — devolve problemas
// para o chamador logar/reescrever. As travas que BLOQUEIAM ficam no compliance-guard.
//
// A pesquisa mostra que exemplos governam tom melhor que regras; aqui o objetivo é só pegar
// os vícios reincidentes de forma barata (heurística), como rede de segurança.

import type { ProibicaoCodigo, VoiceProfile } from "./voice-profiles.ts";

export interface Problema {
  codigo: ProibicaoCodigo | "tamanho";
  detalhe: string;
  trecho?: string;
}
export interface ResultadoLint {
  ok: boolean;
  problemas: Problema[];
}

function semAcento(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Detectores por código. Cada um recebe o texto original e o normalizado (minúsculo/sem acento).
const DETECTORES: Record<ProibicaoCodigo, (orig: string, norm: string) => Problema | null> = {
  razao_social: (orig) => {
    // Razão social na saudação: sufixo jurídico OU nome LongoEmCaixaAlta logo após "Olá/Oi".
    const m = orig.match(/\b(LTDA|EIRELI|MEI|S[\/.]?A|ME)\b/) ||
      orig.match(/\b(?:Ol[áa]|Oi)\s+([A-ZÁÉÍÓÚÂÊÔÃÕÇ][A-ZÁÉÍÓÚÂÊÔÃÕÇ '&-]{10,})/);
    return m ? { codigo: "razao_social", detalhe: "saudação usa razão social", trecho: m[0].slice(0, 40) } : null;
  },
  aplicacao: (_o, norm) => {
    const m = norm.match(/para (o |a )?(sistema|uso|aplica)|aplicacao|destina-se|sera utilizad|para .{0,20}(victron|lifepo|12v)/);
    return m ? { codigo: "aplicacao", detalhe: "descreve a aplicação/'pra que serve'", trecho: m[0].slice(0, 40) } : null;
  },
  prazo_estipulado: (_o, norm) => {
    const m = norm.match(/prazo desejado|o mais breve|com urgencia|prazo de entrega|preciso (para|ate)|entregar ate/);
    return m ? { codigo: "prazo_estipulado", detalhe: "remetente estipula prazo (quem define é o outro)", trecho: m[0].slice(0, 40) } : null;
  },
  tutorial_resposta: (_o, norm) => {
    const m = norm.match(/responder com o (numero|preco)|pode responder com|responda com|ex\.?:\s*"?\d+\s*-\s*r\$/);
    return m ? { codigo: "tutorial_resposta", detalhe: "ensina o outro a responder", trecho: m[0].slice(0, 40) } : null;
  },
  preco: (_o, norm) => {
    const m = norm.match(/r\$\s?\d|preco|custo|margem/);
    return m ? { codigo: "preco", detalhe: "cita preço/custo/margem", trecho: m[0].slice(0, 30) } : null;
  },
  jargao_tecnico: (orig) => {
    const m = orig.match(/\b\d{2,4}\/\d{2,4}\b/) || orig.match(/\b(MPPT|MultiPlus|SmartShunt|SKU|NCM)\b/i);
    return m ? { codigo: "jargao_tecnico", detalhe: "jargão/código técnico para cliente", trecho: m[0] } : null;
  },
  ameaca: (_o, norm) => {
    const m = norm.match(/sob pena|providencias (legais|cabiveis)|negativa|serasa|\bspc\b|evitar transtornos|regularize (imediatamente|o quanto antes)|sera (protestad|cobrad judicial)/);
    return m ? { codigo: "ameaca", detalhe: "tom de ameaça/ultimato", trecho: m[0].slice(0, 40) } : null;
  },
};

/**
 * Revisa a mensagem. NUNCA lança. `ok:true` quando não achou problema.
 * Só checa as proibições do perfil (mais o teto de tamanho).
 */
export function revisarMensagem(texto: string, perfil: VoiceProfile): ResultadoLint {
  const problemas: Problema[] = [];
  try {
    const orig = String(texto || "");
    const norm = semAcento(orig);

    for (const cod of perfil.proibicoes) {
      const det = DETECTORES[cod];
      const p = det ? det(orig, norm) : null;
      if (p) problemas.push(p);
    }

    if (perfil.tetoLinhas > 0) {
      const linhas = orig.split("\n").filter((l) => l.trim().length > 0).length;
      if (linhas > perfil.tetoLinhas) {
        problemas.push({ codigo: "tamanho", detalhe: `${linhas} linhas > teto de ${perfil.tetoLinhas}` });
      }
    }
  } catch {
    return { ok: true, problemas: [] }; // fail-open
  }
  return { ok: problemas.length === 0, problemas };
}
