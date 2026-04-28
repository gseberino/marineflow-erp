import { usePriceSuggestions, useApplyPriceSuggestion } from '@/hooks/use-products';
import { useI18n } from '@/i18n';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { TrendingUp, Check, X, AlertTriangle, ArrowRight } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';

export function PriceSuggestionAlert() {
  const { formatCurrency } = useI18n();
  const { data: suggestions, isLoading } = usePriceSuggestions();
  const applyMutation = useApplyPriceSuggestion();
  const qc = useQueryClient();

  if (isLoading || !suggestions || suggestions.length === 0) return null;

  const handleIgnore = async (id: string) => {
    const { error } = await supabase
      .from('price_update_suggestions')
      .update({ status: 'ignored' })
      .eq('id', id);
    
    if (error) {
      toast.error('Erro ao ignorar sugestão');
    } else {
      qc.invalidateQueries({ queryKey: ['price-suggestions'] });
    }
  };

  return (
    <div className="space-y-3 mb-6 animate-in slide-in-from-top-4 duration-500">
      <div className="flex items-center gap-2 text-amber-600 mb-1">
        <AlertTriangle className="h-4 w-4" />
        <h3 className="text-sm font-semibold">Sugestões de Ajuste de Preço</h3>
        <Badge variant="outline" className="bg-amber-50 text-amber-700 border-amber-200 ml-1">
          {suggestions.length} {suggestions.length === 1 ? 'pendente' : 'pendentes'}
        </Badge>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {suggestions.slice(0, 3).map((s: any) => (
          <Card key={s.id} className="border-amber-200 bg-amber-50/20 shadow-sm overflow-hidden">
            <CardContent className="p-4">
              <div className="flex justify-between items-start mb-2">
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate">{(s.products as any)?.product_name}</p>
                  <p className="text-[10px] text-muted-foreground truncate">SKU: {(s.products as any)?.sku || '—'}</p>
                </div>
                <TrendingUp className="h-4 w-4 text-amber-500 shrink-0" />
              </div>
              
              <div className="flex items-center gap-2 mb-3 text-xs">
                <div className="bg-background px-2 py-1 rounded border">
                   <span className="text-muted-foreground block text-[9px]">Atual</span>
                   <span className="font-mono">{formatCurrency(s.current_sale_price)}</span>
                </div>
                <ArrowRight className="h-3 w-3 text-muted-foreground" />
                <div className="bg-emerald-50 text-emerald-800 px-2 py-1 rounded border border-emerald-100">
                   <span className="text-emerald-600 block text-[9px]">Sugerido</span>
                   <span className="font-bold font-mono">{formatCurrency(s.suggested_sale_price)}</span>
                </div>
              </div>

              <div className="flex justify-between items-center gap-2">
                <p className="text-[10px] text-amber-700 font-medium">Margem: {s.margin_percent}%</p>
                <div className="flex gap-1">
                  <Button 
                    size="sm" 
                    variant="ghost" 
                    className="h-7 w-7 p-0 text-muted-foreground hover:text-destructive"
                    onClick={() => handleIgnore(s.id)}
                  >
                    <X className="h-3.5 w-3.5" />
                  </Button>
                  <Button 
                    size="sm" 
                    className="h-7 gap-1 bg-emerald-600 hover:bg-emerald-700 text-[11px]"
                    onClick={() => applyMutation.mutate({
                      suggestionId: s.id,
                      productId: s.product_id,
                      newPrice: s.suggested_sale_price
                    })}
                    disabled={applyMutation.isPending}
                  >
                    <Check className="h-3.5 w-3.5" /> Aplicar
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
        {suggestions.length > 3 && (
          <div className="flex items-center justify-center p-4 rounded-xl border border-dashed border-amber-200 bg-amber-50/5">
            <p className="text-xs text-muted-foreground">E outras {suggestions.length - 3} sugestões...</p>
          </div>
        )}
      </div>
    </div>
  );
}
