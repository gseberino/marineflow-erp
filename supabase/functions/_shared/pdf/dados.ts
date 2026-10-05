/**
 * A montagem do PDFData de uma ordem — a única, para a tela, o portal e o assistente.
 *
 * Mora em _shared para o assistente do WhatsApp (Edge Function) montar o documento
 * exatamente como a tela monta. src/hooks/use-pdf.ts delega para cá.
 */
import type { PDFData } from './documento.ts';
import {
  OS_PUBLICA, CLIENTE_PUBLICO, VEICULO_PUBLICO, MARINA_PUBLICA, LINHA_SERVICO_PUBLICA,
  PECA_PUBLICA, PRODUTO_PUBLICO, DESPESA_PUBLICA,
} from './colunas-publicas.ts';

/**
 * O mínimo que a montagem precisa de um cliente do banco: `.from(tabela)`.
 *
 * Aceita o cliente da tela (sessão do usuário), o do portal (token do link, sob RLS) e o
 * service-role da Edge Function. Tipado largo de propósito: os três são SupabaseClient de
 * gerações de tipo diferentes, e o que importa aqui são as colunas pedidas nas strings
 * de `.select()` — que o teste postgrest-select-columns confere contra o banco.
 */
// deno-lint-ignore no-explicit-any
export type LeitorDoBanco = { from: (tabela: string) => any };

// As linhas que a montagem soma e percorre. Com o cliente tipado da tela elas vinham dos
// tipos gerados; com o leitor genérico, sem isto, virariam `any` em silêncio.
type LinhaRecebivel = {
  id: string;
  description: string | null;
  amount: number | null;
  paid_amount: number | null;
  balance_amount: number | null;
  status: string;
  is_deposit: boolean | null;
};
type LinhaPagamento = {
  receivable_id: string;
  payment_date: string;
  amount: number | null;
  payment_method: string | null;
};

/**
 * Monta o levantamento para o documento do cliente.
 *
 * O embed acima precisa do hint `!service_surveys_service_order_id_fkey`
 * porque há DUAS chaves estrangeiras ligando as duas tabelas, em direções
 * opostas: `service_orders.survey_id` aponta para o levantamento principal, e
 * `service_surveys.service_order_id` aponta para a ordem. Sem dizer qual, o
 * PostgREST recusa a query inteira com PGRST201 — e, como todo o PDF depende
 * dessa query, o sistema inteiro para de gerar documento. A que interessa aqui
 * é a segunda: "todos os levantamentos DESTA ordem", da qual se pega o fechado.
 *
 * Regras que valem a pena estar aqui e não espalhadas no template:
 *  · só entra levantamento FECHADO — em andamento, meia resposta promete mais
 *    do que entrega;
 *  · só entra se houver ao menos uma resposta;
 *  · a foto vira um indicador, não a imagem: o PDF é assinado e circula por
 *    e-mail, e embutir foto de campo estoura o tamanho do anexo.
 */
function buildSurveyForPdf(raw: unknown): PDFData['survey'] {
  const lista = (Array.isArray(raw) ? raw : raw ? [raw] : []) as any[];
  // NOVO-lev-18: com 2+ levantamentos fechados, o `find` pegava um QUALQUER (ordem
  // de embed não é determinada). O documento do cliente leva o mais RECENTE.
  const fechado = lista
    .filter((s) => s?.status === 'closed')
    .sort((a, b) => String(b?.answered_at ?? '').localeCompare(String(a?.answered_at ?? '')))[0];
  if (!fechado) return undefined;

  const answers = [...((fechado.service_survey_answers || []) as any[])]
    .sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0))
    .map((a) => ({
      question: a.question_snapshot as string,
      answer: a.answer_value as string | null,
      skipped: a.skipped_reason as string | null,
      hasPhoto: !!a.photo_path,
    }));

  if (answers.length === 0) return undefined;

  return {
    // `answered_at` é o carimbo de fechamento — não existe `closed_at` nesta
    // tabela. Pedir a coluna errada num embed do PostgREST não devolve o campo
    // nulo: ele recusa a QUERY INTEIRA com 400, e todo o PDF morre junto.
    answered_at: fechado.answered_at ?? null,
    rationale: fechado.confidence_rationale ?? null,
    answers,
  };
}

/**
 * Monta o PDFData de uma ordem — a única fonte.
 *
 * Antes isto existia duas vezes: uma dentro do hook e outra no fetch
 * imperativo, com as mesmas queries copiadas linha a linha. Duas cópias da
 * mesma montagem significam que corrigir uma e esquecer a outra faz o PDF em
 * lote divergir do individual — e a diferença só aparece quando o cliente
 * recebe um documento que não é o que estava na tela.
 */
