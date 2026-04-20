export type PDFDocumentType = 'quote' | 'service_order' | 'invoice' | 'receipt';

export type PDFOptions = {
  showServicePrices: boolean;
  showPartsPrices: boolean;
  showTravelCost: boolean;
  showDiscount: boolean;
  showTax: boolean;
  showCommission: boolean;
  showTerms: boolean;
  showSignature: boolean;
  // Invoice-only
  showBankDetails?: boolean;
  showPaymentInstructions?: boolean;
  validity?: { mode: 'days' | 'date'; days?: number; date?: string };
  // Invoice payment due date (yyyy-mm-dd)
  dueDate?: string;
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
  showBankDetails: true,
  showPaymentInstructions: true,
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
  bank?: {
    bank_name?: string;
    bank_agency?: string;
    bank_account?: string;
    pix_key?: string;
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
    extra_notes?: string;
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
  // Receipt-only
  receipt?: {
    amount: number;
    payment_date: string; // ISO
    payment_method: string;
    reference?: string;
    notes?: string;
  };
  terms?: string;
};

export function generatePDF(data: PDFData, options: PDFOptions): void {
  const html = buildHTMLDocument(data, options);

  const iframe = document.createElement('iframe');
  iframe.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0;';
  document.body.appendChild(iframe);

  const doc = iframe.contentDocument || iframe.contentWindow?.document;
  if (!doc) {
    document.body.removeChild(iframe);
    const win = window.open('', '_blank');
    if (win) {
      win.document.write(html);
      win.document.close();
      setTimeout(() => win.print(), 500);
    }
    return;
  }

  doc.open();
  doc.write(html);
  doc.close();

  requestAnimationFrame(() => {
    setTimeout(() => {
      try {
        iframe.contentWindow?.focus();
        iframe.contentWindow?.print();
      } catch (e) {
        console.error('Print failed:', e);
      } finally {
        setTimeout(() => {
          if (document.body.contains(iframe)) {
            document.body.removeChild(iframe);
          }
        }, 2000);
      }
    }, 500);
  });
}

// ============= Number to words (pt-BR) =============
const _ones = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez',
  'onze', 'doze', 'treze', 'quatorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'];
const _tens = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
const _hundreds = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos', 'setecentos', 'oitocentos', 'novecentos'];

function _under1000(n: number): string {
  if (n === 0) return '';
  if (n === 100) return 'cem';
  const h = Math.floor(n / 100);
  const rest = n % 100;
  const parts: string[] = [];
  if (h > 0) parts.push(_hundreds[h]);
  if (rest > 0) {
    if (rest < 20) parts.push(_ones[rest]);
    else {
      const t = Math.floor(rest / 10);
      const o = rest % 10;
      parts.push(o > 0 ? `${_tens[t]} e ${_ones[o]}` : _tens[t]);
    }
  }
  return parts.join(' e ');
}

function numberToWordsBRL(value: number): string {
  if (value < 0) return 'menos ' + numberToWordsBRL(-value);
  const intPart = Math.floor(value);
  const cents = Math.round((value - intPart) * 100);

  const intWords = (() => {
    if (intPart === 0) return 'zero';
    const millions = Math.floor(intPart / 1_000_000);
    const thousands = Math.floor((intPart % 1_000_000) / 1000);
    const rest = intPart % 1000;
    const parts: string[] = [];
    if (millions > 0) parts.push(millions === 1 ? 'um milhão' : `${_under1000(millions)} milhões`);
    if (thousands > 0) parts.push(thousands === 1 ? 'mil' : `${_under1000(thousands)} mil`);
    if (rest > 0) parts.push(_under1000(rest));
    return parts.join(' e ');
  })();

  const reaisLabel = intPart === 1 ? 'real' : 'reais';
  let result = `${intWords} ${reaisLabel}`;
  if (cents > 0) {
    const centWords = _under1000(cents);
    result += ` e ${centWords} ${cents === 1 ? 'centavo' : 'centavos'}`;
  }
  return result;
}

