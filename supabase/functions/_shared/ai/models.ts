// Modelos Claude usados pelo AI Operator do MarineFlow, roteados via OpenRouter
// (slugs no formato "anthropic/<modelo>" — note o "." em claude-haiku-4.5, diferente do
// id "claude-haiku-4-5" usado na API nativa da Anthropic).
// Trocar de modelo entre turnos invalida o prompt cache — não fazer roteamento dinâmico
// dentro de um mesmo agente sem repensar a estratégia de cache (ver Fase 8, fora de escopo).
export const MODEL_AGENT = "anthropic/claude-sonnet-5";
export const MODEL_LITE = "anthropic/claude-haiku-4.5";

export const MAX_ITERATIONS = 8;
// Teto de tokens de SAÍDA por turno do agente principal (painel + WhatsApp) — não é um
// piso, o custo é pelos tokens realmente gerados. Compartilhado com os tokens de
// "raciocínio" (reasoning.effort, ver agent.ts), que consomem parte deste orçamento antes
// da resposta final começar — por isso 4096 truncava respostas com listas/várias etapas.
export const DEFAULT_MAX_TOKENS = 8192;
