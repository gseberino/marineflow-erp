import { EvolutionProvider } from "./evolution-provider.ts";
import type { WhatsAppProvider } from "./types.ts";

/**
 * O provedor de WhatsApp: a Evolution (EVOLUTION_API_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE).
 *
 * O Z-API saiu em 06/10/2026 (inventário): não era usado desde a troca para a Evolution, e a
 * fábrica caía nele para QUALQUER valor de WHATSAPP_PROVIDER diferente de "evolution" — um erro
 * de digitação na variável mandaria as mensagens para um provedor sem credencial. Agora valor
 * desconhecido é recusado com o motivo.
 */
export function createWhatsAppProvider(): WhatsAppProvider {
  const providerType = (Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution").trim().toLowerCase();
  if (providerType !== "evolution") {
    throw new Error(
      `WHATSAPP_PROVIDER="${providerType}" não é suportado: o único provedor é a Evolution (o Z-API foi removido em 06/10/2026).`,
    );
  }

  const apiUrl = Deno.env.get("EVOLUTION_API_URL") ?? "";
  const apiKey = Deno.env.get("EVOLUTION_API_KEY") ?? "";
  const instance = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
  if (!apiUrl || !apiKey || !instance) {
    throw new Error(
      "EvolutionProvider: EVOLUTION_API_URL, EVOLUTION_API_KEY e EVOLUTION_INSTANCE são obrigatórios.",
    );
  }
  return new EvolutionProvider({ apiUrl, apiKey, instance });
}