const PAYMENT_METHOD_LABELS: Record<string, string> = {
  pix: 'PIX',
  credit_card: 'Cartão de Crédito',
  debit_card: 'Cartão de Débito',
  cash: 'Dinheiro',
  bank_transfer: 'Transferência Bancária',
  check: 'Cheque',
  boleto: 'Boleto',
  ted: 'TED',
};

function buildHTMLDocument(data: PDFData, options: PDFOptions): string {
  if (data.documentType === 'receipt') return buildReceiptHTML(data, options);
  if (data.documentType === 'invoice') return buildInvoiceHTML(data, options);
  return buildOrderHTML(data, options);
}

const fmtCurrency = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const fmtDate = (iso?: string) => {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR');
};

const esc = (v: unknown): string => {
  if (v === null || v === undefined) return '';
  return String(v)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
};


function companyHeaderHTML(company: PDFData['company']): string {
  return `
<div style="display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #1e3a5f;padding-bottom:12px;margin-bottom:16px;">
  <div>
    <h1 style="font-size:20px;color:#1e3a5f;margin:0;">${esc(company.name)}</h1>
  </div>
  <div style="text-align:right;font-size:11px;color:#6b7280;">
    <div>${esc(company.address)}${company.city ? `, ${esc(company.city)}` : ''}${company.state ? ` - ${esc(company.state)}` : ''}</div>
    <div>${company.postal_code ? `CEP: ${esc(company.postal_code)}` : ''}${company.phone ? ` · Tel: ${esc(company.phone)}` : ''}</div>
    <div>${company.email ? `Email: ${esc(company.email)}` : ''}${company.cnpj ? ` · CNPJ: ${esc(company.cnpj)}` : ''}</div>
  </div>
</div>`;
}

function pageWrapper(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<title>${title}</title>
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
<body>${body}</body>
</html>`;
}

// ============= QUOTE / SERVICE_ORDER (preserved behavior) =============
function buildOrderHTML(data: PDFData, options: PDFOptions): string {
  const isQuote = data.documentType === 'quote';
  const docTitle = isQuote ? 'ORÇAMENTO' : 'ORDEM DE SERVIÇO';
  const docNumber = data.serviceOrder.service_order_number;
  const today = new Date().toLocaleDateString('pt-BR');

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const getValidityText = (): string => {
    const v = options.validity;
    if (!v || v.mode === 'days') {
      const days = v?.days || 15;
      const expiry = new Date();
      expiry.setDate(expiry.getDate() + days);
      return `Validade: ${days} dias (até ${expiry.toLocaleDateString('pt-BR')}).`;
    }
    if (v.date) {
      const d = new Date(v.date + 'T12:00:00');
      return `Válido até: ${d.toLocaleDateString('pt-BR')}.`;
    }
    return 'Validade: 15 dias a partir da emissão.';
  };

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${esc(s.service_name)}${s.description ? `<br/><small style="color:#6b7280;">${esc(s.description)}</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      ${options.showServicePrices ? `<td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(s.unit_price)}</td>` : ''}
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${esc(p.product_name)}${p.sku ? ` <small style="color:#6b7280;">(${esc(p.sku)})</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${p.quantity}</td>
      ${options.showPartsPrices ? `<td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(p.unit_price)}</td>` : ''}
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(p.line_total)}</td>
    </tr>
  `).join('');

  const summaryRows = [
    data.services.length > 0
      ? `<tr><td style="padding:4px 8px;">Mão de obra</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0
      ? `<tr><td style="padding:4px 8px;">Peças e materiais</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0
      ? `<tr><td style="padding:4px 8px;">Deslocamento</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    (data.serviceOrder.operational_cost_total ?? 0) > 0
      ? `<tr><td style="padding:4px 8px;">Despesas operacionais</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.operational_cost_total!)}</td></tr>` : '',
    options.showDiscount && data.serviceOrder.discount_amount > 0
      ? `<tr><td style="padding:4px 8px;">Desconto</td><td style="padding:4px 8px;text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>` : '',
    options.showTax && data.serviceOrder.tax_amount > 0
      ? `<tr><td style="padding:4px 8px;">Impostos</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.tax_amount)}</td></tr>` : '',
  ].filter(Boolean).join('');

  const commissionRows = options.showCommission && (data.serviceOrder.commission_amount ?? 0) > 0
    ? `
      <tr><td style="padding:4px 8px;">Comissão (${data.serviceOrder.commission_rate}%)</td><td style="padding:4px 8px;text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.commission_amount ?? 0)}</td></tr>
      <tr><td style="padding:4px 8px;font-weight:600;">Total líquido</td><td style="padding:4px 8px;text-align:right;font-weight:600;">${fmtCurrency(data.serviceOrder.grand_total - (data.serviceOrder.commission_amount ?? 0))}</td></tr>
    ` : '';

  const body = `
${companyHeaderHTML(data.company)}

<div style="text-align:center;margin-bottom:16px;">
  <h2 style="font-size:16px;letter-spacing:2px;color:#1e3a5f;margin:0;">${docTitle}</h2>
  <div style="font-size:14px;font-weight:600;margin-top:4px;">${esc(docNumber)}</div>
  <div style="font-size:11px;color:#6b7280;">Emitido em: ${today}</div>
  ${!isQuote && data.serviceOrder.scheduled_start_at ? `<div style="font-size:11px;color:#6b7280;">Agendado: ${fmtDate(data.serviceOrder.scheduled_start_at)}</div>` : ''}
</div>

<div style="display:flex;gap:16px;margin-bottom:16px;">
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Cliente</div>
    <div>
      <strong>${esc(data.client.name)}</strong><br/>
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${esc(data.client.cpf_cnpj)}<br/>` : ''}
      ${data.client.phone ? `Tel: ${esc(data.client.phone)}<br/>` : ''}
      ${data.client.email ? `Email: ${esc(data.client.email)}<br/>` : ''}
      ${esc(data.client.address || '')}
    </div>
  </div>
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Embarcação${data.marina ? ' / Marina' : ''}</div>
    <div>
      ${data.vessel ? `<strong>${esc(data.vessel.name)}</strong><br/>` : ''}
      ${data.vessel?.manufacturer ? `${esc(data.vessel.manufacturer)}${data.vessel.model ? ` ${esc(data.vessel.model)}` : ''}${data.vessel.year ? ` (${esc(data.vessel.year)})` : ''}<br/>` : ''}
      ${data.vessel?.registration ? `Registro: ${data.vessel.registration}<br/>` : ''}
      ${data.marina ? `Marina: ${esc(data.marina.name)}${data.marina.city ? `, ${esc(data.marina.city)}` : ''}` : ''}
    </div>
  </div>
