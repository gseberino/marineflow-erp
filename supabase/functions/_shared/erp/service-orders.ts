// Camada de serviço compartilhada — criação de OS/orçamento
//
// CAMINHO ÚNICO: esta é a ÚNICA lógica de criação de OS/orçamento. Ela é
// chamada por três gatilhos, todos passando aqui:
//   1) manual    — o hook useCreateServiceOrder (frontend) embrulha esta função
//   2) AI no app  — o operador propõe e o app executa via esta função
//   3) AI autônomo — a edge function (cron/inbound) executa via esta função
//
// Injeção de dependência: recebe o client Supabase (browser OU service role),
// então funciona nos dois runtimes (Vite e Deno) e respeita o RLS de quem chama.
//
// Regra de negócio preservada do hook original: número OS-NNNNN sequencial.

/** Subconjunto mínimo do client Supabase que esta camada usa. */
export interface DbClientLike {
  from(table: string): {
    select: (cols: string) => Promise<{ data: any[] | null; error: any }>;
    insert: (payload: unknown) => {
      select: () => {
        single: () => Promise<{ data: any; error: any }>;
      };
    };
  };
}

/** Gera o próximo número sequencial OS-NNNNN (mesma regra do hook original). */
export async function generateServiceOrderNumber(
  client: DbClientLike,
): Promise<string> {
  const { data } = await client.from("service_orders").select(
    "service_order_number",
  );
  let maxSeq = 0;
  for (const row of data || []) {
    const match = String(row?.service_order_number ?? "").match(/(\d+)$/);
    if (match) {
      const n = parseInt(match[1], 10);
      if (n > maxSeq) maxSeq = n;
    }
  }
  return `OS-${String(maxSeq + 1).padStart(5, "0")}`;
}

export interface CreateServiceOrderResult {
  ok: boolean;
  data?: any;
  error?: string;
}

/**
 * Cria uma OS/orçamento real em `service_orders` (status rascunho nativo).
 * Mesma lógica que o usuário dispara manualmente — sem objeto paralelo.
 */
export async function createServiceOrder(
  client: DbClientLike,
  values: Record<string, unknown>,
): Promise<CreateServiceOrderResult> {
  try {
    const soNumber = await generateServiceOrderNumber(client);
    const payload = { ...values, service_order_number: soNumber };
    const { data, error } = await client
      .from("service_orders")
      .insert(payload)
      .select()
      .single();
    if (error) {
      return { ok: false, error: String(error?.message ?? error) };
    }
    return { ok: true, data };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}
