/**
 * O documento da ordem (orçamento e OS) em HTML: tipos, opções, nome do arquivo e o desenho.
 *
 * ═══ POR QUE MORA EM supabase/functions/_shared ═══
 *
 * Até 25/09/2026 isto vivia em src/lib/pdf-generator.ts, no mesmo arquivo que o código de
 * navegador (janela de impressão, html2canvas). A montagem do HTML já era pura — só junta
 * texto —, mas o arquivo não carregava fora do navegador, e o assistente do WhatsApp, que
 * roda numa Edge Function, não tinha como gerar o PDF que o dono pedia.
 *
 * Aqui a tela e o assistente usam o MESMO arquivo: o front importa daqui (como já faz com
 * _shared/banking e _shared/service-order-status) e o Deno também. Uma cópia do desenho
 * para o servidor divergiria da tela no primeiro ajuste de layout.
 *
 * Regras para manter isto importável dos dois lados: nada de window/document/localStorage,
 * nada de biblioteca de tela, imports relativos com extensão .ts, e data SEMPRE por
 * ./datas.ts — a Edge Function roda em UTC, e `toLocaleDateString` sem fuso imprimiria o
 * dia seguinte para tudo que aconteceu depois das 21h de Brasília.
 *
 * Fatura e recibo continuam em src/lib/pdf-generator.ts: só o navegador os gera.
 */
import { scopeCss } from './css-scope.ts';
import { itemColumnWidths, valueVisibility } from './pdf-visibility.ts';
import { dataBR, dataHoraBR, diaBR, horaBR, somarDiasAoDia, somarDiasBR } from './datas.ts';

export type PDFDocumentType = 'quote' | 'service_order' | 'invoice' | 'receipt';

export type PDFOptions = {
  showServicePrices: boolean;
  showPartsPrices: boolean;
  showTravelCost: boolean;
  showDiscount: boolean;
  showTax: boolean;
  showCardFee: boolean;
  showCommission: boolean;
  showTerms: boolean;
  showSignature: boolean;
  // Optional: include product images in parts table
  showProductImages?: boolean;
  /**
   * Via de execução (NOVO-006b): a OS impressa para quem vai executar o serviço, sem NENHUM
   * valor — nem unitário, nem subtotal, nem total, nem condição de pagamento, nem dados
   * bancários. Existe porque a folha que vai para o campo circula por marina, terceiro e
   * ajudante, e o preço combinado com o cliente não tem por que viajar junto.
   *
   * É diferente de desmarcar `showServicePrices`/`showPartsPrices`: aqueles escondem a coluna
   * unitária e mantêm subtotal e total. Aqui não sobra número nenhum.
   */
  hideFinancials?: boolean;
  /**
   * "Observações para impressão" (service_orders.extra_notes). Até 16/09/2026 o campo era
   * preenchido no formulário, entregue ao gerador em `serviceOrder.extra_notes` e IGNORADO
   * pelo template — o texto nunca chegou a documento nenhum, e como não havia toggle o dono
   * não tinha como perceber. Ligado por padrão: quem escreveu ali escreveu para o cliente ler.
   */
  showExtraNotes?: boolean;
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
  showCardFee: true,
  showCommission: false,
  showTerms: true,
  showSignature: true,
  showProductImages: false,
  showExtraNotes: true,
  hideFinancials: false,
  showBankDetails: true,
  showPaymentInstructions: true,
};

/**
 * Resolve o PADRÃO DA EMPRESA para um tipo de documento: o que estiver gravado em
 * app_settings (chave `pdf_options_<tipo>`) sobre o padrão de fábrica.
 *
 * Quem grava essa chave é a tela de Configurações › Documentos, e só ela (MF-AUD-014). Até
 * 10/08/2026 quem gravava era o diálogo de Baixar/Imprimir, a cada clique: desmarcar "incluir
 * termos" uma única vez desligava os termos da empresa inteira, para todos os documentos
 * futuros daquele tipo — inclusive os enviados por WhatsApp, que leem daqui.
 *
 * Usado pelo diálogo (como estado inicial dos checkboxes) e pelo envio direto por WhatsApp
 * (que não tem diálogo e portanto usa o padrão puro).
 *
 * Só chaves conhecidas e só valores booleanos entram. Um `pdf_options_quote` com sujeira —
 * um número, uma string, uma chave que não existe mais — cai no padrão de fábrica em vez de
 * contaminar `PDFOptions` com campos que o gerador não entende. `validity` e `dueDate` são
 * deliberadamente ignorados: descrevem um documento, nunca um padrão.
 */
export function resolvePdfOptions(
  appSettings: Record<string, string> | undefined,
  documentType: PDFDocumentType,
): PDFOptions {
  const raw = appSettings?.[`pdf_options_${documentType}`];
  if (!raw) return { ...DEFAULT_PDF_OPTIONS };
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { ...DEFAULT_PDF_OPTIONS };
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { ...DEFAULT_PDF_OPTIONS };
  }
  const saved = parsed as Record<string, unknown>;
  const resolved: PDFOptions = { ...DEFAULT_PDF_OPTIONS };
  for (const key of Object.keys(DEFAULT_PDF_OPTIONS) as Array<keyof PDFOptions>) {
    const value = saved[key];
    if (typeof value === 'boolean') (resolved as Record<string, unknown>)[key] = value;
  }
  return resolved;
}

