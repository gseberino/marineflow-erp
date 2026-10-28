// Agrupar e desagrupar ORDENS DE SERVIÇO pelo assistente (28/10/2026) — paridade com o "Agrupar OS" da tela.
//
// Decisões do dono (spec de 27/10/2026): nasce uma OS NOVA (OS-<seq>) e as originais ficam canceladas como
// histórico (merged_into_id); só mesmo cliente E mesma embarcação ou veículo; 2 a 10; preços mantidos; condição
// de pagamento, contato e comissão do PRINCIPAL; e só OS que AINDA NÃO COMEÇARAM a ser executadas (sem hora
// apontada, despesa, passo de roteiro mexido, foto, baixa de estoque, diária — pesquisa de mercado: ninguém
// mescla OS executada). Desagrupar enquanto a agrupada não começou. Sempre com o "sim" do dono, por texto.
//
// Quem decide é o banco (agrupar_os / desagrupar_os e a leitura os_para_agrupar, migration 20261028120000):
// a tool recebe o que o dono disse (números OS ou ids, o principal) e o sistema resolve, confere e grava.
// A ordem do assistente — a mesma de agrupar orçamentos (agrupar-orcamentos.ts), sem o caso do reprovado:
//   1. listar_os_para_agrupar (só leitura): as OS da embarcação do mais NOVO para o mais antigo, com
//      elegível/motivo, as recentes que ficaram fora (concluída, cancelada, já agrupada) e as agrupadas ativas.
//   2. agrupar_os (pede o "sim"; a confirmação É a pergunta): o resumo lê o banco e mostra cada OS, a soma, o
//      principal, os recebíveis/sinais que passam para a nova (com valores) e os avisos (assinaturas ficam nas
//      originais, comissão e condição do principal, a regra da NFS-e). Impedimento (já começou, nota, fatura,
//      comissão lançada, outro cliente, ainda é orçamento…) NÃO vira pendência: o resumo é uma linha "⚠️ …" e o
//      executor a devolve como recusa (RESUMO_QUE_RESOLVE em agent.ts).
//   3. desagrupar_os (pede o "sim"): pelo número da agrupada ou de uma das originais.
// A FRONTEIRA com orçamentos: ainda é orçamento (status draft, sem converted_to_os_at) → agrupar_orcamentos;
// já virou OS → agrupar_os. Cada tool recusa o outro caso apontando a certa.
// O "sim" foi sobre o retrato (situação, total, cliente, embarcação, última alteração de cada OS e a soma dos
// recebíveis): se algo mudou entre o pedido e o "sim" — ou se o retrato não pôde ser tirado —, a execução
// recusa. As frases da EXECUÇÃO vão direto ao dono: português, sem nome de ferramenta.
import { cargosQueContam, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import { pareceNumeroDeOS } from "./os-referencia.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { CARGOS_DO_AGRUPAMENTO, dataBR, emReais, MAX_AGRUPAR, MIN_AGRUPAR, referenciasDosOrcamentos } from "./agrupar-orcamentos.ts";
import { ROTULOS_STATUS_OS } from "../../service-order-status.ts";
import { TERMO_GERAL } from "../../unidade.ts";

/** Situações de OS que podem ser agrupadas: as que ainda não começaram (spec, seção 9). */
export const STATUS_QUE_AGRUPAM: readonly string[] = ["scheduled", "open", "awaiting_parts", "awaiting_client", "approved"];
/** Situações que dizem por si que a execução já começou (ou acabou). */
const STATUS_EXECUTADOS: readonly string[] = ["in_progress", "completed", "invoiced"];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SEM_CARGO = "Só administrador ou financeiro agrupa ou desagrupa OS.";
const SEM_RETRATO_AGRUPAR = "Nada foi agrupado: não consegui conferir as OS quando o pedido foi feito. Peça de novo que eu confiro.";
const SEM_RETRATO_DESAGRUPAR = "Nada foi desfeito: não consegui conferir o agrupamento quando o pedido foi feito. Peça de novo que eu confiro.";
const JA_COMECOU =
  "Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.";

const centavos = (v: unknown): number => Math.round((Number(v) || 0) * 100);
const situacaoDaOS = (s: unknown) => ROTULOS_STATUS_OS[String(s) as keyof typeof ROTULOS_STATUS_OS] ?? String(s ?? "—");

// Guarda de tipo (o tsc do app roda sem strictNullChecks; ver ehErro em caixa.ts).
function ehErro(x: unknown): x is { error: string } {
  return !!x && typeof x === "object" && "error" in x;
}

/** A frase do banco, sem o código do erro na frente (as regras daqui usam 22023 e P0002 também). */
export function fraseDoBanco(e: unknown): string {
  return mensagemDoBanco(e).replace(/^(ERROR:\s*)?(22023|P0002):\s*/i, "");
}

/** A frase do banco terminada em ponto (as de os_para_agrupar já vêm com o número da OS e, em geral, com o ponto). */
const frasePronta = (t: unknown) => {
  const s = String(t ?? "").trim();
  return /[.!?]$/.test(s) ? s : `${s}.`;
};

/** "OS-00100", "os 100", "100" e "ordem 100" são o mesmo pedido: número sem prefixo, aqui, é OS. */
function chaveDaOS(ref: string): string {
  if (UUID_RE.test(ref)) return ref.toLowerCase();
  const t = ref.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const m = t.match(/^([A-Z]*)0*(\d+)$/);
  if (!m) return t;
  const prefixo = m[1] === "ORCAMENTO" || m[1] === "ORC" ? "ORC" : "OS";
  return `${prefixo}${m[2]}`;
}

/** Só número de documento (OS-00100, "100") ou id: "a última", "a do Starlink" e frases não identificam uma OS aqui. */
const referenciaValida = (r: string) => UUID_RE.test(r) || pareceNumeroDeOS(r);
const naoENumero = (r: string) => ({ error: `"${r}" não é número de OS: diga os números (ex.: OS-00100).` });

/** As OS ditas: lista ou texto "OS-00100, OS-00128" — sem vazios, como vieram. */
export const referenciasDasOS = referenciasDosOrcamentos;

/** Recusa sem banco (antes da pendência): cargo, 2 a 10, só números/ids, sem repetidos. */
export function validarPedidoDeAgruparOS(args: Record<string, unknown> | undefined, ctx: Pick<ToolCtx, "userRole">): { error: string } | null {
  if (!CARGOS_DO_AGRUPAMENTO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
  const refs = referenciasDasOS(args?.os);
  if (refs.length < MIN_AGRUPAR) return { error: "Diga pelo menos 2 OS para agrupar (números OS ou ids)." };
  if (refs.length > MAX_AGRUPAR) return { error: "Agrupe no máximo 10 OS de uma vez." };
  const torto = refs.find((r) => !referenciaValida(r));
  if (torto) return naoENumero(torto);
  const chaves = refs.map(chaveDaOS);
  const repetido = refs.find((_r, i) => chaves.indexOf(chaves[i]) !== i);
  if (repetido) return { error: `A mesma OS foi dita duas vezes (${repetido}).` };
  const principal = String(args?.principal ?? "").trim();
  if (principal && !referenciaValida(principal)) return naoENumero(principal);
  return null;
}

/** A linha de cada OS que o resumo, o retrato e a execução leem. */
export interface LinhaDaOS {
  id: string;
  service_order_number: string;
  status: string;
  quote_status: string | null;
  grand_total: number | null;
  created_at: string;
  updated_at: string;
  client_id: string;
  vessel_id: string;
  merged_into_id: string | null;
  converted_to_os_at: string | null;
  signed_at: string | null;
  travel_cost_total: number | null;
  travel_distance_km: number | null;
  travel_hours: number | null;
  ferry_cost: number | null;
  commission_rate: number | null;
  commissioned_person: string | null;
  payment_conditions: string | null;
  payment_condition_preset_id: string | null;
  discount_amount: number | null;
  tax_amount: number | null;
}

const COLUNAS =
  "id, service_order_number, status, quote_status, grand_total, created_at, updated_at, client_id, vessel_id, merged_into_id, " +
  "converted_to_os_at, signed_at, travel_cost_total, travel_distance_km, travel_hours, ferry_cost, commission_rate, " +
  "commissioned_person, payment_conditions, payment_condition_preset_id, discount_amount, tax_amount";

/** Mesma ordem do banco: created_at, depois id (o 1º é o principal padrão). */
const porData = (ls: LinhaDaOS[]) =>
  [...ls].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)) || a.id.localeCompare(b.id));

