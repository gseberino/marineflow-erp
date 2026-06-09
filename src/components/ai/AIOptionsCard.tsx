import { useState } from 'react';
import { HelpCircle, CheckCircle2, Info, Search } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { ProductFormDialog } from '@/components/ProductFormDialog';

export type OptionItem = { label: string; value: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function ProductDetailButton({ productId }: { productId: string }) {
  const [open, setOpen] = useState(false);
  const [product, setProduct] = useState<any>(null);
  const [fetching, setFetching] = useState(false);

  const handleClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!product && !fetching) {
      setFetching(true);
      const { data } = await supabase
        .from('products')
        .select('*')
        .eq('id', productId)
        .single();
      setProduct(data ?? null);
      setFetching(false);
    }
    setOpen(true);
  };

  return (
    <>
      <button
        onClick={handleClick}
        disabled={fetching}
        className="p-1.5 rounded-md hover:bg-primary/10 transition-colors shrink-0"
        title="Ver cadastro do produto"
        aria-label="Ver cadastro do produto"
      >
        <Info className={`h-3.5 w-3.5 ${fetching ? 'text-muted-foreground/40 animate-pulse' : 'text-muted-foreground hover:text-primary'}`} />
      </button>
      {product && (
        <ProductFormDialog
          open={open}
          onOpenChange={setOpen}
          product={product}
        />
      )}
    </>
  );
}

export function AIOptionsCard({
  question,
  options,
  status,
  onSelect,
  selectedValue,
  entityType,
}: {
  question: string;
  options: OptionItem[];
  status: 'pending' | 'selected';
  onSelect: (value: string, label: string) => void;
  selectedValue?: string;
  entityType?: string;
}) {
  const isProduct = entityType === 'search_products';

  return (
    <div className="rounded-lg border border-border bg-muted/40 overflow-hidden">
      {/* Cabeçalho da pergunta */}
      <div className="flex items-start gap-2 px-3 py-2.5 border-b border-border/60 bg-muted/60">
        <HelpCircle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
        <span className="text-sm font-medium text-foreground leading-snug">{question}</span>
      </div>

      {/* Lista de opções */}
      <div className="divide-y divide-border/40">
        {options.map((opt) => {
          const isSelected = selectedValue === opt.value;
          const isDisabled = status === 'selected' && !isSelected;
          const isRefine = opt.value === '__refine__';
          const canShowInfo = isProduct && !isRefine && UUID_RE.test(opt.value) && status === 'pending';

          return (
            <div
              key={opt.value}
              className={`flex items-center gap-1 transition-colors ${
                isSelected
                  ? 'bg-primary/8 border-l-2 border-l-primary'
                  : isDisabled
                  ? 'opacity-40'
                  : 'hover:bg-background/70'
              }`}
            >
              <button
                className="flex-1 flex items-start gap-2 px-3 py-2.5 text-left disabled:cursor-default"
                disabled={isDisabled}
                onClick={() => status === 'pending' && onSelect(opt.value, opt.label)}
              >
                {isRefine ? (
                  <Search className="h-3.5 w-3.5 text-muted-foreground shrink-0 mt-0.5" />
                ) : isSelected ? (
                  <CheckCircle2 className="h-3.5 w-3.5 text-primary shrink-0 mt-0.5" />
                ) : (
                  <span className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                )}
                <span className={`text-sm leading-snug break-words min-w-0 ${isSelected ? 'text-primary font-medium' : 'text-foreground'}`}>
                  {opt.label}
                </span>
              </button>

              {canShowInfo && <ProductDetailButton productId={opt.value} />}
            </div>
          );
        })}
      </div>
    </div>
  );
}
