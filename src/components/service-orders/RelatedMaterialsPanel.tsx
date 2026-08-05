import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Link2, Loader2, Plus } from 'lucide-react';
import { toast } from 'sonner';

/**
 * "Quem levou isso, levou aquilo."
 *
 * A Tela GX Touch entrou em 5 das 5 ordens que tiveram o Cerbo GX; o Porta
 * Fusível MIDI apareceu em 3 das 4 que tiveram o Kit de Cabos. Não é a máquina
 * adivinhando — é a própria casa, medida.
 *
 * Por isso a contagem aparece em cada linha, e não um selo de "recomendado":
 * é a evidência que se julga. "5 de 5" e "3 de 4" pedem decisões diferentes, e
 * esconder a diferença atrás de uma palavra tiraria de quem lê a única coisa
 * que importa.
 */

export interface RelatedMaterial {
  product_id: string;
  product_name: string;
  unit: string | null;
  sale_price: number;
  por_causa_de: string;
  juntos: number;
  de_total: number;
  pct: number;
}

export function useRelatedMaterials(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['related-materials', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async (): Promise<RelatedMaterial[]> => {
      const { data, error } = await supabase.rpc('related_materials', {
        p_service_order_id: serviceOrderId!,
      });
      if (error) throw error;
      return (data || []) as unknown as RelatedMaterial[];
    },
  });
}

function useAddRelated(serviceOrderId?: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (item: RelatedMaterial) => {
      const { data: prod } = await supabase
        .from('products').select('cost_price, sale_price').eq('id', item.product_id).single();
      const custo = Number(prod?.cost_price ?? 0);
      const venda = Number(prod?.sale_price ?? 0);

      const { error } = await supabase.from('service_order_parts').insert({
        service_order_id: serviceOrderId!,
        product_id: item.product_id,
        quantity: 1,
        unit_cost_snapshot: custo,
        unit_sale_snapshot: venda,
        line_total_cost: custo,
        line_total_sale: venda,
        source: 'ai',
        notes: `Costuma acompanhar: ${item.por_causa_de} (${item.juntos} de ${item.de_total})`,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['related-materials', serviceOrderId] });
      qc.invalidateQueries({ queryKey: ['service-order-parts', serviceOrderId] });
      qc.invalidateQueries({ queryKey: ['service-order', serviceOrderId] });
      toast.success('Item lançado. Confira a quantidade.');
    },
    onError: (e: any) => toast.error(e?.message || 'Erro ao lançar'),
  });
}

export function RelatedMaterialsPanel({ serviceOrderId }: { serviceOrderId?: string }) {
  const { data: itens = [], isLoading } = useRelatedMaterials(serviceOrderId);
  const adicionar = useAddRelated(serviceOrderId);

  if (isLoading) return <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />;
  if (!itens.length) return null;

  return (
    <div className="space-y-2 rounded-md border p-3">
      <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <Link2 className="h-3.5 w-3.5" /> Costuma entrar junto
      </p>
      <div className="divide-y rounded-md border">
        {itens.map((i) => (
          <div key={i.product_id} className="flex items-start gap-3 p-2.5">
            <div className="min-w-0 flex-1 space-y-0.5">
              <p className="text-sm leading-snug">{i.product_name}</p>
              <p className="text-xs text-muted-foreground">
                <strong>{i.juntos} de {i.de_total}</strong> vez(es) que você usou{' '}
                {i.por_causa_de.length > 40 ? `${i.por_causa_de.slice(0, 40)}…` : i.por_causa_de}
                {i.sale_price > 0 && (
                  <> · R$ {i.sale_price.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}</>
                )}
              </p>
            </div>
            <Button
              size="sm" variant="outline" className="h-7 shrink-0 text-xs"
              disabled={adicionar.isPending}
              onClick={() => adicionar.mutate(i)}
            >
              <Plus className="mr-1 h-3 w-3" /> Incluir
            </Button>
          </div>
        ))}
      </div>
      {/* A quantidade é sempre 1: o histórico diz que o item costuma vir junto,
          não quantos vêm. Chutar a quantidade seria inventar onde o dado
          silencia. */}
      <p className="text-[11px] text-muted-foreground">
        Entram com quantidade 1 — o histórico diz que costumam vir junto, não quantos.
      </p>
    </div>
  );
}
