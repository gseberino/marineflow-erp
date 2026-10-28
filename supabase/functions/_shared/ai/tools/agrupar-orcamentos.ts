// Agrupar e desagrupar orçamentos pelo assistente (15/10/2026) — paridade com o "Agrupar orçamentos" da tela.
//
// Pedido do dono: "Agrupe os 3 últimos orçamentos do Rodrigo, do motorhome VW Delivery" tem de pedir
// confirmação — e, se um dos últimos estiver reprovado, o assistente pergunta sobre ele (do que se trata, o
// total, desde quando) e se ele entra, antes de gravar qualquer coisa.
//
// Quem decide é o banco (agrupar_orcamentos / desagrupar_orcamentos, migration 20261015180000; a leitura
// orcamentos_para_agrupar e agrupar_orcamentos_reabrindo, migration 20261015181000): a tool recebe o que o
// dono disse (números ORÇ ou ids, o principal, os reprovados que ENTRAM) e o sistema resolve, confere e grava.
// A ordem do assistente:
//   1. listar_orcamentos_para_agrupar (só leitura): os em aberto da embarcação do mais NOVO para o mais
//      antigo — inclusive os reprovados, que contam nos "N últimos" — com elegível/motivo, e os documentos
//      recentes que ficaram fora da lista (virou OS, cancelado, já agrupado).
//   2. agrupar_orcamentos (pede o "sim"; a confirmação É a pergunta — nada de "posso agrupar?" antes): o
//      resumo da pendência é montado lendo o banco. Reprovado que o dono não disse que entra, inelegível,
//      embarcação/cliente diferentes, já agrupado ou já virou OS NÃO viram pendência: o resumo é uma linha
//      "⚠️ …" e o executor a devolve como recusa (RESUMO_QUE_RESOLVE em agent.ts) — com a PERGUNTA a fazer ao
//      dono, no caso do reprovado. Reprovado que o dono disse que entra vai em voltar_para_em_elaboracao: a
//      confirmação mostra "Reprovado → volta para Em elaboração e entra", e ele só sai de Reprovado no "sim",
//      na mesma transação do agrupamento (agrupar_orcamentos_reabrindo). Antes do "sim" nada muda.
//   3. desagrupar_orcamento (pede o "sim"): pelo número do agrupado ou de um dos originais; os originais
//      voltam como estavam (o reaberto volta como Reprovado); o agrupado fica cancelado.
// O "sim" foi sobre o retrato (situação, total, cliente, embarcação e última alteração de cada orçamento):
// se algo mudou entre o pedido e o "sim" — ou se o retrato não pôde ser tirado —, a execução recusa. As
// frases da EXECUÇÃO vão direto ao dono (o modelo não participa do "sim"): português, sem nome de ferramenta.
import { cargosQueContam, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { acharOS, pareceNumeroDeOS } from "./os-referencia.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { TERMO_GERAL } from "../../unidade.ts";

/** O banco aceita só administrador ou financeiro (is_admin_or_financial). */
export const CARGOS_DO_AGRUPAMENTO: Role[] = ["admin", "financial"];
export const MIN_AGRUPAR = 2;
export const MAX_AGRUPAR = 10;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SEM_CARGO = "Só administrador ou financeiro agrupa ou desagrupa orçamentos.";
const SEM_RETRATO_AGRUPAR = "Nada foi agrupado: não consegui conferir os orçamentos quando o pedido foi feito. Peça de novo que eu confiro.";
const SEM_RETRATO_DESAGRUPAR = "Nada foi desfeito: não consegui conferir o agrupamento quando o pedido foi feito. Peça de novo que eu confiro.";

const fmtBRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
export const emReais = (v: unknown): string => fmtBRL.format(Number(v) || 0);
const centavos = (v: unknown): number => Math.round((Number(v) || 0) * 100);

/** dd/mm/aaaa no horário de Brasília ("" se a data não presta). */
export function dataBR(iso: unknown): string {
  const d = new Date(String(iso ?? ""));
  return isNaN(d.getTime()) ? "" : d.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
}
/** dd/mm no horário de Brasília. */
const diaMes = (iso: unknown): string => dataBR(iso).slice(0, 5);

// Guarda de tipo (o tsc do app roda sem strictNullChecks; ver ehErro em caixa.ts).
function ehErro(x: unknown): x is { error: string } {
  return !!x && typeof x === "object" && "error" in x;
}

/** Situação do orçamento com os rótulos da tela (src/lib/constants.ts) — os mesmos de orcamentos_para_agrupar. */
export const SITUACAO_DO_ORCAMENTO: Record<string, string> = {
  draft: "Em elaboração",
  sent: "Enviado",
  awaiting_approval: "Aguardando aprovação",
  approved: "Aprovado",
  awaiting_deposit: "Aguardando sinal",
  rejected: "Reprovado",
};
const situacao = (qs: unknown) => SITUACAO_DO_ORCAMENTO[String(qs || "draft")] ?? String(qs);

/** Os orçamentos ditos: lista ou texto "ORÇ-00120, ORÇ-00096" — sem vazios, como vieram. */
export function referenciasDosOrcamentos(v: unknown): string[] {
  const bruto = Array.isArray(v) ? v : typeof v === "string" ? v.split(/[,;\n]+/) : [];
  return bruto.map((x) => String(x ?? "").trim()).filter(Boolean);
}

/** "ORÇ-00120", "orc 120" e "ORC-120" são o mesmo pedido de número: para achar repetido antes do banco. */
function chaveDaReferencia(ref: string): string {
  if (UUID_RE.test(ref)) return ref.toLowerCase();
  const t = ref.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const m = t.match(/^([A-Z]*)0*(\d+)$/);
  return m ? `${m[1] === "ORCAMENTO" ? "ORC" : m[1]}${m[2]}` : t;
}

/**
 * Só número de documento (ORÇ-00120, "120") ou id: "último", "o do Starlink" e frases não identificam um
 * orçamento aqui — a busca por número resolveria "último" para o documento mais recente de QUALQUER cliente.
 */
const referenciaValida = (r: string) => UUID_RE.test(r) || pareceNumeroDeOS(r);
const naoENumero = (r: string) => ({ error: `"${r}" não é número de orçamento: diga os números (ex.: ORÇ-00120).` });

/** Recusa sem banco (antes da pendência): cargo, 2 a 10, só números/ids, sem repetidos. */
export function validarPedidoDeAgrupar(args: Record<string, unknown> | undefined, ctx: Pick<ToolCtx, "userRole">): { error: string } | null {
  if (!CARGOS_DO_AGRUPAMENTO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
  const refs = referenciasDosOrcamentos(args?.orcamentos);
  if (refs.length < MIN_AGRUPAR) return { error: "Diga pelo menos 2 orçamentos para agrupar (números ORÇ ou ids)." };
  if (refs.length > MAX_AGRUPAR) return { error: "Agrupe no máximo 10 orçamentos de uma vez." };
  const torto = refs.find((r) => !referenciaValida(r));
  if (torto) return naoENumero(torto);
  const chaves = refs.map(chaveDaReferencia);
  const repetido = refs.find((_r, i) => chaves.indexOf(chaves[i]) !== i);
  if (repetido) return { error: `O mesmo orçamento foi dito duas vezes (${repetido}).` };
  const principal = String(args?.principal ?? "").trim();
  if (principal && !referenciaValida(principal)) return naoENumero(principal);
  const voltaTorto = referenciasDosOrcamentos(args?.voltar_para_em_elaboracao).find((r) => !referenciaValida(r));
  if (voltaTorto) return naoENumero(voltaTorto);
  return null;
}

/** A linha de cada orçamento que o resumo, o retrato e a execução leem. */
export interface LinhaDoOrcamento {
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
  "converted_to_os_at, travel_cost_total, travel_distance_km, travel_hours, ferry_cost, commission_rate, commissioned_person, " +
  "payment_conditions, payment_condition_preset_id, discount_amount, tax_amount";

/** Mesma ordem do banco: created_at, depois id (é a ordem das linhas no orçamento novo; o 1º é o principal padrão). */
const porData = (ls: LinhaDoOrcamento[]) =>
  [...ls].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)) || a.id.localeCompare(b.id));

