// Pagamentos da semana (etapa 2 do controle financeiro, 24/11/2026) — o que pagar, em ordem de prioridade, com o saldo.
//
// A lista e a ordem vêm prontas do banco (pagamentos_da_semana, migration 20270224100000): a manhã do WhatsApp e a
// ferramenta do assistente (list_payables_due) leem a MESMA função, então não têm como discordar. Aqui fica só o texto,
// puro e testado sem rede, e o leitor da manhã, que nunca lança.
//
// Decisões do dono (23/11/2026): ordem pela consequência do atraso (1A); a lista na manhã do 1º dia útil da semana e as
// vencidas todo dia útil (2A); só contas a pagar nesta fatia (3A); o que o sócio pagou do bolso é a empresa devendo a
// ele — linha à parte, fora da fila (4).
//
// As linhas NÃO levam letra nem número: as letras são dos itens da manhã (*A feito*) e "1" é um "sim". O dono responde
// pelo nome ("paguei a Unifique") e o assistente usa as ferramentas de sempre, com a confirmação de sempre. Nada aqui
// paga nem baixa conta.
import { brl, ddmm, diasEntre, umaLinha } from "../secretario/base.ts";
import { diasUteisDaSemana, ehDiaUtilDaTarde } from "../secretario/turno.ts";

export const RPC_DOS_PAGAMENTOS = "pagamentos_da_semana";
export const CHAVE_DOS_PAGAMENTOS = "pagamentos_semana_modo";

/** Quantas contas a lista da manhã mostra por extenso (o resto vira "e mais N"). */
export const MAX_DE_LINHAS = 6;
/** Saldo informado pelo banco há mais dias do que isto sai com a data ao lado. */
const DIAS_DE_SALDO_FRESCO = 2;

export type GrupoDePagamento = 1 | 2 | 3 | 4;

/** Como cada grupo se chama para o dono e para o assistente. */
export const NOME_DO_GRUPO: Record<GrupoDePagamento, string> = {
  1: "pessoas e impostos",
  2: "serviço que corta",
  3: "fornecedor com boleto",
  4: "o resto",
};

export interface ContaDaSemana {
  id: string;
  nome: string;
  valor: number;
  vencimento: string;
  vencida: boolean;
  grupo: GrupoDePagamento;
  /** sem categoria e sem resposta do dono: o grupo é palpite */
  aDefinir: boolean;
  categoria: string | null;
  boletoLinha: string | null;
}

export interface PagamentosDaSemana {
  hoje: string;
  ate: string;
  /** soma do último saldo que cada banco informou; null = nenhum banco informou */
  saldoNoBanco: number | null;
  /** o mais antigo desses saldos (dia de Brasília) */
  saldoEm: string | null;
  /** já na ordem em que se paga */
  contas: ContaDaSemana[];
  soma: number;
  vencido: { n: number; total: number };
  /** o que a empresa deve aos sócios (pago do bolso) — fora da fila */
  reembolsos: { n: number; total: number };
}

const numero = (v: unknown): number => {
  const n = Number(v);
  if (!Number.isFinite(n)) throw new Error("pagamentos_da_semana respondeu um valor que não é número");
  return n;
};