/** Ainda é orçamento: rascunho que não virou OS. */
const aindaEOrcamento = (o: Pick<LinhaDaOS, "status" | "converted_to_os_at">) => o.status === "draft" && !o.converted_to_os_at;

/** Uma referência vira a OS (número sem prefixo = OS; "ORÇ-…" acha o orçamento, que a conferência recusa). Nunca chuta. */
// deno-lint-ignore no-explicit-any
async function acharOrdem(cliente: any, ref: string): Promise<{ id: string; numero: string } | { error: string }> {
  const achado = await localizarOrdem(cliente, ref, "os");
  if ("opcoes" in achado) return { error: `${ref}: existe mais de um documento com esse número (${achado.opcoes.join(" e ")}). Qual deles?` };
  if ("erro" in achado) return { error: `${ref}: ${achado.erro}` };
  return { id: achado.ordem.id, numero: achado.ordem.service_order_number };
}

/** Lê as OS (leitura que falha LANÇA: erro engolido viraria "não achei"). */
// deno-lint-ignore no-explicit-any
async function lerOS(cliente: any, ids: string[]): Promise<LinhaDaOS[]> {
  const { data, error } = await cliente.from("service_orders").select(COLUNAS).in("id", ids);
  if (error) throw new Error(`Não consegui ler as OS: ${error.message}`);
  return (data ?? []) as LinhaDaOS[];
}

/** O pedido resolvido: as origens (na ordem do banco), o principal e a soma. */
export interface PedidoDeAgruparOS {
  origens: LinhaDaOS[];
  principal: LinhaDaOS;
  total: number;
}

/** Resolve números/ids e o principal e lê as linhas. `cliente`: admin no resumo/retrato, sb na execução. */
// deno-lint-ignore no-explicit-any
export async function montarPedidoDeOS(cliente: any, args: Record<string, unknown>): Promise<PedidoDeAgruparOS | { error: string }> {
  const refs = referenciasDasOS(args?.os);
  if (refs.length < MIN_AGRUPAR) return { error: "Diga pelo menos 2 OS para agrupar (números OS ou ids)." };
  if (refs.length > MAX_AGRUPAR) return { error: "Agrupe no máximo 10 OS de uma vez." };
  const achados: Array<{ id: string; numero: string }> = [];
  for (const ref of refs) {
    const a = await acharOrdem(cliente, ref);
    if (ehErro(a)) return a;
    if (achados.some((x) => x.id === a.id)) return { error: `A mesma OS foi dita duas vezes (${a.numero}).` };
    achados.push(a);
  }
  const linhas = await lerOS(cliente, achados.map((a) => a.id));
  const faltando = achados.filter((a) => !linhas.some((l) => l.id === a.id));
  if (faltando.length) return { error: `Não achei ${faltando.map((f) => f.numero).join(", ")}.` };
  const origens = porData(linhas);

  let principal = origens[0];
  const refPrincipal = String(args?.principal ?? "").trim();
  if (refPrincipal) {
    const p = await acharOrdem(cliente, refPrincipal);
    if (ehErro(p)) return { error: `Principal ${p.error}` };
    const escolhida = origens.find((o) => o.id === p.id);
    if (!escolhida) return { error: `A principal (${p.numero}) precisa estar entre as OS escolhidas.` };
    principal = escolhida;
  }
  return { origens, principal, total: origens.reduce((t, o) => t + centavos(o.grand_total), 0) / 100 };
}

/** O que o resumo usa de cada OS da leitura os_para_agrupar. */
export interface OSDaLeitura {
  id: string;
  numero?: string;
  criado_em?: string;
  data?: string;
  total?: number;
  status?: string;
  situacao?: string;
  elegivel?: boolean;
  motivo?: string | null;
  condicao_pagamento?: string | null;
}
export interface LeituraDeOS {
  embarcacao?: { nome?: string };
  cliente?: { nome?: string } | null;
  os?: OSDaLeitura[];
  fora_da_lista?: unknown[];
  /** As OS agrupadas ativas da embarcação (tipo 'os'), com se dá para desagrupar e o motivo (frase pronta do banco). */
  agrupados_ativos?: Array<{ id: string; numero: string; origens?: string[]; pode_desagrupar?: boolean; motivo?: string | null }>;
}

