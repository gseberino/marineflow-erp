import { ZapiProvider, type ZapiConfig } from "./zapi-provider.ts";
import type { WhatsAppProvider } from "./types.ts";

/**
 * Creates the active WhatsApp provider based on the WHATSAPP_PROVIDER env var.
 *
 * Current values:
 *   "zapi"      → ZapiProvider (default, production)
 *   "evolution" → EvolutionProvider (wired in B5, inactive until cutover B6)
 *
 * Callers that resolve credentials from app_settings (DB) pass zapiConfig
 * explicitly. Callers that read only from env can omit it — the factory
 * falls back to ZAPI_* env vars.
 */
export function createWhatsAppProvider(zapiConfig?: Partial<ZapiConfig>): WhatsAppProvider {
  const providerType = Deno.env.get("WHATSAPP_PROVIDER") ?? "zapi";

  if (providerType === "evolution") {
    // EvolutionProvider will be wired here in B5.
    // Until then, return ZapiProvider to preserve existing behaviour.
    console.warn(
      "WHATSAPP_PROVIDER=evolution requested but EvolutionProvider is not yet implemented. Falling back to ZapiProvider.",
    );
  }

  // Resolve Z-API credentials: explicit config takes priority over env vars.
  const instanceId =
    zapiConfig?.instanceId || Deno.env.get("ZAPI_INSTANCE_ID") || "";
  const token = zapiConfig?.token || Deno.env.get("ZAPI_TOKEN") || "";
  const clientToken =
    zapiConfig?.clientToken ?? Deno.env.get("ZAPI_CLIENT_TOKEN");

  return new ZapiProvider({ instanceId, token, clientToken });
}
