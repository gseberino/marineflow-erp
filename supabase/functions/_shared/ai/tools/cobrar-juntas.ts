// "Cobrar juntas" pelo assistente (28/10/2026) — Fase 0 do "Fechar juntas" (spec-fechar-juntas 4.1 e 7).
//
// O pedido do dono: o mesmo cliente tem 2+ OS já executadas (em andamento, concluídas ou "Faturadas") com saldo
// em aberto, e ele quer cobrar tudo numa mensagem só. Caso real (28/10/2026): MP MOTOR HOMES, OS-00045
// (R$ 1.650) + OS-00046 (R$ 20) = R$ 1.670, vencido desde 22/07.
//
// NÃO muda o banco: é o extrato do cliente filtrado pelas OS escolhidas. Cada conta continua na sua OS (o
// payment_status de cada uma é do gatilho dela), e o pagamento segue o caminho de hoje ("Este Pix paga…"
// reparte pelo vencimento). Depois do envio, cada cobrança (collections) das contas escolhidas ganha o contato
// 'whatsapp_sent' e o last_auto_sent_at — como send_collection_reminder (registrarEnvioDaCobranca) —, que é o
// que o plano de inadimplência lê para não mandar cobrar de novo no mesmo dia. Conta SEM cobrança formal (a MP em
// 28/10/2026) não recebe registro nenhum: a confirmação avisa (SEM_COBRANCA_FORMAL).
//
// Cobra o TITULAR da conta, como a tela (a ficha lista as contas por receivables.client_id): conta em nome de
// outro cadastro (o pagador da leva 8) recusa, em vez de mandar a dívida de um ao WhatsApp de outro.
//
// As travas são as MESMAS do send_collection_reminder, pela regra pura compartilhada com a tela
// (_shared/receivables/cobrar-juntas.ts, travaDoCobrarJuntas): cadastro genérico (sem CPF/CNPJ, decisão do dono
// de 28/10/2026 — clients.generico), nada em aberto, piso de materialidade, Pix do cliente esperando no Extrato,
// opt-out e telefone. Mais o portão de comunicação (horário) na hora de enviar.
//
// A FRONTEIRA com agrupar_os: OS que ainda NÃO começou a ser executada não entra aqui (→ agrupar_os, que junta
// numa OS nova); OS executada não se agrupa (→ cobrar_juntas, que só junta a COBRANÇA). Orçamento não se cobra.
//
// Sempre com o "sim" do dono, por texto: a confirmação mostra cada OS com o saldo, o total, o número inteiro e a
// mensagem EXATA que vai ao cliente. Impedimento vira uma linha "⚠️ …" (recusa, sem pendência). O "sim" foi
// sobre o retrato (cliente, telefone, contas e saldos): mudou até o "sim", não envia.
import { cargosQueContam, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import { pareceNumeroDeOS } from "./os-referencia.ts";
import { emReais, referenciasDosOrcamentos } from "./agrupar-orcamentos.ts";
import { STATUS_QUE_AGRUPAM } from "./agrupar-os.ts";
import { pixEsperandoNoExtrato } from "./pix-esperando.ts";
import { telefoneLegivel, telefoneParaEnvio } from "./agendamento.ts";
import { sendWhatsapp } from "./whatsapp.ts";
import { registrarEnvioDaCobranca } from "./cobrancas.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { diaLocal } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { ROTULOS_STATUS_OS } from "../../service-order-status.ts";
import {
  chaveDoCobrarJuntas,
  type ContaDoCliente,
  contaVencida,
  MAX_COBRAR_JUNTAS as MAX_AGRUPAR,
  MIN_COBRAR_JUNTAS as MIN_AGRUPAR,
  pagoDaConta,
  saldoDaConta,
  SEM_COBRANCA_FORMAL,
  STATUS_QUE_COBRAM_JUNTAS,
  travaDoCobrarJuntas,
} from "../../receivables/cobrar-juntas.ts";

/** Quem cobra junto: os mesmos cargos do agrupar (mexe com o saldo de várias OS e fala com o cliente). */
export const CARGOS_DE_COBRAR_JUNTAS: Role[] = ["admin", "financial"];
/** Situações de OS que já começaram a ser executadas (ou acabaram): as que entram — a MESMA lista da tela. */
export { STATUS_QUE_COBRAM_JUNTAS };

/** O relógio da tool (hoje, vencido e o horário do portão) — os testes trocam. */
export const relogioDoCobrarJuntas = { agora: () => new Date() };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SEM_CARGO = "Só administrador ou financeiro cobra várias OS juntas.";
const SEM_RETRATO = "Nada foi enviado: não consegui conferir as contas quando o pedido foi feito. Peça de novo que eu confiro.";
const NAO_COMECOU =
  "Cobrar juntas é para OS já executadas (em andamento, concluídas ou faturadas); para juntar OS que ainda não começaram numa OS só, use agrupar_os.";

const centavos = (v: unknown): number => Math.round((Number(v) || 0) * 100);
const reais = (c: number) => c / 100;
const situacaoDaOS = (s: unknown) => ROTULOS_STATUS_OS[String(s) as keyof typeof ROTULOS_STATUS_OS] ?? String(s ?? "—");
/** "2026-07-22" → "22/07/2026" sem passar por fuso (due_date é data, não instante). */
const dataDaConta = (d: unknown) => {
  const m = String(d ?? "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
};
const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

// Guarda de tipo (o tsc do app roda sem strictNullChecks; ver ehErro em caixa.ts).
function ehErro(x: unknown): x is { error: string } {
  return !!x && typeof x === "object" && "error" in x;
}

/** Hora cheia em Brasília (para o portão de horário). */
function horaEmBrasilia(d: Date): number {
  const h = new Intl.DateTimeFormat("en-US", { timeZone: "America/Sao_Paulo", hour: "numeric", hourCycle: "h23" }).format(d);
  return Number(h) % 24;
}

/** Só número de OS (OS-00045, "45") ou id: frases não identificam uma OS aqui. */
const referenciaValida = (r: string) => UUID_RE.test(r) || pareceNumeroDeOS(r);

/** "OS-00045", "os 45" e "45" são o mesmo pedido (número sem prefixo, aqui, é OS). */
function chaveDaOS(ref: string): string {
  if (UUID_RE.test(ref)) return ref.toLowerCase();
  const t = ref.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const m = t.match(/^([A-Z]*)0*(\d+)$/);
  if (!m) return t;
  return `${m[1] === "ORCAMENTO" || m[1] === "ORC" ? "ORC" : "OS"}${m[2]}`;
}

/** Recusa sem banco (antes da pendência): cargo, as OS (2 a 10, só números/ids, sem repetidas) ou o cliente. */
export function validarPedidoDeCobrarJuntas(args: Record<string, unknown> | undefined, ctx: Pick<ToolCtx, "userRole">): { error: string } | null {
  if (!CARGOS_DE_COBRAR_JUNTAS.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
  const refs = referenciasDosOrcamentos(args?.os);
  const cliente = String(args?.cliente_id ?? "").trim();
  if (cliente && !UUID_RE.test(cliente)) return { error: "Passe o id do cliente (ache com search_clients) ou diga as OS pelos números." };
  if (!refs.length && !cliente) return { error: "Diga as OS a cobrar juntas (números, ex.: OS-00045 e OS-00046) ou o cliente (id de search_clients)." };
  if (refs.length) {
    if (refs.length < MIN_AGRUPAR) {
      return { error: "Cobrar juntas é para 2 OS ou mais. Para uma OS só, cobre pela cobrança dela (send_collection_reminder)." };
    }
    if (refs.length > MAX_AGRUPAR) return { error: "Cobre no máximo 10 OS de uma vez." };
    const torto = refs.find((r) => !referenciaValida(r));
    if (torto) return { error: `"${torto}" não é número de OS: diga os números (ex.: OS-00045).` };
    const chaves = refs.map(chaveDaOS);
    const repetida = refs.find((_r, i) => chaves.indexOf(chaves[i]) !== i);
    if (repetida) return { error: `A mesma OS foi dita duas vezes (${repetida}).` };
  }
  return null;
}

// ── leitura ──────────────────────────────────────────────────────────────────────────────────

interface OSLida {
  id: string;
  service_order_number: string;
  status: string;
  client_id: string | null;
  merged_into_id: string | null;
  converted_to_os_at: string | null;
  check_in_at?: string | null;
  check_out_at?: string | null;
}
const COLUNAS_DA_OS = "id, service_order_number, status, client_id, merged_into_id, converted_to_os_at, check_in_at, check_out_at";

interface ContaLida extends ContaDoCliente {
  client_id?: string | null;
  is_deposit?: boolean | null;
}
const COLUNAS_DA_CONTA = "id, service_order_id, client_id, description, amount, paid_amount, balance_amount, status, due_date, is_deposit";

interface ClienteLido {
  id: string;
  name: string | null;
  display_name: string | null;
  whatsapp: string | null;
  phone: string | null;
  opt_out_whatsapp: boolean | null;
  generico: boolean | null;
}
const COLUNAS_DO_CLIENTE = "id, name, display_name, whatsapp, phone, opt_out_whatsapp, generico";

interface CobrancaLida {
  id: string;
  status: string | null;
  receivable_id: string | null;
  service_order_id: string | null;
  last_auto_sent_at: string | null;
}

/** Uma OS da cobrança conjunta: a linha, as contas com saldo (por vencimento) e o saldo. */
export interface OSDaCobranca {
  id: string;
  numero: string;
  status: string;
  contas: ContaLida[];
  saldo: number;
  vencido: boolean;
}

/** A cobrança conjunta resolvida: o que a confirmação mostra, o retrato guarda e o envio manda. */
export interface CobrancaConjunta {
  cliente: ClienteLido;
  os: OSDaCobranca[];
  /** Total = Pago + Em aberto das contas escolhidas (a mensagem prova a conta). */
  total: number;
  pago: number;
  emAberto: number;
  /** Só dígitos (55…), já validado. */
  telefone: string;
  cobrancas: CobrancaLida[];
  avisos: string[];
  mensagem: string;
}

/** Leitura que falha LANÇA: erro engolido viraria "nada em aberto" ou "sem Pix esperando". */
// deno-lint-ignore no-explicit-any
async function ler<T>(consulta: PromiseLike<{ data: any; error: any }>, oQue: string): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw new Error(`Não consegui ler ${oQue}: ${error.message ?? error}`);
  return data as T;
}

/** As OS ditas (números ou ids), resolvidas sem chute. */
// deno-lint-ignore no-explicit-any
async function osDitas(db: any, refs: string[]): Promise<OSLida[] | { error: string }> {
  const ids: string[] = [];
  for (const ref of refs) {
    const achado = await localizarOrdem(db, ref, "os");
    if ("opcoes" in achado) return { error: `${ref}: existe mais de um documento com esse número (${achado.opcoes.join(" e ")}). Qual deles?` };
    if ("erro" in achado) return { error: `${ref}: ${achado.erro}` };
    if (ids.includes(achado.ordem.id)) return { error: `A mesma OS foi dita duas vezes (${achado.ordem.service_order_number}).` };
    ids.push(achado.ordem.id);
  }
  const linhas = await ler<OSLida[]>(db.from("service_orders").select(COLUNAS_DA_OS).in("id", ids), "as OS");
  const faltando = ids.filter((id) => !(linhas ?? []).some((l) => l.id === id));
  if (faltando.length) return { error: "Não achei uma das OS ditas: liste as OS do cliente de novo." };
  return ids.map((id) => linhas.find((l) => l.id === id)!);
}

/** Por que uma OS dita não entra (null = entra). */
function problemaDaOS(o: OSLida): string | null {
  const n = o.service_order_number;
  if (o.status === "draft" && !o.converted_to_os_at) return `${n} ainda é orçamento (não virou OS): não há o que cobrar junto.`;
  if (o.merged_into_id) return `${n} foi agrupada em outra OS: cobre pela OS agrupada.`;
  if (o.status === "cancelled") return `${n} está cancelada: não entra na cobrança.`;
  if (STATUS_QUE_AGRUPAM.includes(o.status)) {
    // Decisão do dono (28/10/2026): a chegada no barco já é execução, e o agrupar_os recusa a OS. Mandar
    // ao agrupar_os aqui deixaria o assistente em laço entre as duas tools (_os_execucao_iniciada no banco).
    if (o.check_in_at || o.check_out_at) {
      return `${n} está ${situacaoDaOS(o.status)}, mas já tem a chegada no barco registrada: já começou, então o agrupar_os ` +
        "também não a aceita. Para cobrar junto, mude a situação da OS para Em andamento (ou conclua) e peça de novo.";
    }
    return `${n} ainda não começou a ser executada (situação: ${situacaoDaOS(o.status)}). ${NAO_COMECOU} ` +
      "Se o agrupar_os recusar por ela já ter começado (hora apontada, despesa, passo do roteiro…), mude a situação da OS " +
      "para Em andamento e cobre junto.";
  }
  if (!STATUS_QUE_COBRAM_JUNTAS.includes(o.status)) return `${n} está ${situacaoDaOS(o.status)}: não entra na cobrança conjunta.`;
  return null;
}

/** As configurações que a cobrança usa (piso e chave Pix), lidas do banco. */
// deno-lint-ignore no-explicit-any
async function configuracoes(admin: any): Promise<Record<string, string>> {
  const linhas = await ler<Array<{ key: string; value: string | null }>>(
    admin.from("app_settings").select("key, value").in("key", ["collection_min_amount", "pix_key"]),
    "as configurações da cobrança",
  );
  return Object.fromEntries((linhas ?? []).map((l) => [l.key, String(l.value ?? "")]));
}

/** As cobranças das contas escolhidas (pela conta, ou sem conta e pela OS), fora pagas e canceladas. */
// deno-lint-ignore no-explicit-any
async function cobrancasDasContas(db: any, contas: ContaLida[], osIds: string[]): Promise<CobrancaLida[]> {
  const COLUNAS = "id, status, receivable_id, service_order_id, last_auto_sent_at";
  const idsDasContas = contas.map((c) => c.id);
  const pelaConta = await ler<CobrancaLida[]>(db.from("collections").select(COLUNAS).in("receivable_id", idsDasContas), "as cobranças das contas");
  const pelaOS = await ler<CobrancaLida[]>(db.from("collections").select(COLUNAS).in("service_order_id", osIds), "as cobranças das OS");
  const todas = new Map<string, CobrancaLida>();
  for (const c of [...(pelaConta ?? []), ...(pelaOS ?? [])]) {
    const daConta = !!c.receivable_id && idsDasContas.includes(c.receivable_id);
    const daOSSemConta = !c.receivable_id && !!c.service_order_id && osIds.includes(c.service_order_id);
    if ((daConta || daOSSemConta) && c.status !== "paid" && c.status !== "cancelled") todas.set(c.id, c);
  }
  return [...todas.values()].sort((a, b) => a.id.localeCompare(b.id));
}

/**
 * A linha de uma conta na mensagem ao cliente — IGUAL à do "Cobrar juntas" da tela (buildClientStatement com servicoIds,
 * src/lib/client-statement.ts): o número da OS, o SALDO e a situação calculada (vencido pela data, parcial, a vencer).
 */
function linhaDaConta(numero: string, c: ContaLida, hoje: string): string {
  const pago = pagoDaConta(c);
  const situacao = contaVencida(c, hoje) ? ["🔴", "vencido"] : pago > 0.009 ? ["🟠", "parcial"] : ["🟡", "a vencer"];
  const desc = String(c.description ?? "").trim() || "Lançamento";
  const rotulo = numero && !desc.includes(numero) ? `${numero} · ${desc}` : desc;
  const valor = `*${emReais(saldoDaConta(c))}*${pago > 0.009 ? ` (de ${emReais(c.amount)})` : ""}`;
  return `${situacao[0]} ${rotulo} · vence ${dataDaConta(c.due_date) || "—"} · ${situacao[1]}: ${valor}`;
}

/**
 * A mensagem que vai ao cliente — o MESMO texto que o "Cobrar juntas" da tela monta (buildClientStatement com servicoIds):
 * o cliente não recebe dois formatos conforme quem disparou. Correções da Fase 0: o número da OS e o SALDO em cada linha,
 * Pago = soma do pago (parcial incluso), Total − Pago = Em aberto, "vencido" pela data. Pura (os testes leem a frase).
 */
export function mensagemDaCobrancaConjunta(p: {
  cliente: Pick<ClienteLido, "name">;
  os: OSDaCobranca[];
  pixKey?: string | null;
  hoje: string;
}): string {
  const nome = String(p.cliente.name ?? "").trim().split(/\s+/)[0] || "Cliente";
  const linhas = p.os.flatMap((o) => o.contas.map((c) => linhaDaConta(o.numero, c, p.hoje)));
  const contas = p.os.flatMap((o) => o.contas);
  const total = contas.reduce((t, c) => t + centavos(c.amount), 0);
  const pago = contas.reduce((t, c) => t + centavos(pagoDaConta(c)), 0);
  const emAberto = contas.reduce((t, c) => t + centavos(saldoDaConta(c)), 0);
  const pix = String(p.pixKey ?? "").trim();
  return (
    `📋 *Cobrança — HBR*\nCliente: ${nome}\nOS: ${p.os.map((o) => o.numero).join(", ")}\n\n` +
    `${linhas.join("\n")}\n\n` +
    `Total: ${emReais(reais(total))}\n` +
    `Pago: ${emReais(reais(pago))}\n` +
    `*Em aberto: ${emReais(reais(emAberto))}*` +
    (emAberto > 0 && pix ? `\n\n💠 Para pagar por Pix, use a chave: *${pix}*` : "") +
    `\n\n_Qualquer dúvida sobre os valores, estamos à disposição._`
  );
}

/**
 * Resolve o pedido (as OS ditas, ou as OS executadas com saldo do cliente), confere as travas e monta a mensagem.
 * Recusa de negócio = { error } (frase pronta); leitura que falha LANÇA. `db`: o cliente das leituras (admin no
 * resumo e no retrato, sb na execução); `admin`: configurações e Pix esperando (service role, como o lembrete).
 */
// deno-lint-ignore no-explicit-any
export async function montarCobrancaConjunta(db: any, admin: any, args: Record<string, unknown>): Promise<CobrancaConjunta | { error: string }> {
  const agora = relogioDoCobrarJuntas.agora();
  const hoje = diaLocal(agora);
  const refs = referenciasDosOrcamentos(args?.os);
  const clienteDito = String(args?.cliente_id ?? "").trim() || null;

  // 1) As OS.
  let linhas: OSLida[];
  if (refs.length) {
    const ditas = await osDitas(db, refs);
    if (ehErro(ditas)) return ditas;
    const problemas = ditas.map(problemaDaOS).filter((p): p is string => !!p);
    if (problemas.length) return { error: `${problemas.join(" ")} Explique ao dono e proponha cobrar juntas sem ela.` };
    const clientes = new Set(ditas.map((o) => o.client_id ?? ""));
    if (clientes.size > 1) return { error: "As OS são de clientes diferentes: cobrar juntas só junta OS do MESMO cliente." };
    if (clienteDito && ditas[0].client_id !== clienteDito) return { error: "As OS ditas não são desse cliente: confira o cliente e os números." };
    // Na ordem do número (como a tela, osComSaldo), não na ordem em que o dono falou.
    linhas = [...ditas].sort((a, b) => a.service_order_number.localeCompare(b.service_order_number));
  } else {
    linhas = ((await ler<OSLida[]>(
      db.from("service_orders").select(COLUNAS_DA_OS).eq("client_id", clienteDito).in("status", [...STATUS_QUE_COBRAM_JUNTAS]),
      "as OS do cliente",
    )) ?? []).filter((o) => !o.merged_into_id).sort((a, b) => a.service_order_number.localeCompare(b.service_order_number));
  }
  const clienteId = linhas[0]?.client_id ?? clienteDito;
  if (!clienteId) return { error: "As OS não têm cliente no cadastro: não há para quem cobrar." };

  // 2) O cliente (genérico, opt-out, telefone).
  const cliente = await ler<ClienteLido | null>(db.from("clients").select(COLUNAS_DO_CLIENTE).eq("id", clienteId).maybeSingle(), "o cadastro do cliente");
  if (!cliente) return { error: "Não achei o cadastro do cliente das OS." };
  const nomeDoCliente = String(cliente.name ?? "").trim() || "sem nome";
  // Genérico recusa antes de qualquer conta: o "Cliente Final" nunca entra (decisão do dono de 28/10/2026).
  if (cliente.generico) return { error: travaDoCobrarJuntas({ clienteNome: nomeDoCliente, generico: true, totalEmAberto: 0 })! };

  // 3) As contas com saldo de cada OS (canceladas e pagas fora; sinal pago fora).
  const ids = linhas.map((o) => o.id);
  const contasLidas = ids.length
    ? (await ler<ContaLida[]>(db.from("receivables").select(COLUNAS_DA_CONTA).in("service_order_id", ids), "as contas a receber das OS")) ?? []
    : [];
  const comSaldo = contasLidas.filter((c) => saldoDaConta(c) > 0);
  const os: OSDaCobranca[] = linhas.map((o) => {
    const contas = comSaldo.filter((c) => c.service_order_id === o.id)
      .sort((a, b) => String(a.due_date ?? "").localeCompare(String(b.due_date ?? "")) || a.id.localeCompare(b.id));
    return {
      id: o.id, numero: o.service_order_number, status: o.status, contas,
      saldo: reais(contas.reduce((t, c) => t + centavos(saldoDaConta(c)), 0)),
      vencido: contas.some((c) => contaVencida(c, hoje)),
    };
  });
  const semSaldo = os.filter((o) => o.saldo <= 0);
  const entram = os.filter((o) => o.saldo > 0);
  if (refs.length && semSaldo.length) {
    const quais = semSaldo.map((o) => o.numero).join(", ");
    const resto = entram.length >= MIN_AGRUPAR
      ? `Sem ${semSaldo.length === 1 ? "ela" : "elas"}, dá para cobrar juntas ${entram.map((o) => o.numero).join(", ")}.`
      : entram.length === 1
      ? `Sobra só ${entram[0].numero}: cobre pela cobrança dela (send_collection_reminder).`
      : "Não há o que cobrar.";
    return { error: `${quais} não ${semSaldo.length === 1 ? "tem" : "têm"} saldo em aberto. ${resto}` };
  }
  if (entram.length < MIN_AGRUPAR) {
    return {
      error: entram.length === 1
        ? `${nomeDoCliente} tem saldo em aberto só na ${entram[0].numero}: cobre pela cobrança dela (send_collection_reminder).`
        : `${nomeDoCliente} não tem OS executada com saldo em aberto.`,
    };
  }
  if (entram.length > MAX_AGRUPAR) return { error: `${nomeDoCliente} tem ${entram.length} OS com saldo: diga até 10 para cobrar juntas.` };
  const contas = entram.flatMap((o) => o.contas);

  // 4) Conta em nome de outro cadastro: genérico recusa com a frase do genérico; outro cliente de verdade (o
  //    pagador) também recusa — cobra-se o TITULAR da conta, como a tela, e o Pix esperando conferido abaixo é o
  //    do cliente que recebe a mensagem. Avisar só deixava a dívida de um ir ao WhatsApp de outro.
  const avisos: string[] = [];
  const outros = [...new Set(contas.map((c) => c.client_id).filter((x): x is string => !!x && x !== cliente.id))];
  if (outros.length) {
    const deOutros = await ler<Array<{ id: string; name: string | null; generico: boolean | null }>>(
      db.from("clients").select("id, name, generico").in("id", outros), "o cadastro das contas",
    ) ?? [];
    const generico = deOutros.find((c) => c.generico);
    if (generico) {
      const nome = String(generico.name ?? "").trim() || "sem nome";
      return { error: travaDoCobrarJuntas({ clienteNome: nome, generico: true, totalEmAberto: 0 })! };
    }
    const deOutroTitular: string[] = [];
    for (const o of entram) {
      const nomes = [...new Set(o.contas.filter((c) => c.client_id && c.client_id !== cliente.id)
        .map((c) => String(deOutros.find((x) => x.id === c.client_id)?.name ?? "outro cadastro").trim()))];
      if (nomes.length) deOutroTitular.push(`A conta da ${o.numero} está em nome de ${nomes.join(", ")}, não de ${nomeDoCliente}.`);
    }
    if (deOutroTitular.length) {
      return {
        error: `${deOutroTitular.join(" ")} Cobrar juntas cobra o titular da conta: cobre pela ficha de quem está na conta ` +
          "(Cobrar juntas na tela) ou tire essa OS do pedido.",
      };
    }
  }

  // 5) As travas do lembrete (piso, Pix esperando, opt-out, telefone) sobre o TOTAL em aberto.
  const cfg = await configuracoes(admin);
  const emAberto = reais(contas.reduce((t, c) => t + centavos(saldoDaConta(c)), 0));
  const pago = reais(contas.reduce((t, c) => t + centavos(pagoDaConta(c)), 0));
  const pix = (await pixEsperandoNoExtrato({ admin } as ToolCtx, [cliente.id])).get(cliente.id) ?? [];
  const telefone = telefoneParaEnvio(cliente.whatsapp || cliente.phone) ?? "";
  const trava = travaDoCobrarJuntas({
    clienteNome: nomeDoCliente,
    generico: !!cliente.generico,
    optOut: !!cliente.opt_out_whatsapp,
    piso: Number(cfg.collection_min_amount) || 0,
    totalEmAberto: emAberto,
    pixEsperando: pix.map((p) => ({ valor: p.valor, data: p.data })),
    telefone,
  });
  if (trava) return { error: trava };
  if (!telefone) return { error: "Sem telefone válido no cadastro do cliente para enviar a cobrança." };

  // 6) As cobranças que ganham o registro do envio, e os avisos do que o dono precisa saber.
  const cobrancas = await cobrancasDasContas(db, contas, entram.map((o) => o.id));
  const emAndamento = entram.filter((o) => o.status === "in_progress");
  if (emAndamento.length) {
    avisos.push(`${emAndamento.map((o) => o.numero).join(", ")} ainda ${emAndamento.length === 1 ? "está" : "estão"} em andamento: entra na cobrança, mas a nota só depois de concluída.`);
  }
  const cobradasHoje = cobrancas.filter((c) => c.last_auto_sent_at && diaLocal(new Date(c.last_auto_sent_at)) === hoje);
  if (cobradasHoje.length) {
    const quais = [...new Set(cobradasHoje.map((c) => entram.find((o) => o.id === c.service_order_id || o.contas.some((x) => x.id === c.receivable_id))?.numero).filter(Boolean))];
    avisos.push(`Já houve lembrete hoje${quais.length ? ` para ${quais.join(", ")}` : ""}: o cliente vai receber outra mensagem no mesmo dia.`);
  }

  const mensagem = mensagemDaCobrancaConjunta({ cliente, os: entram, pixKey: cfg.pix_key, hoje });
  return { cliente, os: entram, total: reais(centavos(pago) + centavos(emAberto)), pago, emAberto, telefone, cobrancas, avisos, mensagem };
}

/** "⚠️ …" numa linha só: o executor devolve como recusa, sem pendência (RESUMO_QUE_RESOLVE em agent.ts). */
const recusa = (texto: string) => `⚠️ ${texto.replace(/\s*\n+\s*/g, " ").trim()}`;

/** Resumo da confirmação (painel e WhatsApp): cada OS com o saldo, o total, o número inteiro e a mensagem exata. */
// deno-lint-ignore no-explicit-any
export async function resumirCobrancaConjunta(admin: any, args: Record<string, unknown>): Promise<string> {
  const c = await montarCobrancaConjunta(admin, admin, args);
  if (ehErro(c)) return recusa(c.error);
  const nome = String(c.cliente.name ?? "").trim() || "cliente";
  return [
    `Cobrar juntas *${c.os.length}* OS de *${nome}* numa mensagem só, pelo WhatsApp *${telefoneLegivel(c.telefone)}*:`,
    ...c.os.map((o) => `- ${o.numero} · ${situacaoDaOS(o.status)} · em aberto *${emReais(o.saldo)}*${o.vencido ? " (vencido)" : ""}`),
    `Total em aberto: *${emReais(c.emAberto)}*`,
    `- Nada muda no financeiro: cada conta continua na sua OS. ${c.cobrancas.length
      ? `O envio fica registrado em ${plural(c.cobrancas.length, "cobrança", "cobranças")}.`
      : SEM_COBRANCA_FORMAL}`,
    ...c.avisos.map((a) => `- ${a}`),
    "Mensagem que vai ao cliente:",
    c.mensagem,
  ].join("\n");
}

/** O retrato que o "sim" aprova: o cliente, o telefone, as contas com o saldo de cada uma e o total. */
// deno-lint-ignore no-explicit-any
export async function retratoDaCobrancaConjunta(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  try {
    const c = await montarCobrancaConjunta(admin, admin, args);
    if (ehErro(c)) return null;
    return retratoDe(c);
  } catch {
    return null;
  }
}

function retratoDe(c: CobrancaConjunta): Record<string, unknown> {
  return {
    cliente: c.cliente.id,
    telefone: c.telefone,
    contas: c.os.flatMap((o) => o.contas).map((x) => ({ id: x.id, saldo: saldoDaConta(x) })).sort((a, b) => a.id.localeCompare(b.id)),
    total: c.emAberto,
  };
}

/** O que mudou entre o retrato aprovado e agora, em português; null = nada. */
export function oQueMudouNaCobrancaConjunta(retrato: Record<string, unknown>, agora: CobrancaConjunta): string | null {
  const novo = retratoDe(agora);
  if (retrato.cliente !== novo.cliente) return "o cliente das OS mudou";
  if (retrato.telefone !== novo.telefone) return "o telefone do cadastro do cliente mudou";
  const antes = Array.isArray(retrato.contas) ? retrato.contas as Array<{ id?: unknown; saldo?: unknown }> : [];
  const depois = novo.contas as Array<{ id: string; saldo: number }>;
  if (antes.map((x) => String(x.id)).sort().join("|") !== depois.map((x) => x.id).join("|")) return "as contas em aberto das OS não são mais as mesmas";
  const mexida = depois.find((x) => centavos(antes.find((a) => String(a.id) === x.id)?.saldo) !== centavos(x.saldo));
  if (mexida) return `o saldo em aberto mudou (era ${emReais(retrato.total)}, agora ${emReais(novo.total)})`;
  return null;
}

export const cobrarJuntasTools: ToolDef[] = [
  {
    name: "cobrar_juntas",
    description:
      "Cobra numa MENSAGEM SÓ, pelo WhatsApp do cadastro do cliente, o saldo em aberto de 2 a 10 OS JÁ EXECUTADAS (em andamento, " +
      "concluídas ou faturadas) do MESMO cliente: o extrato dessas OS, com o número da OS e o saldo de cada conta, o vencido pela " +
      "data, total, pago e em aberto, e a chave Pix. NÃO junta as OS nem muda conta nenhuma (cada conta continua na sua OS); só " +
      "registra o envio nas cobranças das contas. Diga as OS pelos números ou passe o cliente (id de search_clients) para cobrar " +
      "todas as OS executadas dele com saldo. OS que ainda não começou → agrupar_os (outra coisa: junta numa OS nova). Uma OS só → " +
      "send_collection_reminder. Recusa cadastro genérico (sem CPF/CNPJ), Pix do cliente esperando no Extrato, opt-out e valor " +
      "abaixo do piso. A chamada já pede o 'sim' ao dono mostrando a mensagem exata: não pergunte antes.",
    input_schema: {
      type: "object",
      properties: {
        os: {
          type: "array",
          items: { type: "string" },
          description: "As OS a cobrar juntas: números (OS-00045 ou só 45) ou ids, 2 a 10.",
        },
        cliente_id: { type: "string", description: "Id (UUID) do cliente — sem os números, entram todas as OS executadas dele com saldo." },
      },
    },
    // Mensagem a CLIENTE com valores, que não se desfaz — como send_collection_reminder.
    risk: "high",
    roles: CARGOS_DE_COBRAR_JUNTAS,
    gravarSolicitante: true,
    preValidar: (args, ctx) => validarPedidoDeCobrarJuntas(args, ctx),
    retratoDaPendencia: (args, ctx) => retratoDaCobrancaConjunta(ctx.admin, args),
    async execute(args, ctx) {
      if (!cargosQueContam(args, ctx).every((c) => CARGOS_DE_COBRAR_JUNTAS.includes(c as Role))) return { error: SEM_CARGO };
      const invalido = validarPedidoDeCobrarJuntas(args, { userRole: "admin" });
      if (invalido) return invalido;
      // O "sim" foi sobre o retrato: sem ele (não deu para tirar quando o pedido nasceu), não envia.
      const retrato = lerRetrato(args);
      if (!retrato) return { error: SEM_RETRATO };

      let c: CobrancaConjunta | { error: string };
      try {
        c = await montarCobrancaConjunta(ctx.sb, ctx.admin, args);
      } catch (e) {
        return { error: `Nada foi enviado: não consegui conferir as contas agora (${String((e as Error)?.message ?? e)}). Peça de novo.` };
      }
      if (ehErro(c)) return { error: `Nada foi enviado: ${c.error}` };
      const mudou = oQueMudouNaCobrancaConjunta(retrato, c);
      if (mudou) return { error: `Nada foi enviado: ${mudou} depois do pedido. Peça de novo que eu confiro e mostro a mensagem atualizada.` };

      const agora = relogioDoCobrarJuntas.agora();
      const numeros = c.os.map((o) => o.numero);
      // Portão de comunicação: horário (bloqueia) e estilo (avisa) — como o lembrete individual.
      const g = guardaDeEnvio(c.mensagem, {
        tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: true, texto: c.mensagem,
        horaBrasilia: horaEmBrasilia(agora),
      });
      if (g.bloqueado) {
        await registrarEnvio(ctx.admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: c.cliente.id, phone: c.telefone, preview: c.mensagem, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: `Nada foi enviado: ${g.motivo}` };
      }

      const contas = c.os.flatMap((o) => o.contas).map((x) => x.id);
      // Modo de teste: o whatsapp-send desvia o envio para o número de teste. A chave ganha ":teste"
      // e nada se registra nas cobranças — sem isso o teste "queimava" a chave do dia e marcava o
      // cliente como cobrado, e o envio de verdade no mesmo dia voltava deduplicated sem o cliente
      // receber. A pergunta é "a edge VAI desviar?" (marcar-enviado.ts), como no envio ao cliente.
      const modoTeste = desviadoPorTeste(ctx.settings);
      const chave = chaveDoCobrarJuntas(c.cliente.id, contas, diaLocal(agora), c.mensagem, modoTeste);
      const r = await sendWhatsapp(c.telefone, c.mensagem, ctx.jwt, chave, ctx.userId);
      await registrarEnvio(ctx.admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: c.cliente.id, phone: c.telefone, preview: c.mensagem, status: r.ok ? "sent" : "failed" });
      if (!r.ok) return { error: `A mensagem não saiu (${"error" in r ? r.error : "falha no envio"}). Nada foi registrado nas cobranças.` };
      const nome = String(c.cliente.name ?? "").trim() || "o cliente";
      if (r.deduplicated) {
        return {
          ok: true, ja_feito: true, os: numeros,
          aviso: modoTeste
            ? "Esta mesma cobrança já tinha saído hoje para o número de TESTE do WhatsApp; não reenviei."
            : `Esta mesma cobrança já tinha saído hoje para ${nome}; não reenviei.`,
        };
      }
      if (modoTeste) {
        const texto = `O modo de teste do WhatsApp está ligado: a cobrança conjunta (${numeros.join(", ")} — em aberto ${emReais(c.emAberto)}) foi para o número de TESTE, NÃO para ${nome}. Nada foi registrado nas cobranças. Diga isso.`;
        return {
          ok: true,
          cliente: nome,
          os: numeros,
          em_aberto: c.emAberto,
          enviado_para: "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente",
          cobrancas_registradas: 0,
          ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}),
          aviso: texto,
          message: texto,
        };
      }

      // Enviado: o contato 'whatsapp_sent' e o last_auto_sent_at em cada cobrança das contas (como o lembrete).
      const nota = `Cobrança conjunta enviada pelo assistente (WhatsApp): ${numeros.join(", ")} — em aberto ${emReais(c.emAberto)}`;
      const falhas: string[] = [];
      for (const col of c.cobrancas) {
        const falhou = await registrarEnvioDaCobranca(ctx.admin, col, ctx.userId || null, nota);
        if (falhou) falhas.push(falhou);
      }
      const registro = c.cobrancas.length
        ? falhas.length
          ? ` ${falhas[0]}`
          : ` Envio registrado em ${plural(c.cobrancas.length, "cobrança", "cobranças")}.`
        : "";
      const texto = `Cobrança conjunta enviada para ${nome} (${telefoneLegivel(c.telefone)}): ${numeros.join(", ")} — em aberto ${emReais(c.emAberto)}.${registro}`;
      return {
        ok: true,
        cliente: nome,
        os: numeros,
        em_aberto: c.emAberto,
        cobrancas_registradas: c.cobrancas.length - falhas.length,
        ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}),
        aviso: texto,
        message: texto,
      };
    },
  },
];
