// Ferramentas do agente para a caixa de entrada, as regras e os cadastros do financeiro.
//
// O PRINCÍPIO QUE ORGANIZA OS RISCOS AQUI: ensinar é barato, executar é caro.
//
// Criar uma regra ("toda transação com Mercado Livre é peça e material") não move um
// centavo: ela muda como o sistema PROPÕE dali em diante, e desfazer é pausar. Já aprovar
// uma proposta cria lançamento contábil, mexe em saldo e pode aprovar orçamento — isso é
// irreversível na prática e continua exigindo confirmação humana.
//
// Sem essa distinção, ou o agente vira inútil (pede permissão para tudo, e a fadiga faz o
// gestor aprovar no automático) ou vira perigoso (lança dinheiro sozinho). O critério é o
// mesmo que a literatura de agentes em finanças usa: reversibilidade e alcance da escrita.

import { blockTechnician, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { categoriaValida, ehErro } from "./caixa.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { regraDeFornecedorAlcanca, type FornecedorConhecido, type TransacaoOrfa } from "../../banking/proposals.ts";
import { faltaNoDestino, precisaDeDestino } from "../../banking/destino.ts";
import { entradaSemCliente } from "../../banking/entrada-sem-cliente.ts";
import {
  documentoContradiz, documentoMascarado, documentoNormalizado, perguntaDeQuemEValida, RELACOES_DO_PAGADOR,
  ROTULO_DA_EVIDENCIA, ROTULO_DA_RELACAO, situacaoDoClienteSugerido, type AnotacaoDoDono, type RelacaoDoPagador,
  type TipoDeEvidencia,
} from "../../banking/contraparte.ts";
import { mascararCpfNoTexto } from "./financeiro-comum.ts";
import { orContem } from "../filtro-or.ts";
import {
  candidatosDosClientes, DIAS_DO_PAGAMENTO_A_MAO, fraseDoParecePagar, parecePagar, type ParecePagar,
} from "../../banking/parece-pagar.ts";

/** Nome comparável: sem acento, caixa e espaços sobrando. */
function comparavel(s: string): string {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

/**
 * O centro de custo que o usuário disse — pelo nome igual (sem acento e caixa) ou pelo id, só
 * entre os ATIVOS. Nome que não bate vira pergunta com as opções, nunca escolha.
 */
async function resolverCentroDeCusto(ctx: ToolCtx, dito: string): Promise<{ id: string; nome: string } | { error: string; opcoes: string[] }> {
  const { data } = await ctx.sb.from("cost_centers").select("id, name, active").eq("active", true).order("name");
  const ativos = (data ?? []) as Array<{ id: string; name: string }>;
  const alvo = comparavel(dito);
  const achado = ativos.find((c) => c.id === dito || comparavel(c.name) === alvo);
  if (achado) return { id: achado.id, nome: achado.name };
  return { error: `Não há centro de custo ativo chamado "${dito}". Pergunte ao usuário qual destes é.`, opcoes: ativos.map((c) => c.name) };
}

/**
 * Categoria dita pelo usuário → o nome exato do plano de contas (29/09/2026, "sim" do dono: o
 * assistente troca a categoria ao aprovar, como a tela). A finance-review grava o texto que
 * receber, então o nome se resolve aqui, só entre as ativas do tipo da proposta. Categoria
 * restrita (pró-labore, retirada…) só o administrador escolhe — a mesma regra da tela e da RLS.
 */
async function resolverCategoriaDita(
  ctx: ToolCtx,
  dito: string,
  tipo: "payable" | "receivable",
): Promise<{ nome: string } | { error: string; opcoes?: string[] }> {
  const { data } = await ctx.sb
    .from("financial_categories")
    .select("name, sensitive")
    .eq("type", tipo)
    .eq("active", true)
    .order("name");
  const ativas = (data ?? []) as Array<{ name: string; sensitive: boolean | null }>;
  const alvo = comparavel(dito);
  const achada = ativas.find((c) => comparavel(c.name) === alvo);
  if (!achada) {
    return {
      error: `Não há categoria de ${tipo === "payable" ? "saída" : "entrada"} chamada "${dito}". Pergunte ao usuário qual destas é.`,
      opcoes: ativas.filter((c) => !c.sensitive || ctx.userRole === "admin").map((c) => c.name),
    };
  }
  if (achada.sensitive && ctx.userRole !== "admin") {
    return { error: `"${achada.name}" é categoria restrita: só o administrador lança nela.` };
  }
  return { nome: achada.name };
}

/**
 * Quem pode operar o financeiro pelo agente.
 *
 * NÃO usar NON_TECHNICIAN_ROLES aqui: ele inclui seller e external_seller, e a RLS destas
 * tabelas exige `is_admin_or_financial`. O vendedor veria a ferramenta na lista, o modelo
 * tentaria usá-la e receberia silêncio — SELECT sob RLS devolve vazio, não erro, então o
 * agente concluiria "não há regras cadastradas" em vez de "você não tem acesso".
 */
const CARGOS_FINANCEIRO: Role[] = ["admin", "financial"];

function bloqueiaSemAcesso(ctx: ToolCtx): { error: string } | null {
  const bloqueio = blockTechnician(ctx);
  if (bloqueio) return bloqueio;
  if (!CARGOS_FINANCEIRO.includes(ctx.userRole as Role)) {
    return { error: "Apenas administrador ou financeiro podem operar esta parte do sistema." };
  }
  return null;
}

interface EntradaDaFila {
  id: string;
  kind: string;
  bank_transaction_id: string | null;
  suggested_client_id: string | null;
  suggested_amount: number | null;
  suggested_date: string | null;
}

/**
 * "Parece pagar" (forma A, F4 — 03/10/2026): para cada entrada da fila com cliente identificado,
 * as contas em aberto / pagamentos lançados à mão dele cuja soma bate com o Pix. Mesma regra da
 * tela do Extrato (_shared/banking/parece-pagar.ts). Leitura que falha lança.
 */
async function parecePagarDasEntradas(ctx: ToolCtx, linhas: EntradaDaFila[]): Promise<Map<string, ParecePagar>> {
  const entradas = linhas.filter((l) => l.kind === "create_receivable" && l.bank_transaction_id && l.suggested_client_id && l.suggested_date);
  const out = new Map<string, ParecePagar>();
  if (entradas.length === 0) return out;
  const primeira = entradas.map((e) => String(e.suggested_date)).sort()[0];
  const d = new Date(`${primeira.slice(0, 10)}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - DIAS_DO_PAGAMENTO_A_MAO);
  const candidatos = await candidatosDosClientes(
    ctx.sb, [...new Set(entradas.map((e) => e.suggested_client_id!))], d.toISOString().slice(0, 10),
  );
  for (const e of entradas) {
    const r = parecePagar(
      { valor: Math.abs(Number(e.suggested_amount ?? 0)), data: String(e.suggested_date) },
      candidatos.get(e.suggested_client_id!) ?? [],
    );
    if (r) out.set(e.id, r);
  }
  return out;
}

const brl = (v: number) => v.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

/** O que o modelo recebe: a frase e as aplicações prontas para aplicar_pix_em_contas. */
function parecePagarParaOModelo(r: ParecePagar) {
  return {
    // A frase cita a descrição das contas — às vezes o nome do banco com o CPF dentro (LGPD, leva 8).
    frase: mascararCpfNoTexto(fraseDoParecePagar(r, brl)),
    // Soma de 2+ contas que bate = perguntar ANTES de aprovar; "parte de uma conta" é só possibilidade.
    perguntar_antes_de_aprovar: !r.parcial,
    aplicacoes: r.itens.map((i) => i.tipo === "pagamento"
      ? { pagamento_id: i.id }
      : { receivable_id: i.id, valor: i.valor, ...(i.quitar ? { quitar: true } : {}) }),
  };
}

/** Categorias ativas do plano de contas — o agente não pode inventar categoria. */
async function categoriasValidas(ctx: ToolCtx, tipo: "payable" | "receivable" = "payable") {
  const { data, error } = await ctx.sb
    .from("financial_categories")
    .select("name, dre_group")
    .eq("type", tipo).eq("active", true);
  // Lista vazia por erro faria toda categoria "não existir" — e o agente oferecer outra.
  if (error) throw new Error(`Não consegui ler o plano de contas: ${error.message}`);
  return (data ?? []) as { name: string; dre_group: string | null }[];
}

/**
 * Chama a finance-review com a autenticação que o canal permite.
 *
 * Pelo painel existe JWT do usuário. Pelo WhatsApp NÃO existe — o agente monta o contexto
 * com `jwt: ""` (ai-agent/index.ts), e mandar "Bearer " vazio devolve 401. Nesse caso a
 * chamada usa o segredo interno e informa QUEM está decidindo, para a aprovação continuar
 * tendo dono na trilha de auditoria.
 */
async function chamarFinanceReview(ctx: ToolCtx, body: Record<string, unknown>) {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/finance-review`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  let corpo = body;

  if (ctx.jwt) {
    headers.Authorization = `Bearer ${ctx.jwt}`;
  } else {
    const segredo = Deno.env.get("CRON_SECRET");
    if (!segredo) {
      return { error: "Sem credencial para executar esta ação por este canal." };
    }
    headers["x-cron-secret"] = segredo;
    corpo = { ...body, acting_user_id: ctx.userId };
  }

  const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(corpo) });
  const dados = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { error: dados?.detail || dados?.error || `finance-review respondeu ${res.status}` };
  }
  return dados;
}

/**
 * Quantas transações do extrato esta regra alcança.
 *
 * Regra que não pega nada nasce calada e assim permanece: o gestor acha que ensinou o
 * sistema, a fila continua igual, e não há erro em lugar nenhum para investigar. Foi o que
 * aconteceu com uma regra por NOME criada como "POSTO PAULINHO" enquanto o extrato escreve
 * "POSTO PAULINHO NAVEGANTES BRA" — a comparação por nome é do nome inteiro, então ela
 * nunca valeria para nada.
 *
 * `alcanca_por_trecho` existe para dar o diagnóstico junto do sintoma: quando o alvo não
 * casa como está mas apareceria como pedaço de texto, o problema é o TIPO da regra, não a
 * grafia — e a resposta pode dizer isso em vez de deixar o usuário adivinhando.
 */
/**
 * Todos os fornecedores, em páginas: o PostgREST corta em 1.000 linhas sem avisar, e um
 * .limit(5000) passaria a "não achar" fornecedor quando o cadastro crescer.
 */
async function lerFornecedores(ctx: ToolCtx): Promise<Array<{ id: string; name: string; trade_name: string | null; cnpj_cpf: string | null }>> {
  const todos: Array<{ id: string; name: string; trade_name: string | null; cnpj_cpf: string | null }> = [];
  for (let de = 0; de < 50000; de += 1000) {
    const { data, error } = await ctx.sb.from("suppliers").select("id, name, trade_name, cnpj_cpf").order("id").range(de, de + 999);
    if (error) break;
    const pagina = (data ?? []) as typeof todos;
    todos.push(...pagina);
    if (pagina.length < 1000) break;
  }
  return todos;
}

async function alcanceDaRegra(
  ctx: ToolCtx,
  tipo: string,
  valor: string,
): Promise<{ alcanca: number; alcanca_por_trecho?: number }> {
  const base = () => ctx.sb
    .from("bank_transactions")
    .select("id", { count: "exact", head: true })
    .eq("transaction_type", "debit");

  // Contagem que falha lança: "a regra não alcança nenhuma linha" com erro engolido é falso.
  const contar = (r: { count: number | null; error: { message: string } | null }) => {
    if (r.error) throw new Error(`Não consegui contar as linhas que a regra alcança: ${r.error.message}`);
    return r.count ?? 0;
  };
  const escapado = valor.replace(/[%_]/g, "");
  const trecho = contar(await base().or(orContem(["description", "counterparty_name"], escapado)));

  if (tipo === "text") return { alcanca: trecho };

  if (tipo === "counterparty") {
    const exato = contar(await base().ilike("counterparty_name", escapado));
    return { alcanca: exato, alcanca_por_trecho: trecho };
  }

  if (tipo === "document") {
    const digitos = valor.replace(/\D/g, "");
    return { alcanca: contar(await base().eq("counterparty_document", digitos)) };
  }

  // Fornecedor: conta com as MESMAS provas do motor (documento, mesmo nome, nome cortado
  // provado, mesma empresa) — decisão do dono de 26/09/2026. As candidatas vêm do banco por
  // documento ou pela primeira palavra do nome; quem decide se a regra alcança é o motor.
  // Todas as saídas passam pelo motor (são ~2 mil): um pré-filtro por palavra deixava de fora
  // o que o motor reconhece (nome com a 1ª palavra curta, fantasia diferente da razão social).
  const fornecedores = (await lerFornecedores(ctx)) as FornecedorConhecido[];
  if (!fornecedores.some((x) => x.id === valor)) return { alcanca: 0 };
  let alcanca = 0;
  for (let de = 0; de < 20000; de += 1000) {
    const { data: pagina, error } = await ctx.sb.from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, source_type")
      .eq("transaction_type", "debit").order("id").range(de, de + 999);
    if (error) break;
    const linhas = (pagina ?? []) as TransacaoOrfa[];
    alcanca += linhas.filter((tx) => regraDeFornecedorAlcanca({ ...tx, amount: Number(tx.amount) }, valor, fornecedores)).length;
    if (linhas.length < 1000) break;
  }
  return { alcanca };
}

/**
 * O fornecedor que o usuário disse, pelo nome IGUAL ao do cadastro (razão social ou fantasia,
 * sem acento, caixa e sufixo societário) ou pelo id. Um só parecido NÃO é aceito calado:
 * vira pergunta com o nome por extenso ("é FERNANDO NUNES FACHINI EPP?") — decisão do dono de
 * 26/09/2026: nome diferente só por escolha dele.
 */
type FornecedorDaLista = { id: string; name: string; trade_name: string | null; cnpj_cpf: string | null };

/** A mesma forma comparável do motor: sem parênteses, acento, caixa, pontuação e sufixo. */
function limpaNome(s: string): string {
  return String(s ?? "").replace(/\([^)]*\)/g, " ").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase()
    .replace(/[^A-Z0-9 ]/g, " ").replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, " ").replace(/\s+/g, " ").trim();
}

/** A empresa do cadastro: raiz do CNPJ (matriz e filiais), ou o próprio cadastro sem CNPJ. */
function empresaDoCadastro(f: FornecedorDaLista): string {
  let d = String(f.cnpj_cpf ?? "").replace(/\D/g, "");
  if (d.length === 13) d = d.padStart(14, "0");
  return d.length === 14 ? `raiz:${d.slice(0, 8)}` : `id:${f.id}`;
}

/** Entre cadastros da mesma empresa, sempre o mesmo: o de menor CNPJ (a matriz), como no motor. */
function representanteDa(lista: FornecedorDaLista[]): FornecedorDaLista {
  return [...lista].sort((a, b) => String(a.cnpj_cpf ?? "").replace(/\D/g, "").padStart(14, "0")
    .localeCompare(String(b.cnpj_cpf ?? "").replace(/\D/g, "").padStart(14, "0")) || a.id.localeCompare(b.id))[0];
}

