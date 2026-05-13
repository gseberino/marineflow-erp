import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { PDFData } from '@/lib/pdf-generator';

export function usePDFData(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['pdf-data', serviceOrderId],
    queryFn: async () => {
      if (!serviceOrderId) return null;

      const [soRes, settingsRes] = await Promise.all([
        supabase.from('service_orders')
          .select(`
            *,
            clients(*),
            vessels(*),
            marinas(*),
            service_order_services(*, services(name:service_name)),
            service_order_parts(*, products(name, sku, image_url)),
            service_order_expenses(category, description, amount, paid_by),
            payment_condition_presets(label, installments)
          `)
          .eq('id', serviceOrderId)
          .single(),
        supabase.from('app_settings')
          .select('key, value'),
      ]);

      if (soRes.error) throw soRes.error;
      const so = soRes.data;
      const settingsMap: Record<string, string> = {};
      for (const row of (settingsRes.data || []) as Array<{ key: string; value: string }>) {
        if (row.key) settingsMap[row.key] = String(row.value || '');
      }
      const get = (key: string) => settingsMap[key] || '';

      const pdfData: PDFData = {
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
          logo_url: get('company_logo_url') || undefined,
        },
        bank: {
          bank_name: get('bank_name') || undefined,
          bank_agency: get('bank_agency') || undefined,
          bank_account: get('bank_account') || undefined,
          pix_key: get('pix_key') || undefined,
        },
        serviceOrder: {
          service_order_number: so.service_order_number,
          status: so.status,
          created_at: so.created_at,
          scheduled_start_at: so.scheduled_start_at ?? undefined,
          problem_description: so.problem_description ?? undefined,
          technical_notes: so.technician_notes ?? undefined,
          commissioned_person: so.commissioned_person ?? undefined,
          commission_rate: so.commission_rate ?? undefined,
          commission_amount: so.commission_amount ?? undefined,
          grand_total: so.grand_total || 0,
          labor_cost_total: so.labor_cost_total || 0,
          parts_cost_total: so.parts_cost_total || 0,
          travel_cost_total: so.travel_cost_total || 0,
          travel_hours: (so as any).travel_hours || 0,
          ferry_cost: (so as any).ferry_cost || 0,
          travel_type: (so as any).travel_type || 'comercial',
          discount_amount: so.discount_amount || 0,
          tax_amount: so.tax_amount || 0,
          operational_cost_total: so.operational_cost_total || 0,
          extra_notes: so.extra_notes ?? undefined,
          payment_conditions: (so as any).payment_conditions ?? undefined,
          payment_condition_label: (so as any).payment_condition_presets?.label ?? null,
          payment_condition_installments: (so as any).payment_condition_presets?.installments ?? null,
          subcontract_cost_total: (so as any).subcontract_cost_total || 0,
        },
        client: {
          name: (so.clients as any)?.full_name_or_company_name || '—',
          cpf_cnpj: (so.clients as any)?.cpf_cnpj ?? undefined,
          phone: (so.clients as any)?.phone ?? undefined,
          email: (so.clients as any)?.email ?? undefined,
          address: [
            (so.clients as any)?.address_line_1,
            (so.clients as any)?.city,
            (so.clients as any)?.state,
          ].filter(Boolean).join(', ') || undefined,
        },
        vessel: so.vessels ? {
          name: (so.vessels as any).boat_name,
          manufacturer: (so.vessels as any).manufacturer ?? undefined,
          model: (so.vessels as any).model ?? undefined,
          year: (so.vessels as any).year ?? undefined,
          registration: (so.vessels as any).hull_id_or_registration ?? undefined,
        } : undefined,
        marina: so.marinas ? {
          name: (so.marinas as any).marina_name || '—',
          city: (so.marinas as any).city ?? undefined,
        } : undefined,
        services: ((so as any).service_order_services || []).map((s: any) => ({
          name: s.name_snapshot || s.services?.name || '—',
          description: s.description_snapshot ?? undefined,
          billing_unit: s.billing_unit_snapshot || 'unit',
          quantity: s.quantity || 1,
          unit_price: s.unit_price_snapshot || 0,
          line_total: s.line_total || 0,
        })),
        parts: ((so as any).service_order_parts || []).map((p: any) => ({
          name: p.products?.name || '—',
          sku: p.products?.sku ?? undefined,
          quantity: p.quantity || 1,
          unit_price: p.unit_sale_snapshot || 0,
          line_total: p.line_total_sale || 0,
          image_url: p.products?.image_url || null,
        })),
        expenses: ((so as any).service_order_expenses || [])
          .filter((e: any) => e.paid_by === 'company')
          .map((e: any) => ({
            category: e.category,
            description: e.description,
            amount: e.amount,
          })),
        terms: [
          get('terms_general'),
          get('terms_warranty'),
          get('terms_cancellation'),
          get('terms_delivery'),
          get('terms_responsibilities'),
        ].filter(Boolean).join('\n\n') || undefined,
        photos: (so as any).photos?.map((p: any) => p.url) || [],
      };

      return pdfData;
    },
    enabled: !!serviceOrderId,
    staleTime: 0,
  });
}
