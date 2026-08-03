import { AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  useServiceSystems, useSetLineSystem, type LineMissingSystem,
} from '@/hooks/use-service-systems';

/**
 * Escolha do sistema para uma linha de serviço genérico, no orçamento.
 *
 * Serviços como "diagnóstico técnico no local" servem a vários sistemas, e é
 * aqui que se diz qual. Não é detalhe de roteiro: o sistema muda o tempo
 * previsto — o mesmo diagnóstico vai de 1h45 (sem sistema) a 3h45 (elétrico DC),
 * porque leva junto a preparação e o fechamento de segurança. Orçamento fechado
 * antes desta resposta subestima o trabalho.
 *
 * O campo já vem com o palpite da regra, mas visível e editável: ela lê o
 * problema relatado e as outras linhas da OS, acerta bastante e erra também.
 */
export function LineSystemPicker({ linha }: { linha: LineMissingSystem }) {
  const { data: sistemas = [] } = useServiceSystems();
  const setLineSystem = useSetLineSystem();

  return (
    <div className="mt-1.5 space-y-1 rounded-md border border-amber-500/50 bg-amber-50 p-2 dark:bg-amber-950/30">
      <p className="flex items-start gap-1.5 text-[11px] leading-snug">
        <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
        <span>
          Este serviço atende a vários sistemas. Escolha qual, para o tempo previsto e o roteiro
          saírem certos.
        </span>
      </p>
      <Select
        defaultValue={linha.sistema_sugerido ?? undefined}
        onValueChange={(sistema) =>
          setLineSystem.mutate({ lineId: linha.line_id, system: sistema }, {
            onSuccess: () => toast.success('Sistema definido para esta linha.'),
            onError: (e: any) => toast.error(e?.message || 'Erro ao definir'),
          })
        }
      >
        <SelectTrigger className="h-8 w-full text-xs sm:w-64">
          <SelectValue placeholder="O que este serviço toca?" />
        </SelectTrigger>
        <SelectContent>
          {sistemas.map((s) => (
            <SelectItem key={s.slug} value={s.slug}>{s.name}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {linha.sistema_sugerido && linha.motivo_sugestao && (
        <p className="text-[10px] text-muted-foreground">
          Sugerido {linha.motivo_sugestao} — confira antes de confirmar.
        </p>
      )}
    </div>
  );
}