</div>

${data.serviceOrder.problem_description ? `
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">${isQuote ? 'Escopo do Serviço' : 'Descrição do Problema'}</div>
  <div style="white-space:pre-wrap;">${esc(data.serviceOrder.problem_description)}</div>
</div>
` : ''}

${data.services.length > 0 ? `
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
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Observações Técnicas</div>
  <div style="white-space:pre-wrap;">${esc(data.serviceOrder.technical_notes)}</div>
</div>
` : ''}

${data.serviceOrder.extra_notes ? `
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Observações Adicionais</div>
  <div style="white-space:pre-wrap;">${esc(data.serviceOrder.extra_notes)}</div>
</div>
` : ''}

<div style="margin-bottom:16px;border:1px solid #e5e7eb;border-radius:6px;overflow:hidden;">
  <table style="font-size:12px;">
    <tbody>
      ${summaryRows}
      ${commissionRows}
    </tbody>
    <tfoot>
      <tr style="background:#1e3a5f;color:#fff;">
        <td style="padding:8px;font-weight:700;font-size:14px;">TOTAL</td>
        <td style="padding:8px;text-align:right;font-weight:700;font-size:14px;">${fmtCurrency(data.serviceOrder.grand_total)}</td>
      </tr>
    </tfoot>
  </table>
  ${isQuote ? `<div style="padding:6px 8px;font-size:10px;color:#6b7280;border-top:1px solid #e5e7eb;">${getValidityText()}</div>` : ''}
</div>

