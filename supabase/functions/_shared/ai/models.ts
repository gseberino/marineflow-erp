// Modelos Claude usados pelo AI Operator do MarineFlow, roteados via OpenRouter
// (slugs no formato "anthropic/<modelo>" — note o "." em claude-haiku-4.5, diferente do
// id "claude-haiku-4-5" usado na API nativa da Anthropic).
// Trocar de modelo entre turnos invalida o prompt cache — não fazer roteamento dinâmico
// dentro de um mesmo agente sem repensar a estratégia de cache (ver Fase 8, fora de escopo).
export const MODEL_AGENT = "anthropic/claude-sonnet-5";
export const MODEL_LITE = "anthropic/claude-haiku-4.5";

export const MAX_ITERATIONS = 8;
export const DEFAULT_MAX_TOKENS = 4096;
