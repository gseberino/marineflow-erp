// Quem é a contraparte e o que a linha paga — para a fila do Extrato.
//
// Usado por `gerar` (proposta nova) e por `reclassificar` ("Revisar a fila"), para que as
// duas cheguem ao MESMO resultado. Antes só a proposta nova era identificada: um cliente
// cadastrado depois nunca alcançava as entradas que já estavam esperando.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  identificarContraparte, indexarContrapartes, frasesDaIdentificacao,
  type Identificacao, type IndiceDeContrapartes, type Reconhecimento,
} from "../_shared/banking/contraparte.ts";
import { carregarCandidatos } from "../_shared/banking/candidatos.ts";
import { sugerirVinculo, type VinculoSugerido } from "../_shared/banking/vinculo.ts";
import type { Candidate } from "../_shared/banking/types.ts";

type DbClient = SupabaseClient<any, "public", any>;

export interface ContextoDeIdentificacao {
  indice: IndiceDeContrapartes;
  candidatos: Candidate[];
  categoriaDoFavorecido: Map<string, string>;
  drePorCategoria: Map<string, string>;
}

/** Leitura paginada: o PostgREST corta em 1000 linhas sem avisar. */
async function lerPaginas<T>(consulta: (de: number, ate: number) => any, teto = 20000): Promise<T[]> {
  const todas: T[] = [];
  for (let de = 0; de < teto; de += 1000) {
    const { data, error } = await consulta(de, de + 999);
    if (error) throw error;
    const pagina = (data ?? []) as T[];
    todas.push(...pagina);
    if (pagina.length < 1000) break;
  }
  return todas;
}

/**
 * Carrega o contexto sem nunca derrubar a varredura: se alguma leitura falhar, a proposta
 * continua nascendo como antes (só sem a identificação extra) e o erro fica no log. Uma
 * falha aqui não pode custar o dia inteiro de propostas.
 */
export async function carregarContextoSeguro(admin: DbClient): Promise<ContextoDeIdentificacao | null> {
  try {
    return await carregarContexto(admin);
  } catch (e) {
    console.error("[finance-review] contexto de identificação indisponível — seguindo sem ele", e);
    return null;
  }
}

export async function carregarContexto(admin: DbClient): Promise<ContextoDeIdentificacao> {
  const [fornecedores, favorecidos, clientes, categorias] = await Promise.all([
    lerPaginas<any>((de, ate) => admin.from("suppliers").select("id, name, trade_name, cnpj_cpf").order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("payees").select("id, name, document, bank_branch, bank_account, default_category").eq("active", true).order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("clients").select("id, name, cpf_cnpj").order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("financial_categories").select("name, type, dre_group").order("name").range(de, ate)),
  ]);

  // O que já se lançou a partir do extrato, por documento — "quem já pagou por quem".
  const [saidas, entradas] = await Promise.all([
    lerPaginas<any>((de, ate) => admin.from("payables")
      .select("supplier_id, payee_id, bank_transactions!payables_bank_transaction_id_fkey(counterparty_document)")
      .not("bank_transaction_id", "is", null).neq("status", "cancelled").order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("receivables")
      .select("client_id, bank_transactions!receivables_bank_transaction_id_fkey(counterparty_document)")
      .not("bank_transaction_id", "is", null).neq("status", "cancelled").order("id").range(de, ate)),
  ]);

  const historico = [
    ...saidas.map((p) => ({
      documento: p.bank_transactions?.counterparty_document ?? null, lado: "saida" as const,
      supplier_id: p.supplier_id, payee_id: p.payee_id,
    })),
    ...entradas.map((r) => ({
      documento: r.bank_transactions?.counterparty_document ?? null, lado: "entrada" as const,
      client_id: r.client_id,
    })),
  ];

  const indice = indexarContrapartes({ fornecedores, favorecidos, clientes, historico });
  const candidatos = await carregarCandidatos(admin);

  return {
    indice,
    candidatos,
    categoriaDoFavorecido: new Map(favorecidos.filter((f) => f.default_category).map((f) => [f.id, f.default_category])),
    drePorCategoria: new Map(categorias.filter((c) => c.type === "payable" && c.dre_group).map((c) => [c.name, c.dre_group])),
  };
}

export interface TxDaFila {
  id: string;
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: "credit" | "debit";
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  counterparty_branch?: string | null;
  counterparty_account?: string | null;
  pix_end_to_end_id?: string | null;
}

/** O que o motor de propostas já decidiu (categoria, regra, fornecedor pelo nome). */
export interface PropostaBase {
  kind: string;
  suggestedCategory: string;
  dreGroup: string;
  confidence: number;
  appliedRuleId: string | null;
  suggestedSupplierId: string | null;
  /** Como o motor reconheceu o fornecedor (documento, nome igual ou nome cortado pelo banco). */
  fornecedorPor?: "documento" | "nome_identico" | "nome_cortado" | null;
  /** O fornecedor foi dito pela regra (e não só a categoria). Ausente = como antes: a regra. */
  fornecedorPelaRegra?: boolean;
}

/**
 * Versão do motor que identificou a linha, gravada na evidência.
 *
 * A varredura diária refaz toda linha pendente de versão anterior: foi o que faltou em
 * 26/09/2026, quando a regra "nome diferente nunca identifica" entrou e as linhas já na fila
 * continuavam com o fornecedor do critério antigo, rotulado como "nome idêntico".
 */
export const MOTOR_DA_FILA = 2;

