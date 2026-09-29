import type { MouseEvent, ReactNode } from 'react';
import { useQuery } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import {
  caminhoNoBucket, linkExterno, type BucketPrivado,
} from '../../supabase/functions/_shared/arquivo-privado';

/**
 * Assinaturas e comprovantes ficam em bucket PRIVADO desde 29/09/2026: o banco guarda o caminho
 * e a tela gera um link temporário para mostrar. Antes eram links públicos permanentes (o PDF
 * assinado trazia nome, CPF/CNPJ e endereço do cliente). A regra do caminho mora em
 * supabase/functions/_shared/arquivo-privado.ts, a mesma das edges.
 */
export { caminhoNoBucket, type BucketPrivado };

const VALIDADE_S = 600;

async function gerarLink(bucket: BucketPrivado, caminho: string): Promise<string> {
  // Bucket escrito por extenso (e não numa variável): a guarda storage-sem-listagem-anonima lê
  // cada chamada de Storage do front e cobra que quem a faz tenha a regra de leitura.
  const { data, error } = bucket === 'signatures'
    ? await supabase.storage.from('signatures').createSignedUrl(caminho, VALIDADE_S)
    : await supabase.storage.from('expense-receipts').createSignedUrl(caminho, VALIDADE_S);
  if (error || !data?.signedUrl) throw new Error(error?.message || 'Não consegui gerar o link do arquivo.');
  return data.signedUrl;
}

/** Link temporário para mostrar o arquivo gravado em `valor` (caminho novo ou link antigo). */
export function useLinkDoArquivo(bucket: BucketPrivado, valor: string | null | undefined) {
  const caminho = caminhoNoBucket(valor, bucket);
  const externo = caminho ? null : linkExterno(valor);
  const q = useQuery({
    queryKey: ['link-do-arquivo', bucket, caminho],
    enabled: !!caminho,
    // Renova antes de vencer: a página pode ficar aberta mais que a validade do link.
    staleTime: (VALIDADE_S - 60) * 1000,
    refetchInterval: (VALIDADE_S - 60) * 1000,
    queryFn: () => gerarLink(bucket, caminho!),
  });
  return {
    url: externo ?? q.data ?? null,
    carregando: !!caminho && q.isLoading,
    erro: q.error as Error | null,
    existe: !!caminho || !!externo,
  };
}

/**
 * Abre o arquivo numa aba nova, gerando o link na hora do clique. A aba abre em branco ANTES
 * do link ficar pronto: aberta depois de um await, o navegador a trataria como pop-up.
 */
export async function abrirArquivo(bucket: BucketPrivado, valor: string | null | undefined) {
  const externo = linkExterno(valor);
  const caminho = caminhoNoBucket(valor, bucket);
  if (!caminho && !externo) return;
  const aba = window.open('', '_blank');
  try {
    const url = externo ?? await gerarLink(bucket, caminho!);
    if (aba) aba.location.href = url;
    else window.location.href = url;
  } catch (e) {
    aba?.close();
    toast.error(e instanceof Error ? e.message : 'Não consegui abrir o arquivo.');
  }
}

/** Link de lista ("Ver comprovante"): o link temporário só é gerado no clique. */
export function LinkDoArquivo({ bucket, valor, className, title, children }: {
  bucket: BucketPrivado;
  valor: string | null | undefined;
  className?: string;
  title?: string;
  children: ReactNode;
}) {
  return (
    <a
      href="#"
      role="button"
      title={title}
      className={className}
      onClick={(e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        void abrirArquivo(bucket, valor);
      }}
    >
      {children}
    </a>
  );
}
