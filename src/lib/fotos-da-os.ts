import { useQuery } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

/**
 * Fotos da OS e do levantamento: bucket PRIVADO desde 04/10/2026 (decisão do dono, LGPD — a
 * foto mostra o barco e a casa do cliente). O banco guarda o caminho (`storage_path`,
 * `photo_path`) e a tela gera um link temporário para mostrar. Até aqui o bucket era público e
 * `service_order_photos.public_url` guardava um link permanente, aberto para quem o tivesse.
 *
 * Mesma ideia de src/lib/arquivo-privado.tsx (assinaturas e comprovantes), mas em lote: uma
 * galeria pede todos os links de uma vez.
 */
export const VALIDADE_DO_LINK_DA_FOTO_S = 3600;

/** Caminho → link temporário. Caminho que o perfil não pode ver (ou que sumiu) fica de fora. */
export async function linksDasFotos(caminhos: readonly string[]): Promise<Record<string, string>> {
  const unicos = [...new Set(caminhos.filter(Boolean))];
  if (unicos.length === 0) return {};
  // Bucket escrito por extenso: a guarda storage-sem-listagem-anonima lê cada chamada de
  // Storage do front e cobra que quem a faz tenha a regra de leitura.
  const { data, error } = await supabase.storage
    .from('service-order-photos')
    .createSignedUrls(unicos, VALIDADE_DO_LINK_DA_FOTO_S);
  if (error) throw error;
  const links: Record<string, string> = {};
  for (const item of data ?? []) {
    if (item.path && item.signedUrl) links[item.path] = item.signedUrl;
  }
  return links;
}

/** Os links na ordem dos caminhos, sem os que não vieram — para a galeria do PDF. */
export async function linksEmOrdem(caminhos: readonly string[]): Promise<string[]> {
  const links = await linksDasFotos(caminhos);
  return caminhos.map((c) => links[c]).filter((l): l is string => !!l);
}

/** Os links de uma lista de caminhos, renovados antes de vencer (a tela pode ficar aberta). */
export function useLinksDasFotos(caminhos: readonly string[]) {
  const chave = [...new Set(caminhos.filter(Boolean))].sort();
  return useQuery({
    queryKey: ['links-das-fotos', chave],
    enabled: chave.length > 0,
    staleTime: (VALIDADE_DO_LINK_DA_FOTO_S - 300) * 1000,
    refetchInterval: (VALIDADE_DO_LINK_DA_FOTO_S - 300) * 1000,
    queryFn: () => linksDasFotos(chave),
  });
}

/**
 * Abre a foto numa aba nova, gerando o link na hora do clique. A aba abre em branco ANTES do
 * link ficar pronto: aberta depois de um await, o navegador a trataria como pop-up.
 */
export async function abrirFoto(caminho: string) {
  const aba = window.open('', '_blank');
  try {
    const link = (await linksDasFotos([caminho]))[caminho];
    if (!link) throw new Error('Não consegui gerar o link da foto.');
    if (aba) aba.location.href = link;
    else window.location.href = link;
  } catch (e) {
    aba?.close();
    toast.error(e instanceof Error ? e.message : 'Não consegui abrir a foto.');
  }
}
