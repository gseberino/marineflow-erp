// A fatura do cartão na fila de pagamentos da semana (24/11/2026).
//
// O que isto É: um aviso de saída de caixa, calculado na leitura. O que NÃO é: conta a pagar. A despesa do cartão já é
// reconhecida compra a compra, e o pagamento da fatura entra sozinho pelo extrato; criar conta a pagar para a fatura
// contaria o mesmo dinheiro três vezes. Nada aqui grava, paga nem baixa.
//
// De onde vem cada coisa (medido em 24/11/2026, ver _shared/banking/fatura-do-cartao.ts):
//   · o VENCIMENTO é do banco: o dia em que cada cartão fecha e vence sai das faturas que o banco emitiu
//     (cartao_faturas_do_banco). Deduzir do histórico errava o C6 em um mês. O fechamento da fatura que o banco ainda
//     não publicou é projetado ("por volta de");
//   · o VALOR é estimado: a última fatura que o banco informou, mais o que o cartão cobrou, menos o que foi pago desde
//     então. O banco só publica o total no dia do vencimento, tarde demais para avisar. Erro medido: uns R$ 300 por
//     fatura — o texto tem de dizer "cerca de";
//   · o pagamento de ontem, que o cartão só mostra no dia seguinte, é lido da conta corrente.
import {
  cartaoDoPagamento, comPagamentosEmTransito, DIAS_EM_TRANSITO, faturasPeloBanco, somaEmTransito, somarDias,
  type CartaoConhecido, type DebitoDaConta, type FaturaInformada, type LinhaDoCartao, type PagamentoPelaConta,
} from "../banking/fatura-do-cartao.ts";

/** `app_settings.pagamentos_cartao_modo = 'desligado'` tira o cartão da fila (ausente = ligado). */
export const CHAVE_DOS_CARTOES = "pagamentos_cartao_modo";
/** Quanto do extrato do cartão se lê: cobre com folga da última fatura do banco até hoje (no máximo 3 ciclos). */
export const DIAS_DE_EXTRATO = 200;
/** Cartão sem nenhuma linha há mais que isto não está em uso: não entra nem gera aviso. */
const DIAS_DE_CARTAO_EM_USO = 60;

export interface CartaoNaFila {
  /** "C6", "Nubank" */
  cartao: string;
  /** o que falta pagar desta fatura (0 = coberta) — estimado pelo extrato */
  valor: number;
  /** quanto a fatura soma (a fechada: no fechamento; a aberta: até agora) */
  total: number;
  /** o que já foi pago dela (a fechada: desde o fechamento; a aberta: adiantado) */
  pago: number;
  /** pelo calendário do banco */
  vencimento: string;
  fechamento: string;
  situacao: "fechada" | "aberta";
  /** o vencimento passou e o extrato não mostra pagamento que cubra */
  vencida: boolean;
  /** 'banco' = o total é o que o banco informou; 'extrato' = estimado */
  origem: "banco" | "extrato";
}

export interface CartoesDaSemana {
  /** em ordem de vencimento */
  faturas: CartaoNaFila[];
  /** cartão que ficou de fora e por quê */
  avisos: string[];
  /** pagamentos que já saíram da conta e o cartão ainda não mostrou — já contados */
  emTransito: number;
}

export interface LinhaLida extends LinhaDoCartao {
  bank_connection_id: string | null;
}

export interface DebitoLido extends DebitoDaConta {
  dismissed_kind?: string | null;
}

export interface FaturaLida extends FaturaInformada {
  bank_connection_id: string | null;
}

const ddmm = (data: string) => `${data.slice(8, 10)}/${data.slice(5, 7)}`;

/** "C6 - Conta PJ HBR" → "C6"; "Nubank PJ HBR" → "Nubank". O rótulo é da conexão (conta e cartão dividem a mesma). */
export function nomeDoCartao(rotulo: string | null | undefined): string {
  const primeiro = String(rotulo ?? "").trim().split(/\s+-\s+|\s+/)[0] ?? "";
  return primeiro.slice(0, 20) || "Cartão";
}

/**
 * As faturas de cada cartão, a partir do que já foi lido. Pura.
 * `linhas`: o extrato dos cartões; `debitos`: as saídas recentes das contas correntes; `rotulos`: o nome de cada
 * conexão; `doBanco`: as faturas que o banco emitiu.
 */
