// Quem é a contraparte e o que a linha paga — para a fila do Extrato.
//
// Usado por `gerar` (proposta nova) e por `reclassificar` ("Revisar a fila"), para que as
// duas cheguem ao MESMO resultado. Antes só a proposta nova era identificada: um cliente
// cadastrado depois nunca alcançava as entradas que já estavam esperando.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  documentoNormalizado, identificarContraparte, indexarContrapartes, situacaoDoClienteSugerido,
  frasesDaIdentificacao, nomeDaDescricao, pagadoresDoDocumento, vetoDoPagador,
  type AnotacaoDoDono, type CadastroParaIdentificar, type CandidatoDoPagamento, type ClienteDaEvidencia, type Identificacao,
  type IndiceDeContrapartes, type Reconhecimento,
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
  /**
   * Favorecido SÓCIO → a última categoria que o dono escolheu ao aprovar uma despesa dele (20/10/2026,
   * spec-papelada-fix.md B2). Ausente = como antes.
   */
  ultimaEscolhaDoSocio?: Map<string, EscolhaDoSocio>;
  /**
   * A leitura de pagadores_do_cliente falhou (revisão de 23/10/2026): não se sabe o que o dono guardou nem o que vetou.
   * A regra de cliente não decide sozinha (a linha pergunta, com o cliente da regra como candidato), o histórico sempre
   * pede o SIM, e a ENTRADA sai sem a marca do motor — a varredura diária a refaz quando a leitura voltar.
   */
  pagadoresIndisponiveis?: boolean;
}

/** A última escolha do dono para um sócio: a categoria e quando ele decidiu. */
export interface EscolhaDoSocio {
  categoria: string;
  em: string;
}

/** As categorias que a separação pelo salário mínimo (separar_pro_labore) reparte mês a mês. */
const CATEGORIAS_DA_SEPARACAO = new Set(["Pró-labore", "Retirada de sócio"]);

/**
 * Da trilha de aprovações (reconciliation_log 'aprovou_proposta'), a ÚLTIMA categoria escolhida pelo dono
 * para cada favorecido. "Outras despesas" não é escolha (é a falta dela, como na memória do motor) e
 * categoria que não existe mais no plano ("Pró-labore e retirada", até 25/09) não volta como sugestão.
 */
export function ultimaEscolhaPorFavorecido(
  logs: Array<{ payable_id: string | null; ocorrido_em: string; depois: { categoria?: string | null } | null }>,
  favorecidoDaDespesa: Map<string, string>,
  categoriasAtivas: Set<string>,
): Map<string, EscolhaDoSocio> {
  const m = new Map<string, EscolhaDoSocio>();
  for (const l of logs) {
    const favorecido = l.payable_id ? favorecidoDaDespesa.get(String(l.payable_id)) : undefined;
    const categoria = String(l.depois?.categoria ?? "").trim();
    if (!favorecido || !categoria || categoria === "Outras despesas" || !categoriasAtivas.has(categoria)) continue;
    const atual = m.get(favorecido);
    if (!atual || String(l.ocorrido_em) > atual.em) m.set(favorecido, { categoria, em: String(l.ocorrido_em) });
  }
  return m;
}