${options.showSignature ? `
<div style="display:flex;gap:40px;margin-top:40px;margin-bottom:24px;">
  <div style="flex:1;text-align:center;">
    <div style="border-top:1px solid #1f2937;padding-top:6px;margin-top:60px;">
      <strong>${esc(data.company.name)}</strong>
    </div>
  </div>
  <div style="flex:1;text-align:center;">
    <div style="border-top:1px solid #1f2937;padding-top:6px;margin-top:60px;">
      <div><strong>${esc(data.client.name)}</strong></div>
      <div style="font-size:10px;color:#6b7280;">${isQuote ? 'Aprovação do Orçamento' : 'Aceite do Serviço Realizado'}</div>
    </div>
  </div>
</div>
` : ''}

${options.showTerms && data.terms ? `
<div style="border-top:1px solid #e5e7eb;padding-top:10px;margin-top:16px;">
  <div style="font-weight:700;font-size:10px;color:#1e3a5f;text-transform:uppercase;margin-bottom:4px;">Termos e Condições</div>
  <div style="font-size:9px;color:#6b7280;white-space:pre-wrap;">${esc(data.terms)}</div>
</div>
` : ''}

<div style="text-align:center;font-size:9px;color:#9ca3af;margin-top:20px;border-top:1px solid #e5e7eb;padding-top:8px;">
  ${docTitle} gerado em ${today} · ${esc(data.serviceOrder.service_order_number)}
</div>`;

  return pageWrapper(`${docTitle} ${esc(docNumber)}`, body);
}

// ============= INVOICE (FATURA) =============
function buildInvoiceHTML(data: PDFData, options: PDFOptions): string {
  const docNumber = `FAT-${esc(data.serviceOrder.service_order_number)}`;
  const today = new Date().toLocaleDateString('pt-BR');
  const dueDate = options.dueDate
    ? new Date(options.dueDate + 'T12:00:00').toLocaleDateString('pt-BR')
    : (() => {
        const d = new Date();
        d.setDate(d.getDate() + 15);
        return d.toLocaleDateString('pt-BR');
      })();

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${esc(s.service_name)}${s.description ? `<br/><small style="color:#6b7280;">${esc(s.description)}</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      ${options.showServicePrices ? `<td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(s.unit_price)}</td>` : ''}
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;">${esc(p.product_name)}${p.sku ? ` <small style="color:#6b7280;">(${esc(p.sku)})</small>` : ''}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:center;">${p.quantity}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(p.unit_price)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:right;">${fmtCurrency(p.line_total)}</td>
    </tr>
  `).join('');

  const summaryRows = [
    data.services.length > 0
      ? `<tr><td style="padding:4px 8px;">Mão de obra</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0
      ? `<tr><td style="padding:4px 8px;">Peças e materiais</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0
      ? `<tr><td style="padding:4px 8px;">Deslocamento</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    options.showDiscount && data.serviceOrder.discount_amount > 0
      ? `<tr><td style="padding:4px 8px;">Desconto</td><td style="padding:4px 8px;text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>` : '',
    options.showTax && data.serviceOrder.tax_amount > 0
      ? `<tr><td style="padding:4px 8px;">Impostos</td><td style="padding:4px 8px;text-align:right;">${fmtCurrency(data.serviceOrder.tax_amount)}</td></tr>` : '',
  ].filter(Boolean).join('');

  const bank = data.bank || {};
  const hasBank = !!(bank.bank_name || bank.bank_agency || bank.bank_account || bank.pix_key);

  const body = `
${companyHeaderHTML(data.company)}

<div style="text-align:center;margin-bottom:20px;">
  <h2 style="font-size:28px;letter-spacing:6px;color:#1e3a5f;margin:0;font-weight:800;">FATURA</h2>
  <div style="font-size:14px;font-weight:600;margin-top:6px;">${esc(docNumber)}</div>
  <div style="font-size:11px;color:#6b7280;margin-top:2px;">Emitida em: ${today} · Vencimento: <strong style="color:#dc2626;">${dueDate}</strong></div>
</div>

<div style="display:flex;gap:16px;margin-bottom:16px;">
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Cliente</div>
    <div>
      <strong>${esc(data.client.name)}</strong><br/>
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${esc(data.client.cpf_cnpj)}<br/>` : ''}
      ${data.client.phone ? `Tel: ${esc(data.client.phone)}<br/>` : ''}
      ${data.client.email ? `Email: ${esc(data.client.email)}<br/>` : ''}
      ${esc(data.client.address || '')}
    </div>
  </div>
  <div style="flex:1;border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Referência</div>
    <div>
      OS: <strong>${esc(data.serviceOrder.service_order_number)}</strong><br/>
      ${data.vessel ? `Embarcação: ${esc(data.vessel.name)}<br/>` : ''}
      ${data.marina ? `Marina: ${esc(data.marina.name)}` : ''}
    </div>
  </div>
