// O lembrete INDIVIDUAL de cobrança pelo assistente (send_collection_reminder) — a conferência, o cartão do "sim" e o
// retrato (25/11/2026). A tool mora em whatsapp.ts; as partes que leem e conferem moram aqui, para o cartão
// (buildPendingSummary), o retrato e o envio perguntarem a MESMA coisa.
//
// O defeito que isto conserta. Até 25/11/2026 o lembrete lia o valor e o vencimento da COBRANÇA (collections.amount e
// due_date). Medido em produção em 24/11/2026: em 4 de 5 cobranças abertas esses dois campos divergiam da conta a receber —
// a conta muda quando a OS é editada ou recebe pagamento parcial, e a cobrança fica com o valor antigo. O cliente recebia
// o valor antigo, com a data em ISO ("com vencimento em 2026-07-22"), e o cartão do "sim" era o genérico: não mostrava
// o texto, nem o número, nem o valor conferido.
//
// A verdade é a CONTA (receivables): o saldo pela regra pura saldoDaConta (_shared/receivables/cobrar-juntas.ts, a mesma
// da tela e do cobrar_juntas) e o vencimento da conta. Cobrança SEM conta (avulsa, ou a "Total" da OS sem conta a
// receber) não tem outra fonte: segue com o valor e o vencimento da própria cobrança, como sempre foi — a tela e
// list_pending_collections também só têm esses dois campos para ela (em 25/11/2026 não havia nenhuma aberta assim em
// produção: 5 abertas, todas com conta).
//
// O texto padrão ao cliente NÃO mudou, fora a data, que agora sai em dd/mm/aaaa. custom_message continua sendo o texto
// inteiro. As travas são as de sempre, na ordem de sempre: cobrança paga ou cancelada, (novo) conta paga, cancelada ou sem
// saldo, piso de materialidade — agora comparado com o valor conferido —, entrada do cliente esperando no Extrato,
// opt-out, cadastro genérico sem contato próprio e telefone.
//
// Sempre com o "sim" do dono, por texto: o cartão mostra quem recebe, o número inteiro, o valor e o vencimento
// conferidos, o que a cobrança guardava (quando diverge) e a mensagem EXATA. Trava vira uma linha "⚠️ …" (recusa, sem
// pendência — RESUMO_QUE_RESOLVE em agent.ts). O "sim" é sobre o retrato (cobrança, telefone, valor, vencimento e texto):
// mudou até o "sim", não envia.
import type { Role, ToolCtx } from "./registry.ts";
import { emReais } from "./agrupar-orcamentos.ts";
import { pixEsperandoNoExtrato } from "./pix-esperando.ts";
import { telefoneLegivel, telefoneParaEnvio } from "./agendamento.ts";
import { RECUSA_CLIENTE_FINAL } from "../comms/compliance-guard.ts";
import { chaveDeEnvio, diaLocal, situacaoDaReserva } from "../../whatsapp/idempotencia.ts";
import { saldoDaConta } from "../../receivables/cobrar-juntas.ts";

/**
 * Quem manda lembrete de cobrança (revisão de 25/11/2026): administrador e financeiro, como o cobrar_juntas e a tela
 * (dono, 20/11/2026: "Só admin e financeiro" mexem em cobrança). O cartão agora mostra o saldo da conta e o número do
 * cliente, lidos com a chave de serviço — e o vendedor nem lê cobranças nem contas pela RLS: o "sim" dele recusaria.
 */
export const CARGOS_DO_LEMBRETE: Role[] = ["admin", "financial"];
export const SEM_CARGO_DO_LEMBRETE = "Só administrador ou financeiro envia lembrete de cobrança.";

/** O relógio do lembrete (hoje, os dias de atraso, a chave do dia e o horário do portão) — os testes trocam. */
export const relogioDoLembrete = { agora: () => new Date() };

/** Pendência sem retrato (não deu para conferir quando o pedido nasceu, ou é de antes de 25/11/2026): não envia. */
export const SEM_RETRATO_DO_LEMBRETE =
  "Nada foi enviado: não consegui conferir a cobrança quando o pedido foi feito. Peça de novo que eu confiro e mostro a mensagem.";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NAO_ACHEI =
  "Cobrança não encontrada. Passe o id da cobrança (list_pending_collections), não o da conta a receber nem o número da OS.";

