// MarineFlow AI Operator — validação de referências de entidade do ERP.
//
// Antes de persistir referência a entidade do ERP (client_id/vessel_id/
// product_id/service_id) usando service_role, validamos que o usuário
// autenticado consegue VER aquela linha com seu próprio JWT (cliente `sb`
// instanciado com a anon key + Authorization Bearer do usuário). Isso
// respeita as policies de RLS existentes em clients/vessels/products/
// services — se o usuário não pode ler a entidade, não a referenciamos.
//
// O helper é isolado em módulo próprio para que possa ser testado por
// Vitest sem precisar do runtime Deno.

export type EntityKind = "client" | "vessel" | "product" | "service" | "service_order";

const TABLE_BY_KIND: Record<EntityKind, string> = {
  client: "clients",
  vessel: "vessels",
  product: "products",
  service: "services",
  service_order: "service_orders",
};

export type EntityValidationResult =
  | { ok: true }
  | { ok: false; reason: "not_visible" | "not_found" | "invalid_reference" | "db_error"; details?: string };

// Tipo mínimo do client do supabase-js que precisamos — facilita mock no teste.
export interface SupabaseLike {
  from(table: string): {
    select(cols: string): {
      eq(col: string, val: string): {
        maybeSingle(): Promise<{ data: any; error: any }>;
      };
    };
  };
}

export async function validateEntityVisible(
  sb: SupabaseLike,
  kind: EntityKind,
  id: string
): Promise<EntityValidationResult> {
  const table = TABLE_BY_KIND[kind];
  if (!table) return { ok: false, reason: "not_found", details: `kind inválido: ${kind}` };
  if (!id || typeof id !== "string") {
    return { ok: false, reason: "not_found", details: "id ausente" };
  }
  if (/\[?\s*referencia interna oculta\s*\]?/i.test(id)) {
    return { ok: false, reason: "invalid_reference", details: "referencia sanitizada" };
  }
  try {
    const { data, error } = await sb.from(table).select("id").eq("id", id).maybeSingle();
    if (error) {
      // RLS pode retornar erro vazio — tratamos como invisível por segurança.
      return { ok: false, reason: "db_error", details: error.message ?? "db error" };
    }
    if (!data) {
      // Pode ser tanto inexistente quanto invisível por RLS. Não vazamos diferença.
      return { ok: false, reason: "not_visible" };
    }
    return { ok: true };
  } catch (e: any) {
    return { ok: false, reason: "db_error", details: e?.message ?? "exception" };
  }
}

// Valida múltiplas referências em paralelo. Retorna mapa kind→result.
export async function validateAllReferences(
  sb: SupabaseLike,
  refs: Partial<Record<EntityKind, string | null | undefined>>
): Promise<Partial<Record<EntityKind, EntityValidationResult>>> {
  const entries = (Object.entries(refs) as [EntityKind, string | null | undefined][])
    .filter(([, v]) => typeof v === "string" && v.length > 0);
  const results: Partial<Record<EntityKind, EntityValidationResult>> = {};
  await Promise.all(
    entries.map(async ([kind, id]) => {
      results[kind] = await validateEntityVisible(sb, kind, id as string);
    })
  );
  return results;
}
