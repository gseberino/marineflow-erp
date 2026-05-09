import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Loader2, Ship, User, MapPin, FileText, Wrench, Package, Download, CheckCircle2, AlertTriangle, PenLine, Image as ImageIcon, CreditCard, ExternalLink } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { generatePDF, generatePDFBlob, DEFAULT_PDF_OPTIONS, type PDFData } from '@/lib/pdf-generator';
import { SignaturePad } from '@/components/SignaturePad';
import { computeDocumentHash } from '@/lib/document-hash';
import { toast } from 'sonner';

const fmtCurrency = (n: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(n || 0);

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('pt-BR') : '—';

const fmtDateTime = (d?: string | null) =>
  d ? new Date(d).toLocaleString('pt-BR') : '—';

const isOn = (v?: string) => (v ?? 'true').toLowerCase() !== 'false';

interface Signature {
  id: string;
  signature_image_url: string | null;
  accepted_name: string;
  signed_at: string;
  superseded_at: string | null;
  document_hash: string;
}

interface PublicData {
  order: any;
  client: any;
  vessel: any;
  parts: any[];
  services: any[];
  company: Record<string, string>;
  signature: Signature | null;
  presetData: { label: string | null; installments: number | null } | null;
}

export default function PublicServiceOrderView() {
  const { token } = useParams<{ token: string }>();
  const [data, setData] = useState<PublicData | null>(null);
  const [logoUrl, setLogoUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  // Estado de assinatura
  const [acceptedName, setAcceptedName] = useState('');
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [signaturePng, setSignaturePng] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    setLoading(true);

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

        const [clientRes, vesselRes, partsRes, servicesRes, settingsRes, sigRes, presetRes] = await Promise.all([
          supabase.from('clients').select('*').eq('id', order.client_id).maybeSingle(),
          order.vessel_id
            ? supabase.from('vessels').select('*').eq('id', order.vessel_id).maybeSingle()
            : Promise.resolve({ data: null, error: null }),
          supabase
            .from('service_order_parts')
            .select('*, products(name, sku)')
            .eq('service_order_id', order.id),
          supabase
            .from('service_order_services')
            .select('*')
            .eq('service_order_id', order.id),
          supabase.from('app_settings').select('key, value'),
          supabase
            .from('service_order_signatures')
            .select('id, signature_image_url, accepted_name, signed_at, superseded_at, document_hash')
            .eq('service_order_id', order.id)
            .is('superseded_at', null)
            .order('signed_at', { ascending: false })
            .limit(1)
            .maybeSingle(),
          (order as any).payment_condition_preset_id
            ? supabase
                .from('payment_condition_presets')
                .select('label, installments')
                .eq('id', (order as any).payment_condition_preset_id)
                .maybeSingle()
            : Promise.resolve({ data: null, error: null }),
        ]);

        const company: Record<string, string> = {};
        for (const row of (settingsRes.data || []) as Array<{ key: string; value: string }>) {
          if (row.key) company[row.key] = String(row.value || '');
        }

        if (!cancelled) {
          setLogoUrl(company.company_logo_url || null);
          setData({
            order,
            client: clientRes.data,
            vessel: vesselRes.data,
            parts: partsRes.data || [],
            services: servicesRes.data || [],
            company,
            signature: (sigRes.data as Signature) || null,
            presetData: presetRes?.data || null,
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
  }, [token, reload]);

  // Texto consolidado dos termos (mesma lógica do PDF)
  const termsText = useMemo(() => {
    if (!data) return '';
    const c = data.company;
    return [
      c.terms_general,
      c.terms_warranty,
      c.terms_cancellation,
      c.terms_delivery,
      c.terms_responsibilities,
    ].filter(Boolean).join('\n\n');
  }, [data]);

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

  const { order, client, vessel, parts, services, company, signature } = data;

  // Toggles de exibição (settings)
  const show = {
    servicePrices: isOn(company.public_view_show_service_prices),
    partsPrices: isOn(company.public_view_show_parts_prices),
    travelCost: isOn(company.public_view_show_travel_cost),
    discount: isOn(company.public_view_show_discount),
    tax: isOn(company.public_view_show_tax),
    terms: isOn(company.public_view_show_terms),
    bankDetails: isOn(company.public_view_show_bank_details),
    paymentInstructions: isOn(company.public_view_show_payment_instructions),
    extraNotes: isOn(company.public_view_show_extra_notes),
    validity: isOn(company.public_view_show_validity),
    allowSignature: isOn(company.public_view_allow_signature),
  };

  const isSigned = !!order.signed_at && !order.requires_resignature;
  const needsResignature = !!order.requires_resignature;

  const buildPdfData = (): PDFData => {
    const get = (k: string) => company[k] || '';
    return {
      documentType: 'service_order',
      company: {
        name: get('company_name') || 'MarineFlow',
        address: [get('address_line_1'), get('address_number')].filter(Boolean).join(', '),
        city: get('city'),
        state: get('state'),
        postal_code: get('postal_code'),
        phone: get('phone'),
        email: get('email'),
        cnpj: get('cnpj'),
      },
      bank: {
        bank_name: get('bank_name') || undefined,
        bank_agency: get('bank_agency') || undefined,
        bank_account: get('bank_account') || undefined,
        pix_key: get('pix_key') || undefined,
      },
      serviceOrder: {
        service_order_number: order.service_order_number,
        status: order.status,
        created_at: order.created_at,
        scheduled_start_at: order.scheduled_start_at ?? undefined,
        problem_description: order.problem_description ?? undefined,
        technical_notes: order.technician_notes ?? undefined,
        grand_total: order.grand_total || 0,
        labor_cost_total: order.labor_cost_total || 0,
        parts_cost_total: order.parts_cost_total || 0,
        travel_cost_total: order.travel_cost_total || 0,
        discount_amount: order.discount_amount || 0,
        tax_amount: order.tax_amount || 0,
        operational_cost_total: order.operational_cost_total || 0,
        extra_notes: order.extra_notes ?? undefined,
        payment_conditions: order.payment_conditions ?? undefined,
        payment_condition_label: data?.presetData?.label ?? null,
        payment_condition_installments: data?.presetData?.installments ?? null,
        subcontract_cost_total: (order as any).subcontract_cost_total || 0,
      },
      client: {
        name: client?.name || '—',
        cpf_cnpj: client?.cpf_cnpj ?? undefined,
        phone: client?.phone ?? undefined,
        email: client?.email ?? undefined,
        address: [client?.address_line_1, client?.city, client?.state].filter(Boolean).join(', ') || undefined,
      },
      vessel: vessel ? {
        name: vessel.name,
        manufacturer: vessel.manufacturer ?? undefined,
        model: vessel.model ?? undefined,
        year: vessel.year ?? undefined,
        registration: vessel.hull_id_or_registration ?? undefined,
      } : undefined,
      services: services.map((s: any) => ({
        name: s.name_snapshot || '—',
        description: s.description_snapshot ?? undefined,
        billing_unit: s.billing_unit_snapshot || 'unit',
        quantity: s.quantity || 1,
        unit_price: s.unit_price_snapshot || 0,
        line_total: s.line_total || 0,
      })),
      parts: parts.map((p: any) => ({
        name: p.products?.name || '—',
        sku: p.products?.sku ?? undefined,
        quantity: p.quantity || 1,
        unit_price: p.unit_sale_snapshot || 0,
        line_total: p.line_total_sale || 0,
      })),
      terms: termsText || undefined,
    };
  };

  const handleDownloadPDF = () => {
    generatePDF(buildPdfData(), DEFAULT_PDF_OPTIONS);
  };

  const handleSubmitSignature = async () => {
    if (!acceptedName.trim() || acceptedName.trim().length < 3) {
      toast.error('Informe seu nome completo.');
      return;
    }
    if (!acceptedTerms) {
      toast.error('Você precisa marcar o aceite dos termos.');
      return;
    }
    if (!signaturePng) {
      toast.error('Desenhe sua assinatura no campo indicado.');
      return;
    }

    setSubmitting(true);
    try {
      const hash = await computeDocumentHash(
        order,
        services.map((s: any) => ({
          name: s.name_snapshot,
          qty: s.quantity,
          unit_price: s.unit_price_snapshot,
          line_total: s.line_total,
        })),
        parts.map((p: any) => ({
          name: p.products?.name || '',
          qty: p.quantity,
          unit_price: p.unit_sale_snapshot,
          line_total: p.line_total_sale,
        })),
        termsText,
      );

      // Gera o PDF imutável da OS no exato estado em que está sendo assinado
      let signedPdfBase64: string | undefined;
      try {
        const pdfBlob = await generatePDFBlob(buildPdfData(), DEFAULT_PDF_OPTIONS);
        signedPdfBase64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve(String(reader.result || ''));
          reader.onerror = () => reject(reader.error);
          reader.readAsDataURL(pdfBlob);
        });
      } catch (pdfErr) {
        console.warn('[signature] falha ao gerar PDF arquivado:', pdfErr);
      }

      const { data: result, error: fnErr } = await supabase.functions.invoke('submit-signature', {
        body: {
          share_token: token,
          accepted_name: acceptedName.trim(),
          signature_png_base64: signaturePng,
          document_hash: hash,
          accepted_terms_snapshot: termsText || null,
          signed_pdf_base64: signedPdfBase64,
        },
      });

      if (fnErr) throw fnErr;
      if ((result as any)?.error) throw new Error((result as any).error);

      toast.success('Assinatura registrada com sucesso!');
      setAcceptedName('');
      setAcceptedTerms(false);
      setSignaturePng(null);
      setReload((r) => r + 1);
    } catch (e: any) {
      toast.error(e?.message || 'Falha ao enviar assinatura.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-muted/30 py-8 px-4">
      <div className="max-w-4xl mx-auto space-y-6">
        {/* Banner de status */}
        {needsResignature && (
          <div className="rounded-lg border border-warning bg-warning/10 p-4 flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div className="text-sm">
              <p className="font-semibold text-foreground">Documento atualizado pela equipe</p>
              <p className="text-muted-foreground">
                Esta Ordem de Serviço foi alterada após sua última assinatura. É necessário revisá-la e assinar novamente.
              </p>
            </div>
          </div>
        )}

        {isSigned && (
          <div className="rounded-lg border border-success bg-success/10 p-4 flex items-start gap-3">
            <CheckCircle2 className="h-5 w-5 text-success shrink-0 mt-0.5" />
            <div className="text-sm">
              <p className="font-semibold text-foreground">Documento assinado</p>
              <p className="text-muted-foreground">
                Assinado por <strong className="text-foreground">{order.signed_by_name}</strong> em {fmtDateTime(order.signed_at)}.
              </p>
            </div>
          </div>
        )}

        {/* Company Header */}
        <Card>
          <CardContent className="pt-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                {logoUrl && (
                  <img
                    src={logoUrl}
                    alt="Logo"
                    className="h-12 sm:h-14 w-auto max-w-[200px] object-contain mb-3"
                  />
                )}
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
              <div className="flex flex-col items-start sm:items-end gap-2">
                <Badge variant="secondary" className="text-base px-3 py-1">
                  {order.service_order_number}
                </Badge>
                <p className="text-xs text-muted-foreground">
                  Emissão: {fmtDate(order.created_at)}
                </p>
                {show.validity && order.quote_validity_date && (
                  <p className="text-xs text-muted-foreground">
                    Validade: {fmtDate(order.quote_validity_date)}
                  </p>
                )}
                <Button onClick={handleDownloadPDF} size="sm" className="gap-2">
                  <Download className="h-4 w-4" /> Baixar PDF
                </Button>
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
                <p className="font-medium">{client.name}</p>
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
                <p className="font-medium">{vessel.name}</p>
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
                      <p className="font-medium">{s.name_snapshot}</p>
                      {s.description_snapshot && (
                        <p className="text-xs text-muted-foreground">{s.description_snapshot}</p>
                      )}
                      {show.servicePrices && (
                        <p className="text-xs text-muted-foreground">
                          {s.quantity} × {fmtCurrency(s.unit_price_snapshot)}
                        </p>
                      )}
                    </div>
                    {show.servicePrices && (
                      <p className="font-medium tabular-nums">{fmtCurrency(s.line_total)}</p>
                    )}
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
                      <p className="font-medium">{p.products?.name || '—'}</p>
                      {p.products?.sku && (
                        <p className="text-xs text-muted-foreground">SKU: {p.products.sku}</p>
                      )}
                      {show.partsPrices && (
                        <p className="text-xs text-muted-foreground">
                          {p.quantity} × {fmtCurrency(p.unit_sale_snapshot)}
                        </p>
                      )}
                    </div>
                    {show.partsPrices && (
                      <p className="font-medium tabular-nums">{fmtCurrency(p.line_total_sale)}</p>
                    )}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Photos Gallery */}
        {order.photos && order.photos.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <ImageIcon className="h-5 w-5" />
                Acompanhamento da Obra (Fotos)
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                {order.photos.map((url: string, i: number) => (
                  <div key={i} className="aspect-square rounded-xl overflow-hidden border">
                    <img src={url} alt={`Acompanhamento ${i+1}`} className="w-full h-full object-cover hover:scale-105 transition-transform" />
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Totals */}
        <Card>
          <CardContent className="pt-6 space-y-2 text-sm">
            {show.servicePrices && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Mão de obra</span>
                <span className="tabular-nums">{fmtCurrency(order.labor_cost_total)}</span>
              </div>
            )}
            {show.partsPrices && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">Peças</span>
                <span className="tabular-nums">{fmtCurrency(order.parts_cost_total)}</span>
              </div>
            )}
            {show.travelCost && order.travel_cost_total > 0 && (
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
            {show.discount && order.discount_amount > 0 && (
              <div className="flex justify-between text-destructive">
                <span>Desconto</span>
                <span className="tabular-nums">- {fmtCurrency(order.discount_amount)}</span>
              </div>
            )}
            {show.tax && order.tax_amount > 0 && (
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

        {/* Dados bancários */}
        {show.bankDetails && (company.bank_name || company.pix_key) && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Dados Bancários</CardTitle>
            </CardHeader>
            <CardContent className="text-sm space-y-1">
              {company.bank_name && <p><span className="text-muted-foreground">Banco:</span> {company.bank_name}</p>}
              {company.bank_agency && <p><span className="text-muted-foreground">Agência:</span> {company.bank_agency}</p>}
              {company.bank_account && <p><span className="text-muted-foreground">Conta:</span> {company.bank_account}</p>}
              {company.pix_key && <p><span className="text-muted-foreground">Chave PIX:</span> {company.pix_key}</p>}
            </CardContent>
          </Card>
        )}

        {/* Instruções de pagamento */}
        {show.paymentInstructions && company.payment_instructions && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Instruções de Pagamento</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm whitespace-pre-wrap text-muted-foreground">
                {company.payment_instructions}
              </p>
            </CardContent>
          </Card>
        )}

        {/* Botão de pagamento online */}
        {company.payment_link_url && (
          <Card className="border-primary/30 bg-primary/5">
            <CardContent className="pt-6 pb-6 flex flex-col items-center gap-3 text-center">
              <CreditCard className="h-8 w-8 text-primary" />
              <div>
                <p className="font-semibold text-base">Pague online com segurança</p>
                <p className="text-sm text-muted-foreground mt-0.5">
                  Clique no botão abaixo para realizar o pagamento desta OS.
                </p>
              </div>
              <a
                href={company.payment_link_url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-6 py-2.5 text-sm font-bold text-primary-foreground shadow-md hover:opacity-90 transition-opacity"
              >
                Pagar agora <ExternalLink className="h-4 w-4" />
              </a>
            </CardContent>
          </Card>
        )}

        {/* Notas extras */}
        {show.extraNotes && order.extra_notes && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Observações</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm whitespace-pre-wrap text-muted-foreground">
                {order.extra_notes}
              </p>
            </CardContent>
          </Card>
        )}

        {/* Termos e condições */}
        {show.terms && termsText && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Termos e Condições</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-xs text-muted-foreground whitespace-pre-wrap leading-relaxed max-h-72 overflow-y-auto rounded border bg-muted/40 p-3">
                {termsText}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Bloco de assinatura */}
        {show.allowSignature && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <PenLine className="h-5 w-5" />
                Assinatura Digital
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {isSigned && signature ? (
                <div className="space-y-3">
                  <div className="rounded-lg border bg-background p-4">
                    {signature.signature_image_url ? (
                      <img
                        src={signature.signature_image_url}
                        alt="Assinatura do cliente"
                        className="mx-auto max-h-32"
                      />
                    ) : (
                      <p className="text-center text-sm text-muted-foreground">
                        Assinatura registrada (imagem não disponível)
                      </p>
                    )}
                  </div>
                  <div className="text-sm text-center text-muted-foreground">
                    <p>Assinado por <strong className="text-foreground">{signature.accepted_name}</strong></p>
                    <p>{fmtDateTime(signature.signed_at)}</p>
                  </div>
                </div>
              ) : (
                <>
                  <p className="text-sm text-muted-foreground">
                    Para aprovar este documento, preencha seu nome, marque o aceite dos termos e desenhe sua assinatura abaixo.
                  </p>

                  <div className="space-y-2">
                    <Label htmlFor="accepted-name">Nome completo</Label>
                    <Input
                      id="accepted-name"
                      value={acceptedName}
                      onChange={(e) => setAcceptedName(e.target.value)}
                      placeholder="Como assina nos documentos"
                      disabled={submitting}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Assinatura</Label>
                    <SignaturePad onChange={setSignaturePng} disabled={submitting} />
                  </div>

                  <div className="flex items-start gap-2 rounded border bg-muted/40 p-3">
                    <Checkbox
                      id="accept-terms"
                      checked={acceptedTerms}
                      onCheckedChange={(v) => setAcceptedTerms(!!v)}
                      disabled={submitting}
                      className="mt-0.5"
                    />
                    <Label htmlFor="accept-terms" className="text-sm leading-snug cursor-pointer">
                      Li e aceito os termos, condições, valores e descrição apresentados nesta Ordem de Serviço.
                    </Label>
                  </div>

                  <Button
                    onClick={handleSubmitSignature}
                    disabled={submitting}
                    className="w-full gap-2"
                    size="lg"
                  >
                    {submitting ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      <PenLine className="h-4 w-4" />
                    )}
                    {submitting ? 'Enviando...' : 'Aprovar e Assinar'}
                  </Button>

                  <p className="text-[11px] text-center text-muted-foreground">
                    Ao assinar, registramos seu nome, data, hora e endereço de IP para validade jurídica.
                  </p>
                </>
              )}
            </CardContent>
          </Card>
        )}

        <p className="text-center text-xs text-muted-foreground py-4">
          Documento gerado por {company.company_name || 'MarineFlow'}
        </p>
      </div>
    </div>
  );
}
