import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Loader2, Ship, User, MapPin, FileText, Wrench, Package } from 'lucide-react';

const fmtCurrency = (n: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(n || 0);

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('pt-BR') : '—';

interface PublicData {
  order: any;
  client: any;
  vessel: any;
  parts: any[];
  services: any[];
  company: Record<string, string>;
}

export default function PublicServiceOrderView() {
  const { token } = useParams<{ token: string }>();
  const [data, setData] = useState<PublicData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;

    (async () => {
      try {
        const { data: order, error: orderErr } = await supabase
          .from('service_orders')
          .select('*')
          .eq('share_token', token)
          .maybeSingle();

        if (orderErr) throw orderErr;
        if (!order) {
          if (!cancelled) {
            setError('Documento não encontrado ou link inválido.');
            setLoading(false);
          }
          return;
        }

        const [clientRes, vesselRes, partsRes, servicesRes, settingsRes] = await Promise.all([
          supabase.from('clients').select('*').eq('id', order.client_id).maybeSingle(),
          order.vessel_id
            ? supabase.from('vessels').select('*').eq('id', order.vessel_id).maybeSingle()
            : Promise.resolve({ data: null, error: null }),
          supabase
            .from('service_order_parts')
            .select('*, products(product_name, sku)')
            .eq('service_order_id', order.id),
          supabase
            .from('service_order_services')
            .select('*')
            .eq('service_order_id', order.id),
          supabase.from('app_settings').select('key, value'),
        ]);

        const company: Record<string, string> = {};
        for (const row of (settingsRes.data || []) as Array<{ key: string; value: string }>) {
          if (row.key) company[row.key] = String(row.value || '');
        }

        if (!cancelled) {
          setData({
            order,
            client: clientRes.data,
            vessel: vesselRes.data,
            parts: partsRes.data || [],
            services: servicesRes.data || [],
            company,
          });
          setLoading(false);
        }
      } catch (e: any) {
        if (!cancelled) {
          setError(e.message || 'Erro ao carregar documento.');
          setLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [token]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-muted/30">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-muted/30 p-6">
        <Card className="max-w-md w-full">
          <CardHeader>
            <CardTitle>Documento indisponível</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              {error || 'Não foi possível carregar este documento.'}
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  const { order, client, vessel, parts, services, company } = data;

  return (
    <div className="min-h-screen bg-muted/30 py-8 px-4">
      <div className="max-w-4xl mx-auto space-y-6">
        {/* Company Header */}
        <Card>
          <CardContent className="pt-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h1 className="text-2xl font-bold">{company.company_name || 'MarineFlow'}</h1>
                {company.cnpj && (
                  <p className="text-sm text-muted-foreground">CNPJ: {company.cnpj}</p>
                )}
                {(company.phone || company.email) && (
                  <p className="text-sm text-muted-foreground">
                    {[company.phone, company.email].filter(Boolean).join(' • ')}
                  </p>
                )}
              </div>
              <div className="text-left sm:text-right">
                <Badge variant="secondary" className="text-base px-3 py-1">
                  {order.service_order_number}
                </Badge>
                <p className="text-xs text-muted-foreground mt-1">
                  Emissão: {fmtDate(order.created_at)}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Order Info */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-lg">
              <FileText className="h-5 w-5" />
              Ordem de Serviço
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
              <div>
                <p className="text-muted-foreground">Status</p>
                <p className="font-medium capitalize">{order.status?.replace(/_/g, ' ')}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Prioridade</p>
                <p className="font-medium capitalize">{order.priority}</p>
              </div>
              {order.scheduled_start_at && (
                <div>
                  <p className="text-muted-foreground">Agendamento</p>
                  <p className="font-medium">{fmtDate(order.scheduled_start_at)}</p>
                </div>
              )}
              {order.service_type && (
                <div>
                  <p className="text-muted-foreground">Tipo de Serviço</p>
                  <p className="font-medium">{order.service_type}</p>
                </div>
              )}
            </div>

            {order.problem_description && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Descrição do Problema</p>
                <p className="text-sm whitespace-pre-wrap">{order.problem_description}</p>
              </div>
            )}

            {order.customer_visible_report && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Relatório</p>
                <p className="text-sm whitespace-pre-wrap">{order.customer_visible_report}</p>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Client & Vessel */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {client && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <User className="h-5 w-5" />
                  Cliente
                </CardTitle>
              </CardHeader>
              <CardContent className="text-sm space-y-1">
                <p className="font-medium">{client.full_name_or_company_name}</p>
                {client.cpf_cnpj && <p className="text-muted-foreground">{client.cpf_cnpj}</p>}
                {client.phone && <p className="text-muted-foreground">{client.phone}</p>}
                {client.email && <p className="text-muted-foreground">{client.email}</p>}
              </CardContent>
            </Card>
          )}
          {vessel && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Ship className="h-5 w-5" />
                  Embarcação
                </CardTitle>
              </CardHeader>
              <CardContent className="text-sm space-y-1">
                <p className="font-medium">{vessel.boat_name}</p>
                {(vessel.manufacturer || vessel.model) && (
                  <p className="text-muted-foreground">
                    {[vessel.manufacturer, vessel.model].filter(Boolean).join(' ')}
                    {vessel.year ? ` (${vessel.year})` : ''}
                  </p>
                )}
                {vessel.hull_id_or_registration && (
                  <p className="text-muted-foreground flex items-center gap-1">
                    <MapPin className="h-3 w-3" /> {vessel.hull_id_or_registration}
                  </p>
                )}
              </CardContent>
            </Card>
          )}
        </div>

        {/* Services */}
        {services.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <Wrench className="h-5 w-5" />
                Serviços
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                {services.map((s) => (
                  <div key={s.id} className="flex justify-between gap-4 text-sm py-2 border-b last:border-0">
                    <div className="flex-1">
                      <p className="font-medium">{s.service_name_snapshot}</p>
                      {s.description_snapshot && (
                        <p className="text-xs text-muted-foreground">{s.description_snapshot}</p>
                      )}
                      <p className="text-xs text-muted-foreground">
                        {s.quantity} × {fmtCurrency(s.unit_price_snapshot)}
                      </p>
                    </div>
                    <p className="font-medium tabular-nums">{fmtCurrency(s.line_total)}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Parts */}
        {parts.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <Package className="h-5 w-5" />
                Peças
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                {parts.map((p) => (
                  <div key={p.id} className="flex justify-between gap-4 text-sm py-2 border-b last:border-0">
                    <div className="flex-1">
                      <p className="font-medium">{p.products?.product_name || '—'}</p>
                      {p.products?.sku && (
                        <p className="text-xs text-muted-foreground">SKU: {p.products.sku}</p>
                      )}
                      <p className="text-xs text-muted-foreground">
                        {p.quantity} × {fmtCurrency(p.unit_sale_snapshot)}
                      </p>
                    </div>
                    <p className="font-medium tabular-nums">{fmtCurrency(p.line_total_sale)}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Totals */}
        <Card>
          <CardContent className="pt-6 space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Mão de obra</span>
              <span className="tabular-nums">{fmtCurrency(order.labor_cost_total)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Peças</span>
              <span className="tabular-nums">{fmtCurrency(order.parts_cost_total)}</span>
            </div>
            {order.travel_cost_total > 0 && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Deslocamento</span>
                <span className="tabular-nums">{fmtCurrency(order.travel_cost_total)}</span>
              </div>
            )}
            {order.operational_cost_total > 0 && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Custos operacionais</span>
                <span className="tabular-nums">{fmtCurrency(order.operational_cost_total)}</span>
              </div>
            )}
            {order.discount_amount > 0 && (
              <div className="flex justify-between text-destructive">
                <span>Desconto</span>
                <span className="tabular-nums">- {fmtCurrency(order.discount_amount)}</span>
              </div>
            )}
            {order.tax_amount > 0 && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Impostos</span>
                <span className="tabular-nums">{fmtCurrency(order.tax_amount)}</span>
              </div>
            )}
            <Separator className="my-2" />
            <div className="flex justify-between text-lg font-bold">
              <span>Total</span>
              <span className="tabular-nums">{fmtCurrency(order.grand_total)}</span>
            </div>
            {order.payment_conditions && (
              <p className="text-xs text-muted-foreground pt-2">
                Condições: {order.payment_conditions}
              </p>
            )}
          </CardContent>
        </Card>

        <p className="text-center text-xs text-muted-foreground py-4">
          Documento gerado por {company.company_name || 'MarineFlow'}
        </p>
      </div>
    </div>
  );
}
