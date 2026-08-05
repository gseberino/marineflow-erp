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
  indexarFornecedores, montarProposta, sugerirRegras,
  type FornecedorConhecido, type HistoricoFornecedor, type RegraFinanceira, type TransacaoOrfa,
} from "../_shared/banking/proposals.ts";
import { findInternalTransfers } from "../_shared/banking/matching.ts";

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
  action?: "generate" | "approve" | "reject" | "suggest_rules" | "reclassify";
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
    if (action === "approve") return await aprovar(admin, body.ids ?? [], userId, body.overrides ?? {});
    if (action === "reject") return await recusar(admin, body.ids ?? [], userId, body.note ?? null);
    if (action === "suggest_rules") return await proporRegras(admin);
    return jr({ error: "acao_desconhecida" }, 400);
  } catch (e) {
    console.error("[finance-review] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

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
      .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, source_type, bank_connection_id")
      .eq("reconciled", false)
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

  const historico = await montarHistoricoPorFornecedor(admin);

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

  // Quem ainda não tem proposta nem lançamento. A entrada de um par entra pela saída, e
  // entrada avulsa fica para a conciliação (ver cabeçalho) — as duas somem daqui.
  const elegiveis = transacoes.filter((tx) => {
    if (naFila.has(tx.id) || lancadas.has(tx.id)) return false;
    if (jaCoberta.has(tx.id)) return false;
    return tx.transaction_type === "debit";
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

    const p = montarProposta(tx, fornecedores, historico, regras);

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

    const linha = {
      kind: p.kind,
      bank_transaction_id: p.bankTransactionId,
      title: p.title,
      confidence: p.confidence,
      suggested_amount: p.suggestedAmount,
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
    return jr({ ok: true, atualizadas: 0, message: "Nenhuma proposta na fila para reavaliar." });
  }

  const { data: fornecedoresRows } = await admin
    .from("suppliers").select("id, name, cnpj_cpf, trade_name").limit(2000);
  const fornecedores = indexarFornecedores((fornecedoresRows ?? []) as FornecedorConhecido[]);
  const historico = await montarHistoricoPorFornecedor(admin);
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
    const nova = montarProposta(tx, fornecedores, historico, regras);

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

  return jr({
    ok: true,
    atualizadas,
    avaliadas: alvo.length,
    por_regra: porRegra,
    message: atualizadas === 0
      ? `Nenhuma das ${alvo.length} propostas da fila mudou de classificação`
      : `${atualizadas} proposta(s) reclassificada(s)`
        + (porRegra > 0 ? `, ${porRegra} pelas suas regras` : ""),
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
 * Lê as despesas já lançadas e monta, por fornecedor, a categoria que ele mais recebeu.
 *
 * É a memória que faz a ferramenta melhorar sozinha: cada aprovação do gestor vira
 * evidência para a próxima proposta do mesmo fornecedor. Só conta o que tem categoria de
 * verdade — "Outras despesas" é ausência de classificação, e aprender a não classificar
 * seria transformar a lacuna em regra.
 */
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

  // Só categorias que EXISTEM no plano de contas podem ser aprendidas.
  //
  // Sem esta checagem o motor propagava lixo: "Compras de Mercadorias" entrou por outro
  // fluxo (importação de nota fiscal), não existe no plano de contas — e portanto não tem
  // grupo no DRE —, e mesmo assim virou o padrão daquele fornecedor e foi aplicada a
  // novos lançamentos. Categoria sem grupo é dinheiro que some do resultado, e aprender
  // a errar transforma um engano em política.
  const { data: catsValidas } = await admin
    .from("financial_categories").select("name").eq("type", "payable").eq("active", true);
  const valida = new Set((catsValidas ?? []).map((c: any) => String(c.name)));

  const contagem = new Map<string, Map<string, number>>();
  for (const row of (data ?? []) as any[]) {
    const cat = String(row.expense_category || "").trim();
    if (!cat || cat === "Outras despesas") continue;
    if (!valida.has(cat)) continue;
    const porCat = contagem.get(row.supplier_id) ?? new Map<string, number>();
    porCat.set(cat, (porCat.get(cat) ?? 0) + 1);
    contagem.set(row.supplier_id, porCat);
  }

  const grupoDaCategoria = new Map<string, string>();
  const { data: cats } = await admin
    .from("financial_categories").select("name, dre_group").eq("active", true);
  for (const c of (cats ?? []) as any[]) {
    if (c.dre_group) grupoDaCategoria.set(String(c.name), String(c.dre_group));
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
    .from("finance_review_queue").select("*").in("id", ids).eq("status", "pending");
  if (error) throw error;

  const feitos: string[] = [];
  const falhas: string[] = [];

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
          .update({ reconciled: true, dismissed_reason: "Transferência entre contas próprias" })
          .in("id", [p.bank_transaction_id, p.related_transaction_id].filter(Boolean));
      } else if (p.kind === "create_payable") {
        const { data: criado, error: e1 } = await admin.from("payables").insert({
          description: descricao,
          issue_date: data,
          due_date: data,
          amount: valor,
          paid_amount: valor,
          balance_amount: 0,
          status: "paid",           // saiu do banco: já está pago por definição
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
        const payableId = (criado as any).id as string;
        await admin.from("finance_review_queue").update({ created_payable_id: payableId }).eq("id", p.id);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);

        // Quitar a ordem de compra fecha o ciclo do suprimento: sem isto, a OC fica
        // "enviada" para sempre e ninguém sabe o que já foi pago.
        const ocId = ov.purchaseOrderId ?? p.suggested_purchase_order_id ?? null;
        if (ocId) {
          await admin.from("purchase_orders")
            .update({ payable_id: payableId, status: "received" })
            .eq("id", ocId);
        }
      } else if (p.kind === "create_receivable") {
        // Receita exige cliente (receivables.client_id é NOT NULL) e, sem ele, o
        // lançamento não teria a quem pertencer. Falhar aqui com motivo legível é melhor
        // que devolver um erro cru de banco para o gestor.
        if (!p.suggested_client_id) {
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
          client_id: p.suggested_client_id,
          bank_transaction_id: p.bank_transaction_id,
        }).select("id").single();
        if (e2) throw e2;
        await admin.from("finance_review_queue").update({ created_receivable_id: (criado as any).id }).eq("id", p.id);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);
      }

      await admin.from("finance_review_queue").update({
        status: "approved", decided_by: userId, decided_at: new Date().toISOString(),
      }).eq("id", p.id);

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
    message: `${feitos.length} lançamento(s) criado(s)` + (falhas.length ? ` · ${falhas.length} falharam` : ""),
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
