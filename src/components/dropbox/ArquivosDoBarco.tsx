// Aba "Arquivos" da embarcação (Fase 3, 08/10/2026 — plans/marineflow-dropbox-fase2.md): o que
// está nas pastas do barco no Dropbox, pelo índice (arquivos_dropbox). Só a ficha; abrir leva ao
// site do Dropbox. Só o admin enxerga (RLS).
import { useMemo, useState } from 'react';
import { ExternalLink, FileText, Image as ImageIcon, Loader2, Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { linkDoArquivo, useArquivosDoBarco, type ArquivoDoBarco } from '@/hooks/use-dropbox';

const IMAGENS = new Set(['jpg', 'jpeg', 'png', 'heic', 'gif', 'webp', 'mov', 'mp4']);

function tamanho(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} MB`;
}

const dia = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '—');

export function ArquivosDoBarco({ vesselId }: { vesselId: string }) {
  const { data: arquivos, isLoading, error } = useArquivosDoBarco(vesselId);
  const [busca, setBusca] = useState('');

  const visiveis = useMemo(() => {
    const q = busca.trim().toLowerCase();
    if (!q) return arquivos ?? [];
    return (arquivos ?? []).filter((a) => a.nome.toLowerCase().includes(q) || a.subpasta.toLowerCase().includes(q));
  }, [arquivos, busca]);

  if (isLoading) {
    return (
      <p className="text-sm text-muted-foreground flex items-center gap-2">
        <Loader2 className="h-4 w-4 animate-spin" /> Lendo os arquivos do Dropbox…
      </p>
    );
  }
  if (error) return <p className="text-sm text-destructive">{(error as Error).message}</p>;
  if (!arquivos?.length) {
    return (
      <p className="text-sm text-muted-foreground">
        Nenhum arquivo deste barco no índice ainda. O sistema lê as pastas a cada 10 minutos; na primeira vez,
        o histórico inteiro pode levar algumas horas.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      <div className="relative max-w-sm">
        <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
        <Input
          value={busca}
          onChange={(e) => setBusca(e.target.value)}
          placeholder="Procurar por nome ou subpasta"
          className="pl-8"
          aria-label="Procurar arquivo"
        />
      </div>
      <p className="text-xs text-muted-foreground">
        {visiveis.length} de {arquivos.length} arquivo(s){arquivos.length >= 500 ? ' (mostrando os 500 mais recentes)' : ''}
      </p>
      <ul className="divide-y rounded-lg border">
        {visiveis.map((a: ArquivoDoBarco) => (
          <li key={a.id} className="flex items-start gap-3 p-2.5 text-sm">
            {IMAGENS.has(a.extensao ?? '')
              ? <ImageIcon className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />
              : <FileText className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />}
            <div className="min-w-0 flex-1">
              <a
                href={linkDoArquivo(a.caminho, a.nome)}
                target="_blank"
                rel="noreferrer"
                className="font-medium hover:underline inline-flex items-center gap-1 break-all"
              >
                {a.nome} <ExternalLink className="h-3 w-3 shrink-0" />
              </a>
              <p className="text-xs text-muted-foreground break-words">
                {a.subpasta || 'pasta principal'} · {dia(a.modificado_em)} · {tamanho(a.tamanho)}
                {a.origem === 'sistema' ? ' · salvo pelo sistema' : ''}
              </p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
