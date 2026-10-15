// Como um turno do modelo vira mensagem no WhatsApp e estado da sessão — o MESMO para os dois
// provedores do agente (OpenRouter, que roda o loop na edge, e Claude Max, que roda no gateway
// local). Extraído de ai-agent/index.ts em 03/10/2026 sem mudar o texto nem o metadata.
import type { FluxoQueFalou, OptionsData, Proposal } from "./agent.ts";
import { formatOptionsAsNumberedText, notaDeConfirmacao } from "./whatsapp-channel.ts";

/**
 * O erro como o dono deve ler (15/10/2026): erro técnico cru ("Falha ao chamar a Anthropic API",
 * "HTTP 530", "violates check constraint", um uuid) vira uma frase em português; erro de negócio
 * ("A cotação COT-00012 está fechada") passa como veio. O texto cru continua no log e na pendência
 * (ai_operator_pending_actions.result) — quem chama registra antes de trocar.
 */
const MARCAS_TECNICAS = [
  /\bHTTP\s*\d{3}\b/i, /\bPGRST\d*/i, /\bviolates\b/i, /\bconstraint\b/i, /\brelation\s+"/i, /\bcolumn\s+"/i,
  /\bsyntax error\b/i, /\bTypeError\b/, /\bJWT\b/i, /\bfetch failed\b/i, /\bAnthropic\b/i, /\bOpenRouter\b/i,
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
];
export const ERRO_DO_SISTEMA_PARA_O_DONO = "não consegui concluir agora (erro do sistema, já anotado). Tente de novo em instantes.";

export function erroParaODono(erro: unknown): string {
  // Erro que não é texto (objeto do banco, do provedor) é técnico por natureza.
  if (typeof erro !== "string" || !erro.trim()) return ERRO_DO_SISTEMA_PARA_O_DONO;
  return MARCAS_TECNICAS.some((m) => m.test(erro)) ? ERRO_DO_SISTEMA_PARA_O_DONO : erro;
}

export interface DesfechoDoTurno {
  error?: string;
  options?: OptionsData;
  proposal?: Proposal;
  /** 11/10/2026: o fluxo de comprovantes já mandou a pergunta do CMP — o assistente não manda nada. */
  fluxo?: FluxoQueFalou;
  texto: string;
}

export function respostaDoTurnoNoWhatsApp(
  d: DesfechoDoTurno,
  metadata: Record<string, any>,
  /** A pendência desta conversa que ainda espera resposta (pendenciaQueSegueEsperando). */
  pendenciaViva: { title: string; risk_level?: string | null } | null = null,
): { replyText: string; metadata: Record<string, any> } {
  // O turno passou pelo modelo: a pendência herdada (se havia) deixou de valer aqui — os ramos
  // abaixo zeram ou trocam pending_confirm_action_id, e a marca de herança vai junto.
  const novo: Record<string, any> = { ...metadata, pendencia_herdada: false };
  let replyText: string;

  if (d.error) {
    // ⚠️ fica para erro e risco; o erro técnico cru não chega ao dono (erroParaODono).
    const paraODono = erroParaODono(d.error);
    if (paraODono !== d.error) console.warn("[whatsapp] erro do turno (cru):", d.error);
    replyText = `⚠️ ${paraODono}`;
    novo.pending_confirm_action_id = null;
  } else if (d.options) {
    replyText = formatOptionsAsNumberedText(d.options.question, d.options.options);
    novo.pending_options = d.options.options;
    novo.pending_confirm_action_id = null;
  } else if (d.proposal) {
    // Cartão de confirmação sem ⚠️ (15/10/2026): o ícone dos erros em toda confirmação (67 em 30
    // dias) tirava o peso do aviso de verdade. O título em negrito é a pergunta.
    replyText = `*${d.proposal.title}*\n${d.proposal.summary_markdown}${notaDeConfirmacao(d.proposal.risk_level)}`;
    novo.pending_confirm_action_id = d.proposal.pending_action_id;
    novo.pin_attempts = 0;
    novo.pending_options = null;
  } else if (d.fluxo) {
    // A resposta ao dono é a mensagem do fluxo (a linha "anotei o que você disse" e a pergunta do CMP
    // ou o resumo): texto vazio não é enviado (enviarComRegistro). As referências de pendência e de
    // opções ficam como estavam — este turno não decidiu nenhuma delas.
    replyText = "";
  } else if (pendenciaViva && metadata.pending_confirm_action_id) {
    // Conversa no meio de uma pendência viva (05/10/2026): a referência fica, e o dono vê que ela
    // ainda espera. Como na pendência herdada: "não" cancela, "sim <PIN>" aprova, e "sim" sem PIN
    // a mostra de novo em vez de executar — o "sim" pode ser resposta a outra coisa.
    replyText = `${d.texto || "Ok."}

⏳ Ainda espera a sua resposta: *${pendenciaViva.title}*.${notaDeConfirmacao(pendenciaViva.risk_level)}`;
    novo.pendencia_herdada = true;
  } else {
    replyText = d.texto || "Ok.";
    novo.pending_confirm_action_id = null;
  }
  return { replyText, metadata: novo };
}