/**
 * O fornecedor que o usuário disse, pelo nome IGUAL ao do cadastro (razão social ou fantasia,
 * sem acento, caixa, sufixo societário e parênteses) ou pelo id. Um só parecido NÃO é aceito
 * calado: vira pergunta com o nome por extenso — decisão do dono de 26/09/2026: nome
 * diferente só por escolha dele.
 *
 * Compara em memória (são ~530 cadastros): o ilike do banco diferencia acento, e a
 * transcrição do áudio sempre acentua — "Kamell Comércio Global" não achava nada. Cadastros
 * da mesma empresa (matriz e filial) contam como um só, o mesmo que o motor escolhe.
 */
export async function resolverFornecedorDito(
  ctx: ToolCtx,
  dito: string,
): Promise<{ id: string; nome: string } | { error: string; opcoes?: Array<{ id: string; nome: string; cnpj_cpf: string | null }>; dica?: string }> {
  const d = String(dito ?? "").trim();
  if (/^[0-9a-f-]{36}$/i.test(d)) {
    const { data } = await ctx.sb.from("suppliers").select("id, name").eq("id", d).maybeSingle();
    return data ? { id: (data as any).id, nome: (data as any).name } : { error: "Fornecedor não encontrado." };
  }
  const alvo = limpaNome(d);
  if (!alvo) return { error: "Qual fornecedor?" };
  const todos = (await lerFornecedores(ctx)) as FornecedorDaLista[];
  const opcao = (f: FornecedorDaLista) => ({ id: f.id, nome: f.name, cnpj_cpf: f.cnpj_cpf ?? null });

  const iguais = todos.filter((f) => limpaNome(f.name) === alvo || (!!f.trade_name && limpaNome(f.trade_name) === alvo));
  const empresas = new Map<string, FornecedorDaLista[]>();
  for (const f of iguais) empresas.set(empresaDoCadastro(f), [...(empresas.get(empresaDoCadastro(f)) ?? []), f]);
  if (empresas.size === 1) {
    const r = representanteDa([...empresas.values()][0]);
    return { id: r.id, nome: r.name };
  }
  if (empresas.size > 1) {
    return {
      error: `"${d}" é o nome de mais de uma empresa cadastrada. Pergunte ao usuário qual é e repita com o id da opção escolhida.`,
      opcoes: [...empresas.values()].map((l) => opcao(representanteDa(l))),
    };
  }
  // Nenhum igual: os que CONTÊM o nome dito viram pergunta, nunca escolha.
  const parecidos = todos.filter((f) => limpaNome(f.name).includes(alvo) || (!!f.trade_name && limpaNome(f.trade_name).includes(alvo)));
  if (parecidos.length > 0) {
    return {
      error: parecidos.length === 1
        ? `O cadastro parecido é "${parecidos[0].name}". Pergunte ao usuário se é este; se for, repita com o id dele.`
        : `"${d}" não é o nome exato de um fornecedor. Pergunte ao usuário qual é e repita com o id da opção escolhida.`,
      opcoes: parecidos.slice(0, 8).map(opcao),
    };
  }
  return {
    error: `Nenhum fornecedor cadastrado com "${d}".`,
    dica: "Confira o nome, ou crie a regra por 'texto' usando um trecho do histórico do extrato.",
  };
}

/**
 * O cliente que o usuário disse: pelo nome IGUAL ao do cadastro (sem acento, caixa, sufixo e
 * parênteses) ou pelo id. Parecido não é aceito calado — vira pergunta com as opções, como no
 * fornecedor (decisão do dono de 26/09/2026: nome diferente só por escolha dele).
 */
export async function resolverClienteDito(
  ctx: ToolCtx,
  dito: string,
): Promise<{ id: string; nome: string } | { error: string; opcoes?: Array<{ id: string; nome: string; cpf_cnpj: string | null }> }> {
  const d = String(dito ?? "").trim();
  if (!d) return { error: "De qual cliente é o dinheiro? Pergunte ao usuário." };
  if (/^[0-9a-f-]{36}$/i.test(d)) {
    const { data } = await ctx.sb.from("clients").select("id, name").eq("id", d).maybeSingle();
    return data ? { id: (data as any).id, nome: (data as any).name } : { error: "Cliente não encontrado." };
  }
  const todos: Array<{ id: string; name: string; cpf_cnpj: string | null }> = [];
  for (let de = 0; de < 50000; de += 1000) {
    const { data, error } = await ctx.sb.from("clients").select("id, name, cpf_cnpj").order("id").range(de, de + 999);
    if (error) break;
    const pagina = (data ?? []) as typeof todos;
    todos.push(...pagina);
    if (pagina.length < 1000) break;
  }
  const alvo = limpaNome(d);
  const opcao = (c: (typeof todos)[number]) => ({ id: c.id, nome: c.name, cpf_cnpj: c.cpf_cnpj ?? null });
  const iguais = todos.filter((c) => limpaNome(c.name) === alvo);
  if (iguais.length === 1) return { id: iguais[0].id, nome: iguais[0].name };
  if (iguais.length > 1) {
    return { error: `Há ${iguais.length} clientes com o nome "${d}". Pergunte ao usuário qual é (pelo CPF/CNPJ) e repita com o id.`, opcoes: iguais.map(opcao) };
  }
  const parecidos = alvo ? todos.filter((c) => limpaNome(c.name).includes(alvo)) : [];
  if (parecidos.length > 0) {
    return {
      error: parecidos.length === 1
        ? `O cadastro parecido é "${parecidos[0].name}". Pergunte ao usuário se é este; se for, repita com o id dele.`
        : `"${d}" não é o nome exato de um cliente. Pergunte ao usuário qual é e repita com o id da opção escolhida.`,
      opcoes: parecidos.slice(0, 8).map(opcao),
    };
  }
  return { error: `Nenhum cliente cadastrado com "${d}". Confira o nome ou cadastre o cliente antes.` };
}

// ── QUEM PAGA POR UM CLIENTE (leva 8, 22/10/2026, "siga pelo recomendado") ──────────────────────────
// A entrada paga por um terceiro (cônjuge, empresa do cliente, parente, marina, seguradora) nunca mais vira
// "cadastrar cliente" com os dados de quem pagou: o assistente PERGUNTA de quem é. Quem costuma pagar por um cliente
// fica guardado em pagadores_do_cliente (RPC guardar_pagadores_do_cliente) e volta como SUGESTÃO que pede o SIM —
// nunca baixa sozinha. O documento e o nome de quem pagou saem da linha do banco ("IA pensa, sistema preenche"); o
// CPF de terceiro só aparece mascarado (LGPD).

const ehUuid = (s: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(s ?? "").trim());

/** "2026-10-12" → "12/10/2026". */
const dataBr = (d: unknown) => String(d ?? "").slice(0, 10).split("-").reverse().join("/");

/** O pedido de guardar_pagador_do_cliente conferido sem banco — o preValidar, o resumo e o execute leem igual. */
export interface PedidoDoPagador {
  clientId: string;
  propostaId: string | null;
  bankTransactionId: string | null;
  relacao: RelacaoDoPagador;
  observacao: string | null;
}

export function lerPedidoDoPagador(args: Record<string, unknown> | null | undefined): PedidoDoPagador | { error: string } {
  const a = args ?? {};
  const clientId = String(a.client_id ?? "").trim();
  if (!ehUuid(clientId)) return { error: "Informe o client_id do cliente (o id do cadastro, não o nome)." };
  const relacao = String(a.relacao ?? "").trim() as RelacaoDoPagador;
  if (!RELACOES_DO_PAGADOR.includes(relacao)) {
    return {
      error: "Pergunte ao usuário quem o pagador é para o cliente: "
        + `${RELACOES_DO_PAGADOR.map((r) => ROTULO_DA_RELACAO[r].toLowerCase()).join(", ")}.`,
    };
  }
  const propostaId = String(a.proposta_id ?? "").trim() || null;
  const bankTransactionId = String(a.bank_transaction_id ?? "").trim() || null;
  if (!propostaId && !bankTransactionId) {
    return { error: "Informe a entrada do extrato que essa pessoa pagou: proposta_id (da fila) ou bank_transaction_id." };
  }
  if ((propostaId && !ehUuid(propostaId)) || (bankTransactionId && !ehUuid(bankTransactionId))) {
    return { error: "proposta_id e bank_transaction_id são ids (uuid) da fila ou do extrato, não números nem nomes." };
  }
  const observacao = String(a.observacao ?? "").replace(/\s+/g, " ").trim().slice(0, 500) || null;
  return { clientId, propostaId, bankTransactionId, relacao, observacao };
}

/**
 * A linha do banco do pedido: a da proposta (só de ENTRADA) ou a informada. Leitura que falha devolve o erro — nunca
 * "nenhuma linha".
 */
// deno-lint-ignore no-explicit-any
async function linhaDoPedido(db: any, p: PedidoDoPagador): Promise<{ id: string } | { error: string }> {
  if (!p.propostaId) return { id: p.bankTransactionId! };
  const { data, error } = await db.from("finance_review_queue")
    .select("id, kind, bank_transaction_id").eq("id", p.propostaId).maybeSingle();
  if (error) return { error: `Não consegui ler a proposta: ${error.message}` };
  if (!data) return { error: "Proposta não encontrada na fila do Extrato." };
  if (data.kind !== "create_receivable") return { error: "Só uma ENTRADA do banco mostra quem pagou por um cliente." };
  if (!data.bank_transaction_id) return { error: "Esta proposta não tem linha do banco." };
  if (p.bankTransactionId && p.bankTransactionId !== String(data.bank_transaction_id)) {
    return { error: "A proposta e a linha do extrato informadas não são a mesma entrada: mande só uma." };
  }
  return { id: String(data.bank_transaction_id) };
}

/**
 * O que o dono lê antes do "sim" de guardar_pagador_do_cliente (no WhatsApp é texto, sem botão): quem pagou (nome do
 * extrato e CPF mascarado), o pagamento, o cliente, a relação e o que acontece depois. O que não serve vira UMA linha
 * "⚠️" — recusa, não pendência (resumos-do-financeiro.ts). As outras travas (CNPJ da HBR, documento de outro cliente,
 * linha que não paga conta do cliente nem espera na fila) a função do banco confere ao gravar.
 *
 * `quem` é quem PEDE: admin grava confirmado; os outros, proposto. Se um administrador aprovar a pendência de outra
 * pessoa, a gravação é dele — e fica confirmado (o SIM é dele); o texto diz isso.
 */
export async function resumirGuardarPagador(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: Record<string, unknown>,
  quem: { userRole?: string } = {},
): Promise<string> {
  const p = lerPedidoDoPagador(args);
  if ("error" in p) return `⚠️ ${p.error}`;
  try {
    const linha = await linhaDoPedido(admin, p);
    if ("error" in linha) return `⚠️ ${linha.error}`;
    const [tx, cli] = await Promise.all([
      admin.from("bank_transactions")
        .select("transaction_date, amount, transaction_type, counterparty_name, counterparty_document, description")
        .eq("id", linha.id).maybeSingle(),
      admin.from("clients").select("name, cpf_cnpj, active").eq("id", p.clientId).maybeSingle(),
    ]);
    if (tx.error) throw tx.error;
    if (cli.error) throw cli.error;
    if (!tx.data) return "⚠️ Linha do extrato não encontrada.";
    if (tx.data.transaction_type !== "credit") return "⚠️ Só uma entrada do banco mostra quem pagou por um cliente.";
    const doc = documentoNormalizado(tx.data.counterparty_document);
    if (doc.length !== 11 && doc.length !== 14) {
      return "⚠️ O banco não informou o CPF/CNPJ de quem pagou nesta linha: não há o que guardar.";
    }
    if (!cli.data) return "⚠️ Cliente não encontrado.";
    const cliente = String(cli.data.name ?? "").trim() || "o cliente";
    if (cli.data.active === false) return `⚠️ O cliente ${cliente} está inativo: reative o cadastro antes.`;
    if (documentoNormalizado(cli.data.cpf_cnpj).length >= 11 && !documentoContradiz(doc, cli.data.cpf_cnpj)) {
      return `⚠️ Quem pagou é o próprio cliente ${cliente} (mesmo documento): não precisa guardar.`;
    }
    const tipo = doc.length === 14 ? "CNPJ" : "CPF";
    // O nome que o banco escreve às vezes traz o CPF ("12345678901-MARIA…"): sai mascarado, como o documento.
    const nome = mascararCpfNoTexto(String(tx.data.counterparty_name ?? "").trim() || String(tx.data.description ?? "").trim())
      || "sem nome no extrato";
    return [
      "Guardar quem paga por um cliente",
      `Quem pagou: *${nome}* (${tipo} ${documentoMascarado(doc)})`,
      `Pagamento: ${dataBr(tx.data.transaction_date)} · ${brl(Math.abs(Number(tx.data.amount) || 0))}`,
      `Cliente: *${cliente}*`,
      `Relação: ${ROTULO_DA_RELACAO[p.relacao]}`,
      ...(p.observacao ? [`Observação: ${p.observacao}`] : []),
      quem.userRole === "admin"
        ? `Depois do sim: fica *confirmado*. Os próximos Pix deste ${tipo} vão SUGERIR ${cliente}, sempre pedindo a sua confirmação; nunca dão baixa sozinhos.`
        : "Depois do sim: fica *proposto*. Só passa a valer com o SIM do administrador (na ficha do cliente, ou aprovando ele mesmo esta ação).",
    ].join("\n");
  } catch (e) {
    const motivo = String((e as { message?: string })?.message ?? e).replace(/\s*\n+\s*/g, " ");
    return `⚠️ Não consegui conferir a linha do extrato agora (${motivo}). Nada foi registrado; tente de novo.`;
  }
}

/**
 * A pergunta "de quem é este pagamento?" de uma ENTRADA da fila, para o modelo: o nome do extrato (com o CPF que o
 * banco escreve nele MASCARADO), o documento MASCARADO (CPF de terceiro é dado pessoal) e os clientes para quem esse
 * documento já foi guardado como pagador (dois ou mais: marina, seguradora). Linha antiga da fila (motor 2) traz
 * `cadastrar` de cliente no lugar: vira a mesma pergunta, sem candidatos — nunca a proposta de cadastrar cliente com os
 * dados de quem pagou. A pergunta que SOBROU depois de a linha ganhar cliente (anotação do dono, "É cliente novo") não
 * vai (perguntaDeQuemEValida, revisão de 23/10/2026).
 */
// deno-lint-ignore no-explicit-any
function deQuemEDaEntrada(p: any) {
  const q = perguntaDeQuemEValida(p);
  if (!q) return null;
  const candidatos = q.candidatos.map((c) => ({
    client_id: c.id, nome: c.nome, relacao: ROTULO_DA_RELACAO[c.relacao as RelacaoDoPagador] ?? c.relacao ?? null,
  }));
  return { nome: mascararCpfNoTexto(q.nome ?? null), documento: documentoMascarado(q.documento), candidatos };
}

