// Botões da pasta do barco no Dropbox (Fase 2B/2C, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
//   PastaDoBarcoBotao — no cabeçalho da embarcação: abre a pasta, ou cria se ainda não tem.
//   AcoesDropboxDaOrdem — no menu "Ações" do orçamento/OS: abrir a pasta e salvar o PDF agora.
// Só para admin (as tabelas são só dele); para os outros cargos nada aparece.
import { FolderOpen, FolderPlus, Loader2, UploadCloud } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { DropdownMenuItem, DropdownMenuSeparator } from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/use-auth';
import { linkNoDropbox, usePastaDoBarco, usePedirAoDropbox } from '@/hooks/use-dropbox';

function avisar(r: { status: string; resultado: string }) {
  if (r.status === 'falhou') toast.error(`Dropbox: ${r.resultado}`);
  else if (r.status === 'pendente') toast.info(r.resultado);
  else toast.success(`Dropbox: ${r.resultado}`);
}

export function PastaDoBarcoBotao({ vesselId }: { vesselId: string }) {
  const { user } = useAuth();
  const ehAdmin = user?.role === 'admin';
  const { data: pasta, isLoading } = usePastaDoBarco(ehAdmin ? vesselId : null);
  const pedir = usePedirAoDropbox();
  if (!ehAdmin || isLoading) return null;

  if (pasta) {
    return (
      <Button variant="outline" size="sm" asChild title={pasta.caminho}>
        <a href={linkNoDropbox(pasta.caminho)} target="_blank" rel="noreferrer">
          <FolderOpen className="h-4 w-4 mr-1" />
          {pasta.codigo_projeto ? `Pasta ${pasta.codigo_projeto}` : 'Pasta no Dropbox'}
        </a>
      </Button>
    );
  }
  return (
    <Button
      variant="outline"
      size="sm"
      disabled={pedir.isPending}
      onClick={() =>
        pedir.mutate({ vesselId, motivo: 'pasta' }, {
          onSuccess: avisar,
          onError: (e) => toast.error((e as Error).message || 'Não consegui pedir a pasta.'),
        })}
    >
      {pedir.isPending ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <FolderPlus className="h-4 w-4 mr-1" />}
      Criar pasta no Dropbox
    </Button>
  );
}

export function AcoesDropboxDaOrdem({ orderId, vesselId }: { orderId: string; vesselId: string | null | undefined }) {
  const { user } = useAuth();
  const ehAdmin = user?.role === 'admin';
  const { data: pasta } = usePastaDoBarco(ehAdmin ? vesselId : null);
  const pedir = usePedirAoDropbox();
  if (!ehAdmin) return null;

  return (
    <>
      <DropdownMenuSeparator />
      {pasta && (
        <DropdownMenuItem asChild className="gap-2">
          <a href={linkNoDropbox(pasta.caminho)} target="_blank" rel="noreferrer">
            <FolderOpen className="h-4 w-4" /> Abrir pasta no Dropbox
          </a>
        </DropdownMenuItem>
      )}
      <DropdownMenuItem
        className="gap-2"
        disabled={pedir.isPending}
        onClick={() => {
          toast.info('Gerando o PDF e enviando ao Dropbox…');
          pedir.mutate({ orderId, motivo: 'manual' }, {
            onSuccess: avisar,
            onError: (e) => toast.error((e as Error).message || 'Não consegui enviar ao Dropbox.'),
          });
        }}
      >
        <UploadCloud className="h-4 w-4" /> Salvar PDF no Dropbox agora
      </DropdownMenuItem>
    </>
  );
}