/** Cada referência vira o orçamento (pelo número dito ou pelo id), na ordem dita. Nunca chuta. */
// deno-lint-ignore no-explicit-any
async function resolverReferencias(cliente: any, refs: string[]): Promise<Array<{ id: string; numero: string }> | { error: string }> {
  const achados: Array<{ id: string; numero: string }> = [];
  for (const ref of refs) {
    const a = await acharOS({ admin: cliente }, { service_order_id: ref });
    if (ehErro(a)) return { error: `${ref}: ${a.error}` };
    if (achados.some((x) => x.id === a.id)) return { error: `O mesmo orçamento foi dito duas vezes (${a.numero}).` };
    achados.push({ id: a.id, numero: a.numero });
  }
  return achados;
}

/** Lê os orçamentos (leitura que falha LANÇA: erro engolido viraria "não achei"). */
// deno-lint-ignore no-explicit-any
async function lerOrcamentos(cliente: any, ids: string[]): Promise<LinhaDoOrcamento[]> {
  const { data, error } = await cliente.from("service_orders").select(COLUNAS).in("id", ids);
  if (error) throw new Error(`Não consegui ler os orçamentos: ${error.message}`);
  return (data ?? []) as LinhaDoOrcamento[];
}

/** O pedido resolvido: as origens (na ordem do banco), o principal, a soma e os reprovados que o dono disse que entram. */
export interface PedidoDeAgrupar {
  origens: LinhaDoOrcamento[];
  principal: LinhaDoOrcamento;
  total: number;
  /** Os escolhidos que estão Reprovados E o dono disse que entram (voltar_para_em_elaboracao). */
  reabrir: LinhaDoOrcamento[];
}

/** Resolve números/ids, o principal e os que voltam para Em elaboração e lê as linhas. `cliente`: admin no resumo/retrato, sb na execução. */
// deno-lint-ignore no-explicit-any
export async function montarPedido(cliente: any, args: Record<string, unknown>): Promise<PedidoDeAgrupar | { error: string }> {
  const refs = referenciasDosOrcamentos(args?.orcamentos);
  if (refs.length < MIN_AGRUPAR) return { error: "Diga pelo menos 2 orçamentos para agrupar (números ORÇ ou ids)." };
  if (refs.length > MAX_AGRUPAR) return { error: "Agrupe no máximo 10 orçamentos de uma vez." };
  const achados = await resolverReferencias(cliente, refs);
  if (ehErro(achados)) return achados;
  const linhas = await lerOrcamentos(cliente, achados.map((a) => a.id));
  const faltando = achados.filter((a) => !linhas.some((l) => l.id === a.id));
  if (faltando.length) return { error: `Não achei ${faltando.map((f) => f.numero).join(", ")}.` };
  const origens = porData(linhas);

  let principal = origens[0];
  const refPrincipal = String(args?.principal ?? "").trim();
  if (refPrincipal) {
    const p = await acharOS({ admin: cliente }, { service_order_id: refPrincipal });
    if (ehErro(p)) return { error: `Principal ${refPrincipal}: ${p.error}` };
    const escolhido = origens.find((o) => o.id === p.id);
    if (!escolhido) return { error: `O principal (${p.numero}) precisa estar entre os orçamentos escolhidos.` };
    principal = escolhido;
  }

  // Só sai de Reprovado quem está reprovado agora; um que já não está é ignorado (o retrato pega a mudança).
  const reabrir: LinhaDoOrcamento[] = [];
  for (const ref of referenciasDosOrcamentos(args?.voltar_para_em_elaboracao)) {
    const v = await acharOS({ admin: cliente }, { service_order_id: ref });
    if (ehErro(v)) return { error: `${ref}: ${v.error}` };
    const o = origens.find((x) => x.id === v.id);
    if (!o) return { error: `${v.numero} (que voltaria para Em elaboração) precisa estar entre os orçamentos escolhidos.` };
    if (o.quote_status === "rejected" && !reabrir.includes(o)) reabrir.push(o);
  }
  return { origens, principal, total: origens.reduce((t, o) => t + centavos(o.grand_total), 0) / 100, reabrir: porData(reabrir) };
}

