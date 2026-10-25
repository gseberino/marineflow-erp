/**
 * Agenda › Carteira de produção (Fase 3, P7a; plano §7): o quadro de exceções — o que está parado e por quê, por estado,
 * com a idade e quem trava. O filtro é o MultiFilterBar (padrão das listas), com um grupo "Situação" de 9 opções e o
 * número de cada uma, e a busca pelo número, o cliente ou o bem. Tudo pronto de agenda_tela_carteira.
 */
import { useMemo } from 'react';
import { AlertCircle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { useCarteiraProducao } from '@/hooks/use-agenda-producao';
import { CartaoDaCarteira } from './CartaoDaCarteira';

const FILTROS_INICIAIS = { grupo: [] as string[], search: '' };

export function CarteiraProducao({ onAbrirOs }: { onAbrirOs: (osId: string) => void }) {
  const { data, isLoading, error, refetch, isFetching } = useCarteiraProducao();
  const mf = useMultiFilter(FILTROS_INICIAIS);

  const rotulos = useMemo(() => new Map((data?.grupos ?? []).map((g) => [g.chave, g.rotulo])), [data]);
  const cartoes = useMemo(() => {
    const grupos = mf.filters.grupo as string[];
    const busca = String(mf.filters.search ?? '').trim().toLowerCase();
    return (data?.cartoes ?? []).filter((c) =>
      (grupos.length === 0 || grupos.includes(c.grupo))
      && (!busca || [c.numero, c.cliente, c.bem].some((x) => (x ?? '').toLowerCase().includes(busca))));
  }, [data, mf.filters]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center gap-2 py-12 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> Carregando a carteira…
      </div>
    );
  }
  if (error) {
    return (
      <div className="space-y-3 py-8 text-center" role="alert">
        <p className="flex items-center justify-center gap-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" aria-hidden />
          <span className="break-words">Não consegui ler a carteira: {error instanceof Error ? error.message : String(error)}</span>
        </p>
        <Button size="sm" variant="outline" onClick={() => refetch()} disabled={isFetching}>Tentar de novo</Button>
      </div>
    );
  }
  if (!data) {
    return (
      <p className="py-8 text-center text-sm text-muted-foreground">
        A carteira de produção ainda não está instalada no banco. Use a Grade.
      </p>
    );
  }

  return (
    <div className="space-y-3" data-testid="carteira-producao">
      <MultiFilterBar
        filters={mf.filters}
        activeCount={mf.activeCount}
        onToggle={mf.toggle}
        onSetField={mf.setField}
        onClearAll={mf.clearAll}
        search={String(mf.filters.search ?? '')}
        onSearchChange={(v) => mf.setField('search', v)}
        searchPlaceholder="Buscar OS, cliente ou bem…"
        groups={[{
          type: 'multi', field: 'grupo', label: 'Situação',
          options: data.grupos.map((g) => ({ value: g.chave, label: `${g.rotulo} (${g.n})` })),
        }]}
      />
      {cartoes.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted-foreground">
          {data.cartoes.length === 0 ? 'Nada parado na carteira.' : 'Nenhuma OS com esse filtro.'}
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-2 lg:grid-cols-2">
          {cartoes.map((c) => (
            <CartaoDaCarteira key={c.os} cartao={c} rotuloDoGrupo={rotulos.get(c.grupo) ?? c.grupo} onAbrir={onAbrirOs} />
          ))}
        </div>
      )}
    </div>
  );
}
