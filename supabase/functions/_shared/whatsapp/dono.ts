// Quem é "o dono" no WhatsApp do sistema (comprovantes, F1 de 11/10/2026).
//
// A mesma regra de lembretes-de-revisao (o primeiro admin ativo com o assistente no WhatsApp e
// telefone cadastrado, pelo created_at): um só, de propósito — o fluxo de comprovantes só assume
// a mídia DESSE telefone; os outros funcionários seguem com o assistente como hoje.

export type Dono = { id: string; phone: string };

/** O dono, ou null se não há nenhum admin habilitado. Erro de leitura lança (quem chama decide). */
// deno-lint-ignore no-explicit-any
export async function donoDoWhatsApp(admin: any): Promise<Dono | null> {
  const { data, error } = await admin
    .from("app_users")
    .select("id, phone_normalized")
    .eq("role", "admin")
    .eq("active", true)
    .eq("ai_whatsapp_enabled", true)
    .not("phone_normalized", "is", null)
    .order("created_at", { ascending: true })
    .limit(1);
  if (error) throw new Error(`Falha ao ler o dono: ${error.message ?? "erro desconhecido"}`);
  const linha = (data as Array<{ id?: string; phone_normalized?: string }> | null)?.[0];
  if (!linha?.id || !linha.phone_normalized) return null;
  return { id: String(linha.id), phone: String(linha.phone_normalized) };
}