/**
 * `db` existe para o PORTAL PÚBLICO poder usar esta mesma montagem.
 *
 * Lá quem lê é o cliente do link, com o token no cabeçalho
 * (`createShareClient`), e a RLS compara esse token. Sem este parâmetro o
 * portal precisava de uma montagem PRÓPRIA — e foi o que aconteceu: uma
 * terceira cópia, que divergiu em doze campos e mandava 31 orçamentos ao
 * cliente intitulados "Ordem de Serviço" (NOVO-lev-14).
 *
 * O que a RLS do token não alcança (levantamento, recebíveis, pagamentos,
 * despesas) volta VAZIO, não com erro: as tabelas têm grant de select para
 * `anon`, e política ausente filtra linha, não derruba a consulta.
 */
/**
 * Os links da galeria, em ordem de criação. Falha ao gerar o link não derruba o PDF inteiro:
 * a galeria sai sem as fotos e o motivo vai para o console (o documento continua certo).
 */
async function fotosDaGaleria(
  // deno-lint-ignore no-explicit-any
  linhas: any[] | null | undefined,
  assinar: ((caminhos: string[]) => Promise<string[]>) | undefined,
): Promise<string[]> {
  const caminhos = [...(linhas ?? [])]
    .sort((a, b) => String(a.created_at ?? '').localeCompare(String(b.created_at ?? '')))
    .map((p) => p.storage_path as string)
    .filter(Boolean);
  if (!assinar || caminhos.length === 0) return [];
  try {
    return await assinar(caminhos);
  } catch (e) {
    console.warn('[pdf] fotos da OS sem link temporário:', e);
    return [];
  }
}

/** As parcelas próprias do orçamento (custom_payment_installments), ou null se não houver. */
// deno-lint-ignore no-explicit-any
export function parcelasProprias(so: any): any[] | null {
  const p = so?.custom_payment_installments;
  return Array.isArray(p) && p.length > 0 ? p : null;
}

