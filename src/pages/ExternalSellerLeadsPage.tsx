import { useState, useEffect } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { 
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter 
} from '@/components/ui/dialog';
import { User, Phone, Anchor, Search, Plus, Filter, AlertCircle, Loader2 } from 'lucide-react';
import { useAuth } from '@/hooks/use-auth';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export default function ExternalSellerLeadsPage() {
  const { user } = useAuth();
  const [searchTerm, setSearchTerm] = useState('');
  const [isAddOpen, setIsAddOpen] = useState(false);
  const queryClient = useQueryClient();

  const [newLead, setNewLead] = useState({
    name: '',
    phone: '',
    vessel: ''
  });

  const { data: leads, isLoading } = useQuery({
    queryKey: ['my-leads-full', user?.id],
    queryFn: async () => {
      if (!user) return [];
      const { data, error } = await supabase
        .from('external_quote_leads')
        .select('*')
        .eq('created_by', user.id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!user
  });

  const createLeadMutation = useMutation({
    mutationFn: async (vars: typeof newLead) => {
      if (!user) throw new Error('Não autenticado');

      const { data, error } = await supabase
        .from('external_quote_leads')
        .insert([{
          created_by: user.id,
          type: 'person',
          full_name_or_company_name: vars.name,
          phone: vars.phone,
          boat_name: vars.vessel
        } as any])
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['my-leads-full'] });
      toast.success('Prospecto cadastrado com sucesso!');
      setIsAddOpen(false);
      setNewLead({ name: '', phone: '', vessel: '' });
    },
    onError: (e: any) => {
      toast.error('Erro ao cadastrar: ' + e.message);
    }
  });

  const filteredLeads = leads?.filter(l => 
    l.full_name_or_company_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    l.phone?.includes(searchTerm) ||
    l.boat_name?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Meus Prospectos" 
        description="Gerencie os leads cadastrados para seus orçamentos externos."
      >
        <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2">
              <Plus className="h-4 w-4" /> Novo Prospecto
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Cadastrar Novo Prospecto</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label>Nome Completo *</Label>
                <Input 
                  value={newLead.name} 
                  onChange={e => setNewLead({...newLead, name: e.target.value})}
                  placeholder="Nome do cliente"
                />
              </div>
              <div className="space-y-2">
                <Label>WhatsApp / Telefone</Label>
                <Input 
                  value={newLead.phone} 
                  onChange={e => setNewLead({...newLead, phone: e.target.value})}
                  placeholder="Ex: 5521999998888"
                />
              </div>
              <div className="space-y-2">
                <Label>Embarcação (Opcional)</Label>
                <Input 
                  value={newLead.vessel} 
                  onChange={e => setNewLead({...newLead, vessel: e.target.value})}
                  placeholder="Ex: My Pearl 300"
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancelar</Button>
              <Button 
                onClick={() => createLeadMutation.mutate(newLead)}
                disabled={!newLead.name || createLeadMutation.isPending}
              >
                {createLeadMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Cadastrar'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </PageHeader>

      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input 
            placeholder="Buscar por nome, telefone ou embarcação..." 
            className="pl-9"
            value={searchTerm}
            onChange={e => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1,2,3].map(i => <div key={i} className="h-40 rounded-xl bg-muted animate-pulse" />)}
        </div>
      ) : filteredLeads?.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-12 text-center">
            <User className="h-12 w-12 text-muted-foreground mb-4 opacity-20" />
            <h3 className="font-semibold text-lg">Nenhum prospecto encontrado</h3>
            <p className="text-sm text-muted-foreground">Clique em "Novo Prospecto" para começar.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredLeads?.map(lead => (
            <Card key={lead.id} className="hover:shadow-md transition-shadow group">
              <CardContent className="p-5 space-y-4">
                <div className="flex justify-between items-start">
                  <div className="space-y-1">
                    <h3 className="font-bold text-lg group-hover:text-primary transition-colors">
                      {lead.full_name_or_company_name}
                    </h3>
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Phone className="h-3.5 w-3.5" />
                      {lead.phone || 'Sem telefone'}
                    </div>
                  </div>
                  <Badge variant={lead.promoted_client_id ? "default" : "secondary"} className={lead.promoted_client_id ? "bg-emerald-600 hover:bg-emerald-700" : ""}>
                    {lead.promoted_client_id ? "Convertido" : "Lead"}
                  </Badge>
                </div>

                {lead.boat_name && (
                  <div className="flex items-center gap-2 text-sm bg-primary/5 p-2 rounded-lg text-primary font-medium">
                    <Anchor className="h-4 w-4" />
                    {lead.boat_name}
                  </div>
                )}

                <div className="pt-2 border-t flex justify-between items-center text-xs text-muted-foreground">
                  <span>Cadastrado em {new Date(lead.created_at).toLocaleDateString()}</span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