const centavos = (v: unknown): number => Math.round((Number(v) || 0) * 100);
const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;
/** "2026-07-22" (ou o começo de um instante) → "2026-07-22"; "" se não é data. */
const diaDe = (d: unknown): string => String(d ?? "").match(/^\d{4}-\d{2}-\d{2}/)?.[0] ?? "";
/** "2026-07-22" → "22/07/2026" sem passar por fuso (due_date é data, não instante). */
export function dataDoLembrete(d: unknown): string {
  const m = String(d ?? "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}

/** Guarda de tipo: a recusa de negócio do montarLembreteDeCobranca (o tsc do app roda sem strictNullChecks; ver ehErro em caixa.ts). */
export function ehErro(x: unknown): x is { error: string } {
  return !!x && typeof x === "object" && "error" in x;
}

// ── leitura ──────────────────────────────────────────────────────────────────────────────────

interface CobrancaLida {
  id: string;
  amount: number | string | null;
  due_date: string | null;
  contact_whatsapp: string | null;
  phone: string | null;
  contact_name: string | null;
  client_id: string | null;
  description: string | null;
  status: string | null;
  receivable_id: string | null;
  last_auto_sent_at?: string | null;
}
const COLUNAS_DA_COBRANCA = "id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, description, status, receivable_id, last_auto_sent_at";

interface ContaLida {
  id: string;
  service_order_id?: string | null;
  amount: number | null;
  paid_amount: number | null;
  balance_amount: number | null;
  status: string | null;
  due_date: string | null;
}
const COLUNAS_DA_CONTA = "id, service_order_id, amount, paid_amount, balance_amount, status, due_date";

interface ClienteLido {
  whatsapp: string | null;
  phone: string | null;
  name: string | null;
  display_name: string | null;
  opt_out_whatsapp: boolean | null;
  generico: boolean | null;
}
const COLUNAS_DO_CLIENTE = "whatsapp, phone, name, display_name, opt_out_whatsapp, generico";

/** O lembrete resolvido: o que o cartão mostra, o retrato guarda e o envio manda. */
export interface LembreteDeCobranca {
  cobranca: CobrancaLida;
  /** A conta a receber da cobrança; null = cobrança sem conta (avulsa, ou a "Total" da OS sem conta). */
  conta: ContaLida | null;
  cliente: ClienteLido | null;
  /** O valor conferido: o saldo da conta; sem conta, o valor da cobrança. */
  valor: number;
  /** O vencimento conferido (aaaa-mm-dd): o da conta; sem conta, o da cobrança. */
  vencimento: string;
  /** Só dígitos (55…), já validado: o número que recebe. */
  telefone: string;
  /** O texto EXATO que vai ao cliente. */
  mensagem: string;
}

/** Leitura que falha LANÇA: erro engolido viraria "sem piso", "sem opt-out" ou "sem entrada esperando". */
// deno-lint-ignore no-explicit-any
async function ler<T>(consulta: PromiseLike<{ data: any; error: any }>, oQue: string): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw new Error(`Não consegui ler ${oQue}: ${error.message ?? error}`);
  return data as T;
}

/**
 * O texto padrão do lembrete — o MESMO de sempre, palavra por palavra; só a data mudou de "2026-07-22" para
 * "22/07/2026" (25/11/2026). Frase nova a cliente pede aprovação do dono: não acrescente nada aqui sem ela. Pura.
 */
export function mensagemDoLembrete(p: { nome?: string | null; valor: number; vencimento: string }): string {
  const nome = String(p.nome ?? "").trim();
  const quando = dataDoLembrete(p.vencimento) || p.vencimento;
  return `Olá${nome ? ` ${nome}` : ""}, lembrete amigável: você possui um valor de ${emReais(p.valor)} com vencimento em ${quando}. Qualquer dúvida estamos à disposição.`;
}

/**
 * Lê a cobrança, confere o valor e o vencimento na CONTA, passa as travas (na ordem de sempre) e monta a mensagem.
 * Recusa de negócio = { error } (frase pronta); leitura que falha LANÇA. `db`: o cliente das leituras (admin no cartão
 * e no retrato, sb na execução); `admin`: o piso e as entradas esperando no Extrato (service role, como sempre foi).
 */
// deno-lint-ignore no-explicit-any
export async function montarLembreteDeCobranca(db: any, admin: any, args: Record<string, unknown> | undefined): Promise<LembreteDeCobranca | { error: string }> {
  const id = String(args?.collection_id ?? "").trim();
  // Id que não é uuid (número de OS, nome) faria o banco responder erro de sintaxe, não "não achei".
  if (!UUID_RE.test(id)) return { error: NAO_ACHEI };

  // 1) A cobrança.
  const col = await ler<CobrancaLida | null>(db.from("collections").select(COLUNAS_DA_COBRANCA).eq("id", id).maybeSingle(), "a cobrança");
  if (!col) return { error: NAO_ACHEI };
  // Cobrança paga ou cancelada não se cobra (07/10/2026): cobrar quem pagou custa a relação.
  if (col.status === "paid" || col.status === "cancelled") {
    return { error: `Esta cobrança está ${col.status === "paid" ? "paga" : "cancelada"}: não mando lembrete.` };
  }

  // 2) O valor e o vencimento, pela CONTA a receber (25/11/2026). A cobrança guarda o valor de quando nasceu.
  let conta: ContaLida | null = null;
  let valor = Number(col.amount) || 0;
  let vencimento = diaDe(col.due_date);
  if (col.receivable_id) {
    conta = await ler<ContaLida | null>(db.from("receivables").select(COLUNAS_DA_CONTA).eq("id", col.receivable_id).maybeSingle(), "a conta a receber da cobrança");
    if (!conta) return { error: "Não achei a conta a receber desta cobrança, então não dá para conferir o valor: não mando lembrete. Confira a cobrança na tela (Cobranças)." };
    if (conta.status === "paid" || conta.status === "cancelled") {
      return { error: `A conta desta cobrança já está ${conta.status === "paid" ? "paga" : "cancelada"}: não mando lembrete.` };
    }
    valor = saldoDaConta(conta);
    if (valor <= 0) return { error: "A conta desta cobrança não tem mais saldo em aberto: não mando lembrete." };
    vencimento = diaDe(conta.due_date) || vencimento;
  }

  // 3) D21 (dono, 17/09/2026): piso de materialidade — abaixo dele não se cobra por mensagem. Compara com o valor
  //    conferido: a cobrança de R$ 2.000 cuja conta hoje deve R$ 20 fica abaixo do piso.
  const cfgPiso = await ler<{ value?: string | null } | null>(
    admin.from("app_settings").select("value").eq("key", "collection_min_amount").maybeSingle(),
    "o piso de cobrança (Configurações)",
  );
  const piso = Number(cfgPiso?.value) || 0;
  if (piso > 0 && valor < piso) {
    return { error: `Cobrança de R$ ${valor.toFixed(2)} fica abaixo do piso de R$ ${piso} (Configurações): só listar, não cobrar por WhatsApp.` };
  }

  // 4) Pix do cliente esperando no Extrato: pode ser este pagamento. Não cobra até decidir a linha
  //    (aplicar na conta, ou aprovar como receita nova) — cobrar quem pagou custa a relação.
  if (col.client_id) {
    const pix = (await pixEsperandoNoExtrato({ admin } as ToolCtx, [String(col.client_id)])).get(String(col.client_id)) ?? [];
    if (pix.length) {
      const lista = pix.map((p) => `R$ ${p.valor.toFixed(2)}${p.data ? ` de ${p.data}` : ""}`).join(", ");
      return {
        error: `Este cliente tem entrada esperando no Extrato (${lista}): pode ser este pagamento. `
          + "Confira no Extrato (Este Pix paga…) antes de cobrar; se for outra coisa, decida a linha lá e cobre depois.",
      };
    }
  }

  // 5) Perfil do contato: nome usado (display_name), opt-out e cadastro genérico.
  let cliente: ClienteLido | null = null;
  if (col.client_id) {
    cliente = await ler<ClienteLido | null>(db.from("clients").select(COLUNAS_DO_CLIENTE).eq("id", col.client_id).maybeSingle(), "o cadastro do cliente");
    // Sem o cadastro não dá para saber do opt-out: melhor não mandar do que mandar a quem pediu para não receber.
    if (!cliente) return { error: "Não achei o cadastro do cliente desta cobrança, então não dá para conferir o opt-out: não mando lembrete." };
  }
  if (cliente?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out). Cobre por outro canal." };
  // A cobrança pode ter contato próprio; só recusa quando o destino seria o telefone do cadastro genérico. Revisão de
  // 25/11/2026: toda cobrança nasce com o telefone do cadastro COPIADO como contato (Gerar Cobranças, criar_cobranca e
  // cobrar_juntas_registrar_envio fazem isso), então "tem contato" não prova nada — vale o contato que é OUTRO número.
  if (cliente?.generico) {
    const doCadastro = [cliente.whatsapp, cliente.phone].map((t) => telefoneParaEnvio(t)).filter(Boolean);
    const contato = col.contact_whatsapp || col.phone;
    if (!contato || doCadastro.includes(telefoneParaEnvio(contato))) return { error: RECUSA_CLIENTE_FINAL };
  }

  // 6) O destino, na ordem de sempre: o contato da cobrança, depois o cadastro do cliente.
  const bruto = col.contact_whatsapp || col.phone || cliente?.whatsapp || cliente?.phone;
  if (!bruto) return { error: "Sem telefone para enviar o lembrete." };
  const telefone = telefoneParaEnvio(bruto);
  if (!telefone) {
    const deQuem = col.contact_whatsapp || col.phone ? "do contato desta cobrança" : "do cadastro do cliente";
    return { error: `O telefone ${deQuem} ("${String(bruto).trim()}") não é um número de WhatsApp válido: corrija e peça de novo.` };
  }

  // 7) A mensagem: a frase do dono inteira, ou o texto padrão com o valor e o vencimento conferidos.
  const frase = args?.custom_message;
  const propria = typeof frase === "string" ? frase.trim() : "";
  // O nome da saudação (revisão de 25/11/2026): o contact_name da cobrança é o nome do cadastro copiado na criação, às
  // vezes com rótulo interno ("Nelson - S.I. 7.8", "César – Palazzo"), e ia inteiro no "Olá …". Agora: indo ao número do
  // cadastro, o apelido (display_name) ou o primeiro nome do cliente; indo a um contato PRÓPRIO da cobrança (outro
  // número, outra pessoa), o primeiro nome desse contato.
  const primeiro = (s: unknown) => String(s ?? "").trim().split(/\s+/)[0] || "";
  const doCadastro = [cliente?.whatsapp, cliente?.phone].map((t) => telefoneParaEnvio(t)).filter(Boolean);
  const contatoProprio = !!(col.contact_whatsapp || col.phone) && !doCadastro.includes(telefone);
  const nomeUsado = contatoProprio
    ? primeiro(col.contact_name) || String(cliente?.display_name ?? "").trim() || primeiro(cliente?.name)
    : String(cliente?.display_name ?? "").trim() || primeiro(cliente?.name) || primeiro(col.contact_name);
  const mensagem = propria || mensagemDoLembrete({ nome: nomeUsado, valor, vencimento });
  return { cobranca: col, conta, cliente, valor, vencimento, telefone, mensagem };
}

// ── o cartão do "sim" ────────────────────────────────────────────────────────────────────────

/** "⚠️ …" numa linha só: o executor devolve como recusa, sem pendência (RESUMO_QUE_RESOLVE em agent.ts). */
const recusa = (texto: string) => `⚠️ ${texto.replace(/\s*\n+\s*/g, " ").trim()}`;

/** Dias corridos entre duas datas aaaa-mm-dd (b − a), sem fuso; null se alguma não é data. */
function diasEntre(a: string, b: string): number | null {
  const ms = (d: string) => {
    const m = d.match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
  };
  const [x, y] = [ms(a), ms(b)];
  return x === null || y === null ? null : Math.round((y - x) / 86400000);
}

/** "vencido há 98 dias", "vence hoje", "vence em 3 dias" — pela data, em Brasília. Pura. */
export function prazoDoLembrete(vencimento: string, hoje: string): string {
  const dias = diasEntre(vencimento, hoje);
  if (dias === null) return "";
  if (dias > 0) return `vencido há ${plural(dias, "dia", "dias")}`;
  if (dias === 0) return "vence hoje";
  return `vence em ${plural(-dias, "dia", "dias")}`;
}

/** O que a cobrança guardava e a conta desmente (valor e vencimento), em linhas curtas para o dono. Pura. */
export function divergenciasDoLembrete(l: Pick<LembreteDeCobranca, "cobranca" | "conta" | "valor" | "vencimento">): string[] {
  if (!l.conta) return [];
  const linhas: string[] = [];
  if (centavos(l.cobranca.amount) !== centavos(l.valor)) {
    linhas.push(`A cobrança guardava ${emReais(l.cobranca.amount)}; a conta hoje é ${emReais(l.valor)}.`);
  }
  const guardado = diaDe(l.cobranca.due_date);
  if (guardado && guardado !== l.vencimento) {
    linhas.push(`A cobrança guardava vencimento em ${dataDoLembrete(guardado)}; a conta vence em ${dataDoLembrete(l.vencimento)}.`);
  }
  return linhas;
}

/**
 * Resumo da confirmação (painel e WhatsApp): quem recebe, o número inteiro, o valor e o vencimento conferidos, o que a
 * cobrança guardava (quando diverge) e a mensagem exata. Trava = uma linha "⚠️ …". Leitura que falha lança (o
 * buildPendingSummary transforma em recusa).
 */
// deno-lint-ignore no-explicit-any
export async function resumirLembreteDeCobranca(admin: any, args: Record<string, unknown>): Promise<string> {
  const l = await montarLembreteDeCobranca(admin, admin, args);
  if (ehErro(l)) return recusa(l.error);
  // O lembrete desta cobrança já saiu hoje por aqui (a chave do dia está concluída): o whatsapp-send não reenvia — o "sim"
  // seria em vão e o dono contaria com uma segunda mensagem (conferência de 25/11/2026). Chave livre ou leitura que falha:
  // segue (o envio confere de novo).
  const hoje = diaLocal(relogioDoLembrete.agora());
  if (await situacaoDaReserva(admin, chaveDeEnvio("cobranca", l.cobranca.id, hoje)) === "concluida") {
    return recusa("O lembrete desta cobrança já saiu hoje: o mesmo lembrete não sai duas vezes no dia. Peça de novo amanhã, ou cobre o cliente inteiro (\"cobra o Fulano\").");
  }
  const nome = String(l.cliente?.name ?? "").trim() || String(l.cobranca.contact_name ?? "").trim() || "cliente";
  const prazo = prazoDoLembrete(l.vencimento, hoje);
  return [
    `Lembrete de cobrança para *${nome}*, pelo WhatsApp *${telefoneLegivel(l.telefone)}*:`,
    `- Valor: *${emReais(l.valor)}*${l.conta ? " (o saldo da conta a receber hoje)" : " (o valor da cobrança; ela não tem conta a receber ligada)"}`,
    `- Vencimento: ${dataDoLembrete(l.vencimento) || "—"}${prazo ? ` (${prazo})` : ""}`,
    ...divergenciasDoLembrete(l).map((d) => `- ${d}`),
    ...avisoDaFrasePropria(propriaDoPedido(args), l.valor, l.vencimento, !!l.conta).map((d) => `- ${d}`),
    ...(await avisosDoCliente(admin, l)).map((d) => `- ${d}`),
    ...(pareceTelefoneFixo(l.telefone) ? [`- ${AVISO_DE_FIXO}`] : []),
    "Mensagem que vai ao cliente:",
    l.mensagem,
  ].join("\n");
}

// ── os avisos do cartão (revisão de 25/11/2026) — texto para o DONO, nunca vai ao cliente ──────────────────────────

/** A frase que o dono ditou (custom_message), sem espaços nas pontas; "" = o texto padrão. */
function propriaDoPedido(args: Record<string, unknown> | undefined): string {
  const f = args?.custom_message;
  return typeof f === "string" ? f.trim() : "";
}

/** "1.650,00" → 1650; "1650.00" → 1650 (ponto com 1 ou 2 dígitos no fim, sem vírgula, é decimal); "1.650" → 1650. */
function numeroEmReais(bruto: string): number {
  const s = bruto.trim();
  if (!s.includes(",") && /\.\d{1,2}$/.test(s)) return Number(s.replace(/\.(?=\d{3}(\D|$))/g, ""));
  return Number(s.replace(/\./g, "").replace(",", "."));
}

/** Os valores em reais citados numa frase: "R$ 1.650,00", "R$1650.00", "1.650,00 reais", "R$ 2,5 mil". Pura. */
export function reaisCitados(frase: string): number[] {
  const t = String(frase ?? "");
  const vistos = [
    ...[...t.matchAll(/R\$\s*(\d[\d.]*(?:,\d{1,2})?)(\s*mil\b)?/gi)].map((m) => numeroEmReais(m[1]) * (m[2] ? 1000 : 1)),
    ...[...t.matchAll(/(?<![\d.,$]\s?)\b(\d[\d.]*(?:,\d{1,2})?)(\s*mil)?\s+reais\b/gi)].map((m) => numeroEmReais(m[1]) * (m[2] ? 1000 : 1)),
  ];
  return vistos.filter((v) => Number.isFinite(v) && v > 0);
}

/** As datas citadas numa frase, como aaaa-mm-dd quando têm ano e como mm-dd quando não têm. Pura. */
export function datasCitadas(frase: string): string[] {
  return [...String(frase ?? "").matchAll(/\b(0?[1-9]|[12]\d|3[01])\/(0?[1-9]|1[0-2])(?:\/(\d{4}|\d{2}))?\b/g)].map((m) => {
    const dm = `${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
    return m[3] ? `${m[3].length === 2 ? `20${m[3]}` : m[3]}-${dm}` : dm;
  });
}

/**
 * A frase do dono cita um valor que não é o saldo de hoje (o modelo copiou o valor antigo de list_pending_collections,
 * por exemplo): uma linha de atenção no cartão. Não recusa — o dono pode citar outro valor de propósito (o total da
 * parcela e quanto falta). Pura.
 */
export function avisoDaFrasePropria(frase: string, valor: number, vencimento = "", temConta = true): string[] {
  const avisos: string[] = [];
  const citados = reaisCitados(frase);
  if (citados.length && !citados.some((v) => centavos(v) === centavos(valor))) {
    avisos.push(`Atenção: a frase cita ${citados.map((v) => emReais(v)).join(", ")}; ${temConta ? "o saldo da conta hoje é" : "o valor da cobrança é"} ${emReais(valor)}. Confira antes de aprovar.`);
  }
  const datas = datasCitadas(frase);
  const venc = diaDe(vencimento);
  if (datas.length && venc && !datas.some((d) => d === venc || d === venc.slice(5))) {
    const ditas = [...String(frase).matchAll(/\b(?:0?[1-9]|[12]\d|3[01])\/(?:0?[1-9]|1[0-2])(?:\/(?:\d{4}|\d{2}))?\b/g)].map((m) => m[0]);
    avisos.push(`Atenção: a frase cita ${ditas.join(", ")}; ${temConta ? "a conta vence em" : "a cobrança vence em"} ${dataDoLembrete(venc)}. Confira antes de aprovar.`);
  }
  return avisos;
}

/** Celular brasileiro tem 9 dígitos depois do DDD; 8 dígitos começando por 2 a 5 é telefone fixo (sem WhatsApp, em geral). */
export function pareceTelefoneFixo(digitos: string): boolean {
  return /^55\d{2}[2-5]\d{7}$/.test(String(digitos ?? ""));
}
export const AVISO_DE_FIXO = "Atenção: o número parece de telefone FIXO (sem WhatsApp, em geral): a mensagem pode não chegar. Confira o cadastro.";

/**
 * O que o dono precisa saber do cliente antes do "sim": outro lembrete já saiu hoje (para não cobrar duas vezes no dia) e
 * as OUTRAS contas em aberto dele (o lembrete é só desta; "cobra o Fulano" junta tudo numa mensagem). Leitura que falha
 * LANÇA (o cartão vira "⚠️ Não consegui conferir…"): melhor não pedir o "sim" do que pedir sem saber.
 */
// deno-lint-ignore no-explicit-any
async function avisosDoCliente(admin: any, l: LembreteDeCobranca): Promise<string[]> {
  const avisos: string[] = [];
  const hoje = diaLocal(relogioDoLembrete.agora());
  const deHoje = (t: unknown) => !!t && diaLocal(new Date(String(t))) === hoje;
  const clienteId = l.cobranca.client_id;
  let cobradoHoje = deHoje(l.cobranca.last_auto_sent_at);
  if (clienteId) {
    if (!cobradoHoje) {
      const outras = await ler<Array<{ last_auto_sent_at: string | null }>>(
        admin.from("collections").select("id, last_auto_sent_at").eq("client_id", clienteId), "as cobranças do cliente",
      );
      cobradoHoje = (outras ?? []).some((k) => deHoje(k.last_auto_sent_at));
    }
    if (l.conta) {
      const contas = await ler<ContaLida[]>(
        admin.from("receivables").select(COLUNAS_DA_CONTA).eq("client_id", clienteId), "as contas a receber do cliente",
      );
      let resto = (contas ?? []).filter((c) => c.id !== l.conta!.id && saldoDaConta(c) > 0);
      // conta de OS cancelada ou agrupada em outra não entra no "cobra o Fulano" (fica de fora, com aviso): não conta aqui
      const idsDasOS = [...new Set(resto.map((c) => c.service_order_id).filter((x): x is string => !!x))];
      if (idsDasOS.length) {
        const ordens = await ler<Array<{ id: string; status: string | null; merged_into_id: string | null }>>(
          admin.from("service_orders").select("id, status, merged_into_id").in("id", idsDasOS), "as OS das contas do cliente",
        );
        const naoVale = new Set((ordens ?? []).filter((o) => o.status === "cancelled" || !!o.merged_into_id).map((o) => o.id));
        resto = resto.filter((c) => !c.service_order_id || !naoVale.has(c.service_order_id));
      }
      if (resto.length) {
        const soma = resto.reduce((t, c) => t + centavos(saldoDaConta(c)), 0) / 100;
        avisos.push(`Este lembrete é só desta conta: o cliente tem mais ${plural(resto.length, "conta", "contas")} em aberto (${emReais(soma)}). `
          + "Para cobrar tudo numa mensagem só, peça a cobrança do cliente (\"cobra o Fulano\").");
      }
    }
  }
  if (cobradoHoje) avisos.unshift("Já houve cobrança para este cliente hoje: ele vai receber outra mensagem no mesmo dia.");
  return avisos;
}

// ── o retrato ────────────────────────────────────────────────────────────────────────────────

function retratoDe(l: LembreteDeCobranca): Record<string, unknown> {
  return { cobranca: l.cobranca.id, telefone: l.telefone, valor: l.valor, vencimento: l.vencimento, texto: l.mensagem };
}

/** O retrato que o "sim" aprova: a cobrança, o telefone de destino, o valor, o vencimento e o texto. null = não deu para tirar. */
// deno-lint-ignore no-explicit-any
export async function retratoDoLembreteDeCobranca(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  try {
    const l = await montarLembreteDeCobranca(admin, admin, args);
    return ehErro(l) ? null : retratoDe(l);
  } catch {
    return null;
  }
}

/** O que mudou entre o retrato aprovado e agora, em português; null = nada. */
export function oQueMudouNoLembrete(retrato: Record<string, unknown>, agora: LembreteDeCobranca): string | null {
  const novo = retratoDe(agora);
  if (retrato.cobranca !== novo.cobranca) return "a cobrança do pedido não é a mesma";
  if (retrato.telefone !== novo.telefone) return "o telefone de destino mudou";
  if (centavos(retrato.valor) !== centavos(novo.valor)) return `o valor mudou (era ${emReais(retrato.valor)}, agora ${emReais(novo.valor)})`;
  if (retrato.vencimento !== novo.vencimento) {
    return `o vencimento mudou (era ${dataDoLembrete(retrato.vencimento) || "—"}, agora ${dataDoLembrete(novo.vencimento) || "—"})`;
  }
  if (retrato.texto !== novo.texto) return "o texto da mensagem mudou";
  return null;
}
