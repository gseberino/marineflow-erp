import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MoneyInput } from '@/components/MoneyInput';
import { useCreateExternalQuote, type ClientType } from '@/hooks/use-external-quotes';
import { useProducts } from '@/hooks/use-products';
import { Plus, Trash2, Save, ShoppingCart, User, Phone, Anchor } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

export default function ExternalQuoteNewPage() {
  const navigate = useNavigate();
  const createQuote = useCreateExternalQuote();
  const { data: products } = useProducts();

  const [clientName, setClientName] = useState('');
  const [clientPhone, setClientPhone] = useState('');
  const [clientType, setClientType] = useState<ClientType>('person');
  const [vesselName, setVesselName] = useState('');
  const [items, setItems] = useState<any[]>([]);

  const addItem = () => {
    setItems([...items, { product_id: '', quantity: 1, unit_price: 0, product_name_manual: '' }]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_, i) => i !== index));
  };

  const updateItem = (index: number, field: string, value: any) => {
    const newItems = [...items];
    newItems[index][field] = value;
    
    // Se selecionou um produto existente, preenche o preço
    if (field === 'product_id' && value) {
      const p = products?.find(x => x.id === value);
      if (p) {
        newItems[index].unit_price = p.sale_price || 0;
        newItems[index].product_name_manual = p.product_name;
      }
    }
    
    setItems(newItems);
  };

  const calculateTotal = () => {
    return items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);
  };

  const handleSave = async () => {
    if (!clientName || !clientPhone || items.length === 0) {
      toast.error('Preencha os dados do cliente e adicione pelo menos um item.');
      return;
    }

    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Não autenticado');

      const total = calculateTotal();
      
      await createQuote.mutateAsync({
        seller_user_id: user.id,
        client_name: clientName,
        client_phone: clientPhone,
        client_type: clientType,
        vessel_name: vesselName || undefined,
        status: 'pending_approval',
        subtotal: total,
        grand_total: total,
        items: items.map(it => ({
          product_id: it.product_id || null,
          product_name_manual: it.product_name_manual,
          quantity: it.quantity,
          unit_price: it.unit_price,
          status: it.product_id ? 'ok' : 'pending_product_registration'
        }))
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
        description="Preencha os dados abaixo para enviar um orçamento para aprovação."
      />

      <Card className="border-primary/10 shadow-sm overflow-hidden">
        <div className="bg-primary/5 p-4 border-b border-primary/10 flex items-center gap-2">
          <User className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-primary">Dados do Cliente</h3>
        </div>
        <CardContent className="p-6 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Nome do Cliente *</Label>
              <Input 
                value={clientName} 
                onChange={e => setClientName(e.target.value)} 
                placeholder="Ex: João Silva"
              />
            </div>
            <div className="space-y-2">
              <Label>WhatsApp/Telefone *</Label>
              <div className="relative">
                <Phone className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
                <Input 
                  className="pl-9"
                  value={clientPhone} 
                  onChange={e => setClientPhone(e.target.value)} 
                  placeholder="5521999998888"
                />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Tipo de Cliente</Label>
              <Select value={clientType} onValueChange={(v: ClientType) => setClientType(v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="person">Pessoa Física</SelectItem>
                  <SelectItem value="vessel">Embarcação</SelectItem>
                  <SelectItem value="motorhome">Motorhome</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {clientType !== 'person' && (
              <div className="space-y-2">
                <Label>Nome da {clientType === 'vessel' ? 'Embarcação' : 'Unidade'}</Label>
                <div className="relative">
                  <Anchor className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
                  <Input 
                    className="pl-9"
                    value={vesselName} 
                    onChange={e => setVesselName(e.target.value)} 
                    placeholder="Ex: My Pearl 300"
                  />
                </div>
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      <div className="space-y-4">
        <div className="flex justify-between items-center px-1">
          <div className="flex items-center gap-2">
            <ShoppingCart className="h-5 w-5 text-primary" />
            <h3 className="font-semibold">Produtos e Serviços</h3>
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
                      <Label className="text-xs">Produto do Catálogo (Opcional)</Label>
                      <Select 
                        value={item.product_id} 
                        onValueChange={v => updateItem(index, 'product_id', v)}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione um produto..." />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="">-- Produto Não Listado --</SelectItem>
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

                  {!item.product_id && (
                    <div className="space-y-2">
                      <Label className="text-xs">Nome do Produto Manual *</Label>
                      <Input 
                        value={item.product_name_manual} 
                        onChange={e => updateItem(index, 'product_name_manual', e.target.value)}
                        placeholder="Descreva o produto ou serviço"
                      />
                    </div>
                  )}

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
