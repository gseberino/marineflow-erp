import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Link } from 'react-router-dom';
import { Anchor, Loader2, ArrowRight, ShieldCheck, LogOut, Ship } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { statusConfig } from '@/lib/constants';
import { useI18n } from '@/i18n';
import { toast } from 'sonner';

export default function ClientPortal() {
  const { t, formatCurrency, formatDate } = useI18n();
  const [identifier, setIdentifier] = useState('');
  const [loading, setLoading] = useState(false);
  const [clientData, setClientData] = useState<any>(null);
  const [orders, setOrders] = useState<any[]>([]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!identifier || identifier.trim().length < 5) {
      toast.error('Por favor, insira um documento ou telefone válido.');
      return;
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('client-portal', {
        body: { identifier: identifier.trim() },
      });

      if (error) throw error;
      if (data.error) throw new Error(data.error);

      setClientData(data.client);
      setOrders(data.orders || []);
      toast.success(`Bem-vindo, ${data.client.name}`);
    } catch (err: any) {
      console.error(err);
      toast.error(err.message || 'Dados não encontrados. Verifique o número e tente novamente.');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    setClientData(null);
    setOrders([]);
    setIdentifier('');
  };

  if (!clientData) {
    return (
      <div className="min-h-screen bg-muted/30 flex items-center justify-center p-4">
        <Card className="w-full max-w-md shadow-lg border-primary/10">
          <CardHeader className="text-center pb-2">
            <div className="mx-auto w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mb-4 text-primary">
              <Anchor className="h-8 w-8" />
            </div>
            <CardTitle className="text-2xl font-bold">Portal do Cliente</CardTitle>
            <CardDescription className="text-base">
              Acompanhe suas Ordens de Serviço
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleLogin} className="space-y-4 pt-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">CPF, CNPJ, Telefone ou Email</label>
                <Input 
                  placeholder="Digite aqui para acessar..." 
                  value={identifier}
                  onChange={(e) => setIdentifier(e.target.value)}
                  className="h-12"
                  autoFocus
                />
              </div>
              <Button type="submit" className="w-full h-12 text-md" disabled={loading}>
                {loading ? <Loader2 className="h-5 w-5 animate-spin mr-2" /> : <ShieldCheck className="h-5 w-5 mr-2" />}
                Acessar Portal
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-muted/30 pb-12">
      {/* Header do Portal */}
      <div className="bg-card border-b sticky top-0 z-10 shadow-sm">
        <div className="max-w-5xl mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2 text-primary font-bold">
            <Anchor className="h-5 w-5" />
            <span>Portal do Cliente</span>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-sm font-medium hidden sm:inline-block">
              {clientData.name}
            </span>
            <Button variant="ghost" size="sm" onClick={handleLogout} className="text-muted-foreground hover:text-foreground">
              <LogOut className="h-4 w-4 mr-1.5" /> Sair
            </Button>
          </div>
        </div>
      </div>

      {/* Conteúdo */}
      <div className="max-w-5xl mx-auto px-4 mt-8">
        <h1 className="text-2xl font-bold mb-6">Minhas Ordens de Serviço</h1>

        {orders.length === 0 ? (
          <div className="text-center py-16 bg-card border border-dashed rounded-xl">
            <p className="text-muted-foreground">Você ainda não possui Ordens de Serviço registradas.</p>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {orders.map((o) => (
              <Card key={o.id} className="hover:shadow-md transition-shadow group flex flex-col">
                <CardHeader className="pb-3 border-b">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <CardTitle className="text-lg text-primary">{o.service_order_number}</CardTitle>
                      <p className="text-xs text-muted-foreground mt-1">
                        Aberto em {formatDate(o.created_at)}
                      </p>
                    </div>
                    <StatusBadge className={statusConfig[o.status as keyof typeof statusConfig]?.className ?? ''}>
                      {(t.status as Record<string, string>)[o.status] ?? o.status}
                    </StatusBadge>
                  </div>
                </CardHeader>
                <CardContent className="pt-4 flex-1 flex flex-col justify-between">
                  <div className="space-y-3 mb-6">
                    {o.vessels && (
                      <div className="flex items-center text-sm text-muted-foreground">
                        <Ship className="h-4 w-4 mr-2" />
                        {o.vessels.name}
                      </div>
                    )}
                    <div className="text-sm">
                      <span className="text-muted-foreground">Valor Total:</span>{' '}
                      <span className="font-semibold">{formatCurrency(o.grand_total ?? 0)}</span>
                    </div>
                  </div>
                  
                  <Link to={`/view/${o.share_token}`} target="_blank" className="w-full">
                    <Button variant="outline" className="w-full group-hover:border-primary group-hover:text-primary transition-colors">
                      Abrir Documento <ArrowRight className="h-4 w-4 ml-2 opacity-50 group-hover:opacity-100 transition-opacity" />
                    </Button>
                  </Link>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