/** O que o resumo usa de cada item de orcamentos_para_agrupar. */
interface ItemDaLeitura {
  id: string;
  numero?: string;
  criado_em?: string;
  data?: string;
  total?: number;
  situacao?: string;
  quote_status?: string;
  elegivel?: boolean;
  motivo?: string | null;
  reprovado_em?: string | null;
  impedimento_se_voltar?: string | null;
  resumo?: string | null;
  condicao_pagamento?: string | null;
}
interface LeituraDoBarco {
  embarcacao?: { nome?: string };
  cliente?: { nome?: string } | null;
  orcamentos?: ItemDaLeitura[];
  agrupados_ativos?: Array<{ id: string; numero: string; origens?: string[]; pode_desagrupar?: boolean; motivo?: string | null }>;
}

/**
 * A leitura do banco para a embarcação (mesmas regras do agrupar). `incluir`: os escolhidos, para virem
 * conferidos mesmo fora dos 20 mais novos. Erro vira { error } com a frase do banco.
 */
// deno-lint-ignore no-explicit-any
async function lerDoBarco(cliente: any, vessel: string, client: string | null, autor: string | null, incluir: string[] = []): Promise<LeituraDoBarco | { error: string }> {
  const { data, error } = await cliente.rpc("orcamentos_para_agrupar", {
    p_vessel_id: vessel, p_client_id: client, p_autor: autor, ...(incluir.length ? { p_incluir: incluir } : {}),
  });
  if (error) return { error: mensagemDoBanco(error) };
  return (data ?? {}) as LeituraDoBarco;
}

/**
 * A pergunta sobre um reprovado (o texto vai ao MODELO, que pergunta ao dono): do que se trata, o total e
 * desde quando — "deve questionar sobre o que estava reprovado" (pedido do dono, 15/10/2026). A pergunta é
 * "ele entra?", não "voltar ou agrupar os outros?": um "sim" solto não responde a ela.
 */
export function perguntaDoReprovado(r: { numero: string; resumo?: string | null; total?: unknown; reprovadoEm?: string | null }): string {
  const sobre = [String(r.resumo ?? "").trim(), r.total == null ? "" : emReais(r.total)].filter(Boolean).join(", ");
  const quando = r.reprovadoEm && diaMes(r.reprovadoEm) ? ` desde ${diaMes(r.reprovadoEm)}` : " (a data da reprovação não foi registrada)";
  return `${r.numero}${sobre ? ` (${sobre})` : ""} está reprovado${quando}. Antes de gravar qualquer coisa, pergunte ao dono se ele ` +
    `entra no agrupamento (o cliente voltou atrás?), dizendo do que se trata. Entra: chame agrupar_orcamentos de novo com ${r.numero} ` +
    `também em voltar_para_em_elaboracao — ele só sai de Reprovado no "sim" da confirmação. Fica de fora: agrupe só os outros. ` +
    `Resposta que não escolhe ("sim", "ok"): pergunte de novo.`;
}

/**
 * O que impede o agrupamento, lido no banco, em frases para o modelo — vazio = pode seguir. As que o banco
 * certamente recusaria: já agrupado, já virou OS/cancelado, cliente ou embarcação diferentes, reprovado que
 * o dono não disse que entra (vira a pergunta) ou que nem voltando pode entrar, inelegível pela leitura
 * (assinado, repasse do cartão, vínculos, total velho) e deslocamento em mais de um.
 */
export function problemasDoPedido(
  pedido: PedidoDeAgrupar,
  leitura: LeituraDoBarco | null,
  destinos: Record<string, string>,
): string[] {
  const problemas: string[] = [];
  const itens = new Map((leitura?.orcamentos ?? []).map((i) => [i.id, i]));
  const { origens, principal } = pedido;
  const reabre = new Set(pedido.reabrir.map((o) => o.id));
  const foraDeVez: string[] = [];

  for (const o of origens) {
    const n = o.service_order_number;
    const item = itens.get(o.id);
    const fora = (texto: string) => {
      problemas.push(texto);
      foraDeVez.push(o.id);
    };
    if (o.merged_into_id) fora(`${n} já foi agrupado em ${destinos[o.merged_into_id] ?? "outro orçamento"}: não pode entrar de novo.`);
    else if (o.status !== "draft" || o.converted_to_os_at) {
      // A fronteira com agrupar_os (28/10/2026): já virou OS → a tool de OS; cancelado → fora.
      fora(o.status === "cancelled"
        ? `${n} não é mais um orçamento em aberto (foi cancelado).`
        : `${n} não é mais um orçamento em aberto: já virou OS. Para juntar OS, use agrupar_os (listar_os_para_agrupar mostra as candidatas).`);
    }
    else if (o.client_id !== principal.client_id || o.vessel_id !== principal.vessel_id) {
      fora(`${n} é de outro cliente ou de outra embarcação ou veículo: só dá para agrupar orçamentos do mesmo cliente e da mesma unidade.`);
    } else if (!item) fora(`Não consegui conferir ${n} na leitura do banco: liste os orçamentos de novo.`);
    else if (o.quote_status === "rejected") {
      if (item.impedimento_se_voltar) {
        fora(`${n} está reprovado e, mesmo voltando para Em elaboração, não pode entrar: ${item.impedimento_se_voltar}. ` +
          `Explique ao dono e proponha agrupar sem ele (não ofereça incluí-lo).`);
      } else if (!reabre.has(o.id)) {
        fora(perguntaDoReprovado({ numero: n, resumo: item.resumo, total: o.grand_total, reprovadoEm: item.reprovado_em }));
      }
    } else if (item.elegivel === false && item.motivo) {
      fora(`${n} não pode entrar no agrupamento: ${item.motivo}. Explique ao dono e proponha deixá-lo de fora (ou resolver isso antes).`);
    }
  }

  const comDeslocamento = origens.filter((o) =>
    !foraDeVez.includes(o.id) &&
    [o.travel_cost_total, o.travel_distance_km, o.travel_hours, o.ferry_cost].some((v) => centavos(v) !== 0)
  );
  if (comDeslocamento.length > 1) {
    problemas.push(`Mais de um tem deslocamento (${comDeslocamento.map((o) => o.service_order_number).join(", ")}): deixe o deslocamento em um só antes de agrupar, para não cobrar a viagem duas vezes.`);
  }

  if (problemas.length && foraDeVez.length) {
    const sobram = origens.filter((o) => !foraDeVez.includes(o.id)).map((o) => o.service_order_number);
    const sem = foraDeVez.length === 1 ? "Sem ele" : "Sem eles";
    problemas.push(sobram.length < MIN_AGRUPAR
      ? `${sem}, sobram menos de 2 orçamentos: não há o que agrupar.`
      : comDeslocamento.length > 1
      ? `${sem}, sobram ${sobram.join(", ")}.`
      : `${sem}, dá para agrupar ${sobram.join(", ")}.`);
  }
  return problemas;
}

