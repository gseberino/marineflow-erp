// Quem pediu, para o histórico de documentos (migration 20270121100000_historico_de_documentos_captura).
//
// O banco grava o histórico por gatilho e descobre o autor pelo auth.uid() do JWT. Pelo WhatsApp e pelo Claude Max
// o assistente grava com o client service-role (não há JWT de usuário), e aí o auth.uid() é nulo: sem isto, toda
// edição do assistente nesses canais ficaria "servidor", sem dono. O banco lê estes dois cabeçalhos
// (private.historico_contexto) SÓ quando o papel da requisição é service_role — do navegador, valem nada.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

export type OrigemDoHistorico = "assistente_whatsapp" | "assistente_max" | "assistente_painel" | "cliente_link" | "servidor";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Os cabeçalhos que o banco lê. Autor que não é uuid fica de fora (o banco também ignoraria). */
export function cabecalhosDoHistorico(ator: string | null | undefined, origem: OrigemDoHistorico): Record<string, string> {
  const h: Record<string, string> = { "x-mf-origem": origem };
  if (ator && UUID.test(ator)) h["x-mf-ator"] = ator;
  return h;
}

/** Client service-role que carrega quem pediu em toda requisição — para o ToolCtx do turno. */
export function clienteServicoComAtor(url: string, chaveServico: string, ator: string | null | undefined, origem: OrigemDoHistorico) {
  return createClient(url, chaveServico, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: cabecalhosDoHistorico(ator, origem) },
  });
}
