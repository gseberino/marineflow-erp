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
  agruparParcelamentos, compraJaTratada, descreverParcelamento, lerParcela, nomeSemParcela,
  type CompraParcelada, type PernaDeParcelamento,
} from "../_shared/banking/installments.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { carregarContextoSeguro, identificarLinha, type TxDaFila } from "./identificacao.ts";
import { exigeDecisao, vinculoAutomatico, type OpcaoDeVinculo, type VinculoSugerido } from "../_shared/banking/vinculo.ts";
import { lerRespostaDaReceita } from "../_shared/banking/cnae.ts";
import { selecionarParaLancarSozinho, type LinhaCandidata } from "./lancar-sozinho.ts";

type DbClient = SupabaseClient<any, "public", any>;

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Acima disto, a proposta exige olhar individual — decisão do usuário (29/07/2026). O valor
 * vive em app_settings.finance_review_batch_limit (trava nº 2 do plano: limite no banco, não
 * no código); a constante é só o padrão quando a chave não existe. A tela lê a mesma chave.
 */
const LIMITE_LOTE_PADRAO = 500;
async function lerLimiteLote(admin: any): Promise<number> {
  try {
    const { data } = await admin.from("app_settings").select("value").eq("key", "finance_review_batch_limit").maybeSingle();
    const n = parseFloat(String(data?.value ?? "").replace(",", "."));
    return Number.isFinite(n) && n > 0 ? n : LIMITE_LOTE_PADRAO;
  } catch {
    return LIMITE_LOTE_PADRAO;
  }
}
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
  action?: "generate" | "approve" | "reject" | "suggest_rules" | "reclassify" | "classify_ai" | "undismiss" | "vigiar" | "consult_document";
  /** consult_document: CNPJ (ou CPF) a consultar. */
  documento?: string;
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
  /**
   * O que esta linha paga, escolhido pela pessoa: o id de uma das opções de
   * `vinculo_sugerido` (principal ou alternativa), ou "nenhum" para lançar novo mesmo
   * havendo sugestão. Ausente = a política decide (vinculoAutomatico / exigeDecisao).
   */
  vinculo?: { id: string } | "nenhum";
}