/**
 * Os em aberto da leitura que ficaram FORA do pedido e são mais novos que o mais antigo escolhido, do mais
 * novo para o mais antigo: "os 3 últimos" com um pulado (o reprovado, por exemplo) aparece na confirmação.
 */
export function foraDoPedido(pedido: PedidoDeAgrupar, leitura: LeituraDoBarco | null): ItemDaLeitura[] {
  const escolhidos = new Set(pedido.origens.map((o) => o.id));
  const desde = Math.min(...pedido.origens.map((o) => new Date(o.created_at).getTime()));
  return (leitura?.orcamentos ?? []).filter((i) => !escolhidos.has(i.id) && new Date(String(i.criado_em ?? "")).getTime() > desde);
}

/** "⚠️ …" numa linha só: o executor devolve como recusa, sem pendência (RESUMO_QUE_RESOLVE). */
const recusa = (texto: string) => `⚠️ ${texto.replace(/\s*\n+\s*/g, " ").trim()}`;

/** Os números dos agrupados para onde as origens já foram (só para a frase). */
// deno-lint-ignore no-explicit-any
async function numerosDosDestinos(cliente: any, origens: LinhaDoOrcamento[]): Promise<Record<string, string>> {
  const ids = [...new Set(origens.map((o) => o.merged_into_id).filter((x): x is string => !!x))];
  if (!ids.length) return {};
  const { data } = await cliente.from("service_orders").select("id, service_order_number").in("id", ids);
  return Object.fromEntries(((data ?? []) as Array<{ id: string; service_order_number: string }>).map((d) => [d.id, d.service_order_number]));
}

/** Avisos do que muda ao juntar (nada aqui impede: o deslocamento duplo já virou recusa). */
function avisosDoAgrupamento(pedido: PedidoDeAgrupar): string[] {
  const { origens } = pedido;
  const avisos: string[] = [];
  const pct = (v: unknown) => `${(Number(v) || 0).toLocaleString("pt-BR", { maximumFractionDigits: 2 })}%`;
  if (pedido.reabrir.length) {
    const nums = pedido.reabrir.map((o) => o.service_order_number).join(", ");
    avisos.push(`${nums} sai de Reprovado só com este "sim"; se desagrupar depois, volta como Reprovado.`);
  }
  const aceitos = origens.filter((o) => o.quote_status === "approved" || o.quote_status === "awaiting_deposit");
  if (aceitos.length) {
    avisos.push(`${aceitos.map((o) => `${o.service_order_number} (${situacao(o.quote_status)})`).join(", ")} já tinha o aceite do cliente: ` +
      "o orçamento novo nasce Em elaboração e precisa ser aprovado de novo.");
  }
  const chaveComissao = (o: LinhaDoOrcamento) => `${Number(o.commission_rate) || 0}|${String(o.commissioned_person ?? "").trim().toLowerCase()}`;
  if (new Set(origens.map(chaveComissao)).size > 1) {
    const cada = origens.map((o) => `${o.service_order_number} ${Number(o.commission_rate) > 0 ? pct(o.commission_rate) : "sem comissão"}`).join("; ");
    avisos.push(`Comissões diferentes (${cada}): vale a do principal.`);
  }
  const chavePagamento = (o: LinhaDoOrcamento) => `${o.payment_condition_preset_id ?? ""}|${String(o.payment_conditions ?? "").trim().toLowerCase()}`;
  if (new Set(origens.map(chavePagamento)).size > 1) avisos.push("Condições de pagamento diferentes entre os orçamentos: vale a do principal.");
  const comDesconto = origens.filter((o) => centavos(o.discount_amount) !== 0);
  if (comDesconto.length) {
    const soma = comDesconto.reduce((t, o) => t + centavos(o.discount_amount), 0) / 100;
    avisos.push(`Desconto no cabeçalho em ${comDesconto.map((o) => o.service_order_number).join(", ")}: vira um desconto só de ${emReais(soma)} sobre o orçamento inteiro.`);
  }
  const comImposto = origens.filter((o) => centavos(o.tax_amount) !== 0);
  if (comImposto.length) {
    const soma = comImposto.reduce((t, o) => t + centavos(o.tax_amount), 0) / 100;
    avisos.push(`Imposto no cabeçalho em ${comImposto.map((o) => o.service_order_number).join(", ")}: vira um valor só de ${emReais(soma)}.`);
  }
  return avisos;
}

/** No máximo tantas linhas "Fica de fora" na confirmação (o resto vira uma contagem). */
const MAX_DE_FORA_NO_RESUMO = 5;

/**
 * Resumo da confirmação de agrupar_orcamentos (painel e WhatsApp). Lê o banco com o service role e confere
 * com a leitura orcamentos_para_agrupar (em nome de quem pede). Problema = uma linha "⚠️ …" (recusa).
 */