/**
 * A validade que vai impressa no orçamento: a do PRÓPRIO orçamento
 * (service_orders.quote_validity_days); sem ela, o padrão da empresa
 * (app_settings.quote_validity_days); sem os dois, 15.
 *
 * ═══ POR QUE UMA FUNÇÃO SÓ ═══
 *
 * Até 26/09/2026 cada caminho do PDF decidia por conta própria. O Baixar do formulário e o
 * assistente usavam a do orçamento; o envio pela tela (SendViaWhatsAppDialog) e o Baixar do
 * portal do cliente não passavam validade nenhuma, porque `resolvePdfOptions` a descarta — e
 * o gerador caía no literal 15. Um orçamento de 3 dias ia para o cliente dizendo "Válido por
 * 15 dias", enquanto a rotina de expiração o rejeitava no 7º dia. É o caso das "três fontes
 * para o mesmo padrão" (config, coluna e literal): aqui a ordem entre elas é decidida uma vez.
 *
 * `settings` é o mapa de app_settings de quem chama. No portal (anônimo) a chave
 * `quote_validity_days` não está na whitelist, então lá o padrão da empresa não chega e a
 * conta fica em orçamento → 15 — sem efeito prático hoje, porque a coluna tem DEFAULT 15 e
 * nenhum orçamento vivo a tem vazia.
 */
export function validadeDoOrcamento(
  diasDoOrcamento: unknown,
  settings?: Record<string, unknown> | null,
): { mode: 'days'; days: number } {
  const padraoDaEmpresa = Number(settings?.quote_validity_days ?? 15) || 15;
  return { mode: 'days', days: Number(diasDoOrcamento) || padraoDaEmpresa };
}

/**
 * O ÚLTIMO dia (aaaa-mm-dd, calendário de Brasília) em que o orçamento vale — o mesmo "até"
 * que o PDF imprime em "Válido por N dias (até dd/mm/aaaa)".
 *
 * `quote_validity_date` (data fixa) vence se existir. Senão, dia de Brasília da emissão
 * (`created_at`, decisão D13: reimprimir não renova) mais a validade de `validadeDoOrcamento`.
 * Devolve null quando não há data de emissão legível — sem ela não há o que comparar.
 */