const dia = (v: unknown): string => {
  const s = String(v ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new Error("pagamentos_da_semana respondeu uma data fora da forma");
  return s;
};

/** O instante do banco → o dia de Brasília (UTC−3, sem horário de verão). */
function diaDeBrasilia(v: unknown): string | null {
  const ms = typeof v === "string" ? Date.parse(v) : NaN;
  return Number.isNaN(ms) ? null : new Date(ms - 3 * 3_600_000).toISOString().slice(0, 10);
}

/** A resposta da RPC → a forma tipada. Forma errada LANÇA (quem lê decide o que fazer com o erro). */
export function pagamentosDaResposta(data: unknown): PagamentosDaSemana {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("pagamentos_da_semana respondeu fora da forma");
  const d = data as Record<string, unknown>;
  if (!Array.isArray(d.contas)) throw new Error("pagamentos_da_semana respondeu sem a lista de contas");
  const par = (v: unknown) => {
    const o = (v ?? {}) as { n?: unknown; total?: unknown };
    return { n: numero(o.n ?? 0), total: numero(o.total ?? 0) };
  };
  return {
    hoje: dia(d.hoje),
    ate: dia(d.ate),
    saldoNoBanco: d.saldo_no_banco === null || d.saldo_no_banco === undefined ? null : numero(d.saldo_no_banco),
    saldoEm: diaDeBrasilia(d.saldo_em),
    contas: d.contas.map((c) => {
      const x = (c ?? {}) as Record<string, unknown>;
      const grupo = numero(x.grupo);
      if (typeof x.id !== "string" || !x.id) throw new Error("pagamentos_da_semana respondeu uma conta sem id");
      if (![1, 2, 3, 4].includes(grupo)) throw new Error("pagamentos_da_semana respondeu um grupo desconhecido");
      return {
        id: x.id,
        nome: String(x.nome ?? "conta"),
        valor: numero(x.valor),
        vencimento: dia(x.vencimento),
        vencida: x.vencida === true,
        grupo: grupo as GrupoDePagamento,
        aDefinir: x.a_definir === true,
        categoria: typeof x.categoria === "string" && x.categoria.trim() ? x.categoria : null,
        boletoLinha: typeof x.boleto_linha === "string" && x.boleto_linha.trim() ? x.boleto_linha : null,
      };
    }),
    soma: numero(d.soma ?? 0),
    vencido: par(d.vencido),
    reembolsos: par(d.reembolsos),
  };
}

const centavos = (v: number) => Math.round(v * 100) / 100;

function quando(c: ContaDaSemana, hoje: string): string {
  if (c.vencimento === hoje) return "vence hoje";
  return `${c.vencida ? "venceu" : "vence"} ${ddmm(c.vencimento)}`;
}

/** "no banco: R$ 1.476,13" (com a data quando o saldo é velho); null = nenhum banco informou saldo. */
function textoDoSaldo(p: PagamentosDaSemana): string | null {
  if (p.saldoNoBanco === null) return null;
  const velho = p.saldoEm !== null && diasEntre(p.saldoEm, p.hoje) > DIAS_DE_SALDO_FRESCO;
  return `no banco: ${brl(p.saldoNoBanco)}${velho ? ` (saldo de ${ddmm(p.saldoEm)})` : ""}`;
}

/** O primeiro nome de quem cobra, para os exemplos de resposta ("paguei a Unifique"). */
function primeiroNome(c: ContaDaSemana): string {
  return umaLinha(c.nome, 40).split(/\s+/)[0] || "conta";
}

/**
 * O bloco da semana (1º dia útil): a fila na ordem de pagar, a soma contra o saldo, o que a empresa deve ao sócio e, uma
 * vez por fornecedor, a pergunta do grupo. Sem conta na fila = null (a manhã sai como antes).
 */
export function blocoDaSemana(p: PagamentosDaSemana): string | null {
  if (!p.contas.length) return null;
  const saldo = textoDoSaldo(p);
  const linhas: string[] = [`*Pagamentos da semana*${saldo ? ` — ${saldo}` : ""}`, "Na ordem em que eu pagaria:"];
  const mostradas = p.contas.slice(0, MAX_DE_LINHAS);
  for (const c of mostradas) linhas.push(`• ${umaLinha(c.nome, 28)} — ${brl(c.valor)} (${quando(c, p.hoje)})`);
  const resto = p.contas.slice(MAX_DE_LINHAS);
  if (resto.length) linhas.push(`• e mais ${resto.length} (${brl(centavos(resto.reduce((s, c) => s + c.valor, 0)))})`);
  if (p.saldoNoBanco === null) linhas.push(`Soma ${brl(p.soma)}.`);
  else {
    const falta = centavos(p.soma - p.saldoNoBanco);
    linhas.push(falta > 0 ? `Soma ${brl(p.soma)}: faltam ${brl(falta)} no banco.` : `Soma ${brl(p.soma)}: o saldo cobre.`);
  }
  if (p.reembolsos.n > 0) {
    linhas.push(`Fora da fila: a empresa te deve ${brl(p.reembolsos.total)} (${p.reembolsos.n === 1 ? "1 reembolso" : `${p.reembolsos.n} reembolsos`}).`);
  }
  const semGrupo = [...new Set(p.contas.filter((c) => c.aDefinir).map((c) => umaLinha(c.nome, 24)))];
  if (semGrupo.length) {
    const nomes = semGrupo.slice(0, 3).join(", ") + (semGrupo.length > 3 ? ` e mais ${semGrupo.length - 3}` : "");
    linhas.push(`Ainda não sei a prioridade de ${nomes}: é imposto ou pessoa, serviço que corta, ou fornecedor comum?`);
  }
  const exemplo = primeiroNome(p.contas[0]);
  const comBoleto = p.contas.find((c) => c.boletoLinha);
  linhas.push(`Pagou alguma? Me diga qual (*paguei ${exemplo}*).${comBoleto ? ` Para o código do boleto: *boleto ${primeiroNome(comBoleto)}*.` : ""}`);
  return linhas.join("\n");
}

/** A linha dos outros dias úteis: só o que já venceu, com o primeiro da fila. Sem vencida = null. */
export function linhaDasVencidas(p: PagamentosDaSemana): string | null {
  const vencidas = p.contas.filter((c) => c.vencida);
  if (!vencidas.length) return null;
  const primeira = vencidas[0];
  if (vencidas.length === 1) {
    return `A pagar vencido: ${umaLinha(primeira.nome, 28)}, ${brl(primeira.valor)} (venceu ${ddmm(primeira.vencimento)}).`;
  }
  const total = centavos(vencidas.reduce((s, c) => s + c.valor, 0));
  return `A pagar vencido: ${brl(total)} (${vencidas.length} contas). Primeiro da fila: ${umaLinha(primeira.nome, 28)}, ${brl(primeira.valor)}. ` +
    "Peça *pagamentos da semana* para ver tudo.";
}

/**
 * O que a manhã de `hoje` leva: no 1º dia útil da semana (seg–sex, sem feriado) o bloco inteiro; nos outros dias úteis a
 * linha das vencidas; sábado, domingo e feriado, nada (banco fechado para boleto).
 */
export function pagamentosDaManha(p: PagamentosDaSemana | null | undefined, hoje: string): string | null {
  if (!p || !ehDiaUtilDaTarde(hoje)) return null;
  return diasUteisDaSemana(hoje)[0] === hoje ? blocoDaSemana(p) : linhaDasVencidas(p);
}

/** O bloco no fim da manhã. Sem bloco = o texto de antes, byte a byte. */
export function comPagamentos(texto: string, bloco: string | null | undefined): string {
  return bloco ? `${texto}\n\n${bloco}` : texto;
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/**
 * A fila para a ferramenta do assistente (list_payables_due), até o dia `ate`. null = a função ainda não está publicada
 * (ou não respondeu nada): quem chama mostra a lista de antes. Qualquer outro erro LANÇA — leitura que engole erro vira
 * "não há conta" na boca do assistente.
 */
export async function filaDePagamentos(admin: Admin, ate: string): Promise<PagamentosDaSemana | null> {
  if (typeof admin?.rpc !== "function") return null;
  const { data, error } = await admin.rpc(RPC_DOS_PAGAMENTOS, { p_ate: ate });
  if (error) {
    const codigo = String((error as { code?: unknown })?.code ?? "");
    if (codigo === "PGRST202" || codigo === "42883") return null;
    throw new Error(`Não consegui ler a ordem de pagamento: ${(error as { message?: string })?.message ?? codigo}`);
  }
  if (data === null || data === undefined) return null;
  return pagamentosDaResposta(data);
}

/**
 * O que o dono lê antes do "sim" de definir_prioridade_de_pagamento: o fornecedor pelo nome e o grupo por extenso.
 * Conta que não existe ou sem quem cobra = linha "⚠️ …" (vira recusa, não pedido de confirmação).
 */
export async function resumirPrioridade(admin: Admin, args: Record<string, unknown>): Promise<string | null> {
  const grupo = Number(args.grupo) as GrupoDePagamento;
  if (!NOME_DO_GRUPO[grupo]) return "⚠️ Grupo de prioridade inválido: use 1, 2, 3 ou 4.";
  const { data, error } = await admin.from("payables").select("supplier_name, suppliers(name)").eq("id", String(args.payable_id ?? "")).maybeSingle();
  if (error) return null;
  if (!data) return "⚠️ Não achei essa conta a pagar.";
  const nome = String((data.suppliers as { name?: string } | null)?.name || data.supplier_name || "").trim();
  if (!nome) return "⚠️ Essa conta não tem fornecedor nem nome de quem cobra: não há a quem ligar a prioridade.";
  return `Prioridade de pagamento de *${umaLinha(nome, 60)}*: grupo ${grupo} — ${NOME_DO_GRUPO[grupo]}.\n` +
    "Vale para as contas dele de agora e as próximas. Não paga nem altera conta.";
}

/**
 * Lê a fila para a manhã. Nunca lança: chave desligada, função ainda não publicada ou qualquer erro = null (a manhã sai
 * como antes; o erro vai só para o log, com o código).
 */
export async function lerPagamentosDaManha(admin: Admin, hoje: string): Promise<PagamentosDaSemana | null> {
  try {
    const { data: chave } = await admin.from("app_settings").select("value").eq("key", CHAVE_DOS_PAGAMENTOS).maybeSingle();
    if (String(chave?.value ?? "").trim().replace(/^"(.*)"$/, "$1").toLowerCase() === "desligado") return null;
    const { data, error } = await admin.rpc(RPC_DOS_PAGAMENTOS, { p_hoje: hoje });
    if (error) throw error;
    return pagamentosDaResposta(data);
  } catch (e) {
    const codigo = String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
    // a função ainda não existe (edge publicada antes da migration): silêncio
    if (codigo !== "PGRST202" && codigo !== "42883") {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", secretario: "pagamentos_falhou", codigo }));
    }
    return null;
  }
}
