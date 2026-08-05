import { useState, useMemo } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { AlertTriangle, Loader2, Package, Plus } from 'lucide-react';
import { toast } from 'sonner';
import {
  useSuggestedMaterials, useApplySurveyMaterials,
} from '@/hooks/use-survey-material-rules';

/**
 * O material que o levantamento indica, para conferir e lançar.
 *
 * O ponto desta tela é a CONFERÊNCIA. A quantidade vem de uma conta feita sobre
 * uma resposta digitada em campo — "2,5 m até o inversor e 2 m até o quadro"
 * tem dois números, e o motor só lê o primeiro. Por isso cada linha carrega o
 * que pode estar errado com ela, ao lado do número e não num rodapé, e nada é
 * lançado sem alguém marcar.
 */
export function SuggestedMaterialsPanel({
  surveyId, serviceOrderId,
}: { surveyId: string; serviceOrderId?: string }) {
  const { data: itens = [], isLoading } = useSuggestedMaterials(surveyId);
  const aplicar = useApplySurveyMaterials();
  // A decisão explícita de quem confere, quando houver. Guardar só os
  // "desmarcados" não serve: a linha com alerta já nasce desmarcada, e clicar
  // nela não teria como se distinguir do estado inicial — o aviso viraria
  // bloqueio em vez de freio.
  const [escolhas, setEscolhas] = useState<Record<string, boolean>>({});

  // Sem decisão, vem marcado o que não tem aviso. Marcar tudo por padrão faria
  // do alerta um enfeite.
  const estaMarcado = (ruleId: string, alerta: string | null, qtd: number | null) =>
    !qtd ? false : escolhas[ruleId] ?? !alerta;

  const alternar = (ruleId: string, valor: boolean) =>
    setEscolhas((s) => ({ ...s, [ruleId]: valor }));

  const escolhidos = useMemo(
    () => itens.filter((i) => estaMarcado(i.rule_id, i.alerta, i.quantity)),
    [itens, escolhas],
  );
  const total = escolhidos.reduce((s, i) => s + Number(i.line_total ?? 0), 0);

  if (isLoading) {
    return <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />;
  }

  if (!itens.length) return null;

  return (
    <div className="space-y-3 rounded-md border p-3">
      <div className="flex items-center gap-2">
        <Package className="h-4 w-4 text-muted-foreground" />
        <p className="text-sm font-medium">Material que este levantamento indica</p>
      </div>

      <div className="divide-y rounded-md border">
        {itens.map((i) => (
          <div key={i.rule_id} className="flex items-start gap-3 p-2.5">
            <Checkbox
              className="mt-0.5 shrink-0"
              checked={estaMarcado(i.rule_id, i.alerta, i.quantity)}
              disabled={!i.quantity}
              onCheckedChange={(v) => alternar(i.rule_id, !!v)}
            />
            <div className="min-w-0 flex-1 space-y-1">
              <p className="text-sm leading-snug">{i.product_name}</p>
              <p className="text-xs text-muted-foreground">
                {i.quantity ?? '—'} {i.unit || ''}
                {i.line_total !== null && (
                  <> · R$ {i.line_total.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}</>
                )}
              </p>
              {/* De onde saiu a conta. Sem isso o número é mágico e ninguém
                  ousa corrigi-lo. */}
              <p className="text-[11px] text-muted-foreground">
                de "{i.answer.length > 70 ? `${i.answer.slice(0, 70)}…` : i.answer}"
              </p>
              {i.alerta && (
                <p className="flex items-start gap-1.5 text-[11px] text-amber-700 dark:text-amber-500">
                  <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />
                  <span>{i.alerta}</span>
                </p>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {escolhidos.length} de {itens.length} · R${' '}
          {total.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
        </span>
        <Button
          size="sm"
          disabled={!escolhidos.length || aplicar.isPending}
          onClick={() =>
            aplicar.mutate(
              { surveyId, serviceOrderId, ruleIds: escolhidos.map((i) => i.rule_id) },
              {
                onSuccess: (r) => toast.success(r.mensagem),
                onError: (e: any) => toast.error(e?.message || 'Erro ao lançar'),
              },
            )}
        >
          <Plus className="mr-1.5 h-4 w-4" />
          Lançar no orçamento
        </Button>
      </div>
    </div>
  );
}