export function ultimoDiaDaValidade(
  orcamento: { created_at?: string | null; quote_validity_date?: string | null; quote_validity_days?: unknown },
  settings?: Record<string, unknown> | null,
): string | null {
  const fixa = String(orcamento.quote_validity_date ?? '').slice(0, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(fixa)) return fixa;
  if (!orcamento.created_at) return null;
  const emissao = new Date(orcamento.created_at);
  if (Number.isNaN(emissao.getTime())) return null;
  return somarDiasAoDia(diaBR(emissao), validadeDoOrcamento(orcamento.quote_validity_days, settings).days);
}

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
  /**
   * Levantamento feito antes de orçar.
   *
   * Vai para o documento porque é ele que sustenta o preço diante do cliente:
   * "medi a distância do banco ao quadro, são 14 metros — daí a bitola e o
   * valor do cabo". Sem isso o orçamento é um número sem defesa, e a conversa
   * de desconto começa do zero.
   */
  survey?: {
    answered_at?: string | null;
    rationale?: string | null;
    answers: Array<{
      question: string;
      answer?: string | null;
      skipped?: string | null;
      hasPhoto?: boolean;
    }>;
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
    card_fee_amount?: number;
    card_installments?: number;
    extra_notes?: string;
    payment_conditions?: string;
    payment_condition_label?: string | null;
    payment_condition_installments?: any[] | number | null;
    subcontract_cost_total?: number;
    financial_notes?: string;
    payment_method_preferred?: string;
    quote_validity_days?: number;
    deposit_paid?: number;
    // Registro real de cobranças/pagamentos — distinto da "Programação de
    // Pagamento" (que só mostra o plano acordado, preset ou texto livre).
    // Aninhado dentro de serviceOrder para que os builders (que recebem
    // PDFData['serviceOrder']) consigam ler estes campos.
    receivables?: Array<{
      id: string;
      description: string;
      amount: number;
      balance_amount: number;
      status: string;
      is_deposit: boolean;
    }>;
    payments?: Array<{
      receivable_id: string;
      payment_date: string; // ISO
      amount: number;
      payment_method: string;
    }>;
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
export function buildPDFFilename(data: PDFData, options?: PDFOptions): string {
  const parts: string[] = [DOC_TYPE_FILENAME_LABEL[data.documentType] || 'Documento'];
  // A via de execução tem que se distinguir no nome do arquivo: as duas versões da MESMA OS
  // acabam na mesma pasta de downloads, e a diferença entre elas é justamente o que não pode
  // ir para a mão errada (NOVO-006b).
  if (options?.hideFinancials && data.documentType === 'service_order') parts.push('Via-Execucao');
  const soNumber = data.serviceOrder?.service_order_number;
  if (soNumber) parts.push(slugifyForFilename(String(soNumber)));
  const clientName = slugifyForFilename(data.client?.name || '');
  if (clientName) parts.push(clientName);
  const vesselName = slugifyForFilename(data.vessel?.name || '');
  if (vesselName) parts.push(vesselName);
  return `${parts.filter(Boolean).join('_')}.pdf`;
}

/** Título da janela de impressão = nome do arquivo sem `.pdf`: é o que o navegador sugere ao salvar. */
export function tituloParaImpressao(data: PDFData, options?: PDFOptions): string {
  return buildPDFFilename(data, options).replace(/\.pdf$/i, '');
}

export const PAYMENT_METHOD_LABELS: Record<string, string> = {
  pix: 'PIX',
  credit_card: 'Cartão de Crédito',
  debit_card: 'Cartão de Débito',
  cash: 'Dinheiro',
  bank_transfer: 'Transferência Bancária',
  check: 'Cheque',
  boleto: 'Boleto',
  ted: 'TED',
};

export const fmtCurrency = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

// 'aaaa-mm-dd' (coluna date) sai como está; instante, no dia de Brasília. Ver ./datas.ts —
// era aqui que o "Pago em" da tela saía um dia antes.
export const fmtDate = (iso?: string) => {
  if (!iso) return '—';
  return dataBR(iso);
};

/**
 * Texto corrido em parágrafos: um <p> por linha do campo.
 *
 * Um único <div white-space:pre-wrap> era UM bloco para quem pagina. O navegador ainda
 * quebra entre linhas, mas a captura do Baixar fatia a imagem onde calhar — inclusive no
 * meio de uma linha. Com um elemento por linha, a paginação do Baixar mede e empurra
 * linha a linha, e a impressão ganha orphans/widows de verdade.
 */
export const paragrafos = (texto: unknown, estilo: string): string => {
  // Parágrafo = bloco separado por linha em branco; as quebras de linha DENTRO dele ficam
  // (pre-wrap). Uma linha por <p> — a primeira versão, 16/09 — deixava o navegador livre
  // para cortar entre duas linhas quaisquer, e o título "CONDIÇÕES GERAIS" saiu sozinho
  // no pé de uma página. Com o parágrafo inteiro num <p>, `orphans/widows` valem de
  // verdade e um subtítulo em caixa alta gruda no parágrafo seguinte.
  const blocos = String(texto ?? '')
    .replace(/\r\n?/g, '\n')
    .split(/\n[ \t]*\n+/)
    .map((b) => b.replace(/^\n+|\n+$/g, ''))
    .filter((b) => b.trim() !== '');
  return blocos
    .map((b) => {
      const gruda = pareceSubtitulo(b) ? 'break-after:avoid;page-break-after:avoid;' : '';
      return `<p style="margin:0 0 0.8em;white-space:pre-wrap;${gruda}${estilo}">${esc(b)}</p>`;
    })
    .join('');
};

/** "GARANTIA", "CONDIÇÕES TÉCNICAS": uma linha curta, em caixa alta, sem pontuação final. */
const pareceSubtitulo = (bloco: string): boolean => {
  const t = bloco.trim();
  return !t.includes('\n') && t.length <= 80 && /[A-ZÁ-Ú]/.test(t) && t === t.toUpperCase() && !/[.:;,!?]$/.test(t);
};

export const esc = (v: unknown): string => {
  if (v === null || v === undefined) return '';
  return String(v)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
};


/** dd/mm/aaaa de uma data ISO; sem data válida, cai em hoje (documentos antigos sem created_at). */
function dataCurta(iso?: string | null): string {
  const d = iso ? new Date(iso) : new Date();
  return dataBR(Number.isNaN(d.getTime()) ? new Date() : d);
}

export function companyHeaderHTML(
  company: PDFData['company'],
  docTypeLabel: string,
  docNumber: string,
  datas: { emissao?: string | null; agendado?: string | null } = {},
): string {
  // D14 (17/09/2026): a OS impressa mostra a data agendada quando houver.
  const agendado = datas.agendado ? new Date(datas.agendado) : null;
  const linhaAgendado = agendado && !Number.isNaN(agendado.getTime())
    ? `<div style="margin-top:2px;font-size:10px;color:var(--pdf-text-muted);">Agendado para: ${dataBR(agendado)} ${horaBR(agendado)}</div>`
    : '';
  const logoHtml = company.logo_url
    // Fundo em vez de <img>: um logo que não carrega (URL do projeto antigo, rede fora) não
    // deixa rastro — <img> quebrado imprime o texto alternativo no lugar, e o render no
    // servidor roda sem JavaScript, então `onerror` não salvaria.
    ? `<div role="img" aria-label="${esc(company.name)}"
        style="width:220px;height:80px;background:url('${esc(company.logo_url)}') left center / contain no-repeat;"></div>`
    : `<div style="font-size:28px;font-weight:900;color:var(--pdf-primary);letter-spacing:-1px;line-height:1;">
        ${esc(company.name).toUpperCase()}
       </div>`;

  return `
    <header style="display:flex;justify-content:space-between;margin-bottom:30px;align-items:flex-start;">
      <div style="flex:1;">
        ${logoHtml}
        <div style="margin-top:12px;font-size:10px;color:var(--pdf-text-muted);max-width:300px;line-height:1.4;">
          <strong>${esc(company.name)}</strong><br/>
          ${esc(company.address)}${company.city ? `, ${esc(company.city)}` : ''}${company.state ? ` - ${esc(company.state)}` : ''}<br/>
          ${company.cnpj ? `CNPJ: ${esc(company.cnpj)}` : ''}${company.phone ? ` · Tel: ${esc(company.phone)}` : ''}<br/>
          ${company.email ? `Email: ${esc(company.email)}` : ''}
        </div>
      </div>
      <div style="text-align:right;">
        <h1 style="font-size:24px;margin-bottom:4px;color:var(--pdf-primary);">${docTypeLabel}</h1>
        <div style="font-size:16px;font-weight:700;color:var(--pdf-secondary);">${esc(docNumber)}</div>
        <div style="margin-top:8px;font-size:10px;color:var(--pdf-text-muted);">
          Emissão: ${dataCurta(datas.emissao)}
        </div>${linhaAgendado}
      </div>
    </header>
  `;
}

/**
 * Classe que delimita o documento.
 *
 * Tudo do PDF vive dentro dela, e todo o CSS é preso a ela antes de sair —
 * ver `scopeCss`. Sem isso, baixar o PDF repintava o ERP inteiro por um
 * segundo, porque `* { margin:0 }` e `body { font-size:11px }` não têm como
 * saber que só valem para o documento.
 */
export const PDF_ROOT_CLASS = 'mf-pdf-doc';

export function pageWrapper(title: string, body: string): string {
  // O CSS sai preso à raiz do documento. É isto que impede as regras globais
  // (`*`, `body`, `h1`) de repintarem o app enquanto o html2canvas captura —
  // o solavanco visual de um segundo ao clicar em Baixar.
  const css = scopeCss(`
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
  
  :root {
    --pdf-primary: #002B5B;
    --pdf-primary-light: #1A4D8B;
    --pdf-secondary: #D4AF37;
    --pdf-text-main: #1E293B;
    --pdf-text-muted: #64748B;
    --pdf-bg-light: #F8FAFC;
    --pdf-border: #E2E8F0;
  }

  * { margin:0; padding:0; box-sizing:border-box; }
  body { 
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
    font-size: 11px; 
    color: var(--pdf-text-main); 
    line-height: 1.5;
    background: #fff;
  }

  .container { padding: 40px; width: 100%; max-width: 800px; margin: 0 auto; }
  
  @media print {
    .container { padding: 0; }
    @page { margin: 12mm; size: A4; }
  }

  h1, h2, h3 { color: var(--pdf-primary); font-weight: 800; text-transform: uppercase; letter-spacing: 0.05em; }
  
  .card { 
    border: 1px solid var(--pdf-border); 
    border-radius: 8px; 
    padding: 16px; 
    margin-bottom: 20px;
    background: var(--pdf-bg-light);
  }

  .section-title {
    font-size: 10px;
    font-weight: 700;
    color: var(--pdf-primary-light);
    text-transform: uppercase;
    margin-bottom: 8px;
    border-bottom: 1px solid var(--pdf-border);
    padding-bottom: 4px;
    display: flex;
    justify-content: space-between;
    /* Título de seção nunca fica sozinho no pé da página, longe do que ele nomeia. */
    break-after: avoid;
    page-break-after: avoid;
  }

  table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
  th { 
    background: var(--pdf-primary); 
    color: #fff; 
    text-align: left; 
    padding: 8px 12px; 
    font-size: 9px; 
    text-transform: uppercase;
    font-weight: 600;
  }
  td { padding: 8px 12px; border-bottom: 1px solid var(--pdf-border); vertical-align: top; }
  tr:last-child td { border-bottom: none; }

  .summary-table td { padding: 4px 12px; border: none; }
  .total-row { background: var(--pdf-primary); color: #fff; font-weight: 800; font-size: 14px; }
  .total-row td { padding: 12px; }

  .badge {
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 9px;
    font-weight: 700;
    text-transform: uppercase;
  }
  .badge-primary { background: var(--pdf-primary); color: #fff; }

  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }

  /* ── Quebra de página ──────────────────────────────────────────────────
     Sem estas regras o documento parte onde calhar: card de condições de
     pagamento cortado ao meio, linha de tabela com o valor numa página e a
     descrição na outra, título de seção sozinho no pé. Valem para os DOIS
     caminhos — a impressão do navegador entende \`page-break-*\`, e o
     html2pdf lê as mesmas regras no modo \`css\`. */
  .card, .badge, .signature-box { page-break-inside: avoid; break-inside: avoid; }
  /* Texto corrido (objetivo, observações, conclusão técnica, termos) PODE partir entre
     linhas. Travá-lo inteiro empurrava o card para a folha seguinte e deixava meia página
     em branco — e, maior que a folha, ele partia de qualquer jeito. O gerador emite um <p>
     por linha justamente para a quebra cair ENTRE linhas nos dois caminhos. */
  .pdf-texto { page-break-inside: auto; break-inside: auto; }
  .pdf-texto p { orphans: 3; widows: 3; }
  table { page-break-inside: auto; }
  tr    { page-break-inside: avoid; break-inside: avoid; }
  /* Cabeçalho de tabela se repete em cada página: tabela longa sem cabeçalho
     na segunda página obriga a voltar para saber o que é cada coluna. */
  thead { display: table-header-group; }
  tfoot { display: table-footer-group; }
  /* Título nunca fica órfão no pé da página, longe do que ele nomeia. */
  h1, h2, h3 { page-break-after: avoid; break-after: avoid; }
  /* Duas linhas soltas no fim ou no começo da página é o que mais suja a
     leitura de um texto corrido. */
  p { orphans: 3; widows: 3; }

  /* As cores do documento têm que sair na impressão. Por padrão o navegador
     remove fundos e imagens ao imprimir para poupar tinta — e o cabeçalho
     azul, as tarjas e o total em destaque sairiam brancos no papel. */
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
`, `.${PDF_ROOT_CLASS}`);
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<title>${title}</title>
<style>${css}</style>
</head>
<body>
  <div class="${PDF_ROOT_CLASS}"><div class="container">${body}</div></div>
</body>
</html>`;
}

// ============= QUOTE / SERVICE_ORDER (preserved behavior) =============
export function buildPaymentSection(so: PDFData['serviceOrder']): string {
  // "Mostrar o real, esconder o plano": quando já existe pagamento registrado,
  // a Programação de Pagamento (o plano acordado) não bate mais com a
  // realidade e só confunde — some, dando lugar à seção de pagamentos reais.
  if ((so.payments?.length ?? 0) > 0) return '';

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
          <tr style="background:rgba(212, 175, 55, 0.05);color:var(--pdf-primary);">
            <th style="background:transparent;color:var(--pdf-primary);width:30%;">Vencimento</th>
            <th style="background:transparent;color:var(--pdf-primary);width:40%;">Data/Evento</th>
            <th style="background:transparent;color:var(--pdf-primary);text-align:right;">Valor</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  return `
    <div class="card" style="margin-top:20px;border-left:4px solid var(--pdf-secondary); background:#fff;">
      <div class="section-title">
        <span>Programação de Pagamento</span>
        <span style="color:var(--pdf-text-muted);font-size:8px;">${esc(so.payment_condition_label || 'Condição Comercial')}</span>
      </div>
      ${installmentsHtml}
      ${(hasText && !hasInstallments) ? (() => {
        // Recálculo via regex do texto livre só roda quando NÃO há parcelas
        // estruturadas (preset/personalizado) — senão duplica/conflita com
        // a tabela de parcelas já renderizada acima. Selecionar um preset
        // preenche payment_conditions com o label dele automaticamente
        // (ServiceOrderForm.tsx), então hasText fica true mesmo sem o
        // usuário ter digitado nada manualmente.
        // Tenta calcular parcelas a partir do texto livre
        // Detecta padrões como "50% mão de obra + 100% materiais"
        const servicesTotal = Number(so.labor_cost_total || 0);
        const partsTotal = Number(so.parts_cost_total || 0);
        const grandTotal = Number(so.grand_total || 0);

        const svcMatch = (so.payment_conditions || '').match(/(\d+(?:[.,]\d+)?)\s*%\s*(?:m[aã]o[\s-]de[\s-]obra|servi[cç]os?|labor)/i);
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

        return `<div style="font-size:10px;color:var(--pdf-text-main);margin-top:8px;padding:8px;background:var(--pdf-bg-light);border-radius:4px;border:1px dashed var(--pdf-border);white-space:pre-wrap;">${esc(so.payment_conditions)}</div>${calcHtml}`;
      })() : ''}
    </div>
  `;
}

const RECEIVABLE_STATUS_LABELS: Record<string, string> = {
  paid: 'Pago',
  partially_paid: 'Parcial',
  pending: 'Pendente',
  overdue: 'Vencido',
};

/**
 * Registro real de cobranças/pagamentos já efetuados — distinto de
 * buildPaymentSection (que mostra só o plano acordado). Mostra o que
 * realmente foi cobrado/pago/está em aberto, mesmo quando o pagamento real
 * não seguiu exatamente a programação combinada.
 */
export function buildPaymentHistorySection(so: PDFData['serviceOrder']): string {
  const payments = so.payments || [];
  // Só aparece quando há de fato um pagamento registrado (senão o documento
  // mostra a "Programação de Pagamento"/plano). Ver buildPaymentSection.
  if (payments.length === 0) return '';

  const receivables = so.receivables || [];
  const totalCharged = receivables.reduce((s, r) => s + (r.amount || 0), 0);
  const totalBalance = receivables.reduce((s, r) => s + (r.balance_amount || 0), 0);
  const totalPaid = Math.max(0, totalCharged - totalBalance);

  // Selo de situação global da OS.
  const isPaid = totalCharged > 0 && totalBalance <= 0.01;
  const statusLabel = isPaid ? 'Quitado' : totalPaid > 0 ? 'Parcialmente pago' : 'Em aberto';
  const statusColor = isPaid ? '#16a34a' : totalPaid > 0 ? '#d97706' : '#dc2626';

  const rows = receivables.map((r) => {
    const recColor = r.status === 'paid' ? '#16a34a' : r.status === 'partially_paid' ? '#d97706' : 'var(--pdf-text-muted)';
    // Rótulo claro: "Sinal" para depósito, senão a descrição do recebível.
    const recLabel = r.is_deposit ? `Sinal — ${esc(r.description)}` : esc(r.description);
    const relatedPayments = payments.filter((p) => p.receivable_id === r.id);
    const paymentsHtml = relatedPayments.map((p) => {
      const methodLabel = PAYMENT_METHOD_LABELS[p.payment_method] || p.payment_method;
      return `
        <tr>
          <td style="padding:2px 12px 2px 24px;font-size:9px;color:var(--pdf-text-muted);">↳ Pago em ${esc(fmtDate(p.payment_date))}${methodLabel ? ` — ${esc(methodLabel)}` : ''}</td>
          <td style="text-align:right;padding:2px 12px;font-size:9px;color:var(--pdf-text-muted);">${fmtCurrency(p.amount)}</td>
        </tr>
      `;
    }).join('');
    return `
      <tr>
        <td style="font-weight:600;padding:6px 12px;">${recLabel}</td>
        <td style="text-align:right;padding:6px 12px;">
          ${fmtCurrency(r.amount)}
          <span style="font-size:8px;font-weight:600;margin-left:6px;color:${recColor};">${esc(RECEIVABLE_STATUS_LABELS[r.status] || r.status)}</span>
        </td>
      </tr>
      ${paymentsHtml}
    `;
  }).join('');

  return `
    <div class="card" style="margin-top:20px;border-left:4px solid var(--pdf-secondary); background:#fff;">
      <div class="section-title">
        <span>Situação de Pagamento</span>
        <span style="font-size:8px;font-weight:700;padding:2px 8px;border-radius:10px;color:#fff;background:${statusColor};">${statusLabel}</span>
      </div>
      <div style="display:flex;justify-content:space-between;gap:12px;margin-bottom:10px;">
        <div style="flex:1;text-align:center;padding:8px;background:var(--pdf-bg-light);border-radius:4px;">
          <div style="font-size:8px;color:var(--pdf-text-muted);text-transform:uppercase;">Total</div>
          <div style="font-size:13px;font-weight:700;">${fmtCurrency(totalCharged)}</div>
        </div>
        <div style="flex:1;text-align:center;padding:8px;background:var(--pdf-bg-light);border-radius:4px;">
          <div style="font-size:8px;color:var(--pdf-text-muted);text-transform:uppercase;">Pago</div>
          <div style="font-size:13px;font-weight:700;color:#16a34a;">${fmtCurrency(totalPaid)}</div>
        </div>
        <div style="flex:1;text-align:center;padding:8px;background:var(--pdf-bg-light);border-radius:4px;">
          <div style="font-size:8px;color:var(--pdf-text-muted);text-transform:uppercase;">Saldo em Aberto</div>
          <div style="font-size:13px;font-weight:700;color:${totalBalance > 0.01 ? '#dc2626' : '#16a34a'};">${fmtCurrency(totalBalance)}</div>
        </div>
      </div>
      <table style="width:100%; border-collapse:collapse;">
        <tbody>${rows}</tbody>
      </table>
    </div>
  `;
}

/** Orçamento ou OS — o documento que a tela baixa e que o assistente manda pelo WhatsApp. */
export function buildOrderHTML(data: PDFData, options: PDFOptions): string {
  const isQuote = data.documentType === 'quote';
  // Via de execução (NOVO-006b): documento para o campo, sem valor nenhum. Um orçamento sem
  // preço não é um documento — é um mal-entendido —, então a opção só vale para a OS.
  const semValores = !!options.hideFinancials && !isQuote;
  const docTypeLabel = isQuote ? 'Orçamento' : semValores ? 'Ordem de Serviço — Via de Execução' : 'Ordem de Serviço';
  const docNumber = data.serviceOrder.service_order_number;

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const getValidityText = (): string => {
    const v = options.validity;
    if (!v || v.mode === 'days') {
      const days = v?.days || 15;
      // D13 (17/09/2026): a validade conta da EMISSÃO (created_at), não do dia em que
      // alguém reimprimiu. Reimprimir um orçamento de 20 dias não o renova por mais 15.
      const base = data.serviceOrder.created_at ? new Date(data.serviceOrder.created_at) : new Date();
      const emissao = Number.isNaN(base.getTime()) ? new Date() : base;
      return `Válido por ${days} dias (até ${somarDiasBR(emissao, days)})`;
    }
    if (v.date) {
      return `Válido até ${dataBR(v.date)}`;
    }
    return 'Válido por 15 dias.';
  };

  // O que aparece de valor. Desmarcar uma seção no diálogo esconde o preço
  // dela INTEIRO — unitário e total —, e sem preço em nenhuma seção o resumo
  // financeiro some junto. Antes a opção tirava só a coluna "Unitário", e o
  // documento saía com os totais mesmo com tudo desmarcado.
  const vis = valueVisibility(options);

  // As larguras seguem a contagem de colunas para fecharem em 100%. Com literais, uma
  // coluna de valor a menos deixava 15% sem dono — e imprimir e baixar redistribuíam
  // a sobra de jeitos diferentes. Na via de execução não há coluna de valor nenhuma.
  const colServico = itemColumnWidths(!semValores && vis.servicoUnitario, !semValores && vis.servicoTotal);
  const colPeca = itemColumnWidths(!semValores && vis.pecaUnitario, !semValores && vis.pecaTotal);

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="font-weight:600;">${esc(s.name)}${s.description ? `<div style="font-weight:400;color:var(--pdf-text-muted);font-size:9px;margin-top:2px;">${esc(s.description)}</div>` : ''}</td>
      <td style="text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      ${semValores ? '' : `
      ${vis.servicoUnitario ? `<td style="text-align:right;">${fmtCurrency(s.unit_price)}</td>` : ''}
      ${vis.servicoTotal ? `<td style="text-align:right;font-weight:600;">${fmtCurrency(s.line_total)}</td>` : ''}`}
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => {
    const showImg = !!options.showProductImages && !!p.image_url;
    const itemCell = showImg 
      ? `<div style="display:flex;align-items:center;gap:10px;">
           <img src="${esc(p.image_url!)}" style="width:40px;height:40px;object-fit:cover;border-radius:4px;border:1px solid var(--pdf-border);" crossorigin="anonymous" />
           <div>
             <div style="font-weight:600;">${esc(p.name)}</div>
             ${p.sku ? `<div style="font-size:9px;color:var(--pdf-text-muted);">#${esc(p.sku)}</div>` : ''}
           </div>
         </div>`
      : `<div style="font-weight:600;">${esc(p.name)}</div>
         ${p.sku ? `<div style="font-size:9px;color:var(--pdf-text-muted);">#${esc(p.sku)}</div>` : ''}`;

    return `
    <tr>
      <td>${itemCell}</td>
      <td style="text-align:center;">${p.quantity}</td>
      ${semValores ? '' : `
      ${vis.pecaUnitario ? `<td style="text-align:right;">${fmtCurrency(p.unit_price)}</td>` : ''}
      ${vis.pecaTotal ? `<td style="text-align:right;font-weight:600;">${fmtCurrency(p.line_total)}</td>` : ''}`}
    </tr>
  `;}).join('');

  const photoGallery = (data.photos && data.photos.length > 0) ? `
    <div style="page-break-before: always; margin-top: 40px;">
      <div class="section-title">Galeria Técnica / Evidências do Serviço</div>
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; margin-top: 10px;">
        ${data.photos.map(url => `
          <div style="border:1px solid var(--pdf-border); border-radius:8px; overflow:hidden; background:var(--pdf-bg-light);">
            <img src="${esc(url)}" style="width:100%; height:200px; object-fit:cover;" crossorigin="anonymous" />
          </div>
        `).join('')}
      </div>
      <div style="font-size:9px; color:var(--pdf-text-muted); margin-top:8px; text-align:center;">
        As imagens acima servem como registro técnico das etapas e componentes analisados/substituídos.
      </div>
    </div>
  ` : '';

  const summaryRows = semValores ? '' : [
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
    options.showCardFee && (data.serviceOrder.card_fee_amount ?? 0) > 0
      ? `<tr><td>Taxa de cartão${data.serviceOrder.card_installments ? ` (${data.serviceOrder.card_installments}x)` : ''}</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.card_fee_amount!)}</td></tr>`
      : '',
  ].filter(Boolean).join('');

  const body = `