/** A leitura do banco para a embarcação (mesmas regras do agrupar). `incluir`: as escolhidas, conferidas mesmo fora das mais novas. */
// deno-lint-ignore no-explicit-any
async function lerDoBarco(cliente: any, vessel: string, client: string | null, autor: string | null, incluir: string[] = []): Promise<LeituraDeOS | { error: string }> {
  const { data, error } = await cliente.rpc("os_para_agrupar", {
    p_vessel_id: vessel, p_client_id: client, p_autor: autor, ...(incluir.length ? { p_incluir: incluir } : {}),
  });
  if (error) return { error: fraseDoBanco(error) };
  return (data ?? {}) as LeituraDeOS;
}

/**
 * O que impede o agrupamento, em frases para o modelo — vazio = pode seguir. As que o banco certamente
 * recusaria: já agrupada, ainda é orçamento (→ agrupar_orcamentos), cancelada, já começou a ser executada,
 * cliente ou embarcação diferentes, inelegível pela leitura (nota, fatura, comissão lançada, execução, total
 * velho, repasse do cartão) e deslocamento em mais de uma.
 */
export function problemasDoPedidoDeOS(pedido: PedidoDeAgruparOS, leitura: LeituraDeOS | null, destinos: Record<string, string>): string[] {
  const problemas: string[] = [];
  const itens = new Map((leitura?.os ?? []).map((i) => [i.id, i]));
  const { origens, principal } = pedido;
  const foraDeVez: string[] = [];

  for (const o of origens) {
    const n = o.service_order_number;
    const item = itens.get(o.id);
    const fora = (texto: string) => {
      problemas.push(texto);
      foraDeVez.push(o.id);
    };
    if (o.merged_into_id) fora(`${n} já foi agrupada em ${destinos[o.merged_into_id] ?? "outra OS"}: não pode entrar de novo.`);
    else if (aindaEOrcamento(o)) {
      fora(`${n} ainda é orçamento (não virou OS): para juntar orçamentos, use agrupar_orcamentos — agrupar_os só junta OS.`);
    } else if (o.status === "cancelled") fora(`${n} está cancelada: não entra no agrupamento.`);
    else if (STATUS_EXECUTADOS.includes(o.status)) {
      fora(`${n} já começou a ser executada (situação: ${situacaoDaOS(o.status)}). ${JA_COMECOU} Explique ao dono e proponha agrupar sem ela.`);
    } else if (!STATUS_QUE_AGRUPAM.includes(o.status)) fora(`${n} está ${situacaoDaOS(o.status)}: só OS que ainda não começaram entram.`);
    else if (o.client_id !== principal.client_id || o.vessel_id !== principal.vessel_id) {
      fora(`${n} é de outro cliente ou de outra embarcação ou veículo: só dá para agrupar OS do mesmo cliente e da mesma unidade.`);
    } else if (!item) fora(`Não consegui conferir ${n} na leitura do banco: liste as OS de novo.`);
    else if (item.elegivel === false && item.motivo) {
      // O motivo do banco (_os_impedimento_para_agrupar) é a frase inteira, com o número: "OS-X tem fatura. …".
      fora(`${frasePronta(item.motivo)} Explique ao dono e proponha deixá-la de fora (ou resolver isso antes). ` +
        "Nunca sugira cancelar nota, fatura, comissão ou apagar horas/despesas para caber.");
    }
  }

  const comDeslocamento = origens.filter((o) =>
    !foraDeVez.includes(o.id) &&
    [o.travel_cost_total, o.travel_distance_km, o.travel_hours, o.ferry_cost].some((v) => centavos(v) !== 0)
  );
  if (comDeslocamento.length > 1) {
    problemas.push(`Mais de uma tem deslocamento (${comDeslocamento.map((o) => o.service_order_number).join(", ")}): deixe o deslocamento em uma só antes de agrupar, para não cobrar a viagem duas vezes.`);
  }

  if (problemas.length && foraDeVez.length) {
    const sobram = origens.filter((o) => !foraDeVez.includes(o.id)).map((o) => o.service_order_number);
    const sem = foraDeVez.length === 1 ? "Sem ela" : "Sem elas";
    problemas.push(sobram.length < MIN_AGRUPAR
      ? `${sem}, sobram menos de 2 OS: não há o que agrupar.`
      : comDeslocamento.length > 1
      ? `${sem}, sobram ${sobram.join(", ")}.`
      : `${sem}, dá para agrupar ${sobram.join(", ")}.`);
  }
  return problemas;
}

/** "⚠️ …" numa linha só: o executor devolve como recusa, sem pendência (RESUMO_QUE_RESOLVE). */
const recusa = (texto: string) => `⚠️ ${texto.replace(/\s*\n+\s*/g, " ").trim()}`;

/** Os números das agrupadas para onde as origens já foram (só para a frase). */
// deno-lint-ignore no-explicit-any
async function numerosDosDestinos(cliente: any, origens: Array<{ merged_into_id: string | null }>): Promise<Record<string, string>> {
  const ids = [...new Set(origens.map((o) => o.merged_into_id).filter((x): x is string => !!x))];
  if (!ids.length) return {};
  const { data } = await cliente.from("service_orders").select("id, service_order_number").in("id", ids);
  return Object.fromEntries(((data ?? []) as Array<{ id: string; service_order_number: string }>).map((d) => [d.id, d.service_order_number]));
}

/** Os recebíveis ativos das OS — os que passam para a nova (sem mudar valor nem situação). Leitura que falha LANÇA. */
export interface RecebivelDaOS {
  id: string;
  service_order_id: string;
  description: string | null;
  amount: number | null;
  paid_amount: number | null;
  status: string | null;
  is_deposit: boolean | null;
}
// deno-lint-ignore no-explicit-any
async function lerRecebiveis(cliente: any, ids: string[]): Promise<RecebivelDaOS[]> {
  const { data, error } = await cliente.from("receivables")
    .select("id, service_order_id, description, amount, paid_amount, status, is_deposit").in("service_order_id", ids);
  if (error) throw new Error(`Não consegui ler os recebíveis das OS: ${error.message}`);
  // Como o banco (_os_agrupar_mover: status is distinct from 'cancelled'): o de situação nula também passa.
  // O .neq do PostgREST o deixaria de fora (null <> 'cancelled' é nulo), e a soma do retrato ficaria menor.
  return ((data ?? []) as RecebivelDaOS[]).filter((r) => r.status !== "cancelled");
}