</div>

${data.services.length > 0 ? `
<div style="margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Serviços</div>
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
<div style="margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Peças e Materiais</div>
  <table>
    <thead>
      <tr style="background:#f3f4f6;">
        <th style="padding:6px 8px;text-align:left;font-size:11px;">Item</th>
        <th style="padding:6px 8px;text-align:center;font-size:11px;">Qtd</th>
        <th style="padding:6px 8px;text-align:right;font-size:11px;">Unit.</th>
        <th style="padding:6px 8px;text-align:right;font-size:11px;">Total</th>
      </tr>
    </thead>
    <tbody>${partsRows}</tbody>
  </table>
</div>
` : ''}

<div style="margin-bottom:16px;border:1px solid #e5e7eb;border-radius:6px;overflow:hidden;">
  <table style="font-size:12px;">
    <tbody>${summaryRows}</tbody>
    <tfoot>
      <tr style="background:#1e3a5f;color:#fff;">
        <td style="padding:10px;font-weight:700;font-size:15px;">TOTAL A PAGAR</td>
        <td style="padding:10px;text-align:right;font-weight:700;font-size:15px;">${fmtCurrency(data.serviceOrder.grand_total)}</td>
      </tr>
    </tfoot>
  </table>
</div>

${options.showBankDetails !== false && hasBank ? `
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:12px;margin-bottom:16px;background:#f9fafb;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:8px;">Dados Bancários</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;font-size:12px;">
    ${bank.bank_name ? `<div><strong>Banco:</strong> ${esc(bank.bank_name)}</div>` : ''}
    ${bank.bank_agency ? `<div><strong>Agência:</strong> ${esc(bank.bank_agency)}</div>` : ''}
    ${bank.bank_account ? `<div><strong>Conta:</strong> ${esc(bank.bank_account)}</div>` : ''}
    ${bank.pix_key ? `<div><strong>Chave PIX:</strong> ${esc(bank.pix_key)}</div>` : ''}
    <div><strong>Favorecido:</strong> ${esc(data.company.name)}</div>
    ${data.company.cnpj ? `<div><strong>CNPJ:</strong> ${esc(data.company.cnpj)}</div>` : ''}
  </div>
</div>
` : ''}

${options.showPaymentInstructions !== false ? `
<div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;margin-bottom:16px;">
  <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Formas de Pagamento Aceitas</div>
  <div style="font-size:11px;line-height:1.6;">
    • <strong>PIX</strong> — pagamento instantâneo usando a chave acima<br/>
    • <strong>TED / Transferência Bancária</strong> — para os dados bancários informados<br/>
    • <strong>Boleto</strong> — solicite o boleto pelo telefone ou e-mail de contato
  </div>
  <div style="font-size:10px;color:#6b7280;margin-top:8px;">
    Após o pagamento, envie o comprovante para ${data.company.email || 'o e-mail de contato'} informando o número da fatura <strong>${esc(docNumber)}</strong>.
  </div>
</div>
` : ''}

${options.showTerms && data.terms ? `
<div style="border-top:1px solid #e5e7eb;padding-top:10px;margin-top:16px;">
  <div style="font-weight:700;font-size:10px;color:#1e3a5f;text-transform:uppercase;margin-bottom:4px;">Termos e Condições</div>
  <div style="font-size:9px;color:#6b7280;white-space:pre-wrap;">${esc(data.terms)}</div>
</div>
` : ''}

