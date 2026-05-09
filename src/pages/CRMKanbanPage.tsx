import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { MessageCircle, Calendar, Edit, ArrowRight, Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { Skeleton } from '@/components/ui/skeleton';
import { SendViaZAPIDialog } from '@/components/SendViaZAPIDialog';

const COLUMNS = [
  { id: 'draft', title: 'Oportunidade / Rascunho', color: 'bg-amber-100/50 border-amber-200' },
  { id: 'approved', title: 'Aprovado / Negociação', color: 'bg-blue-100/50 border-blue-200' },
  { id: 'scheduled', title: 'Agendado', color: 'bg-purple-100/50 border-purple-200' },
  { id: 'in_progress', title: 'Em Execução', color: 'bg-orange-100/50 border-orange-200' },
];

export default function CRMKanbanPage() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: orders, isLoading } = useServiceOrders();
  const updateStatus = useUpdateServiceOrderStatus();

  const [zapiTarget, setZapiTarget] = useState<any>(null);
  const [search, setSearch] = useState('');

  if (isLoading) return <div className="p-6 space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-[600px] w-full" /></div>;

  const activeOrders = (orders || []).filter(o => {
    if (!COLUMNS.map(c => c.id).includes(o.status || '')) return false;
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      (o.service_order_number || '').toLowerCase().includes(q) ||
      ((o as any).clients?.name || '').toLowerCase().includes(q) ||
      ((o as any).vessels?.name || '').toLowerCase().includes(q)
    );
  });

  const moveOrder = async (orderId: string, newStatus: string) => {
    await updateStatus.mutateAsync({ id: orderId, status: newStatus as any });
  };

  return (
    <div className="space-y-6 animate-fade-in h-[calc(100vh-80px)] flex flex-col">
      <div className="flex justify-between items-start">
        <PageHeader 
          title="CRM & Funil de Vendas" 
          description="Acompanhe oportunidades, orçamentos e serviços em andamento."
        />
        <div className="flex gap-2 items-center">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input placeholder="Buscar OS, cliente, barco..." className="pl-8 w-56 h-9" value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <Button onClick={() => navigate('/service-orders/new')}>Novo Negócio / OS</Button>
        </div>
      </div>

      <div className="flex-1 overflow-x-auto pb-4">
        <div className="flex gap-4 min-w-max h-full">
          {COLUMNS.map(col => {
            const colOrders = activeOrders.filter(o => o.status === col.id).sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
            const colTotal = colOrders.reduce((sum, o) => sum + (o.grand_total || 0), 0);

            return (
              <div key={col.id} className={`w-80 flex flex-col rounded-xl border ${col.color}`}>
                <div className="p-3 border-b bg-white/50 backdrop-blur-sm rounded-t-xl">
                  <div className="flex justify-between items-center mb-1">
                    <h3 className="font-semibold text-sm">{col.title}</h3>
                    <Badge variant="secondary">{colOrders.length}</Badge>
                  </div>
                  <p className="text-xs text-muted-foreground font-medium">{formatCurrency(colTotal)}</p>
                </div>
                
                <div className="flex-1 p-3 overflow-y-auto space-y-3">
                  {colOrders.map(order => (
                    <Card key={order.id} className="shadow-sm hover:shadow-md transition-shadow cursor-default group">
                      <CardContent className="p-3">
                        <div className="flex justify-between items-start mb-2">
                          <span className="text-xs font-medium text-muted-foreground">OS #{order.service_order_number}</span>
                          <span className="text-xs font-semibold">{formatCurrency(order.grand_total || 0)}</span>
                        </div>
                        <h4 className="font-bold text-sm leading-tight mb-1">{(order as any).clients?.name}</h4>
                        <p className="text-xs text-muted-foreground truncate mb-3">{(order as any).vessels?.name || 'Sem unidade'}</p>
                        
                        <div className="flex items-center gap-2 mb-3">
                          <Button size="icon" variant="ghost" className="h-7 w-7 text-green-600 hover:text-green-700 hover:bg-green-50" onClick={() => setZapiTarget({
                            kind: 'service_order',
                            serviceOrderId: order.id,
                            serviceOrderNumber: order.service_order_number,
                            clientPhone: (order as any).clients?.whatsapp || (order as any).clients?.phone,
                            clientName: (order as any).clients?.name,
                            clientId: (order as any).clients?.id,
                            documentType: order.status === 'draft' ? 'quote' : 'service_order',
                            shareToken: order.share_token
                          })}>
                            <MessageCircle className="h-4 w-4" />
                          </Button>
                          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => navigate(`/service-orders/${order.id}`)}>
                            <Edit className="h-4 w-4" />
                          </Button>
                          {order.scheduled_start_at && (
                            <div className="flex items-center text-xs text-muted-foreground ml-auto">
                              <Calendar className="h-3 w-3 mr-1" />
                              {formatDate(order.scheduled_start_at)}
                            </div>
                          )}
                        </div>

                        <div className="pt-2 border-t flex justify-end">
                          {col.id === 'draft' && <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={() => moveOrder(order.id, 'approved')}>Aprovar <ArrowRight className="h-3 w-3 ml-1"/></Button>}
                          {col.id === 'approved' && <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={() => moveOrder(order.id, 'scheduled')}>Agendar <ArrowRight className="h-3 w-3 ml-1"/></Button>}
                          {col.id === 'scheduled' && <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={() => moveOrder(order.id, 'in_progress')}>Iniciar <ArrowRight className="h-3 w-3 ml-1"/></Button>}
                          {col.id === 'in_progress' && <Button size="sm" variant="ghost" className="h-6 text-xs px-2" onClick={() => moveOrder(order.id, 'completed')}>Concluir <ArrowRight className="h-3 w-3 ml-1"/></Button>}
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                  {colOrders.length === 0 && (
                    <div className="text-center p-4 text-xs text-muted-foreground border-2 border-dashed rounded-lg opacity-50">
                      Nenhuma OS aqui
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {zapiTarget && (
        <SendViaZAPIDialog
          open={!!zapiTarget}
          onOpenChange={(op) => !op && setZapiTarget(null)}
          target={zapiTarget}
        />
      )}
    </div>
  );
}