${companyHeaderHTML(data.company, docTypeLabel, docNumber, {
  // D13: a emissão é a data em que o documento nasceu, não a de cada reimpressão.
  emissao: data.serviceOrder.created_at,
  agendado: isQuote ? null : data.serviceOrder.scheduled_start_at,
})}

${semValores ? `
<div style="margin:0 0 12px;padding:8px 12px;border:1px dashed var(--pdf-border);border-radius:6px;background:var(--pdf-bg-light);font-size:10px;color:var(--pdf-text-muted);">
  <strong style="color:var(--pdf-primary);text-transform:uppercase;">Via de execução</strong> — documento de campo, sem valores.
  Para a via com preços, condições de pagamento e dados bancários, gere a versão completa desta mesma OS.
</div>` : ''}

<div class="grid">
  <div class="card">
    <div class="section-title">Informações do Cliente</div>
    <div style="font-size:12px;font-weight:700;color:var(--pdf-primary);">${esc(data.client.name)}</div>
    ${data.client.cpf_cnpj ? `<div style="font-size:10px;">CPF/CNPJ: ${esc(data.client.cpf_cnpj)}</div>` : ''}
    ${data.client.phone ? `<div style="font-size:10px;">Fone: ${esc(data.client.phone)}</div>` : ''}
    ${data.client.email ? `<div style="font-size:10px;">Email: ${esc(data.client.email)}</div>` : ''}
    ${data.client.address ? `<div style="font-size:10px;margin-top:4px;color:var(--pdf-text-muted);">${esc(data.client.address)}</div>` : ''}
  </div>
  <div class="card">
    <div class="section-title">Dados do Ativo / Localização</div>
    ${data.vessel ? `<div style="font-size:12px;font-weight:700;color:var(--pdf-primary);">${esc(data.vessel.name)}</div>` : ''}
    <div style="font-size:10px;">
      ${data.vessel?.manufacturer ? `${esc(data.vessel.manufacturer)} ${esc(data.vessel.model || '')} (${data.vessel.year || '—'})<br/>` : ''}
      ${data.vessel?.registration ? `Registro: ${esc(data.vessel.registration)}<br/>` : ''}
      ${data.marina ? `<strong>Marina:</strong> ${esc(data.marina.name)}${data.marina.city ? ` (${esc(data.marina.city)})` : ''}` : ''}
    </div>
  </div>
