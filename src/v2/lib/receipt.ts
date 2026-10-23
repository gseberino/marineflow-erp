import { supabase } from '@/integrations/supabase/client';
import { DEFAULT_PDF_OPTIONS, type PDFData } from '@/lib/pdf-generator';
import { printPDF } from '@/lib/pdf-print';
import { toast } from 'sonner';
import { documentoMascarado, nomeSemCpf } from '../../../supabase/functions/_shared/banking/contraparte';

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

type PagamentoDoRecibo = {
  id: string;
  amount: number | string;
  payment_date: string;
  payment_method: string | null;
  notes: string | null;
  status: string | null;
};

type QuemPagou = {
  pagador_nome: string | null;
  pagador_documento: string | null;
  situacao: 'cliente' | 'terceiro' | 'indefinido' | 'sem_dado' | null;
};

export type DadosDoRecibo = { ok: true; pdf: PDFData } | { ok: false; erro: string };

const motivo = (e: unknown) => (e as { message?: string })?.message ?? String(e);

/**
 * Os dados do recibo de UM pagamento de conta a receber — a função única do recibo (ReceivablesV2, FinancialPage e
 * o "Recibo deste pagamento" do recebimento). Sem `paymentId`, o último pagamento confirmado.
 *
 * Leva 8 (22/10/2026):
 *   - quem pagou vem da view pagamentos_com_pagador (sem o embed payments ↔ bank_transactions, que tem 2 FKs);
 *     `receipt.payer` só quando a situação é 'terceiro' — "Recebemos de X por conta de Y". 'indefinido' (cliente sem
 *     documento) não vira payer: nome diferente nunca identifica;
 *   - o CPF/CNPJ do cliente é lido de clients direto: as listas de contas a receber não trazem cpf_cnpj no embed, e o
 *     documento do cliente nunca saía no recibo;
 *   - toda leitura que falha devolve erro e NENHUM PDF: recibo com o pagador ou o valor errado é pior que recibo
 *     nenhum.
 */