export function cartoesDoExtrato(
  linhas: LinhaLida[],
  debitos: DebitoLido[],
  rotulos: Map<string, string>,
  doBanco: FaturaLida[],
  hoje: string,
): CartoesDaSemana {
  const porConexao = new Map<string, LinhaLida[]>();
  for (const l of linhas) {
    if (!l.bank_connection_id) continue;
    porConexao.set(l.bank_connection_id, [...(porConexao.get(l.bank_connection_id) ?? []), l]);
  }
  const emUso = somarDias(hoje, -DIAS_DE_CARTAO_EM_USO);
  const cartoes: CartaoConhecido[] = [...porConexao.entries()]
    .filter(([, ls]) => ls.some((l) => String(l.transaction_date).slice(0, 10) >= emUso))
    .map(([conexao]) => ({ conexao, rotulo: rotulos.get(conexao) ?? "" }));

  const pelaConta = new Map<string, PagamentoPelaConta[]>();
  for (const d of debitos) {
    if (d.dismissed_kind === "duplicata") continue;
    const conexao = cartaoDoPagamento(d, cartoes);
    if (conexao) pelaConta.set(conexao, [...(pelaConta.get(conexao) ?? []), { transaction_date: d.transaction_date, amount: d.amount }]);
  }

  const faturas: CartaoNaFila[] = [];
  const avisos: string[] = [];
  let emTransito = 0;
  for (const { conexao, rotulo } of cartoes) {
    const nome = nomeDoCartao(rotulo);
    const informadas = doBanco.filter((f) => f.bank_connection_id === conexao);
    const doCartao = comPagamentosEmTransito(porConexao.get(conexao) ?? [], pelaConta.get(conexao) ?? [], hoje);
    const r = faturasPeloBanco(nome, doCartao, informadas, hoje);
    if (!r.ancora) {
      avisos.push(`Cartão ${nome}: ainda não tenho as faturas do banco; ficou de fora.`);
      continue;
    }
    if (r.fechamentosSemOBanco > 0 && r.faturas.length === 0) {
      avisos.push(`Cartão ${nome}: o banco não informa fatura desde a que fechou em ${ddmm(r.ancora.fechamento)}; ficou de fora.`);
      continue;
    }
    emTransito += somaEmTransito(doCartao);
    for (const f of r.faturas) {
      faturas.push({
        cartao: nome, valor: f.valor, total: f.total, pago: f.pago, vencimento: f.vencimento, fechamento: f.fechamento,
        situacao: f.situacao, vencida: f.vencida, origem: f.origem,
      });
    }
  }
  faturas.sort((a, b) => a.vencimento.localeCompare(b.vencimento) || a.cartao.localeCompare(b.cartao));
  return { faturas, avisos, emTransito: Math.round(emTransito * 100) / 100 };
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Lê tudo, em páginas: o servidor corta em 1.000 linhas sem avisar, e extrato cortado muda a conta calado. */
async function emPaginas<T>(pagina: (de: number, ate: number) => PromiseLike<{ data: unknown; error: unknown }>): Promise<T[]> {
  const todas: T[] = [];
  for (let de = 0; de < 20_000; de += 1000) {
    const { data, error } = await pagina(de, de + 999);
    if (error) throw error;
    const lote = (data ?? []) as T[];
    todas.push(...lote);
    if (lote.length < 1000) break;
  }
  return todas;
}

/**
 * As faturas dos cartões para a fila. LANÇA em erro de leitura: quem chama decide (a manhã segue sem o cartão; o
 * assistente diz que não conseguiu ler). Chave desligada = sem cartão, sem erro.
 */
export async function lerCartoes(admin: Admin, hoje: string): Promise<CartoesDaSemana> {
  const vazio: CartoesDaSemana = { faturas: [], avisos: [], emTransito: 0 };
  const { data: chave, error: erroDaChave } = await admin.from("app_settings").select("value").eq("key", CHAVE_DOS_CARTOES).maybeSingle();
  if (erroDaChave) throw erroDaChave;
  if (String(chave?.value ?? "").trim().replace(/^"(.*)"$/, "$1").toLowerCase() === "desligado") return vazio;

  const linhas = await emPaginas<LinhaLida>((de, ate) =>
    admin.from("bank_transactions")
      .select("id, bank_connection_id, transaction_date, amount, transaction_type, description, bill_id, dismissed_kind, import_batch_id, tx_status")
      .eq("source_type", "credit_card")
      .gte("transaction_date", somarDias(hoje, -DIAS_DE_EXTRATO))
      .order("transaction_date").order("id").range(de, ate)
  );
  if (linhas.length === 0) return vazio;

  const debitos = await emPaginas<DebitoLido>((de, ate) =>
    admin.from("bank_transactions")
      .select("id, bank_connection_id, transaction_date, amount, description, counterparty_name, dismissed_kind")
      .eq("source_type", "bank").eq("transaction_type", "debit")
      .gte("transaction_date", somarDias(hoje, -DIAS_EM_TRANSITO - 1))
      .order("transaction_date").order("id").range(de, ate)
  );

  const doBanco = await emPaginas<FaturaLida>((de, ate) =>
    admin.from("cartao_faturas_do_banco")
      .select("bill_id, bank_connection_id, fechamento, vencimento, total")
      .order("bill_id").range(de, ate)
  );

  const { data: conexoes, error: erroDasConexoes } = await admin.from("bank_connections").select("id, label");
  if (erroDasConexoes) throw erroDasConexoes;
  const rotulos = new Map<string, string>(((conexoes ?? []) as Array<{ id: string; label: string | null }>).map((c) => [c.id, c.label ?? ""]));

  return cartoesDoExtrato(linhas, debitos, rotulos, doBanco, hoje);
}
