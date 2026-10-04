// Como um turno do modelo vira mensagem no WhatsApp e estado da sessão — o MESMO para os dois
// provedores do agente (OpenRouter, que roda o loop na edge, e Claude Max, que roda no gateway
// local). Extraído de ai-agent/index.ts em 03/10/2026 sem mudar o texto nem o metadata.
import type { OptionsData, Proposal } from "./agent.ts";
import { formatOptionsAsNumberedText, notaDeConfirmacao } from "./whatsapp-channel.ts";

export interface DesfechoDoTurno {
  error?: string;
  options?: OptionsData;
  proposal?: Proposal;
  texto: string;
}

export function respostaDoTurnoNoWhatsApp(
  d: DesfechoDoTurno,
  metadata: Record<string, any>,
): { replyText: string; metadata: Record<string, any> } {
  // O turno passou pelo modelo: a pendência herdada (se havia) deixou de valer aqui — os ramos
  // abaixo zeram ou trocam pending_confirm_action_id, e a marca de herança vai junto.
  const novo: Record<string, any> = { ...metadata, pendencia_herdada: false };
  let replyText: string;

  if (d.error) {
    replyText = `⚠️ ${d.error}`;
    novo.pending_confirm_action_id = null;
  } else if (d.options) {
    replyText = formatOptionsAsNumberedText(d.options.question, d.options.options);
    novo.pending_options = d.options.options;
    novo.pending_confirm_action_id = null;
  } else if (d.proposal) {
    replyText = `⚠️ ${d.proposal.title}\n${d.proposal.summary_markdown}${notaDeConfirmacao(d.proposal.risk_level)}`;
    novo.pending_confirm_action_id = d.proposal.pending_action_id;
    novo.pin_attempts = 0;
    novo.pending_options = null;
  } else {
    replyText = d.texto || "Ok.";
    novo.pending_confirm_action_id = null;
  }
  return { replyText, metadata: novo };
}