export interface LinhaIdentificada {
  supplierId: string | null;
  payeeId: string | null;
  clientId: string | null;
  /** OS apontada pelo vínculo forte, quando há. */
  serviceOrderId: string | null;
  categoria: string;
  dreGroup: string;
  evidencia: Record<string, unknown> | null;
  vinculo: VinculoSugerido | null;
  frases: string[];
}

function semNulos(i: Identificacao): Record<string, unknown> | null {
  const o = Object.fromEntries(Object.entries(i).filter(([, v]) => v != null));
  return Object.keys(o).length ? o : null;
}

export function identificarLinha(tx: TxDaFila, p: PropostaBase, ctx: ContextoDeIdentificacao | null): LinhaIdentificada {
  // Sem contexto (leitura falhou): o que o motor de propostas já sabia, e nada mais.
  if (!ctx) {
    return {
      supplierId: p.suggestedSupplierId, payeeId: null, clientId: null, serviceOrderId: null,
      categoria: p.suggestedCategory, dreGroup: p.dreGroup, evidencia: null, vinculo: null, frases: [],
    };
  }
  const ident = identificarContraparte(tx, ctx.indice);
  const frases: string[] = [];

  // Fornecedor: o do motor de propostas vale (regra sua ou CNPJ/nome, já com a trava da
  // cabeça do nome); o identificador preenche quando o motor não achou — pelo histórico.
  let supplierId = p.suggestedSupplierId;
  if (supplierId) {
    if (ident.fornecedor?.id !== supplierId) {
      const e = ctx.indice.porId.fornecedor.get(supplierId);
      const nome = e?.nome ?? "fornecedor";
      // "Regra sua aponta X" só quando a regra DISSE o fornecedor. Regra de texto que só dá a
      // categoria não aponta ninguém: aí vale como o motor reconheceu — e o nome cortado
      // pelo banco continua pedindo "confira", com ou sem regra.
      const pelaRegra = !!p.appliedRuleId && p.fornecedorPelaRegra !== false && p.fornecedorPor !== "nome_cortado";
      const por: Reconhecimento["por"] = p.fornecedorPor === "nome_cortado" ? "nome_cortado"
        : pelaRegra ? "regra"
        : (p.fornecedorPor ?? "nome_identico");
      ident.fornecedor = {
        id: supplierId, nome, por,
        detalhe: por === "nome_cortado" ? `Mesmo nome de ${nome}, cortado pelo banco — confira`
          : por === "regra" ? `Regra sua aponta ${nome}`
          : por === "documento" ? `CNPJ/CPF confere com o fornecedor ${nome}`
          : `Mesmo nome do fornecedor ${nome}`,
      } as Reconhecimento;
    }
  } else if (ident.fornecedor) {
    supplierId = ident.fornecedor.id;
    frases.push(ident.fornecedor.detalhe);
  }
  if (supplierId) ident.cadastrar = null;

  const payeeId = ident.favorecido?.id ?? null;
  const clientId = ident.cliente?.id ?? null;
  for (const r of [ident.favorecido, ident.cliente]) if (r) frases.push(r.detalhe);
  for (const f of frasesDaIdentificacao({ ...ident, fornecedor: null, favorecido: null, cliente: null })) frases.push(f);

  // Categoria padrão do favorecido: "paguei o Roberto" é diária de campo, sempre. Só entra
  // onde nada melhor decidiu — regra sua vence, e confiança alta do motor também.
  let categoria = p.suggestedCategory;
  let dreGroup = p.dreGroup;
  const padrao = payeeId ? ctx.categoriaDoFavorecido.get(payeeId) : undefined;
  if (padrao && !p.appliedRuleId && (categoria === "Outras despesas" || p.confidence < 60)) {
    categoria = padrao;
    dreGroup = ctx.drePorCategoria.get(padrao) ?? dreGroup;
    frases.push(`Categoria padrão de ${ident.favorecido?.nome}: ${padrao}`);
  }

  const vinculo = sugerirVinculo(
    {
      id: tx.id, transaction_date: tx.transaction_date, description: tx.description, amount: Number(tx.amount),
      transaction_type: tx.transaction_type, counterparty_name: tx.counterparty_name,
      counterparty_document: tx.counterparty_document, pix_end_to_end_id: tx.pix_end_to_end_id,
    },
    ctx.candidatos,
    ident.cliente ? { id: ident.cliente.id, nome: ident.cliente.nome } : null,
  );

  let serviceOrderId: string | null = null;
  if (vinculo) {
    const v = vinculo.principal;
    frases.push(
      v.jaLancado
        ? `Parece ser ${v.rotulo.replace(/^Pagamento já lançado: /, "")}, JÁ LANÇADO — diga se é o mesmo dinheiro (casar) ou outro (${v.confianca} pontos)`
        : `Parece pagar: ${v.rotulo} (${v.confianca} pontos) — diga se é isso`,
    );
    // A OS fica como SUGESTÃO: a tela pergunta "é desta OS?" e só a resposta liga (decisão do
    // dono, 26/09/2026). Antes, com 70+ pontos, a OS e o cliente dela já vinham escolhidos.
    if (v.confianca >= 70 && !v.converteOrcamento) serviceOrderId = v.ordemDeServicoId;
  }

  return {
    supplierId, payeeId, clientId, serviceOrderId, categoria, dreGroup,
    evidencia: { ...(semNulos(ident) ?? {}), motor: MOTOR_DA_FILA }, vinculo, frases,
  };
}