/** As OS com assinatura do cliente que vale (não substituída). Leitura que falha LANÇA. */
// deno-lint-ignore no-explicit-any
async function osAssinadas(cliente: any, origens: LinhaDaOS[]): Promise<Set<string>> {
  const { data, error } = await cliente.from("service_order_signatures")
    .select("service_order_id, superseded_at").in("service_order_id", origens.map((o) => o.id));
  if (error) throw new Error(`Não consegui ler as assinaturas das OS: ${error.message}`);
  const assinadas = new Set(origens.filter((o) => !!o.signed_at).map((o) => o.id));
  for (const s of (data ?? []) as Array<{ service_order_id: string; superseded_at: string | null }>) {
    if (!s.superseded_at) assinadas.add(s.service_order_id);
  }
  return assinadas;
}

const SITUACAO_DO_RECEBIVEL: Record<string, string> = {
  pending: "em aberto", paid: "pago", partial: "pago em parte", overdue: "vencido", received: "recebido",
};

/** "OS-00100: sinal R$ 2.869,50 (pago)" — os recebíveis de cada OS na ordem das origens. */
export function linhasDosRecebiveis(origens: LinhaDaOS[], recebiveis: RecebivelDaOS[]): string[] {
  return origens.flatMap((o) => {
    const deles = recebiveis.filter((r) => r.service_order_id === o.id);
    if (!deles.length) return [];
    const cada = deles.map((r) => {
      const nome = r.is_deposit ? "sinal" : String(r.description ?? "").trim() || "recebível";
      const sit = SITUACAO_DO_RECEBIVEL[String(r.status ?? "")] ?? String(r.status ?? "");
      return `${nome} ${emReais(r.amount)}${sit ? ` (${sit})` : ""}`;
    });
    return [`${o.service_order_number}: ${cada.join("; ")}`];
  });
}

/** Avisos do que muda ao juntar (nada aqui impede: o deslocamento duplo já virou recusa). */
function avisosDoAgrupamentoDeOS(pedido: PedidoDeAgruparOS, assinadas: Set<string>): string[] {
  const { origens } = pedido;
  const avisos: string[] = [];
  const pct = (v: unknown) => `${(Number(v) || 0).toLocaleString("pt-BR", { maximumFractionDigits: 2 })}%`;
  const comAssinatura = origens.filter((o) => assinadas.has(o.id));
  if (comAssinatura.length) {
    avisos.push(`Assinaturas ficam nas OS originais (${comAssinatura.map((o) => o.service_order_number).join(", ")}): o cliente assinou ` +
      "aquele documento. A OS nova nasce sem assinatura; se precisar, peça a assinatura dela.");
  }
  const chaveComissao = (o: LinhaDaOS) => `${Number(o.commission_rate) || 0}|${String(o.commissioned_person ?? "").trim().toLowerCase()}`;
  if (new Set(origens.map(chaveComissao)).size > 1) {
    const cada = origens.map((o) => `${o.service_order_number} ${Number(o.commission_rate) > 0 ? pct(o.commission_rate) : "sem comissão"}`).join("; ");
    avisos.push(`Comissões diferentes (${cada}): vale a da principal.`);
  }
  const chavePagamento = (o: LinhaDaOS) => `${o.payment_condition_preset_id ?? ""}|${String(o.payment_conditions ?? "").trim().toLowerCase()}`;
  if (new Set(origens.map(chavePagamento)).size > 1) avisos.push("Condições de pagamento diferentes entre as OS: vale a da principal.");
  if (new Set(origens.map((o) => o.status)).size > 1) {
    avisos.push(`Situações diferentes (${origens.map((o) => `${o.service_order_number} ${situacaoDaOS(o.status)}`).join("; ")}): a nova nasce com a da principal.`);
  }
  const comDesconto = origens.filter((o) => centavos(o.discount_amount) !== 0);
  if (comDesconto.length) {
    const soma = comDesconto.reduce((t, o) => t + centavos(o.discount_amount), 0) / 100;
    avisos.push(`Desconto no cabeçalho em ${comDesconto.map((o) => o.service_order_number).join(", ")}: vira um desconto só de ${emReais(soma)} sobre a OS inteira.`);
  }
  const comImposto = origens.filter((o) => centavos(o.tax_amount) !== 0);
  if (comImposto.length) {
    const soma = comImposto.reduce((t, o) => t + centavos(o.tax_amount), 0) / 100;
    avisos.push(`Imposto no cabeçalho em ${comImposto.map((o) => o.service_order_number).join(", ")}: vira um valor só de ${emReais(soma)}.`);
  }
  // Regra fiscal (spec, seção 9): lembrar, não bloquear.
  avisos.push("Nota de serviço: uma NFS-e cobre um tomador, um código de serviço e uma competência — confira antes de emitir a da OS nova.");
  return avisos;
}

/**
 * Resumo da confirmação de agrupar_os (painel e WhatsApp). Lê o banco com o service role e confere com a
 * leitura os_para_agrupar (em nome de quem pede). Problema = uma linha "⚠️ …" (recusa).
 */
