import { ZapiProvider, type ZapiConfig } from "./zapi-provider.ts";
import { EvolutionProvider } from "./evolution-provider.ts";
import type { WhatsAppProvider } from "./types.ts";

/**
 * Creates the active WhatsApp provider based on the WHATSAPP_PROVIDER env var.
 *
 * "zapi" (default) — reads credentials from zapiConfig or ZAPI_* env vars.
 * "evolution"      — reads EVOLUTION_API_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE
 *                    from env vars (zapiConfig is ignored).
 *
 * Callers that resolve Z-API credentials from app_settings (DB) pass zapiConfig
 * explicitly. Callers that read only from env can omit it.
 */
export function createWhatsAppProvider(zapiConfig?: Partial<ZapiConfig>): WhatsAppProvider {
  const providerType = Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution";

  if (providerType === "evolution") {
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

  // Default: ZapiProvider — resolve credentials from explicit config or env vars.
  const instanceId =
    zapiConfig?.instanceId || Deno.env.get("ZAPI_INSTANCE_ID") || "";
  const token = zapiConfig?.token || Deno.env.get("ZAPI_TOKEN") || "";
  const clientToken =
    zapiConfig?.clientToken ?? Deno.env.get("ZAPI_CLIENT_TOKEN");

  return new ZapiProvider({ instanceId, token, clientToken });
}
