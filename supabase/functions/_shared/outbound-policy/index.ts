// Outbound Policy Engine — ponto de entrada
export * from "./types.ts";
export { DEFAULT_POLICY_CONFIG } from "./config.ts";
export { evaluateOutbound } from "./rules.ts";
