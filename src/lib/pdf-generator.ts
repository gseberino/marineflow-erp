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
  // Optional: include product images in parts table
  showProductImages?: boolean;
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
  showProductImages: false,
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
    logo_url?: string;
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
    travel_hours?: number;
    ferry_cost?: number;
    travel_type?: string;
    discount_amount: number;
    discount_services_pct?: number;
    discount_parts_pct?: number;
    tax_amount: number;
    operational_cost_total?: number;
    extra_notes?: string;
    payment_conditions?: string;
    payment_condition_label?: string | null;
    payment_condition_installments?: any[] | number | null;
    subcontract_cost_total?: number;
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
    name: string;
    description?: string;
    billing_unit: string;
    quantity: number;
    unit_price: number;
    line_total: number;
  }>;
  parts: Array<{
    name: string;
    sku?: string;
    quantity: number;
    unit_price: number;
    line_total: number;
    image_url?: string | null;
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
  photos?: string[];
};

export function generatePDF(data: PDFData, options: PDFOptions): void {
  const html = buildHTMLDocument(data, options);

  // Primary: open in a dedicated window so the OS always prints/saves from the
  // right context. The iframe approach causes iPadOS to save the main ERP page
  // instead of the generated PDF when the user taps "Save" in the share sheet.
  const win = window.open('', '_blank');
  if (win) {
    win.document.write(html);
    win.document.close();
    win.focus();
    setTimeout(() => win.print(), 500);
    return;
  }

  // Fallback (popup blocked): invisible iframe approach
  const iframe = document.createElement('iframe');
  iframe.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0;';
  document.body.appendChild(iframe);

  const doc = iframe.contentDocument || iframe.contentWindow?.document;
  if (!doc) {
    document.body.removeChild(iframe);
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

/**
 * Gera o PDF como Blob (sem abrir janela de impressão).
 * Usa html2pdf.js (jsPDF + html2canvas) renderizando o HTML montado por buildHTMLDocument.
 */
export async function generatePDFBlob(data: PDFData, options: PDFOptions): Promise<Blob> {
  const html = buildHTMLDocument(data, options);

  // html2canvas requires the element to be on-screen to capture correctly —
  // elements at left:-10000px render blank. We position at origin and hide from
  // the user with a white fixed overlay instead.
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;background:#fff;z-index:99999;pointer-events:none;';
  document.body.appendChild(overlay);

  const container = document.createElement('div');
  container.style.cssText = 'position:absolute;left:0;top:0;width:794px;background:#ffffff;pointer-events:none;';
  container.innerHTML = html;
  document.body.appendChild(container);

  // Aguarda o browser calcular layout + carregar fontes antes da captura
  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  if ((document as any).fonts?.ready) {
    try { await (document as any).fonts.ready; } catch { /* ignore */ }
  }

  try {
    // Import dinâmico para não pesar o bundle inicial
    const html2pdfModule: any = await import('html2pdf.js');
    const html2pdf = html2pdfModule.default || html2pdfModule;

    const blob: Blob = await html2pdf()
      .from(container)
      .set({
        margin: [10, 10, 10, 10],
        filename: 'documento.pdf',
        image: { type: 'jpeg', quality: 0.92 },
        html2canvas: {
          scale: 2,
          useCORS: true,
          backgroundColor: '#ffffff',
          windowWidth: 794,
          width: 794,
        },
        jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
        pagebreak: { mode: ['avoid-all', 'css', 'legacy'] },
      })
      .outputPdf('blob');

    // Sanity check — blob suspeito (<2KB) costuma significar página em branco
    if (blob.size < 2000) {
      console.warn('[generatePDFBlob] PDF suspeito de estar vazio:', {
        size: blob.size,
        scrollHeight: container.scrollHeight,
      });
    }
    return blob;
  } finally {
    if (document.body.contains(container)) document.body.removeChild(container);
    if (document.body.contains(overlay)) document.body.removeChild(overlay);
  }
}

/** Remove acentos, troca espaços por hífen e tira caracteres inválidos para nome de arquivo. */
function slugifyForFilename(value: string): string {
  return (value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // remove acentos
    .replace(/[^a-zA-Z0-9]+/g, '-')  // qualquer não-alfanumérico vira hífen
    .replace(/^-+|-+$/g, '')          // remove hífens das pontas
    .slice(0, 60);
}

const DOC_TYPE_FILENAME_LABEL: Record<PDFDocumentType, string> = {
  quote: 'Orcamento',
  service_order: 'OrdemServico',
  invoice: 'Fatura',
  receipt: 'Recibo',
};

/**
 * Monta o nome do arquivo PDF a partir do tipo de documento, número da OS,
 * cliente e embarcação/motorhome. Ex.: "OrdemServico_OS-00123_Joao-Silva_Lancha-Azul.pdf"
 */
export function buildPDFFilename(data: PDFData): string {
  const parts: string[] = [DOC_TYPE_FILENAME_LABEL[data.documentType] || 'Documento'];
  const soNumber = data.serviceOrder?.service_order_number;
  if (soNumber) parts.push(slugifyForFilename(String(soNumber)));
  const clientName = slugifyForFilename(data.client?.name || '');
  if (clientName) parts.push(clientName);
  const vesselName = slugifyForFilename(data.vessel?.name || '');
  if (vesselName) parts.push(vesselName);
  return `${parts.filter(Boolean).join('_')}.pdf`;
}

/**
 * Gera o PDF e dispara o download direto do arquivo, com nome adequado
 * (tipo do documento + número da OS + cliente + embarcação). Funciona
 * de forma idêntica em desktop, celular e tablet — não depende do diálogo
 * de impressão do navegador.
 */
export async function downloadPDF(data: PDFData, options: PDFOptions): Promise<void> {
  const blob = await generatePDFBlob(data, options);
  const filename = buildPDFFilename(data);
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  } finally {
    // Libera a memória do object URL após o download iniciar
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
}

/** Remove acentos, troca espaços por hífen e tira caracteres inválidos para nome de arquivo. */
function slugifyForFilename(value: string): string {
  return (value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // remove acentos
    .replace(/[^a-zA-Z0-9]+/g, '-')  // qualquer não-alfanumérico vira hífen
    .replace(/^-+|-+$/g, '')          // remove hífens das pontas
    .slice(0, 60);
}

const DOC_TYPE_FILENAME_LABEL: Record<PDFDocumentType, string> = {
  quote: 'Orcamento',
  service_order: 'OrdemServico',
  invoice: 'Fatura',
  receipt: 'Recibo',
};

/**
 * Monta o nome do arquivo PDF a partir do tipo de documento, número da OS,
 * cliente e embarcação/motorhome. Ex.: "OrdemServico_OS-00123_Joao-Silva_Lancha-Azul.pdf"
 */
export function buildPDFFilename(data: PDFData): string {
  const parts: string[] = [DOC_TYPE_FILENAME_LABEL[data.documentType] || 'Documento'];
  const soNumber = data.serviceOrder?.service_order_number;
  if (soNumber) parts.push(slugifyForFilename(String(soNumber)));
  const clientName = slugifyForFilename(data.client?.name || '');
  if (clientName) parts.push(clientName);
  const vesselName = slugifyForFilename(data.vessel?.name || '');
  if (vesselName) parts.push(vesselName);
  return `${parts.filter(Boolean).join('_')}.pdf`;
}

/**
 * Gera o PDF e dispara o download direto do arquivo, com nome adequado
 * (tipo do documento + número da OS + cliente + embarcação). Funciona
 * de forma idêntica em desktop, celular e tablet — não depende do diálogo
 * de impressão do navegador.
 */
export async function downloadPDF(data: PDFData, options: PDFOptions): Promise<void> {
  const blob = await generatePDFBlob(data, options);
  const filename = buildPDFFilename(data);
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  } finally {
    // Libera a memória do object URL após o download iniciar
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
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


function companyHeaderHTML(company: PDFData['company'], docTypeLabel: string, docNumber: string): string {
  const logoHtml = company.logo_url
    ? `<img src="${esc(company.logo_url)}" alt="${esc(company.name)}"
        style="max-height:80px;max-width:220px;object-fit:contain;"
        crossorigin="anonymous" />`
    : `<div style="font-size:28px;font-weight:900;color:var(--primary);letter-spacing:-1px;line-height:1;">
        ${esc(company.name).toUpperCase()}
       </div>`;

  return `
    <header style="display:flex;justify-content:space-between;margin-bottom:30px;align-items:flex-start;">
      <div style="flex:1;">
        ${logoHtml}
        <div style="margin-top:12px;font-size:10px;color:var(--text-muted);max-width:300px;line-height:1.4;">
          <strong>${esc(company.name)}</strong><br/>
          ${esc(company.address)}${company.city ? `, ${esc(company.city)}` : ''}${company.state ? ` - ${esc(company.state)}` : ''}<br/>
          ${company.cnpj ? `CNPJ: ${esc(company.cnpj)}` : ''}${company.phone ? ` · Tel: ${esc(company.phone)}` : ''}<br/>
          ${company.email ? `Email: ${esc(company.email)}` : ''}
        </div>
      </div>
      <div style="text-align:right;">
        <h1 style="font-size:24px;margin-bottom:4px;color:var(--primary);">${docTypeLabel}</h1>
        <div style="font-size:16px;font-weight:700;color:var(--secondary);">${esc(docNumber)}</div>
        <div style="margin-top:8px;font-size:10px;color:var(--text-muted);">
          Emissão: ${new Date().toLocaleDateString('pt-BR')}<br/>
          Página 01 / 01
        </div>
      </div>
    </header>
  `;
}

function pageWrapper(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<title>${title}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
  
  :root {
    --primary: #002B5B;
    --primary-light: #1A4D8B;
    --secondary: #D4AF37;
    --text-main: #1E293B;
    --text-muted: #64748B;
    --bg-light: #F8FAFC;
    --border: #E2E8F0;
  }

  * { margin:0; padding:0; box-sizing:border-box; }
  body { 
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
    font-size: 11px; 
    color: var(--text-main); 
    line-height: 1.5;
    background: #fff;
  }

  .container { padding: 40px; width: 100%; max-width: 800px; margin: 0 auto; }
  
  @media print {
    .container { padding: 0; }
    @page { margin: 12mm; size: A4; }
  }

  h1, h2, h3 { color: var(--primary); font-weight: 800; text-transform: uppercase; letter-spacing: 0.05em; }
  
  .card { 
    border: 1px solid var(--border); 
    border-radius: 8px; 
    padding: 16px; 
    margin-bottom: 20px;
    background: var(--bg-light);
  }

  .section-title {
    font-size: 10px;
    font-weight: 700;
    color: var(--primary-light);
    text-transform: uppercase;
    margin-bottom: 8px;
    border-bottom: 1px solid var(--border);
    padding-bottom: 4px;
    display: flex;
    justify-content: space-between;
  }

  table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
  th { 
    background: var(--primary); 
    color: #fff; 
    text-align: left; 
    padding: 8px 12px; 
    font-size: 9px; 
    text-transform: uppercase;
    font-weight: 600;
  }
  td { padding: 8px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
  tr:last-child td { border-bottom: none; }

  .summary-table td { padding: 4px 12px; border: none; }
  .total-row { background: var(--primary); color: #fff; font-weight: 800; font-size: 14px; }
  .total-row td { padding: 12px; }

  .badge {
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 9px;
    font-weight: 700;
    text-transform: uppercase;
  }
  .badge-primary { background: var(--primary); color: #fff; }

  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
</style>
</head>
<body>
  <div class="container">${body}</div>
</body>
</html>`;
}

// ============= QUOTE / SERVICE_ORDER (preserved behavior) =============
function buildPaymentSection(so: PDFData['serviceOrder']): string {
  const installments = so.payment_condition_installments;
  const hasInstallments = installments && Array.isArray(installments) && installments.length > 0;
  const hasText = !!so.payment_conditions;

  if (!hasInstallments && !hasText) return '';

  let installmentsHtml = '';
  if (hasInstallments) {
    const servicesTotal = Number(so.labor_cost_total || 0);
    const partsTotal = Number(so.parts_cost_total || 0);
    const expensesTotal =
      Number(so.travel_cost_total || 0) +
      Number(so.operational_cost_total || 0) +
      Number(so.subcontract_cost_total || 0);
    const grandTotal = Number(so.grand_total || 0);

    // Compute amount for each installment, supporting both formats:
    //   1) preset percentages: { services_pct, parts_pct, expenses_pct }
    //   2) flat percent: { percent }
    //   3) explicit amount: { amount }
    // Discount ratio ensures the installment amounts sum to grandTotal (not the gross subtotal)
    const subtotal = servicesTotal + partsTotal + expensesTotal;
    const discountRatio = subtotal > 0 ? grandTotal / subtotal : 1;

    const computedAmounts: number[] = installments.map((inst: any) => {
      if (typeof inst.amount === 'number' && !isNaN(inst.amount)) return Math.round(inst.amount * discountRatio * 100) / 100;
      if (typeof inst.percent === 'number' && !isNaN(inst.percent)) {
        return Math.round(grandTotal * (inst.percent / 100) * 100) / 100;
      }
      const sPct = Number(inst.services_pct || 0) / 100;
      const pPct = Number(inst.parts_pct || 0) / 100;
      const ePct = Number(inst.expenses_pct || 0) / 100;
      // Apply discount ratio so amounts reflect the final discounted total
      const gross = servicesTotal * sPct + partsTotal * pPct + expensesTotal * ePct;
      return Math.round(gross * discountRatio * 100) / 100;
    });

    // Sanity adjust: if rounding leaves a residue, push it onto the last installment
    const sum = computedAmounts.reduce((a, b) => a + b, 0);
    if (grandTotal > 0 && Math.abs(sum - grandTotal) < 1 && computedAmounts.length > 0) {
      const diff = Math.round((grandTotal - sum) * 100) / 100;
      computedAmounts[computedAmounts.length - 1] =
        Math.round((computedAmounts[computedAmounts.length - 1] + diff) * 100) / 100;
    }

    const rows = installments.map((inst: any, idx: number) => {
      const eventLabel = inst.due_date
        ? fmtDate(inst.due_date)
        : (inst.label || (inst.tipo === 'aprovacao' ? 'Na aprovação' : inst.tipo === 'entrega' ? 'Na entrega' : '—'));
      return `
      <tr>
        <td style="font-weight:600;padding:6px 12px;">Parcela ${idx + 1}</td>
        <td style="padding:6px 12px;">${esc(eventLabel)}</td>
        <td style="text-align:right;font-weight:700;padding:6px 12px;">${fmtCurrency(computedAmounts[idx])}</td>
      </tr>
    `;
    }).join('');

    installmentsHtml = `
      <table style="margin-bottom:0; width:100%; border-collapse:collapse;">
        <thead>
          <tr style="background:rgba(212, 175, 55, 0.05);color:var(--primary);">
            <th style="background:transparent;color:var(--primary);width:30%;">Vencimento</th>
            <th style="background:transparent;color:var(--primary);width:40%;">Data/Evento</th>
            <th style="background:transparent;color:var(--primary);text-align:right;">Valor</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  return `
    <div class="card" style="margin-top:20px;border-left:4px solid var(--secondary); background:#fff;">
      <div class="section-title">
        <span>Programação de Pagamento</span>
        <span style="color:var(--text-muted);font-size:8px;">${esc(so.payment_condition_label || 'Condição Comercial')}</span>
      </div>
      ${installmentsHtml}
      ${hasText ? (() => {
        // Tenta calcular parcelas a partir do texto livre
        // Detecta padrões como "50% mão de obra + 100% materiais"
        const servicesTotal = Number(so.labor_cost_total || 0);
        const partsTotal = Number(so.parts_cost_total || 0);
        const grandTotal = Number(so.grand_total || 0);

        const svcMatch = (so.payment_conditions || '').match(/(\d+(?:[.,]\d+)?)\s*%\s*(?:m[aã]o[\s\-]de[\s\-]obra|servi[cç]os?|labor)/i);
        const partsMatch = (so.payment_conditions || '').match(/(\d+(?:[.,]\d+)?)\s*%\s*(?:materiais?|pe[cç]as?|produtos?|parts?)/i);
        const totalPctMatch = (so.payment_conditions || '').match(/^(\d+(?:[.,]\d+)?)\s*%\s*(?:entrada|antecipado|adiantamento)/i);

        const hasCalc = (svcMatch || partsMatch || totalPctMatch) && grandTotal > 0;

        let calcHtml = '';
        if (hasCalc) {
          const rows: string[] = [];
          if (svcMatch) {
            const pct = parseFloat(svcMatch[1].replace(',', '.'));
            const val = servicesTotal * (pct / 100);
            if (val > 0) rows.push(`<tr><td style="padding:4px 8px;">${pct}% Mão de obra</td><td style="text-align:right;font-weight:700;padding:4px 8px;">${fmtCurrency(val)}</td></tr>`);
          }
          if (partsMatch) {
            const pct = parseFloat(partsMatch[1].replace(',', '.'));
            const val = partsTotal * (pct / 100);
            if (val > 0) rows.push(`<tr><td style="padding:4px 8px;">${pct}% Materiais</td><td style="text-align:right;font-weight:700;padding:4px 8px;">${fmtCurrency(val)}</td></tr>`);
          }
          if (totalPctMatch && rows.length === 0) {
            const pct = parseFloat(totalPctMatch[1].replace(',', '.'));
            const val = grandTotal * (pct / 100);
            rows.push(`<tr><td style="padding:4px 8px;">Entrada (${pct}%)</td><td style="text-align:right;font-weight:700;padding:4px 8px;">${fmtCurrency(val)}</td></tr>`);
          }
          if (rows.length > 0) {
            calcHtml = `<table style="width:100%;border-collapse:collapse;margin-top:6px;font-size:10px;">${rows.join('')}</table>`;
          }
        }

        return `<div style="font-size:10px;color:var(--text-main);margin-top:8px;padding:8px;background:var(--bg-light);border-radius:4px;border:1px dashed var(--border);white-space:pre-wrap;">${esc(so.payment_conditions)}</div>${calcHtml}`;
      })() : ''}
    </div>
  `;
}

function buildOrderHTML(data: PDFData, options: PDFOptions): string {
  const isQuote = data.documentType === 'quote';
  const docTypeLabel = isQuote ? 'Orçamento' : 'Ordem de Serviço';
  const docNumber = data.serviceOrder.service_order_number;

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const getValidityText = (): string => {
    const v = options.validity;
    if (!v || v.mode === 'days') {
      const days = v?.days || 15;
      const expiry = new Date();
      expiry.setDate(expiry.getDate() + days);
      return `Válido por ${days} dias (até ${expiry.toLocaleDateString('pt-BR')})`;
    }
    if (v.date) {
      const d = new Date(v.date + 'T12:00:00');
      return `Válido até ${d.toLocaleDateString('pt-BR')}`;
    }
    return 'Válido por 15 dias.';
  };

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="font-weight:600;">${esc(s.name)}${s.description ? `<div style="font-weight:400;color:var(--text-muted);font-size:9px;margin-top:2px;">${esc(s.description)}</div>` : ''}</td>
      <td style="text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      ${options.showServicePrices ? `<td style="text-align:right;">${fmtCurrency(s.unit_price)}</td>` : ''}
      <td style="text-align:right;font-weight:600;">${fmtCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => {
    const showImg = !!options.showProductImages && !!p.image_url;
    const itemCell = showImg 
      ? `<div style="display:flex;align-items:center;gap:10px;">
           <img src="${esc(p.image_url!)}" style="width:40px;height:40px;object-fit:cover;border-radius:4px;border:1px solid var(--border);" crossorigin="anonymous" />
           <div>
             <div style="font-weight:600;">${esc(p.name)}</div>
             ${p.sku ? `<div style="font-size:9px;color:var(--text-muted);">#${esc(p.sku)}</div>` : ''}
           </div>
         </div>`
      : `<div style="font-weight:600;">${esc(p.name)}</div>
         ${p.sku ? `<div style="font-size:9px;color:var(--text-muted);">#${esc(p.sku)}</div>` : ''}`;

    return `
    <tr>
      <td>${itemCell}</td>
      <td style="text-align:center;">${p.quantity}</td>
      ${options.showPartsPrices ? `<td style="text-align:right;">${fmtCurrency(p.unit_price)}</td>` : ''}
      <td style="text-align:right;font-weight:600;">${fmtCurrency(p.line_total)}</td>
    </tr>
  `;}).join('');

  const photoGallery = (data.photos && data.photos.length > 0) ? `
    <div style="page-break-before: always; margin-top: 40px;">
      <div class="section-title">Galeria Técnica / Evidências do Serviço</div>
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; margin-top: 10px;">
        ${data.photos.map(url => `
          <div style="border:1px solid var(--border); border-radius:8px; overflow:hidden; background:var(--bg-light);">
            <img src="${esc(url)}" style="width:100%; height:200px; object-fit:cover;" crossorigin="anonymous" />
          </div>
        `).join('')}
      </div>
      <div style="font-size:9px; color:var(--text-muted); margin-top:8px; text-align:center;">
        As imagens acima servem como registro técnico das etapas e componentes analisados/substituídos.
      </div>
    </div>
  ` : '';

  const summaryRows = [
    data.services.length > 0 ? `<tr><td>Subtotal Serviços</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0 ? `<tr><td>Subtotal Peças</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0 ? `<tr><td>Deslocamento / Logística</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    (data.serviceOrder.operational_cost_total ?? 0) > 0 ? `<tr><td>Outras Despesas</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.operational_cost_total!)}</td></tr>` : '',
    (() => {
      if (!options.showDiscount || data.serviceOrder.discount_amount <= 0) return '';
      const sPct = data.serviceOrder.discount_services_pct ?? 0;
      const pPct = data.serviceOrder.discount_parts_pct ?? 0;
      const hasBreakdown = (sPct > 0 || pPct > 0) && (sPct + pPct > 0);
      if (hasBreakdown) {
        const dSvc = Math.round(data.serviceOrder.labor_cost_total * sPct / 100 * 100) / 100;
        const dPts = Math.round(data.serviceOrder.parts_cost_total * pPct / 100 * 100) / 100;
        return [
          dSvc > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Serviços (${sPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dSvc)}</td></tr>` : '',
          dPts > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Peças (${pPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dPts)}</td></tr>` : '',
          `<tr><td style="color:#dc2626;font-weight:600;">Total Desconto</td><td style="text-align:right;color:#dc2626;font-weight:600;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`,
        ].filter(Boolean).join('');
      }
      return `<tr><td style="color:#dc2626;">Desconto Especial</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`;
    })(),
  ].filter(Boolean).join('');

  const body = `
${companyHeaderHTML(data.company, docTypeLabel, docNumber)}

<div class="grid">
  <div class="card">
    <div class="section-title">Informações do Cliente</div>
    <div style="font-size:12px;font-weight:700;color:var(--primary);">${esc(data.client.name)}</div>
    ${data.client.cpf_cnpj ? `<div style="font-size:10px;">CPF/CNPJ: ${esc(data.client.cpf_cnpj)}</div>` : ''}
    ${data.client.phone ? `<div style="font-size:10px;">Fone: ${esc(data.client.phone)}</div>` : ''}
    ${data.client.email ? `<div style="font-size:10px;">Email: ${esc(data.client.email)}</div>` : ''}
    ${data.client.address ? `<div style="font-size:10px;margin-top:4px;color:var(--text-muted);">${esc(data.client.address)}</div>` : ''}
  </div>
  <div class="card">
    <div class="section-title">Dados do Ativo / Localização</div>
    ${data.vessel ? `<div style="font-size:12px;font-weight:700;color:var(--primary);">${esc(data.vessel.name)}</div>` : ''}
    <div style="font-size:10px;">
      ${data.vessel?.manufacturer ? `${esc(data.vessel.manufacturer)} ${esc(data.vessel.model || '')} (${data.vessel.year || '—'})<br/>` : ''}
      ${data.vessel?.registration ? `Registro: ${data.vessel.registration}<br/>` : ''}
      ${data.marina ? `<strong>Marina:</strong> ${esc(data.marina.name)}${data.marina.city ? ` (${esc(data.marina.city)})` : ''}` : ''}
    </div>
  </div>
</div>

<div class="card">
  <div class="section-title">${isQuote ? 'Objetivo do Projeto / Diagnóstico' : 'Relato do Problema'}</div>
  <div style="white-space:pre-wrap;font-size:11px;line-height:1.6;">${esc(data.serviceOrder.problem_description || 'Nenhuma descrição fornecida.')}</div>
</div>

${data.services.length > 0 ? `
<div class="section-title">Cronograma de Serviços / Mão de Obra</div>
<table>
  <thead>
    <tr>
      <th style="width:55%;">Descrição Técnica</th>
      <th style="width:15%;text-align:center;">Qtd/Unid</th>
      ${options.showServicePrices ? '<th style="width:15%;text-align:right;">Unitário</th>' : ''}
      <th style="width:15%;text-align:right;">Subtotal</th>
    </tr>
  </thead>
  <tbody>${serviceRows}</tbody>
</table>
` : ''}

${data.parts.length > 0 ? `
<div class="section-title">Peças, Equipamentos e Materiais</div>
<table>
  <thead>
    <tr>
      <th style="width:55%;">Item / Especificação</th>
      <th style="width:15%;text-align:center;">Qtd</th>
      ${options.showPartsPrices ? '<th style="width:15%;text-align:right;">Unitário</th>' : ''}
      <th style="width:15%;text-align:right;">Subtotal</th>
    </tr>
  </thead>
  <tbody>${partsRows}</tbody>
</table>
` : ''}

${!isQuote && data.serviceOrder.technical_notes ? `
<div class="card" style="background:#F0F4F8;border-left:4px solid var(--primary);">
  <div class="section-title">Conclusão Técnica / Recomendações</div>
  <div style="white-space:pre-wrap;font-size:11px;font-style:italic;">${esc(data.serviceOrder.technical_notes)}</div>
</div>
` : ''}

<div style="display:flex;justify-content:flex-end;">
  <div style="width:300px;">
    <table class="summary-table">
      <tbody>
        ${summaryRows}
        <tr class="total-row">
          <td>VALOR TOTAL</td>
          <td style="text-align:right;">${fmtCurrency(data.serviceOrder.grand_total)}</td>
        </tr>
      </tbody>
    </table>
    ${isQuote ? `<div style="text-align:right;font-size:10px;font-weight:700;color:var(--secondary);margin-top:-10px;padding-right:12px;">${getValidityText()}</div>` : ''}
  </div>
</div>

${buildPaymentSection(data.serviceOrder)}

${options.showBankDetails !== false && data.bank && (data.bank.bank_name || data.bank.pix_key) ? `
<div class="card" style="margin-top:20px; background:rgba(212, 175, 55, 0.03); border:1px solid rgba(212, 175, 55, 0.2);">
  <div class="section-title">Informações para Pagamento / Transferência</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;font-size:10px;">
    <div>
      <strong style="color:var(--primary);display:block;margin-bottom:4px;">DADOS BANCÁRIOS</strong>
      ${data.bank.bank_name ? `Banco: ${esc(data.bank.bank_name)}<br/>` : ''}
      ${data.bank.bank_agency ? `Agência: ${esc(data.bank.bank_agency)} · ` : ''}${data.bank.bank_account ? `Conta: ${esc(data.bank.bank_account)}` : ''}<br/>
      Favorecido: ${esc(data.company.name)}<br/>
      CNPJ: ${esc(data.company.cnpj || '—')}
    </div>
    <div style="border-left:1px solid rgba(212, 175, 55, 0.2);padding-left:20px;">
      <strong style="color:var(--primary);display:block;margin-bottom:4px;">PAGAMENTO VIA PIX</strong>
      Chave: <span style="font-size:12px;font-weight:800;color:var(--secondary);">${esc(data.bank.pix_key || '—')}</span><br/>
      <span style="font-size:9px;color:var(--text-muted);display:block;margin-top:6px;">Por favor, envie o comprovante para <strong>${esc(data.company.email)}</strong> para agilizar a baixa.</span>
    </div>
  </div>
</div>
` : ''}

<div class="grid" style="margin-top:40px;">
  <div style="text-align:center;">
    <div style="height:60px;"></div>
    <div style="border-top:1px solid var(--primary);padding-top:8px;">
      <div style="font-weight:700;text-transform:uppercase;color:var(--primary);">${esc(data.company.name)}</div>
      <div style="font-size:9px;color:var(--text-muted);">Responsável Técnico</div>
    </div>
  </div>
  <div style="text-align:center;">
    <div style="height:60px;"></div>
    <div style="border-top:1px solid var(--primary);padding-top:8px;">
      <div style="font-weight:700;text-transform:uppercase;color:var(--primary);">${esc(data.client.name)}</div>
      <div style="font-size:9px;color:var(--text-muted);">${isQuote ? 'Aprovação do Orçamento' : 'Aceite do Serviço Realizado'}</div>
    </div>
  </div>
</div>

${photoGallery}

${options.showTerms && data.terms ? `
<div style="margin-top:30px;padding-top:10px;border-top:1px dashed var(--border);">
  <div style="font-size:9px;font-weight:700;color:var(--primary-light);text-transform:uppercase;margin-bottom:4px;">Condições Gerais e Garantia</div>
  <div style="font-size:8.5px;color:var(--text-muted);white-space:pre-wrap;text-align:justify;">${esc(data.terms)}</div>
</div>
` : ''}

<footer style="margin-top:30px;text-align:center;font-size:9px;color:var(--text-muted);border-top:1px solid var(--border);padding-top:10px; display:flex; justify-content:space-between; align-items:center;">
  <span>MarineFlow ERP · Documento Digital Autenticado</span>
  <span>Página 01 / 01</span>
  <span>Emitido em ${new Date().toLocaleString('pt-BR')}</span>
</footer>
`;

  return pageWrapper(`${docTypeLabel} ${docNumber}`, body);
}

// ============= INVOICE (FATURA) =============
function buildInvoiceHTML(data: PDFData, options: PDFOptions): string {
  const docNumber = `FAT-${esc(data.serviceOrder.service_order_number)}`;
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
      <td style="font-weight:600;">${esc(s.name)}${s.description ? `<div style="font-weight:400;color:var(--text-muted);font-size:9px;">${esc(s.description)}</div>` : ''}</td>
      <td style="text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      <td style="text-align:right;font-weight:600;">${fmtCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => `
    <tr>
      <td style="font-weight:600;">${esc(p.name)}</td>
      <td style="text-align:center;">${p.quantity}</td>
      <td style="text-align:right;font-weight:600;">${fmtCurrency(p.line_total)}</td>
    </tr>
  `).join('');

  const summaryRows = [
    data.services.length > 0 ? `<tr><td>Serviços Executados</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0 ? `<tr><td>Materiais e Peças</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0 ? `<tr><td>Custos de Deslocamento</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    (() => {
      if (!options.showDiscount || data.serviceOrder.discount_amount <= 0) return '';
      const sPct = data.serviceOrder.discount_services_pct ?? 0;
      const pPct = data.serviceOrder.discount_parts_pct ?? 0;
      const hasBreakdown = sPct > 0 || pPct > 0;
      if (hasBreakdown) {
        const dSvc = Math.round(data.serviceOrder.labor_cost_total * sPct / 100 * 100) / 100;
        const dPts = Math.round(data.serviceOrder.parts_cost_total * pPct / 100 * 100) / 100;
        return [
          dSvc > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Serviços (${sPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dSvc)}</td></tr>` : '',
          dPts > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Peças (${pPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dPts)}</td></tr>` : '',
          `<tr><td style="color:#dc2626;font-weight:600;">Total Desconto</td><td style="text-align:right;color:#dc2626;font-weight:600;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`,
        ].filter(Boolean).join('');
      }
      return `<tr><td style="color:#dc2626;">Desconto Especial</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`;
    })(),
  ].filter(Boolean).join('');

  const bank = data.bank || {};
  const hasBank = !!(bank.bank_name || bank.bank_agency || bank.bank_account || bank.pix_key);

  const body = `
${companyHeaderHTML(data.company, 'Fatura de Serviço', docNumber)}

<div class="grid">
  <div class="card" style="border-left:4px solid var(--secondary);">
    <div class="section-title">Resumo Financeiro</div>
    <div style="font-size:10px;color:var(--text-muted);">Vencimento:</div>
    <div style="font-size:16px;font-weight:800;color:#dc2626;margin-bottom:8px;">${dueDate}</div>
    <div style="font-size:10px;color:var(--text-muted);">Total a Pagar:</div>
    <div style="font-size:18px;font-weight:800;color:var(--primary);">${fmtCurrency(data.serviceOrder.grand_total)}</div>
  </div>
  <div class="card">
    <div class="section-title">Informações do Pagador</div>
    <div style="font-size:12px;font-weight:700;color:var(--primary);">${esc(data.client.name)}</div>
    <div style="font-size:10px;color:var(--text-muted);">
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${esc(data.client.cpf_cnpj)}<br/>` : ''}
      ${data.client.email || ''}
    </div>
  </div>
</div>

<div class="section-title">Detalhamento dos Itens</div>
<table>
  <thead>
    <tr>
      <th>Descrição do Serviço / Produto</th>
      <th style="text-align:center;width:100px;">Qtd</th>
      <th style="text-align:right;width:120px;">Subtotal</th>
    </tr>
  </thead>
  <tbody>
    ${serviceRows}
    ${partsRows}
  </tbody>
</table>

<div style="display:flex;justify-content:flex-end;margin-bottom:30px;">
  <div style="width:300px;">
    <table class="summary-table">
      <tbody>
        ${summaryRows}
        <tr class="total-row">
          <td>VALOR TOTAL</td>
          <td style="text-align:right;">${fmtCurrency(data.serviceOrder.grand_total)}</td>
        </tr>
      </tbody>
    </table>
  </div>
</div>

${options.showBankDetails !== false && hasBank ? `
<div class="card">
  <div class="section-title">Instruções para Pagamento</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;font-size:10px;line-height:1.6;">
    <div>
      <strong>Dados Bancários:</strong><br/>
      ${bank.bank_name ? `Banco: ${esc(bank.bank_name)}<br/>` : ''}
      ${bank.bank_agency ? `Agência: ${esc(bank.bank_agency)} · ` : ''}${bank.bank_account ? `Conta: ${esc(bank.bank_account)}` : ''}<br/>
      Favorecido: ${esc(data.company.name)}<br/>
      ${data.company.cnpj ? `CNPJ: ${esc(data.company.cnpj)}` : ''}
    </div>
    <div style="border-left:1px solid var(--border);padding-left:12px;">
      <strong>Pague via PIX:</strong><br/>
      Chave: <span style="font-size:11px;font-weight:700;color:var(--primary);">${esc(bank.pix_key || 'N/A')}</span><br/>
      <span style="font-size:9px;color:var(--text-muted);margin-top:4px;display:block;">Após o pagamento, envie o comprovante para ${data.company.email || 'nosso contato'}.</span>
    </div>
  </div>
</div>
` : ''}

<footer style="margin-top:50px;text-align:center;font-size:9px;color:var(--text-muted);">
  Referente à Ordem de Serviço ${esc(data.serviceOrder.service_order_number)} · Gerado em ${new Date().toLocaleString('pt-BR')}
</footer>
`;

  return pageWrapper(`FATURA ${docNumber}`, body);
}


// ============= RECEIPT (RECIBO) =============
function buildReceiptHTML(data: PDFData, options: PDFOptions): string {
  const r = data.receipt || {
    amount: data.serviceOrder.grand_total,
    payment_date: new Date().toISOString(),
    payment_method: 'pix',
    reference: data.serviceOrder.service_order_number,
  };
  const docNumber = `REC-${esc(r.reference || data.serviceOrder.service_order_number)}`;
  const methodLabel = PAYMENT_METHOD_LABELS[r.payment_method] || r.payment_method;
  const amountWords = numberToWordsBRL(r.amount);

  const body = `
${companyHeaderHTML(data.company, 'Recibo de Quitação', docNumber)}

<div class="card" style="margin:30px 0;padding:30px;background:white;position:relative;overflow:hidden;">
  <div style="position:absolute;top:0;left:0;width:4px;height:100%;background:var(--secondary);"></div>
  <div style="text-align:right;margin-bottom:20px;">
    <div style="font-size:10px;color:var(--text-muted);text-transform:uppercase;">Valor Recebido</div>
    <div style="font-size:24px;font-weight:800;color:var(--primary);">${fmtCurrency(r.amount)}</div>
  </div>
  
  <div style="font-size:14px;line-height:2;text-align:justify;color:var(--text-main);">
    Recebemos de <strong>${esc(data.client.name).toUpperCase()}</strong>, 
    ${data.client.cpf_cnpj ? `inscrito(a) no CPF/CNPJ sob o nº <strong>${esc(data.client.cpf_cnpj)}</strong>, ` : ''}
    a importância líquida e certa de <strong>${fmtCurrency(r.amount)}</strong> 
    <span style="font-size:11px;color:var(--text-muted);">(${esc(amountWords)})</span>, 
    referente ao pagamento de <strong>${esc(r.reference || data.serviceOrder.service_order_number)}</strong>
    ${data.vessel ? ` (Ativo: ${esc(data.vessel.name)})` : ''}.
  </div>
  
  <div style="margin-top:20px;font-size:12px;color:var(--text-muted);">
    Forma de Pagamento: <strong>${esc(methodLabel)}</strong><br/>
    Data da Transação: <strong>${fmtDate(r.payment_date)}</strong>
  </div>
</div>

<div class="grid">
  <div class="card">
    <div class="section-title">Dados do Emissor</div>
    <div style="font-size:11px;">
      <strong>${esc(data.company.name)}</strong><br/>
      CNPJ: ${esc(data.company.cnpj || '—')}<br/>
      ${esc(data.company.city || '')} / ${esc(data.company.state || '')}
    </div>
  </div>
  <div style="text-align:center;padding-top:20px;">
    <div style="height:50px;"></div>
    <div style="border-top:1px solid var(--primary);padding-top:8px;">
      <div style="font-weight:700;font-size:11px;">${esc(data.company.name).toUpperCase()}</div>
      <div style="font-size:9px;color:var(--text-muted);">Assinatura Autorizada</div>
    </div>
  </div>
</div>

<footer style="margin-top:50px;text-align:center;font-size:9px;color:var(--text-muted);">
  Este recibo confirma a quitação do valor acima descrito para os fins de direito.
</footer>
`;

  return pageWrapper(`RECIBO ${docNumber}`, body);
}