// deno-lint-ignore no-explicit-any
export async function resumirAgrupamento(admin: any, args: Record<string, unknown>, autor: string | null): Promise<string> {
  const pedido = await montarPedido(admin, args);
  if (ehErro(pedido)) return recusa(pedido.error);
  const { origens, principal, total } = pedido;

  const leitura = await lerDoBarco(admin, principal.vessel_id, principal.client_id, autor, origens.map((o) => o.id));
  if (ehErro(leitura)) return recusa(`Não consegui conferir os orçamentos: ${leitura.error}`);

  const destinos = await numerosDosDestinos(admin, origens);
  const problemas = problemasDoPedido(pedido, leitura, destinos);
  if (problemas.length) return recusa(problemas.join(" "));

  const itens = new Map((leitura.orcamentos ?? []).map((i) => [i.id, i]));
  const reabre = new Set(pedido.reabrir.map((o) => o.id));
  const condicao = itens.get(principal.id)?.condicao_pagamento || principal.payment_conditions?.trim() || "sem condição definida";
  const comissao = Number(principal.commission_rate) > 0
    ? `${(Number(principal.commission_rate)).toLocaleString("pt-BR", { maximumFractionDigits: 2 })}%${principal.commissioned_person ? ` para ${principal.commissioned_person}` : ""}, recalculada sobre o total novo`
    : "nenhuma";
  const quem = [leitura.cliente?.nome, leitura.embarcacao?.nome].filter(Boolean).join(" · ");
  const deFora = foraDoPedido(pedido, leitura);

  const linhas = [
    `Agrupar *${origens.length}* orçamentos${quem ? ` de *${quem}*` : ""} em um orçamento NOVO (Em elaboração):`,
    ...origens.map((o) => {
      const sit = reabre.has(o.id) ? `${situacao("rejected")} → volta para Em elaboração e entra` : situacao(o.quote_status);
      return `- ${o.service_order_number} · ${dataBR(o.created_at)} · ${sit} · ${emReais(o.grand_total)}${o.id === principal.id ? " ← principal" : ""}`;
    }),
    ...deFora.slice(0, MAX_DE_FORA_NO_RESUMO).map((i) =>
      `- Fica de fora: ${i.numero ?? "—"} · ${i.data || dataBR(i.criado_em)} · ${i.situacao || situacao(i.quote_status)} · ${emReais(i.total)}`
    ),
    ...(deFora.length > MAX_DE_FORA_NO_RESUMO ? [`- Ficam de fora também mais ${deFora.length - MAX_DE_FORA_NO_RESUMO} em aberto.`] : []),
    `Total previsto: *${emReais(total)}* (a soma dos originais)`,
    `Principal: *${principal.service_order_number}* — dele vêm a condição de pagamento (${condicao}), o contato e a comissão (${comissao}).`,
    "- Preços mantidos como estão em cada orçamento.",
    ...avisosDoAgrupamento(pedido).map((a) => `- ${a}`),
    "- Os originais ficam cancelados como histórico, com o link do cliente desligado (envio agendado com o link antigo é cancelado).",
    "- Dá para desagrupar enquanto o novo não virar OS (nem for assinado ou tiver dinheiro ligado).",
  ];
  return linhas.join("\n");
}

/** O retrato que o "sim" aprova: cada origem como estava, o principal, a soma e os que saem de Reprovado. */
// deno-lint-ignore no-explicit-any
export async function retratoDoAgrupamento(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  const pedido = await montarPedido(admin, args);
  if (ehErro(pedido)) return null;
  return {
    origens: pedido.origens.map((o) => ({
      id: o.id, numero: o.service_order_number, status: o.status, quote_status: o.quote_status ?? null,
      grand_total: Number(o.grand_total) || 0, updated_at: o.updated_at, client_id: o.client_id, vessel_id: o.vessel_id,
    })),
    principal: pedido.principal.id,
    total: pedido.total,
    reabrir: pedido.reabrir.map((o) => o.id),
  };
}

/** O que mudou entre o retrato aprovado e agora, em português; null = nada. */
export function oQueMudouNoAgrupamento(retrato: Record<string, unknown>, pedido: PedidoDeAgrupar): string | null {
  const antes = Array.isArray(retrato.origens) ? retrato.origens as Array<Record<string, unknown>> : [];
  const idsAntes = antes.map((o) => String(o.id)).sort().join("|");
  const idsAgora = pedido.origens.map((o) => o.id).sort().join("|");
  if (idsAntes !== idsAgora) return "os orçamentos escolhidos não são mais os mesmos do pedido";
  if (retrato.principal && retrato.principal !== pedido.principal.id) return "o principal mudou";
  const reabrirAntes = Array.isArray(retrato.reabrir) ? (retrato.reabrir as unknown[]).map(String).sort().join("|") : "";
  if (reabrirAntes !== pedido.reabrir.map((o) => o.id).sort().join("|")) return "o que sairia de Reprovado mudou";
  const mudancas: string[] = [];
  for (const o of pedido.origens) {
    const a = antes.find((x) => x.id === o.id)!;
    const n = o.service_order_number;
    if (a.status !== o.status || (a.quote_status ?? null) !== (o.quote_status ?? null)) mudancas.push(`${n} mudou de situação`);
    else if (Math.abs((Number(a.grand_total) || 0) - (Number(o.grand_total) || 0)) > 0.005) {
      mudancas.push(`o total de ${n} mudou (era ${emReais(a.grand_total)}, agora ${emReais(o.grand_total)})`);
    } else if (a.client_id !== o.client_id) mudancas.push(`${n} mudou de cliente`);
    else if (a.vessel_id !== o.vessel_id) mudancas.push(`${n} mudou de ${TERMO_GERAL.toLowerCase()}`);
    else if (new Date(String(a.updated_at)).getTime() !== new Date(String(o.updated_at)).getTime()) mudancas.push(`${n} foi alterado`);
  }
  return mudancas.length ? mudancas.join("; ") : null;
}

/**
 * Já está feito (15/10/2026): duas pendências do mesmo agrupamento (uma no painel, outra no WhatsApp) e as
 * duas aprovadas — a segunda diz que já está agrupado, em vez de "mudou de situação".
 */
// deno-lint-ignore no-explicit-any
async function jaAgrupado(cliente: any, pedido: PedidoDeAgrupar): Promise<Record<string, unknown> | null> {
  const destinos = new Set(pedido.origens.map((o) => o.merged_into_id ?? null));
  const [destino] = [...destinos];
  if (destinos.size !== 1 || !destino) return null;
  const numero = (await numerosDosDestinos(cliente, pedido.origens))[destino] ?? "outro orçamento";
  const nums = pedido.origens.map((o) => o.service_order_number).join(", ");
  return { ok: true, ja_feito: true, numero, aviso: `Já estava feito: ${nums} já foram agrupados em ${numero}; nada novo foi gravado.` };
}