export async function montarDadosDoRecibo(r: ReceivableRow, paymentId?: string): Promise<DadosDoRecibo> {
  const clientId = r.client_id ?? r.clients?.id ?? null;

  const leituraDoPagamento = paymentId
    ? supabase
      .from('payments')
      .select('id, amount, payment_date, payment_method, notes, status')
      .eq('id', paymentId)
      .eq('receivable_id', r.id)
      .limit(1)
    : supabase
      .from('payments')
      .select('id, amount, payment_date, payment_method, notes, status')
      .eq('receivable_id', r.id)
      .eq('status', 'confirmed')
      .order('payment_date', { ascending: false })
      .limit(1);

  const [ajustes, pagamentos, cliente] = await Promise.all([
    supabase.from('app_settings').select('key, value'),
    leituraDoPagamento,
    clientId
      ? supabase.from('clients').select('name, cpf_cnpj, phone, email').eq('id', clientId).limit(1)
      : Promise.resolve({ data: [] as unknown[], error: null }),
  ]);

  if (ajustes.error) return { ok: false, erro: `Não consegui ler os dados da empresa para o recibo: ${motivo(ajustes.error)}` };
  if (pagamentos.error) return { ok: false, erro: `Não consegui ler o pagamento para o recibo: ${motivo(pagamentos.error)}` };
  if (cliente.error) return { ok: false, erro: `Não consegui ler o cadastro do cliente para o recibo: ${motivo(cliente.error)}` };

  const pagamento = ((pagamentos.data ?? []) as unknown as PagamentoDoRecibo[])[0] ?? null;
  if (paymentId && (!pagamento || pagamento.status !== 'confirmed')) {
    return { ok: false, erro: 'Este pagamento foi estornado ou não existe mais: não há recibo para ele.' };
  }

  // Conta antiga marcada como paga sem pagamento registrado: o recibo do valor pago (como sempre foi).
  const amount = pagamento ? Number(pagamento.amount) : Number(r.paid_amount || 0);
  if (!(amount > 0)) return { ok: false, erro: 'Não há pagamento confirmado para gerar recibo' };

  let payer: NonNullable<PDFData['receipt']>['payer'];
  if (pagamento) {
    const { data, error } = await supabase
      .from('pagamentos_com_pagador')
      .select('pagador_nome, pagador_documento, situacao')
      .eq('payment_id', pagamento.id)
      .limit(1);
    if (error) return { ok: false, erro: `Não consegui conferir quem pagou: ${motivo(error)}` };
    const quem = ((data ?? []) as unknown as QuemPagou[])[0];
    const nome = quem?.pagador_nome?.trim();
    if (quem?.situacao === 'terceiro' && nome) {
      // Mascarado já aqui: o CPF de terceiro não sai inteiro nem para dentro do gerador — nem o documento, nem o CPF
      // que o banco escreve dentro do NOME ("12345678901-MARIA", o MEI "JOAO SILVA 12345678901").
      payer = { name: nomeSemCpf(nome), cpf_cnpj: documentoMascarado(quem.pagador_documento) ?? undefined };
    }
  }

  const sm: Record<string, string> = {};
  for (const row of (ajustes.data || []) as Array<{ key: string; value: string }>) {
    if (row.key) sm[row.key] = String(row.value || '');
  }
  const get = (k: string) => sm[k] || '';
  const c = ((cliente.data ?? []) as Array<{ name?: string | null; cpf_cnpj?: string | null; phone?: string | null; email?: string | null }>)[0];
  // A referência do recibo (o número REC-…, o título, o "referente ao pagamento de" e o nome do arquivo): o número da
  // OS ou, sem OS, a descrição da conta — que, na receita que nasce da fila do Extrato, é o nome que o banco escreveu,
  // às vezes com o CPF de quem pagou dentro ("12345678901-MARIA"). SEMPRE por nomeSemCpf, em qualquer situação de quem
  // pagou: não dá para saber de quem é o CPF que o banco escreveu (revisão de 23/10/2026, 4ª rodada). A observação do
  // pagamento também (o gerador não a imprime hoje, mas o CPF não entra inteiro nem no gerador).
  const referencia = nomeSemCpf(r.service_orders?.service_order_number || r.description || '');

  const pdf: PDFData = {
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
      service_order_number: referencia || r.id.slice(0, 8),
      status: r.status || 'paid', created_at: r.created_at || new Date().toISOString(),
      grand_total: amount, labor_cost_total: 0, parts_cost_total: 0,
      travel_cost_total: 0, discount_amount: 0, tax_amount: 0,
    },
    client: {
      name: c?.name || r.clients?.name || '—',
      cpf_cnpj: c?.cpf_cnpj?.trim() || r.clients?.cpf_cnpj?.trim() || undefined,
      phone: c?.phone ?? r.clients?.phone ?? undefined,
      email: c?.email ?? r.clients?.email ?? undefined,
    },
    services: [], parts: [],
    receipt: {
      amount,
      payment_date: pagamento?.payment_date || new Date().toISOString(),
      payment_method: pagamento?.payment_method || r.payment_method || 'pix',
      reference: referencia,
      notes: nomeSemCpf(pagamento?.notes || undefined),
      ...(payer ? { payer } : {}),
    },
  };
  return { ok: true, pdf };
}

/**
 * Gera o recibo em PDF de um pagamento (sem `paymentId`, o último confirmado). Devolve se o PDF foi gerado; com
 * qualquer leitura falhando, avisa e não gera.
 */
export async function generateReceivableReceipt(r: ReceivableRow, paymentId?: string): Promise<boolean> {
  try {
    const dados = await montarDadosDoRecibo(r, paymentId);
    // 'erro' in: o projeto compila sem strict, e aí `!dados.ok` não estreita a união
    if ('erro' in dados) {
      toast.error(dados.erro);
      return false;
    }
    printPDF(dados.pdf, { ...DEFAULT_PDF_OPTIONS });
    return true;
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Erro ao gerar recibo');
    return false;
  }
}
