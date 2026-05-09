import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Search, Package, CheckCircle2, XCircle, Info, ShoppingCart } from 'lucide-react';
import { useProducts } from '@/hooks/use-products';
import { useI18n } from '@/i18n';

export default function ExternalProductCatalogPage() {
  const { data: products, isLoading } = useProducts();
  const { formatCurrency } = useI18n();
  const [searchTerm, setSearchTerm] = useState('');

  const filteredProducts = products?.filter(p => 
    p.active && (
      p.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.category?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.sku?.toLowerCase().includes(searchTerm.toLowerCase())
    )
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Catálogo de Produtos" 
        description="Consulte a disponibilidade e preços dos produtos para venda externa."
      />

      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input 
          placeholder="Buscar produtos por nome, categoria ou código..." 
          className="pl-9 h-12 text-lg"
          value={searchTerm}
          onChange={e => setSearchTerm(e.target.value)}
        />
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {[1,2,3,4,5,6,7,8].map(i => <div key={i} className="h-48 rounded-xl bg-muted animate-pulse" />)}
        </div>
      ) : filteredProducts?.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <Package className="h-12 w-12 text-muted-foreground mb-4 opacity-20" />
            <h3 className="font-semibold text-lg">Nenhum produto encontrado</h3>
            <p className="text-sm text-muted-foreground">Tente buscar por outros termos.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filteredProducts?.map(product => {
            const isAvailable = (product.stock_quantity || 0) > 0;
            return (
              <Card key={product.id} className="overflow-hidden border-primary/5 hover:border-primary/20 transition-all group">
                <CardContent className="p-0">
                  <div className="p-5 space-y-4">
                    <div className="flex justify-between items-start gap-2">
                      <div className="space-y-1 min-w-0">
                        <Badge variant="outline" className="text-[10px] uppercase tracking-wider font-bold opacity-70">
                          {product.category || 'Geral'}
                        </Badge>
                        <h3 className="font-bold text-base leading-tight group-hover:text-primary transition-colors truncate">
                          {product.name}
                        </h3>
                      </div>
                    </div>

                    <div className="flex items-baseline gap-1">
                      <span className="text-2xl font-black text-primary">
                        {formatCurrency(product.sale_price || 0)}
                      </span>
                      <span className="text-[10px] text-muted-foreground font-medium uppercase">Preço Venda</span>
                    </div>

                    <div className="pt-4 border-t flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        {isAvailable ? (
                          <div className="flex items-center gap-1 text-emerald-600 font-bold text-xs">
                            <CheckCircle2 className="h-3.5 w-3.5" />
                            Disponível
                          </div>
                        ) : (
                          <div className="flex items-center gap-1 text-destructive font-bold text-xs">
                            <XCircle className="h-3.5 w-3.5" />
                            Indisponível
                          </div>
                        )}
                        <span className="text-[10px] text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
                          {product.stock_quantity || 0} em estoque
                        </span>
                      </div>
                      
                      {!isAvailable && (
                        <div className="group relative">
                          <Info className="h-4 w-4 text-muted-foreground cursor-help" />
                          <div className="absolute bottom-full right-0 mb-2 w-48 p-2 bg-popover text-popover-foreground text-[10px] rounded shadow-lg border opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-10">
                            Produto indisponível no momento. Preço exibido é baseado na última prática.
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                  
                  <div className="bg-muted/30 px-5 py-3 flex items-center justify-between text-[10px] font-medium text-muted-foreground">
                    <span>SKU: {product.sku || '—'}</span>
                    <ShoppingCart className="h-3 w-3 opacity-30" />
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