/** Erro do banco na execução, para o dono (a frase do "Os orçamentos mudaram desde que a tela abriu" é da tela). */
function erroDoAgrupar(error: unknown): string {
  const msg = mensagemDoBanco(error);
  return /^Os orçamentos mudaram desde que a tela abriu/.test(msg)
    ? "Nada foi agrupado: a soma dos orçamentos mudou depois do pedido. Peça de novo que eu confiro."
    : msg;
}

// ── desagrupar ───────────────────────────────────────────────────────────────────────────────

interface OrigemDoAgrupamento {
  id: string;
  numero: string;
  quote_status_antes: string | null;
  grand_total_antes: number | null;
}

interface AgrupadoLido {
  agrupado: LinhaDoOrcamento;
  /** As origens do agrupamento ATIVO (vazio = não é agrupado ou já foi desfeito). */
  origens: OrigemDoAgrupamento[];
  /** O dono disse o número de um dos ORIGINAIS ("desfaz o agrupamento do ORÇ-00120"): esse número. */
  ditoPelaOrigem: string | null;
  /** Há agrupamento desfeito deste agrupado (e nenhum ativo): já foi desagrupado. */
  desfeito: boolean;
}

/** Os agrupamentos (ativo e desfeitos) em que `id` é o agrupado. Leitura que falha LANÇA. */
// deno-lint-ignore no-explicit-any
async function gruposDoAgrupado(cliente: any, id: string): Promise<Array<{ id: string; desfeito_em: string | null }>> {
  const { data, error } = await cliente.from("orcamento_agrupamentos").select("id, desfeito_em").eq("agrupado_id", id);
  if (error) throw new Error(`Não consegui ler o agrupamento: ${error.message}`);
  return (data ?? []) as Array<{ id: string; desfeito_em: string | null }>;
}

/** O agrupado (pelo número/id dele OU de um dos originais) e as origens do agrupamento ativo. */
// deno-lint-ignore no-explicit-any
async function lerAgrupado(cliente: any, ref: unknown): Promise<AgrupadoLido | { error: string }> {
  const r = String(ref ?? "").trim();
  if (!r) return { error: "Diga qual orçamento agrupado desfazer (o número ORÇ do agrupado ou de um dos originais)." };
  const a = await acharOS({ admin: cliente }, { service_order_id: r });
  if (ehErro(a)) return a;
  const [linha] = await lerOrcamentos(cliente, [a.id]);
  if (!linha) return { error: `Não achei ${a.numero}.` };

  let agrupado = linha;
  let ditoPelaOrigem: string | null = null;
  let grupos = await gruposDoAgrupado(cliente, linha.id);
  // Número de um dos originais: o agrupado é o destino dele (merged_into_id só existe no agrupamento ativo).
  if (!grupos.some((g) => !g.desfeito_em) && linha.merged_into_id) {
    const [destino] = await lerOrcamentos(cliente, [linha.merged_into_id]);
    if (destino) {
      agrupado = destino;
      ditoPelaOrigem = linha.service_order_number;
      grupos = await gruposDoAgrupado(cliente, destino.id);
    }
  }
  const ativo = grupos.find((g) => !g.desfeito_em);
  if (!ativo) return { agrupado, origens: [], ditoPelaOrigem, desfeito: grupos.length > 0 };
  const { data: origens, error: e2 } = await cliente.from("orcamento_agrupamento_origens")
    .select("origem_id, numero, ordem, quote_status_antes, grand_total_antes").eq("agrupamento_id", ativo.id).order("ordem", { ascending: true });
  if (e2) throw new Error(`Não consegui ler os originais do agrupamento: ${e2.message}`);
  return {
    agrupado,
    origens: ((origens ?? []) as Array<{ origem_id: string; numero: string; ordem?: number; quote_status_antes?: string | null; grand_total_antes?: number | null }>)
      .sort((x, y) => (Number(x.ordem) || 0) - (Number(y.ordem) || 0))
      .map((o) => ({ id: o.origem_id, numero: o.numero, quote_status_antes: o.quote_status_antes ?? null, grand_total_antes: o.grand_total_antes ?? null })),
    ditoPelaOrigem,
    desfeito: false,
  };
}

/** Por que não dá para desagrupar, pelo que se lê; null = pode. */
function problemaDoDesagrupar(l: AgrupadoLido, leitura: LeituraDoBarco | null, destino: string | null): string | null {
  const n = l.agrupado.service_order_number;
  if (!l.origens.length) return `${n} não é um orçamento agrupado (ou já foi desagrupado).`;
  if (l.agrupado.merged_into_id) return `${n} foi agrupado de novo em ${destino ?? "outro orçamento"}: desagrupe ${destino ?? "aquele"} primeiro.`;
  if (l.agrupado.status !== "draft" || l.agrupado.converted_to_os_at) {
    // Agrupamento de OS (28/10/2026) mora nas mesmas tabelas: quem o desfaz é desagrupar_os.
    return `${n} já virou OS ou foi cancelado: não dá mais para desagrupar como orçamento (se ${n} é uma OS que reúne outras OS, use desagrupar_os).`;
  }
  const ativo = leitura?.agrupados_ativos?.find((g) => g.id === l.agrupado.id);
  if (ativo && ativo.pode_desagrupar === false && ativo.motivo) return `${n} não pode ser desagrupado agora: ${ativo.motivo}. Resolva isso antes.`;
  return null;
}

// deno-lint-ignore no-explicit-any
export async function resumirDesagrupamento(admin: any, args: Record<string, unknown>, autor: string | null): Promise<string> {
  const l = await lerAgrupado(admin, args?.orcamento);
  if (ehErro(l)) return recusa(l.error);
  let leitura: LeituraDoBarco | null = null;
  if (l.origens.length) {
    const lida = await lerDoBarco(admin, l.agrupado.vessel_id, l.agrupado.client_id, autor);
    if (ehErro(lida)) return recusa(`Não consegui conferir o agrupado: ${lida.error}`);
    leitura = lida;
  }
  const destinos = await numerosDosDestinos(admin, [l.agrupado]);
  const problema = problemaDoDesagrupar(l, leitura, l.agrupado.merged_into_id ? destinos[l.agrupado.merged_into_id] ?? null : null);
  if (problema) return recusa(problema);
  const n = l.agrupado.service_order_number;
  const cada = l.origens.map((o) => `*${o.numero}* (${situacao(o.quote_status_antes)}, ${emReais(o.grand_total_antes)})`).join(", ");
  return [
    `${l.ditoPelaOrigem ? `${l.ditoPelaOrigem} está agrupado em ${n}. ` : ""}Desagrupar *${n}* (${emReais(l.agrupado.grand_total)}):`,
    `- Voltam a valer, como estavam antes de agrupar (situação e link do cliente): ${cada}.`,
    `- ${n} fica cancelado como histórico, com o link do cliente desligado.`,
    `- O que foi editado em ${n} depois de agrupar NÃO volta para os originais.`,
  ].join("\n");
}