// deno-lint-ignore no-explicit-any
export async function resumirAgrupamentoDeOS(admin: any, args: Record<string, unknown>, autor: string | null): Promise<string> {
  const pedido = await montarPedidoDeOS(admin, args);
  if (ehErro(pedido)) return recusa(pedido.error);
  const { origens, principal, total } = pedido;

  // Tudo orçamento: a recusa já diz qual tool usar, sem ler a embarcação.
  const destinos = await numerosDosDestinos(admin, origens);
  if (origens.every(aindaEOrcamento)) {
    return recusa(`${origens.map((o) => o.service_order_number).join(", ")} ainda são orçamentos (não viraram OS): para juntar ` +
      "orçamentos, use agrupar_orcamentos — agrupar_os só junta OS.");
  }
  const leitura = await lerDoBarco(admin, principal.vessel_id, principal.client_id, autor, origens.map((o) => o.id));
  if (ehErro(leitura)) return recusa(`Não consegui conferir as OS: ${leitura.error}`);
  const problemas = problemasDoPedidoDeOS(pedido, leitura, destinos);
  if (problemas.length) return recusa(problemas.join(" "));

  const ids = origens.map((o) => o.id);
  const recebiveis = await lerRecebiveis(admin, ids);
  const assinadas = await osAssinadas(admin, origens);
  const itens = new Map((leitura.os ?? []).map((i) => [i.id, i]));
  const condicao = itens.get(principal.id)?.condicao_pagamento || principal.payment_conditions?.trim() || "sem condição definida";
  const comissao = Number(principal.commission_rate) > 0
    ? `${(Number(principal.commission_rate)).toLocaleString("pt-BR", { maximumFractionDigits: 2 })}%${principal.commissioned_person ? ` para ${principal.commissioned_person}` : ""}, recalculada sobre o total novo`
    : "nenhuma";
  const quem = [leitura.cliente?.nome, leitura.embarcacao?.nome].filter(Boolean).join(" · ");
  const somaRecebiveis = recebiveis.reduce((t, r) => t + centavos(r.amount), 0) / 100;
  const doDinheiro = linhasDosRecebiveis(origens, recebiveis);

  const linhas = [
    `Agrupar *${origens.length}* OS${quem ? ` de *${quem}*` : ""} em uma OS NOVA (${situacaoDaOS(principal.status)}, como a principal):`,
    ...origens.map((o) =>
      `- ${o.service_order_number} · ${dataBR(o.created_at)} · ${situacaoDaOS(o.status)} · ${emReais(o.grand_total)}${o.id === principal.id ? " ← principal" : ""}`
    ),
    `Total previsto: *${emReais(total)}* (a soma das originais)`,
    `Principal: *${principal.service_order_number}* — dela vêm a situação, a condição de pagamento (${condicao}), o contato e a comissão (${comissao}).`,
    "- Preços mantidos como estão em cada OS; os técnicos de todas ficam na nova.",
    doDinheiro.length
      ? `- Passam para a OS nova, sem mudar valor nem situação (total ${emReais(somaRecebiveis)}): ${doDinheiro.join(" · ")}.`
      : "- Nenhum recebível ou sinal ligado às OS.",
    "- Cobranças, lembretes de cobrança, tarefas manuais pendentes, pedidos de compra e cotações ligados também passam para a nova.",
    ...avisosDoAgrupamentoDeOS(pedido, assinadas).map((a) => `- ${a}`),
    "- As originais ficam canceladas como histórico, com o link do cliente desligado (envio agendado com o link antigo é cancelado).",
    "- Dá para desagrupar enquanto a nova não começar a ser executada (horas, despesas, fotos, baixa de estoque, nota).",
  ];
  return linhas.join("\n");
}

/** O retrato que o "sim" aprova: cada OS como estava, a principal, a soma e a soma dos recebíveis. */
// deno-lint-ignore no-explicit-any
export async function retratoDoAgrupamentoDeOS(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  const pedido = await montarPedidoDeOS(admin, args);
  if (ehErro(pedido)) return null;
  let recebiveis: RecebivelDaOS[];
  try {
    recebiveis = await lerRecebiveis(admin, pedido.origens.map((o) => o.id));
  } catch {
    return null;
  }
  return {
    origens: pedido.origens.map((o) => ({
      id: o.id, numero: o.service_order_number, status: o.status, grand_total: Number(o.grand_total) || 0,
      updated_at: o.updated_at, client_id: o.client_id, vessel_id: o.vessel_id,
    })),
    principal: pedido.principal.id,
    total: pedido.total,
    recebiveis: recebiveis.reduce((t, r) => t + centavos(r.amount), 0) / 100,
  };
}

/** O que mudou entre o retrato aprovado e agora, em português; null = nada. */
export function oQueMudouNoAgrupamentoDeOS(retrato: Record<string, unknown>, pedido: PedidoDeAgruparOS, recebiveisAgora: number | null): string | null {
  const antes = Array.isArray(retrato.origens) ? retrato.origens as Array<Record<string, unknown>> : [];
  const idsAntes = antes.map((o) => String(o.id)).sort().join("|");
  const idsAgora = pedido.origens.map((o) => o.id).sort().join("|");
  if (idsAntes !== idsAgora) return "as OS escolhidas não são mais as mesmas do pedido";
  if (retrato.principal && retrato.principal !== pedido.principal.id) return "a principal mudou";
  const mudancas: string[] = [];
  for (const o of pedido.origens) {
    const a = antes.find((x) => x.id === o.id)!;
    const n = o.service_order_number;
    if (a.status !== o.status) mudancas.push(`${n} mudou de situação`);
    else if (Math.abs((Number(a.grand_total) || 0) - (Number(o.grand_total) || 0)) > 0.005) {
      mudancas.push(`o total de ${n} mudou (era ${emReais(a.grand_total)}, agora ${emReais(o.grand_total)})`);
    } else if (a.client_id !== o.client_id) mudancas.push(`${n} mudou de cliente`);
    else if (a.vessel_id !== o.vessel_id) mudancas.push(`${n} mudou de ${TERMO_GERAL.toLowerCase()}`);
    else if (new Date(String(a.updated_at)).getTime() !== new Date(String(o.updated_at)).getTime()) mudancas.push(`${n} foi alterada`);
  }
  if (!mudancas.length && recebiveisAgora != null && typeof retrato.recebiveis === "number" &&
    Math.abs(retrato.recebiveis - recebiveisAgora) > 0.005) {
    mudancas.push(`os recebíveis das OS mudaram (eram ${emReais(retrato.recebiveis)}, agora ${emReais(recebiveisAgora)})`);
  }
  return mudancas.length ? mudancas.join("; ") : null;
}

/** Já está feito: duas pendências do mesmo agrupamento e as duas aprovadas — a segunda diz que já está agrupado. */
// deno-lint-ignore no-explicit-any
async function jaAgrupadas(cliente: any, pedido: PedidoDeAgruparOS): Promise<Record<string, unknown> | null> {
  const destinos = new Set(pedido.origens.map((o) => o.merged_into_id ?? null));
  const [destino] = [...destinos];
  if (destinos.size !== 1 || !destino) return null;
  const numero = (await numerosDosDestinos(cliente, pedido.origens))[destino] ?? "outra OS";
  const nums = pedido.origens.map((o) => o.service_order_number).join(", ");
  return { ok: true, ja_feito: true, numero, aviso: `Já estava feito: ${nums} já foram agrupadas em ${numero}; nada novo foi gravado.` };
}

/** Erro do banco na execução, para o dono (a frase "mudaram desde que a tela abriu" é da tela). */
function erroDoAgrupar(error: unknown): string {
  const msg = fraseDoBanco(error);
  return /mudaram desde que a tela abriu/.test(msg)
    ? "Nada foi agrupado: a soma das OS mudou depois do pedido. Peça de novo que eu confiro."
    : msg;
}

// ── desagrupar ───────────────────────────────────────────────────────────────────────────────

interface OrigemDaOSAgrupada {
  id: string;
  numero: string;
  status_antes: string | null;
  grand_total_antes: number | null;
}

