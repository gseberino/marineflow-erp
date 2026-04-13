export type PDFDocumentType = 'quote' | 'service_order';

export type PDFOptions = {
  showServicePrices: boolean;
  showPartsPrices: boolean;
  showTravelCost: boolean;
  showDiscount: boolean;
  showTax: boolean;
  showCommission: boolean;
  showTerms: boolean;
  showSignature: boolean;
};

export const DEFAULT_PDF_OPTIONS: PDFOptions = {
  showServicePrices: true,
  showPartsPrices: true,
  showTravelCost: true,
  showDiscount: true,
  showTax: true,
  showCommission: false,
  showTerms: true,
  showSignature: true,
};

export type PDFData = {
  documentType: PDFDocumentType;
  company: {
    name: string;
    address: string;
    city: string;
    state: string;
    postal_code: string;
    phone: string;
    email: string;
    cnpj: string;
  };
  serviceOrder: {
    service_order_number: string;
    status: string;
    created_at: string;
    scheduled_start_at?: string;
    problem_description?: string;
    technical_notes?: string;
    commissioned_person?: string;
    commission_rate?: number;
    commission_amount?: number;
    grand_total: number;
    labor_cost_total: number;
    parts_cost_total: number;
    travel_cost_total: number;
    discount_amount: number;
    tax_amount: number;
    operational_cost_total?: number;
  };
  client: {
    name: string;
    cpf_cnpj?: string;
    phone?: string;
    email?: string;
    address?: string;
  };
  vessel?: {
    name: string;
    type?: string;
    manufacturer?: string;
    model?: string;
    year?: number;
    registration?: string;
  };
  marina?: {
    name: string;
    city?: string;
  };
  services: Array<{
    service_name: string;
    description?: string;
    billing_unit: string;
    quantity: number;
    unit_price: number;
    line_total: number;
  }>;
  parts: Array<{
    product_name: string;
    sku?: string;
    quantity: number;
    unit_price: number;
    line_total: number;
  }>;
  expenses?: Array<{
    category: string;
    description: string;
    amount: number;
  }>;
  terms?: string;
};

export function generatePDF(data: PDFData, options: PDFOptions): void {
  const html = buildHTMLDocument(data, options);

  const iframe = document.createElement('iframe');
  iframe.style.position = 'fixed';
  iframe.style.right = '0';
  iframe.style.bottom = '0';
  iframe.style.width = '0';
  iframe.style.height = '0';
  iframe.style.border = '0';
  iframe.style.visibility = 'hidden';
  document.body.appendChild(iframe);

  const doc = iframe.contentWindow?.document;
  if (!doc) {
    document.body.removeChild(iframe);
    const win = window.open('', '_blank');
    if (win) {
      win.document.write(html);
      win.document.close();
      setTimeout(() => win.print(), 400);
    }
    return;
  }

  doc.open();
  doc.write(html);
  doc.close();

  iframe.onload = () => {
    setTimeout(() => {
      try {
        iframe.contentWindow?.focus();
        iframe.contentWindow?.print();
      } finally {
        setTimeout(() => {
          document.body.removeChild(iframe);
        }, 1000);
      }
    }, 300);
  };
}

