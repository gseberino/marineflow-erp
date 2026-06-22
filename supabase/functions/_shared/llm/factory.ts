// Fábrica de LLM provider — escolhe o adapter por config e injeta a chave do env.

import type { FetchLike, LLMConfig, LLMProvider, LLMProviderKind } from "./types.ts";
import { OpenRouterProvider } from "./openrouter-provider.ts";
import { AnthropicProvider } from "./anthropic-provider.ts";

// Modelos padrão por provider (econômico p/ classificar; troque via app_settings).
const DEFAULT_MODEL: Record<LLMProviderKind, string> = {
  openrouter: "anthropic/claude-haiku-4-5",
  anthropic: "claude-haiku-4-5",
};

export function createLLMProvider(
  cfg: LLMConfig,
  fetchFn?: FetchLike,
): LLMProvider {
  switch (cfg.provider) {
    case "anthropic":
      return new AnthropicProvider(cfg.apiKey, cfg.defaultModel, fetchFn);
    case "openrouter":
    default:
      return new OpenRouterProvider(cfg.apiKey, cfg.defaultModel, fetchFn);
  }
}

/**
 * Monta a LLMConfig a partir de app_settings (provider/modelo — não-secreto) e
 * do ambiente (a CHAVE — secret). Retorna null se não houver chave configurada
 * (nesse caso o orquestrador simplesmente não escala ao LLM).
 */
export function buildLLMConfig(
  settings: Record<string, string>,
  env: (key: string) => string | undefined,
): LLMConfig | null {
  const provider: LLMProviderKind =
    settings["ai_operator_llm_provider"] === "anthropic"
      ? "anthropic"
      : "openrouter";

  const apiKey =
    provider === "anthropic"
      ? env("ANTHROPIC_API_KEY")
      : env("OPENROUTER_API_KEY");
  if (!apiKey) return null;

  const defaultModel =
    settings["ai_operator_llm_model"] || DEFAULT_MODEL[provider];

  return { provider, apiKey, defaultModel };
}
