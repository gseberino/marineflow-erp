import { useParams } from 'react-router-dom';
import { useServiceOrder } from '@/hooks/use-service-orders';
import { ServiceOrderForm } from '@/components/ServiceOrderForm';
import { ServiceOrderTimeline } from '@/components/ServiceOrderTimeline';
import { Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useRecordHistory } from '@/hooks/use-audit-log';
import { Badge } from '@/components/ui/badge';
import { History, Link2, Check } from 'lucide-react';
import { useState } from 'react';
import { toast } from 'sonner';

function TimelineTab({ id }: { id: string }) {
  const { data: history } = useRecordHistory('service_orders', id);
  const count = history?.length ?? 0;
  return (
    <TabsTrigger value="timeline" className="flex items-center gap-1.5">
      <History className="h-3.5 w-3.5" />
      Histórico
      {count > 0 && (
        <Badge variant="secondary" className="h-4 min-w-4 px-1 text-[10px] leading-none">
          {count}
        </Badge>
      )}
    </TabsTrigger>
  );
}

export default function ServiceOrderDetail() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const isNew = !id || id === 'new';

  const { data: order, isLoading, error } = useServiceOrder(isNew ? undefined : id);

  // Hook must be declared before any conditional return (Rules of Hooks)
  const [copied, setCopied] = useState(false);

  const handleCopyLink = () => {
    if (!order?.share_token) return;
    const url = `${window.location.origin}/view/${order.share_token}`;
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true);
      toast.success('Link público copiado!');
      setTimeout(() => setCopied(false), 2000);
    });
  };

  if (!isNew && !isLoading && !order && !error) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <p className="text-muted-foreground">{t.serviceOrders.notFound}</p>
        <Link to="/service-orders" className="text-accent hover:underline mt-2">{t.serviceOrders.backToList}</Link>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <p className="text-destructive">Erro ao carregar ordem de serviço</p>
        <Link to="/service-orders" className="text-accent hover:underline mt-2">{t.serviceOrders.backToList}</Link>
      </div>
    );
  }

  // For new OS, just show the form without tabs
  if (isNew) {
    return (
      <ServiceOrderForm
        orderId={undefined}
        orderData={undefined}
        isLoading={false}
      />
    );
  }

  return (
    <Tabs defaultValue="details" className="flex flex-col gap-0">
      <div className="border-b bg-background px-4 lg:px-6 sticky top-0 z-10 flex items-center justify-between">
        <TabsList className="h-10 bg-transparent p-0 gap-4">
          <TabsTrigger
            value="details"
            className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:shadow-none data-[state=active]:text-primary px-1 pb-2 h-10 bg-transparent"
          >
            Detalhes da OS
          </TabsTrigger>
          {id && (
            <TimelineTab id={id} />
          )}
        </TabsList>
        {order?.share_token && (
          <button
            onClick={handleCopyLink}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors pb-1"
            title="Copiar link público da OS"
          >
            {copied ? <Check className="h-3.5 w-3.5 text-emerald-600" /> : <Link2 className="h-3.5 w-3.5" />}
            {copied ? 'Copiado!' : 'Link público'}
          </button>
        )}
      </div>

      <TabsContent value="details" className="mt-0">
        <ServiceOrderForm
          orderId={id}
          orderData={order}
          isLoading={isLoading}
        />
      </TabsContent>

      <TabsContent value="timeline" className="mt-0 p-4 lg:p-6">
        <div className="max-w-2xl">
          <h2 className="text-lg font-semibold mb-1">Histórico de alterações</h2>
          <p className="text-sm text-muted-foreground mb-6">
            Todas as alterações registradas nesta OS em ordem cronológica.
          </p>
          <ServiceOrderTimeline orderId={id} />
        </div>
      </TabsContent>
    </Tabs>
  );
}
