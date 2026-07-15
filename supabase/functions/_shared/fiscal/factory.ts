import { ContoraProvider } from "./contora-provider.ts";
import type { FiscalEnvironment, FiscalProvider } from "./types.ts";

const VALID_ENVIRONMENTS: readonly FiscalEnvironment[] = ["homologacao", "producao"];

// Validates FISCAL_ENVIRONMENT against the exact allowed set instead of a
// blind cast — a typo ("producao " with trailing space, "production") would
// otherwise sail through and only fail later as a confusing Postgres CHECK
// constraint violation on issued_fiscal_documents.environment.
export function readFiscalEnvironment(): FiscalEnvironment {
  const raw = Deno.env.get("FISCAL_ENVIRONMENT") ?? "homologacao";
  if (!VALID_ENVIRONMENTS.includes(raw as FiscalEnvironment)) {
    throw new Error(
      `FISCAL_ENVIRONMENT inválido: "${raw}". Valores aceitos: ${VALID_ENVIRONMENTS.join(" | ")}.`,
    );
  }
  return raw as FiscalEnvironment;
}

/**
 * Creates the active fiscal provider based on the FISCAL_PROVIDER env var.
 *
 * "contora" (default) — reads CONTORA_API_TOKEN, CONTORA_BASE_URL,
 *   CONTORA_WEBHOOK_SECRET and FISCAL_ENVIRONMENT. Uses Contora's flat/global
 *   routes, which infer the company from the token (single-CNPJ account).
 *
 * Additional providers (e.g. Focus NFe for NFS-e in production) can be added here
 * and selected per document type by the caller if needed.
 */
export function createFiscalProvider(): FiscalProvider {
  const providerType = Deno.env.get("FISCAL_PROVIDER") ?? "contora";

  if (providerType === "contora") {
    const baseUrl = Deno.env.get("CONTORA_BASE_URL") ??
      "https://fiscal.contora.com.br/api/v1";
    const token = Deno.env.get("CONTORA_API_TOKEN") ?? "";
    const webhookSecret = Deno.env.get("CONTORA_WEBHOOK_SECRET") ?? "";
    const environment = readFiscalEnvironment();

    if (!token) {
      throw new Error("ContoraProvider: CONTORA_API_TOKEN é obrigatório.");
    }

    return new ContoraProvider({ baseUrl, token, webhookSecret, environment });
  }

  throw new Error(`FISCAL_PROVIDER desconhecido: ${providerType}`);
}