function buildHTMLDocument(data: PDFData, options: PDFOptions): string {
  const isQuote = data.documentType === 'quote';
  const docTitle = isQuote ? 'ORÇAMENTO' : 'ORDEM DE SERVIÇO';
  const docNumber = data.serviceOrder.service_order_number;
  const today = new Date().toLocaleDateString('pt-BR');

  const formatCurrency = (v: number) =>
    new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

  const formatDate = (iso?: string) => {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('pt-BR');
  };

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${s.service_name}${s.description ? `<br/><small style="color:#6b7280;">${s.description}</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${s.quantity} ${billingUnitLabel[s.billing_unit] || s.billing_unit}</td>
      ${options.showServicePrices ? `<td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${formatCurrency(s.unit_price)}</td>` : ''}
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${formatCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${p.product_name}${p.sku ? ` <small style="color:#6b7280;">(${p.sku})</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${p.quantity}</td>
      ${options.showPartsPrices ? `<td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${formatCurrency(p.unit_price)}</td>` : ''}
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${formatCurrency(p.line_total)}</td>
    </tr>
  `).join('');

  const summaryRows = [
    data.services.length > 0
      ? `<tr><td style="padding:4px 8px;">Mão de obra</td><td style="padding:4px 8px;text-align:right;">${formatCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0
      ? `<tr><td style="padding:4px 8px;">Peças e materiais</td><td style="padding:4px 8px;text-align:right;">${formatCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0
      ? `<tr><td style="padding:4px 8px;">Deslocamento</td><td style="padding:4px 8px;text-align:right;">${formatCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    (data.serviceOrder.operational_cost_total ?? 0) > 0
      ? `<tr><td style="padding:4px 8px;">Despesas operacionais</td><td style="padding:4px 8px;text-align:right;">${formatCurrency(data.serviceOrder.operational_cost_total!)}</td></tr>` : '',
    options.showDiscount && data.serviceOrder.discount_amount > 0
      ? `<tr><td style="padding:4px 8px;">Desconto</td><td style="padding:4px 8px;text-align:right;color:#dc2626;">− ${formatCurrency(data.serviceOrder.discount_amount)}</td></tr>` : '',
    options.showTax && data.serviceOrder.tax_amount > 0
      ? `<tr><td style="padding:4px 8px;">Impostos</td><td style="padding:4px 8px;text-align:right;">${formatCurrency(data.serviceOrder.tax_amount)}</td></tr>` : '',
  ].filter(Boolean).join('');

  const commissionRows = options.showCommission && (data.serviceOrder.commission_amount ?? 0) > 0
    ? `
      <tr><td style="padding:4px 8px;">Comissão (${data.serviceOrder.commission_rate}%)</td><td style="padding:4px 8px;text-align:right;color:#dc2626;">− ${formatCurrency(data.serviceOrder.commission_amount ?? 0)}</td></tr>
      <tr><td style="padding:4px 8px;font-weight:600;">Total líquido</td><td style="padding:4px 8px;text-align:right;font-weight:600;">${formatCurrency(data.serviceOrder.grand_total - (data.serviceOrder.commission_amount ?? 0))}</td></tr>
    ` : '';

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<title>${docTitle} ${docNumber}</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family: 'Segoe UI', Arial, sans-serif; font-size:12px; color:#1f2937; padding:20px; }
  @media print {
    body { padding:0; }
    @page { margin:15mm 20mm; size:A4; }
  }
  table { border-collapse:collapse; width:100%; }
</style>
</head>
<body>

<!-- Company Header -->
<div style="display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #1e3a5f;padding-bottom:12px;margin-bottom:16px;">
  <div>
    <h1 style="font-size:20px;color:#1e3a5f;margin:0;">${data.company.name}</h1>
  </div>
  <div style="text-align:right;font-size:11px;color:#6b7280;">
    <div>${data.company.address}${data.company.city ? `, ${data.company.city}` : ''}${data.company.state ? ` - ${data.company.state}` : ''}</div>
    <div>${data.company.postal_code ? `CEP: ${data.company.postal_code}` : ''}${data.company.phone ? ` · Tel: ${data.company.phone}` : ''}</div>
    <div>${data.company.email ? `Email: ${data.company.email}` : ''}${data.company.cnpj ? ` · CNPJ: ${data.company.cnpj}` : ''}</div>
  </div>
</div>

<!-- Document Title -->
<div style="text-align:center;margin-bottom:16px;">
  <h2 style="font-size:16px;letter-spacing:2px;color:#1e3a5f;margin:0;">${docTitle}</h2>
  <div style="font-size:14px;font-weight:600;margin-top:4px;">${docNumber}</div>
  <div style="font-size:11px;color:#6b7280;">Emitido em: ${today}</div>
  ${data.serviceOrder.scheduled_start_at ? `<div style="font-size:11px;color:#6b7280;">Agendado: ${formatDate(data.serviceOrder.scheduled_start_at)}</div>` : ''}
</div>

<!-- Client & Vessel -->
<div style="display:flex;gap:16px;margin-bottom:16px;">
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Cliente</div>
    <div>
      <strong>${data.client.name}</strong><br/>
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${data.client.cpf_cnpj}<br/>` : ''}
      ${data.client.phone ? `Tel: ${data.client.phone}<br/>` : ''}
      ${data.client.email ? `Email: ${data.client.email}<br/>` : ''}
      ${data.client.address || ''}
    </div>
  </div>
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Embarcação${data.marina ? ' / Marina' : ''}</div>
    <div>
      ${data.vessel ? `<strong>${data.vessel.name}</strong><br/>` : ''}
      ${data.vessel?.manufacturer ? `${data.vessel.manufacturer}${data.vessel.model ? ` ${data.vessel.model}` : ''}${data.vessel.year ? ` (${data.vessel.year})` : ''}<br/>` : ''}
      ${data.vessel?.registration ? `Registro: ${data.vessel.registration}<br/>` : ''}
      ${data.marina ? `Marina: ${data.marina.name}${data.marina.city ? `, ${data.marina.city}` : ''}` : ''}
    </div>
  </div>
</div>

${data.serviceOrder.problem_description ? `
<!-- Problem Description -->
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">${isQuote ? 'Escopo do Serviço' : 'Descrição do Problema'}</div>
  <div style="white-space:pre-wrap;">${data.serviceOrder.problem_description}</div>
</div>
` : ''}

${data.services.length > 0 ? `
<!-- Services Table -->
<div style="margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Serviços / Mão de Obra</div>
  <table>
    <thead>
      <tr style="background:#f3f4f6;">
        <th style="padding:6px 8px;text-align:left;font-size:11px;">Descrição</th>
        <th style="padding:6px 8px;text-align:center;font-size:11px;">Qtd</th>
        ${options.showServicePrices ? '<th style="padding:6px 8px;text-align:right;font-size:11px;">Unit.</th>' : ''}
        <th style="padding:6px 8px;text-align:right;font-size:11px;">Total</th>
      </tr>
    </thead>
    <tbody>${serviceRows}</tbody>
  </table>
</div>
` : ''}

${data.parts.length > 0 ? `
<!-- Parts Table -->
<div style="margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Peças e Materiais</div>
  <table>
    <thead>
      <tr style="background:#f3f4f6;">
        <th style="padding:6px 8px;text-align:left;font-size:11px;">Item</th>
        <th style="padding:6px 8px;text-align:center;font-size:11px;">Qtd</th>
        ${options.showPartsPrices ? '<th style="padding:6px 8px;text-align:right;font-size:11px;">Unit.</th>' : ''}
        <th style="padding:6px 8px;text-align:right;font-size:11px;">Total</th>
      </tr>
    </thead>
    <tbody>${partsRows}</tbody>
  </table>
</div>
` : ''}

${!isQuote && data.serviceOrder.technical_notes ? `
<!-- Technical Notes -->
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Observações Técnicas</div>
  <div style="white-space:pre-wrap;">${data.serviceOrder.technical_notes}</div>
</div>
` : ''}

<!-- Summary -->
<div style="margin-bottom:16px;border:1px solid #e5e7eb;border-radius:6px;overflow:hidden;">
  <table style="font-size:12px;">
    <tbody>
      ${summaryRows}
      ${commissionRows}
    </tbody>
    <tfoot>
      <tr style="background:#1e3a5f;color:#fff;">
        <td style="padding:8px;font-weight:700;font-size:14px;">TOTAL</td>
        <td style="padding:8px;text-align:right;font-weight:700;font-size:14px;">${formatCurrency(data.serviceOrder.grand_total)}</td>
      </tr>
    </tfoot>
  </table>
  ${isQuote ? '<div style="padding:6px 8px;font-size:10px;color:#6b7280;border-top:1px solid #e5e7eb;">Validade deste orçamento: 15 dias a partir da emissão.</div>' : ''}
</div>

${options.showSignature ? `
<!-- Signatures -->
<div style="display:flex;gap:40px;margin-top:40px;margin-bottom:24px;">
  <div style="flex:1;text-align:center;">
    <div style="border-top:1px solid #1f2937;padding-top:6px;margin-top:60px;">
      <strong>${data.company.name}</strong>
    </div>
  </div>
  <div style="flex:1;text-align:center;">
    <div style="border-top:1px solid #1f2937;padding-top:6px;margin-top:60px;">
      <div><strong>${data.client.name}</strong></div>
      <div style="font-size:10px;color:#6b7280;">${isQuote ? 'Aprovação do Orçamento' : 'Aceite do Serviço Realizado'}</div>
    </div>
  </div>
</div>
` : ''}

${options.showTerms && data.terms ? `
<!-- Terms -->
<div style="border-top:1px solid #e5e7eb;padding-top:10px;margin-top:16px;">
  <div style="font-weight:700;font-size:10px;color:#1e3a5f;text-transform:uppercase;margin-bottom:4px;">Termos e Condições</div>
  <div style="font-size:9px;color:#6b7280;white-space:pre-wrap;">${data.terms}</div>
</div>
` : ''}

<!-- Footer -->
<div style="text-align:center;font-size:9px;color:#9ca3af;margin-top:20px;border-top:1px solid #e5e7eb;padding-top:8px;">
  ${docTitle} gerado em ${today} · ${data.serviceOrder.service_order_number}
</div>

</body>
</html>`;
}
