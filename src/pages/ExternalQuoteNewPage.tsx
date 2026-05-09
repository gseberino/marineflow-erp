import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MoneyInput } from '@/components/MoneyInput';
import { useAuth } from '@/hooks/use-auth';
import { useCreateExternalQuote } from '@/hooks/use-external-quotes';
import { useProducts } from '@/hooks/use-products';
import { Plus, Trash2, Save, ShoppingCart, User, Phone, Anchor, AlertCircle } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useQuery } from '@tanstack/react-query';

export default function ExternalQuoteNewPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const createQuote = useCreateExternalQuote();
  const { data: products } = useProducts();

  const [leadName, setLeadName] = useState('');
  const [leadPhone, setLeadPhone] = useState('');
  const [leadId, setLeadId] = useState<string | 'new'>('new');
  const [vesselName, setVesselName] = useState('');
  const [items, setItems] = useState<any[]>([]);

  // Fetch only leads created by the current user
  const { data: myLeads } = useQuery({
    queryKey: ['my-leads'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return [];
      const { data, error } = await supabase
        .from('external_quote_leads')
        .select('*')
        .eq('created_by', user.id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    }
  });

  // Autofill if existing lead is selected
  useEffect(() => {
    if (leadId !== 'new' && myLeads) {
      const l = myLeads.find(x => x.id === leadId);
      if (l) {
        setLeadName(l.name);
        setLeadPhone(l.phone || '');
        setVesselName(l.name || '');
      }
    } else {
      setLeadName('');
      setLeadPhone('');
      setVesselName('');
    }
  }, [leadId, myLeads]);

  const addItem = () => {
    setItems([...items, { product_id: '', quantity: 1, unit_price: 0, name: '' }]);
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
        newItems[index].name = p.name;
      }
    }
    
    setItems(newItems);
  };

  const calculateTotal = () => {
    return items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);
  };

  const handleSave = async () => {
    if (!leadName || items.length === 0) {
      toast.error('Informe o nome do prospecto e adicione pelo menos um item.');
      return;
    }

    try {
      if (!user) throw new Error('Não autenticado');

      let currentLeadId = leadId !== 'new' ? leadId : null;


      // Se for 'new', criamos um novo lead no banco
      if (leadId === 'new') {
        const { data: newLead, error: leadError } = await supabase
          .from('external_quote_leads')
          .insert([{
            created_by: user.id,
            type: 'person',
            name: leadName,
            phone: leadPhone,
            boat_name: vesselName
          } as any])
          .select()
          .single();

        if (leadError) throw leadError;
        currentLeadId = newLead.id;
      }

      const total = calculateTotal();
      
      await createQuote.mutateAsync({
        created_by: user.id,
        lead_id: currentLeadId,
        status: 'pending_approval',
        discount_amount: 0,
        grand_total: total,
        parts: items.map(it => ({
          product_id: it.product_id || null,
          name_snapshot: it.name || 'Item manual',
          quantity: it.quantity,
          unit_sale_snapshot: it.unit_price,
          unit_cost_snapshot: 0,
          line_total_sale: it.quantity * it.unit_price,
          line_total_cost: 0
        })),
        services: []
      });

      navigate('/external-quotes');
    } catch (e: any) {
      console.error(e);
      toast.error('Erro ao salvar: ' + e.message);
    }
  };

  const [duplicateWarning, setDuplicateWarning] = useState<string | null>(null);

  // Duplicate Check Logic
  useEffect(() => {
    const checkDuplicate = async () => {
      if ((leadName.length < 3 && leadPhone.length < 5) || leadId !== 'new') {
        setDuplicateWarning(null);
        return;
      }

      try {
        // Check in Clients
        const { data: existingClients } = await supabase
          .from('clients')
          .select('name, phone')
          .or(`name.ilike.%${leadName}%,phone.eq.${leadPhone}`)
          .limit(1);

        if (existingClients && existingClients.length > 0) {
          setDuplicateWarning(`Atenção: Já existe um CLIENTE cadastrado com nome ou telefone similar: "${existingClients[0].name}"`);
          return;
        }

        // Check in other Leads
        const { data: existingLeads } = await supabase
          .from('external_quote_leads')
          .select('name, phone')
          .or(`name.ilike.%${leadName}%,phone.eq.${leadPhone}`)
          .neq('id', leadId === 'new' ? '00000000-0000-0000-0000-000000000000' : leadId)
          .limit(1);

        if (existingLeads && existingLeads.length > 0) {
          setDuplicateWarning(`Atenção: Já existe um PROSPECTO com dados similares: "${existingLeads[0].name}"`);
        } else {
          setDuplicateWarning(null);
        }
      } catch (e) {
        console.error('Erro na verificação de duplicidade', e);
      }
    };

    const timer = setTimeout(checkDuplicate, 500);
    return () => clearTimeout(timer);
  }, [leadName, leadPhone, leadId]);

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 animate-fade-in">
      <PageHeader 
        title="Novo Orçamento Externo" 
        description="Adicione dados do prospecto e os itens para enviar para aprovação."
      />

      {duplicateWarning && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 flex items-start gap-3 text-amber-800 animate-in fade-in slide-in-from-top-2">
          <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
          <div className="text-sm">
            <p className="font-bold">Possível Duplicidade</p>
            <p>{duplicateWarning}</p>
            <p className="mt-1 text-xs opacity-70 italic">Considere vincular ao registro existente se for a mesma pessoa.</p>
          </div>
        </div>
      )}

      <Card className="border-primary/10 shadow-sm overflow-hidden">
        <div className="bg-primary/5 p-4 border-b border-primary/10 flex items-center gap-2">
          <User className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-primary">Dados do Cliente/Lead</h3>
        </div>
        <CardContent className="p-6 space-y-4">
          {myLeads && myLeads.length > 0 && (
            <div className="space-y-2 mb-4 pb-4 border-b">
              <Label>Selecionar Prospecto Existente</Label>
              <Select value={leadId} onValueChange={setLeadId}>
                <SelectTrigger>
                  <SelectValue placeholder="Criar novo prospecto..." />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="new">+ Criar Novo Prospecto</SelectItem>
                  {myLeads.map(l => (
                    <SelectItem key={l.id} value={l.id}>{l.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Nome do Cliente *</Label>
              <Input 
                value={leadName} 
                onChange={e => setLeadName(e.target.value)} 
                placeholder="Ex: João Silva"
                disabled={leadId !== 'new'}
              />
            </div>
            <div className="space-y-2">
              <Label>WhatsApp/Telefone</Label>
              <div className="relative">
                <Phone className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
                <Input 
                  className="pl-9"
                  value={leadPhone} 
                  onChange={e => setLeadPhone(e.target.value)} 
                  placeholder="5521999998888"
                  disabled={leadId !== 'new'}
                />
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Label>Embarcação (Opcional)</Label>
            <div className="relative">
              <Anchor className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
              <Input 
                className="pl-9"
                value={vesselName} 
                onChange={e => setVesselName(e.target.value)} 
                placeholder="Ex: My Pearl 300"
                disabled={leadId !== 'new'}
              />
            </div>
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
                        value={item.product_id || 'manual'} 
                        onValueChange={v => updateItem(index, 'product_id', v === 'manual' ? '' : v)}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione um produto..." />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="manual">-- Produto Manual --</SelectItem>
                          {products?.filter(p => p.active).map(p => (
                            <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
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
                      <Label className="text-xs">Descrição do Produto *</Label>
                      <Input 
                        value={item.name} 
                        onChange={e => updateItem(index, 'name', e.target.value)}
                        placeholder="Descreva o produto/peça"
                      />
                    </div>
                  )}

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
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