</div>

<div class="card pdf-texto" data-pdf-quebra="dentro">
  <div class="section-title">${isQuote ? 'Objetivo do Projeto / Diagnóstico' : 'Relato do Problema'}</div>
  ${paragrafos(data.serviceOrder.problem_description || 'Nenhuma descrição fornecida.', 'font-size:11px;line-height:1.6;')}
</div>

${(data.survey?.answers?.length || 0) > 0 ? `
<div class="card">
  <div class="section-title">Levantamento Técnico no Local</div>
  <div style="font-size:10px;color:var(--pdf-text-muted);margin-bottom:6px;">
    O que foi verificado antes de orçar${data.survey?.answered_at
      ? ` — ${dataBR(data.survey.answered_at)}`
      : ''}.
  </div>
  <table>
    <thead>
      <tr>
        <th style="width:52%;">Verificado</th>
        <th style="width:48%;">Constatação</th>
      </tr>
    </thead>
    <tbody>
      ${data.survey!.answers
        .map((a) => `
        <tr>
          <td style="font-size:10px;">${esc(a.question)}</td>
          <td style="font-size:10px;">${
            a.skipped
              ? `<span style="color:var(--pdf-text-muted);font-style:italic;">não foi possível verificar — ${esc(a.skipped)}</span>`
              : esc(a.answer || '—')
          }${a.hasPhoto ? ' <span style="color:var(--pdf-primary);">📷</span>' : ''}</td>
        </tr>`)
        .join('')}
    </tbody>
  </table>
  ${data.survey?.rationale ? `
  <div style="margin-top:8px;font-size:10px;line-height:1.5;">
    <strong>Conclusão de quem levantou:</strong> ${esc(data.survey.rationale)}
  </div>` : ''}
</div>` : ''}