interface AgrupadaLida {
  agrupada: LinhaDaOS;
  /** As origens do agrupamento ATIVO de OS (vazio = não é agrupada ou já foi desfeita). */
  origens: OrigemDaOSAgrupada[];
  /** O dono disse o número de uma das ORIGINAIS: esse número. */
  ditoPelaOrigem: string | null;
  /** Há agrupamento desfeito desta agrupada (e nenhum ativo): já foi desagrupada. */
  desfeito: boolean;
  /** O agrupamento ativo é de ORÇAMENTOS (tipo 'orcamento'): quem desfaz é desagrupar_orcamento. */
  deOrcamentos: boolean;
}

/** Os agrupamentos (ativo e desfeitos) em que `id` é a agrupada. Leitura que falha LANÇA. */
// deno-lint-ignore no-explicit-any
async function gruposDaAgrupada(cliente: any, id: string): Promise<Array<{ id: string; desfeito_em: string | null; tipo?: string | null }>> {
  const { data, error } = await cliente.from("orcamento_agrupamentos").select("id, desfeito_em, tipo").eq("agrupado_id", id);
  if (error) throw new Error(`Não consegui ler o agrupamento: ${error.message}`);
  return (data ?? []) as Array<{ id: string; desfeito_em: string | null; tipo?: string | null }>;
}

/** A agrupada (pelo número/id dela OU de uma das originais) e as origens do agrupamento ativo. */
// deno-lint-ignore no-explicit-any
async function lerAgrupada(cliente: any, ref: unknown): Promise<AgrupadaLida | { error: string }> {
  const r = String(ref ?? "").trim();
  if (!r) return { error: "Diga qual OS agrupada desfazer (o número OS da agrupada ou de uma das originais)." };
  const a = await acharOrdem(cliente, r);
  if (ehErro(a)) return a;
  const [linha] = await lerOS(cliente, [a.id]);
  if (!linha) return { error: `Não achei ${a.numero}.` };

  let agrupada = linha;
  let ditoPelaOrigem: string | null = null;
  let grupos = await gruposDaAgrupada(cliente, linha.id);
  // Número de uma das originais: a agrupada é o destino dela (merged_into_id só existe no agrupamento ativo).
  if (!grupos.some((g) => !g.desfeito_em) && linha.merged_into_id) {
    const [destino] = await lerOS(cliente, [linha.merged_into_id]);
    if (destino) {
      agrupada = destino;
      ditoPelaOrigem = linha.service_order_number;
      grupos = await gruposDaAgrupada(cliente, destino.id);
    }
  }
  const ativo = grupos.find((g) => !g.desfeito_em);
  if (!ativo) return { agrupada, origens: [], ditoPelaOrigem, desfeito: grupos.length > 0, deOrcamentos: false };
  if ((ativo.tipo ?? "orcamento") !== "os") return { agrupada, origens: [], ditoPelaOrigem, desfeito: false, deOrcamentos: true };
  const { data: origens, error: e2 } = await cliente.from("orcamento_agrupamento_origens")
    .select("origem_id, numero, ordem, status_antes, grand_total_antes").eq("agrupamento_id", ativo.id).order("ordem", { ascending: true });
  if (e2) throw new Error(`Não consegui ler as originais do agrupamento: ${e2.message}`);
  return {
    agrupada,
    origens: ((origens ?? []) as Array<{ origem_id: string; numero: string; ordem?: number; status_antes?: string | null; grand_total_antes?: number | null }>)
      .sort((x, y) => (Number(x.ordem) || 0) - (Number(y.ordem) || 0))
      .map((o) => ({ id: o.origem_id, numero: o.numero, status_antes: o.status_antes ?? null, grand_total_antes: o.grand_total_antes ?? null })),
    ditoPelaOrigem,
    desfeito: false,
    deOrcamentos: false,
  };
}

/** Por que não dá para desagrupar, pelo que se lê; null = pode. */
function problemaDoDesagruparOS(l: AgrupadaLida, leitura: LeituraDeOS | null, destino: string | null): string | null {
  const n = l.agrupada.service_order_number;
  if (l.deOrcamentos) {
    return `${n} reúne orçamentos (não OS): para desfazer esse agrupamento, use desagrupar_orcamento.`;
  }
  if (!l.origens.length) return `${n} não é uma OS agrupada (ou já foi desagrupada).`;
  if (l.agrupada.merged_into_id) return `${n} foi agrupada de novo em ${destino ?? "outra OS"}: desagrupe ${destino ?? "aquela"} primeiro.`;
  if (l.agrupada.status === "cancelled") return `${n} está cancelada: não dá mais para desagrupar.`;
  if (STATUS_EXECUTADOS.includes(l.agrupada.status)) {
    return `${n} já começou a ser executada (situação: ${situacaoDaOS(l.agrupada.status)}): não dá mais para desagrupar; ela mantém o histórico.`;
  }
  // O motivo do banco (_os_impedimento_para_desagrupar) é a frase inteira, com o número.
  const ativa = leitura?.agrupados_ativos?.find((g) => g.id === l.agrupada.id);
  if (ativa && ativa.pode_desagrupar === false && ativa.motivo) return frasePronta(ativa.motivo);
  return null;
}

// deno-lint-ignore no-explicit-any
export async function resumirDesagrupamentoDeOS(admin: any, args: Record<string, unknown>, autor: string | null): Promise<string> {
  const l = await lerAgrupada(admin, args?.os_agrupada);
  if (ehErro(l)) return recusa(l.error);
  let leitura: LeituraDeOS | null = null;
  if (l.origens.length) {
    const lida = await lerDoBarco(admin, l.agrupada.vessel_id, l.agrupada.client_id, autor);
    if (ehErro(lida)) return recusa(`Não consegui conferir a OS agrupada: ${lida.error}`);
    leitura = lida;
  }
  const destinos = await numerosDosDestinos(admin, [l.agrupada]);
  const problema = problemaDoDesagruparOS(l, leitura, l.agrupada.merged_into_id ? destinos[l.agrupada.merged_into_id] ?? null : null);
  if (problema) return recusa(problema);
  const n = l.agrupada.service_order_number;
  const cada = l.origens.map((o) => `*${o.numero}* (${situacaoDaOS(o.status_antes)}, ${emReais(o.grand_total_antes)})`).join(", ");
  return [
    `${l.ditoPelaOrigem ? `${l.ditoPelaOrigem} está agrupada em ${n}. ` : ""}Desagrupar *${n}* (${emReais(l.agrupada.grand_total)}):`,
    `- Voltam a valer, como estavam antes de agrupar (situação e link do cliente): ${cada}.`,
    "- Recebíveis, sinais, cobranças, tarefas e compras que vieram delas voltam cada um para a sua OS de origem.",
    `- ${n} fica cancelada como histórico, com o link do cliente desligado.`,
    `- O que foi acrescentado ou editado em ${n} depois de agrupar NÃO volta para as originais.`,
  ].join("\n");
}

