import { AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  useServiceSystems, useServiceVerbs, useSetLineClassification,
  type LineMissingSystem,
} from '@/hooks/use-service-systems';

/**
 * Classificação da linha de serviço, no orçamento.
 *
 * Serve a dois casos que parecem diferentes e são o mesmo:
 *   · serviço genérico do catálogo ("diagnóstico no local") — falta o sistema;
 *   · linha digitada à mão, sem serviço nenhum — falta tudo, e é dela que
 *     dependem três das maiores OS abertas, hoje invisíveis para o roteiro.
 *
 * O sistema muda o tempo previsto (o mesmo diagnóstico vai de 1h45 a 3h45,
 * porque carrega a preparação e o fechamento de segurança), então isto não é
 * detalhe de execução: é o que faz o orçamento fechar no valor certo.
 *
 * A confiança do palpite aparece na tela. Lido no texto da própria linha é
 * forte; deduzido do problema da OS é fraco, e a frase diz isso — palpite
 * fraco com cara de certeza é convite a confirmar sem ler.
 */
export function LineSystemPicker({ linha }: { linha: LineMissingSystem }) {
  const { data: sistemas = [] } = useServiceSystems();
  const { data: verbos = [] } = useServiceVerbs();
  const salvar = useSetLineClassification();

  const faltaSistema = !linha.sistema_sugerido || linha.origem_sistema !== 'linha';
  const precisaVerbo = !linha.service_verb;

  return (
    <div className="mt-1.5 space-y-1.5 rounded-md border border-amber-500/50 bg-amber-50 p-2 dark:bg-amber-950/30">
      <p className="flex items-start gap-1.5 text-[11px] leading-snug">
        <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
        <span>
          Sem classificação, esta linha não entra no roteiro e o tempo previsto sai menor do que o
          trabalho.
        </span>
      </p>

      <div className="flex flex-wrap items-center gap-2">
        <Select
          defaultValue={linha.sistema_sugerido ?? undefined}
          onValueChange={(sistema) =>
            salvar.mutate({ lineId: linha.line_id, system: sistema }, {
              onSuccess: () => toast.success('Sistema definido.'),
              onError: (e: any) => toast.error(e?.message || 'Erro ao definir'),
            })
          }
        >
          <SelectTrigger className="h-8 w-full text-xs sm:w-56">
            <SelectValue placeholder="Sistema / categoria" />
          </SelectTrigger>
          <SelectContent>
            {sistemas.map((s) => (
              <SelectItem key={s.slug} value={s.slug}>{s.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>

        {precisaVerbo && (
          <Select
            defaultValue={linha.verbo_sugerido ?? undefined}
            onValueChange={(verbo) =>
              salvar.mutate({ lineId: linha.line_id, verb: verbo }, {
                onSuccess: () => toast.success('Tipo de serviço definido.'),
                onError: (e: any) => toast.error(e?.message || 'Erro ao definir'),
              })
            }
          >
            <SelectTrigger className="h-8 w-full text-xs sm:w-48">
              <SelectValue placeholder="O que se faz" />
            </SelectTrigger>
            <SelectContent>
              {verbos.map((v) => (
                <SelectItem key={v.slug} value={v.slug}>{v.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
      </div>

      {linha.sistema_sugerido && (
        <p className="text-[10px] text-muted-foreground">
          {linha.origem_sistema === 'linha'
            ? 'Sugerido pelo texto desta linha.'
            : 'Palpite fraco, tirado do contexto da OS — confira com atenção.'}
        </p>
      )}
      {!linha.sistema_sugerido && faltaSistema && (
        <p className="text-[10px] text-muted-foreground">
          A regra não arriscou um palpite aqui — escolha você.
        </p>
      )}
    </div>
  );
}
