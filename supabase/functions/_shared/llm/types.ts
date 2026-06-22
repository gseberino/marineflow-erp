// Abstração de LLM — tipos
//
// Permite trocar de provider (OpenRouter ↔ Anthropic direto) com UMA variável
// de config, sem mudar o orquestrador. A chave é sempre um SECRET de ambiente
// (Deno.env), nunca app_settings nem hardcoded.

export type LLMRole = "system" | "user" | "assistant";

export interface LLMMessage {
  role: LLMRole;
  content: string;
}

export interface LLMCompleteOptions {
  model?: string;
  maxTokens?: number;
}

export interface LLMProvider {
  /** Nome do provider (auditoria). */
  readonly name: string;
  /** Completa uma conversa e devolve o texto da resposta. */
  complete(messages: LLMMessage[], opts?: LLMCompleteOptions): Promise<string>;
}

export type LLMProviderKind = "openrouter" | "anthropic";

export interface LLMConfig {
  provider: LLMProviderKind;
  /** Chave do provider (vinda de Deno.env — secret). */
  apiKey: string;
  /** Modelo padrão (slug do provider). */
  defaultModel: string;
}

/** fetch injetável para testabilidade (default: global fetch). */
export type FetchLike = (
  input: string,
  init?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
  },
) => Promise<{ ok: boolean; status: number; json: () => Promise<any> }>;