// deno-lint-ignore no-explicit-any
export async function retratoDoDesagrupamento(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  const l = await lerAgrupado(admin, args?.orcamento);
  if (ehErro(l) || !l.origens.length) return null;
  return {
    agrupado: l.agrupado.id, status: l.agrupado.status, quote_status: l.agrupado.quote_status ?? null,
    updated_at: l.agrupado.updated_at, origens: l.origens.map((o) => o.id),
  };
}

function podeAgrupar(args: unknown, ctx: ToolCtx): { error: string } | null {
  return cargosQueContam(args, ctx).every((c) => CARGOS_DO_AGRUPAMENTO.includes(c as Role)) ? null : { error: SEM_CARGO };
}

export const agruparOrcamentosTools: ToolDef[] = [
  {
    name: "listar_orcamentos_para_agrupar",
    description:
      "Lista os orçamentos EM ABERTO de uma embarcação ou veículo (e do cliente, se passar) para AGRUPAR: do mais NOVO para o mais antigo, " +
      "INCLUSIVE os reprovados, com número, data, situação, total, resumo, se pode entrar no agrupamento (elegivel) e, se não " +
      "pode, o motivo; os documentos recentes que ficaram fora da lista (virou OS, cancelado, já agrupado); e os agrupados ativos " +
      "(para desagrupar). Use ANTES de agrupar_orcamentos. Resolva antes a unidade com search_vessels (o cliente é o dono " +
      "dela). 'Os N últimos' = os N primeiros desta lista (os mais novos), contando os reprovados. Já viraram OS? Use " +
      "listar_os_para_agrupar. Só leitura.",
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
      const { data, error } = await ctx.sb.rpc("orcamentos_para_agrupar", {
        p_vessel_id: barco,
        p_client_id: cliente || null,
        p_autor: ctx.userId || null,
      });
      if (error) return { error: mensagemDoBanco(error) };
      return {
        ...(data ?? {}),
        instrucao:
          "'Os N últimos' = os N primeiros de 'orcamentos' (mais novos), contando os reprovados. Algum de fora_da_lista é mais novo " +
          "que eles? Diga ao dono. Sem reprovado nem impedido entre os N: chame agrupar_orcamentos já — a confirmação mostra a lista, " +
          "o principal e o total; não pergunte antes. Reprovado: antes de gravar qualquer coisa, pergunte ao dono se ele entra, " +
          "dizendo do que se trata (resumo), o total e desde quando (reprovado_em_data; vazio = a data não foi registrada); só com " +
          "'entra' passe-o também em voltar_para_em_elaboracao de agrupar_orcamentos (com impedimento_se_voltar ele não entra). " +
          "Impedido por outro motivo: diga o motivo e proponha agrupar sem ele. Não mostre ids.",
      };
    },
  },
  {
    name: "agrupar_orcamentos",
    description:
      "Junta 2 a 10 orçamentos em aberto do MESMO cliente e da MESMA embarcação ou veículo num orçamento NOVO (Em elaboração), com a soma " +
      "dos originais e os preços como estão. Condição de pagamento, contato e comissão vêm do PRINCIPAL (padrão: o mais antigo); a " +
      "comissão é recalculada. Os originais ficam cancelados como histórico, com o link do cliente desligado. Use depois de " +
      "listar_orcamentos_para_agrupar. A chamada já pede o 'sim' ao dono, com a lista, o principal e o total: não pergunte antes. " +
      "Reprovado só entra se o dono disser que entra: ponha-o também em voltar_para_em_elaboracao. Já virou OS? Use agrupar_os.",
    input_schema: {
      type: "object",
      properties: {
        orcamentos: {
          type: "array",
          items: { type: "string" },
          description: "Os orçamentos a juntar: números (ORÇ-00120) ou ids, 2 a 10.",
        },
        principal: { type: "string", description: "Número ou id do principal (condição, contato e comissão). Padrão: o mais antigo." },
        voltar_para_em_elaboracao: {
          type: "array",
          items: { type: "string" },
          description: "Os reprovados que o DONO DISSE que entram (números). Saem de Reprovado para Em elaboração junto com o " +
            "agrupamento, só depois do 'sim'. Nunca sem o dono dizer que entram.",
        },
      },
      required: ["orcamentos"],
    },
    risk: "medium",
    roles: CARGOS_DO_AGRUPAMENTO,
    gravarSolicitante: true,
    preValidar: (args, ctx) => validarPedidoDeAgrupar(args, ctx),
    retratoDaPendencia: (args, ctx) => retratoDoAgrupamento(ctx.admin, args),
    async execute(args, ctx) {
      const semCargo = podeAgrupar(args, ctx);
      if (semCargo) return semCargo;
      const invalido = validarPedidoDeAgrupar(args, { userRole: "admin" });
      if (invalido) return invalido;
      const pedido = await montarPedido(ctx.sb, args);
      if (ehErro(pedido)) return pedido;

      const feito = await jaAgrupado(ctx.sb, pedido);
      if (feito) return feito;
      // O "sim" foi sobre o retrato: sem ele (não deu para tirar quando o pedido nasceu), não executa.
      const retrato = lerRetrato(args);
      if (!retrato) return { error: SEM_RETRATO_AGRUPAR };
      const mudou = oQueMudouNoAgrupamento(retrato, pedido);
      if (mudou) return { error: `Nada foi agrupado: ${mudou} depois do pedido. Peça de novo que eu confiro e mostro a lista atualizada.` };
      const reprovado = pedido.origens.find((o) => o.quote_status === "rejected" && !pedido.reabrir.includes(o));
      if (reprovado) {
        return { error: `Nada foi agrupado: ${reprovado.service_order_number} está reprovado. Diga se ele entra ou fica de fora e eu refaço o pedido.` };
      }

      const totalEsperado = Number.isFinite(Number(retrato.total)) ? Number(retrato.total) : pedido.total;
      const comum = {
        p_orcamentos: pedido.origens.map((o) => o.id),
        p_base: pedido.principal.id,
        p_total_esperado: totalEsperado,
        p_autor: ctx.userId || null,
      };
      // Com reprovado que o dono disse que entra: reabre e agrupa na MESMA transação (recusa = nada muda).
      const { data, error } = pedido.reabrir.length
        ? await ctx.sb.rpc("agrupar_orcamentos_reabrindo", { ...comum, p_reabrir: pedido.reabrir.map((o) => o.id) })
        : await ctx.sb.rpc("agrupar_orcamentos", comum);
      if (error) return { error: erroDoAgrupar(error) };
      // deno-lint-ignore no-explicit-any
      const r = (data ?? {}) as any;
      const base = (ctx.settings?.app_public_url || "").replace(/\/+$/, "");
      const origens: string[] = Array.isArray(r.origens) ? r.origens : pedido.origens.map((o) => o.service_order_number);
      const reabertos: string[] = Array.isArray(r.reabertos) ? r.reabertos : pedido.reabrir.map((o) => o.service_order_number);
      const saiuDeReprovado = reabertos.length ? ` ${reabertos.join(", ")} saiu de Reprovado e entrou.` : "";
      return {
        ok: true,
        numero: r.numero,
        orcamento_id: r.service_order_id,
        origens,
        principal: r.principal ?? pedido.principal.service_order_number,
        total: r.total_geral,
        comissao: r.comissao ?? null,
        servicos: r.servicos,
        pecas: r.pecas,
        envios_cancelados: r.envios_cancelados ?? 0,
        reabertos,
        ...(base && r.service_order_id ? { link_interno: `${base}/service-orders/${r.service_order_id}` } : {}),
        // O "✅ … executado." do "sim" (sino e WhatsApp) mostra o aviso: é ali que o dono lê o número novo.
        aviso: `Novo orçamento ${r.numero}, com ${origens.join(", ")} — ${emReais(r.total_geral)}. Os originais ficaram cancelados ` +
          `como histórico, com o link desligado.${saiuDeReprovado}`,
        message:
          `Pronto: ${r.numero} reúne ${origens.join(", ")} — total ${emReais(r.total_geral)}.${saiuDeReprovado} Os originais ficaram ` +
          `cancelados como histórico, com o link desligado. Para desfazer enquanto ${r.numero} não virar OS, é só pedir para desagrupar.`,
      };
    },
  },
  {
    name: "desagrupar_orcamento",
    description:
      "Desfaz um agrupamento: os orçamentos originais voltam exatamente como estavam (situação e link do cliente) e o agrupado fica " +
      "cancelado como histórico. Só enquanto o agrupado está em aberto (não virou OS, não foi assinado, sem dinheiro/nota ligados). " +
      "O que foi editado no agrupado NÃO volta para os originais — avise o dono. OS agrupada é desagrupar_os. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        orcamento: { type: "string", description: "Número (ORÇ-00125) ou id do orçamento AGRUPADO — ou de um dos originais dele." },
      },
      required: ["orcamento"],
    },
    risk: "medium",
    roles: CARGOS_DO_AGRUPAMENTO,
    gravarSolicitante: true,
    preValidar(args, ctx) {
      if (!CARGOS_DO_AGRUPAMENTO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
      const ref = String(args?.orcamento ?? "").trim();
      if (!ref) return { error: "Diga qual orçamento agrupado desfazer (o número ORÇ do agrupado ou de um dos originais)." };
      if (!referenciaValida(ref)) return naoENumero(ref);
      return null;
    },
    retratoDaPendencia: (args, ctx) => retratoDoDesagrupamento(ctx.admin, args),
    async execute(args, ctx) {
      const semCargo = podeAgrupar(args, ctx);
      if (semCargo) return semCargo;
      // O "sim" foi sobre o retrato: o agrupado é o dele (o número dito pode ter sido o de um original).
      const retrato = lerRetrato(args);
      if (!retrato || typeof retrato.agrupado !== "string") return { error: SEM_RETRATO_DESAGRUPAR };
      const l = await lerAgrupado(ctx.sb, retrato.agrupado);
      if (ehErro(l)) return l;
      const n = l.agrupado.service_order_number;
      if (!l.origens.length && l.desfeito) {
        return { ok: true, ja_feito: true, agrupado: n, aviso: `Já estava desfeito: ${n} já tinha sido desagrupado; nada novo foi gravado.` };
      }

      const mudou = retrato.agrupado !== l.agrupado.id
        || retrato.status !== l.agrupado.status
        || (retrato.quote_status ?? null) !== (l.agrupado.quote_status ?? null)
        || new Date(String(retrato.updated_at)).getTime() !== new Date(String(l.agrupado.updated_at)).getTime()
        || (Array.isArray(retrato.origens) ? [...retrato.origens].map(String).sort().join("|") : "") !== l.origens.map((o) => o.id).sort().join("|");
      if (mudou) return { error: `Nada foi desfeito: ${n} mudou depois do pedido. Peça de novo que eu confiro.` };

      const { data, error } = await ctx.sb.rpc("desagrupar_orcamentos", { p_agrupado: l.agrupado.id, p_autor: ctx.userId || null });
      if (error) return { error: mensagemDoBanco(error) };
      // deno-lint-ignore no-explicit-any
      const r = (data ?? {}) as any;
      const origens: string[] = Array.isArray(r.origens) ? r.origens : l.origens.map((o) => o.numero);
      const texto = `${origens.join(", ")} voltaram a valer como estavam; ${r.agrupado ?? n} ficou cancelado como histórico.`;
      return {
        ok: true,
        agrupado: r.agrupado ?? n,
        origens,
        envios_cancelados: r.envios_cancelados ?? 0,
        aviso: texto,
        message: `Desfeito: ${texto}`,
      };
    },
  },
];
