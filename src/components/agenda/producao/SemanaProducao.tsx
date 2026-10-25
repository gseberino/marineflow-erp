/**
 * Agenda › Semana de produção (Fase 3, P7a; plano §7): lista vertical por dia (no desktop, 2 colunas), a carga de cada
 * pessoa no dia ("Roberto 2/2", verde, âmbar ou vermelha), os blocos "OS · cliente · bem · pessoas · dia n de N", a
 * última linha "livre: Roberto tarde", o que o gestor mudou sozinho (com Desfazer) e as decisões que esperam o dono. Tudo
 * sai pronto de agenda_tela_semana; a resposta às decisões é pela conversa.
 *
 * Os estados: carregando, erro (a frase do banco e "Tentar de novo" — nunca "nada marcado"), a tela ainda não instalada
 * no banco (o aviso para usar a Grade) e a semana.
 */
import { AlertCircle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useSemanaProducao, type DiaDaSemana } from '@/hooks/use-agenda-producao';
import { cn } from '@/lib/utils';
import { BarraDeCarga } from './BarraDeCarga';
import { BlocoDaOs } from './BlocoDaOs';
import { MudancasDoGestor } from './MudancasDoGestor';

interface Props {
  /** A segunda-feira da semana (yyyy-mm-dd). */
  de: string;
  onAbrirOs: (osId: string) => void;
}

function Dia({ dia, onAbrirOs }: { dia: DiaDaSemana; onAbrirOs: (osId: string) => void }) {
  return (
    <section
      className={cn('min-w-0 space-y-2 rounded-lg border p-3', dia.hoje && 'ring-1 ring-primary')}
      aria-label={dia.rotulo}
      data-testid={`dia-${dia.dia}`}
    >
      <h3 className={cn('text-xs font-semibold tracking-wide', dia.hoje ? 'text-primary' : 'text-muted-foreground')}>
        {dia.rotulo}
        {dia.hoje && ' · hoje'}
        {dia.feriado && <span className="font-normal"> · {dia.feriado}</span>}
      </h3>
      {dia.pessoas.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {dia.pessoas.map((p) => <BarraDeCarga key={p.payee_id} pessoa={p} />)}
        </div>
      )}
      {dia.blocos.length > 0 ? (
        <div className="space-y-2">
          {dia.blocos.map((b) => <BlocoDaOs key={`${b.os}-${dia.dia}`} bloco={b} onAbrir={onAbrirOs} />)}
        </div>
      ) : (
        !dia.feriado && <p className="text-xs text-muted-foreground">Nada no plano.</p>
      )}
      {dia.livre_texto && <p className="text-xs font-medium text-emerald-700 dark:text-emerald-400">{dia.livre_texto}</p>}
    </section>
  );
}

export function SemanaProducao({ de, onAbrirOs }: Props) {
  const { data, isLoading, error, refetch, isFetching } = useSemanaProducao(de);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center gap-2 py-12 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> Carregando a semana…
      </div>
    );
  }
  if (error) {
    return (
      <div className="space-y-3 py-8 text-center" role="alert">
        <p className="flex items-center justify-center gap-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" aria-hidden />
          <span className="break-words">Não consegui ler a semana: {error instanceof Error ? error.message : String(error)}</span>
        </p>
        <Button size="sm" variant="outline" onClick={() => refetch()} disabled={isFetching}>Tentar de novo</Button>
      </div>
    );
  }
  if (!data) {
    return (
      <p className="py-8 text-center text-sm text-muted-foreground">
        A semana de produção ainda não está instalada no banco. Use a Grade.
      </p>
    );
  }

  return (
    <div className="space-y-4" data-testid="semana-producao">
      <header className="space-y-1">
        <h2 className="break-words text-base font-semibold">{data.titulo}</h2>
        {data.resumo && <p className="break-words text-sm text-muted-foreground">{data.resumo}</p>}
        {data.livre_de_verdade && <p className="break-words text-sm">{data.livre_de_verdade}</p>}
      </header>

      {data.em_teste && (
        <p className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-800 dark:text-amber-300">
          Em teste: nada disto foi publicado nem avisado a ninguém.
        </p>
      )}

      <MudancasDoGestor mudancas={data.mudancas} />

      {data.decisoes.length > 0 && (
        <section className="space-y-2 rounded-lg border border-primary/40 p-3" aria-labelledby="decisoes-abertas">
          <h3 id="decisoes-abertas" className="text-sm font-semibold">Esperando a sua decisão</h3>
          <ul className="space-y-1.5">
            {data.decisoes.map((d) => <li key={d.pergunta_id} className="break-words text-sm">{d.texto}</li>)}
          </ul>
          {data.como_responder && <p className="break-words text-xs text-muted-foreground">{data.como_responder}</p>}
        </section>
      )}

      {data.dias.length > 0 && (
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {data.dias.map((d) => <Dia key={d.dia} dia={d} onAbrirOs={onAbrirOs} />)}
        </div>
      )}
    </div>
  );
}