${data.services.length > 0 ? `
<div class="section-title">Cronograma de Serviços / Mão de Obra</div>
<table>
  <thead>
    <tr>
      <th style="width:${colServico.descricao}%;">Descrição Técnica</th>
      <th style="width:${colServico.quantidade}%;text-align:center;">Qtd/Unid</th>
      ${semValores ? '' : `
      ${vis.servicoUnitario ? `<th style="width:${colServico.valor}%;text-align:right;">Unitário</th>` : ''}
      ${vis.servicoTotal ? `<th style="width:${colServico.valor}%;text-align:right;">Subtotal</th>` : ''}`}
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
      <th style="width:${colPeca.descricao}%;">Item / Especificação</th>
      <th style="width:${colPeca.quantidade}%;text-align:center;">Qtd</th>
      ${semValores ? '' : `
      ${vis.pecaUnitario ? `<th style="width:${colPeca.valor}%;text-align:right;">Unitário</th>` : ''}
      ${vis.pecaTotal ? `<th style="width:${colPeca.valor}%;text-align:right;">Subtotal</th>` : ''}`}
    </tr>
  </thead>
  <tbody>${partsRows}</tbody>
</table>
` : ''}

${!isQuote && data.serviceOrder.technical_notes ? `
<div class="card pdf-texto" data-pdf-quebra="dentro" style="background:#F0F4F8;border-left:4px solid var(--pdf-primary);">
  <div class="section-title">Conclusão Técnica / Recomendações</div>
  ${paragrafos(data.serviceOrder.technical_notes, 'font-size:11px;font-style:italic;')}
</div>
` : ''}

