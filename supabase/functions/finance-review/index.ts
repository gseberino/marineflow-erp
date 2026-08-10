// Edge Function: finance-review
//
// Gera as propostas de lançamento a partir do extrato e aplica as que o gestor aprova.
// É o módulo que ataca o problema central do financeiro: quase todo o dinheiro que passou
// pela conta nunca virou despesa ou receita registrada, porque lançar isso à mão é inviável.
//
// GOVERNANÇA (decisões do usuário em 29/07/2026):
//   · Limite de R$ 500 — abaixo, aprovação em lote; acima, item a item.
//   · Últimos 90 dias na fila; o histórico anterior fica para um mutirão à parte.
//   · Aprovar cria REGISTRO de despesa/receita. Nada aqui movimenta dinheiro.
//
// O limite vive aqui e na tabela, não no texto de um prompt: instrução em linguagem
// natural não é controle de acesso.
//
// POR QUE SÓ SAÍDAS, POR ENQUANTO
// Saída de dinheiro quase nunca está registrada (R$ 926 mil em saídas para 5 contas a
// pagar): a despesa só existe no extrato, e propô-la não corre risco de duplicar nada.
// Entrada é o oposto — quase sempre corresponde a um orçamento ou OS que JÁ existe no
// sistema, e é o módulo de conciliação que sabe ligar as duas pontas. Criar uma receita
// avulsa para cada entrada contaria o mesmo faturamento duas vezes assim que a OS fosse
// faturada, e ninguém perceberia. Entrada, portanto, entra na fila apenas quando é a
// perna de uma transferência entre contas próprias (que não é receita de ninguém).

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  chaveDoRecebedor, indexarFornecedores, montarProposta, sugerirRegras,
  type FornecedorConhecido, type HistoricoFornecedor, type RegraFinanceira, type TransacaoOrfa,
} from "../_shared/banking/proposals.ts";
import { findInternalTransfers } from "../_shared/banking/matching.ts";
import { callClaude } from "../_shared/ai/anthropic.ts";
import { MODEL_LITE } from "../_shared/ai/models.ts";
import {
  agruparParcelamentos, descreverParcelamento, lerParcela,
  type CompraParcelada, type PernaDeParcelamento,
} from "../_shared/banking/installments.ts";

type DbClient = SupabaseClient<any, "public", any>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Acima disto, a proposta exige olhar individual — decisão do usuário. */
const LIMITE_LOTE = 500;
/** Janela da fila: o que é mais antigo vira mutirão separado, para não sepultar o dia. */
const JANELA_DIAS = 90;

/**
 * Quantas transações o mutirão do histórico resolve por chamada.
 *
 * Edge function tem orçamento de CPU por invocação, e o mutirão real tem 1.330 saídas
 * atrasadas: processá-las de uma vez matava o worker com o erro 546, que chega na tela como
 * "Edge Function returned a non-2xx status code" — sem corpo, sem motivo, sem nada feito.
 * Cada chamada resolve um pedaço e devolve quantas faltam; a tela repete até zerar. Assim o
 * trabalho anda mesmo se uma chamada falhar, em vez de recomeçar do nada.
 */
const LOTE_HISTORICO = 200;

interface Body {
  action?: "generate" | "approve" | "reject" | "suggest_rules" | "reclassify" | "classify_ai" | "undismiss";
  /** generate: inclui o histórico inteiro, não só a janela. */
  incluir_historico?: boolean;
  ids?: string[];
  note?: string;
  /** Quem está decidindo, quando a chamada é interna (só respeitado com x-cron-secret). */
  acting_user_id?: string;
  /** Correções do gestor antes de aprovar. */
  overrides?: Record<string, Correcao>;
}

interface Correcao {
  category?: string;
  description?: string;
  amount?: number;
  date?: string;
  /** A quem a despesa pertence quando não é a um fornecedor. */
  payeeId?: string | null;
  /** OS a que a compra pertence — é o que dá custo e margem reais por serviço. */
  serviceOrderId?: string | null;
  /** OC que este pagamento quita. */
  purchaseOrderId?: string | null;
  /**
   * De quem veio a entrada. `receivables.client_id` é NOT NULL e o motor não tem como
   * adivinhar o cliente a partir do extrato com segurança — quem recebeu por Pix aparece
   * com o nome da pessoa física, não o do cliente cadastrado. Sem este campo, toda proposta
   * de receita nasceria impossível de aprovar.
   */
  clientId?: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin: DbClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const cronSecret = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && cronSecret === Deno.env.get("CRON_SECRET");
  let userId: string | null = null;

  const body: Body = await req.json().catch(() => ({}));