export async function carregarPDFData(
  serviceOrderId: string,
  db: LeitorDoBanco,
  /**
   * `publico`: quem lê é o link do cliente (anônimo). Pede só as colunas liberadas em
   * colunas-publicas.ts — o banco recusa as internas para o anônimo, e `*` derrubaria a
   * consulta inteira. A tela e o assistente seguem lendo tudo.
   * Sem `services(name)` aqui: o anônimo não lê o catálogo, e o embed derrubava a consulta
   * inteira com 42501 — o "Baixar PDF" do portal falhava assim até 01/10/2026. O nome vem
   * de `name_snapshot`, gravado na própria linha.
   *
   * `assinarFotos`: as fotos da OS ficam em bucket PRIVADO desde 04/10/2026, então a galeria
   * precisa de link temporário — e quem gera é quem chama, com o próprio cliente: a tela com a
   * sessão (src/lib/fotos-da-os.ts), o servidor com a chave de serviço (_shared/pdf/fotos.ts).
   * Sem ele (o link público do cliente), a galeria sai vazia — como já saía: a regra da tabela
   * service_order_photos só deixa o usuário logado ler.
   */
  opcoes: { publico?: boolean; assinarFotos?: (caminhos: string[]) => Promise<string[]> } = {},
): Promise<PDFData> {
  // O que é igual para os dois leitores (o levantamento, as fotos, a condição de pagamento).
  const comuns = `
        service_surveys!service_surveys_service_order_id_fkey(
          answered_at, confidence_rationale, status,
          service_survey_answers(seq, question_snapshot, answer_value, skipped_reason, photo_path)),
        service_order_photos!service_order_photos_service_order_id_fkey(storage_path, created_at),
        payment_condition_presets(label, installments)`;
  const selecao = opcoes.publico
    ? `
        ${OS_PUBLICA},
        clients(${CLIENTE_PUBLICO}),
        vessels(${VEICULO_PUBLICO}),
        marinas(${MARINA_PUBLICA}),
        service_order_services(${LINHA_SERVICO_PUBLICA}),
        service_order_parts(${PECA_PUBLICA}, products(${PRODUTO_PUBLICO})),
        service_order_expenses(${DESPESA_PUBLICA}),${comuns}
      `
    : `
        *,
        clients(*),
        vessels(*),
        marinas(*),
        service_order_services(*, services(name)),
        service_order_parts(*, products(name, sku, image_url)),
        service_order_expenses(category, description, amount, paid_by),${comuns}
      `;
  const [soRes, settingsRes, receivablesRes] = await Promise.all([
    db.from('service_orders')
      .select(selecao)
      .eq('id', serviceOrderId)
      .single(),
    db.from('app_settings')
      .select('key, value'),
    // Todos os recebíveis não cancelados da OS — usado tanto para o
    // card "Sinal Recebido" da fatura quanto para a seção de histórico
    // de pagamentos real (distinta da programação de pagamento).
    db.from('receivables')
      .select('id, description, amount, paid_amount, balance_amount, status, is_deposit')
      .eq('service_order_id', serviceOrderId)
      .not('status', 'eq', 'cancelled')
      .order('due_date', { ascending: true }),
  ]);

  if (soRes.error) throw soRes.error;
  // NOVO-lev-16: cada `|| []`/`|| ''` daqui para baixo transformava FALHA em ausência —
  // app_settings falho saía como empresa "MarineFlow" sem CNPJ nem termos, e receivables
  // falho apagava o sinal já pago do documento do cliente. Erro engolido que produz
  // documento plausível e errado é pior que derrubar: agora derruba, e quem chama
  // (usePDFData/fetchPDFData/portal) mostra indisponibilidade em vez de mentir.
  // Sob o token do portal, política ausente FILTRA linha (não é erro) — nada muda lá.
  if (settingsRes.error) throw settingsRes.error;
  if (receivablesRes.error) throw receivablesRes.error;
  const so = soRes.data;
  const receivables: LinhaRecebivel[] = receivablesRes.data || [];
  const depositPaid = receivables
    .filter((r) => r.is_deposit && r.status === 'paid')
    .reduce((sum, r) => sum + (r.paid_amount || 0), 0);

  const receivableIds = receivables.map((r) => r.id);
  const paymentsRes = receivableIds.length > 0
    ? await db.from('payments')
        .select('receivable_id, payment_date, amount, payment_method')
        .in('receivable_id', receivableIds)
        .eq('status', 'confirmed')
        .order('payment_date', { ascending: true })
    : { data: [] as any[], error: null };
  if (paymentsRes.error) throw paymentsRes.error; // NOVO-lev-16
  const paymentsData: LinhaPagamento[] | null = paymentsRes.data;

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
      discount_services_pct: (so as any).discount_services_pct ?? 0,
      discount_parts_pct: (so as any).discount_parts_pct ?? 0,
      tax_amount: so.tax_amount || 0,
      operational_cost_total: so.operational_cost_total || 0,
      extra_notes: so.extra_notes ?? undefined,
      payment_conditions: (so as any).payment_conditions ?? undefined,
      // A condição pronta (preset) manda; sem ela, as parcelas PRÓPRIAS do orçamento
      // ("Personalizado" na tela, ou definidas pelo assistente). Até 05/10/2026 só o preset era
      // lido: o PDF e o resumo de valores ignoravam as parcelas próprias que a tela já usava
      // para calcular o sinal (nenhum orçamento as usava ainda — o assistente passou a gravar).
      payment_condition_label: (so as any).payment_condition_presets?.label
        ?? (parcelasProprias(so) ? ((so as any).payment_conditions ?? null) : null),
      payment_condition_installments: (so as any).payment_condition_presets
        ? ((so as any).payment_condition_presets.installments ?? null)
        : parcelasProprias(so),
      subcontract_cost_total: (so as any).subcontract_cost_total || 0,
      financial_notes: (so as any).financial_notes ?? undefined,
      payment_method_preferred: (so as any).payment_method_preferred ?? undefined,
      quote_validity_days: (so as any).quote_validity_days ?? undefined,
      // A data fixa de validade: sem ela aqui, o PDF dizia "Válido por N dias" de um orçamento
      // que a R19 dava por vencido no dia seguinte à data (validadeDoOrcamento).
      quote_validity_date: (so as any).quote_validity_date ?? null,
      deposit_paid: depositPaid > 0 ? depositPaid : undefined,
      receivables: receivables.map((r) => ({
        id: r.id,
        description: r.description || 'Recebível',
        amount: r.amount || 0,
        balance_amount: r.balance_amount || 0,
        status: r.status,
        is_deposit: !!r.is_deposit,
      })),
      payments: (paymentsData || []).map((p) => ({
        receivable_id: p.receivable_id,
        payment_date: p.payment_date,
        amount: p.amount || 0,
        payment_method: p.payment_method || '',
      })),
    },
    client: {
      name: (so.clients as any)?.name || '—',
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
      name: (so.vessels as any).name,
      manufacturer: (so.vessels as any).manufacturer ?? undefined,
      model: (so.vessels as any).model ?? undefined,
      year: (so.vessels as any).year ?? undefined,
      registration: (so.vessels as any).hull_id_or_registration ?? undefined,
    } : undefined,
    marina: so.marinas ? {
      name: (so.marinas as any).name || '—',
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
    // Só o levantamento FECHADO vai para o documento do cliente: enquanto
    // está em andamento, a resposta pela metade diria menos do que promete.
    survey: buildSurveyForPdf((so as any).service_surveys),
    terms: [
      get('terms_general'),
      get('terms_warranty'),
      get('terms_cancellation'),
      get('terms_delivery'),
      get('terms_responsibilities'),
    ].filter(Boolean).join('\n\n') || undefined,
    // NOVO-lev-17: a galeria lia `service_orders.photos`, coluna que NADA escreve —
    // as fotos reais vivem em `service_order_photos`. Desde 04/10/2026 o bucket é privado: a
    // linha guarda o caminho e o link temporário vem de `opcoes.assinarFotos`.
    photos: await fotosDaGaleria((so as any).service_order_photos, opcoes.assinarFotos),
  };
  return pdfData;
}
