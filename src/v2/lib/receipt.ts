import { supabase } from '@/integrations/supabase/client';
import { DEFAULT_PDF_OPTIONS, type PDFData } from '@/lib/pdf-generator';
import { printPDF } from '@/lib/pdf-print';
import { toast } from 'sonner';

export type ReceivableRow = {
  id: string;
  description: string;
  amount: number | null;
  balance_amount?: number | null;
  paid_amount?: number | null;
  status?: string | null;
  due_date: string;
  created_at?: string | null;
  payment_method?: string | null;
  client_id?: string | null;
  service_order_id?: string | null;
  origin?: string | null;
  clients?: { id?: string; name?: string; cpf_cnpj?: string | null; phone?: string | null; whatsapp?: string | null; email?: string | null } | null;
  service_orders?: { id?: string; service_order_number?: string; share_token?: string | null } | null;
};

/** Gera o recibo em PDF do último pagamento confirmado (porte fiel do handler da FinancialPage v1). */
export async function generateReceivableReceipt(r: ReceivableRow): Promise<void> {
  try {
    const { data: settingsRows } = await supabase.from('app_settings').select('key, value');
    const sm: Record<string, string> = {};
    for (const row of (settingsRows || []) as Array<{ key: string; value: string }>) {
      if (row.key) sm[row.key] = String(row.value || '');
    }
    const get = (k: string) => sm[k] || '';

    const { data: pays } = await supabase
      .from('payments')
      .select('*')
      .eq('receivable_id', r.id)
      .eq('status', 'confirmed')
      .order('payment_date', { ascending: false })
      .limit(1);
    const lastPay = (pays || [])[0];

    const amount = lastPay ? Number(lastPay.amount) : Number(r.paid_amount || 0);
    if (amount <= 0) {
      toast.error('Não há pagamento confirmado para gerar recibo');
      return;
    }

    const pdfData: PDFData = {
      documentType: 'receipt',
      company: {
        name: get('company_name') || 'MarineFlow',
        address: [get('address_line_1'), get('address_number')].filter(Boolean).join(', '),
        city: get('city'), state: get('state'), postal_code: get('postal_code'),
        phone: get('phone'), email: get('email'), cnpj: get('cnpj'),
      },
      bank: {
        bank_name: get('bank_name') || undefined,
        bank_agency: get('bank_agency') || undefined,
        bank_account: get('bank_account') || undefined,
        pix_key: get('pix_key') || undefined,
      },
      serviceOrder: {
        service_order_number: r.service_orders?.service_order_number || r.description || r.id.slice(0, 8),
        status: r.status || 'paid', created_at: r.created_at || new Date().toISOString(),
        grand_total: amount, labor_cost_total: 0, parts_cost_total: 0,
        travel_cost_total: 0, discount_amount: 0, tax_amount: 0,
      },
      client: {
        name: r.clients?.name || '—',
        cpf_cnpj: r.clients?.cpf_cnpj ?? undefined,
        phone: r.clients?.phone ?? undefined,
        email: r.clients?.email ?? undefined,
      },
      services: [], parts: [],
      receipt: {
        amount,
        payment_date: lastPay?.payment_date || new Date().toISOString(),
        payment_method: lastPay?.payment_method || r.payment_method || 'pix',
        reference: r.service_orders?.service_order_number || r.description,
        notes: lastPay?.notes || undefined,
      },
    };
    printPDF(pdfData, { ...DEFAULT_PDF_OPTIONS });
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Erro ao gerar recibo');
  }
}