/**
 * O que as anotações do dono aplicadas às ENTRADAS disseram do cliente (cliente_id, os_id), pelo id que cada linha
 * aponta — só das que precisam: anotação sem OS na evidência (com OS, a evidência já basta) numa linha cujo sugerido,
 * sem a anotação, não valeria sozinho (situacaoDoClienteSugerido: prova deste cliente que pede o SIM, ou sugerido que
 * não é o da prova). A anotação que disse o cliente É o SIM (revisão de 23/10/2026). Como o servidor ao aprovar
 * (anotacaoDaLinha), o que se pediu e não voltou como aplicada vale null (cancelada, trocada), e a leitura que falha
 * também (4ª rodada): o cliente da prova continua pedindo o SIM, e o sugerido que não é o da prova fica por escolher —
 * nunca "a marca da evidência basta".
 */
// deno-lint-ignore no-explicit-any
async function anotacoesDasEntradas(cliente: any, linhas: any[]): Promise<Map<string, AnotacaoDoDono | null>> {
  const ids = [...new Set(linhas
    .filter((p) => {
      if (p.kind !== "create_receivable" || !p.evidencia?.anotacao?.id || p.evidencia.anotacao.os_id) return false;
      const semAnotacao = situacaoDoClienteSugerido(p.suggested_client_id, p.evidencia?.cliente, null);
      return semAnotacao === "pede_sim" || semAnotacao === "escolher";
    })
    .map((p) => String(p.evidencia.anotacao.id)))];
  const m = new Map<string, AnotacaoDoDono | null>(ids.map((id) => [id, null]));
  if (!ids.length) return m;
  try {
    const { data, error } = await cliente.from("anotacoes_do_extrato")
      .select("id, cliente_id, os_id").in("id", ids).eq("status", "aplicada");
    if (error) return m;
    for (const a of (data ?? []) as Array<{ id: string; cliente_id: string | null; os_id: string | null }>) {
      m.set(String(a.id), { cliente_id: a.cliente_id ?? null, os_id: a.os_id ?? null });
    }
  } catch { /* leitura que falha: nada da anotação vale (null) */ }
  return m;
}

/** O "quem" de uma ENTRADA na situação "escolher": nenhum cliente — nem o sugerido, nem a prova antiga de outro. */
export const QUEM_FALTA_ESCOLHER = "falta escolher o cliente: a sugestão da fila não veio da prova do motor nem de uma "
  + "anotação do dono em vigor (desfeita, ou não deu para conferi-la agora)";

/**
 * Numa ENTRADA, o cadastro a partir do extrato só cria CLIENTE, e só com o usuário dizendo que quem pagou é o próprio
 * cliente, novo (tipo='cliente'). Sem isso, a pergunta "de quem é?". null = pode seguir.
 */
export function recusaDeCadastroNaEntrada(kind: unknown, tipo: unknown): { error: string } | null {
  if (kind !== "create_receivable" || tipo === "cliente") return null;
  return {
    error: "Numa entrada, não cadastre ninguém com os dados de quem pagou: quase sempre é o cônjuge, a empresa do cliente ou a "
      + "marina. Pergunte ao usuário de quem é este pagamento. Se quem pagou costuma pagar por um cliente, use "
      + "guardar_pagador_do_cliente; só se ele disser que quem pagou é o próprio cliente, NOVO, repita com tipo='cliente'.",
  };
}

/**
 * Antes da pendência de cadastrar_contraparte_do_extrato: a entrada sem o "é cliente novo" dito vira recusa (uma linha
 * "⚠️"), não um "sim" que a execução recusaria depois. null = segue o resumo de sempre (a execução confere de novo).
 */
// deno-lint-ignore no-explicit-any
export async function resumirCadastroDoExtrato(admin: any, args: Record<string, unknown>): Promise<string | null> {
  const { data, error } = await admin.from("finance_review_queue").select("kind").eq("id", String(args?.proposta_id ?? "")).maybeSingle();
  if (error || !data) return null;
  const recusa = recusaDeCadastroNaEntrada(data.kind, args?.tipo);
  return recusa ? `⚠️ ${recusa.error}` : null;
}

/** Os ids de `cliente_confirmado` (aprovar_propostas_de_lancamento), sem repetição. */
function idsDoClienteConfirmado(args: Record<string, unknown>): string[] {
  const v = args?.cliente_confirmado;
  return [...new Set((Array.isArray(v) ? v : []).map((x) => String(x ?? "").trim()).filter(Boolean))];
}

/**
 * O retrato de aprovar_propostas_de_lancamento quando a leitura da fila falhou ao nascer a pendência: a execução recusa
 * (o modelo não forja: o agente apaga o `_retrato` que vem nos argumentos e grava só o que retratoDaPendencia devolve).
 */
export const RETRATO_QUE_FALHOU = Object.freeze({ leitura_falhou: true as const });

/** Texto numa linha só: a recusa "⚠️" só é recusa sem quebra de linha (agent.ts, resumoQueRecusa). */
const umaLinha = (s: unknown) => String(s ?? "").replace(/\s+/g, " ").trim();

/**
 * O título da proposta como vai ao modelo e ao cartão: nasce do nome que o banco escreve, que às vezes traz o CPF de
 * quem pagou ("Receita: 12345678901-MARIA…") — sai mascarado (LGPD, leva 8).
 */
const tituloMascarado = (t: string | null | undefined) => mascararCpfNoTexto(t ?? null);

/**
 * O cartão do "sim" de aprovar_propostas_de_lancamento quando há `cliente_confirmado` (leva 8, revisão de 23/10/2026):
 * o "Sim, é do X" é sobre o cliente RESOLVIDO — título, data, valor e "cliente: <nome> (<motivo>)" por entrada
 * confirmada —, nunca sobre uuid. O cliente é o SUGERIDO pela fila agora (o mesmo que a execução aplica e o retrato
 * guarda), com o nome lido do cadastro; o motivo é o detalhe da evidência (pagador conhecido, histórico, vínculo).
 *
 * Id confirmado sem sugestão (não é entrada, não tem cliente sugerido, não está na fila), cliente que não está mais no
 * cadastro ou leitura que falha: UMA linha "⚠️" — recusa, não pendência. Nunca lança: o resumo genérico mostraria uuid
 * e pediria um "sim" às cegas. Sem cliente_confirmado → null (o resumo de sempre).
 *
 * Como na execução, vale o confirmado das propostas que estão em `ids`; o resto é ignorado.
 */
// deno-lint-ignore no-explicit-any
export async function resumirClienteConfirmado(admin: any, args: Record<string, unknown>): Promise<string | null> {
  const pedidos = idsDoClienteConfirmado(args);
  if (!pedidos.length) return null;
  const ids = [...new Set((Array.isArray(args?.ids) ? args.ids : []).map((x) => String(x ?? "").trim()).filter(Boolean))];
  if (!ids.length) return "⚠️ Diga quais propostas aprovar (ids): o cliente confirmado vale só para as que são aprovadas. Nada foi registrado.";
  const confirmados = pedidos.filter((id) => ids.includes(id));
  try {
    const { data, error } = await admin.from("finance_review_queue")
      .select("id, kind, title, suggested_amount, suggested_date, suggested_client_id, evidencia").in("id", ids);
    if (error) throw new Error(error.message);
    type Lida = {
      id: string; kind: string; title: string | null; suggested_amount: number | null; suggested_date: string | null;
      suggested_client_id: string | null;
      evidencia: { cliente?: { id?: string; por?: string; detalhe?: string }; anotacao?: { id?: string } | null } | null;
    };
    const porId = new Map(((data ?? []) as Lida[]).map((f) => [String(f.id), f]));
    const titulo = (id: string) => umaLinha(tituloMascarado(porId.get(id)?.title)) || "proposta que não está na fila";
    const semSugestao = confirmados.filter((id) => {
      const f = porId.get(id);
      return !f || f.kind !== "create_receivable" || !f.suggested_client_id;
    });
    if (semSugestao.length) {
      return `⚠️ Não há cliente sugerido para confirmar em: ${semSugestao.map(titulo).join("; ")}. Pergunte ao usuário de quem é o `
        + "pagamento (se quem pagou costuma pagar por aquele cliente, guardar_pagador_do_cliente; senão, o cliente se escolhe na tela "
        + "do Extrato). Nada foi registrado.";
    }
    const idsDosClientes = [...new Set(confirmados.map((id) => String(porId.get(id)!.suggested_client_id)))];
    const nomes = new Map<string, string>();
    if (idsDosClientes.length) {
      const { data: clis, error: eCli } = await admin.from("clients").select("id, name").in("id", idsDosClientes);
      if (eCli) throw new Error(eCli.message);
      for (const c of (clis ?? []) as Array<{ id: string; name: string | null }>) nomes.set(String(c.id), umaLinha(c.name));
    }
    const semCadastro = confirmados.filter((id) => !nomes.get(String(porId.get(id)!.suggested_client_id)));
    if (semCadastro.length) {
      return `⚠️ O cliente sugerido de ${semCadastro.map(titulo).join("; ")} não está mais no cadastro: liste as propostas de novo e `
        + "pergunte de quem é o pagamento. Nada foi registrado.";
    }
    const linhas = ids.map((id) => {
      const f = porId.get(id);
      if (!f) return `- Proposta que não está mais na fila (${id.slice(0, 8)})`;
      const partes = [umaLinha(tituloMascarado(f.title)) || "Proposta", ...(f.suggested_date ? [dataBr(f.suggested_date)] : []),
        brl(Math.abs(Number(f.suggested_amount) || 0))];
      if (!confirmados.includes(id)) return `- ${partes.join(" · ")}`;
      const clienteId = String(f.suggested_client_id);
      const ev = f.evidencia?.cliente;
      // O motivo é o da evidência DESTE cliente; se a evidência fala de outro, não serve de motivo — e, com anotação, o
      // cliente sugerido é o que o dono anotou (o _aplicar_anotacao troca o sugerido e mantém a prova antiga). Sem a
      // anotação (desfeita), ninguém disse que é dele (situacaoDoClienteSugerido "escolher"): o cartão diz isso, para o
      // "sim" ser a escolha do dono, não a confirmação de uma sugestão.
      const motivo = ev && (!ev.id || String(ev.id) === clienteId)
        ? umaLinha(mascararCpfNoTexto(ev.detalhe)) || ROTULO_DA_EVIDENCIA[ev.por as TipoDeEvidencia] || "sugestão da fila"
        : f.evidencia?.anotacao?.id ? "você anotou" : "ninguém disse que é dele: confirme só se for";
      return `- ${partes.join(" · ")} — cliente: *${nomes.get(clienteId)}* (${motivo})`;
    });
    return [`Aprovar ${ids.length === 1 ? "1 proposta" : `${ids.length} propostas`} de lançamento:`, ...linhas].join("\n");
  } catch (e) {
    const motivo = umaLinha((e as { message?: string })?.message ?? e);
    return `⚠️ Não consegui conferir o cliente das entradas agora (${motivo}). Nada foi registrado; tente de novo.`;
  }
}

/**
 * O documento de uma regra por CPF/CNPJ (leva 8, revisão de 23/10/2026). A lista do extrato mostra o CPF MASCARADO
 * (***.456.789-**), que não identifica ninguém: com bank_transaction_id, o documento é o da LINHA do banco, lido pelo id
 * — nunca o texto que o modelo viu. Sem a linha, vale o que o usuário ditou, como sempre; mascarado é recusado (a regra
 * com "***" não alcançaria nada). Leitura que falha é erro, nunca "sem documento".
 */
// Mensagens únicas para o CPF mascarado (leva 8, LGPD): as mesmas antes do cartão (preValidar) e na execução.
const MSG_CPF_MASCARADO = "Este CPF está mascarado (***): passe o id da linha do extrato em bank_transaction_id (o documento é "
  + "lido do banco) ou o documento que o usuário disser.";
const MSG_LINHA_INVALIDA = "bank_transaction_id é o id (uuid) da linha do extrato, de listar_transacoes_pendentes.";
const MSG_TAMANHO_DO_DOCUMENTO = "CPF/CNPJ com tamanho errado: o CPF tem 11 dígitos e o CNPJ, 14.";

/**
 * Checagem síncrona ANTES do cartão de confirmação (o dono não aprova algo que a execução recusaria): documento
 * mascarado sem a linha do extrato, id de linha inválido ou documento com tamanho errado. Sem nada dito, passa.
 */
function preValidarDocumento(dito: unknown, linha: unknown): { error: string } | null {
  const l = String(linha ?? "").trim();
  if (l) return ehUuid(l) ? null : { error: MSG_LINHA_INVALIDA };
  const d = String(dito ?? "").trim();
  if (!d) return null;
  if (d.includes("*")) return { error: MSG_CPF_MASCARADO };
  const n = documentoNormalizado(d);
  return n.length === 11 || n.length === 14 ? null : { error: MSG_TAMANHO_DO_DOCUMENTO };
}

async function documentoDaRegra(args: Record<string, unknown>, ctx: ToolCtx): Promise<{ documento: string } | { error: string }> {
  const dito = String(args.valor_de_busca ?? "").trim();
  const linhaId = String(args.bank_transaction_id ?? "").trim();
  if (!linhaId) {
    if (dito.includes("*")) return { error: MSG_CPF_MASCARADO };
    return { documento: dito };
  }
  if (!ehUuid(linhaId)) return { error: MSG_LINHA_INVALIDA };
  const { data, error } = await ctx.sb.from("bank_transactions")
    .select("counterparty_document, transaction_type").eq("id", linhaId).maybeSingle();
  if (error) return { error: `Não consegui ler a linha do extrato: ${error.message}` };
  if (!data) return { error: "Linha do extrato não encontrada." };
  const doc = documentoNormalizado(data.counterparty_document);
  if (doc.length !== 11 && doc.length !== 14) {
    return {
      error: "O banco não informou o CPF/CNPJ nesta linha: não há documento para a regra. Use reconhecer_por='texto' com um "
        + "trecho do histórico.",
    };
  }
  const daLinha = data.transaction_type === "credit" ? "entrada" : "saida";
  if ((args.sentido === "entrada" ? "entrada" : "saida") !== daLinha) {
    return {
      error: `Esta linha do extrato é uma ${daLinha === "entrada" ? "ENTRADA" : "SAÍDA"}: confira com o usuário e repita com `
        + `sentido='${daLinha}'.`,
    };
  }
  const ditoInteiro = dito.includes("*") ? "" : documentoNormalizado(dito);
  if ((ditoInteiro.length === 11 || ditoInteiro.length === 14) && ditoInteiro !== doc) {
    return { error: "O documento dito não é o desta linha do extrato: confira com o usuário qual vale." };
  }
  return { documento: doc };
}

/**
 * O documento do favorecido: o dito (11/14 dígitos, nunca mascarado) ou, com bank_transaction_id, o da LINHA do banco —
 * leitura que falha é erro, linha sem documento é recusa e o dito que diverge da linha também. Nada dito = sem documento.
 */