${semValores ? '' : `
${vis.resumoFinanceiro ? `
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
    ${isQuote ? `<div style="text-align:right;font-size:10px;font-weight:700;color:var(--pdf-secondary);margin-top:-10px;padding-right:12px;">${getValidityText()}</div>` : ''}
  </div>
</div>` : ''}

${buildPaymentSection(data.serviceOrder)}
${buildPaymentHistorySection(data.serviceOrder)}

${data.serviceOrder.financial_notes ? `
<div class="card pdf-texto" data-pdf-quebra="dentro" style="border-left:4px solid var(--pdf-border);margin-top:8px;">
  <div class="section-title">Observações Financeiras</div>
  ${paragrafos(data.serviceOrder.financial_notes, 'font-size:10px;line-height:1.6;color:var(--pdf-text-main);')}
</div>
` : ''}`}

${!semValores && options.showBankDetails !== false && data.bank && (data.bank.bank_name || data.bank.pix_key) ? `
<div class="card" style="margin-top:20px; background:rgba(212, 175, 55, 0.03); border:1px solid rgba(212, 175, 55, 0.2);">
  <div class="section-title">Informações para Pagamento${data.serviceOrder.payment_method_preferred ? ` — ${PAYMENT_METHOD_LABELS[data.serviceOrder.payment_method_preferred] || data.serviceOrder.payment_method_preferred}` : ''}</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;font-size:10px;">
    <div>
      <strong style="color:var(--pdf-primary);display:block;margin-bottom:4px;">DADOS BANCÁRIOS</strong>
      ${data.bank.bank_name ? `Banco: ${esc(data.bank.bank_name)}<br/>` : ''}
      ${data.bank.bank_agency ? `Agência: ${esc(data.bank.bank_agency)} · ` : ''}${data.bank.bank_account ? `Conta: ${esc(data.bank.bank_account)}` : ''}<br/>
      Favorecido: ${esc(data.company.name)}<br/>
      CNPJ: ${esc(data.company.cnpj || '—')}
    </div>
    <div style="border-left:1px solid rgba(212, 175, 55, 0.2);padding-left:20px;">
      <strong style="color:var(--pdf-primary);display:block;margin-bottom:4px;">PAGAMENTO VIA PIX</strong>
      Chave: <span style="font-size:12px;font-weight:800;color:var(--pdf-secondary);">${esc(data.bank.pix_key || '—')}</span><br/>
      <span style="font-size:9px;color:var(--pdf-text-muted);display:block;margin-top:6px;">Por favor, envie o comprovante para <strong>${esc(data.company.email)}</strong> para agilizar a baixa.</span>
    </div>
  </div>
</div>
` : ''}