<div style="text-align:center;font-size:9px;color:#9ca3af;margin-top:20px;border-top:1px solid #e5e7eb;padding-top:8px;">
  FATURA gerada em ${today} · ${esc(docNumber)}
</div>`;

  return pageWrapper(`FATURA ${esc(docNumber)}`, body);
}

// ============= RECEIPT (RECIBO) =============
function buildReceiptHTML(data: PDFData, options: PDFOptions): string {
  const today = new Date().toLocaleDateString('pt-BR');
  const r = data.receipt || {
    amount: data.serviceOrder.grand_total,
    payment_date: new Date().toISOString(),
    payment_method: 'pix',
    reference: data.serviceOrder.service_order_number,
  };
  const methodLabel = PAYMENT_METHOD_LABELS[r.payment_method] || r.payment_method;
  const amountWords = numberToWordsBRL(r.amount);

  const body = `
${companyHeaderHTML(data.company)}

<div style="text-align:center;margin:30px 0 20px;">
  <h2 style="font-size:26px;letter-spacing:5px;color:#1e3a5f;margin:0;font-weight:800;">RECIBO DE PAGAMENTO</h2>
</div>

<div style="text-align:right;font-size:13px;margin-bottom:20px;">
  <strong>Valor:</strong> <span style="font-size:18px;font-weight:700;color:#1e3a5f;">${fmtCurrency(r.amount)}</span>
</div>

<div style="border:1px solid #e5e7eb;border-radius:6px;padding:20px;margin-bottom:24px;line-height:1.8;font-size:13px;">
  Recebemos de <strong>${esc(data.client.name)}</strong>${data.client.cpf_cnpj ? `, inscrito(a) no CPF/CNPJ <strong>${esc(data.client.cpf_cnpj)}</strong>,` : ''}
  a importância de <strong>${fmtCurrency(r.amount)}</strong>
  <em>(${esc(amountWords)})</em>,
  referente a <strong>${esc(r.reference || data.serviceOrder.service_order_number)}</strong>${data.vessel ? ` — embarcação <strong>${esc(data.vessel.name)}</strong>` : ''},
  pago via <strong>${esc(methodLabel)}</strong> em <strong>${fmtDate(r.payment_date)}</strong>.
  ${r.notes ? `<br/><br/><span style="color:#6b7280;">Obs.: ${esc(r.notes)}</span>` : ''}
  <br/><br/>
  Para clareza e validade, firmamos o presente recibo, dando plena, geral e irrevogável quitação do valor recebido.
</div>

<div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:24px;font-size:12px;">
  <div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Pagador</div>
    <div>
      <strong>${esc(data.client.name)}</strong><br/>
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${esc(data.client.cpf_cnpj)}<br/>` : ''}
      ${data.client.phone || ''}
    </div>
  </div>
  <div style="border:1px solid #e5e7eb;border-radius:6px;padding:10px;">
    <div style="font-weight:700;font-size:11px;color:#1e3a5f;text-transform:uppercase;margin-bottom:6px;">Recebedor</div>
    <div>
      <strong>${esc(data.company.name)}</strong><br/>
      ${data.company.cnpj ? `CNPJ: ${esc(data.company.cnpj)}<br/>` : ''}
      ${data.company.city ? `${esc(data.company.city)}${data.company.state ? ` - ${esc(data.company.state)}` : ''}` : ''}
    </div>
  </div>
</div>

<div style="text-align:center;margin-top:60px;">
  <div style="display:inline-block;text-align:center;min-width:280px;">
    <div style="border-top:1px solid #1f2937;padding-top:6px;">
      <strong>${esc(data.company.name)}</strong>
      <div style="font-size:10px;color:#6b7280;">${data.company.city || ''}${data.company.city ? ', ' : ''}${today}</div>
    </div>
  </div>
</div>

<div style="text-align:center;font-size:9px;color:#9ca3af;margin-top:30px;border-top:1px solid #e5e7eb;padding-top:8px;">
  RECIBO gerado em ${today} · Ref: ${esc(r.reference || data.serviceOrder.service_order_number)}
</div>`;

  return pageWrapper(`RECIBO — ${esc(r.reference || data.serviceOrder.service_order_number)}`, body);
}