async function documentoDoFavorecido(args: Record<string, unknown>, ctx: ToolCtx): Promise<{ documento: string | null } | { error: string }> {
  const pre = preValidarDocumento(args.documento, args.bank_transaction_id);
  if (pre) return pre;
  const dito = String(args.documento ?? "").trim();
  const ditoInteiro = dito.includes("*") ? "" : documentoNormalizado(dito);
  const linhaId = String(args.bank_transaction_id ?? "").trim();
  if (!linhaId) return { documento: ditoInteiro || null };
  const { data, error } = await ctx.sb.from("bank_transactions").select("counterparty_document").eq("id", linhaId).maybeSingle();
  if (error) return { error: `Não consegui ler a linha do extrato: ${error.message}` };
  if (!data) return { error: "Linha do extrato não encontrada." };
  const daLinha = documentoNormalizado(data.counterparty_document);
  if (daLinha.length !== 11 && daLinha.length !== 14) {
    return { error: "O banco não informou o CPF/CNPJ nesta linha: cadastre sem documento ou com o que o usuário disser." };
  }
  if ((ditoInteiro.length === 11 || ditoInteiro.length === 14) && ditoInteiro !== daLinha) {
    return { error: "O documento dito não é o desta linha do extrato: confira com o usuário qual vale." };
  }
  return { documento: daLinha };
}

/**
 * Regra de ENTRADA sem cliente: "o Pix do CPF do sócio é aporte" (28/09/2026). Só pelo documento (nome não
 * identifica ninguém), só sugere (a entrada espera o OK do dono) e, se já houver uma para o mesmo documento, só troca
 * com o usuário dizendo que é para trocar.
 *
 * Leva 8 (22/10/2026, decisão do dono): "o Pix do CPF X é do cliente Y" deixou de ser regra (resposta 18, 26/09/2026).
 * Quem paga por um cliente é PAGADOR CONHECIDO: nasce de uma linha do banco que ele pagou, com o SIM do dono, e só
 * sugere o cliente (guardar_pagador_do_cliente). Uma fonte só para o mesmo vínculo — a regra antiga de cliente é
 * consolidada quando o dono confirma o pagador.
 */
async function criarRegraDeEntrada(args: Record<string, unknown>, ctx: ToolCtx) {
  if (String(args.cliente ?? "").trim()) return RECUSA_REGRA_DE_CLIENTE;
  if (String(args.reconhecer_por ?? "") !== "documento") {
    return { error: "Regra de entrada reconhece só pelo CPF/CNPJ de quem paga: use reconhecer_por='documento'. Nome não identifica ninguém." };
  }
  const doc = String(args.valor_de_busca ?? "").replace(/\D/g, "");
  if (doc.length !== 11 && doc.length !== 14) {
    return { error: "CPF tem 11 dígitos e CNPJ, 14. Confira o documento com o usuário." };
  }
  if (args.lancar_sozinha) {
    return { error: "Regra de entrada só sugere: a receita sempre espera o OK do usuário. Repita sem lancar_sozinha." };
  }
  const cats = await categoriasValidas(ctx, "receivable");
  const cat = cats.find((c) => c.name.toLowerCase() === String(args.categoria ?? "").toLowerCase());
  if (!cat) {
    return { error: `A categoria de receita "${args.categoria}" não existe.`, categorias_disponiveis: cats.map((c) => c.name) };
  }
  // "O Pix do CPF do sócio é aporte": transferência e aporte não têm cliente (28/09/2026). Receita de cliente não se
  // ensina por regra desde a leva 8: o cliente vem do documento dele ou do pagador conhecido (guardado com o SIM).
  if (!entradaSemCliente(cat.name)) return RECUSA_REGRA_DE_CLIENTE;

  const campos = {
    set_category: cat.name, set_dre_group: cat.dre_group, set_client_id: null, set_supplier_id: null,
    autonomy: "suggest", min_amount: (args.valor_minimo as number | undefined) ?? null,
    max_amount: (args.valor_maximo as number | undefined) ?? null, status: "active",
  };
  const { data: existentes } = await ctx.sb.from("finance_rules")
    .select("id, set_client_id, set_category, status")
    .eq("match_type", "document").eq("direction", "credit").eq("match_value", doc).in("status", ["active", "proposed"]);
  const ja = ((existentes ?? []) as any[])[0];
  let regraId: string;
  if (ja) {
    if (!ja.set_client_id && ja.set_category === cat.name) {
      return { ok: true, ja_existia: true, categoria: cat.name, documento: documentoMascarado(doc) };
    }
    if (!args.substituir_regra_existente) {
      return {
        error: "Já existe regra de entrada para este CPF/CNPJ, com outro cliente ou categoria. Pergunte ao usuário se é para TROCAR; "
          + "se for, repita com substituir_regra_existente=true.",
      };
    }
    const { error } = await ctx.sb.from("finance_rules").update(campos).eq("id", ja.id);
    if (error) return { error: `Não consegui trocar a regra: ${error.message}` };
    regraId = ja.id;
  } else {
    const { data, error } = await ctx.sb.from("finance_rules").insert({
      match_type: "document", match_value: doc, direction: "credit", origin: "user",
      reasoning: "Criada pelo assistente a pedido do usuário.", ...campos,
    }).select("id").single();
    if (error) return { error: `Não consegui criar a regra: ${error.message}` };
    regraId = (data as any).id;
  }

  // Quantas entradas do extrato vieram deste documento: regra que não alcança nada é dita na hora.
  const { count } = await ctx.sb.from("bank_transactions").select("id", { count: "exact", head: true })
    .eq("transaction_type", "credit").eq("counterparty_document", doc);
  const efeito = await chamarFinanceReview(ctx, { action: "reclassify" });
  return {
    // CPF mascarado na resposta (LGPD, leva 8): a regra guarda o inteiro; o modelo não precisa dele.
    ok: true, regra_id: regraId, categoria: cat.name, documento: documentoMascarado(doc),
    entradas_deste_documento_no_extrato: count ?? 0,
    propostas_reclassificadas: Number((efeito as any)?.atualizadas ?? 0),
    lembrete: `A regra só preenche a categoria (${cat.name}, sem cliente): cada entrada sai da fila sem receita, e só com o OK do usuário na própria linha.`,
  };
}

/** A recusa da regra de entrada com cliente (leva 8): aponta o caminho novo, com o SIM do dono. */
const RECUSA_REGRA_DE_CLIENTE = {
  error: "Regra de entrada não diz mais de quem é o dinheiro (decisão do dono, 22/10/2026). Quem paga por um cliente — "
    + "cônjuge, empresa dele, parente, marina, seguradora — se guarda com guardar_pagador_do_cliente, a partir de uma entrada "
    + "do extrato que essa pessoa pagou, e o dono confirma; os próximos Pix dela só SUGEREM o cliente. Regra de entrada só "
    + "para 'Aporte de sócio' ou 'Transferência entre contas' (sem cliente).",
};

