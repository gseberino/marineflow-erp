// Triagem de fotos (Fase 4 do Dropbox, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
// As fotos que o dono manda do celular para "Envio da câmera", agrupadas por dia. Para cada dia, o
// sistema lista as OS prováveis e diz POR QUÊ; o dono marca as fotos, escolhe a OS e confirma.
// As fotos são MOVIDAS para "<pasta do barco>/3- FOTOS/AAAA-MM-DD OS-xxxxx" e ligadas à OS.
// Prints de tela (PNG) ficam escondidos por padrão.
import { useMemo, useState } from 'react';
import { Camera, ChevronDown, ChevronRight, FolderInput, Loader2, RefreshCw, Video } from 'lucide-react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  type FotoNaCaixa,
  type OsSugerida,
  useFotosDaCaixa,
  useMiniaturas,
  useMoverFotos,
  useOsRecentes,
  useSugestoes,
} from '@/hooks/use-triagem-fotos';

const SEM_DIA = 'sem-data';

function rotuloDoDia(dia: string): string {
  if (dia === SEM_DIA) return 'Sem data';
  const d = new Date(`${dia}T12:00:00`);
  return d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' });
}

function GrupoDoDia({
  dia, fotos, sugeridas, aberto, onAlternar,
}: {
  dia: string;
  fotos: FotoNaCaixa[];
  sugeridas: OsSugerida[];
  aberto: boolean;
  onAlternar: () => void;
}) {
  const [marcadas, setMarcadas] = useState<Set<string>>(() => new Set(fotos.map((f) => f.id)));
  const [escolha, setEscolha] = useState<string>('');
  const { data: miniaturas, isLoading: carregando } = useMiniaturas(fotos.map((f) => f.id), aberto);
  const { data: recentes } = useOsRecentes();
  const mover = useMoverFotos();

  const alvo = escolha || sugeridas[0]?.id || '';
  const rotuloDoAlvo = useMemo(() => {
    const s = sugeridas.find((x) => x.id === alvo);
    if (s) return `${s.numero} · ${s.barco ?? '—'}`;
    const r = recentes?.find((x) => x.id === alvo);
    return r ? `${r.service_order_number} · ${r.vessels?.name ?? '—'}` : '';
  }, [alvo, sugeridas, recentes]);

  const alternarFoto = (id: string) =>
    setMarcadas((m) => {
      const n = new Set(m);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });

  const confirmar = () => {
    const itens = fotos.filter((f) => marcadas.has(f.id)).map((f) => ({ id: f.id, nome: f.nome, dia: f.dia ?? dia }));
    if (!itens.length || !alvo) return;
    mover.mutate({ itens, order_id: alvo }, {
      onSuccess: (r) => {
        if (r.pendente) toast.info(r.aviso ?? 'O Dropbox ainda está movendo.');
        else toast.success(`${r.movidas} foto(s) em ${r.destino}${r.falharam ? ` · ${r.falharam} falharam` : ''}`);
      },
      onError: (e) => toast.error((e as Error).message || 'Não consegui mover as fotos.'),
    });
  };

  return (
    <section className="rounded-xl border bg-card">
      <button
        type="button"
        onClick={onAlternar}
        className="w-full flex items-center gap-2 p-3 text-left"
        aria-expanded={aberto}
      >
        {aberto ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
        <span className="font-semibold capitalize">{rotuloDoDia(dia)}</span>
        <span className="text-sm text-muted-foreground">· {fotos.length} arquivo(s)</span>
        {!aberto && sugeridas[0] && (
          <span className="ml-auto text-xs text-muted-foreground truncate">provável: {sugeridas[0].numero} · {sugeridas[0].barco ?? '—'}</span>
        )}
      </button>

      {aberto && (
        <div className="border-t p-3 space-y-4">
          {carregando && (
            <p className="text-sm text-muted-foreground flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Carregando miniaturas…</p>
          )}
          <ul className="grid grid-cols-3 sm:grid-cols-5 lg:grid-cols-8 gap-2">
            {fotos.map((f) => (
              <li key={f.id}>
                <label className="block cursor-pointer">
                  <div className={`relative aspect-square rounded-md overflow-hidden border-2 ${marcadas.has(f.id) ? 'border-primary' : 'border-transparent opacity-50'}`}>
                    {miniaturas?.[f.id]
                      ? <img src={`data:image/jpeg;base64,${miniaturas[f.id]}`} alt={f.nome} className="h-full w-full object-cover" />
                      : <div className="h-full w-full bg-muted flex items-center justify-center">{f.tipo === 'video' ? <Video className="h-5 w-5" /> : <Camera className="h-5 w-5" />}</div>}
                    <Checkbox
                      checked={marcadas.has(f.id)}
                      onCheckedChange={() => alternarFoto(f.id)}
                      className="absolute top-1 left-1 bg-background"
                      aria-label={`Marcar ${f.nome}`}
                    />
                  </div>
                  <span className="block text-[11px] text-muted-foreground mt-0.5">{f.hora ?? ''}{f.tipo === 'video' ? ' · vídeo' : f.tipo === 'print' ? ' · print' : ''}</span>
                </label>
              </li>
            ))}
          </ul>

          <div className="space-y-2">
            <p className="text-sm font-medium">Estas fotos são de qual OS?</p>
            {sugeridas.length > 0 ? (
              <div className="space-y-1">
                {sugeridas.map((s) => (
                  <label key={s.id} className="flex items-start gap-2 text-sm cursor-pointer">
                    <input
                      type="radio"
                      name={`os-${dia}`}
                      checked={alvo === s.id}
                      onChange={() => setEscolha(s.id)}
                      className="mt-1"
                    />
                    <span>
                      <strong>{s.numero}</strong> · {s.barco ?? '—'} · {s.cliente ?? '—'}
                      <span className="block text-xs text-muted-foreground">{s.motivos.join(' · ')}</span>
                    </span>
                  </label>
                ))}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">Nenhuma OS com sinal nesse dia. Escolha abaixo.</p>
            )}
            <div className="max-w-md">
              <Label className="text-xs text-muted-foreground">Outra OS</Label>
              <Select value={sugeridas.some((s) => s.id === alvo) ? '' : alvo} onValueChange={setEscolha}>
                <SelectTrigger aria-label="Escolher outra OS"><SelectValue placeholder="Procurar entre as OS recentes" /></SelectTrigger>
                <SelectContent>
                  {(recentes ?? []).map((o) => (
                    <SelectItem key={o.id} value={o.id}>
                      {o.service_order_number} · {o.vessels?.name ?? '—'} · {o.clients?.name ?? '—'}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <Button onClick={confirmar} disabled={!alvo || marcadas.size === 0 || mover.isPending}>
              {mover.isPending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <FolderInput className="h-4 w-4 mr-2" />}
              Mover {marcadas.size} para {rotuloDoAlvo || '…'}
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setMarcadas(new Set())}>Desmarcar todas</Button>
            <Button variant="ghost" size="sm" onClick={() => setMarcadas(new Set(fotos.map((f) => f.id)))}>Marcar todas</Button>
          </div>
        </div>
      )}
    </section>
  );
}

export default function TriagemFotosPage() {
  const { data, isLoading, error, refetch, isFetching } = useFotosDaCaixa();
  const [verPrints, setVerPrints] = useState(false);
  const [abertos, setAbertos] = useState<Set<string>>(new Set());

  const grupos = useMemo(() => {
    const porDia = new Map<string, FotoNaCaixa[]>();
    for (const f of data?.itens ?? []) {
      if (f.tipo === 'outro') continue;
      if (f.tipo === 'print' && !verPrints) continue;
      const dia = f.dia ?? SEM_DIA;
      const lista = porDia.get(dia) ?? [];
      lista.push(f);
      porDia.set(dia, lista);
    }
    return [...porDia.entries()].sort((a, b) => b[0].localeCompare(a[0]));
  }, [data, verPrints]);

  const dias = useMemo(() => grupos.map(([d]) => d).filter((d) => d !== SEM_DIA), [grupos]);
  const { data: sugestoes } = useSugestoes(dias);
  const prints = (data?.itens ?? []).filter((f) => f.tipo === 'print').length;

  const alternar = (dia: string) =>
    setAbertos((a) => {
      const n = new Set(a);
      if (n.has(dia)) n.delete(dia);
      else n.add(dia);
      return n;
    });

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader
        title="Triagem de fotos"
        description="As fotos que você manda do celular para o Dropbox (Envio da câmera), por dia. Escolha a OS e o sistema leva as fotos para a pasta do barco."
      />
      <div className="flex flex-wrap items-center gap-3">
        <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
          <RefreshCw className={`h-4 w-4 mr-2 ${isFetching ? 'animate-spin' : ''}`} /> Atualizar
        </Button>
        <label className="flex items-center gap-2 text-sm">
          <Checkbox checked={verPrints} onCheckedChange={(v) => setVerPrints(v === true)} aria-label="Mostrar prints de tela" />
          Mostrar prints de tela ({prints})
        </label>
        {data && <span className="text-sm text-muted-foreground">{data.itens.length} arquivo(s) na caixa</span>}
      </div>

      {isLoading && <p className="text-sm text-muted-foreground flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Lendo o Envio da câmera…</p>}
      {error && <p className="text-sm text-destructive">{(error as Error).message}</p>}
      {data && grupos.length === 0 && <p className="text-sm text-muted-foreground">Nada para triar. 🎉</p>}

      <div className="space-y-2">
        {grupos.map(([dia, fotos]) => (
          <GrupoDoDia
            key={dia}
            dia={dia}
            fotos={fotos}
            sugeridas={sugestoes?.[dia] ?? []}
            aberto={abertos.has(dia)}
            onAlternar={() => alternar(dia)}
          />
        ))}
      </div>
    </div>
  );
}
