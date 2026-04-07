import { useParams } from 'react-router-dom';
import { useServiceOrder } from '@/hooks/use-service-orders';
import { ServiceOrderForm } from '@/components/ServiceOrderForm';
import { Link } from 'react-router-dom';
import { useI18n } from '@/i18n';

export default function ServiceOrderDetail() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const isNew = !id || id === 'new';

  const { data: order, isLoading, error } = useServiceOrder(isNew ? undefined : id);

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

  return (
    <ServiceOrderForm
      orderId={isNew ? undefined : id}
      orderData={order}
      isLoading={isLoading}
    />
  );
}