/** Lê a última escolha do dono para cada sócio. Lança se a leitura falhar (quem chama segue sem ela). */
async function lerUltimaEscolhaDoSocio(
  admin: DbClient,
  socios: string[],
  categoriasAtivas: Set<string>,
): Promise<Map<string, EscolhaDoSocio>> {
  if (socios.length === 0) return new Map();
  // A despesa principal (divisao_id nulo): a parte que a separação criou não é decisão do dono.
  const despesas = await lerPaginas<{ id: string; payee_id: string }>((de, ate) => admin.from("payables")
    .select("id, payee_id").in("payee_id", socios).not("bank_transaction_id", "is", null).is("divisao_id", null)
    .order("id").range(de, ate));
  const favorecidoDaDespesa = new Map(despesas.map((d) => [String(d.id), String(d.payee_id)]));
  const ids = [...favorecidoDaDespesa.keys()];
  const logs: Array<{ payable_id: string | null; ocorrido_em: string; depois: { categoria?: string | null } | null }> = [];
  for (let i = 0; i < ids.length; i += 150) {
    const { data, error } = await admin.from("reconciliation_log")
      .select("payable_id, ocorrido_em, depois")
      .eq("acao", "aprovou_proposta").not("autor", "is", null).in("payable_id", ids.slice(i, i + 150));
    if (error) throw error;
    logs.push(...((data ?? []) as typeof logs));
  }
  return ultimaEscolhaPorFavorecido(logs, favorecidoDaDespesa, categoriasAtivas);
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

/**
 * O que o motor da fila lê de pagadores_do_cliente:
 *   - confirmados: os pagadores CONFIRMADOS pelo dono, só de cliente ativo — cliente desativado para de ser sugerido
 *     sem mudar dado (reativar o cliente reativa a sugestão);
 *   - vetados: os RECUSADOS e PAUSADOS (revisão de 23/10/2026) — o "não" do dono para aquele documento × cliente, que
 *     tira o cliente da sugestão (histórico, nome idêntico, pagador conhecido). Vale para qualquer cliente: só tira.
 * O proposto (sem o SIM) não entra. Lança se a leitura falhar — quem chama marca pagadoresIndisponiveis.
 */
export async function lerPagadoresDoMotor(
  admin: DbClient,
  clientesAtivos: Set<string>,
): Promise<{
  confirmados: NonNullable<CadastroParaIdentificar["pagadores"]>;
  vetados: NonNullable<CadastroParaIdentificar["vetados"]>;
}> {
  const linhas = await lerPaginas<{
    documento: string; client_id: string; relacao: string; situacao: string; confirmado_em: string | null;
  }>((de, ate) => admin.from("pagadores_do_cliente")
    .select("documento, client_id, relacao, situacao, confirmado_em")
    .in("situacao", ["confirmado", "recusado", "pausado"]).order("id").range(de, ate));
  return {
    confirmados: linhas
      .filter((p) => p.situacao === "confirmado" && clientesAtivos.has(String(p.client_id)))
      .map(({ documento, client_id, relacao, confirmado_em }) => ({ documento, client_id, relacao, confirmado_em })),
    vetados: linhas
      .filter((p) => p.situacao === "recusado" || p.situacao === "pausado")
      .map(({ documento, client_id, situacao }) => ({ documento, client_id, situacao })),
  };
}

export async function carregarContexto(admin: DbClient): Promise<ContextoDeIdentificacao> {
  const [fornecedores, favorecidos, clientes, categorias] = await Promise.all([
    lerPaginas<any>((de, ate) => admin.from("suppliers").select("id, name, trade_name, cnpj_cpf").order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("payees").select("id, name, kind, document, bank_branch, bank_account, default_category").eq("active", true).order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("clients").select("id, name, cpf_cnpj, active").order("id").range(de, ate)),
    lerPaginas<any>((de, ate) => admin.from("financial_categories").select("name, type, dre_group, active").order("name").range(de, ate)),
  ]);

  // Pagadores conhecidos e os vetos do dono (leva 8). Falhar aqui NÃO derruba a identificação (carregarContextoSeguro
  // devolveria nulo para tudo), mas também não vira "ninguém guardou nada" em silêncio: marca pagadoresIndisponiveis —
  // a regra de cliente não decide sozinha, o histórico pede o SIM e a entrada sai sem a marca do motor (a varredura a
  // refaz). Inclui a tabela ainda não existir (função publicada antes da migration).
  let pagadores: NonNullable<CadastroParaIdentificar["pagadores"]> = [];
  let vetados: NonNullable<CadastroParaIdentificar["vetados"]> = [];
  let pagadoresIndisponiveis = false;
  try {
    ({ confirmados: pagadores, vetados } = await lerPagadoresDoMotor(
      admin, new Set(clientes.filter((c) => c.active !== false).map((c) => String(c.id)))));
  } catch (e) {
    pagadoresIndisponiveis = true;
    console.error("[finance-review] pagadores do cliente indisponíveis — as entradas perguntam de quem é (também as de regra de cliente) e a varredura diária as refaz",
      (e as Error)?.message ?? e);
  }

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

  const indice = indexarContrapartes({
    fornecedores, favorecidos, clientes, historico, pagadores, vetados, pagadoresIndisponiveis,
  });
  const candidatos = await carregarCandidatos(admin);

  // Pix para o sócio segue a última escolha do dono (B2). Falhar aqui NÃO derruba a identificação das
  // linhas (carregarContextoSeguro devolveria nulo para tudo): segue sem esta parte, como antes.
  let ultimaEscolhaDoSocio = new Map<string, EscolhaDoSocio>();
  try {
    const ativas = new Set(categorias.filter((c) => c.type === "payable" && c.active !== false).map((c) => String(c.name)));
    ultimaEscolhaDoSocio = await lerUltimaEscolhaDoSocio(
      admin, favorecidos.filter((f) => f.kind === "socio").map((f) => String(f.id)), ativas);
  } catch (e) {
    console.error("[finance-review] última escolha do sócio indisponível — seguindo sem ela", (e as Error)?.message ?? e);
  }

  return {
    indice,
    candidatos,
    categoriaDoFavorecido: new Map(favorecidos.filter((f) => f.default_category).map((f) => [f.id, f.default_category])),
    drePorCategoria: new Map(categorias.filter((c) => c.type === "payable" && c.dre_group).map((c) => [c.name, c.dre_group])),
    ultimaEscolhaDoSocio,
    pagadoresIndisponiveis,
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
  /** Entrada: o cliente que uma regra sua diz ser o dono do CPF/CNPJ ("o Pix de X é do Y"). */
  suggestedClientId?: string | null;
}

/**
 * Versão do motor que identificou a linha, gravada na evidência.
 *
 * A varredura diária refaz toda linha pendente de versão anterior: foi o que faltou em
 * 26/09/2026, quando a regra "nome diferente nunca identifica" entrou e as linhas já na fila
 * continuavam com o fornecedor do critério antigo, rotulado como "nome idêntico".
 *
 * 3 (leva 8, 22/10/2026): a entrada deixou de propor "cadastrar cliente" com os dados de quem pagou (pergunta "de
 * quem é?"), ganhou o pagador conhecido e o histórico de terceiro passou a pedir o SIM. Subir a versão faz a
 * varredura diária refazer as entradas pendentes que ainda carregam o `cadastrar` antigo.
 */
export const MOTOR_DA_FILA = 3;

/** O que a aprovação precisa ler de uma proposta para saber de quem é a receita. */
export interface PropostaComCliente {
  suggested_client_id?: string | null;
  evidencia?: {
    cliente?: ClienteDaEvidencia | null;
    /** A anotação do dono aplicada à linha (_aplicar_anotacao grava {id, os_id}). */
    anotacao?: { id?: string | null; os_id?: string | null } | null;
  } | null;
}

/**
 * O cliente que a aprovação pode usar SEM a pessoa escolher: o sugerido, só na situação "vale"
 * (situacaoDoClienteSugerido): prova do motor deste cliente que não pede o SIM, ou anotação do dono que disse este
 * cliente. Na situação "pede_sim" (prova deste cliente que é vínculo, pagador conhecido ou histórico de terceiro) e na
 * "escolher" (sugerido que não é o da prova, sem anotação em vigor que o diga) só vale o cliente escolhido.
 *
 * `anotacao`: o que a anotação do dono disse, LIDO da anotação aplicada (cliente_id, os_id); null = lida e não há
 * (cancelada, trocada, leitura que falhou): nada dela vale. Ausente (undefined) = não lida: vale a marca que a evidência
 * guarda (evidencia.anotacao: {id, os_id}). Revisão de 23/10/2026: o "o Pix de 1.500 é da TSD" troca o cliente sugerido
 * e mantém a prova antiga do motor; a prova antiga não pode pedir o SIM sobre o cliente que o dono disse — e, sem a
 * anotação (desfeita, leitura que falhou), o sugerido que não é o da prova não vale sozinho (4ª rodada).
 */
export function clienteQueAprovacaoUsa(p: PropostaComCliente, anotacao?: AnotacaoDoDono | null): string | null {
  return situacaoDoClienteSugerido(p.suggested_client_id, p.evidencia?.cliente, anotacaoQueVale(p, anotacao)) === "vale"
    ? (p.suggested_client_id ?? null)
    : null;
}

/** A anotação lida (mesmo nula) vence; sem leitura, a marca que a evidência guarda. */
function anotacaoQueVale(p: PropostaComCliente, lida: AnotacaoDoDono | null | undefined): AnotacaoDoDono | null {
  return lida !== undefined ? lida : (p.evidencia?.anotacao ?? null);
}

/** A recusa da situação "escolher": nenhum cliente — nem o sugerido, nem o da prova antiga (nunca "Sim, é do <prova>"). */
export const PEDIDO_DE_ESCOLHA_DO_CLIENTE = "Escolha o cliente antes de aprovar esta receita: o cliente sugerido não veio da "
  + "prova do motor nem de uma anotação sua em vigor (a anotação foi desfeita, ou não deu para conferi-la agora)";

/**
 * A recusa legível quando a receita ficou sem cliente porque o sugerido não vale sozinho:
 *   - "pede_sim": "Confirme o cliente: este pagador já pagou por X — responda 'Sim, é do X' ou escolha outro";
 *   - "escolher": PEDIDO_DE_ESCOLHA_DO_CLIENTE ("Escolha o cliente…") — nunca o "Sim, é do <prova antiga>".
 * Null = a recusa de sempre ("Escolha o cliente"). O vínculo antigo não entra: lá o cliente veio do que a linha paga,
 * não de quem pagou.
 */
export function pedidoDeConfirmacaoDoCliente(p: PropostaComCliente, anotacao?: AnotacaoDoDono | null): string | null {
  const c = p.evidencia?.cliente;
  const situacao = situacaoDoClienteSugerido(p.suggested_client_id, c, anotacaoQueVale(p, anotacao));
  if (situacao === "escolher") return PEDIDO_DE_ESCOLHA_DO_CLIENTE;
  if (situacao !== "pede_sim" || !c?.id || c.por === "vinculo") return null;
  const nome = String(c.nome ?? "").trim() || "o cliente sugerido";
  return `Confirme o cliente: este pagador já pagou por ${nome} — responda "Sim, é do ${nome}" ou escolha outro`;
}

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

/**
 * Sem o contexto (carregarContextoSeguro falhou), a regra de cliente da ENTRADA não preenche o cliente (revisão de
 * 23/10/2026, 4ª rodada): não deu para conferir os pagadores que o dono guardou nem os que ele recusou ou pausou — e o
 * "não" dele vence a regra antiga. A linha fica sem cliente e com esta pergunta no motivo; sem a marca do motor
 * (evidência nula), a varredura diária a refaz quando o contexto voltar.
 */
export const FRASE_DA_REGRA_SEM_CONTEXTO = "De quem é este pagamento? Uma regra antiga aponta um cliente para este "
  + "CPF/CNPJ, mas não deu para conferir os pagadores que você guardou nem os que recusou — escolha o cliente";

export function identificarLinha(tx: TxDaFila, p: PropostaBase, ctx: ContextoDeIdentificacao | null): LinhaIdentificada {
  // Sem contexto (leitura falhou): o que o motor de propostas já sabia, e nada mais — menos o cliente da regra da
  // entrada, que sem conferir pagadores e vetos não decide sozinho (fica a pergunta).
  if (!ctx) {
    const regraDeCliente = p.kind === "create_receivable" && !!p.suggestedClientId;
    return {
      supplierId: p.suggestedSupplierId, payeeId: null, clientId: null, serviceOrderId: null,
      categoria: p.suggestedCategory, dreGroup: p.dreGroup, evidencia: null, vinculo: null,
      frases: regraDeCliente ? [FRASE_DA_REGRA_SEM_CONTEXTO] : [],
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
  // Com fornecedor, a linha já tem dono: nem "cadastrar", nem a pergunta "de quem é este pagamento?" (simulação de
  // 22/10/2026, P4 — hoje não há regra de entrada com fornecedor, mas a pergunta não pode sobrar se houver).
  if (supplierId) {
    ident.cadastrar = null;
    ident.deQuemE = null;
  }

  // Cliente dito por regra sua ("o Pix do CPF X é do cliente Y" — resposta 18 do dono,
  // 26/09/2026): é instrução, vence o reconhecimento automático, e continua só sugestão (a
  // receita espera o OK dele). Cliente que não existe mais não entra.
  //
  // Leva 8 (revisão de 22/10/2026): regra ANTIGA de outro cliente não vence o pagador que o dono confirmou. Se este
  // documento foi guardado como pagador de um cliente diferente do da regra, a regra não decide o cliente — a linha
  // pergunta "de quem é?", com o cliente da regra e os dos pagadores como candidatos (a categoria da regra continua).
  // Sem isto, a regra preenchia o cliente como prova "regra" (que a aprovação usa sem o SIM) e o que o dono acabou
  // de ensinar não tinha efeito nenhum. Sem pagador de OUTRO cliente (nenhum, ou só o da própria regra ainda não
  // consolidada), a regra decide como sempre.
  //
  // Revisão de 23/10/2026: o "não" do dono vence a regra antiga — se ele recusou ou pausou este documento como pagador
  // do cliente da regra, a regra não escolhe o cliente (fica o que o reconhecimento achou, que já respeita o veto). E
  // se a leitura dos pagadores falhou, não dá para saber se há pagador de outro cliente nem veto: a regra não decide
  // sozinha — a linha pergunta, com o cliente da regra como candidato ("regra antiga").
  let fraseDoConflito: string | null = null;
  let fraseDaRegraVetada: string | null = null;
  if (p.kind === "create_receivable" && p.suggestedClientId) {
    const e = ctx.indice.porId.cliente.get(p.suggestedClientId);
    const veto = e ? vetoDoPagador(ctx.indice, tx.counterparty_document, e.id) : null;
    const pagadores = e ? pagadoresDoDocumento(ctx.indice, tx.counterparty_document) : [];
    const deOutroCliente = pagadores.filter((x) => x.cliente.id !== e?.id);
    if (e && veto) {
      fraseDaRegraVetada = `Uma regra antiga diz que este CPF/CNPJ é do cliente ${e.nome}, mas você `
        + `${veto === "pausado" ? "pausou" : "recusou"} quem pagou como pagador de ${e.nome}: a regra não escolhe o cliente`;
    } else if (e && (deOutroCliente.length > 0 || ctx.pagadoresIndisponiveis)) {
      // O cliente da regra primeiro ("regra antiga", ou a relação dele se também foi guardado como pagador), depois
      // os clientes dos pagadores, e o dono do documento quando o documento é o de um cliente (cadastro feito depois).
      const comoPagador = pagadores.find((x) => x.cliente.id === e.id);
      const candidatos: CandidatoDoPagamento[] = [{ id: e.id, nome: e.nome, relacao: comoPagador?.relacao ?? "regra antiga" }];
      for (const x of pagadores) {
        if (!candidatos.some((c) => c.id === x.cliente.id)) {
          candidatos.push({ id: x.cliente.id, nome: x.cliente.nome, relacao: x.relacao });
        }
      }
      if (ident.cliente?.por === "documento" && !candidatos.some((c) => c.id === ident.cliente!.id)) {
        candidatos.push({ id: ident.cliente.id, nome: ident.cliente.nome, relacao: "documento do cliente" });
      }
      // O que a própria pergunta do reconhecimento já tinha (ex.: o cliente de nome idêntico quando a leitura dos
      // pagadores falhou) continua candidato.
      for (const x of ident.deQuemE?.candidatos ?? []) {
        if (!candidatos.some((c) => c.id === x.id)) candidatos.push(x);
      }
      ident.cliente = null;
      ident.cadastrar = null;
      ident.deQuemE = {
        documento: documentoNormalizado(tx.counterparty_document) || null,
        nome: ident.deQuemE?.nome
          ?? ((tx.counterparty_name ?? "").trim() || nomeDaDescricao(tx.description) || ident.nomeConhecido || null),
        candidatos,
      };
      const guardados = deOutroCliente.map((x) => x.cliente.nome).join(", ");
      fraseDoConflito = deOutroCliente.length > 0
        ? `De quem é este pagamento? Uma regra antiga diz que este CPF/CNPJ é do cliente ${e.nome}, `
          + `mas você guardou quem pagou como pagador de ${guardados} — escolha o cliente`
        : `De quem é este pagamento? Uma regra antiga diz que este CPF/CNPJ é do cliente ${e.nome}, `
          + `mas não deu para conferir os pagadores que você guardou agora — escolha o cliente`;
    } else if (e) {
      ident.cliente = {
        id: e.id, nome: e.nome, por: "regra",
        detalhe: `Regra sua: este CPF/CNPJ é do cliente ${e.nome}`,
      };
      ident.cadastrar = null;
      ident.outroCadastro = null;
      ident.deQuemE = null;
    }
  }

  const payeeId = ident.favorecido?.id ?? null;
  const clientId = ident.cliente?.id ?? null;
  for (const r of [ident.favorecido, ident.cliente]) if (r) frases.push(r.detalhe);
  if (fraseDoConflito) frases.push(fraseDoConflito);
  if (fraseDaRegraVetada) frases.push(fraseDaRegraVetada);
  for (const f of frasesDaIdentificacao({
    ...ident, fornecedor: null, favorecido: null, cliente: null,
    // No conflito, a frase acima já explica a pergunta (a genérica diria "paga por mais de um cliente").
    deQuemE: fraseDoConflito ? null : ident.deQuemE,
  })) frases.push(f);

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

  // Pix para o SÓCIO (o próprio dono) — 20/10/2026, spec-papelada-fix.md B2. O histórico por nome se divide
  // (Pró-labore 5 de 9) e a sugestão saía pela maioria, enquanto a última escolha dele foi Retirada de sócio
  // (28/09): a fila sugeria o que ele acabara de trocar. Agora a sugestão segue a ÚLTIMA escolha dele para
  // esse favorecido; regra sua continua vencendo. Para Pró-labore × Retirada de sócio o erro é barato: a
  // separação pelo salário mínimo (separar_pro_labore) reparte as duas mês a mês. Só sugestão: a confiança
  // é a do motor (abaixo de 90, e Retirada fica fora do resultado — nada disso vai sozinho).
  const escolha = payeeId && p.kind === "create_payable" && !p.appliedRuleId
    ? ctx.ultimaEscolhaDoSocio?.get(payeeId) : undefined;
  if (escolha && escolha.categoria !== categoria) {
    const dia = `${escolha.em.slice(8, 10)}/${escolha.em.slice(5, 7)}`;
    frases.push(`Da última vez (${dia}) você lançou Pix para ${ident.favorecido?.nome ?? "o sócio"} como ${escolha.categoria}: a sugestão segue a sua última escolha`
      + (CATEGORIAS_DA_SEPARACAO.has(escolha.categoria) && CATEGORIAS_DA_SEPARACAO.has(categoria)
        ? " (a separação pelo salário mínimo acerta o pró-labore do mês)" : ""));
    categoria = escolha.categoria;
    dreGroup = ctx.drePorCategoria.get(escolha.categoria) ?? dreGroup;
  }

  const vinculo = sugerirVinculo(
    {
      id: tx.id, transaction_date: tx.transaction_date, description: tx.description, amount: Number(tx.amount),
      transaction_type: tx.transaction_type, counterparty_name: tx.counterparty_name,
      counterparty_document: tx.counterparty_document, pix_end_to_end_id: tx.pix_end_to_end_id,
    },
    ctx.candidatos,
    ident.cliente
      ? { id: ident.cliente.id, nome: ident.cliente.nome, por: ident.cliente.por, relacao: ident.cliente.relacao ?? null }
      : null,
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

  // A marca do motor diz à varredura diária que a linha já foi feita por esta versão (index.ts reclassificar). Com a
  // leitura dos pagadores falhando, a ENTRADA sai sem ela: a varredura a refaz quando a leitura voltar — sem isto a
  // pergunta (ou um cliente sem conferir o veto) ficaria gravada como definitiva.
  const semMarca = ctx.pagadoresIndisponiveis === true && tx.transaction_type === "credit";
  const evidencia = { ...(semNulos(ident) ?? {}), ...(semMarca ? {} : { motor: MOTOR_DA_FILA }) };
  return {
    supplierId, payeeId, clientId, serviceOrderId, categoria, dreGroup,
    evidencia: Object.keys(evidencia).length > 0 ? evidencia : null, vinculo, frases,
  };
}
