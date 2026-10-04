// Fotos da OS no PDF gerado no servidor (assistente do WhatsApp).
//
// O bucket `service-order-photos` é PRIVADO desde 04/10/2026: a galeria do PDF precisa de link
// temporário, gerado aqui com o cliente `admin` (chave de serviço). A guarda
// src/test/storage-sem-listagem-anonima.test.ts cobra que toda chamada de Storage nos buckets com
// dado de cliente, dentro de supabase/functions, use o cliente chamado `admin`.
//
// A tela tem o par dela em src/lib/fotos-da-os.ts (link com a sessão de quem está logado).

/** Validade do link: o PDF é renderizado logo em seguida; uma hora sobra. */
export const VALIDADE_DO_LINK_DA_FOTO_S = 3600;

/** Os links na ordem dos caminhos, sem os que não vieram. */
// deno-lint-ignore no-explicit-any
export async function linksDasFotosNoServidor(admin: any, caminhos: readonly string[]): Promise<string[]> {
  const unicos = [...new Set(caminhos.filter(Boolean))];
  if (unicos.length === 0) return [];
  const { data, error } = await admin.storage
    .from("service-order-photos")
    .createSignedUrls(unicos, VALIDADE_DO_LINK_DA_FOTO_S);
  if (error) throw new Error(`Não consegui gerar os links das fotos: ${error.message ?? error}`);
  const links = new Map<string, string>();
  for (const item of (data ?? []) as Array<{ path?: string | null; signedUrl?: string | null }>) {
    if (item.path && item.signedUrl) links.set(item.path, item.signedUrl);
  }
  return caminhos.map((c) => links.get(c)).filter((l): l is string => !!l);
}