export const financeRulesTools: ToolDef[] = [
  // ── ENSINAR: muda o que o sistema propõe, não o que ele já lançou ──────────────
  {
    name: "criar_regra_financeira",
    description:
      "Ensina o sistema a classificar despesas automaticamente. Use quando o usuário disser algo como " +
      "'toda transação com Mercado Livre é peças e materiais', 'pagamentos para Fulano são sempre pró-labore' " +
      "ou 'despesas do fornecedor X vão para categoria Y'. Também ensina ENTRADAS sem cliente: 'o Pix do CPF do " +
      "sócio é aporte' (sentido='entrada', reconhecer_por='documento'). 'O Pix do CPF X é do cliente Y' NÃO é regra: " +
      "quem paga por um cliente (cônjuge, empresa dele, marina) se guarda com guardar_pagador_do_cliente. Ao criar, a regra também " +
      "reclassifica as propostas que já estão na fila aguardando decisão. Não altera " +
      "lançamentos já feitos.",
    input_schema: {
      type: "object",
      properties: {
        reconhecer_por: {
          type: "string",
          enum: ["texto", "fornecedor", "documento", "nome_de_quem_recebe"],
          description:
            "texto = trecho que aparece no histórico do extrato (ex: MERCADOLIVRE) — é o mais comum. " +
            "fornecedor = NOME de fornecedor cadastrado, igual ao do cadastro (vale só para o que o banco escreve com o " +
            "MESMO nome ou o mesmo CNPJ). Para a grafia do cartão ('PREMEL - ITAJAI'), use texto + fornecedor_da_regra. " +
            "documento = CNPJ/CPF. nome_de_quem_recebe = nome exato da contraparte no extrato.",
        },
        valor_de_busca: {
          type: "string",
          description:
            "O trecho, nome do fornecedor, documento ou nome procurado. " +
            "Com reconhecer_por='texto', VÁRIOS trechos podem vir separados por vírgula e " +
            "cada um vira uma regra — use isso quando o usuário listar sinônimos e " +
            "abreviações para a mesma categoria (ex: 'PANIFIC, PADAR, CONFEIT'). " +
            "O trecho casa em qualquer parte do histórico, inclusive colado a outras " +
            "letras: 'CONFEIT' pega 'LMGCONFEITARIA'. Prefira o radical curto e sem " +
            "acento, que cobre as variações de uma vez.",
        },
        bank_transaction_id: {
          type: "string",
          description: "Com reconhecer_por='documento' e o documento de uma linha do extrato: o id da linha (de " +
            "listar_transacoes_pendentes). O CPF/CNPJ é lido do banco — a lista mostra o CPF mascarado (***), que não serve " +
            "em valor_de_busca.",
        },
        categoria: {
          type: "string",
          description: "Categoria do plano de contas a aplicar. Com sentido='entrada', uma categoria de RECEITA "
            + "(ex.: Serviços prestados, Venda de peças e produtos, Sinal e adiantamento).",
        },
        sentido: {
          type: "string",
          enum: ["saida", "entrada"],
          description: "saida (padrão) = despesa. entrada = dinheiro que ENTRA e não é de cliente: categoria 'Aporte de sócio' "
            + "ou 'Transferência entre contas' (\"o Pix do CPF do sócio é aporte\"), com reconhecer_por='documento' e o CPF/CNPJ "
            + "em valor_de_busca — ou, se o CPF veio mascarado da lista do extrato, o id da linha em bank_transaction_id. "
            + "Regra de entrada não leva cliente e só sugere: a entrada espera o OK do usuário.",
        },
        substituir_regra_existente: {
          type: "boolean",
          description: "Só com reconhecer_por='fornecedor', quando a ferramenta disser que já há regra para a empresa e o usuário confirmar a troca: pausa a antiga e cria a nova.",
        },
        fornecedor_da_regra: {
          type: "string",
          description: "Só com reconhecer_por='texto': o fornecedor cadastrado (nome igual ao do cadastro) a quem a despesa pertence.",
        },
        valor_minimo: { type: "number", description: "Opcional: só vale acima deste valor." },
        valor_maximo: { type: "number", description: "Opcional: só vale até este valor." },
        lancar_sozinha: {
          type: "boolean",
          description:
            "false (padrão) = a despesa fica na fila já classificada, aguardando o OK do gestor. " +
            "true = a despesa é lançada automaticamente. Só use true se o usuário pedir explicitamente.",
        },
      },
      required: ["reconhecer_por", "valor_de_busca", "categoria"],
    },
    // Média, não alta: a regra não move dinheiro e desfazer é pausá-la. Mas escreve
    // configuração que afeta lançamentos futuros, então passa pela confirmação.
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    // CPF mascarado sem a linha do extrato é recusado ANTES do cartão (revisão da leva 8, 23/10/2026).
    preValidar: (args) => String(args?.reconhecer_por ?? "") === "documento"
      ? preValidarDocumento(args?.valor_de_busca, args?.bank_transaction_id)
      : null,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;

      // Regra por documento (leva 8, LGPD): o CPF que o modelo vê sai mascarado; o inteiro vem da LINHA do banco.
      if (args.reconhecer_por === "documento") {
        const doc = await documentoDaRegra(args as Record<string, unknown>, ctx);
        if ("error" in doc) return doc;
        args = { ...args, valor_de_busca: doc.documento };
      }

      // Regra de ENTRADA ("o Pix deste CPF é do cliente Y") é outro caminho, com outras travas.
      if (args.sentido === "entrada") return await criarRegraDeEntrada(args as Record<string, unknown>, ctx);

      const cats = await categoriasValidas(ctx);
      const cat = cats.find((c) => c.name.toLowerCase() === String(args.categoria).toLowerCase());
      if (!cat) {
        return {
          error: `A categoria "${args.categoria}" não existe no plano de contas.`,
          categorias_disponiveis: cats.map((c) => c.name),
          dica: "Use criar_categoria_de_despesa antes, ou escolha uma da lista.",
        };
      }

      const tipoMap: Record<string, string> = {
        texto: "text",
        fornecedor: "supplier",
        documento: "document",
        nome_de_quem_recebe: "counterparty",
      };
      const tipo = tipoMap[String(args.reconhecer_por)];
      let alvo = String(args.valor_de_busca).trim();

      // Regra por fornecedor guarda o ID, mas quem fala diz o NOME — e o agente não tem
      // como adivinhar um uuid. Resolver aqui evita a regra nascer apontando para um
      // fornecedor que não existe, que só apareceria como "regra que nunca aplica".
      let fornecedorNome: string | null = null;
      /** Regras da mesma empresa que a nova substitui — pausadas só DEPOIS de a nova existir. */
      let aSubstituir: string[] = [];
      if (tipo === "supplier") {
        const r = await resolverFornecedorDito(ctx, alvo);
        if ("error" in r) return r;
        alvo = r.id;
        fornecedorNome = r.nome;
        // Já existe regra ativa para esta EMPRESA (o mesmo cadastro, a matriz ou uma filial)?
        // Duas regras na mesma empresa brigariam; a nova só entra trocando a antiga, e só se
        // o usuário disser (revisão de 26/09/2026).
        const cadastros = (await lerFornecedores(ctx)) as FornecedorDaLista[];
        const eu = cadastros.find((f) => f.id === alvo);
        const daEmpresa = eu ? cadastros.filter((f) => empresaDoCadastro(f) === empresaDoCadastro(eu)).map((f) => f.id) : [alvo];
        // Ativas e propostas: uma proposta na filial bateria no índice único na hora de criar.
        const { data: existentes } = await ctx.sb.from("finance_rules")
          .select("id, match_value, set_category, autonomy, direction, status")
          .eq("match_type", "supplier").in("status", ["active", "proposed"]).in("match_value", daEmpresa);
        const conflito = ((existentes ?? []) as any[]).filter((x) => x.direction === "debit" || x.direction === "any");
        if (conflito.length > 0 && !args.substituir_regra_existente) {
          return {
            error: `Já existe regra ${conflito[0].status === "proposed" ? "sugerida" : "ativa"} para esta empresa (${eu?.name ?? fornecedorNome}): `
              + `categoria "${conflito[0].set_category}"${conflito[0].autonomy === "apply" ? ", lançando sozinha" : ""}. `
              + "Pergunte ao usuário se é para TROCAR; se for, repita com substituir_regra_existente=true (a antiga é pausada, não apagada).",
          };
        }
        // Trocar a regra do MESMO cadastro é editar a que existe (o índice não deixa duas no
        // mesmo alvo); trocar a de outro cadastro da empresa é criar a nova e só então pausar.
        const mesma = conflito.find((x) => x.match_value === alvo);
        if (mesma) {
          const { error: eEdita } = await ctx.sb.from("finance_rules").update({
            set_category: cat.name, set_dre_group: cat.dre_group, set_supplier_id: alvo,
            autonomy: args.lancar_sozinha ? "apply" : "suggest",
            min_amount: args.valor_minimo ?? null, max_amount: args.valor_maximo ?? null, status: "active",
          }).eq("id", mesma.id);
          if (eEdita) return { error: `Não consegui trocar a regra: ${eEdita.message}` };
          const outras = conflito.filter((x) => x.id !== mesma.id).map((x) => x.id);
          if (outras.length > 0) await ctx.sb.from("finance_rules").update({ status: "paused" }).in("id", outras);
          const efeito = await chamarFinanceReview(ctx, { action: "reclassify" });
          return {
            ok: true, categoria: cat.name, fornecedor: fornecedorNome ?? undefined, regra_trocada: mesma.id,
            lanca_sozinha: !!args.lancar_sozinha,
            propostas_reclassificadas: Number((efeito as any)?.atualizadas ?? 0),
          };
        }
        aSubstituir = conflito.map((x) => x.id);
      }
      // Regra de TEXTO que também diz de quem é a despesa: o caminho para a grafia do cartão
      // ("PREMEL - ITAJAI" é a PREMEL MAT. ELETRICOS), que a regra de fornecedor não alcança
      // mais por nome parecido (decisão do dono, 26/09/2026).
      let fornecedorDaRegra: { id: string; nome: string } | null = null;
      if (tipo === "text" && args.fornecedor_da_regra) {
        const r = await resolverFornecedorDito(ctx, String(args.fornecedor_da_regra));
        if ("error" in r) return r;
        fornecedorDaRegra = r;
      }

      /**
       * Vários trechos numa tacada, quando a regra é por texto.
       *
       * O usuário pediu seis termos para "Alimentação de campo" — PANIFICADORA, PANIFIC,
       * PADARIA, PADAR, CONFEITARIA, CONFEIT — e o assistente criou UM. Os outros cinco
       * simplesmente não existiam, e a tela seguia sem classificar padaria nenhuma sem
       * nada indicando que faltava regra. Quem lista sinônimos está descrevendo UMA
       * intenção; obrigá-lo a repetir o pedido seis vezes é transformar a ferramenta em
       * formulário.
       */
      const alvos = tipo === "text"
        ? [...new Set(alvo.split(/[,;]/).map((t) => t.trim()).filter(Boolean))]
        : [alvo];

      const criadas: Array<Record<string, unknown>> = [];
      const recusadas: string[] = [];
      // O documento volta ao modelo mascarado (CPF ***; CNPJ inteiro); a regra guarda o inteiro.
      const rotuloDoAlvo = (v: string) => (tipo === "document" ? documentoMascarado(v) ?? v : v);

      for (const valor of alvos) {
        const { data, error } = await ctx.sb
          .from("finance_rules")
          .insert({
            match_type: tipo,
            match_value: valor,
            direction: "debit",
            set_category: cat.name,
            set_dre_group: cat.dre_group,
            set_supplier_id: fornecedorDaRegra?.id ?? null,
            min_amount: args.valor_minimo ?? null,
            max_amount: args.valor_maximo ?? null,
            autonomy: args.lancar_sozinha ? "apply" : "suggest",
            origin: "user",
            status: "active",
            reasoning: "Criada pelo assistente a pedido do usuário.",
          })
          .select("id")
          .single();

        if (error) {
          recusadas.push(/uma_por_alvo|duplicate key/i.test(error.message)
            ? `${rotuloDoAlvo(valor)}: já existe uma regra ativa para este alvo`
            : `${rotuloDoAlvo(valor)}: ${error.message}`);
          continue;
        }
        criadas.push({ id: (data as any).id, alvo: rotuloDoAlvo(valor), ...await alcanceDaRegra(ctx, tipo, valor) });
      }

      if (criadas.length === 0) {
        return { error: "Nenhuma regra criada.", detalhes: recusadas };
      }
      // Só agora, com a nova de pé, a antiga da mesma empresa sai (pausada, não apagada).
      if (aSubstituir.length > 0) {
        const { error: ePausa } = await ctx.sb.from("finance_rules").update({ status: "paused" }).in("id", aSubstituir);
        if (ePausa) recusadas.push(`A regra antiga não foi pausada (${ePausa.message}) — pause-a pela tela para as duas não brigarem`);
      }

      // A regra nova alcança de imediato o que JÁ está esperando decisão. Sem isto, quem
      // ensina "compra na Corema é ferramenta" continua corrigindo à mão as 40 compras da
      // Corema que já estavam na fila — as linhas que a regra existe para resolver.
      // Reclassificar troca a sugestão e não aprova nada, então é seguro rodar sozinho.
      const efeito = await chamarFinanceReview(ctx, { action: "reclassify" });

      // Regra que não alcança nada é regra morta, e hoje ela nascia calada. Dizer o número
      // na hora é o que separa "ensinei o sistema" de "achei que tinha ensinado".
      const mortas = criadas.filter((c) => Number(c.alcanca ?? 0) === 0);

      return {
        ok: true,
        categoria: cat.name,
        // O cadastro que a regra usa, por extenso: o "sim" foi sobre ele.
        fornecedor: fornecedorNome ?? fornecedorDaRegra?.nome ?? undefined,
        regras_criadas: criadas,
        nao_criadas: recusadas.length > 0 ? recusadas : undefined,
        lanca_sozinha: !!args.lancar_sozinha,
        propostas_reclassificadas: Number((efeito as any)?.atualizadas ?? 0),
        aviso: mortas.length > 0
          ? `Estas não alcançam nenhuma transação do extrato hoje: ${mortas.map((m) => m.alvo).join(", ")}. `
            + "Confira a grafia — e, se o alvo era um nome de estabelecimento, prefira "
            + "reconhecer_por='texto' com um trecho curto, porque a regra por nome exige o nome inteiro."
          : undefined,
      };
    },
  },

  {
    name: "listar_regras_financeiras",
    description:
      "Mostra as regras de classificação já ensinadas, quantas vezes cada uma foi aplicada e quais " +
      "estão apenas sugeridas pelo sistema aguardando aceite.",
    input_schema: {
      type: "object",
      properties: {
        situacao: { type: "string", enum: ["ativas", "sugeridas", "pausadas", "todas"] },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const mapa: Record<string, string> = {
        ativas: "active", sugeridas: "proposed", pausadas: "paused",
      };
      let q = ctx.sb.from("finance_rules")
        .select("id, match_type, match_value, direction, set_category, set_client_id, autonomy, status, times_applied, reasoning, clients(name)")
        .order("times_applied", { ascending: false }).limit(100);
      const alvo = mapa[String(args.situacao ?? "ativas")];
      if (alvo) q = q.eq("status", alvo);

      const { data, error } = await q;
      if (error) return { error: error.message };
      // Regra de entrada diz o cliente pelo nome: o id sozinho não significa nada para quem lê.
      // CPF mascarado (LGPD, leva 8) no alvo da regra por documento e no texto do porquê; mudar a regra é pelo id.
      const regras = ((data ?? []) as any[]).map(({ clients, set_client_id, direction, ...r }) => ({
        ...r,
        match_value: r.match_type === "document" ? documentoMascarado(r.match_value) ?? r.match_value : r.match_value,
        reasoning: mascararCpfNoTexto(r.reasoning),
        sentido: direction === "credit" ? "entrada" : "saida",
        ...(set_client_id ? { cliente: clients?.name ?? "(cadastro removido)" } : {}),
      }));
      return { regras, total: regras.length };
    },
  },

  {
    name: "mudar_situacao_da_regra",
    description:
      "Ativa, pausa ou recusa uma regra. Use para 'pare de aplicar a regra do posto', " +
      "'aceite a regra que você sugeriu para a Coremma' ou 'reative aquela regra'.",
    input_schema: {
      type: "object",
      properties: {
        regra_id: { type: "string" },
        nova_situacao: { type: "string", enum: ["ativa", "pausada", "recusada"] },
      },
      required: ["regra_id", "nova_situacao"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const mapa: Record<string, string> = { ativa: "active", pausada: "paused", recusada: "rejected" };
      const { error } = await ctx.sb.from("finance_rules")
        .update({ status: mapa[String(args.nova_situacao)] })
        .eq("id", args.regra_id);
      if (error) return { error: error.message };
      return { ok: true, situacao: args.nova_situacao };
    },
  },

  {
    name: "criar_categoria_de_despesa",
    description:
      "Cria uma categoria nova no plano de contas, quando nenhuma existente serve. " +
      "Sempre confira a lista antes com listar_categorias_financeiras — categoria duplicada " +
      "divide o mesmo gasto em duas linhas do resultado.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        grupo: {
          type: "string",
          enum: ["custo_direto", "despesa_operacional", "financeiro", "nao_operacional", "receita"],
          description:
            "Onde entra no resultado. custo_direto = ligado à execução do serviço. " +
            "despesa_operacional = manter a empresa aberta. financeiro = juros e tarifas. " +
            "nao_operacional = NÃO entra no resultado (fatura de cartão, transferência própria).",
        },
      },
      required: ["nome", "grupo"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const { error } = await ctx.sb.from("financial_categories").insert({
        name: String(args.nome).trim(),
        type: args.grupo === "receita" ? "receivable" : "payable",
        dre_group: args.grupo,
        active: true,
        sort_order: 900,
      });
      if (error) {
        if (/duplicate key|nome_tipo/i.test(error.message)) {
          return { error: `A categoria "${args.nome}" já existe.` };
        }
        return { error: error.message };
      }
      return { ok: true, categoria: args.nome, grupo: args.grupo };
    },
  },

  {
    name: "listar_categorias_financeiras",
    description: "Lista as categorias do plano de contas com o grupo de cada uma no resultado.",
    input_schema: {
      type: "object",
      properties: { tipo: { type: "string", enum: ["despesa", "receita"] } },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const cats = await categoriasValidas(ctx, args.tipo === "receita" ? "receivable" : "payable");
      return { categorias: cats, total: cats.length };
    },
  },

  // ── A CAIXA DE ENTRADA: propor é barato, aprovar cria lançamento ───────────────
  {
    name: "analisar_extrato_e_propor_lancamentos",
    description:
      "Varre as movimentações do banco que ainda não viraram lançamento e monta propostas de despesa, " +
      "já classificadas pelas regras. NÃO lança nada — só enche a fila para o gestor decidir. " +
      "Use para 'analise o extrato', 'o que ainda não foi lançado'.",
    input_schema: {
      type: "object",
      properties: {
        incluir_historico_antigo: {
          type: "boolean",
          description: "false (padrão) olha os últimos 90 dias; true varre tudo.",
        },
      },
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "generate", incluir_historico: !!args.incluir_historico_antigo });
    },
  },

  {
    name: "listar_propostas_de_lancamento",
    description:
      "Mostra o que está esperando decisão na caixa de entrada financeira: o que o sistema propôs lançar, " +
      "com valor, categoria, QUEM é a contraparte (e por qual prova), o que cadastrar numa SAÍDA quando ninguém foi " +
      "reconhecido (o CPF vem mascarado: para cadastrar, cadastrar_contraparte_do_extrato com o id da proposta) " +
      "e o VÍNCULO sugerido (conta, OS, pagamento/sinal que PODE JÁ ESTAR LANÇADO). ENTRADA sem cliente " +
      "(de_quem_e): PERGUNTE ao usuário de quem é o pagamento; nunca cadastre cliente com os dados de quem pagou (quase " +
      "sempre é cônjuge, empresa do cliente, marina). Se quem pagou costuma pagar por aquele cliente, guardar_pagador_do_cliente " +
      "(os já guardados: listar_pagadores_do_cliente). " +
      "ENTRADA com cliente_pede_sim: o cliente é só sugestão (motivo_do_cliente) — pergunte 'É do X?' e, com o sim, passe o " +
      "id em cliente_confirmado ao aprovar. ENTRADA com falta_escolher_o_cliente: ninguém resolveu de quem é (a anotação que " +
      "dizia o cliente foi desfeita ou não deu para conferi-la) — PERGUNTE de quem é o pagamento, sem sugerir cliente nenhum; " +
      "a aprovação é recusada até o cliente ser escolhido (na tela do Extrato, ou numa anotação nova). Todo vínculo " +
      "é pergunta: antes de aprovar, pergunte se é aquele (casar) ou se é para lançar novo. Idem os_sugerida e " +
      "oc_sugerida: pergunte 'é da OS X?' / 'paga a OC Y?' e passe a resposta em aprovar (os / oc). " +
      "ENTRADA com parece_pagar: o Pix parece pagar contas que JÁ EXISTEM do cliente (soma bate). Pergunte " +
      "'este Pix paga <frase>?'; com o sim, chame aplicar_pix_em_contas com bank_transaction_id e as aplicacoes " +
      "dadas (a linha sai da fila); se o dono disser que é receita nova, aprove com vinculos[id]='nenhum'. " +
      "Aprovar sem perguntar contaria o dinheiro duas vezes.",
    input_schema: {
      type: "object",
      properties: { limite: { type: "number" } },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const { data, error } = await ctx.sb
        .from("finance_review_queue")
        .select("id, title, suggested_amount, suggested_category, suggested_date, confidence, kind, evidencia, vinculo_sugerido, suggested_service_order_id, suggested_purchase_order_id, bank_transaction_id, suggested_client_id")
        .eq("status", "pending")
        .order("suggested_amount", { ascending: false })
        .limit(Number(args.limite ?? 30));
      if (error) return { error: error.message };
      const linhas = (data ?? []) as any[];
      // Número da OS e da OC sugeridas: a pergunta "é da OS 60?" precisa do número, não do id.
      const idsOs = [...new Set(linhas.map((l) => l.suggested_service_order_id).filter(Boolean))];
      const idsOc = [...new Set(linhas.map((l) => l.suggested_purchase_order_id).filter(Boolean))];
      const [{ data: oss }, { data: ocs }] = await Promise.all([
        idsOs.length ? ctx.sb.from("service_orders").select("id, service_order_number").in("id", idsOs) : Promise.resolve({ data: [] }),
        idsOc.length ? ctx.sb.from("purchase_orders").select("id, po_number").in("id", idsOc) : Promise.resolve({ data: [] }),
      ]);
      const numeroDaOs = new Map(((oss ?? []) as any[]).map((o) => [o.id, o.service_order_number]));
      const numeroDaOc = new Map(((ocs ?? []) as any[]).map((o) => [o.id, o.po_number]));
      // Resumo curto por linha: o modelo precisa do que decide, não do objeto inteiro.
      const quem = (e: any) => {
        const r = e?.fornecedor ?? e?.favorecido ?? e?.cliente;
        return r ? mascararCpfNoTexto(`${r.nome} (por ${r.por})`) : null;
      };
      // O rótulo do vínculo é a descrição da conta/pagamento — às vezes o nome do banco com o CPF dentro (LGPD).
      const opcoes = (v: any) => (v ? [v.principal, ...(v.alternativas ?? [])] : []).map((o: any) => ({
        opcao_id: o.id, o_que: mascararCpfNoTexto(o.rotulo ?? null), valor: o.valor, pontos: o.confianca, ja_lancado: !!o.jaLancado,
        converte_orcamento: !!o.converteOrcamento,
      }));
      // Leva 8 (22/10/2026): a ENTRADA nunca traz "cadastrar" (cliente com os dados de quem pagou) — traz a pergunta
      // de_quem_e, com o CPF mascarado. E o cliente sugerido por pagador conhecido, histórico de terceiro ou vínculo
      // antigo pede o SIM — menos quando a anotação do dono disse o cliente (revisão de 23/10/2026). O sugerido que não
      // é o da prova só vale com a anotação em vigor que o disse; sem ela (desfeita, leitura que falhou), falta escolher
      // o cliente (4ª rodada). situacaoDoClienteSugerido é a mesma fonte do servidor.
      const anotacoes = await anotacoesDasEntradas(ctx.sb, linhas);
      // deno-lint-ignore no-explicit-any
      const anotacaoDa = (p: any): AnotacaoDoDono | null => {
        const id = String(p.evidencia?.anotacao?.id ?? "");
        return id && anotacoes.has(id) ? anotacoes.get(id) ?? null : (p.evidencia?.anotacao ?? null);
      };
      // deno-lint-ignore no-explicit-any
      const situacao = (p: any) => situacaoDoClienteSugerido(p.suggested_client_id, p.evidencia?.cliente, anotacaoDa(p));
      // "Parece pagar" só com um cliente que vale ou que pede o SIM — nunca com o sugerido que ninguém disse ser o
      // da linha (situação "escolher": anotação desfeita, leitura que falhou), como na tela (revisão de 23/10/2026).
      const parece = await parecePagarDasEntradas(
        ctx, (linhas as EntradaDaFila[]).filter((l) => l.kind !== "create_receivable" || situacao(l) !== "escolher"),
      );
      // O sugerido que veio de fora da prova do motor (a anotação do dono): o "quem" é ELE, pelo nome do cadastro —
      // nunca a prova antiga de outro cliente (C2, 4ª rodada). Uma leitura só, com o erro conferido.
      // deno-lint-ignore no-explicit-any
      const foraDaProva = (p: any) => p.kind === "create_receivable" && !!p.suggested_client_id
        && String(p.evidencia?.cliente?.id ?? "") !== String(p.suggested_client_id);
      const idsAnotados = [...new Set(linhas.filter((p) => foraDaProva(p) && situacao(p) === "vale")
        .map((p) => String(p.suggested_client_id)))];
      const nomeDoAnotado = new Map<string, string>();
      let nomesFalharam = false;
      if (idsAnotados.length) {
        try {
          const { data: clis, error: eCli } = await ctx.sb.from("clients").select("id, name").in("id", idsAnotados);
          if (eCli) nomesFalharam = true;
          for (const c of (clis ?? []) as Array<{ id: string; name: string | null }>) {
            if (String(c.name ?? "").trim()) nomeDoAnotado.set(String(c.id), String(c.name).trim());
          }
        } catch {
          nomesFalharam = true;
        }
      }
      // deno-lint-ignore no-explicit-any
      const quemDaLinha = (p: any) => {
        if (!foraDaProva(p)) return quem(p.evidencia);
        if (situacao(p) === "escolher") return QUEM_FALTA_ESCOLHER;
        const nome = nomeDoAnotado.get(String(p.suggested_client_id));
        if (nome) return mascararCpfNoTexto(`${nome} (você anotou)`);
        return nomesFalharam
          ? "o cliente que você anotou (não consegui ler o nome dele agora)"
          : "o cliente que você anotou (não está mais no cadastro)";
      };
      // deno-lint-ignore no-explicit-any
      const daEntrada = (p: any) => {
        if (p.kind !== "create_receivable") return null;
        const s = situacao(p);
        // Ninguém resolveu de quem é: nenhum cliente é oferecido — a pergunta "de quem é?" que estava na evidência
        // volta (a anotação que a resolvia não vale mais); a prova antiga de outro cliente não vira sugestão.
        if (s === "escolher") {
          return {
            falta_escolher_o_cliente: true,
            de_quem_e: deQuemEDaEntrada({ suggested_client_id: null, evidencia: p.evidencia }),
          };
        }
        return {
          de_quem_e: deQuemEDaEntrada(p),
          ...(s === "pede_sim"
            ? { cliente_pede_sim: true, motivo_do_cliente: mascararCpfNoTexto(p.evidencia?.cliente?.detalhe ?? null) }
            : {}),
        };
      };
      // deno-lint-ignore no-explicit-any
      const daLinha = (p: any) => daEntrada(p) ?? {
        // Na SAÍDA, o CPF do favorecido/freelancer também sai mascarado (decisão do dono, 23/10/2026): para cadastrá-lo,
        // cadastrar_contraparte_do_extrato lê o documento da fila pelo id da proposta.
        cadastrar: p.evidencia?.cadastrar
          // Só o CPF (pessoa) é mascarado; o CNPJ de empresa segue como veio.
          ? {
            ...p.evidencia.cadastrar,
            // O nome que o banco escreve pode trazer o CPF ("12345678901-JOAO"): mascarado também.
            nome: mascararCpfNoTexto(p.evidencia.cadastrar.nome ?? null),
            documento: documentoNormalizado(p.evidencia.cadastrar.documento).length === 11
              ? documentoMascarado(p.evidencia.cadastrar.documento)
              : p.evidencia.cadastrar.documento ?? null,
          }
          : null,
      };
      return {
        propostas: linhas.map((p) => ({
          id: p.id, tipo: p.kind === "create_receivable" ? "entrada" : p.kind === "create_payable" ? "saida" : p.kind,
          titulo: tituloMascarado(p.title), valor: Number(p.suggested_amount ?? 0), data: p.suggested_date,
          bank_transaction_id: p.bank_transaction_id ?? null,
          parece_pagar: parece.has(p.id) ? parecePagarParaOModelo(parece.get(p.id)!) : null,
          categoria: p.suggested_category, confianca: p.confidence,
          quem: quemDaLinha(p),
          ...daLinha(p),
          pode_ja_estar_lancado: opcoes(p.vinculo_sugerido).some((o: any) => o.ja_lancado),
          vinculos: opcoes(p.vinculo_sugerido),
          // OS que é do próprio vínculo já é perguntada pelo vínculo; a anotada já foi dita.
          os_sugerida: p.suggested_service_order_id
            && ![p.vinculo_sugerido?.principal, ...(p.vinculo_sugerido?.alternativas ?? [])]
              .some((o: any) => o?.ordemDeServicoId === p.suggested_service_order_id)
            ? {
              os_id: p.suggested_service_order_id,
              numero: numeroDaOs.get(p.suggested_service_order_id) ?? null,
              ja_dita_na_anotacao: p.evidencia?.anotacao?.os_id === p.suggested_service_order_id,
            }
            : null,
          oc_sugerida: p.suggested_purchase_order_id
            ? { oc_id: p.suggested_purchase_order_id, numero: numeroDaOc.get(p.suggested_purchase_order_id) ?? null }
            : null,
          // Serviço de terceiro: pergunte para onde foi (serviço de um cliente → OS; para a HBR →
          // centro de custo) e o que foi feito, e passe em aprovar (destino, os, centro_de_custo,
          // observacao). Decisão do dono, 26/09/2026.
          servico_de_terceiro: precisaDeDestino(p.kind, p.suggested_category)
            ? {
              falta: faltaNoDestino(p.kind, p.suggested_category, {},
                p.evidencia?.anotacao?.os_id === p.suggested_service_order_id ? p.suggested_service_order_id : null),
            }
            : undefined,
        })),
        total: linhas.length,
        valor_total: linhas.reduce((s, p) => s + Number(p.suggested_amount ?? 0), 0),
      };
    },
  },

  {
    name: "aprovar_propostas_de_lancamento",
    description:
      "Aprova propostas da caixa de entrada, CRIANDO os lançamentos correspondentes — ou CASANDO com o que " +
      "já existe, quando o usuário escolheu um vínculo. Linha com vínculo sugerido é recusada pelo " +
      "servidor sem a escolha: pergunte e passe em `vinculos`. Serviço de terceiro (servico_de_terceiro na " +
      "lista) exige para onde foi e o que foi feito: pergunte e passe `destino` (cliente + os, ou empresa + " +
      "centro_de_custo) e `observacao`. Se o usuário mandar trocar a categoria sugerida, passe a nova em " +
      "`categoria` (o nome dito; o sistema confere no plano de contas). Entrada com parece_pagar é recusada sem " +
      "resposta: se paga as contas, use aplicar_pix_em_contas; se é receita nova, passe vinculos[id]='nenhum'. " +
      "Entrada com cliente_pede_sim é recusada sem o sim do usuário ao cliente sugerido: pergunte 'É do X?' e passe o id em " +
      "`cliente_confirmado`. Só use quando o usuário confirmar quais aprovar.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" }, description: "Ids das propostas a aprovar." },
        cliente_confirmado: {
          type: "array",
          items: { type: "string" },
          description: "Ids das ENTRADAS cujo cliente SUGERIDO o usuário confirmou (\"Sim, é do X\") — as que vêm com "
            + "cliente_pede_sim. Vale o cliente que a fila sugere, nunca um nome.",
        },
        destino: {
          type: "object",
          description: "Por proposta de serviço de terceiro: \"cliente\" (foi para o serviço de um cliente — passe a OS em `os`, ou \"nenhuma\" se não tem OS) ou \"empresa\" (para a própria HBR: sede, obra, veículo, equipamento — passe `centro_de_custo`).",
          additionalProperties: { type: "string", enum: ["cliente", "empresa"] },
        },
        centro_de_custo: {
          type: "object",
          description: "Por proposta: o NOME do centro de custo dito pelo usuário (ex.: \"Obras e reformas da sede\", \"Veículos da empresa\").",
          additionalProperties: { type: "string" },
        },
        observacao: {
          type: "object",
          description: "Por proposta: a observação do usuário. No serviço de terceiro é o que foi feito (ex.: \"pintura da fachada da sede\").",
          additionalProperties: { type: "string" },
        },
        vinculos: {
          type: "object",
          description: "Por proposta: o opcao_id escolhido (de listar_propostas_de_lancamento) para casar, ou \"nenhum\" para lançar novo. "
            + "Numa ENTRADA com categoria 'Aporte de sócio' ou 'Transferência entre contas', \"nenhum\" tira a linha da fila SEM receita; "
            + "casar ali é recusado — se o usuário disser que é pagamento de cliente, a categoria se troca na tela do Extrato.",
          additionalProperties: { type: "string" },
        },
        os: {
          type: "object",
          description: "Por proposta: o os_id que o usuário CONFIRMOU (\"é desta OS\"), ou \"nenhuma\". Sem resposta, a despesa entra sem OS.",
          additionalProperties: { type: "string" },
        },
        oc: {
          type: "object",
          description: "Por proposta: o oc_id que o usuário confirmou que este pagamento quita, ou \"nenhuma\".",
          additionalProperties: { type: "string" },
        },
        categoria: {
          type: "object",
          description: "Por proposta: a categoria que o usuário mandou usar NO LUGAR da sugerida (ex.: \"Alimentação de campo\"). "
            + "Só quando ele pedir a troca; nome fora do plano de contas volta como pergunta, com as opções.",
          additionalProperties: { type: "string" },
        },
      },
      required: ["ids"],
    },
    // ALTA: cria lançamento contábil. Diferente de criar regra, isto não se desfaz
    // pausando nada — vira despesa registrada com data e valor.
    risk: "high",
    roles: CARGOS_FINANCEIRO,
    // O "sim" ao cliente sugerido (cliente_confirmado) foi dado sobre o cliente que a fila sugeria QUANDO a pendência
    // nasceu: se a varredura trocar a sugestão até o "sim" da aprovação, a execução recusa em vez de lançar para outro.
    // Leitura que falha (erro ou exceção) NÃO vira "sem retrato" — sem ele a execução aplicaria o cliente do momento,
    // a quem o dono pode nunca ter dito sim: vira o marcador RETRATO_QUE_FALHOU, e a execução recusa (revisão de 23/10).
    retratoDaPendencia: async (args, ctx) => {
      const confirmados = idsDoClienteConfirmado(args);
      if (!confirmados.length) return null;
      try {
        const { data, error } = await ctx.admin.from("finance_review_queue").select("id, suggested_client_id").in("id", confirmados);
        if (error) return { ...RETRATO_QUE_FALHOU };
        return {
          cliente_confirmado: Object.fromEntries(((data ?? []) as Array<{ id: string; suggested_client_id: string | null }>)
            .map((f) => [String(f.id), f.suggested_client_id ?? null])),
        };
      } catch {
        return { ...RETRATO_QUE_FALHOU };
      }
    },
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      // Entrada que parece pagar contas que já existem (F4, 03/10/2026): sem resposta, recusa — a tela
      // faz o mesmo. Foi aprovando Pix como receita nova que a de agosto contou R$ 4.800 duas vezes.
      const ids: string[] = (Array.isArray(args.ids) ? args.ids : []).map(String);
      const respondidas = new Set(Object.entries((args.vinculos ?? {}) as Record<string, string>).filter(([, v]) => !!v).map(([id]) => id));
      const semResposta = ids.filter((id) => !respondidas.has(id));
      if (semResposta.length) {
        const { data: filas, error: erroFila } = await ctx.sb.from("finance_review_queue")
          .select("id, kind, title, bank_transaction_id, suggested_client_id, suggested_amount, suggested_date")
          .in("id", semResposta);
        if (erroFila) throw new Error(`Não consegui ler as propostas: ${erroFila.message}`);
        const parece = await parecePagarDasEntradas(ctx, (filas ?? []) as EntradaDaFila[]);
        const fortes = ((filas ?? []) as Array<EntradaDaFila & { title: string }>)
          .filter((f) => parece.get(f.id) && !parece.get(f.id)!.parcial);
        if (fortes.length) {
          return {
            error: "Estas entradas parecem pagar contas que já existem — aprovar como receita nova contaria o dinheiro duas vezes. "
              + "Pergunte ao usuário: se pagam, use aplicar_pix_em_contas; se são receita nova, repita com vinculos[id]='nenhum'.",
            entradas: fortes.map((f) => ({
              id: f.id, titulo: tituloMascarado(f.title), bank_transaction_id: f.bank_transaction_id,
              parece_pagar: parecePagarParaOModelo(parece.get(f.id)!),
            })),
          };
        }
      }
      const overrides: Record<string, Record<string, unknown>> = {};
      const de = (id: string) => (overrides[id] ??= {});
      for (const [id, escolha] of Object.entries((args.vinculos ?? {}) as Record<string, string>)) {
        if (!escolha) continue;
        de(id).vinculo = escolha === "nenhum" ? "nenhum" : { id: String(escolha) };
      }
      // "É desta OS?" / "Paga esta OC?" respondidos pelo usuário (decisão do dono, 26/09/2026).
      const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      for (const [campo, mapa] of [["os", args.os], ["oc", args.oc]] as const) {
        for (const [id, v] of Object.entries((mapa ?? {}) as Record<string, string>)) {
          if (!v) continue;
          if (!/^nenhum/i.test(v) && !UUID.test(String(v))) {
            return { error: `Em ${campo}, use o ${campo}_id de listar_propostas_de_lancamento (não o número) ou "nenhuma".` };
          }
          const valor = /^nenhum/i.test(v) ? null : String(v);
          if (campo === "os") de(id).serviceOrderId = valor; else de(id).purchaseOrderId = valor;
        }
      }
      // Para onde foi, centro de custo e o que foi feito (decisão do dono, 26/09/2026). O servidor
      // confere de novo o que falta; o centro é resolvido aqui pelo nome, só entre os ativos.
      for (const [id, v] of Object.entries((args.destino ?? {}) as Record<string, string>)) {
        if (v !== "cliente" && v !== "empresa") return { error: `Em destino, use "cliente" ou "empresa" (veio "${v}").` };
        de(id).destino = v;
      }
      for (const [id, v] of Object.entries((args.centro_de_custo ?? {}) as Record<string, string>)) {
        if (!v) continue;
        const r = await resolverCentroDeCusto(ctx, String(v));
        if ("error" in r) return r;
        de(id).costCenterId = r.id;
      }
      for (const [id, v] of Object.entries((args.observacao ?? {}) as Record<string, string>)) {
        if (String(v ?? "").trim()) de(id).notes = String(v).trim().slice(0, 1000);
      }
      // Troca de categoria pedida pelo usuário: o tipo (saída/entrada) vem da própria proposta.
      const categorias = Object.entries((args.categoria ?? {}) as Record<string, string>)
        .filter(([, v]) => String(v ?? "").trim());
      if (categorias.length) {
        const { data: props } = await ctx.sb
          .from("finance_review_queue")
          .select("id, kind")
          .in("id", categorias.map(([id]) => id));
        const tipoDe = new Map(((props ?? []) as any[]).map((p) => [String(p.id), String(p.kind)]));
        for (const [id, v] of categorias) {
          const kind = tipoDe.get(id);
          if (!kind) return { error: `A proposta ${id} não está na caixa de entrada.` };
          if (kind !== "create_payable" && kind !== "create_receivable") {
            return { error: "Esta proposta não tem categoria para trocar (é transferência entre contas)." };
          }
          const r = await resolverCategoriaDita(ctx, String(v), kind === "create_receivable" ? "receivable" : "payable");
          if ("error" in r) return r;
          de(id).category = r.nome;
        }
      }
      // "Sim, é do X" (leva 8, 22/10/2026): o cliente SUGERIDO que o usuário confirmou — lido da fila agora, nunca de
      // um nome. É o ov.clientId que o servidor exige quando a sugestão pede o SIM (pagador conhecido, histórico de
      // terceiro); sem ele, a entrada volta com "Confirme o cliente".
      const confirmados = idsDoClienteConfirmado(args).filter((id) => ids.includes(id));
      if (confirmados.length) {
        const { data: filas, error: eConf } = await ctx.sb.from("finance_review_queue")
          .select("id, kind, title, suggested_client_id").in("id", confirmados);
        if (eConf) throw new Error(`Não consegui ler as propostas: ${eConf.message}`);
        type Lida = { id: string; kind: string; title: string | null; suggested_client_id: string | null };
        const porId = new Map(((filas ?? []) as Lida[]).map((f) => [String(f.id), f]));
        const semSugestao = confirmados.filter((id) => {
          const f = porId.get(id);
          return !f || f.kind !== "create_receivable" || !f.suggested_client_id;
        });
        if (semSugestao.length) {
          return {
            error: "Só se confirma o cliente SUGERIDO de uma entrada, e estas não têm: pergunte ao usuário de quem é o pagamento. "
              + "Se quem pagou costuma pagar por aquele cliente, use guardar_pagador_do_cliente; senão, o cliente se escolhe na tela do Extrato.",
            propostas: semSugestao.map((id) => ({ id, titulo: tituloMascarado(porId.get(id)?.title) })),
          };
        }
        const lido = lerRetrato(args);
        if (lido?.leitura_falhou === true) {
          return {
            error: "Não consegui conferir, quando o pedido foi feito, o cliente que o usuário confirmou: nada foi aprovado. "
              + "Liste as propostas de novo e pergunte outra vez.",
            propostas: confirmados.map((id) => ({ id, titulo: tituloMascarado(porId.get(id)?.title) })),
          };
        }
        const retrato = lido?.cliente_confirmado as Record<string, string | null> | undefined;
        // Id que o retrato não tem (não estava na fila quando o dono confirmou) também é "mudou": o sim não foi sobre ele.
        const mudou = retrato
          ? confirmados.filter((id) => !(id in retrato) || retrato[id] !== porId.get(id)!.suggested_client_id)
          : [];
        if (mudou.length) {
          return {
            error: "O cliente sugerido destas entradas mudou depois que o usuário confirmou: nada foi aprovado. Liste de novo e pergunte outra vez.",
            propostas: mudou.map((id) => ({ id, titulo: tituloMascarado(porId.get(id)?.title) })),
          };
        }
        for (const id of confirmados) de(id).clientId = String(porId.get(id)!.suggested_client_id);
      }
      return await chamarFinanceReview(ctx, { action: "approve", ids: args.ids, overrides });
    },
  },

  {
    name: "recusar_propostas_de_lancamento",
    description: "Descarta propostas da caixa de entrada sem criar lançamento nenhum.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" } },
        motivo: { type: "string" },
      },
      required: ["ids"],
    },
    // Baixa: recusar não cria nem apaga nada — a transação volta a ficar pendente.
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      return await chamarFinanceReview(ctx, { action: "reject", ids: args.ids, note: args.motivo ?? null });
    },
  },

  // A edge finance-review já sabe reclassificar, classificar por IA, sugerir regras e desfazer
  // — só faltava o agente poder pedir. Nenhuma destas cria lançamento.
  {
    name: "reclassificar_propostas_de_lancamento",
    description:
      "Reaplica as regras financeiras vigentes às propostas ainda pendentes da caixa de entrada " +
      "(categoria/favorecido). Use depois de criar ou mudar uma regra. Não lança nada.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "reclassify" });
    },
  },

  {
    name: "classificar_propostas_com_ia",
    description:
      "Pede à IA uma categoria para as propostas pendentes que as regras não classificaram, usando o " +
      "plano de contas e as decisões anteriores do gestor como exemplo. Só sugere (confiança limitada a 80); " +
      "nunca aprova. Custa uma chamada de modelo.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "classify_ai" });
    },
  },

  {
    name: "sugerir_regras_financeiras",
    description:
      "Olha os lançamentos já decididos pelo gestor e propõe regras de categoria para o que se repete " +
      "(mínimo 3 casos, sem divergência). As regras nascem como 'proposta' e só valem depois de aceitas.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "suggest_rules" });
    },
  },

  {
    name: "desfazer_propostas_ignoradas",
    description:
      "Volta para a fila propostas que foram recusadas/ignoradas por engano (e desfaz o lançamento que o " +
      "motor tiver criado para elas, se houver). Use quando o usuário disser que recusou sem querer.",
    input_schema: {
      type: "object",
      properties: { ids: { type: "array", items: { type: "string" }, description: "Ids das propostas." } },
      required: ["ids"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      // Ids de PROPOSTA vão para a ação que espera ids de proposta ('reopen', 20/10/2026). Antes iam para
      // o 'undismiss', que espera ids de LINHA do banco: nada casava e a resposta era sempre "estas
      // transações não estão ignoradas". O 'reopen' devolve pelo undismiss a linha que está em Fora da
      // fila e reabre a recusa de saída ou de aviso (finance-review/recusa.ts). Descrição e esquema
      // iguais de propósito: o prefixo das tools (cacheado) não muda.
      return await chamarFinanceReview(ctx, { action: "reopen", ids: args.ids });
    },
  },

  // ── CADASTRAR QUEM O EXTRATO TROUXE ─────────────────────────────────────────────
  // A IA escolhe a LINHA; o sistema preenche o resto: documento e nome do extrato, dados da
  // Receita quando é CNPJ, categoria pela atividade, e toda linha com o mesmo documento passa
  // a apontar para o cadastro. Não duplica: documento já cadastrado devolve o existente.
  {
    name: "cadastrar_contraparte_do_extrato",
    description:
      "Cadastra o fornecedor ou favorecido de uma SAÍDA do Extrato que ninguém reconheceu " +
      "(listar_propostas_de_lancamento mostra 'cadastrar'). Informe só a proposta; o sistema busca o " +
      "documento, os dados da Receita (CNPJ) e a categoria. ENTRADA: não cadastre cliente com os dados de quem " +
      "pagou — pergunte de quem é o pagamento; só com o usuário dizendo que quem pagou é o próprio cliente, NOVO, " +
      "use tipo='cliente'. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        proposta_id: { type: "string", description: "Id da proposta (de listar_propostas_de_lancamento)." },
        tipo: {
          type: "string", enum: ["fornecedor", "favorecido", "cliente"],
          description: "Saída: só se o usuário disser outro tipo que o sugerido. Entrada: obrigatório 'cliente', e só quando "
            + "o usuário disser que quem pagou é o próprio cliente, novo.",
        },
        tipo_de_favorecido: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
        nome: { type: "string", description: "Só se o usuário corrigir o nome (o nome da linha é lido do banco; nunca repita um nome mascarado com ***)." },
      },
      required: ["proposta_id"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    // O modelo vê o nome com o CPF mascarado: copiá-lo gravaria "***" no cadastro (revisão da leva 8, 23/10/2026).
    preValidar: (args) => String(args?.nome ?? "").includes("*")
      ? { error: "Este nome está mascarado (***): deixe o nome em branco (ele é lido da linha do extrato) ou use o nome que o usuário disser." }
      : null,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const { data: p, error: eProposta } = await ctx.admin.from("finance_review_queue")
        .select("id, kind, suggested_category, evidencia, bank_transactions!finance_review_queue_bank_transaction_id_fkey(counterparty_name, counterparty_document, description)")
        .eq("id", String(args.proposta_id)).maybeSingle();
      if (eProposta) return { error: `Não consegui ler a proposta: ${eProposta.message}` };
      if (!p) return { error: "Proposta não encontrada." };
      // Leva 8 (22/10/2026): numa ENTRADA, quem pagou quase nunca é um cliente novo — é o cônjuge, a empresa do
      // cliente, a marina. Cadastrar cliente com esses dados criava cadastro duplicado. Só com o "é cliente novo" dito.
      const recusaDaEntrada = recusaDeCadastroNaEntrada((p as any).kind, args.tipo);
      if (recusaDaEntrada) return recusaDaEntrada;
      const entrada = (p as any).kind === "create_receivable";
      // A sugestão de cadastro só vale na saída; na entrada o documento e o nome são os da linha do banco.
      const sugestao = entrada ? null : (p as any).evidencia?.cadastrar ?? null;
      const tx = (p as any).bank_transactions ?? {};
      const documento = String(sugestao?.documento ?? tx.counterparty_document ?? "").replace(/\D/g, "") || null;
      const tipo = String(args.tipo ?? sugestao?.tipo ?? (documento?.length === 14 ? "fornecedor" : "favorecido"));

      let receita: any = null;
      if (documento && documento.length === 14) {
        const r = await chamarFinanceReview(ctx, { action: "consult_document", documento });
        receita = (r as any)?.dados ?? null;
      }
      const nome = String(args.nome ?? receita?.razao_social ?? sugestao?.nome ?? tx.counterparty_name ?? "").trim();
      if (!nome) return { error: "O extrato não traz o nome. Pergunte ao usuário como cadastrar." };
      const categoriaDaLinha = (p as any).suggested_category && (p as any).suggested_category !== "Outras despesas"
        ? (p as any).suggested_category : null;

      const { data, error } = await ctx.sb.rpc("cadastrar_contraparte", {
        p_tipo: tipo,
        p_dados: {
          documento, nome, nome_fantasia: receita?.nome_fantasia ?? null,
          tipo_de_favorecido: tipo === "favorecido" ? (args.tipo_de_favorecido ?? "prestador") : null,
          categoria: tipo === "cliente" ? null : (receita?.categoria_sugerida ?? categoriaDaLinha),
          telefone: receita?.telefone ?? null, email: receita?.email ?? null,
          cep: receita?.cep ?? null, logradouro: receita?.logradouro ?? null, numero: receita?.numero ?? null,
          complemento: receita?.complemento ?? null, bairro: receita?.bairro ?? null,
          cidade: receita?.cidade ?? null, uf: receita?.uf ?? null,
          observacao: receita?.cnae_descricao ? `Atividade na Receita: ${receita.cnae_descricao}` : "Cadastrado pelo assistente a partir do extrato",
        },
        p_autor: ctx.userId || null,
      });
      if (error) return { error: error.message.replace(/^(P0001|42501|23514):\s*/, "") };
      return { ...(data as Record<string, unknown>), situacao_na_receita: receita?.situacao ?? null };
    },
  },

  // ── QUEM PAGA POR UM CLIENTE (leva 8, 22/10/2026) ───────────────────────────────
  // Ficam só pela rede (perfil-operacao.ts, SO_PELA_REDE): a lista é leitura e roda direto; guardar vira pendência
  // com o resumo resolvido (resumirGuardarPagador) e nunca roda sozinha (autonomy-policy.ts, NEVER_AUTONOMOUS).
  {
    name: "listar_pagadores_do_cliente",
    description:
      "Mostra quem costuma pagar por um cliente (cônjuge, empresa dele, parente, marina, seguradora), como está guardado " +
      "na ficha dele: nome, documento (CPF mascarado), relação, situação (proposto, confirmado, recusado, pausado), desde " +
      "quando e quem confirmou. Só confirmado vale: ele SUGERE o cliente nos próximos Pix, sempre pedindo o sim.",
    input_schema: {
      type: "object",
      properties: { client_id: { type: "string", description: "Id do cliente." } },
      required: ["client_id"],
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const id = String(args?.client_id ?? "").trim();
      if (!ehUuid(id)) return { error: "Informe o client_id do cliente (o id do cadastro, não o nome)." };
      const [cli, lidos] = await Promise.all([
        ctx.sb.from("clients").select("id, name").eq("id", id).maybeSingle(),
        ctx.sb.from("pagadores_do_cliente")
          .select("nome, documento, relacao, situacao, observacao, origem, proposto_em, confirmado_em, confirmado_por, decidido_motivo")
          .eq("client_id", id).order("proposto_em"),
      ]);
      // Leitura que falha diz que falhou: "ninguém paga por este cliente" por erro levaria a guardar de novo.
      if (lidos.error) return { error: `Não consegui ler quem paga por este cliente: ${lidos.error.message}` };
      if (cli.error) return { error: `Não consegui ler o cliente: ${cli.error.message}` };
      if (!cli.data) return { error: "Cliente não encontrado." };
      const linhas = (lidos.data ?? []) as Array<{
        nome: string; documento: string; relacao: string; situacao: string; observacao: string | null;
        proposto_em: string | null; confirmado_em: string | null; confirmado_por: string | null; decidido_motivo: string | null;
      }>;
      // Quem confirmou, pelo nome (só para ler: sem o nome, a linha continua certa).
      const ids = [...new Set(linhas.map((l) => l.confirmado_por).filter(Boolean))];
      const nomes = new Map<string, string>();
      if (ids.length) {
        const { data: us } = await ctx.sb.from("app_users").select("id, full_name").in("id", ids);
        for (const u of (us ?? []) as Array<{ id: string; full_name: string | null }>) if (u.full_name) nomes.set(u.id, u.full_name);
      }
      return {
        cliente: cli.data.name,
        // O nome do pagador vem do extrato e às vezes traz o CPF ("12345678901-MARIA…"): mascarado, como o documento
        // (revisão de 23/10/2026). A observação e o motivo são texto livre: a mesma máscara.
        pagadores: linhas.map((l) => ({
          nome: mascararCpfNoTexto(l.nome),
          documento: documentoMascarado(l.documento),
          relacao: ROTULO_DA_RELACAO[l.relacao as RelacaoDoPagador] ?? l.relacao,
          situacao: l.situacao,
          desde: l.proposto_em ? dataBr(l.proposto_em) : null,
          ...(l.confirmado_em
            ? { confirmado_em: dataBr(l.confirmado_em), confirmado_por: nomes.get(String(l.confirmado_por ?? "")) ?? null }
            : {}),
          ...(l.observacao ? { observacao: mascararCpfNoTexto(l.observacao) } : {}),
          ...(l.decidido_motivo ? { motivo: mascararCpfNoTexto(l.decidido_motivo) } : {}),
        })),
        total: linhas.length,
        lembrete: "Proposto ainda não vale: só o administrador confirma (na ficha do cliente). Confirmado só SUGERE o cliente "
          + "nos próximos Pix, sempre pedindo o sim — nunca dá baixa sozinho.",
      };
    },
  },

  {
    name: "guardar_pagador_do_cliente",
    description:
      "Guarda QUEM PAGA por um cliente (cônjuge, empresa dele, parente, marina, seguradora) a partir de uma ENTRADA do " +
      "extrato que essa pessoa pagou: os próximos Pix dela passam a SUGERIR o cliente, sempre pedindo o sim (nunca dão " +
      "baixa sozinhos). Use quando o usuário disser de quem é o pagamento e que essa pessoa costuma pagar por aquele cliente. " +
      "Informe o cliente (client_id), a entrada (proposta_id da fila ou bank_transaction_id) e a relação; o documento e o " +
      "nome de quem pagou o sistema tira da linha do banco. Administrador grava confirmado; financeiro grava proposto (falta o " +
      "sim do administrador). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "Id do cliente que recebeu o pagamento (o dono da dívida)." },
        proposta_id: { type: "string", description: "Id da entrada na fila (listar_propostas_de_lancamento)." },
        bank_transaction_id: { type: "string", description: "Ou o id da linha do extrato (entrada) que essa pessoa pagou." },
        relacao: {
          type: "string", enum: RELACOES_DO_PAGADOR,
          description: "Quem o pagador é para o cliente. Pergunte ao usuário se ele não disse.",
        },
        observacao: { type: "string", description: "Opcional: o que o usuário disse (ex.: \"esposa do Acrisio\")." },
      },
      required: ["client_id", "relacao"],
    },
    // Média: não move dinheiro, mas muda o que o sistema sugere para os próximos Pix — e é o SIM do dono.
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    preValidar: (args) => {
      const p = lerPedidoDoPagador(args);
      return "error" in p ? p : null;
    },
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const p = lerPedidoDoPagador(args);
      if ("error" in p) return p;
      const linha = await linhaDoPedido(ctx.sb, p);
      if ("error" in linha) return linha;
      // O documento e o nome de quem pagou NÃO vão daqui: a função tira da linha do banco. No painel ela usa auth.uid();
      // no WhatsApp (service role) o autor vai em p_autor, conferido como admin/financeiro (_autor_do_financeiro).
      const { data, error } = await ctx.sb.rpc("guardar_pagadores_do_cliente", {
        p_itens: [{
          client_id: p.clientId, bank_transaction_id: linha.id, relacao: p.relacao,
          ...(p.observacao ? { observacao: p.observacao } : {}), origem: "assistente",
        }],
        p_autor: ctx.userId || null,
      });
      if (error) return { error: mensagemDoBanco(error) };
      const r = (data ?? {}) as {
        ok?: boolean; message?: string;
        gravados?: Array<{ cliente?: string; nome?: string; relacao?: string; situacao?: string }>;
        recusados?: Array<{ motivo?: string }>;
      };
      // O nome de quem pagou (v_nome, do extrato) entra na mensagem e no aviso de regra antiga ("…as entradas de
      // 12345678901-MARIA passam a perguntar de quem é"): tudo que volta ao modelo sai com o CPF mascarado.
      if (!r.ok) return { error: mascararCpfNoTexto(r.recusados?.[0]?.motivo ?? r.message ?? "Nada foi guardado.") };
      const g = r.gravados?.[0] ?? {};
      // Confirmado: as entradas pendentes deste documento são refeitas na hora (o "Revisar a fila" da tela) e passam a
      // sugerir o cliente — sugerir, não aprovar.
      let refeitas: number | null = null;
      let aviso: string | undefined;
      if (g.situacao === "confirmado") {
        const efeito = await chamarFinanceReview(ctx, { action: "reclassify" }) as { atualizadas?: number; error?: string };
        if (efeito?.error) aviso = `Guardado, mas a fila não foi refeita agora (${efeito.error}): a varredura diária refaz.`;
        else refeitas = Number(efeito?.atualizadas ?? 0);
      }
      return {
        ok: true,
        message: mascararCpfNoTexto(r.message ?? null),
        quem_pagou: mascararCpfNoTexto(g.nome ?? null),
        cliente: g.cliente ?? null,
        relacao: ROTULO_DA_RELACAO[g.relacao as RelacaoDoPagador] ?? g.relacao ?? null,
        situacao: g.situacao ?? null,
        ...(refeitas !== null ? { propostas_reclassificadas: refeitas } : {}),
        ...(aviso ? { aviso } : {}),
        lembrete: g.situacao === "confirmado"
          ? "Os próximos Pix deste documento SUGEREM o cliente, com o motivo; cada um ainda espera o sim."
          : "Ficou proposto: só vale depois do sim do administrador.",
      };
    },
  },

  // ── CADASTRO DE FAVORECIDOS ───────────────────────────────────────────────────
  {
    name: "cadastrar_favorecido",
    description:
      "Cadastra quem recebe dinheiro sem ser fornecedor: sócio, funcionário, diarista, prestador ou " +
      "comissionado. Use ao lançar uma despesa de pró-labore para alguém que ainda não existe. " +
      "Também é a REGRA 'todo pagamento para Fulano é <categoria>': com categoria_padrao, os Pix para essa pessoa " +
      "chegam do banco já classificados nela (ex.: Eliane, que faz as refeições → prestador, Alimentação de campo). " +
      "Freelancer que recebe por DIA (diarista): use cadastrar_freelancer — esta aqui não cria a diária, e sem ela " +
      "o dia trabalhado não pode ser registrado.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
        documento: { type: "string", description: "CPF ou CNPJ que o usuário disser, só números. Se o CPF veio mascarado (***) da lista do extrato, use bank_transaction_id." },
        bank_transaction_id: { type: "string", description: "Opcional: o id da linha do extrato (de listar_transacoes_pendentes) — o CPF/CNPJ é lido do banco." },
        chave_pix: { type: "string" },
        percentual_comissao: { type: "number", description: "Só para comissionado." },
        categoria_padrao: { type: "string", description: "Categoria de despesa em que TODO pagamento a essa pessoa entra (ex.: Alimentação de campo)." },
      },
      required: ["nome", "tipo"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    // CPF mascarado (vindo da lista do extrato) nunca vira documento do favorecido (revisão da leva 8, 23/10/2026).
    preValidar: (args) => preValidarDocumento(args?.documento, args?.bank_transaction_id),
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const doc = await documentoDoFavorecido(args, ctx);
      if ("error" in doc) return doc;
      const cat = await categoriaValida(ctx, args.categoria_padrao, "payable");
      if (ehErro(cat)) return cat;
      const { data, error } = await ctx.sb.from("payees").insert({
        name: String(args.nome).trim(),
        kind: args.tipo,
        ...(cat ? { default_category: cat.nome } : {}),
        document: doc.documento,
        pix_key: args.chave_pix ?? null,
        commission_percentage: args.tipo === "comissionado" ? args.percentual_comissao ?? null : null,
        active: true,
      }).select("id").single();
      if (error) {
        if (/documento_unico|duplicate key/i.test(error.message)) {
          return { error: "Já existe um favorecido com este CPF/CNPJ." };
        }
        return { error: error.message };
      }
      return { ok: true, id: (data as any).id, nome: args.nome, tipo: args.tipo, ...(cat ? { categoria_padrao: cat.nome } : {}) };
    },
  },

  {
    name: "listar_favorecidos",
    description: "Lista sócios, funcionários, diaristas, prestadores e comissionados cadastrados.",
    input_schema: {
      type: "object",
      properties: {
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      let q = ctx.sb.from("payees")
        .select("id, name, kind, document, pix_key, commission_percentage")
        .eq("active", true).order("name");
      if (args.tipo) q = q.eq("kind", args.tipo);
      const { data, error } = await q;
      if (error) return { error: error.message };
      return { favorecidos: data ?? [], total: (data ?? []).length };
    },
  },

  // ── LEITURA DO RESULTADO ──────────────────────────────────────────────────────
  {
    name: "resultado_do_periodo",
    description:
      "Monta o resultado (DRE) de um ano ou mês: receita, custo dos serviços, despesas operacionais, " +
      "resultado financeiro e o que ficou fora do resultado. Use para 'como fechou julho', " +
      "'quanto gastamos com peças este ano', 'estamos no lucro?'.",
    input_schema: {
      type: "object",
      properties: {
        ano: { type: "number" },
        mes: { type: "number", description: "1 a 12. Omita para o ano inteiro." },
      },
      required: ["ano"],
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const ano = Number(args.ano);
      const mes = args.mes ? Number(args.mes) : null;
      if (mes !== null && (mes < 1 || mes > 12)) {
        return { error: "Mês precisa estar entre 1 e 12." };
      }

      // Último dia do mês calculado em UTC. `new Date(ano, mes, 0).toISOString()` usa o
      // fuso LOCAL para montar e converte para UTC ao serializar — num servidor a leste de
      // Greenwich isso volta um dia e o último dia do mês fica de fora do relatório.
      const ultimoDia = mes ? new Date(Date.UTC(ano, mes, 0)).getUTCDate() : 31;
      const de = mes ? `${ano}-${String(mes).padStart(2, "0")}-01` : `${ano}-01-01`;
      const ate = mes ? `${ano}-${String(mes).padStart(2, "0")}-${ultimoDia}` : `${ano}-12-31`;

      // Leitura que falha lança (o assistente diz que a consulta falhou): engolida, virava receita
      // ou despesa 0 e um lucro ou prejuízo falso. Em páginas: o ano passa de 1.000 linhas e o
      // servidor corta em silêncio (02/10/2026).
      const lerTudo = async (montar: () => any): Promise<any[]> => {
        const todas: any[] = [];
        for (let i = 0; i < 50000; i += 1000) {
          const { data, error } = await montar().order("id").range(i, i + 999);
          if (error) throw error;
          todas.push(...(data ?? []));
          if ((data ?? []).length < 1000) break;
        }
        return todas;
      };
      const catsRes = await ctx.sb.from("financial_categories").select("name, type, dre_group");
      if (catsRes.error) throw catsRes.error;
      const [paysData, recsData] = await Promise.all([
        // Despesa cancelada não entra no resultado — mesma regra do DRE da tela.
        lerTudo(() => ctx.sb.from("payables").select("id, amount, expense_category").neq("status", "cancelled").gte("issue_date", de).lte("issue_date", ate)),
        lerTudo(() => ctx.sb.from("receivables").select("id, amount, category, status").gte("issue_date", de).lte("issue_date", ate)),
      ]);
      const cats = { data: catsRes.data };
      const pays = { data: paysData };
      const recs = { data: recsData };

      const grupoDe = new Map<string, string>();
      for (const c of (cats.data ?? []) as any[]) {
        if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
      }

      const total = (g: string) =>
        ((pays.data ?? []) as any[])
          .filter((p) => grupoDe.get(`payable:${p.expense_category}`) === g)
          .reduce((s, p) => s + Number(p.amount), 0);

      const receita = ((recs.data ?? []) as any[])
        .filter((r) => r.status !== "cancelled")
        .reduce((s, r) => s + Number(r.amount), 0);

      const custo = total("custo_direto");
      const despesa = total("despesa_operacional");
      const financeiro = total("financeiro");
      const foraDoResultado = total("nao_operacional");

      // Este número engana quando a receita ainda não foi conciliada — a caixa de entrada
      // lança despesa sozinha e receita nunca, então o resultado nasce pessimista.
      const { count: entradasPendentes, error: entErr } = await ctx.sb
        .from("bank_transactions")
        .select("id", { count: "exact", head: true })
        .eq("transaction_type", "credit").eq("reconciled", false).eq("source_type", "bank")
        .gte("transaction_date", de).lte("transaction_date", ate);
      if (entErr) throw entErr;
      // E do lado da despesa: saídas ainda sem lançamento, inclusive compras no cartão que o banco
      // ainda não fechou (setembro/2026 tinha 35, R$ 2.547,49, fora do resultado).
      const saidas = await lerTudo(() => ctx.sb.from("bank_transactions")
        .select("id, amount, tx_status").eq("transaction_type", "debit").eq("reconciled", false).is("dismissed_kind", null)
        .gte("transaction_date", de).lte("transaction_date", ate));
      const saidasSemLancamento = saidas.length;
      const valorSemLancamento = Math.round(saidas.reduce((s, t) => s + Math.abs(Number(t.amount)), 0) * 100) / 100;
      const pendentesNoCartao = saidas.filter((t) => String(t.tx_status ?? "").toUpperCase() === "PENDING").length;

      return {
        periodo: mes ? `${String(mes).padStart(2, "0")}/${ano}` : String(ano),
        receita,
        custo_dos_servicos: custo,
        lucro_bruto: receita - custo,
        despesas_operacionais: despesa,
        resultado_operacional: receita - custo - despesa,
        resultado_financeiro: financeiro,
        resultado_do_periodo: receita - custo - despesa - financeiro,
        fora_do_resultado: foraDoResultado,
        aviso: (entradasPendentes ?? 0) > 0
          ? `ATENÇÃO: ${entradasPendentes} entrada(s) do banco ainda não viraram receita lançada. ` +
            "O resultado acima está incompleto do lado da receita e parece pior do que é. " +
            "Avise isto ao usuário antes de comentar o número."
          : null,
        aviso_despesa: saidasSemLancamento > 0
          ? `ATENÇÃO: ${saidasSemLancamento} saída(s) do banco (R$ ${valorSemLancamento.toFixed(2).replace(".", ",")}) ainda não viraram despesa lançada` +
            (pendentesNoCartao ? `, ${pendentesNoCartao} delas compras no cartão que o banco ainda não fechou` : "") +
            ". A despesa acima está incompleta e o resultado parece melhor do que é. Avise isto ao usuário."
          : null,
      };
    },
  },
];