// deno-lint-ignore no-explicit-any
export async function retratoDoDesagrupamentoDeOS(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  const l = await lerAgrupada(admin, args?.os_agrupada);
  if (ehErro(l) || !l.origens.length) return null;
  return { agrupada: l.agrupada.id, status: l.agrupada.status, updated_at: l.agrupada.updated_at, origens: l.origens.map((o) => o.id) };
}

function podeAgrupar(args: unknown, ctx: ToolCtx): { error: string } | null {
  return cargosQueContam(args, ctx).every((c) => CARGOS_DO_AGRUPAMENTO.includes(c as Role)) ? null : { error: SEM_CARGO };
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

export const agruparOsTools: ToolDef[] = [
  {
    name: "listar_os_para_agrupar",
    description:
      "Lista as ORDENS DE SERVIÇO de uma embarcação ou veículo (e do cliente, se passar) que podem ser AGRUPADAS: do mais NOVO para " +
      "o mais antigo, com número, data, situação, total, se pode entrar (elegivel) e, se não pode, o motivo (já começou a ser " +
      "executada, nota, fatura, comissão lançada…); as recentes que ficaram fora (concluída, cancelada, já agrupada); e as OS " +
      "agrupadas ativas (para desagrupar). Só OS (já aprovadas); orçamento é listar_orcamentos_para_agrupar. Use ANTES de " +
      "agrupar_os. Resolva antes a unidade com search_vessels. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        embarcacao_id: { type: "string", description: "Id (UUID) da embarcação ou veículo — ache com search_vessels." },
        cliente_id: { type: "string", description: "Id (UUID) do cliente (o dono da unidade), se souber." },
      },
      required: ["embarcacao_id"],
    },
    risk: "low",
    roles: CARGOS_DO_AGRUPAMENTO,
    async execute(args, ctx) {
      if (!CARGOS_DO_AGRUPAMENTO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
      const barco = String(args?.embarcacao_id ?? "").trim();
      const cliente = String(args?.cliente_id ?? "").trim();
      if (!UUID_RE.test(barco)) return { error: "Passe o id da embarcação ou veículo (ache com search_vessels)." };
      if (cliente && !UUID_RE.test(cliente)) return { error: "Passe o id do cliente (ache com search_clients) ou deixe vazio." };
      const { data, error } = await ctx.sb.rpc("os_para_agrupar", {
        p_vessel_id: barco,
        p_client_id: cliente || null,
        p_autor: ctx.userId || null,
      });
      if (error) return { error: fraseDoBanco(error) };
      return {
        ...(data ?? {}),
        instrucao:
          "'As N últimas' = as N primeiras de 'os' (mais novas). Alguma de fora_da_lista é mais nova que elas? Diga ao dono. Todas " +
          "elegíveis: chame agrupar_os já — a confirmação mostra a lista, a principal, o total e o dinheiro que passa para a nova; " +
          "não pergunte antes. Impedida (já começou a ser executada, nota, fatura, comissão): diga o motivo e proponha agrupar sem ela; " +
          "nunca sugira apagar horas, despesas ou cancelar nota para caber. Não mostre ids.",
      };
    },
  },
  {
    name: "agrupar_os",
    description:
      "Junta 2 a 10 ORDENS DE SERVIÇO que ainda NÃO começaram a ser executadas, do MESMO cliente e da MESMA embarcação ou veículo, " +
      "numa OS NOVA (número novo), com a soma das originais e os preços como estão. Situação, condição de pagamento, contato e " +
      "comissão vêm da PRINCIPAL (padrão: a mais antiga); a comissão é recalculada. Recebíveis, sinais, cobranças, tarefas manuais, " +
      "compras e técnicos passam para a nova; as assinaturas ficam nas originais, que ficam canceladas como histórico. Ainda é " +
      "orçamento? Use agrupar_orcamentos. Use depois de listar_os_para_agrupar. A chamada já pede o 'sim' ao dono: não pergunte antes.",
    input_schema: {
      type: "object",
      properties: {
        os: {
          type: "array",
          items: { type: "string" },
          description: "As OS a juntar: números (OS-00100 ou só 100) ou ids, 2 a 10.",
        },
        principal: { type: "string", description: "Número ou id da principal (situação, condição, contato e comissão). Padrão: a mais antiga." },
      },
      required: ["os"],
    },
    risk: "medium",
    roles: CARGOS_DO_AGRUPAMENTO,
    gravarSolicitante: true,
    preValidar: (args, ctx) => validarPedidoDeAgruparOS(args, ctx),
    retratoDaPendencia: (args, ctx) => retratoDoAgrupamentoDeOS(ctx.admin, args),
    async execute(args, ctx) {
      const semCargo = podeAgrupar(args, ctx);
      if (semCargo) return semCargo;
      const invalido = validarPedidoDeAgruparOS(args, { userRole: "admin" });
      if (invalido) return invalido;
      const pedido = await montarPedidoDeOS(ctx.sb, args);
      if (ehErro(pedido)) return pedido;

      const feito = await jaAgrupadas(ctx.sb, pedido);
      if (feito) return feito;
      // O "sim" foi sobre o retrato: sem ele (não deu para tirar quando o pedido nasceu), não executa.
      const retrato = lerRetrato(args);
      if (!retrato) return { error: SEM_RETRATO_AGRUPAR };
      let recebiveisAgora: number | null = null;
      try {
        recebiveisAgora = (await lerRecebiveis(ctx.sb, pedido.origens.map((o) => o.id))).reduce((t, r) => t + centavos(r.amount), 0) / 100;
      } catch {
        return { error: SEM_RETRATO_AGRUPAR };
      }
      const mudou = oQueMudouNoAgrupamentoDeOS(retrato, pedido, recebiveisAgora);
      if (mudou) return { error: `Nada foi agrupado: ${mudou} depois do pedido. Peça de novo que eu confiro e mostro a lista atualizada.` };

      const totalEsperado = Number.isFinite(Number(retrato.total)) ? Number(retrato.total) : pedido.total;
      const { data, error } = await ctx.sb.rpc("agrupar_os", {
        p_os: pedido.origens.map((o) => o.id),
        p_base: pedido.principal.id,
        p_total_esperado: totalEsperado,
        p_autor: ctx.userId || null,
      });
      if (error) return { error: erroDoAgrupar(error) };
      // deno-lint-ignore no-explicit-any
      const r = (data ?? {}) as any;
      const base = (ctx.settings?.app_public_url || "").replace(/\/+$/, "");
      const origens: string[] = Array.isArray(r.origens) ? r.origens : pedido.origens.map((o) => o.service_order_number);
      const avisos: string[] = Array.isArray(r.avisos) ? r.avisos.map(String).filter(Boolean) : [];
      const movidos = Number(r.recebiveis_movidos) || 0;
      const dinheiro = movidos ? ` ${plural(movidos, "recebível passou", "recebíveis passaram")} para a nova, sem mudar valor nem situação.` : "";
      // No "✅" vão só os avisos que a confirmação não disse (assinaturas, data de atendimento diferente): a
      // condição da principal, as situações diferentes e a regra da NFS-e o dono já leu antes do "sim".
      const novos = avisos.filter((a) =>
        !/^(Na hora da nota|Condição de pagamento, contato e comissão|As OS estavam em situações diferentes)/.test(a)
      );
      const extra = novos.length ? ` ${novos.join(" ")}` : "";
      return {
        ok: true,
        numero: r.numero,
        os_id: r.service_order_id,
        origens,
        principal: r.principal ?? pedido.principal.service_order_number,
        total: r.total_geral,
        comissao: r.comissao ?? null,
        servicos: r.servicos,
        pecas: r.pecas,
        recebiveis_movidos: movidos,
        cobrancas_movidas: Number(r.cobrancas_movidas) || 0,
        tarefas_movidas: Number(r.tarefas_movidas) || 0,
        tecnicos: Number(r.tecnicos) || 0,
        envios_cancelados: r.envios_cancelados ?? 0,
        avisos,
        ...(base && r.service_order_id ? { link_interno: `${base}/service-orders/${r.service_order_id}` } : {}),
        // O "✅ … executado." do "sim" (sino e WhatsApp) mostra o aviso: é ali que o dono lê o número novo.
        aviso: `Nova OS ${r.numero}, com ${origens.join(", ")} — ${emReais(r.total_geral)}. As originais ficaram canceladas como ` +
          `histórico, com o link desligado.${dinheiro}${extra}`,
        message:
          `Pronto: ${r.numero} reúne ${origens.join(", ")} — total ${emReais(r.total_geral)}.${dinheiro} As originais ficaram canceladas ` +
          `como histórico, com o link desligado. Para desfazer enquanto ${r.numero} não começar a ser executada, é só pedir para desagrupar.`,
      };
    },
  },
  {
    name: "desagrupar_os",
    description:
      "Desfaz um agrupamento de OS: as OS originais voltam como estavam (situação e link do cliente), recebíveis, sinais, cobranças, " +
      "tarefas e compras voltam cada um para a sua, e a agrupada fica cancelada como histórico. Só enquanto a agrupada não começou a " +
      "ser executada (sem horas, despesas, fotos, baixa de estoque, nota). O que foi acrescentado na agrupada NÃO volta para as " +
      "originais — avise o dono. Orçamento agrupado é desagrupar_orcamento. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        os_agrupada: { type: "string", description: "Número (OS-00131) ou id da OS AGRUPADA — ou de uma das originais dela." },
      },
      required: ["os_agrupada"],
    },
    risk: "medium",
    roles: CARGOS_DO_AGRUPAMENTO,
    gravarSolicitante: true,
    preValidar(args, ctx) {
      if (!CARGOS_DO_AGRUPAMENTO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
      const ref = String(args?.os_agrupada ?? "").trim();
      if (!ref) return { error: "Diga qual OS agrupada desfazer (o número OS da agrupada ou de uma das originais)." };
      if (!referenciaValida(ref)) return naoENumero(ref);
      return null;
    },
    retratoDaPendencia: (args, ctx) => retratoDoDesagrupamentoDeOS(ctx.admin, args),
    async execute(args, ctx) {
      const semCargo = podeAgrupar(args, ctx);
      if (semCargo) return semCargo;
      // O "sim" foi sobre o retrato: a agrupada é a dele (o número dito pode ter sido o de uma original).
      const retrato = lerRetrato(args);
      if (!retrato || typeof retrato.agrupada !== "string") return { error: SEM_RETRATO_DESAGRUPAR };
      const l = await lerAgrupada(ctx.sb, retrato.agrupada);
      if (ehErro(l)) return l;
      const n = l.agrupada.service_order_number;
      if (!l.origens.length && l.desfeito) {
        return { ok: true, ja_feito: true, agrupada: n, aviso: `Já estava desfeito: ${n} já tinha sido desagrupada; nada novo foi gravado.` };
      }

      const mudou = retrato.agrupada !== l.agrupada.id
        || retrato.status !== l.agrupada.status
        || new Date(String(retrato.updated_at)).getTime() !== new Date(String(l.agrupada.updated_at)).getTime()
        || (Array.isArray(retrato.origens) ? [...retrato.origens].map(String).sort().join("|") : "") !== l.origens.map((o) => o.id).sort().join("|");
      if (mudou) return { error: `Nada foi desfeito: ${n} mudou depois do pedido. Peça de novo que eu confiro.` };

      const { data, error } = await ctx.sb.rpc("desagrupar_os", { p_agrupado: l.agrupada.id, p_autor: ctx.userId || null });
      if (error) return { error: fraseDoBanco(error) };
      // deno-lint-ignore no-explicit-any
      const r = (data ?? {}) as any;
      const origens: string[] = Array.isArray(r.origens) ? r.origens : l.origens.map((o) => o.numero);
      const devolvidos = Number(r.registros_devolvidos) || 0;
      const volta = devolvidos ? ` ${plural(devolvidos, "registro ligado voltou", "registros ligados voltaram")} para a sua OS de origem.` : "";
      const texto = `${origens.join(", ")} voltaram a valer como estavam; ${r.agrupado ?? n} ficou cancelada como histórico.${volta}`;
      return {
        ok: true,
        agrupada: r.agrupado ?? n,
        origens,
        registros_devolvidos: devolvidos,
        envios_cancelados: r.envios_cancelados ?? 0,
        envios_reativados: r.envios_reativados ?? 0,
        aviso: texto,
        message: `Desfeito: ${texto}`,
      };
    },
  },
];
