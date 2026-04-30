import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MoneyInput } from '@/components/MoneyInput';
import { useCreateExternalQuote } from '@/hooks/use-external-quotes';
import { useProducts } from '@/hooks/use-products';
import { useClients } from '@/hooks/use-clients';
import { Plus, Trash2, Save, ShoppingCart, User, Search } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

export default function ExternalQuoteNewPage() {
  const navigate = useNavigate();
  const createQuote = useCreateExternalQuote();
  const { data: products } = useProducts();
  const { data: clients } = useClients();

  const [clientId, setClientId] = useState('');
  const [vesselId, setVesselId] = useState('');
  const [items, setItems] = useState<any[]>([]);

  const addItem = () => {
    setItems([...items, { product_id: '', quantity: 1, unit_price: 0, product_name: '' }]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_, i) => i !== index));
  };

  const updateItem = (index: number, field: string, value: any) => {
    const newItems = [...items];
    newItems[index][field] = value;
    
    if (field === 'product_id' && value) {
      const p = products?.find(x => x.id === value);
      if (p) {
        newItems[index].unit_price = p.sale_price || 0;
        newItems[index].product_name = p.product_name;
      }
    }
    
    setItems(newItems);
  };

  const calculateTotal = () => {
    return items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);
  };

  const handleSave = async () => {
    if (!clientId || items.length === 0) {
      toast.error('Selecione um cliente e adicione pelo menos um item.');
      return;
    }

    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Não autenticado');

      const total = calculateTotal();
      
      await createQuote.mutateAsync({
        created_by: user.id,
        client_id: clientId,
        vessel_id: vesselId || null,
        status: 'pending_approval',
        discount_amount: 0,
        grand_total: total,
        parts: items.map(it => ({
          product_id: it.product_id || null,
          product_name_snapshot: it.product_name || 'Item manual',
          quantity: it.quantity,
          unit_sale_snapshot: it.unit_price,
          unit_cost_snapshot: 0,
          line_total_sale: it.quantity * it.unit_price,
          line_total_cost: 0
        })),
        services: []
      });

      navigate('/external-quotes');
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 animate-fade-in">
      <PageHeader 
        title="Novo Orçamento Externo" 
        description="Selecione o cliente e adicione os itens para aprovação."
      />

      <Card className="border-primary/10 shadow-sm overflow-hidden">
        <div className="bg-primary/5 p-4 border-b border-primary/10 flex items-center gap-2">
          <User className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-primary">Dados do Cliente</h3>
        </div>
        <CardContent className="p-6 space-y-4">
          <div className="space-y-2">
            <Label>Cliente *</Label>
            <Select value={clientId} onValueChange={setClientId}>
              <SelectTrigger>
                <SelectValue placeholder="Selecione um cliente..." />
              </SelectTrigger>
              <SelectContent>
                {clients?.map(c => (
                  <SelectItem key={c.id} value={c.id}>{c.full_name_or_company_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      <div className="space-y-4">
        <div className="flex justify-between items-center px-1">
          <div className="flex items-center gap-2">
            <ShoppingCart className="h-5 w-5 text-primary" />
            <h3 className="font-semibold">Produtos</h3>
          </div>
          <Button onClick={addItem} variant="outline" size="sm" className="gap-2">
            <Plus className="h-4 w-4" /> Adicionar Item
          </Button>
        </div>

        {items.length === 0 ? (
          <div className="text-center py-12 bg-muted/20 rounded-xl border-2 border-dashed border-muted">
            <p className="text-muted-foreground">Nenhum item adicionado ainda.</p>
            <Button variant="link" onClick={addItem}>Clique para adicionar seu primeiro produto</Button>
          </div>
        ) : (
          <div className="space-y-3">
            {items.map((item, index) => (
              <Card key={index} className="shadow-sm">
                <CardContent className="p-4 space-y-4">
                  <div className="flex justify-between gap-2">
                    <div className="flex-1 space-y-2">
                      <Label className="text-xs">Produto do Catálogo</Label>
                      <Select 
                        value={item.product_id} 
                        onValueChange={v => updateItem(index, 'product_id', v)}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione um produto..." />
                        </SelectTrigger>
                        <SelectContent>
                          {products?.filter(p => p.active).map(p => (
                            <SelectItem key={p.id} value={p.id}>{p.product_name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <Button 
                      variant="ghost" 
                      size="icon" 
                      className="text-destructive mt-6" 
                      onClick={() => removeItem(index)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label className="text-xs">Quantidade</Label>
                      <Input 
                        type="number" 
                        value={item.quantity} 
                        onChange={e => updateItem(index, 'quantity', Number(e.target.value))}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label className="text-xs">Preço Unitário</Label>
                      <MoneyInput 
                        value={item.unit_price} 
                        onValueChange={v => updateItem(index, 'unit_price', v)}
                      />
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>

      {items.length > 0 && (
        <Card className="bg-primary text-primary-foreground border-none">
          <CardContent className="p-6 flex justify-between items-center">
            <div>
              <p className="text-primary-foreground/70 text-sm">Total do Orçamento</p>
              <h2 className="text-3xl font-bold">
                {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(calculateTotal())}
              </h2>
            </div>
            <Button 
              size="lg" 
              variant="secondary" 
              className="gap-2 font-bold"
              onClick={handleSave}
              disabled={createQuote.isPending}
            >
              <Save className="h-5 w-5" />
              {createQuote.isPending ? 'Salvando...' : 'Enviar para Aprovação'}
            </Button>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
