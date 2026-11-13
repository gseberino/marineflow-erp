// Retorno rápido, F5 (P10.1): a camada determinística do orçamento, antes das camadas do parceiro (F4) e do retorno (F2)
// no ai-agent.
//
// Só responde a quem ehDoDono. A palavra (comandos.ts) casou → orcamento_dito(p_comando, p_autor) → a resposta volta como
// texto. O banco confere o dono de novo (is_admin_or_financial) e acha a ordem pelo número, nunca pelo nome.
//
// Nunca há PIN aqui: as palavras do orçamento não levam *sim <PIN>* (segurar, soltar e trocar o motivo de um perdido não
// mandam nada ao cliente; marcar perdido um aberto depende de motivo_marca_aberto, dúvida 8). O comando vai ao banco como
// foi lido, e o leitor recusa qualquer frase com número a mais.
//
// Falha fecha: erro de RPC, exceção, função ausente (o ai-agent subindo antes das migrations) ou resposta sem texto →
// "Não consegui agora; tente pela tela." (C-DITO-O), e nada vai ao modelo. Nunca lança. O histórico do assistente não
// recebe nada daqui.
//
// Fora de _shared/ai/ de propósito: isolamento_test.ts varre esta pasta. Tudo chega por parâmetro.
//
// Reverter: tirar a chamada de camadaDoOrcamento do ai-agent e a marca do webhook (ehPalavraDoOrcamentoLigada).

import type { RespostaDaCamada, RespostaDaRpc } from "../retorno/camada.ts";
import { type ComandoDoOrcamento, lerComandoDoOrcamento } from "./comandos.ts";

export interface DependenciasDoOrcamento {
  /** O usuário do turno: vai como p_autor (orcamento_dito confere o cargo dele). */
  autor: string;
  ehDoDono: () => Promise<boolean>;
  /** A RPC como ela é. */
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RespostaDaRpc>;
}

/** C-DITO-O: o texto de quando não deu (o mesmo c_erro de orcamento_dito). */
export const R_ORCAMENTO = "Não consegui agora; tente pela tela.";

function falha(comando: string): RespostaDaCamada {
  return { comando, texto: R_ORCAMENTO, noHistorico: null };
}

async function doDono(deps: DependenciasDoOrcamento): Promise<boolean> {
  try {
    return (await deps.ehDoDono()) === true;
  } catch {
    return false;
  }
}

/** O comando como ele vai ao banco (orcamento_dito lê comando, numero e letra). */
function paraOBanco(c: ComandoDoOrcamento): Record<string, unknown> {
  return { ...c };
}

export async function camadaDoOrcamento(texto: string, deps: DependenciasDoOrcamento): Promise<RespostaDaCamada | null> {
  const comando = lerComandoDoOrcamento(texto);
  if (!comando) return null;
  if (!(await doDono(deps))) return null;

  let resposta: RespostaDaRpc;
  try {
    resposta = await deps.rpc("orcamento_dito", { p_comando: paraOBanco(comando), p_autor: deps.autor });
  } catch {
    return falha(comando.comando);
  }
  // Erro ou função ausente: a frase fixa. A palavra é nova (F5), mas *segura 151* nunca pode chegar ao modelo.
  if (resposta.error) return falha(comando.comando);

  const r = resposta.data;
  if (r === null || typeof r !== "object" || Array.isArray(r)) return falha(comando.comando);
  const lido = r as { ok?: unknown; texto?: unknown; motivo?: unknown };
  // O banco confere o dono de novo: quem não é segue como sempre.
  if (lido.motivo === "nao_e_o_dono") return null;
  if (typeof lido.texto !== "string" || !lido.texto.trim()) return falha(comando.comando);
  return { comando: comando.comando, texto: lido.texto, noHistorico: null };
}

/**
 * A palavra do orçamento, para o webhook não deixar o CMP aberto engoli-la (P10.1): verdadeira quando o leitor casa, sem
 * banco. Nunca lança.
 */
export function ehPalavraDoOrcamentoLigada(texto: string): boolean {
  try {
    return lerComandoDoOrcamento(texto) !== null;
  } catch {
    return false;
  }
}