servirComCors(async (req) => {
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
    if (action === "vigiar") return await vigiar(admin);
    if (action === "reclassify") return await reclassificar(admin);
    if (action === "classify_ai") return await classificarComIA(admin);
    if (action === "undismiss") return await desfazerIgnorada(admin, body.ids ?? [], userId);
    if (action === "approve") return await aprovar(admin, body.ids ?? [], userId, body.overrides ?? {});
    if (action === "reject") return await recusar(admin, body.ids ?? [], userId, body.note ?? null);
    if (action === "suggest_rules") return await proporRegras(admin);
    if (action === "consult_document") return await consultarDocumento(admin, String(body.documento ?? ""), userId);
    return jr({ error: "acao_desconhecida" }, 400);
  } catch (e) {
    console.error("[finance-review] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

/**
 * Vigilante de despesas (Executivo Financeiro, módulo IV — decisão do dono de 14/09/2026).
 *
 * Só AVISA: grava propostas de kind 'anomaly' na caixa de entrada, sem lançamento nenhum.
 * Quatro olhares sobre as saídas do extrato dos últimos 12 meses, agrupadas por quem recebeu
 * (documento quando há; senão o nome normalizado):
 *   1. valor fora do padrão — ≥ 2× a mediana de ≥3 pagamentos anteriores (e ≥ R$ 200 acima);
 *   2. quem recebeu pela primeira vez — sem histórico em 12 meses e ≥ R$ 500 nos últimos 30 dias;
 *   3. recorrência que parou — presente em ≥3 dos 4 meses anteriores e nada nos últimos 35 dias;
 *   4. duplicidade — mesmo valor para o mesmo recebedor em até 3 dias.
 * Cada alerta tem uma chave (suggested_description = 'vigia:…') que impede repeti-lo por 45 dias.
 * "Ciente" (aprovar) e "Descartar" (recusar) só tiram o alerta da lista.
 */
async function vigiar(admin: DbClient) {
  const hoje = new Date();
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const d30 = iso(new Date(hoje.getTime() - 30 * 86400000));
  const d35 = iso(new Date(hoje.getTime() - 35 * 86400000));
  const d45 = new Date(hoje.getTime() - 45 * 86400000).toISOString();
  const d365 = iso(new Date(hoje.getTime() - 365 * 86400000));

  // Um ano de débitos passa de 1.000 linhas, e o PostgREST corta aí por padrão: com
  // .limit() o vigilante enxergava só os meses mais antigos e achava "nada fora do
  // padrão" olhando para o passado. Paginar é o que faz ele ver o mês corrente.
  // Data futura é parcela de cartão ainda não cobrada: não é gasto, e entraria como
  // "recente" em toda regra. Fica de fora até o dia chegar.
  const hojeIso = iso(hoje);
  const txs = await lerTudo<Record<string, unknown>>((de, ate) =>
    admin
      .from("bank_transactions")
      .select("id, transaction_date, amount, description, counterparty_name, counterparty_document, merchant_name, merchant_document, dismissed_kind")
      .eq("transaction_type", "debit")
      .gte("transaction_date", d365)
      .lte("transaction_date", hojeIso)
      .order("transaction_date", { ascending: true })
      .order("id")
      .range(de, ate), 8000);

  const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
  const generico = (n: string) =>
    /^(transf enviada( pix)?( c)?|transferencia enviada|debito de cartao|pagamento de pix|pix enviado|compra no (debito|credito))$/.test(n);
  type Tx = { id: string; transaction_date: string; amount: number; rotulo: string };
  const grupos = new Map<string, Tx[]>();
  // O mesmo favorecido aparece ora com CNPJ, ora só pelo nome (extrato do cartão não
  // traz documento). Sem isto viram dois grupos e o mesmo aviso sai em dobro.
  const docPorNome = new Map<string, string>();
  for (const t of (txs ?? []) as any[]) {
    const doc = String(t.counterparty_document ?? t.merchant_document ?? "").replace(/\D/g, "");
    const nome = norm(String(t.merchant_name || t.counterparty_name || "").trim()).slice(0, 40);
    if (doc.length >= 11 && nome && !docPorNome.has(nome)) docPorNome.set(nome, `doc:${doc}`);
  }
  for (const t of (txs ?? []) as any[]) {
    // Transferência entre contas e parcela já explicada não são despesa nova.
    if (t.dismissed_kind === "transferencia" || t.dismissed_kind === "parcela") continue;
    const doc = String(t.counterparty_document ?? t.merchant_document ?? "").replace(/\D/g, "");
    const nome = String(t.merchant_name || t.counterparty_name || t.description || "").trim();
    const chave = doc.length >= 11 ? `doc:${doc}` : (docPorNome.get(norm(nome).slice(0, 40)) ?? `nome:${norm(nome).slice(0, 40)}`);
    if (chave === "nome:") continue;
    // Sem favorecido e com descrição genérica ("TRANSF ENVIADA PIX", "DEBITO DE CARTAO")
    // o grupo mistura dezenas de destinos: mediana, "novo" e "parou" não dizem nada.
    if (doc.length < 11 && generico(norm(nome))) continue;
    const tx: Tx = {
      id: t.id, transaction_date: String(t.transaction_date).slice(0, 10),
      amount: Math.abs(Number(t.amount || 0)), rotulo: nome.slice(0, 60) || chave,
    };
    const lista = grupos.get(chave);
    if (lista) lista.push(tx); else grupos.set(chave, [tx]);
  }

  type Alerta = { tipo: string; chave: string; titulo: string; motivo: string; valor: number; data: string; txId: string | null };
  const alertas: Alerta[] = [];
  const fmt = (n: number) => n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
  const mediana = (v: number[]) => {
    const s = [...v].sort((a, b) => a - b); const m = Math.floor(s.length / 2);
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  };
  const mesDe = (d: string) => d.slice(0, 7);
  const mesesAnteriores = [1, 2, 3, 4].map((n) => {
    const d = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() - n, 1));
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
  });

  for (const [chave, lista] of grupos) {
    const rotulo = lista[lista.length - 1].rotulo;
    const recentes = lista.filter((t) => t.transaction_date >= d30);
    const historico = lista.filter((t) => t.transaction_date < d30);

    if (historico.length >= 3) {
      const med = mediana(historico.map((t) => t.amount));
      for (const t of recentes) {
        if (med > 0 && t.amount >= 2 * med && t.amount - med >= 200) {
          alertas.push({
            tipo: "valor", chave: `vigia:valor:${t.id}`, txId: t.id, valor: t.amount, data: t.transaction_date,
            titulo: `Valor acima do padrão: ${rotulo} — ${fmt(t.amount)} (costuma ser ~${fmt(med)})`,
            motivo: `${historico.length} pagamentos anteriores a ${rotulo} nos últimos 12 meses, mediana ${fmt(med)}. Este é ${(t.amount / med).toFixed(1)}× o normal. Confira o valor antes de lançar.`,
          });
        }
      }
    }

    if (historico.length === 0 && recentes.length > 0) {
      const maior = recentes.reduce((m, t) => (t.amount > m.amount ? t : m), recentes[0]);
      const soma = recentes.reduce((s, t) => s + t.amount, 0);
      if (maior.amount >= 500) {
        alertas.push({
          tipo: "novo", chave: `vigia:novo:${chave}:${mesDe(maior.transaction_date)}`, txId: maior.id, valor: maior.amount, data: maior.transaction_date,
          titulo: `Primeira vez no extrato: ${rotulo} — ${fmt(maior.amount)}`,
          motivo: `Nenhum pagamento a ${rotulo} nos 12 meses anteriores; ${recentes.length} nos últimos 30 dias, somando ${fmt(soma)}. Vale confirmar que é um recebedor legítimo.`,
        });
      }
    }

    const meses = new Set(lista.map((t) => mesDe(t.transaction_date)));
    const presentes = mesesAnteriores.filter((m) => meses.has(m));
    const ultimo = lista[lista.length - 1];
    if (presentes.length >= 3 && ultimo.transaction_date < d35) {
      alertas.push({
        tipo: "parou", chave: `vigia:parou:${chave}:${mesDe(iso(hoje))}`, txId: ultimo.id, valor: ultimo.amount, data: ultimo.transaction_date,
        titulo: `${rotulo} aparecia todo mês e parou (último em ${ddmm(ultimo.transaction_date)})`,
        motivo: `Pagamentos em ${presentes.slice().reverse().join(", ")}; nenhum nos últimos 35 dias. Pode ser cancelamento, atraso ou outra forma de pagamento — só vale saber.`,
      });
    }

    for (let i = 0; i < recentes.length; i++) {
      for (let j = i + 1; j < recentes.length; j++) {
        const a = recentes[i], b = recentes[j];
        const dias = Math.abs(new Date(a.transaction_date).getTime() - new Date(b.transaction_date).getTime()) / 86400000;
        if (a.amount > 0 && Math.abs(a.amount - b.amount) < 0.01 && dias <= 3) {
          alertas.push({
            tipo: "duplicidade", chave: `vigia:dup:${a.id}:${b.id}`, txId: b.id, valor: b.amount, data: b.transaction_date,
            titulo: `Possível duplicidade: ${rotulo} — ${fmt(a.amount)} em ${ddmm(a.transaction_date)} e ${ddmm(b.transaction_date)}`,
            motivo: `Dois débitos iguais para o mesmo recebedor com ${Math.round(dias)} dia(s) de diferença. Se for cobrança em dobro, marque a segunda como duplicata na fila.`,
          });
        }
      }
    }
  }

  // Cinto e suspensório: dois grupos que ainda assim descrevam o mesmo fato não avisam duas vezes.
  const vistos = new Set<string>();
  for (let i = alertas.length - 1; i >= 0; i--) {
    const t = alertas[i].titulo;
    if (vistos.has(t)) alertas.splice(i, 1); else vistos.add(t);
  }
  if (alertas.length === 0) return jr({ ok: true, alertas: 0, message: "Nada fora do padrão." });
  const { data: existentes } = await admin
    .from("finance_review_queue")
    .select("suggested_description")
    .in("suggested_description", alertas.map((a) => a.chave))
    .gte("created_at", d45);
  const jaTem = new Set(((existentes ?? []) as any[]).map((r) => r.suggested_description));
  const novos = alertas.filter((a) => !jaTem.has(a.chave)).slice(0, 40);
  if (novos.length > 0) {
    const { error: e } = await admin.from("finance_review_queue").insert(novos.map((a) => ({
      kind: "anomaly", status: "pending", bank_transaction_id: null, related_transaction_id: a.txId,
      title: a.titulo.slice(0, 200), reasoning: a.motivo, confidence: 55,
      suggested_amount: a.valor, suggested_date: a.data, suggested_description: a.chave, dre_group: null,
    })));
    if (e) throw e;
  }
  const porTipo: Record<string, number> = {};
  for (const a of novos) porTipo[a.tipo] = (porTipo[a.tipo] ?? 0) + 1;
  return jr({
    ok: true, alertas: novos.length, ja_avisados: alertas.length - novos.length, por_tipo: porTipo,
    message: novos.length ? `${novos.length} alerta(s) novo(s) na caixa de entrada` : "Nada novo (já avisado antes).",
  });
}

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
  // D2 (dono, 17/09/2026): regra autônoma lança sozinha SÓ até o limite de lote. Acima
  // dele a proposta fica na caixa mesmo com regra "apply" — valor grande merece um olhar.
  const limiteLote = await lerLimiteLote(admin);
  // D4 (dono, 17/09/2026): contraparte com o CNPJ da própria empresa é transferência entre
  // contas mesmo sem a outra perna no extrato (a conta de destino pode não estar conectada).
  const { data: cfgCnpj } = await admin.from("app_settings").select("value").eq("key", "cnpj").maybeSingle();
  const cnpjEmpresa = String((cfgCnpj as { value?: string } | null)?.value ?? "").replace(/\D/g, "");

  const transacoes = await lerTudo<TransacaoOrfa>((de, ate) => {
    let q = admin
      .from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, counterparty_branch, counterparty_account, pix_end_to_end_id, source_type, bank_connection_id, installment_label, payee_mcc, tx_status")
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
    // Mesmo sem transação nova, o que está na fila sem identificação é completado.
    const r = await (await reclassificar(admin, true)).json().catch(() => ({}));
    return jr({ ok: true, message: "Nenhuma transação pendente na janela.", criadas: 0, completadas: Number(r?.atualizadas ?? 0) });
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

  // Quem é quem e o que cada linha paga: cadastros, "quem já pagou por quem" e tudo que
  // está em aberto ou já lançado. O mesmo contexto serve à "Revisar a fila".
  const contexto = await carregarContextoSeguro(admin);

  // Compra parcelada é UMA compra: a proposta nasce na parcela mais antiga, com o valor
  // total, e as outras pernas não viram despesa separada.
  const { compras: todasAsCompras, pernaDe } = agruparParcelamentos(transacoes as unknown as PernaDeParcelamento[]);

  // A MESMA COMPRA NÃO NASCE DUAS VEZES (25/09/2026). Esta varredura só lê transação ainda
  // não tratada; quando a parcela do mês seguinte chega, as irmãs antigas já viraram
  // lançamento e ficam invisíveis, e o agrupador montava "a compra" de novo só com ela —
  // 19 compras lançadas em dobro, R$ 12.445. Agora cada compra montada aqui procura, nas
  // parcelas antigas da mesma série, uma que já tenha virado lançamento. Achando, a parcela
  // nova sai da fila como parcela daquela compra, com o motivo escrito.
  //
  // Duplicata de importação fica fora da leitura: ela repete o número da parcela e
  // atrapalharia a série. Prova de "já lançada" é lançamento ou parcela já dada como tal;
  // proposta pendente não conta, porque ainda pode ser recusada.
  const historicas = todasAsCompras.length === 0
    ? []
    : await lerTudo<PernaDeParcelamento & { dismissed_kind: string | null }>((de, ate) =>
      admin.from("bank_transactions")
        .select("id, transaction_date, description, amount, counterparty_name, installment_label, dismissed_kind")
        .not("installment_label", "is", null)
        .or("dismissed_kind.is.null,dismissed_kind.eq.parcela")
        .order("id")
        .range(de, ate)
    );
  const dadaComoParcela = new Set(historicas.filter((h) => h.dismissed_kind === "parcela").map((h) => h.id));
  const jaLancadaComo = (id: string) => lancadas.has(id) || dadaComoParcela.has(id);

  const comprasJaLancadas: Array<{ compra: CompraParcelada; prova: PernaDeParcelamento }> = [];
  for (const c of todasAsCompras) {
    const prova = compraJaTratada(c, historicas, jaLancadaComo);
    if (prova) comprasJaLancadas.push({ compra: c, prova });
  }
  const chavesJaLancadas = new Set(comprasJaLancadas.map((j) => j.compra.chave));
  const compras = todasAsCompras.filter((c) => !chavesJaLancadas.has(c.chave));

  let parcelasDeCompraJaLancada = 0;
  for (const { compra, prova } of comprasJaLancadas) {
    const soltas = compra.pernas.map((perna) => perna.id).filter((id) => !jaLancadaComo(id));
    if (soltas.length === 0) continue;
    const valorParcela = compra.valorDaParcela.toFixed(2).replace(".", ",");
    const motivo = `Parcela da compra já lançada (${compra.totalDeParcelas}x de R$ ${valorParcela}; reconhecida pela parcela ${prova.installment_label} de ${prova.transaction_date})`;
    const { error: eParc } = await admin.from("bank_transactions").update({
      reconciled: true,
      dismissed_reason: motivo,
      dismissed_kind: "parcela",
      dismissed_at: new Date().toISOString(),
      dismissed_by: null,
    }).in("id", soltas);
    if (eParc) throw eParc;
    // Se alguma já estava na fila como proposta, ela deixa de valer pelo mesmo motivo.
    await admin.from("finance_review_queue").update({
      status: "superseded",
      decision_note: "Parcela de compra parcelada que já tem lançamento",
    }).in("bank_transaction_id", soltas).eq("status", "pending");
    for (const id of soltas) naFila.delete(id);
    await anotar(admin, {
      acao: "ignorou",
      autor: null,
      bank_transaction_id: soltas[0],
      valor: Number((compra.valorDaParcela * soltas.length).toFixed(2)),
      detalhe: `${compra.rotulo}: ${motivo}`.slice(0, 300),
    });
    parcelasDeCompraJaLancada += soltas.length;
  }

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
    // Parcela de compra que já tem lançamento acabou de sair da fila acima.
    if (chavesJaLancadas.has(pernaDe.get(tx.id) ?? "")) return false;
    return tx.transaction_type === "debit" || tx.transaction_type === "credit";
  });

  // O corte é sobre os ELEGÍVEIS, não sobre o que veio do banco: as propostas criadas neste
  // lote entram em `naFila` e são excluídas na chamada seguinte, então repetir a chamada
  // avança sempre. Cortar a consulta em vez da fila devolveria sempre as mesmas 200 e o
  // mutirão nunca sairia do lugar.
  // Mutirão do histórico ataca os MAIORES valores primeiro (D2): cada rodada de 200 é um
  // clique do gestor, e os R$ que faltam no resultado estão concentrados em poucas linhas.
  const ordenados = incluirHistorico
    ? [...elegiveis].sort((a, b) => Math.abs(Number(b.amount)) - Math.abs(Number(a.amount)))
    : elegiveis;
  const desteLote = incluirHistorico ? ordenados.slice(0, LOTE_HISTORICO) : elegiveis;
  const restantes = elegiveis.length - desteLote.length;

  const linhas: Array<Record<string, any>> = [];
  const autoAplicar: Array<Record<string, any>> = [];
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

    const docContraparte = String(tx.counterparty_document ?? "").replace(/\D/g, "");
    if (cnpjEmpresa.length === 14 && docContraparte === cnpjEmpresa) {
      linhas.push({
        kind: "internal_transfer",
        bank_transaction_id: tx.id,
        related_transaction_id: null,
        title: `Transferência entre contas: ${tx.description}`.slice(0, 160),
        reasoning: "A contraparte é o CNPJ da própria HBR: o dinheiro mudou de conta, não de dono.",
        confidence: 95,
        suggested_amount: tx.amount,
        suggested_date: tx.transaction_date,
        suggested_category: "Transferência entre contas",
        suggested_description: tx.description.slice(0, 200),
        dre_group: "nao_operacional",
      });
      continue;
    }

    const p = montarProposta(tx, fornecedores, memoria.porFornecedor, regras, memoria.porNome);

    // Fornecedor, favorecido e cliente com a evidência escrita, e o que a linha provavelmente
    // paga (conta em aberto, pagamento já lançado, sinal, saldo de OS).
    const id = identificarLinha(tx as unknown as TxDaFila, p, contexto);

    // OC do MESMO fornecedor com valor idêntico — o par é forte o bastante para sugerir,
    // fraco o bastante para exigir confirmação: duas OCs de igual valor existem.
    const oc = id.supplierId
      ? ocs.find((o) => o.supplier_id === id.supplierId
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
      suggested_category: id.categoria,
      suggested_description: p.suggestedDescription,
      suggested_supplier_id: id.supplierId,
      suggested_payee_id: id.payeeId,
      suggested_client_id: id.clientId,
      // A OC costuma saber para qual serviço a compra foi — herdar isso evita perguntar
      // duas vezes a mesma coisa. Sem OC, vale a OS do vínculo forte.
      suggested_purchase_order_id: oc?.id ?? null,
      suggested_service_order_id: oc?.service_order_id ?? id.serviceOrderId,
      dre_group: id.dreGroup,
      applied_rule_id: p.appliedRuleId,
      evidencia: id.evidencia,
      vinculo_sugerido: id.vinculo,
      reasoning: [
        compra && descreverParcelamento(compra),
        p.reasoning,
        ...id.frases,
        oc && `Mesmo valor da ordem de compra ${oc.po_number}, do mesmo fornecedor`,
      ].filter(Boolean).join(" · "),
    };
    linhas.push(linha);
    // Regra com autonomia foi conferida pelo gestor no momento em que ele a criou; segurar
    // a proposta para ele confirmar de novo seria pedir a mesma decisão duas vezes.
    if (p.autoAplicavel && Math.abs(Number(tx.amount)) <= limiteLote && !exigeDecisao(id.vinculo)) autoAplicar.push(linha);
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

  // Anotações antecipadas ("o Pix de 1.500 é da TSD"): a linha que acabou de chegar ganha o
  // que o dono disse. Vem ANTES do automático — e o que foi anotado não é lançado sozinho:
  // a anotação classifica; aprovar continua sendo dele.
  let anotadas = 0;
  const anotadasAgora = new Set<string>();
  try {
    const { data: n } = await admin.rpc("aplicar_anotacoes_pendentes");
    anotadas = Number(n ?? 0);
    if (anotadas > 0) {
      const { data: aplicadas } = await admin.from("anotacoes_do_extrato").select("bank_transaction_id")
        .eq("status", "aplicada").gte("aplicada_em", new Date(Date.now() - 10 * 60_000).toISOString());
      for (const a of (aplicadas ?? []) as any[]) if (a.bank_transaction_id) anotadasAgora.add(String(a.bank_transaction_id));
    }
  } catch (e) {
    console.error("[finance-review] aplicar anotações falhou", e);
  }

  // Aplica de imediato o que as regras autônomas resolveram. Cada lançamento fica ligado à
  // regra que o criou, então desligar a regra e desfazer o que ela fez são a mesma consulta.
  let lancadasSozinhas = 0;
  const idsAuto = autoAplicar
    .filter((l) => !anotadasAgora.has(String(l.bank_transaction_id)))
    .map((l) => idsPorTransacao.get(String(l.bank_transaction_id)))
    .filter((v): v is string => !!v);
  if (idsAuto.length > 0) {
    const resposta = await aprovar(admin, idsAuto, null, {}, "regra");
    const corpo = await resposta.json();
    lancadasSozinhas = Number(corpo?.aprovadas ?? 0);
  }

  /**
   * Lançar sozinho por CONFIANÇA (decisão do dono, 25/09/2026).
   *
   * Só saída, confiança na faixa que acertou 98,6% (85+), abaixo do limite de lote, com
   * categoria de verdade (não "Outras despesas"), sem alerta do vigilante sobre a transação
   * e sem "pode já estar lançado". Fica marcada como automática, aparece em "Lançados
   * sozinhos" e se desfaz como qualquer aprovação.
   */
  const cfgAuto = await admin.from("app_settings").select("key, value")
    .in("key", ["finance_auto_approve", "finance_auto_approve_min_confidence"]);
  const mapaAuto = Object.fromEntries(((cfgAuto.data ?? []) as { key: string; value: string }[]).map((r) => [r.key, r.value]));
  const autoLigado = String(mapaAuto.finance_auto_approve ?? "off").toLowerCase() === "on";
  const confiancaMinima = Math.max(85, Number(mapaAuto.finance_auto_approve_min_confidence ?? 85) || 85);
  if (autoLigado) {
    const jaPorRegra = new Set([...autoAplicar.map((l) => String(l.bank_transaction_id)), ...anotadasAgora]);
    // Transação com alerta do vigilante pendente não entra: o alerta existe para alguém olhar.
    const comAlerta = new Set<string>();
    const txs = linhas.filter((l) => l.kind === "create_payable").map((l) => String(l.bank_transaction_id));
    for (let i = 0; i < txs.length; i += 150) {
      const { data } = await admin.from("finance_review_queue").select("related_transaction_id")
        .eq("kind", "anomaly").eq("status", "pending").in("related_transaction_id", txs.slice(i, i + 150));
      for (const r of (data ?? []) as any[]) comAlerta.add(String(r.related_transaction_id));
    }
    const idsConfianca = selecionarParaLancarSozinho(linhas as unknown as LinhaCandidata[], {
      confiancaMinima, limiteLote, comAlerta, jaPorRegra,
    })
      .map((l) => idsPorTransacao.get(String(l.bank_transaction_id)))
      .filter((v): v is string => !!v);
    if (idsConfianca.length > 0) {
      const resposta = await aprovar(admin, idsConfianca, null, {}, "confianca");
      const corpo = await resposta.json();
      lancadasSozinhas += Number(corpo?.aprovadas ?? 0);
    }
  }

  // Linhas que nasceram antes do identificador (ou antes de um cadastro novo) ganham quem é e
  // o que pagam na própria varredura diária — sem depender de alguém clicar em "Revisar a fila".
  let completadas = 0;
  try {
    const r = await (await reclassificar(admin, true)).json();
    completadas = Number(r?.atualizadas ?? 0);
  } catch (e) {
    console.error("[finance-review] completar identificação falhou", e);
  }

  const partes = [
    criadas > 0 ? `${criadas - lancadasSozinhas} proposta(s) para revisar` : "Nada novo para propor",
    completadas > 0 ? `${completadas} já na fila ganharam identificação` : "",
    anotadas > 0 ? `${anotadas} classificada(s) pelas suas anotações` : "",
    lancadasSozinhas > 0 ? `${lancadasSozinhas} lançada(s) sozinha(s) — veja em "Lançados sozinhos"` : "",
    pares.length ? `${pares.length} transferência(s) entre contas` : "",
    parcelasDeCompraJaLancada > 0 ? `${parcelasDeCompraJaLancada} parcela(s) de compra já lançada saíram da fila` : "",
    restantes > 0 ? `faltam ${restantes} do histórico` : "",
  ].filter(Boolean);

  return jr({
    ok: true,
    criadas,
    lancadas_por_regra: lancadasSozinhas,
    transferencias_internas: pares.length,
    parcelas_de_compra_ja_lancada: parcelasDeCompraJaLancada,
    elegiveis_lote: linhas.filter((l) => Number(l.suggested_amount) < limiteLote).length,
    limite_lote: limiteLote,
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
async function reclassificar(admin: DbClient, soSemEvidencia = false) {
  // Antes de reclassificar, juntar o que é a mesma compra: classificar dez vezes a mesma
  // coisa é trabalho que não deveria existir, e vale a pena eliminá-lo antes de gastar
  // uma decisão com ele.
  const parcelamentos = await consolidarParcelamentosNaFila(admin);

  const pendentes = await lerTudo<any>((de, ate) =>
    admin
      .from("finance_review_queue")
      .select(`id, kind, bank_transaction_id, suggested_category, suggested_amount,
               suggested_supplier_id, suggested_payee_id, suggested_client_id, suggested_service_order_id,
               dre_group, applied_rule_id, confidence, reasoning, evidencia, vinculo_sugerido,
               bank_transactions!finance_review_queue_bank_transaction_id_fkey (
                 id, transaction_date, description, amount, transaction_type,
                 counterparty_name, counterparty_document, counterparty_branch, counterparty_account,
                 pix_end_to_end_id, source_type, installment_label )`)
      .eq("status", "pending")
      .order("id")
      .range(de, ate)
  );

  // Transferência entre contas não se classifica por regra de despesa: ela já é o que é.
  // soSemEvidencia: a varredura diária só completa o que nasceu antes do identificador.
  const alvo = pendentes.filter((p) => p.kind !== "internal_transfer" && p.bank_transactions
    && (!soSemEvidencia || (p.evidencia == null && p.vinculo_sugerido == null)));
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

  const contexto = await carregarContextoSeguro(admin);

  /**
   * Cada linha é reidentificada: categoria e regra (como antes) e, agora, fornecedor,
   * favorecido, cliente, evidência e o que a linha paga. Foi o que faltou para as seis
   * entradas da MP Motorhomes: o cliente foi cadastrado depois e a fila nunca soube.
   * Só vão ao banco as linhas que mudaram, todas numa chamada.
   */
  const mudadas: Record<string, unknown>[] = [];
  let porRegra = 0;
  const igual = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

  for (const p of alvo) {
    const tx = p.bank_transactions as TransacaoOrfa;
    const nova = montarProposta(tx, fornecedores, memoria.porFornecedor, regras, memoria.porNome);
    const id = identificarLinha(tx as unknown as TxDaFila, nova, contexto);
    // A descrição da compra parcelada (quando há) continua no começo do motivo.
    const prefixo = String(p.reasoning ?? "").startsWith("Compra parcelada")
      ? String(p.reasoning).split(" · ")[0] : null;
    const linha = {
      id: p.id,
      suggested_category: id.categoria,
      dre_group: id.dreGroup,
      suggested_supplier_id: id.supplierId,
      suggested_payee_id: id.payeeId,
      suggested_client_id: id.clientId,
      suggested_service_order_id: id.serviceOrderId ?? p.suggested_service_order_id ?? null,
      applied_rule_id: nova.appliedRuleId,
      confidence: nova.confidence,
      reasoning: [prefixo, nova.reasoning, ...id.frases].filter(Boolean).join(" · "),
      evidencia: id.evidencia,
      vinculo_sugerido: id.vinculo,
    };
    // Sem contexto (leitura falhou), a identificação que a linha JÁ tem fica como está —
    // reavaliar não pode apagar o que se sabia por causa de uma falha de leitura.
    if (!contexto) {
      Object.assign(linha, {
        suggested_payee_id: p.suggested_payee_id ?? null, suggested_client_id: p.suggested_client_id ?? null,
        suggested_service_order_id: p.suggested_service_order_id ?? null,
        evidencia: p.evidencia ?? null, vinculo_sugerido: p.vinculo_sugerido ?? null,
      });
    }
    const mudou = linha.suggested_category !== p.suggested_category
      || linha.dre_group !== p.dre_group
      || (linha.suggested_supplier_id ?? null) !== (p.suggested_supplier_id ?? null)
      || (linha.suggested_payee_id ?? null) !== (p.suggested_payee_id ?? null)
      || (linha.suggested_client_id ?? null) !== (p.suggested_client_id ?? null)
      || (linha.suggested_service_order_id ?? null) !== (p.suggested_service_order_id ?? null)
      || (linha.applied_rule_id ?? null) !== (p.applied_rule_id ?? null)
      || !igual(linha.evidencia, p.evidencia)
      || !igual(linha.vinculo_sugerido, p.vinculo_sugerido);
    if (!mudou) continue;
    if (nova.appliedRuleId) porRegra += 1;
    mudadas.push(linha);
  }

  let atualizadas = 0;
  for (let i = 0; i < mudadas.length; i += 300) {
    const { data, error } = await admin.rpc("aplicar_reavaliacao_da_fila", { p_linhas: mudadas.slice(i, i + 300) });
    if (error) throw error;
    atualizadas += Number(data ?? 0);
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
  // Pelo nome SEM a parcela e com um centavo de folga: alguns bancos escrevem "COREMMA 2/4"
  // no nome, e o cartão joga o centavo que não divide numa parcela só. Com nome exato e
  // valor exato, as irmãs não eram achadas — a aprovação tirava da fila só a parcela
  // clicada, e as outras voltavam no dia seguinte como compras novas.
  const base = nomeSemParcela(ancora).replace(/[%_]/g, "");
  let q = admin
    .from("bank_transactions")
    .select("id, transaction_date, description, amount, counterparty_name, installment_label")
    .gte("amount", Number((ancora.amount - 0.02).toFixed(2)))
    .lte("amount", Number((ancora.amount + 0.02).toFixed(2)))
    .not("installment_label", "is", null)
    .limit(120);
  q = ancora.counterparty_name
    ? q.ilike("counterparty_name", `${base}%`)
    : q.ilike("description", `${base}%`);

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
  /** Aprovação sem clique: por regra com autonomia ou por confiança alta. Fica marcada e é desfazível. */
  automatica: "regra" | "confianca" | null = null,
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

  // Decisão do dono (14/09/2026): acima do limite de lote a proposta é aprovada UMA A UMA.
  // Em lote (mais de um id), o servidor tira do caminho o que passa do limite e devolve a
  // lista — assim nem a tela nem o agente conseguem contornar por engano. Transferência
  // entre contas não tem valor a julgar: passa.
  const todas = (propostas ?? []) as any[];
  const acimaDoLimite: string[] = [];
  let elegiveis = todas;
  if (ids.length > 1) {
    const limite = await lerLimiteLote(admin);
    elegiveis = todas.filter((p) => {
      if (p.kind !== "create_payable" && p.kind !== "create_receivable") return true;
      const valor = Math.abs(Number(overrides[p.id]?.amount ?? p.suggested_amount ?? 0));
      if (valor < limite) return true;
      acimaDoLimite.push(`${String(p.title).slice(0, 60)} (${valor.toFixed(2)})`);
      return false;
    });
  }

  for (const p of elegiveis) {
    try {
      const ov = overrides[p.id] ?? {};

      /**
       * O que esta linha PAGA. Escolha da pessoa primeiro; sem escolha, a política:
       * vínculo forte vale sozinho; "pode já estar lançado" sem vínculo forte barra a linha —
       * aprovar no escuro criaria o lançamento em dobro.
       */
      const sugerido = (p.vinculo_sugerido ?? null) as VinculoSugerido | null;
      let vinculo: OpcaoDeVinculo | null = null;
      if (ov.vinculo === "nenhum") vinculo = null;
      else if (ov.vinculo && typeof ov.vinculo === "object") {
        vinculo = [sugerido?.principal, ...(sugerido?.alternativas ?? [])].find((o) => o?.id === (ov.vinculo as { id: string }).id) ?? null;
        if (!vinculo) throw new Error("A opção escolhida não está mais entre as sugestões desta linha — revise a fila e escolha de novo");
      } else {
        vinculo = vinculoAutomatico(sugerido);
        if (!vinculo && exigeDecisao(sugerido)) {
          const o = sugerido!.principal;
          throw new Error(`Pode ser ${o.rotulo.replace(/^Pagamento já lançado: /, "")}, que JÁ está lançado. Abra a linha e escolha: casar com ele ou lançar novo`);
        }
      }

      // Casar com o que já existe: nenhum lançamento novo nasce.
      if (vinculo && vinculo.lancamentoId && vinculo.lado
          && (vinculo.tipo === "receivable" || vinculo.tipo === "payable" || vinculo.tipo === "existing_payment")) {
        const ladoCerto = p.kind === "create_receivable" ? "receivable" : "payable";
        if (vinculo.lado !== ladoCerto) throw new Error("O vínculo escolhido é do outro sentido do dinheiro");
        const { error: eCasar } = await admin.rpc("conciliar_lancamento", {
          p_tipo: vinculo.lado, p_id: vinculo.lancamentoId, p_transacao: p.bank_transaction_id, p_autor: userId,
        });
        if (eCasar) throw new Error(eCasar.message.replace(/^(P0001|42501|23514):\s*/, ""));
        await admin.from("finance_review_queue").update({
          status: "approved", decided_by: userId, decided_at: new Date().toISOString(), automatica,
          decision_note: `Casada com ${vinculo.rotulo}`.slice(0, 300),
        }).eq("id", p.id);
        feitos.push(p.id);
        continue;
      }
      // Sinal de orçamento: registra o sinal e converte o orçamento em OS, como o botão
      // "Receber sinal" — só quando a pessoa escolheu (nunca é automático).
      if (vinculo && vinculo.tipo === "quote_deposit") {
        if (p.kind !== "create_receivable") throw new Error("Sinal de orçamento só casa com entrada");
        const { data: sinal, error: eSinal } = await admin.rpc("registrar_sinal_pelo_extrato", {
          p_orcamento: vinculo.id, p_transacao: p.bank_transaction_id, p_autor: userId,
        });
        if (eSinal) throw new Error(eSinal.message.replace(/^(P0001|42501|23514):\s*/, ""));
        if ((sinal as any)?.receivable_id) recebidoPara.set(p.id, String((sinal as any).receivable_id));
        feitos.push(p.id);
        continue;
      }

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
        const osDaReceita = ov.serviceOrderId !== undefined
          ? ov.serviceOrderId
          : (vinculo?.tipo === "service_order_balance" ? vinculo.ordemDeServicoId : p.suggested_service_order_id ?? null);
        const clienteId = ov.clientId ?? p.suggested_client_id
          ?? (vinculo?.tipo === "service_order_balance" ? vinculo.clienteId : null) ?? null;
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
          // Ligada à OS, a receita entra na margem do serviço e a OS dá baixa sozinha
          // (sync_service_order_payment_status). Eram 52 receitas do extrato sem OS.
          service_order_id: osDaReceita,
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
        automatica,
        ...(automatica ? { decision_note: automatica === "regra" ? "Lançada sozinha pela sua regra" : `Lançada sozinha: confiança ${p.confidence}%` } : {}),
      }).eq("id", p.id);

      await anotar(admin, {
        acao: p.kind === "internal_transfer" ? "ignorou" : automatica ? "lancou_sozinho" : "aprovou_proposta",
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
    acima_do_limite: acimaDoLimite,
    pernas_de_parcelamento: pernasRetiradas,
    message: `${feitos.length} lançamento(s) criado(s)`
      + (pernasRetiradas > 0
        ? ` · ${pernasRetiradas} parcela(s) da mesma compra saíram da fila junto` : "")
      + (acimaDoLimite.length
        ? ` · ${acimaDoLimite.length} acima do limite de lote ficaram para aprovação individual` : "")
      + (falhas.length ? ` · ${falhas.length} falharam` : ""),
  });
}

/**
 * Dados da Receita para um CNPJ, para cadastrar sem digitar (Fase 2.2).
 *
 * BrasilAPI é pública e gratuita; o resultado fica 30 dias em `consulta_cnpj`, porque a
 * mesma empresa aparece dezenas de vezes no extrato. CPF não tem consulta pública: volta só
 * o que já se sabe.
 */
async function consultarDocumento(admin: DbClient, documento: string, userId: string | null) {
  if (!userId) return jr({ error: "unauthorized" }, 401);
  const doc = documento.replace(/\D/g, "");
  if (doc.length === 11) return jr({ ok: true, tipo: "cpf", documento: doc, dados: null });
  if (doc.length !== 14) return jr({ ok: false, error: "Documento precisa ter 11 (CPF) ou 14 (CNPJ) dígitos" }, 400);

  const { data: cache } = await admin.from("consulta_cnpj").select("dados, consultado_em").eq("cnpj", doc).maybeSingle();
  const fresco = cache && Date.now() - new Date((cache as any).consultado_em).getTime() < 30 * 86_400_000;
  let bruto = fresco ? (cache as any).dados : null;

  if (!bruto) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 8000);
      const res = await fetch(`https://brasilapi.com.br/api/cnpj/v1/${doc}`, { signal: ctl.signal });
      clearTimeout(t);
      if (res.status === 404) return jr({ ok: true, tipo: "cnpj", documento: doc, dados: null, aviso: "CNPJ não encontrado na Receita" });
      if (!res.ok) throw new Error(`Receita respondeu ${res.status}`);
      bruto = await res.json();
      await admin.from("consulta_cnpj").upsert({ cnpj: doc, dados: bruto, consultado_em: new Date().toISOString() });
    } catch (e) {
      // Sem a Receita o cadastro continua possível: com o nome do extrato, à mão.
      if (cache) bruto = (cache as any).dados;
      else return jr({ ok: true, tipo: "cnpj", documento: doc, dados: null, aviso: `Consulta à Receita indisponível agora (${String((e as Error)?.message ?? e).slice(0, 80)}). Preencha à mão.` });
    }
  }
  return jr({ ok: true, tipo: "cnpj", documento: doc, dados: lerRespostaDaReceita(doc, bruto as Record<string, unknown>) });
}

async function recusar(admin: DbClient, ids: string[], userId: string | null, note: string | null) {
  if (ids.length === 0) return jr({ error: "nenhuma proposta informada" }, 400);
  const { error } = await admin.from("finance_review_queue").update({
    status: "rejected", decided_by: userId, decided_at: new Date().toISOString(), decision_note: note,
  }).in("id", ids).eq("status", "pending");
  if (error) throw error;
  return jr({ ok: true, recusadas: ids.length, message: `${ids.length} proposta(s) recusada(s)` });
}