  if (!isCron) {
    const token = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!token) return jr({ error: "unauthorized" }, 401);
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data?.user) return jr({ error: "unauthorized" }, 401);
    userId = data.user.id;
  } else if (body.acting_user_id) {
    // Chamada interna autenticada pelo segredo (agente pelo WhatsApp, onde não há JWT de
    // usuário). A identidade vem no corpo para que a decisão continue tendo dono: sem
    // isso, toda aprovação feita por voz ficaria registrada como "ninguém".
    userId = String(body.acting_user_id);
  }
  const action = body.action ?? "generate";

  try {
    if (action === "generate") return await gerar(admin, !!body.incluir_historico);
    if (action === "reclassify") return await reclassificar(admin);
    if (action === "classify_ai") return await classificarComIA(admin);
    if (action === "undismiss") return await desfazerIgnorada(admin, body.ids ?? [], userId);
    if (action === "approve") return await aprovar(admin, body.ids ?? [], userId, body.overrides ?? {});
    if (action === "reject") return await recusar(admin, body.ids ?? [], userId, body.note ?? null);
    if (action === "suggest_rules") return await proporRegras(admin);
    return jr({ error: "acao_desconhecida" }, 400);
  } catch (e) {
    console.error("[finance-review] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

/**
 * Registra na trilha o que foi feito.
 *
 * Tabela de auditoria sem escrita é decoração. E a escrita nunca pode derrubar a operação
 * que ela registra: falhar em anotar é ruim, desfazer um lançamento correto porque a
 * anotação falhou é pior.
 */
async function anotar(
  admin: DbClient,
  registro: {
    acao: string;
    autor?: string | null;
    bank_transaction_id?: string | null;
    payable_id?: string | null;
    receivable_id?: string | null;
    finance_rule_id?: string | null;
    valor?: number | null;
    detalhe?: string | null;
    antes?: unknown;
    depois?: unknown;
  },
): Promise<void> {
  try {
    await admin.from("reconciliation_log").insert({
      acao: registro.acao,
      autor: registro.autor ?? null,
      bank_transaction_id: registro.bank_transaction_id ?? null,
      payable_id: registro.payable_id ?? null,
      receivable_id: registro.receivable_id ?? null,
      finance_rule_id: registro.finance_rule_id ?? null,
      valor: registro.valor ?? null,
      detalhe: registro.detalhe ?? null,
      antes: registro.antes ?? null,
      depois: registro.depois ?? null,
    });
  } catch (e) {
    console.error("[finance-review] falha ao anotar na trilha:", e);
  }
}

/** Tamanho de página nas leituras longas — é o teto que a API impõe por requisição. */
const PAGINA = 1000;

/**
 * Lê uma tabela inteira, em páginas.
 *
 * A API devolve no máximo mil linhas por requisição, e cala sobre o resto: uma consulta
 * truncada tem exatamente a cara de uma consulta completa. Enquanto a fila tinha 21 linhas
 * e os lançamentos 361, isso nunca apareceu — mas o mutirão do histórico leva os dois para
 * a casa dos milhares, e aí a leitura truncada faria o motor concluir que uma transação
 * ainda não foi proposta quando ela JÁ virou despesa aprovada. O resultado seria uma
 * segunda despesa para o mesmo dinheiro, criada em silêncio por cima do trabalho do gestor.
 *
 * A ordenação por uma coluna única não é enfeite: paginar sem ordem estável é o que faz
 * uma linha aparecer em duas páginas e outra em nenhuma.
 */
async function lerTudo<T = Record<string, unknown>>(
  pagina: (de: number, ate: number) => PromiseLike<{ data: unknown[] | null; error: unknown }>,
  teto = 10 * PAGINA,
): Promise<T[]> {
  const todas: T[] = [];
  for (let de = 0; de < teto; de += PAGINA) {
    const { data, error } = await pagina(de, Math.min(de + PAGINA, teto) - 1);
    if (error) throw error;
    const linhas = (data ?? []) as T[];
    todas.push(...linhas);
    if (linhas.length < PAGINA) break;
  }
  return todas;
}

/** Conjunto de `bank_transaction_id` de uma tabela, sem truncar. */
async function idsDeTransacao(
  admin: DbClient,
  tabela: "finance_review_queue" | "payables" | "receivables",
  ajustar: (q: any) => any,
): Promise<Set<string>> {
  const linhas = await lerTudo<{ bank_transaction_id: string | null }>((de, ate) =>
    ajustar(admin.from(tabela).select("id, bank_transaction_id").order("id")).range(de, ate)
  );
  const ids = new Set<string>();
  for (const r of linhas) if (r.bank_transaction_id) ids.add(String(r.bank_transaction_id));
  return ids;
}

async function gerar(admin: DbClient, incluirHistorico: boolean) {
  const desde = new Date(Date.now() - JANELA_DIAS * 86_400_000).toISOString().slice(0, 10);

  const transacoes = await lerTudo<TransacaoOrfa>((de, ate) => {
    let q = admin
      .from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, source_type, bank_connection_id, installment_label, payee_mcc, tx_status")
      .eq("reconciled", false)
      // Transação PENDENTE não vira lançamento: o banco ainda pode mudar o valor ou
      // cancelá-la. Criar despesa em cima disso é construir sobre areia — e desfazer
      // depois custa mais que esperar o fechamento.
      .or("tx_status.is.null,tx_status.neq.PENDING")
      .order("transaction_date", { ascending: false })
      .order("id");
    if (!incluirHistorico) q = q.gte("transaction_date", desde);
    return q.range(de, ate);
  }, 3000);
  if (transacoes.length === 0) {
    return jr({ ok: true, message: "Nenhuma transação pendente na janela.", criadas: 0 });
  }

  // Transferência entre contas próprias não é despesa nem receita: entra na fila como o
  // que é, para o gestor confirmar e as duas pernas saírem do resultado de uma vez.
  // Uma proposta por PAR, não por perna — duas linhas para o mesmo dinheiro fariam o
  // gestor decidir a mesma coisa duas vezes.
  const pares = findInternalTransfers(transacoes as never[]);
  const parPor = new Map<string, { detail: string; outra: string }>();
  const jaCoberta = new Set<string>();
  for (const p of pares) {
    parPor.set(p.saida.id, { detail: p.detail, outra: p.entrada.id });
    jaCoberta.add(p.entrada.id);
  }

  // Não propor de novo o que já está na fila ou já virou lançamento.
  const naFila = await idsDeTransacao(admin, "finance_review_queue",
    (q) => q.eq("status", "pending"));

  const lancadas = new Set([
    ...await idsDeTransacao(admin, "payables",
      (q) => q.not("bank_transaction_id", "is", null)),
    ...await idsDeTransacao(admin, "receivables",
      (q) => q.not("bank_transaction_id", "is", null)),
  ]);

  const { data: fornecedoresRows } = await admin
    .from("suppliers").select("id, name, cnpj_cpf, trade_name").limit(2000);
  // Índice montado uma vez: comparar cada transação com 530 fornecedores limpando o nome
  // dos dois lados a cada comparação era metade do custo que estourava o limite de CPU.
  const fornecedores = indexarFornecedores((fornecedoresRows ?? []) as FornecedorConhecido[]);

  const memoria = await montarMemoria(admin);

  const { data: regrasRows } = await admin
    .from("finance_rules").select("*").eq("status", "active").limit(500);
  const regras = (regrasRows ?? []) as unknown as RegraFinanceira[];

  // Ordens de compra ainda sem pagamento: é com elas que uma saída pode casar.
  const { data: ocsAbertas } = await admin
    .from("purchase_orders")
    .select("id, po_number, total_amount, supplier_id, service_order_id, expected_date")
    .is("payable_id", null)
    .not("status", "in", '("cancelled")')
    .limit(500);
  const ocs = (ocsAbertas ?? []) as any[];

  // Favorecidos conhecidos, para reconhecer sócio/diarista pelo CPF do extrato.
  const { data: favorecidosRows } = await admin
    .from("payees").select("id, name, document, default_category").eq("active", true).limit(500);
  const favorecidos = (favorecidosRows ?? []) as any[];

  // Compra parcelada é UMA compra: a proposta nasce na parcela mais antiga, com o valor
  // total, e as outras pernas não viram despesa separada.
  const { compras, pernaDe } = agruparParcelamentos(transacoes as unknown as PernaDeParcelamento[]);
  const compraPorChave = new Map(compras.map((c) => [c.chave, c]));
  const ancoras = new Set(compras.map((c) => c.ancora.id));

  // Quem ainda não tem proposta nem lançamento. A entrada de um par entra pela saída e
  // parcela que não é a âncora entra pela compra — as duas somem daqui.
  //
  // ENTRADA AVULSA AGORA ENTRA. Até aqui havia um `return tx.transaction_type === "debit"`
  // que mandava toda entrada "para a conciliação". A consequência medida em 09/08/2026: 87
  // créditos somando R$ 628 mil nunca receberam proposta, sumiam da caixa de entrada e
  // reapareciam na tela de conciliação — que é literalmente o "por que disso?" do gestor.
  // São os mesmos R$ 628 mil que faltam no DRE.
  //
  // A máquina já sabia fazer isso dos dois lados: `montarProposta` devolve
  // create_receivable para entrada desde sempre, e o approve já trata esse kind. Só este
  // filtro os mantinha fora. Transferência interna continua protegida: a perna de entrada
  // sai por `jaCoberta`, então entrada de par não vira receita.
  const elegiveis = transacoes.filter((tx) => {
    if (naFila.has(tx.id) || lancadas.has(tx.id)) return false;
    if (jaCoberta.has(tx.id)) return false;
    if (pernaDe.has(tx.id) && !ancoras.has(tx.id)) return false;
    return tx.transaction_type === "debit" || tx.transaction_type === "credit";
  });

  // O corte é sobre os ELEGÍVEIS, não sobre o que veio do banco: as propostas criadas neste
  // lote entram em `naFila` e são excluídas na chamada seguinte, então repetir a chamada
  // avança sempre. Cortar a consulta em vez da fila devolveria sempre as mesmas 200 e o
  // mutirão nunca sairia do lugar.
  const desteLote = incluirHistorico ? elegiveis.slice(0, LOTE_HISTORICO) : elegiveis;
  const restantes = elegiveis.length - desteLote.length;

  const linhas: Record<string, unknown>[] = [];
  const autoAplicar: Record<string, unknown>[] = [];
  for (const tx of desteLote) {
    const par = parPor.get(tx.id);
    if (par) {
      linhas.push({
        kind: "internal_transfer",
        bank_transaction_id: tx.id,
        related_transaction_id: par.outra,
        title: `Transferência entre contas: ${tx.description}`.slice(0, 160),
        reasoning: par.detail,
        confidence: 92,
        suggested_amount: tx.amount,
        suggested_date: tx.transaction_date,
        suggested_category: "Transferência entre contas",
        suggested_description: tx.description.slice(0, 200),
        dre_group: "nao_operacional",
      });
      continue;
    }

    const p = montarProposta(tx, fornecedores, memoria.porFornecedor, regras, memoria.porNome);

    // Favorecido pelo documento: CPF é identidade, e reconhecê-lo poupa o gestor de
    // escolher a mesma pessoa toda vez que ela recebe.
    const docTx = (tx.counterparty_document || "").replace(/\D/g, "");
    const favorecido = docTx.length >= 11
      ? favorecidos.find((f) => String(f.document || "").replace(/\D/g, "") === docTx)
      : undefined;

    // OC do MESMO fornecedor com valor idêntico — o par é forte o bastante para sugerir,
    // fraco o bastante para exigir confirmação: duas OCs de igual valor existem.
    const oc = p.suggestedSupplierId
      ? ocs.find((o) => o.supplier_id === p.suggestedSupplierId
          && Math.abs(Number(o.total_amount) - tx.amount) < 0.01)
      : undefined;

    // A despesa é a COMPRA, não a parcela. Sem isto, dez parcelas de R$ 102,40 viravam dez
    // despesas — dez classificações para o mesmo fato e um custo por fornecedor que não
    // fecha com nota nenhuma.
    const compra = compraPorChave.get(pernaDe.get(tx.id) ?? "");

    const linha = {
      kind: p.kind,
      bank_transaction_id: p.bankTransactionId,
      title: compra ? `${p.title} (${compra.totalDeParcelas}x)`.slice(0, 160) : p.title,
      confidence: p.confidence,
      suggested_amount: compra ? compra.valorDaCompra : p.suggestedAmount,
      suggested_date: p.suggestedDate,
      suggested_category: p.suggestedCategory,
      suggested_description: p.suggestedDescription,
      suggested_supplier_id: p.suggestedSupplierId,
      suggested_payee_id: favorecido?.id ?? null,
      // A OC costuma saber para qual serviço a compra foi — herdar isso evita perguntar
      // duas vezes a mesma coisa.
      suggested_purchase_order_id: oc?.id ?? null,
      suggested_service_order_id: oc?.service_order_id ?? null,
      dre_group: p.dreGroup,
      applied_rule_id: p.appliedRuleId,
      reasoning: [
        compra && descreverParcelamento(compra),
        p.reasoning,
        favorecido && `Favorecido reconhecido pelo CPF/CNPJ: ${favorecido.name}`,
        oc && `Mesmo valor da ordem de compra ${oc.po_number}, do mesmo fornecedor`,
      ].filter(Boolean).join(" · "),
    };
    linhas.push(linha);
    // Regra com autonomia foi conferida pelo gestor no momento em que ele a criou; segurar
    // a proposta para ele confirmar de novo seria pedir a mesma decisão duas vezes.
    if (p.autoAplicavel) autoAplicar.push(linha);
  }

  let criadas = 0;
  const idsPorTransacao = new Map<string, string>();
  for (let i = 0; i < linhas.length; i += 200) {
    const lote = linhas.slice(i, i + 200);
    const { data: inseridas, error: insErr } = await admin
      .from("finance_review_queue").insert(lote).select("id, bank_transaction_id");
    if (insErr) throw insErr;
    for (const r of (inseridas ?? []) as any[]) idsPorTransacao.set(r.bank_transaction_id, r.id);
    criadas += lote.length;
  }

  // Aplica de imediato o que as regras autônomas resolveram. Cada lançamento fica ligado à
  // regra que o criou, então desligar a regra e desfazer o que ela fez são a mesma consulta.
  let lancadasSozinhas = 0;
  const idsAuto = autoAplicar
    .map((l) => idsPorTransacao.get(String(l.bank_transaction_id)))
    .filter((v): v is string => !!v);
  if (idsAuto.length > 0) {
    const resposta = await aprovar(admin, idsAuto, null, {});
    const corpo = await resposta.json();
    lancadasSozinhas = Number(corpo?.aprovadas ?? 0);
  }

  const partes = [
    criadas > 0 ? `${criadas - lancadasSozinhas} proposta(s) para revisar` : "Nada novo para propor",
    lancadasSozinhas > 0 ? `${lancadasSozinhas} lançada(s) pelas suas regras` : "",
    pares.length ? `${pares.length} transferência(s) entre contas` : "",
    restantes > 0 ? `faltam ${restantes} do histórico` : "",
  ].filter(Boolean);

  return jr({
    ok: true,
    criadas,
    lancadas_por_regra: lancadasSozinhas,
    transferencias_internas: pares.length,
    elegiveis_lote: linhas.filter((l) => Number(l.suggested_amount) < LIMITE_LOTE).length,
    // Quantas transações antigas sobraram para a próxima chamada. Zero = mutirão terminado.
    restantes,
    message: partes.join(" · "),
  });
}

/**
 * Reavalia as propostas que já estão na fila com as regras de HOJE.
 *
 * A regra era consultada só no nascimento da proposta, e a varredura pula o que já está na
 * fila — então ensinar "compra na Corema é ferramenta" não alcançava as 40 compras da
 * Corema já enfileiradas. O gestor criava a regra e continuava corrigindo à mão exatamente
 * as linhas que a regra existia para resolver: o aprendizado valia só para o futuro, e o
 * passado ficava de castigo.
 *
 * NÃO APROVA NADA. Reclassificar troca a sugestão; aprovar cria lançamento. Mesmo uma
 * regra com autonomia para lançar sozinha só faz isso com transação nova, onde o gestor
 * ainda não olhou — varrer a fila inteira lançando em silêncio seria decidir por ele
 * centenas de vezes de uma vez, com um clique que ele deu para outra coisa.
 */
async function reclassificar(admin: DbClient) {
  // Antes de reclassificar, juntar o que é a mesma compra: classificar dez vezes a mesma
  // coisa é trabalho que não deveria existir, e vale a pena eliminá-lo antes de gastar
  // uma decisão com ele.
  const parcelamentos = await consolidarParcelamentosNaFila(admin);

  const pendentes = await lerTudo<any>((de, ate) =>
    admin
      .from("finance_review_queue")
      .select(`id, kind, bank_transaction_id, suggested_category, suggested_amount,
               suggested_supplier_id, dre_group, applied_rule_id, confidence, reasoning,
               bank_transactions!finance_review_queue_bank_transaction_id_fkey (
                 id, transaction_date, description, amount, transaction_type,
                 counterparty_name, counterparty_document, source_type )`)
      .eq("status", "pending")
      .order("id")
      .range(de, ate)
  );

  // Transferência entre contas não se classifica por regra de despesa: ela já é o que é.
  const alvo = pendentes.filter((p) => p.kind !== "internal_transfer" && p.bank_transactions);
  if (alvo.length === 0) {
    return jr({
      ok: true, atualizadas: 0, ...parcelamentos,
      message: "Nenhuma proposta na fila para reavaliar.",
    });
  }

  const { data: fornecedoresRows } = await admin
    .from("suppliers").select("id, name, cnpj_cpf, trade_name").limit(2000);
  const fornecedores = indexarFornecedores((fornecedoresRows ?? []) as FornecedorConhecido[]);
  const memoria = await montarMemoria(admin);
  const { data: regrasRows } = await admin
    .from("finance_rules").select("*").eq("status", "active").limit(500);
  const regras = (regrasRows ?? []) as unknown as RegraFinanceira[];

  /**
   * Uma atualização por CLASSIFICAÇÃO, não por linha.
   *
   * Uma regra costuma dizer a mesma coisa sobre dezenas de transações; mandar dezenas de
   * updates idênticos seria pagar uma ida ao banco por linha e estourar o tempo da função
   * numa fila de mil. Linhas que terminam com o mesmo resultado viajam juntas.
   */
  const porResultado = new Map<string, { payload: Record<string, unknown>; ids: string[] }>();
  let porRegra = 0;

  for (const p of alvo) {
    const tx = p.bank_transactions as TransacaoOrfa;
    const nova = montarProposta(tx, fornecedores, memoria.porFornecedor, regras, memoria.porNome);

    const mudou = nova.suggestedCategory !== p.suggested_category
      || nova.dreGroup !== p.dre_group
      || (nova.suggestedSupplierId ?? null) !== (p.suggested_supplier_id ?? null)
      || (nova.appliedRuleId ?? null) !== (p.applied_rule_id ?? null);
    if (!mudou) continue;
    if (nova.appliedRuleId) porRegra += 1;

    const payload = {
      suggested_category: nova.suggestedCategory,
      dre_group: nova.dreGroup,
      suggested_supplier_id: nova.suggestedSupplierId,
      applied_rule_id: nova.appliedRuleId,
      confidence: nova.confidence,
      reasoning: nova.reasoning,
    };
    const chave = JSON.stringify(payload);
    const entrada = porResultado.get(chave) ?? { payload, ids: [] as string[] };
    entrada.ids.push(p.id);
    porResultado.set(chave, entrada);
  }

  let atualizadas = 0;
  for (const { payload, ids } of porResultado.values()) {
    for (let i = 0; i < ids.length; i += 200) {
      const lote = ids.slice(i, i + 200);
      const { error } = await admin
        .from("finance_review_queue").update(payload).in("id", lote).eq("status", "pending");
      if (error) throw error;
      atualizadas += lote.length;
    }
  }

  const partes = [
    atualizadas > 0
      ? `${atualizadas} proposta(s) reclassificada(s)` + (porRegra > 0 ? `, ${porRegra} pelas suas regras` : "")
      : "",
    parcelamentos.compras > 0
      ? `${parcelamentos.compras} compra(s) parcelada(s) juntada(s), ${parcelamentos.retiradas} linha(s) a menos`
      : "",
  ].filter(Boolean);

  return jr({
    ok: true,
    atualizadas,
    avaliadas: alvo.length,
    por_regra: porRegra,
    compras_parceladas: parcelamentos.compras,
    linhas_retiradas: parcelamentos.retiradas,
    message: partes.length > 0
      ? partes.join(" · ")
      : `Nenhuma das ${alvo.length} propostas da fila mudou`,
  });
}

/**
 * Devolve à fila uma transação que tinha sido ignorada, desfazendo o que a ignorada causou.
 *
 * Ignorar nunca foi só esconder uma linha: aprovar uma compra em 10x tira as outras nove
 * pernas de vista E cria um lançamento no valor da compra inteira. Desfazer a perna sozinha
 * devolveria a linha e deixaria o lançamento de pé — o mesmo dinheiro contado duas vezes.
 * Por isso o alcance é calculado, não assumido: a partir de UMA linha, chega-se à compra
 * toda, ao lançamento que ela criou e às propostas que foram decididas junto.
 *
 * Só apaga lançamento que o próprio motor criou (`origin = 'bank_reconciliation'`). O que
 * foi lançado à mão fica onde está e é relatado — desfazer uma automação não é licença
 * para apagar o trabalho de alguém.
 */
async function desfazerIgnorada(admin: DbClient, ids: string[], userId: string | null) {
  if (ids.length === 0) return jr({ error: "nenhuma transação informada" }, 400);

  const { data: alvos, error } = await admin
    .from("bank_transactions")
    .select("id, dismissed_kind, counterparty_name, description, amount, transaction_date, installment_label")
    .in("id", ids)
    .not("dismissed_reason", "is", null);
  if (error) throw error;
  if (!alvos || alvos.length === 0) {
    return jr({ ok: true, transacoes: 0, message: "Nada para desfazer: estas transações não estão ignoradas." });
  }

  const afetadas = new Set<string>();
  for (const tx of alvos as any[]) {
    afetadas.add(tx.id);
    // Perna de compra parcelada: o alcance é a compra inteira, não a linha clicada.
    if (tx.dismissed_kind === "parcela" || tx.installment_label) {
      const compra = await lerCompraParcelada(admin, tx as PernaDeParcelamento);
      for (const perna of compra?.pernas ?? []) afetadas.add(perna.id);
    }
  }

  // Transferência entre contas tem duas pernas, e a proposta guarda a segunda.
  const { data: propostas } = await admin
    .from("finance_review_queue")
    .select("id, bank_transaction_id, related_transaction_id, created_payable_id, created_receivable_id, status")
    .or(`bank_transaction_id.in.(${[...afetadas].join(",")}),related_transaction_id.in.(${[...afetadas].join(",")})`);
  for (const p of (propostas ?? []) as any[]) {
    if (p.bank_transaction_id) afetadas.add(p.bank_transaction_id);
    if (p.related_transaction_id) afetadas.add(p.related_transaction_id);
  }

  const lista = [...afetadas];

  // Lançamentos criados pelo motor a partir destas transações.
  const { data: pagaveis } = await admin
    .from("payables").select("id, description, origin").in("bank_transaction_id", lista);
  const { data: recebiveis } = await admin
    .from("receivables").select("id, description").in("bank_transaction_id", lista);

  const apagaveis = (pagaveis ?? []).filter((p: any) => p.origin === "bank_reconciliation");
  const preservados = (pagaveis ?? []).filter((p: any) => p.origin !== "bank_reconciliation");

  if (apagaveis.length > 0) {
    const { error: e1 } = await admin.from("payables").delete().in("id", apagaveis.map((p: any) => p.id));
    if (e1) throw e1;
  }
  if ((recebiveis ?? []).length > 0) {
    const { error: e2 } = await admin.from("receivables").delete().in("id", (recebiveis ?? []).map((r: any) => r.id));
    if (e2) throw e2;
  }

  // As propostas voltam a PENDENTES: a decisão foi desfeita, então ela precisa ser tomada
  // de novo — deixá-las aprovadas apontando para um lançamento apagado seria mentir na
  // trilha de auditoria.
  const idsPropostas = (propostas ?? []).map((p: any) => p.id);
  if (idsPropostas.length > 0) {
    const { error: e3 } = await admin.from("finance_review_queue").update({
      status: "pending",
      decided_by: null, decided_at: null,
      created_payable_id: null, created_receivable_id: null,
      decision_note: `Reaberta em ${new Date().toISOString().slice(0, 10)}: a transação voltou para a fila`,
    }).in("id", idsPropostas);
    if (e3) throw e3;
  }

  const { error: e4 } = await admin.from("bank_transactions").update({
    reconciled: false,
    dismissed_reason: null,
    dismissed_kind: null,
    dismissed_at: null,
    dismissed_by: null,
    reconciled_payment_id: null,
  }).in("id", lista);
  if (e4) throw e4;

  for (const id of lista) {
    await anotar(admin, {
      acao: "devolveu",
      autor: userId,
      bank_transaction_id: id,
      detalhe: `Devolvida à fila · ${apagaveis.length + (recebiveis ?? []).length} lançamento(s) desfeito(s)`,
      antes: { estado: "ignorada" },
      depois: { estado: "pendente" },
    });
  }

  return jr({
    ok: true,
    transacoes: lista.length,
    lancamentos_apagados: apagaveis.length + (recebiveis ?? []).length,
    propostas_reabertas: idsPropostas.length,
    lancamentos_preservados: preservados.map((p: any) => p.description),
    message: `${lista.length} transação(ões) de volta à fila`
      + (apagaveis.length + (recebiveis ?? []).length > 0
        ? ` · ${apagaveis.length + (recebiveis ?? []).length} lançamento(s) desfeito(s)` : "")
      + (preservados.length > 0
        ? ` · ${preservados.length} lançamento(s) manual(is) preservado(s), confira-os` : ""),
  });
}

/**
 * Classifica com IA o que nem regra nem memória alcançaram.
 *
 * A memória do sistema só sabe o que já foi decidido: das 151 propostas sem categoria, ela
 * resolvia 8, porque as outras 143 são estabelecimentos que aparecem pela PRIMEIRA vez.
 * Nenhuma regra vai adivinhá-los — "MP *GTEKENERGIASU" não contém palavra nenhuma do plano
 * de contas —, mas um humano lendo o nome sabe o que é. É exatamente o trabalho para o qual
 * um modelo de linguagem serve, e o único ponto deste módulo onde ele ganha da aritmética.
 *
 * TRÊS COISAS QUE MANTÊM ISSO HONESTO
 *
 * 1. O plano de contas vai no pedido e a resposta é CONFERIDA contra ele. Categoria
 *    inventada é descartada, não criada — inventar conta é como o resultado começa a mentir.
 * 2. Os exemplos são as decisões DO GESTOR, não exemplos genéricos. É o que ensina que
 *    "peça de barco" aqui é custo direto e não material de escritório.
 * 3. Nunca aprova. A sugestão entra com confiança modesta e dizendo que veio da IA, para
 *    que quem revisa saiba o peso do que está lendo.
 */
async function classificarComIA(admin: DbClient) {
  const { valida, grupoDaCategoria } = await lerPlanoDeContas(admin);
  if (valida.size === 0) return jr({ ok: true, sugeridas: 0, message: "Plano de contas vazio." });

  const pendentes = await lerTudo<any>((de, ate) =>
    admin
      .from("finance_review_queue")
      .select(`id, suggested_category, applied_rule_id,
               bank_transactions!finance_review_queue_bank_transaction_id_fkey (
                 counterparty_name, description )`)
      .eq("status", "pending")
      .neq("kind", "internal_transfer")
      .is("applied_rule_id", null)
      .order("id")
      .range(de, ate)
  );

  // Só o que segue sem categoria de verdade: o que a regra ou a memória já resolveram não
  // volta para a IA opinar por cima.
  const porNome = new Map<string, { ids: string[]; exemplo: string }>();
  for (const p of pendentes) {
    const cat = String(p.suggested_category ?? "").trim();
    if (cat && cat !== "Outras despesas") continue;
    const tx = p.bank_transactions;
    if (!tx) continue;
    const nome = String(tx.counterparty_name || tx.description || "").trim();
    if (!nome) continue;
    const chave = chaveDoRecebedor({ description: String(tx.description ?? ""), counterparty_name: tx.counterparty_name ?? null } as TransacaoOrfa);
    const atual = porNome.get(chave) ?? { ids: [], exemplo: nome };
    atual.ids.push(p.id);
    porNome.set(chave, atual);
  }
  if (porNome.size === 0) {
    return jr({ ok: true, sugeridas: 0, message: "Nada sem categoria para a IA analisar." });
  }

  // Exemplos vindos do próprio histórico do gestor: é o que ensina a convenção da casa.
  const memoria = await montarHistoricoPorNome(admin, valida, grupoDaCategoria);
  const exemplos = [...memoria.entries()].slice(0, 60)
    .map(([nome, h]) => `${nome} → ${h.categoria}`).join("\n");

  const nomes = [...porNome.entries()].slice(0, 200);
  const lista = nomes.map(([, v], i) => `${i + 1}. ${v.exemplo}`).join("\n");

  const resposta = await callClaude({
    model: MODEL_LITE,
    maxTokens: 8000,
    system: [{
      type: "text",
      text: [
        "Você classifica despesas de uma empresa de serviços náuticos e elétricos (barcos e motorhomes)",
        "a partir do NOME DO ESTABELECIMENTO como ele aparece na fatura do cartão.",
        "",
        "Categorias permitidas (use EXATAMENTE estes nomes, nada fora da lista):",
        [...valida].map((c) => `- ${c}`).join("\n"),
        "",
        exemplos ? `Como esta empresa já classificou antes:\n${exemplos}` : "",
        "",
        "Regras: quando o nome não permitir concluir com segurança, devolva confianca baixa",
        "em vez de chutar. Prefixos de adquirente (EC *, PAG*, MP *, SPG*) não são o nome:",
        "ignore-os e olhe o que vem depois.",
      ].filter(Boolean).join("\n"),
    }],
    messages: [{
      role: "user",
      content: [{ type: "text", text: `Classifique cada estabelecimento:\n\n${lista}` }],
    }],
    tools: [{
      name: "classificar",
      description: "Devolve a categoria de cada estabelecimento da lista.",
      input_schema: {
        type: "object",
        properties: {
          itens: {
            type: "array",
            items: {
              type: "object",
              properties: {
                numero: { type: "number", description: "O número da linha na lista." },
                categoria: { type: "string" },
                confianca: { type: "number", description: "0 a 100." },
              },
              required: ["numero", "categoria", "confianca"],
            },
          },
        },
        required: ["itens"],
      },
    }],
  });

  const chamada = resposta.content.find((b) => b.type === "tool_use") as
    { input?: { itens?: Array<{ numero: number; categoria: string; confianca: number }> } } | undefined;
  const itens = chamada?.input?.itens ?? [];

  let sugeridas = 0;
  let recusadas = 0;
  for (const item of itens) {
    const alvo = nomes[Number(item.numero) - 1];
    if (!alvo) continue;
    const categoria = String(item.categoria ?? "").trim();
    // Categoria fora do plano é descartada. Criar conta a partir de um palpite é como o
    // resultado começa a mentir sem ninguém perceber.
    if (!valida.has(categoria)) { recusadas += 1; continue; }
    const confianca = Math.max(20, Math.min(80, Math.round(Number(item.confianca) || 50)));

    const { error } = await admin.from("finance_review_queue").update({
      suggested_category: categoria,
      dre_group: grupoDaCategoria.get(categoria) ?? "despesa_operacional",
      confidence: confianca,
      reasoning: `Sugerido pela IA a partir do nome "${alvo[1].exemplo}" — confira antes de aprovar`,
    }).in("id", alvo[1].ids).eq("status", "pending");
    if (error) throw error;
    sugeridas += alvo[1].ids.length;
  }

  return jr({
    ok: true,
    sugeridas,
    estabelecimentos: nomes.length,
    fora_do_plano: recusadas,
    message: sugeridas > 0
      ? `${sugeridas} proposta(s) classificada(s) pela IA em ${nomes.length} estabelecimento(s) — confira antes de aprovar`
      : "A IA não conseguiu classificar nada com segurança",
  });
}

/**
 * Procura repetições nas decisões já tomadas e as grava como regras PROPOSTAS.
 *
 * Nasce inerte: `status: 'proposed'` não classifica nada até alguém aceitar. O sistema
 * observou um padrão, não recebeu uma ordem — e um padrão pode ser três erros iguais.
 */
async function proporRegras(admin: DbClient) {
  const lancamentos = await lerTudo<{
    supplier_id: string | null; supplier_name: string | null; expense_category: string;
  }>((de, ate) =>
    admin
      .from("payables")
      .select("id, supplier_id, supplier_name, expense_category")
      .not("expense_category", "is", null)
      // `id` como desempate: ordem instável faz uma linha cair em duas páginas e outra em
      // nenhuma, e aí a contagem de repetições que vira regra sai errada.
      .order("created_at", { ascending: false })
      .order("id")
      .range(de, ate)
  , 3000);

  const { data: cats } = await admin
    .from("financial_categories").select("name, dre_group").eq("active", true);
  const grupoDa = new Map<string, string>();
  for (const c of (cats ?? []) as any[]) if (c.dre_group) grupoDa.set(String(c.name), String(c.dre_group));

  const { data: fornecedores } = await admin.from("suppliers").select("id, name").limit(2000);
  const nomeDo = new Map<string, string>();
  for (const f of (fornecedores ?? []) as any[]) nomeDo.set(f.id, f.name);

  const decisoes = ((lancamentos ?? []) as any[]).map((p) => ({
    supplierId: p.supplier_id ?? null,
    supplierName: p.supplier_id ? nomeDo.get(p.supplier_id) : p.supplier_name,
    counterpartyName: p.supplier_name ?? null,
    categoria: String(p.expense_category),
    dreGroup: grupoDa.get(String(p.expense_category)) ?? "despesa_operacional",
  }));

  const { data: existentes } = await admin.from("finance_rules").select("*").limit(1000);
  const padroes = sugerirRegras(decisoes, (existentes ?? []) as unknown as RegraFinanceira[]);

  if (padroes.length === 0) {
    return jr({ ok: true, propostas: 0, message: "Nenhum padrão novo o bastante para virar regra" });
  }

  const { error } = await admin.from("finance_rules").insert(
    padroes.map((p) => ({
      match_type: p.matchType,
      match_value: p.matchValue,
      direction: p.direction,
      set_category: p.setCategory,
      set_dre_group: p.setDreGroup,
      set_supplier_id: p.setSupplierId,
      autonomy: "suggest",
      origin: "ai",
      status: "proposed",
      reasoning: p.reasoning,
    })),
  );
  if (error) throw error;

  return jr({
    ok: true,
    propostas: padroes.length,
    message: `${padroes.length} regra(s) sugerida(s) a partir do que você já decidiu`,
  });
}

/**
 * Recompõe a compra parcelada a partir de UMA das suas parcelas.
 *
 * Recalcula em vez de guardar a lista de pernas na proposta: entre propor e aprovar pode
 * ter chegado mais uma parcela do extrato, e uma lista congelada deixaria essa parcela
 * órfã na fila, virando uma segunda despesa da mesma compra.
 */
async function lerCompraParcelada(
  admin: DbClient,
  ancora: PernaDeParcelamento | null,
): Promise<CompraParcelada | null> {
  // A âncora vem junto da proposta, não numa consulta à parte: aprovar um grupo de 23 são
  // 23 idas ao banco só para descobrir que 22 delas não são parceladas.
  if (!ancora || !lerParcela(ancora.installment_label)) return null;

  // Mesmo favorecido e mesmo valor de parcela: o resto do filtro é do agrupador, que sabe
  // recusar colisão indistinguível.
  let q = admin
    .from("bank_transactions")
    .select("id, transaction_date, description, amount, counterparty_name, installment_label")
    .eq("amount", ancora.amount)
    .not("installment_label", "is", null)
    .limit(60);
  q = ancora.counterparty_name
    ? q.eq("counterparty_name", ancora.counterparty_name)
    : q.eq("description", ancora.description);

  const { data: irmas } = await q;
  const { compras, pernaDe } = agruparParcelamentos((irmas ?? []) as PernaDeParcelamento[]);
  const chave = pernaDe.get(ancora.id);
  return (chave && compras.find((c) => c.chave === chave)) || null;
}

/**
 * Junta o que já está na fila como parcelas soltas numa proposta só, da compra.
 *
 * A varredura pula o que já está enfileirado, então as compras parceladas propostas antes
 * desta regra existir continuariam como dez linhas para sempre. Aqui a proposta da parcela
 * mais antiga vira a proposta da compra e as outras saem de cena — sem tocar em nada que
 * já virou lançamento.
 */
async function consolidarParcelamentosNaFila(admin: DbClient): Promise<{ compras: number; retiradas: number }> {
  const pendentes = await lerTudo<any>((de, ate) =>
    admin
      .from("finance_review_queue")
      .select(`id, bank_transaction_id, suggested_amount, title, reasoning,
               bank_transactions!finance_review_queue_bank_transaction_id_fkey (
                 id, transaction_date, description, amount, counterparty_name, installment_label )`)
      .eq("status", "pending")
      .not("bank_transaction_id", "is", null)
      .order("id")
      .range(de, ate)
  );

  const propostaDaTransacao = new Map<string, any>();
  const pernas: PernaDeParcelamento[] = [];
  for (const p of pendentes) {
    const tx = p.bank_transactions as PernaDeParcelamento | null;
    if (!tx?.installment_label) continue;
    propostaDaTransacao.set(tx.id, p);
    pernas.push(tx);
  }
  if (pernas.length === 0) return { compras: 0, retiradas: 0 };

  const { compras } = agruparParcelamentos(pernas);
  let consolidadas = 0;
  let retiradas = 0;

  for (const c of compras) {
    // A proposta fica na parcela mais antiga que TENHA proposta — a âncora pode já ter
    // sido lançada ou recusada antes, e nesse caso a compra segue pela mais antiga viva.
    const dona = c.pernas.map((p) => propostaDaTransacao.get(p.id)).find(Boolean);
    if (!dona) continue;

    const outras = c.pernas
      .map((p) => propostaDaTransacao.get(p.id))
      .filter((p) => p && p.id !== dona.id)
      .map((p) => p.id as string);

    const { error } = await admin.from("finance_review_queue").update({
      suggested_amount: c.valorDaCompra,
      title: /\(\d+x\)$/.test(String(dona.title)) ? dona.title : `${dona.title} (${c.totalDeParcelas}x)`.slice(0, 160),
      reasoning: [descreverParcelamento(c), dona.reasoning].filter(Boolean).join(" · ").slice(0, 1000),
    }).eq("id", dona.id).eq("status", "pending");
    if (error) throw error;
    consolidadas += 1;

    if (outras.length > 0) {
      const { error: e2 } = await admin.from("finance_review_queue").update({
        status: "superseded",
        decision_note: "Parcela da mesma compra — decidida na proposta da compra",
      }).in("id", outras).eq("status", "pending");
      if (e2) throw e2;
      retiradas += outras.length;
    }
  }

  return { compras: consolidadas, retiradas };
}

/**
 * Lê as despesas já lançadas e monta, por fornecedor, a categoria que ele mais recebeu.
 *
 * É a memória que faz a ferramenta melhorar sozinha: cada aprovação do gestor vira
 * evidência para a próxima proposta do mesmo fornecedor. Só conta o que tem categoria de
 * verdade — "Outras despesas" é ausência de classificação, e aprender a não classificar
 * seria transformar a lacuna em regra.
 */
/**
 * O que já se decidiu para cada NOME do extrato.
 *
 * O histórico por fornecedor só alcança quem está cadastrado, e a fatura de cartão é quase
 * toda de estabelecimentos que nunca serão fornecedor. Eram eles que ficavam em "Outras
 * despesas" para sempre: o gestor classificava a mesma padaria pela décima vez e o sistema
 * não aprendia, porque não tinha onde guardar. Aqui a memória passa a ter a chave que a
 * fatura usa — o nome do estabelecimento.
 *
 * Exige DUAS decisões iguais, não uma. Uma classificação isolada pode ter sido um engano, e
 * repetir um engano com confiança é pior que não sugerir nada.
 */
async function montarHistoricoPorNome(
  admin: DbClient,
  categoriasValidas: Set<string>,
  grupoDaCategoria: Map<string, string>,
): Promise<Map<string, HistoricoFornecedor>> {
  const linhas = await lerTudo<any>((de, ate) =>
    admin
      .from("payables")
      .select(`id, expense_category,
               bank_transactions ( counterparty_name, description )`)
      .not("expense_category", "is", null)
      .not("bank_transaction_id", "is", null)
      .order("id")
      .range(de, ate)
  );

  const contagem = new Map<string, Map<string, number>>();
  for (const row of linhas) {
    const cat = String(row.expense_category || "").trim();
    if (!cat || cat === "Outras despesas" || !categoriasValidas.has(cat)) continue;
    const tx = row.bank_transactions;
    if (!tx) continue;
    const chave = chaveDoRecebedor({
      description: String(tx.description ?? ""),
      counterparty_name: tx.counterparty_name ?? null,
    } as TransacaoOrfa);
    if (!chave) continue;
    const porCat = contagem.get(chave) ?? new Map<string, number>();
    porCat.set(cat, (porCat.get(cat) ?? 0) + 1);
    contagem.set(chave, porCat);
  }

  const historico = new Map<string, HistoricoFornecedor>();
  for (const [chave, porCat] of contagem) {
    let melhor = ""; let vezes = 0; let segundo = 0;
    for (const [cat, n] of porCat) {
      if (n > vezes) { segundo = vezes; melhor = cat; vezes = n; }
      else if (n > segundo) segundo = n;
    }
    // Duas decisões iguais no mínimo, e a preferida tem de ser a preferida de verdade:
    // empate significa que o próprio histórico está dividido, e aí ele não ensina nada.
    if (melhor && vezes >= 2 && vezes > segundo) {
      historico.set(chave, {
        categoria: melhor,
        dreGroup: grupoDaCategoria.get(melhor) ?? "despesa_operacional",
        vezes,
      });
    }
  }
  return historico;
}

async function montarHistoricoPorFornecedor(admin: DbClient): Promise<Map<string, HistoricoFornecedor>> {
  // Em páginas: depois do mutirão são milhares de lançamentos, e uma leitura truncada
  // ensinaria o motor com metade da história — sem nada indicando que faltou metade.
  const data = await lerTudo<{ supplier_id: string; expense_category: string }>((de, ate) =>
    admin
      .from("payables")
      .select("id, supplier_id, expense_category")
      .not("supplier_id", "is", null)
      .not("expense_category", "is", null)
      .order("id")
      .range(de, ate)
  );

  const { valida, grupoDaCategoria } = await lerPlanoDeContas(admin);

  const contagem = new Map<string, Map<string, number>>();
  for (const row of (data ?? []) as any[]) {
    const cat = String(row.expense_category || "").trim();
    if (!cat || cat === "Outras despesas") continue;
    if (!valida.has(cat)) continue;
    const porCat = contagem.get(row.supplier_id) ?? new Map<string, number>();
    porCat.set(cat, (porCat.get(cat) ?? 0) + 1);
    contagem.set(row.supplier_id, porCat);
  }

  const historico = new Map<string, HistoricoFornecedor>();
  for (const [supplierId, porCat] of contagem) {
    let melhor = ""; let vezes = 0;
    for (const [cat, n] of porCat) if (n > vezes) { melhor = cat; vezes = n; }
    if (melhor) {
      historico.set(supplierId, {
        categoria: melhor,
        dreGroup: grupoDaCategoria.get(melhor) ?? "despesa_operacional",
        vezes,
      });
    }
  }
  return historico;
}

/**
 * Plano de contas, lido uma vez.
 *
 * Só categorias que EXISTEM aqui podem ser aprendidas. Sem esta checagem o motor propagava
 * lixo: "Compras de Mercadorias" entrou por outro fluxo (importação de nota fiscal), não
 * tinha grupo no DRE, e mesmo assim virou o padrão de um fornecedor e foi aplicada a novos
 * lançamentos. Categoria sem grupo é dinheiro que some do resultado, e aprender a errar
 * transforma um engano em política.
 */
async function lerPlanoDeContas(admin: DbClient): Promise<{
  valida: Set<string>; grupoDaCategoria: Map<string, string>;
}> {
  const { data: cats } = await admin
    .from("financial_categories").select("name, dre_group, type, active").eq("active", true);
  const valida = new Set<string>();
  const grupoDaCategoria = new Map<string, string>();
  for (const c of (cats ?? []) as any[]) {
    if (c.type === "payable") valida.add(String(c.name));
    if (c.dre_group) grupoDaCategoria.set(String(c.name), String(c.dre_group));
  }
  return { valida, grupoDaCategoria };
}

/** As duas memórias do motor: por fornecedor cadastrado e por nome do extrato. */
async function montarMemoria(admin: DbClient) {
  const { valida, grupoDaCategoria } = await lerPlanoDeContas(admin);
  const [porFornecedor, porNome] = await Promise.all([
    montarHistoricoPorFornecedor(admin),
    montarHistoricoPorNome(admin, valida, grupoDaCategoria),
  ]);
  return { porFornecedor, porNome };
}

/**
 * Aprova propostas, criando os lançamentos.
 *
 * Transferência entre contas NÃO gera lançamento: ela apenas marca as duas pernas como
 * resolvidas. Criar despesa e receita para o mesmo dinheiro é exatamente o erro que a
 * detecção existe para evitar.
 */
async function aprovar(
  admin: DbClient,
  ids: string[],
  userId: string | null,
  overrides: Record<string, Correcao>,
) {
  if (ids.length === 0) return jr({ error: "nenhuma proposta informada" }, 400);

  const { data: propostas, error } = await admin
    .from("finance_review_queue")
    // A transação vem junto para não custar uma consulta por linha só para saber se é
    // compra parcelada — na grande maioria das vezes não é.
    .select(`*, bank_transactions!finance_review_queue_bank_transaction_id_fkey (
      id, transaction_date, description, amount, counterparty_name, installment_label )`)
    .in("id", ids).eq("status", "pending");
  if (error) throw error;

  const feitos: string[] = [];
  const falhas: string[] = [];
  /** Lançamento criado por proposta, para gravar o vínculo junto com o "aprovado". */
  const criadoPara = new Map<string, string>();
  const recebidoPara = new Map<string, string>();
  /** Pernas de compra parcelada que saíram de vista junto com a aprovação. */
  let pernasRetiradas = 0;

  for (const p of (propostas ?? []) as any[]) {
    try {
      const ov = overrides[p.id] ?? {};
      const valor = Number(ov.amount ?? p.suggested_amount);
      const data = String(ov.date ?? p.suggested_date);
      const descricao = String(ov.description ?? p.suggested_description ?? p.title);
      const categoria = String(ov.category ?? p.suggested_category ?? "Outras despesas");

      if (p.kind === "internal_transfer") {
        // Só marca as duas pernas: nenhum lançamento é criado.
        await admin.from("bank_transactions")
          .update({
            reconciled: true,
            dismissed_reason: "Transferência entre contas próprias",
            dismissed_kind: "transferencia",
            dismissed_at: new Date().toISOString(),
            dismissed_by: userId,
          })
          .in("id", [p.bank_transaction_id, p.related_transaction_id].filter(Boolean));
      } else if (p.kind === "create_payable") {
        /**
         * Compra no cartão é DESPESA, nunca conta a pagar.
         *
         * A versão anterior deixava as parcelas futuras como saldo em aberto, "para não
         * esconder dívida". O efeito foi o oposto: 41 compras parceladas viraram contas a
         * pagar de R$ 33 mil — e o gestor não deve isso ao LOJISTA. A compra está paga do
         * ponto de vista dele; quem ele deve é o BANCO, e essa dívida é a fatura, uma só.
         * Manter as duas contava a mesma dívida duas vezes.
         *
         * A competência continua certa: a despesa inteira é reconhecida na data da compra,
         * e o pagamento da fatura é não operacional — sai do resultado, então nada é
         * contado em dobro no DRE. O financiamento com o banco pertence à fatura (Fase B3),
         * não a cada compra.
         */
        const parcelamento = await lerCompraParcelada(
          admin, (p.bank_transactions ?? null) as PernaDeParcelamento | null,
        );
        const pago = valor;
        const aberto = 0;

        const { data: criado, error: e1 } = await admin.from("payables").insert({
          description: parcelamento
            ? `${descricao} (compra em ${parcelamento.totalDeParcelas}x)`.slice(0, 200)
            : descricao,
          issue_date: data,
          due_date: data,
          amount: valor,
          paid_amount: pago,
          balance_amount: aberto,
          status: aberto > 0.005 ? "partially_paid" : "paid",
          expense_category: categoria,
          supplier_id: p.suggested_supplier_id,
          // Sem fornecedor cadastrado, o nome do extrato é a única identificação que
          // existe — melhor guardá-lo do que deixar a despesa anônima.
          supplier_name: p.suggested_supplier_id ? null : descricao,
          // Favorecido pessoa e OS a que a compra pertence: é o que transforma "saiu
          // dinheiro" em "este serviço custou isto" e "este sócio retirou aquilo".
          payee_id: ov.payeeId ?? p.suggested_payee_id ?? null,
          linked_service_order_id: ov.serviceOrderId ?? p.suggested_service_order_id ?? null,
          origin: "bank_reconciliation",
          bank_transaction_id: p.bank_transaction_id,
        }).select("id").single();
        if (e1) throw e1;
        // O vínculo com o lançamento vai junto do "aprovado", numa escrita só. Eram duas
        // idas ao banco por linha para gravar dois campos da mesma linha.
        criadoPara.set(p.id, (criado as any).id as string);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);

        // As outras parcelas saem da fila junto: são a mesma compra, e deixá-las pendentes
        // faria a próxima varredura propô-las de novo, uma despesa por parcela — o defeito
        // que este agrupamento existe para acabar.
        if (parcelamento) {
          const outras = parcelamento.pernas
            .map((perna) => perna.id)
            .filter((id) => id !== p.bank_transaction_id);
          if (outras.length > 0) {
            await admin.from("bank_transactions").update({
              reconciled: true,
              dismissed_reason: `Parcela da compra lançada em ${data} (${parcelamento.totalDeParcelas}x)`,
              dismissed_kind: "parcela",
              dismissed_at: new Date().toISOString(),
              dismissed_by: userId,
            }).in("id", outras);
            // O gestor precisa SABER que outras linhas saíram junto. Elas somem da tela no
            // mesmo clique, e sumiço silencioso é o que fez 380 transações virarem
            // desconfiança.
            pernasRetiradas += outras.length;
            await admin.from("finance_review_queue").update({
              status: "superseded",
              decision_note: "Faz parte de uma compra parcelada já lançada",
            }).in("bank_transaction_id", outras).eq("status", "pending");
          }
        }

        // Quitar a ordem de compra fecha o ciclo do suprimento: sem isto, a OC fica
        // "enviada" para sempre e ninguém sabe o que já foi pago.
        const ocId = ov.purchaseOrderId ?? p.suggested_purchase_order_id ?? null;
        if (ocId) {
          await admin.from("purchase_orders")
            .update({ payable_id: criadoPara.get(p.id), status: "received" })
            .eq("id", ocId);
        }
      } else if (p.kind === "create_receivable") {
        // Receita exige cliente (receivables.client_id é NOT NULL) e, sem ele, o
        // lançamento não teria a quem pertencer. Falhar aqui com motivo legível é melhor
        // que devolver um erro cru de banco para o gestor.
        const clienteId = ov.clientId ?? p.suggested_client_id ?? null;
        if (!clienteId) {
          throw new Error("Escolha o cliente antes de aprovar esta receita");
        }
        const { data: criado, error: e2 } = await admin.from("receivables").insert({
          description: descricao,
          issue_date: data,
          due_date: data,
          amount: valor,
          paid_amount: valor,
          balance_amount: 0,
          status: "paid",           // entrou no banco: já está recebido
          category: categoria,
          client_id: clienteId,
          bank_transaction_id: p.bank_transaction_id,
        }).select("id").single();
        if (e2) throw e2;
        recebidoPara.set(p.id, (criado as any).id as string);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);
      }

      await admin.from("finance_review_queue").update({
        status: "approved",
        decided_by: userId,
        decided_at: new Date().toISOString(),
        created_payable_id: criadoPara.get(p.id) ?? null,
        created_receivable_id: recebidoPara.get(p.id) ?? null,
      }).eq("id", p.id);

      await anotar(admin, {
        acao: p.kind === "internal_transfer" ? "ignorou" : "aprovou_proposta",
        autor: userId,
        bank_transaction_id: p.bank_transaction_id,
        payable_id: criadoPara.get(p.id) ?? null,
        receivable_id: recebidoPara.get(p.id) ?? null,
        finance_rule_id: p.applied_rule_id ?? null,
        valor,
        detalhe: `${categoria} · ${descricao}`.slice(0, 300),
        antes: { status: "pending", categoria_sugerida: p.suggested_category },
        depois: { status: "approved", categoria },
      });

      // Quanto cada regra trabalhou é o que separa regra útil de regra esquecida — e é o
      // número que permite auditar uma regra pelo resultado, não pela intenção.
      if (p.applied_rule_id) {
        await admin.rpc("increment_finance_rule_usage", { rule_id: p.applied_rule_id })
          .then(undefined, () => { /* contador é telemetria: nunca derruba a aprovação */ });
      }
      feitos.push(p.id);
    } catch (e) {
      console.error("[finance-review] falha ao aprovar", p.id, e);
      falhas.push(`${p.title}: ${String((e as Error)?.message ?? e).slice(0, 120)}`);
    }
  }

  return jr({
    ok: falhas.length === 0,
    aprovadas: feitos.length,
    falhas,
    pernas_de_parcelamento: pernasRetiradas,
    message: `${feitos.length} lançamento(s) criado(s)`
      + (pernasRetiradas > 0
        ? ` · ${pernasRetiradas} parcela(s) da mesma compra saíram da fila junto` : "")
      + (falhas.length ? ` · ${falhas.length} falharam` : ""),
  });
}

async function recusar(admin: DbClient, ids: string[], userId: string | null, note: string | null) {
  if (ids.length === 0) return jr({ error: "nenhuma proposta informada" }, 400);
  const { error } = await admin.from("finance_review_queue").update({
    status: "rejected", decided_by: userId, decided_at: new Date().toISOString(), decision_note: note,
  }).in("id", ids).eq("status", "pending");
  if (error) throw error;
  return jr({ ok: true, recusadas: ids.length, message: `${ids.length} proposta(s) recusada(s)` });
}