${options.showSignature !== false ? `
<div class="grid" style="margin-top:40px;">
  <div style="text-align:center;">
    <div style="height:60px;"></div>
    <div style="border-top:1px solid var(--pdf-primary);padding-top:8px;">
      <div style="font-weight:700;text-transform:uppercase;color:var(--pdf-primary);">${esc(data.company.name)}</div>
      <div style="font-size:9px;color:var(--pdf-text-muted);">Responsável Técnico</div>
    </div>
  </div>
  <div style="text-align:center;">
    <div style="height:60px;"></div>
    <div style="border-top:1px solid var(--pdf-primary);padding-top:8px;">
      <div style="font-weight:700;text-transform:uppercase;color:var(--pdf-primary);">${esc(data.client.name)}</div>
      <div style="font-size:9px;color:var(--pdf-text-muted);">${isQuote ? 'Aprovação do Orçamento' : 'Aceite do Serviço Realizado'}</div>
    </div>
  </div>
</div>
` : ''}

${photoGallery}

${options.showExtraNotes !== false && !semValores && data.serviceOrder.extra_notes ? `
<div class="card pdf-texto" data-pdf-quebra="dentro" style="border-left:4px solid var(--pdf-primary);margin-top:8px;">
  <div class="section-title">Observações</div>
  ${paragrafos(data.serviceOrder.extra_notes, 'font-size:10.5px;line-height:1.6;color:var(--pdf-text-main);')}
</div>
` : ''}

${options.showTerms && data.terms ? `
<div class="pdf-texto" data-pdf-quebra="dentro" style="margin-top:30px;padding-top:10px;border-top:1px dashed var(--pdf-border);">
  <div style="font-size:9px;font-weight:700;color:var(--pdf-primary-light);text-transform:uppercase;margin-bottom:4px;break-after:avoid;page-break-after:avoid;">Condições Gerais e Garantia</div>
  ${paragrafos(data.terms, 'font-size:8.5px;color:var(--pdf-text-muted);text-align:justify;')}
</div>
` : ''}

<footer style="margin-top:30px;text-align:center;font-size:9px;color:var(--pdf-text-muted);border-top:1px solid var(--pdf-border);padding-top:10px; display:flex; justify-content:space-between; align-items:center;">
  <span>MarineFlow ERP · Documento Digital Autenticado</span>
  <span>Emitido em ${dataHoraBR(new Date())}</span>
</footer>
`;

  return pageWrapper(`${docTypeLabel} ${docNumber}`, body);
}
