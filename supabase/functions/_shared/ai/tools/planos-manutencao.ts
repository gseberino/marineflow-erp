// Planos de manutenção pelo assistente (07/10/2026) — frente BACKEND dos planos com lembretes.
//
// O que o dono pede conversando: "cria um plano de revisão das baterias da Mar Azul a cada 12
// meses", "quais revisões vencem este mês?", "a revisão do motor da Brisa foi feita na OS-00112",
// "adia a revisão da Mar Azul para dezembro", "sugere planos a partir do que já fizemos", "manda o
// lembrete para o Carlos agora", "como estão os lembretes?".
//
// FAZ O MESMO QUE A TELA (MaintenancePlansPanel): criar/editar grava direto em maintenance_plans
// com os mesmos campos; "serviço feito" e "adiar" usam as MESMAS funções do banco que a tela usa
// (registrar_servico_do_plano, adiar_plano). Vencimento e situação vêm da view
// v_maintenance_plans_due — ninguém recalcula. Lembrete ao cliente só pelo RPC
// enviar_lembrete_de_revisao, depois do "sim" do dono (NEVER_AUTONOMOUS).
// No WhatsApp a sessão não existe (auth.uid() nulo): as RPCs recebem p_autor.
import { lerRetrato, NON_TECHNICIAN_ROLES, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import { telefoneParaEnvio } from "./agendamento.ts";
import { lerDataDaResposta } from "../../revisao/data-da-resposta.ts";
import { hojeEmBrasilia, type PlanoDue, rotuloDoToque, type Toque } from "../../revisao/texto.ts";
import { clientesPorId, lerPlanosDue, prepararMensagem, resumoDaProposta } from "../../revisao/lembretes.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CARGOS_DO_ENVIO: Role[] = ["admin", "financial"];
const CARGOS_DO_CADASTRO: Role[] = ["admin", "financial", "seller"];
export const SISTEMAS = ["eletrico_dc", "eletrico_ac", "eletronico", "hidraulico", "mecanico", "refrigeracao", "estrutural", "gas"];
const FEITAS = ["completed", "invoiced"];

const norm = (s: unknown) => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
const brl = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v || 0);
const dataBR = (iso: string | null | undefined) => (iso ? iso.slice(0, 10).split("-").reverse().join("/") : null);
const erroDe = (e: unknown) => ({ error: e instanceof Error ? e.message : String(e) });

// ─── Critério do "serviço feito" ────────────────────────────────────────────────────────────

export interface Criterio {
  service_system: string | null;
  service_verb?: string | null;
  match_keywords: string[];
}

/** O critério sugerido pelo nome do plano ("IA pensa, sistema preenche"). Sem pista = sem critério. */
export function criterioPeloNome(nome: string): Criterio {
  const n = norm(nome);
  if (/bateria/.test(n)) return { service_system: "eletrico_dc", match_keywords: ["bateria"] };
  if (/inversor|carregador/.test(n)) return { service_system: null, match_keywords: ["inversor", "carregador"] };
  if (/gerador/.test(n)) return { service_system: null, match_keywords: ["gerador"] };
  if (/motor|oleo|rabeta|propuls/.test(n)) return { service_system: "mecanico", match_keywords: ["motor", "oleo"] };
  if (/ar condicionado|ar-condicionado|refrigera|geladeira/.test(n)) return { service_system: "refrigeracao", match_keywords: [] };
  if (/bomba|porao|hidraul/.test(n)) return { service_system: "hidraulico", match_keywords: ["bomba"] };
  if (/eletronic|navega|radar|gps|plotter|sonar/.test(n)) return { service_system: "eletronico", match_keywords: [] };
  return { service_system: null, match_keywords: [] };
}

interface LinhaDeServico { service_order_id: string; name_snapshot: string | null; service_system: string | null; service_verb: string | null; line_total?: number | null }
interface LinhaDePeca { service_order_id: string; nome: string | null; line_total_sale?: number | null }

/** A mesma regra de _plano_casa_com_os (migration 20261007150000): as palavras estreitam o sistema. */
export function casaComCriterio(c: Criterio, servicos: LinhaDeServico[], pecas: LinhaDePeca[]): boolean {
  const palavras = (c.match_keywords ?? []).map(norm).filter(Boolean);
  const sistemaOk = (s: LinhaDeServico) =>
    (!c.service_system || s.service_system === c.service_system) && (!c.service_verb || s.service_verb === c.service_verb);
  if (!c.service_system && !c.service_verb && !palavras.length) return true;
  if (!palavras.length) return servicos.some(sistemaOk);
  return palavras.some((k) =>
    servicos.some((s) => sistemaOk(s) && norm(s.name_snapshot).includes(k)) || pecas.some((p) => norm(p.nome).includes(k))
  );
}

// ─── Datas ditas ────────────────────────────────────────────────────────────────────────────

/** Data de serviço (passado): "2026-10-01", "01/10/2026", "01/10" (este ano, ou o anterior se ainda não chegou), "hoje", "ontem". */
export function dataDoServicoDita(bruto: unknown, agora: Date = new Date()): { iso: string } | { error: string } | null {
  const t = norm(bruto);
  if (!t) return null;
  const hoje = hojeEmBrasilia(agora);
  if (t === "hoje") return { iso: hoje };
  if (t === "ontem") return { iso: new Date(Date.parse(`${hoje}T12:00:00Z`) - 86_400_000).toISOString().slice(0, 10) };
  let iso: string | null = null;
  const a = t.match(/^(\d{4})-(\d{2})-(\d{2})/);
  const b = t.match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?$/);
  if (a) iso = `${a[1]}-${a[2]}-${a[3]}`;
  else if (b) {
    const ano = b[3] ? (b[3].length === 2 ? 2000 + Number(b[3]) : Number(b[3])) : Number(hoje.slice(0, 4));
    iso = `${ano}-${b[2].padStart(2, "0")}-${b[1].padStart(2, "0")}`;
    if (!b[3] && iso > hoje) iso = `${ano - 1}-${b[2].padStart(2, "0")}-${b[1].padStart(2, "0")}`;
  }
  if (!iso || Number.isNaN(Date.parse(`${iso}T12:00:00Z`)) || new Date(`${iso}T12:00:00Z`).toISOString().slice(0, 10) !== iso) {
    return { error: `Não entendi a data "${String(bruto)}". Use dd/mm/aaaa.` };
  }
  if (iso > hoje) return { error: `${dataBR(iso)} ainda não chegou — o serviço tem de ter sido feito.` };
  return { iso };
}

/** Data futura (adiar): AAAA-MM-DD, dd/mm[/aaaa], "dia 15", "semana que vem", "mês que vem", "daqui a 2 semanas". */
export function dataFuturaDita(bruto: unknown, agora: Date = new Date()): { iso: string } | { error: string } {
  const t = String(bruto ?? "").trim();
  const hoje = hojeEmBrasilia(agora);
  const iso = /^\d{4}-\d{2}-\d{2}/.test(t) ? t.slice(0, 10) : lerDataDaResposta(t, agora);
  if (!iso) return { error: `Não entendi a data "${t}". Diga, por exemplo, 15/12 ou "mês que vem".` };
  if (iso <= hoje) return { error: `${dataBR(iso)} não é depois de hoje.` };
  return { iso };
}

// ─── Achar embarcação e plano pelo nome ─────────────────────────────────────────────────────

type Achado<T> = { ok: T } | { error: string; opcoes?: string[] };

/** Embarcação pelo id ou pelo nome IGUAL ou CORTADO (começo do nome). Parecido não serve: pergunta. */
export async function acharEmbarcacao(db: Db, bruto: unknown): Promise<Achado<{ id: string; name: string; client_id: string | null }>> {
  const termo = String(bruto ?? "").trim();
  if (!termo) return { error: "Diga qual embarcação." };
  if (UUID_RE.test(termo)) {
    const { data, error } = await db.from("vessels").select("id, name, client_id").eq("id", termo).maybeSingle();
    if (error) return { error: `Falha ao buscar a embarcação: ${error.message}` };
    return data ? { ok: data } : { error: "Embarcação não encontrada." };
  }
  const { data, error } = await db.from("vessels").select("id, name, client_id, active")
    .ilike("name", `%${termo.replace(/[%_]/g, " ")}%`).limit(20);
  if (error) return { error: `Falha ao buscar a embarcação: ${error.message}` };
  const lista = ((data ?? []) as Array<{ id: string; name: string; client_id: string | null; active: boolean }>).filter((v) => v.active !== false);
  const t = norm(termo);
  const iguais = lista.filter((v) => norm(v.name) === t);
  if (iguais.length === 1) return { ok: iguais[0] };
  const cortados = lista.filter((v) => norm(v.name).startsWith(t));
  if (iguais.length === 0 && cortados.length === 1) return { ok: cortados[0] };
  if (!lista.length) return { error: `Não achei embarcação chamada "${termo}".` };
  return { error: `Há mais de uma embarcação para "${termo}" (ou só nomes parecidos). Qual delas?`, opcoes: lista.map((v) => v.name) };
}

/** O plano: pelo id, ou pela embarcação (+ o nome do plano, se ela tiver mais de um ativo). */
export async function acharPlano(
  db: Db,
  args: { plano?: unknown; embarcacao?: unknown; plano_nome?: unknown },
  soAtivos = true,
): Promise<Achado<{ id: string; name: string; vessel_id: string; vessel_name: string; active: boolean }>> {
  const id = String(args.plano ?? "").trim();
  if (UUID_RE.test(id)) {
    const { data, error } = await db.from("maintenance_plans").select("id, name, vessel_id, active, vessels(name)").eq("id", id).maybeSingle();
    if (error) return { error: `Falha ao buscar o plano: ${error.message}` };
    if (!data) return { error: "Plano de manutenção não encontrado." };
    return { ok: { id: data.id, name: data.name, vessel_id: data.vessel_id, vessel_name: data.vessels?.name ?? "", active: data.active } };
  }
  const barco = await acharEmbarcacao(db, args.embarcacao);
  if ("error" in barco) return barco;
  let q = db.from("maintenance_plans").select("id, name, vessel_id, active").eq("vessel_id", barco.ok.id);
  if (soAtivos) q = q.eq("active", true);
  const { data, error } = await q.limit(50);
  if (error) return { error: `Falha ao buscar os planos: ${error.message}` };
  let planos = (data ?? []) as Array<{ id: string; name: string; vessel_id: string; active: boolean }>;
  const nome = norm(args.plano_nome ?? (UUID_RE.test(id) ? "" : id));
  if (nome) {
    const iguais = planos.filter((p) => norm(p.name) === nome);
    planos = iguais.length ? iguais : planos.filter((p) => norm(p.name).includes(nome));
  }
  if (planos.length === 1) return { ok: { ...planos[0], vessel_name: barco.ok.name } };
  if (!planos.length) return { error: `A ${barco.ok.name} não tem plano${nome ? ` "${String(args.plano_nome ?? id)}"` : ""}${soAtivos ? " ativo" : ""}.` };
  return { error: `A ${barco.ok.name} tem ${planos.length} planos. Qual?`, opcoes: planos.map((p) => p.name) };
}

/** Os serviços e peças das OS (para achar o último serviço que casa com o critério). */
async function linhasDasOs(db: Db, osIds: string[]): Promise<{ servicos: LinhaDeServico[]; pecas: LinhaDePeca[] } | { error: string }> {
  const servicos: LinhaDeServico[] = [];
  const pecas: LinhaDePeca[] = [];
  for (let i = 0; i < osIds.length; i += 200) {
    const lote = osIds.slice(i, i + 200);
    const [s, p] = await Promise.all([
      db.from("service_order_services").select("service_order_id, name_snapshot, service_system, service_verb, line_total").in("service_order_id", lote).limit(1000),
      db.from("service_order_parts").select("service_order_id, line_total_sale, products(name)").in("service_order_id", lote).limit(1000),
    ]);
    if (s.error) return { error: `Falha ao ler os serviços das OS: ${s.error.message}` };
    if (p.error) return { error: `Falha ao ler as peças das OS: ${p.error.message}` };
    servicos.push(...(s.data ?? []));
    // deno-lint-ignore no-explicit-any
    pecas.push(...((p.data ?? []) as any[]).map((x) => ({ service_order_id: x.service_order_id, nome: x.products?.name ?? null, line_total_sale: x.line_total_sale })));
  }
  return { servicos, pecas };
}

interface OsFeita { id: string; vessel_id: string; service_order_number: string; quando: string }

/** OS concluídas das embarcações, com a data do serviço (check_out_at ?? scheduled_end_at ?? updated_at, em Brasília). */
async function osConcluidas(db: Db, vesselIds: string[] | null): Promise<OsFeita[] | { error: string }> {
  let q = db.from("service_orders").select("id, vessel_id, service_order_number, check_out_at, scheduled_end_at, updated_at")
    .in("status", FEITAS).not("vessel_id", "is", null);
  if (vesselIds) q = q.in("vessel_id", vesselIds);
  const { data, error } = await q.limit(1000);
  if (error) return { error: `Falha ao ler as OS concluídas: ${error.message}` };
  // deno-lint-ignore no-explicit-any
  return ((data ?? []) as any[])
    .filter((o) => o.check_out_at || o.scheduled_end_at || o.updated_at)
    .map((o) => ({
      id: o.id, vessel_id: o.vessel_id, service_order_number: o.service_order_number,
      quando: hojeEmBrasilia(new Date(o.check_out_at || o.scheduled_end_at || o.updated_at)),
    }));
}

/** A última OS concluída da embarcação que casa com o critério, ou null. */
export function ultimaQueCasa(c: Criterio, oss: OsFeita[], servicos: LinhaDeServico[], pecas: LinhaDePeca[]): OsFeita | null {
  const ordenadas = [...oss].sort((a, b) => b.quando.localeCompare(a.quando));
  for (const o of ordenadas) {
    if (casaComCriterio(c, servicos.filter((s) => s.service_order_id === o.id), pecas.filter((p) => p.service_order_id === o.id))) return o;
  }
  return null;
}

// ─── Lembrete "agora" (o toque certo, o texto pronto) ───────────────────────────────────────

/** O toque que cabe ao pedido "manda o lembrete agora": o próximo do ciclo; nada enviado → 1 (ou 3, se já venceu). */
export function toqueParaAgora(p: Pick<PlanoDue, "dias_para_vencer"> & { ultimo_toque?: number | null }, pedido?: unknown): { toque: 1 | 2 | 3 } | { error: string } {
  const n = Number(pedido);
  if ([1, 2, 3].includes(n)) return { toque: n as 1 | 2 | 3 };
  const ultimo = Number(p.ultimo_toque) || 0;
  if (ultimo >= 3) return { error: "Os 3 lembretes deste vencimento já foram. Daqui em diante, só o dono fala com o cliente." };
  if (ultimo === 0) return { toque: Number(p.dias_para_vencer) < 0 ? 3 : 1 };
  return { toque: (ultimo + 1) as 2 | 3 };
}

export interface LembretePronto {
  planos: string[];
  toque: Toque;
  texto: string;
  cliente: string;
  telefone: string | null;
  vence: string | null;
  embarcacao: string;
}

/** Monta o lembrete de UM plano, como a edge montaria (mesmo texto), para virar a pendência. */
export async function prepararLembreteAgora(db: Db, args: Record<string, unknown>, agora: Date = new Date()): Promise<LembretePronto | { error: string; opcoes?: string[] }> {
  const plano = await acharPlano(db, args as { plano?: unknown; embarcacao?: unknown; plano_nome?: unknown });
  if ("error" in plano) return plano;
  let linhas: PlanoDue[];
  try {
    linhas = await lerPlanosDue(db, { planIds: [plano.ok.id] });
  } catch (e) {
    return erroDe(e);
  }
  const p = linhas[0] as (PlanoDue & { ultimo_toque?: number | null }) | undefined;
  if (!p) return { error: `O plano ${plano.ok.name} está desligado.` };
  if (!p.client_id) return { error: `A ${p.vessel_name} não tem cliente cadastrado.` };
  if (p.opt_out) return { error: `${p.client_name} pediu para não receber WhatsApp.` };
  if (!telefoneParaEnvio(p.client_phone)) return { error: `${p.client_name} está sem telefone válido no cadastro.` };
  if (p.client_reminder_enabled === false) return { error: `O lembrete ao cliente está desligado no plano ${p.plan_name}. Ligue antes (update_maintenance_plan).` };
  const t = toqueParaAgora(p, args.toque);
  if ("error" in t) return t;
  const hoje = hojeEmBrasilia(agora);
  let texto: string;
  let cliente: string;
  try {
    const clientes = await clientesPorId(db, [p.client_id]);
    const proposta = await prepararMensagem(db, { toque: t.toque, planos: [p] }, hoje, clientes[p.client_id]);
    texto = proposta.texto;
    cliente = proposta.cliente;
  } catch (e) {
    return erroDe(e);
  }
  const ajustado = String(args.texto ?? "").trim();
  return {
    planos: [p.plan_id],
    toque: t.toque,
    texto: ajustado || texto,
    cliente,
    telefone: telefoneParaEnvio(p.client_phone),
    vence: p.next_due_on,
    embarcacao: p.vessel_name ?? "",
  };
}

/** Chama o RPC do envio (o mesmo para a pendência da edge e para o "manda agora"). */
async function executarEnvio(ctx: ToolCtx, planos: string[], toque: number, texto: string, embarcacao: string | null) {
  const { data, error } = await ctx.sb.rpc("enviar_lembrete_de_revisao", {
    p_planos: planos, p_toque: toque, p_texto: texto, p_autor: ctx.userId, p_embarcacao: embarcacao,
  });
  if (error) return { error: error.message };
  if (data?.error) return { error: data.error, pulado: data.pulado ?? null, nada_enviado: true };
  return {
    ok: true,
    message: data?.message,
    cliente: data?.cliente,
    embarcacao: data?.embarcacao,
    agendado_para: data?.agendado_para,
    ...(data?.teste ? { enviado_para: data?.enviado_para } : {}),
    aviso: data?.message,
  };
}

/** O resumo da confirmação dos dois envios (agent.ts → buildPendingSummary). */
export async function resumirLembreteDeRevisao(admin: Db, toolName: string, args: Record<string, unknown>): Promise<string | null> {
  if (toolName === "send_maintenance_reminder_now") {
    const r = await prepararLembreteAgora(admin, args);
    if ("error" in r) return `⚠️ ${r.error}`;
    return `${r.embarcacao ? `Embarcação: *${r.embarcacao}*\n` : ""}${resumoDaProposta(r, false)}`;
  }
  if (toolName === "enviar_lembrete_de_revisao") {
    const planos = Array.isArray(args.planos) ? (args.planos as string[]).filter((x) => UUID_RE.test(String(x))) : [];
    const toque = Number(args.toque) as Toque;
    const texto = String(args.texto ?? "").trim();
    let cliente = "cliente";
    let telefone: string | null = null;
    let vence: string | null = null;
    if (planos.length) {
      const linhas = await lerPlanosDue(admin, { planIds: planos });
      if (linhas[0]) {
        cliente = linhas[0].client_name ?? cliente;
        telefone = telefoneParaEnvio(linhas[0].client_phone);
        vence = linhas[0].next_due_on;
      }
    } else if (args.embarcacao) {
      const b = await acharEmbarcacao(admin, args.embarcacao);
      if ("ok" in b && b.ok.client_id) {
        const { data } = await admin.from("clients").select("name, whatsapp, phone").eq("id", b.ok.client_id).maybeSingle();
        cliente = data?.name ?? cliente;
        telefone = telefoneParaEnvio(data?.whatsapp || data?.phone);
      }
    }
    return resumoDaProposta({ cliente, telefone, toque, vence, texto }, false);
  }
  return null;
}

export const TITULOS_DOS_PLANOS: Record<string, string> = {
  enviar_lembrete_de_revisao: "Lembrete de revisão ao cliente",
  send_maintenance_reminder_now: "Lembrete de revisão ao cliente (agora)",
  create_maintenance_plan: "Criar plano de manutenção",
  update_maintenance_plan: "Alterar plano de manutenção",
  register_plan_service: "Registrar serviço feito no plano",
  snooze_maintenance_plan: "Adiar plano de manutenção",
};

// ─── Ferramentas ────────────────────────────────────────────────────────────────────────────

const PLANO_PROPS = {
  plano: { type: "string", description: "Id do plano (de list_maintenance_plans). Ou use embarcacao (+ plano_nome)." },
  embarcacao: { type: "string", description: "Nome da embarcação (igual ou o começo do nome) ou id." },
  plano_nome: { type: "string", description: "Nome do plano, quando a embarcação tem mais de um (ex.: 'baterias')." },
};

const SITUACOES = ["vencendo_30", "na_janela", "vencida", "adiada", "em_dia", "respondeu", "todas"];

function linhaDoPlano(p: PlanoDue & Record<string, unknown>, verValor: boolean) {
  return {
    plano_id: p.plan_id,
    plano: p.plan_name,
    embarcacao: p.vessel_name,
    cliente: p.client_name,
    vence: dataBR(p.next_due_on),
    dias_para_vencer: p.dias_para_vencer,
    situacao: p.situacao,
    ultimo_servico: dataBR(p.last_service_at),
    adiado_ate: dataBR(p.snoozed_until),
    ...(verValor ? { valor_estimado: p.estimated_value != null ? Number(p.estimated_value) : null } : {}),
    lembrete_ao_cliente: p.client_reminder_enabled,
    ultimo_lembrete: p.ultimo_toque ? rotuloDoToque(Number(p.ultimo_toque) as Toque) : null,
    respondeu: p.respondeu_no_ciclo,
    os_agendada: p.os_agendada_numero ?? (p.tem_os_agendada ? "sim" : null),
    sem_contato: p.opt_out ? "pediu para não receber WhatsApp" : !p.client_phone ? "sem telefone" : null,
  };
}

export const planosManutencaoTools: ToolDef[] = [
  {
    name: "list_maintenance_plans",
    description:
      "Lista os PLANOS DE MANUTENÇÃO (revisões recorrentes por embarcação) com vencimento, situação (em dia, na janela de 21 dias, vencida, adiada), último serviço, valor estimado, último lembrete ao cliente e se ele respondeu. Filtros: embarcação, cliente, situação ('vencendo_30' = vence nos próximos 30 dias). Traz a receita prevista (soma dos valores). Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        embarcacao: { type: "string", description: "Parte do nome da embarcação." },
        cliente: { type: "string", description: "Parte do nome do cliente." },
        situacao: { type: "string", enum: SITUACOES, description: "Padrão: todas." },
        limit: { type: "number", description: "Máximo de planos (padrão 30, teto 100)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      let planos: PlanoDue[];
      try {
        planos = await lerPlanosDue(ctx.sb);
      } catch (e) {
        return erroDe(e);
      }
      const barco = norm(args?.embarcacao);
      const cliente = norm(args?.cliente);
      const situacao = String(args?.situacao ?? "todas");
      const lista = planos.filter((p) =>
        (!barco || norm(p.vessel_name).includes(barco)) &&
        (!cliente || norm(p.client_name).includes(cliente)) &&
        (situacao === "todas" ? true
          : situacao === "vencendo_30" ? p.dias_para_vencer >= 0 && p.dias_para_vencer <= 30
          : situacao === "respondeu" ? p.respondeu_no_ciclo
          : p.situacao === situacao)
      );
      const limite = Math.min(Number(args?.limit) || 30, 100);
      const verValor = ctx.userRole !== "technician";
      return {
        count: lista.length,
        ...(verValor ? { receita_prevista: brl(lista.reduce((s, p) => s + (Number(p.estimated_value) || 0), 0)) } : {}),
        planos: lista.slice(0, limite).map((p) => linhaDoPlano(p as PlanoDue & Record<string, unknown>, verValor)),
        ...(planos.length === 0 ? { nota: "Nenhum plano cadastrado. suggest_maintenance_plans propõe planos a partir das OS já feitas." } : {}),
      };
    },
  },
  {
    name: "create_maintenance_plan",
    description:
      "Cria um PLANO DE MANUTENÇÃO recorrente para uma embarcação (ex.: 'revisão das baterias da Mar Azul a cada 12 meses, uns R$ 1.500'). O critério do 'serviço feito' (sistema/palavras) é sugerido pelo nome do plano; a data do último serviço, se não for dita, é a da última OS concluída que casa com o critério. Use as propostas de suggest_maintenance_plans (origem 'sugerido'). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        embarcacao: { type: "string", description: "Nome da embarcação (igual ou o começo do nome) ou id." },
        nome: { type: "string", description: "Nome do plano (ex.: 'Revisão das baterias')." },
        intervalo_meses: { type: "number", description: "A cada quantos meses (1 a 60)." },
        escopo: { type: "string", description: "O que a revisão inclui." },
        valor_estimado: { type: "number", description: "Valor estimado da revisão (R$)." },
        ultimo_servico_em: { type: "string", description: "Quando foi o último serviço (dd/mm/aaaa). Vazio = acha pela última OS." },
        sistema: { type: "string", enum: SISTEMAS, description: "Sistema que conta como 'serviço feito' (opcional; sugerido pelo nome)." },
        palavras: { type: "array", items: { type: "string" }, description: "Palavras no nome do serviço/peça que contam como 'serviço feito' (opcional)." },
        lembrete_ao_cliente: { type: "boolean", description: "Lembrar o cliente pelo WhatsApp, sempre com o seu sim (padrão true)." },
        origem: { type: "string", enum: ["manual", "sugerido"], description: "'sugerido' quando veio de suggest_maintenance_plans." },
      },
      required: ["embarcacao", "nome", "intervalo_meses"],
    },
    risk: "medium",
    roles: CARGOS_DO_CADASTRO,
    preValidar(args) {
      if (!String(args?.nome ?? "").trim()) return { error: "Diga o nome do plano (ex.: 'Revisão das baterias')." };
      const n = Number(args?.intervalo_meses);
      if (!Number.isInteger(n) || n < 1 || n > 60) return { error: "O intervalo tem de ser de 1 a 60 meses." };
      if (args?.ultimo_servico_em) {
        const d = dataDoServicoDita(args.ultimo_servico_em);
        if (d && "error" in d) return d;
      }
      return null;
    },
    async execute(args, ctx) {
      if (!CARGOS_DO_CADASTRO.includes(ctx.userRole as Role)) return { error: "Cargo não autorizado para criar plano de manutenção." };
      const nome = String(args?.nome ?? "").trim();
      const intervalo = Number(args?.intervalo_meses);
      if (!nome) return { error: "Diga o nome do plano." };
      if (!Number.isInteger(intervalo) || intervalo < 1 || intervalo > 60) return { error: "O intervalo tem de ser de 1 a 60 meses." };
      const barco = await acharEmbarcacao(ctx.sb, args?.embarcacao);
      if ("error" in barco) return barco;

      const { data: existentes, error: eP } = await ctx.sb.from("maintenance_plans").select("id, name").eq("vessel_id", barco.ok.id).eq("active", true);
      if (eP) return { error: `Falha ao conferir os planos da embarcação: ${eP.message}` };
      if (((existentes ?? []) as Array<{ name: string }>).some((p) => norm(p.name) === norm(nome))) {
        return { error: `A ${barco.ok.name} já tem o plano "${nome}" ativo. Para mudar, use update_maintenance_plan.` };
      }

      const sugerido = criterioPeloNome(nome);
      const palavras = Array.isArray(args?.palavras) ? (args.palavras as unknown[]).map((x) => String(x).trim()).filter(Boolean) : null;
      const criterio: Criterio = {
        service_system: args?.sistema && SISTEMAS.includes(String(args.sistema)) ? String(args.sistema) : (palavras ? null : sugerido.service_system),
        match_keywords: palavras ?? sugerido.match_keywords,
      };

      let ultimo: string | null = null;
      let ultimaOs: OsFeita | null = null;
      if (args?.ultimo_servico_em) {
        const d = dataDoServicoDita(args.ultimo_servico_em);
        if (d && "error" in d) return d;
        ultimo = d ? d.iso : null;
      } else {
        const oss = await osConcluidas(ctx.sb, [barco.ok.id]);
        if ("error" in oss) return oss;
        if (oss.length) {
          const linhas = await linhasDasOs(ctx.sb, oss.map((o) => o.id));
          if ("error" in linhas) return linhas;
          ultimaOs = ultimaQueCasa(criterio, oss, linhas.servicos, linhas.pecas);
          ultimo = ultimaOs?.quando ?? null;
        }
      }

      const valor = Number(args?.valor_estimado);
      const linha = {
        vessel_id: barco.ok.id,
        name: nome,
        interval_months: intervalo,
        scope: String(args?.escopo ?? "").trim() || null,
        estimated_value: Number.isFinite(valor) && valor > 0 ? valor : null,
        last_service_at: ultimo,
        last_service_order_id: ultimaOs?.id ?? null,
        service_system: criterio.service_system,
        match_keywords: criterio.match_keywords.length ? criterio.match_keywords : null,
        client_reminder_enabled: args?.lembrete_ao_cliente !== false,
        source: args?.origem === "sugerido" ? "sugerido" : "manual",
        active: true,
        created_by: ctx.userId,
      };
      const { data: criado, error } = await ctx.sb.from("maintenance_plans").insert(linha).select("id").single();
      if (error) return { error: `Falha ao criar o plano: ${error.message}` };
      let vence: string | null = null;
      try {
        vence = (await lerPlanosDue(ctx.sb, { planIds: [criado.id] }))[0]?.next_due_on ?? null;
      } catch { /* o plano foi criado; só a data do vencimento fica sem mostrar */ }
      return {
        ok: true,
        plano_id: criado.id,
        message: `Plano "${nome}" criado para a ${barco.ok.name}, a cada ${intervalo} meses.` +
          (ultimo ? ` Último serviço: ${dataBR(ultimo)}${ultimaOs ? ` (${ultimaOs.service_order_number})` : ""}.` : " Sem serviço anterior: conta a partir de hoje.") +
          (vence ? ` Próximo vencimento: ${dataBR(vence)}.` : ""),
        criterio: {
          sistema: criterio.service_system,
          palavras: criterio.match_keywords,
          explicacao: !criterio.service_system && !criterio.match_keywords.length
            ? "Sem critério: qualquer OS concluída da embarcação conta como serviço feito."
            : "OS concluída que casa com isto atualiza o plano sozinha.",
        },
      };
    },
  },
  {
    name: "update_maintenance_plan",
    description:
      "Altera um plano de manutenção: ligar/desligar, nome, intervalo, valor estimado, escopo, lembrete ao cliente on/off, critério do 'serviço feito' (sistema/palavras), observações. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        ...PLANO_PROPS,
        ativo: { type: "boolean", description: "false = desliga o plano (para de vencer e de lembrar)." },
        nome: { type: "string" },
        intervalo_meses: { type: "number", description: "1 a 60." },
        valor_estimado: { type: "number" },
        escopo: { type: "string" },
        lembrete_ao_cliente: { type: "boolean" },
        sistema: { type: "string", enum: [...SISTEMAS, "nenhum"], description: "'nenhum' tira o sistema do critério." },
        palavras: { type: "array", items: { type: "string" }, description: "Substitui as palavras do critério ([] tira)." },
        observacoes: { type: "string" },
      },
    },
    risk: "medium",
    roles: CARGOS_DO_CADASTRO,
    async execute(args, ctx) {
      if (!CARGOS_DO_CADASTRO.includes(ctx.userRole as Role)) return { error: "Cargo não autorizado para alterar plano de manutenção." };
      const plano = await acharPlano(ctx.sb, args ?? {}, false);
      if ("error" in plano) return plano;
      const patch: Record<string, unknown> = {};
      if (typeof args?.ativo === "boolean") patch.active = args.ativo;
      if (String(args?.nome ?? "").trim()) patch.name = String(args.nome).trim();
      if (args?.intervalo_meses !== undefined && args?.intervalo_meses !== null) {
        const n = Number(args.intervalo_meses);
        if (!Number.isInteger(n) || n < 1 || n > 60) return { error: "O intervalo tem de ser de 1 a 60 meses." };
        patch.interval_months = n;
      }
      if (args?.valor_estimado !== undefined && args?.valor_estimado !== null) {
        const v = Number(args.valor_estimado);
        if (!Number.isFinite(v) || v < 0) return { error: "Valor estimado inválido." };
        patch.estimated_value = v > 0 ? v : null;
      }
      if (typeof args?.escopo === "string") patch.scope = args.escopo.trim() || null;
      if (typeof args?.observacoes === "string") patch.notes = args.observacoes.trim() || null;
      if (typeof args?.lembrete_ao_cliente === "boolean") patch.client_reminder_enabled = args.lembrete_ao_cliente;
      if (args?.sistema) patch.service_system = args.sistema === "nenhum" ? null : SISTEMAS.includes(String(args.sistema)) ? args.sistema : undefined;
      if (patch.service_system === undefined) delete patch.service_system;
      if (Array.isArray(args?.palavras)) {
        const p = (args.palavras as unknown[]).map((x) => String(x).trim()).filter(Boolean);
        patch.match_keywords = p.length ? p : null;
      }
      if (!Object.keys(patch).length) return { error: "Diga o que mudar no plano." };
      const { data: antes, error: eA } = await ctx.sb.from("maintenance_plans")
        .select("name, active, interval_months, estimated_value, scope, notes, client_reminder_enabled, service_system, match_keywords")
        .eq("id", plano.ok.id).maybeSingle();
      if (eA) return { error: `Falha ao ler o plano: ${eA.message}` };
      const { error } = await ctx.sb.from("maintenance_plans").update(patch).eq("id", plano.ok.id);
      if (error) return { error: `Falha ao alterar o plano: ${error.message}` };
      const mudou = Object.fromEntries(Object.keys(patch).map((k) => [k, { antes: antes?.[k] ?? null, depois: patch[k] }]));
      return { ok: true, plano: plano.ok.name, embarcacao: plano.ok.vessel_name, mudou, message: `Plano "${plano.ok.name}" da ${plano.ok.vessel_name} alterado.` };
    },
  },
  {
    name: "register_plan_service",
    description:
      "Registra que o serviço de um plano de manutenção FOI FEITO ('a revisão das baterias da Mar Azul foi feita na OS-00112', 'fiz a revisão do motor da Brisa ontem'). Zera o ciclo: o próximo vencimento conta desta data. Sem data = hoje (Brasília). OS concluída que casa com o plano já faz isso sozinha. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        ...PLANO_PROPS,
        data: { type: "string", description: "Quando foi feito (dd/mm/aaaa, 'hoje', 'ontem'). Padrão: hoje." },
        os: { type: "string", description: "Número da OS do serviço (OS-00112 ou 112), se houver." },
      },
    },
    risk: "medium",
    preValidar(args) {
      if (args?.data) {
        const d = dataDoServicoDita(args.data);
        if (d && "error" in d) return d;
      }
      return null;
    },
    async execute(args, ctx) {
      const plano = await acharPlano(ctx.sb, args ?? {}, false);
      if ("error" in plano) return plano;
      let data: string | null = null;
      if (args?.data) {
        const d = dataDoServicoDita(args.data);
        if (d && "error" in d) return d;
        data = d?.iso ?? null;
      }
      let osId: string | null = null;
      if (args?.os) {
        const achado = await localizarOrdem(ctx.sb, String(args.os), "os");
        if ("erro" in achado) return { error: achado.erro };
        if ("opcoes" in achado) return { error: `Mais de um documento com esse número: ${achado.opcoes.join(", ")}. Qual?` };
        osId = achado.ordem.id;
      }
      const { data: r, error } = await ctx.sb.rpc("registrar_servico_do_plano", { p_plano: plano.ok.id, p_data: data, p_os: osId, p_autor: ctx.userId });
      if (error) return { error: error.message };
      return { ok: true, ...r };
    },
  },
  {
    name: "snooze_maintenance_plan",
    description:
      "Adia um plano de manutenção até uma data ('adia a revisão da Mar Azul para dezembro', 'o cliente pediu para depois do dia 15'): nada de lembrete até lá. Aceita 15/12, 'mês que vem', 'semana que vem', 'daqui a 2 semanas'.",
    input_schema: {
      type: "object",
      properties: {
        ...PLANO_PROPS,
        ate: { type: "string", description: "Até quando (dd/mm/aaaa, 'mês que vem'…)." },
        motivo: { type: "string" },
      },
      required: ["ate"],
    },
    risk: "low",
    async execute(args, ctx) {
      const ate = dataFuturaDita(args?.ate);
      if ("error" in ate) return ate;
      const plano = await acharPlano(ctx.sb, args ?? {});
      if ("error" in plano) return plano;
      const { data, error } = await ctx.sb.rpc("adiar_plano", { p_plano: plano.ok.id, p_ate: ate.iso, p_motivo: args?.motivo ?? null, p_autor: ctx.userId });
      if (error) return { error: error.message };
      return { ok: true, ...data };
    },
  },
  {
    name: "suggest_maintenance_plans",
    description:
      "PROPÕE planos de manutenção a partir do que já foi feito: para cada embarcação, a última troca/manutenção de BATERIAS, MOTOR e INVERSOR/CARREGADOR nas OS concluídas (e os equipamentos cadastrados), com intervalo, valor e critério prontos para create_maintenance_plan (origem 'sugerido'). Ignora o que já tem plano. Só leitura — não cria nada.",
    input_schema: {
      type: "object",
      properties: {
        embarcacao: { type: "string", description: "Só esta embarcação (nome igual/começo do nome). Vazio = todas." },
        limit: { type: "number", description: "Máximo de propostas (padrão 15, teto 40)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      let vesselIds: string[] | null = null;
      if (args?.embarcacao) {
        const b = await acharEmbarcacao(ctx.sb, args.embarcacao);
        if ("error" in b) return b;
        vesselIds = [b.ok.id];
      }
      const oss = await osConcluidas(ctx.sb, vesselIds);
      if ("error" in oss) return oss;
      const comServico = [...new Set(oss.map((o) => o.vessel_id))];
      if (vesselIds === null) vesselIds = comServico;
      if (!vesselIds.length) return { count: 0, propostas: [], nota: "Nenhuma embarcação com OS concluída." };

      let qv = ctx.sb.from("vessels").select("id, name, client_id, active, engine_brand, engine_model, engine_type, battery_bank_summary, inverter_charger_summary, clients(name)").in("id", vesselIds);
      qv = qv.eq("active", true);
      const [{ data: barcos, error: eV }, { data: planos, error: eP }] = await Promise.all([
        qv,
        ctx.sb.from("maintenance_plans").select("vessel_id, name, service_system, match_keywords").eq("active", true).in("vessel_id", vesselIds),
      ]);
      if (eV) return { error: `Falha ao ler as embarcações: ${eV.message}` };
      if (eP) return { error: `Falha ao ler os planos: ${eP.message}` };
      const linhas = await linhasDasOs(ctx.sb, oss.map((o) => o.id));
      if ("error" in linhas) return linhas;

      const MODELOS = [
        {
          chave: "baterias", nome: "Revisão das baterias", intervalo: 12, criterio: { service_system: "eletrico_dc", match_keywords: ["bateria"] },
          escopo: "Teste de capacidade, terminais, carga e equalização do banco de baterias",
          // deno-lint-ignore no-explicit-any
          equipamento: (v: any) => v.battery_bank_summary,
        },
        {
          chave: "inversor", nome: "Revisão do inversor/carregador", intervalo: 12, criterio: { service_system: null, match_keywords: ["inversor", "carregador"] },
          escopo: "Parametrização, firmware, conexões e teste com carga do inversor/carregador",
          // deno-lint-ignore no-explicit-any
          equipamento: (v: any) => v.inverter_charger_summary,
        },
        {
          chave: "motor", nome: "Revisão do motor", intervalo: 12, criterio: { service_system: "mecanico", match_keywords: ["motor", "oleo"] },
          escopo: "Troca de óleo e filtros, correias, arrefecimento e teste de funcionamento",
          // deno-lint-ignore no-explicit-any
          equipamento: (v: any) => [v.engine_brand, v.engine_model, v.engine_type].filter(Boolean).join(" ") || null,
        },
      ];

      const propostas: Array<Record<string, unknown>> = [];
      // deno-lint-ignore no-explicit-any
      for (const v of (barcos ?? []) as any[]) {
        const dosPlanos = ((planos ?? []) as Array<{ vessel_id: string; name: string; service_system: string | null; match_keywords: string[] | null }>)
          .filter((p) => p.vessel_id === v.id);
        const ossDoBarco = oss.filter((o) => o.vessel_id === v.id);
        for (const m of MODELOS) {
          const jaTem = dosPlanos.some((p) => criterioPeloNome(p.name).match_keywords.some((k) => m.criterio.match_keywords.includes(k)) ||
            (p.match_keywords ?? []).some((k) => m.criterio.match_keywords.includes(norm(k))));
          if (jaTem) continue;
          const ultima = ultimaQueCasa(m.criterio, ossDoBarco, linhas.servicos, linhas.pecas);
          const equipamento = m.equipamento(v);
          if (!ultima && !equipamento) continue;
          // Valor: o que essas linhas custaram na última OS (referência; o dono ajusta).
          const valor = ultima
            ? linhas.servicos.filter((s) => s.service_order_id === ultima.id && casaComCriterio(m.criterio, [s], [])).reduce((a, s) => a + (Number(s.line_total) || 0), 0)
            : 0;
          propostas.push({
            embarcacao: v.name,
            vessel_id: v.id,
            cliente: v.clients?.name ?? null,
            nome: m.nome,
            intervalo_meses: m.intervalo,
            escopo: m.escopo,
            sistema: m.criterio.service_system,
            palavras: m.criterio.match_keywords,
            ultimo_servico_em: ultima ? dataBR(ultima.quando) : null,
            os_do_ultimo_servico: ultima?.service_order_number ?? null,
            valor_estimado: valor > 0 ? Math.round(valor) : null,
            equipamento: equipamento ? String(equipamento).slice(0, 80) : null,
            por_que: ultima
              ? `Último serviço de ${m.chave} em ${dataBR(ultima.quando)} (${ultima.service_order_number}).`
              : `Tem ${m.chave} cadastrado, sem serviço registrado: o plano conta a partir de hoje.`,
            origem: "sugerido",
          });
        }
      }
      const limite = Math.min(Number(args?.limit) || 15, 40);
      propostas.sort((a, b) => String(a.ultimo_servico_em ?? "9").localeCompare(String(b.ultimo_servico_em ?? "9")));
      return {
        count: propostas.length,
        propostas: propostas.slice(0, limite),
        instrucao: "Mostre as propostas ao dono e só crie (create_maintenance_plan com origem 'sugerido') as que ele aprovar.",
      };
    },
  },
  {
    name: "send_maintenance_reminder_now",
    description:
      "Prepara AGORA o lembrete de revisão ao cliente de um plano ('manda o lembrete da revisão da Mar Azul'): escolhe o toque certo (1º, 2º ou último), monta o texto com datas e faixa de valor, e vira pedido de confirmação mostrando o texto exato. Só sai com o seu sim; vai na janela de terça a quinta. Para mudar o texto, passe texto.",
    input_schema: {
      type: "object",
      properties: {
        ...PLANO_PROPS,
        toque: { type: "number", enum: [1, 2, 3], description: "Força o toque (1 = D-21, 2 = D-7, 3 = D+14). Vazio = o próximo do ciclo." },
        texto: { type: "string", description: "Texto ajustado pelo dono (substitui o modelo)." },
      },
    },
    risk: "medium",
    roles: CARGOS_DO_ENVIO,
    preValidar(args, ctx) {
      if (!CARGOS_DO_ENVIO.includes(ctx.userRole as Role)) return { error: "Só administrador ou financeiro manda lembrete ao cliente." };
      if (!args?.plano && !args?.embarcacao) return { error: "Diga de qual embarcação (ou plano) é o lembrete." };
      return null;
    },
    async retratoDaPendencia(args, ctx) {
      const r = await prepararLembreteAgora(ctx.admin, args);
      return "error" in r ? null : { planos: r.planos, toque: r.toque, texto: r.texto };
    },
    async execute(args, ctx) {
      if (!CARGOS_DO_ENVIO.includes(ctx.userRole as Role)) return { error: "Só administrador ou financeiro manda lembrete ao cliente." };
      // O "sim" foi sobre o texto do retrato (o que o resumo mostrou): é ele que sai.
      const retrato = lerRetrato(args);
      if (retrato && Array.isArray(retrato.planos) && typeof retrato.texto === "string") {
        return executarEnvio(ctx, retrato.planos as string[], Number(retrato.toque), retrato.texto, null);
      }
      const r = await prepararLembreteAgora(ctx.sb, args);
      if ("error" in r) return r;
      return executarEnvio(ctx, r.planos, r.toque, r.texto, null);
    },
  },
  {
    name: "enviar_lembrete_de_revisao",
    description:
      "EXECUTA o envio de um lembrete de revisão já redigido (os pedidos diários de lembrete chegam ao dono assim). Use quando o dono pedir AJUSTE num lembrete proposto ('sim, mas troca a data para sexta'): chame de novo com os mesmos planos e toque da referência do pedido e o texto final — vira um novo pedido de confirmação com o texto novo. Campanha: toque 0 e embarcacao.",
    input_schema: {
      type: "object",
      properties: {
        planos: { type: "array", items: { type: "string" }, description: "Ids dos planos (da referência do pedido)." },
        toque: { type: "number", enum: [0, 1, 2, 3], description: "1 = D-21, 2 = D-7, 3 = D+14, 0 = campanha de temporada." },
        texto: { type: "string", description: "O texto exato que vai ao cliente." },
        embarcacao: { type: "string", description: "Campanha sem plano: a embarcação (id ou nome)." },
      },
      required: ["toque", "texto"],
    },
    risk: "medium",
    roles: CARGOS_DO_ENVIO,
    preValidar(args, ctx) {
      if (!CARGOS_DO_ENVIO.includes(ctx.userRole as Role)) return { error: "Só administrador ou financeiro manda lembrete ao cliente." };
      if (!String(args?.texto ?? "").trim()) return { error: "O texto do lembrete está vazio." };
      if (![0, 1, 2, 3].includes(Number(args?.toque))) return { error: "Toque inválido (0 a 3)." };
      const planos = Array.isArray(args?.planos) ? args.planos.filter((x: unknown) => UUID_RE.test(String(x))) : [];
      if (!planos.length && !args?.embarcacao) return { error: "Diga os planos (ou a embarcação, na campanha)." };
      return null;
    },
    async execute(args, ctx) {
      if (!CARGOS_DO_ENVIO.includes(ctx.userRole as Role)) return { error: "Só administrador ou financeiro manda lembrete ao cliente." };
      const planos = Array.isArray(args?.planos) ? (args.planos as unknown[]).map(String).filter((x) => UUID_RE.test(x)) : [];
      let barco: string | null = null;
      if (!planos.length) {
        const b = await acharEmbarcacao(ctx.sb, args?.embarcacao);
        if ("error" in b) return b;
        barco = b.ok.id;
      }
      return executarEnvio(ctx, planos, Number(args?.toque), String(args?.texto ?? "").trim(), barco);
    },
  },
  {
    name: "maintenance_reminder_metrics",
    description:
      "Como estão os LEMBRETES DE REVISÃO num período: propostos, aprovados/recusados por você, enviados, respostas, PARAR, agendamentos (OS da embarcação aberta até 30 dias depois do envio), receita dessas OS e o atraso médio entre o vencimento e o serviço feito. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        de: { type: "string", description: "Início (AAAA-MM-DD). Padrão: 90 dias atrás." },
        ate: { type: "string", description: "Fim (AAAA-MM-DD). Padrão: hoje." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const hoje = hojeEmBrasilia();
      const ate = /^\d{4}-\d{2}-\d{2}$/.test(String(args?.ate ?? "")) ? String(args.ate) : hoje;
      const de = /^\d{4}-\d{2}-\d{2}$/.test(String(args?.de ?? "")) ? String(args.de)
        : new Date(Date.parse(`${ate}T12:00:00Z`) - 90 * 86_400_000).toISOString().slice(0, 10);
      const ini = `${de}T03:00:00Z`;
      const fim = new Date(Date.parse(`${ate}T03:00:00Z`) + 86_400_000).toISOString();

      const { data: evs, error } = await ctx.sb.from("maintenance_plan_events")
        .select("plan_id, vessel_id, client_id, due_on, tipo, toque, detalhe, created_at")
        .gte("created_at", ini).lt("created_at", fim).limit(1000);
      if (error) return { error: `Falha ao ler os lembretes: ${error.message}` };
      const { data: pend, error: eP } = await ctx.sb.from("ai_operator_pending_actions")
        .select("status, action_name")
        .in("action_name", ["enviar_lembrete_de_revisao", "send_maintenance_reminder_now"])
        .gte("created_at", ini).lt("created_at", fim).limit(1000);
      if (eP) return { error: `Falha ao ler as aprovações: ${eP.message}` };

      // deno-lint-ignore no-explicit-any
      type Ev = Record<string, any>;
      const eventos = (evs ?? []) as Ev[];
      const conta = (f: (e: Ev) => boolean) => eventos.filter(f).length;
      // Um envio = uma mensagem (vários planos do mesmo envio têm o mesmo fila_id).
      const envios = new Map<string, { vessel_id: string; quando: string }>();
      for (const e of eventos.filter((x) => x.tipo === "reminder_sent" || x.tipo === "campaign_sent")) {
        const chave = String(e.detalhe?.fila_id ?? `${e.client_id}:${e.created_at}`);
        if (!envios.has(chave)) envios.set(chave, { vessel_id: e.vessel_id, quando: e.created_at });
      }
      const respostas = new Set(eventos.filter((e) => e.tipo === "client_replied").map((e) => `${e.client_id}:${e.detalhe?.envio_em ?? e.created_at}`));

      // Agendamentos: OS (não cancelada, não orçamento) da embarcação criada até 30 dias depois do envio.
      const barcos = [...new Set([...envios.values()].map((x) => x.vessel_id).filter(Boolean))];
      let agendamentos = 0;
      let receita = 0;
      const osContadas = new Set<string>();
      if (barcos.length) {
        const { data: oss, error: eO } = await ctx.sb.from("service_orders")
          .select("id, vessel_id, status, created_at, grand_total")
          .in("vessel_id", barcos).gte("created_at", ini).limit(1000);
        if (eO) return { error: `Falha ao ler as OS: ${eO.message}` };
        for (const env of envios.values()) {
          const t0 = Date.parse(env.quando);
          // deno-lint-ignore no-explicit-any
          const achada = ((oss ?? []) as any[]).find((o) => o.vessel_id === env.vessel_id && !["cancelled", "draft"].includes(o.status) &&
            Date.parse(o.created_at) >= t0 && Date.parse(o.created_at) <= t0 + 30 * 86_400_000);
          if (achada) {
            agendamentos++;
            if (!osContadas.has(achada.id)) {
              osContadas.add(achada.id);
              receita += Number(achada.grand_total) || 0;
            }
          }
        }
      }

      // Atraso: dias entre o vencimento do ciclo e o serviço feito (negativo = adiantado).
      const atrasos = eventos.filter((e) => e.tipo === "serviced" && e.due_on && e.detalhe?.data)
        .map((e) => Math.round((Date.parse(`${e.detalhe.data}T12:00:00Z`) - Date.parse(`${e.due_on}T12:00:00Z`)) / 86_400_000));
      // deno-lint-ignore no-explicit-any
      const pendencias = (pend ?? []) as any[];
      return {
        periodo: `${dataBR(de)} a ${dataBR(ate)}`,
        propostos: conta((e) => e.tipo === "reminder_proposed" || e.tipo === "campaign_proposed"),
        aprovados: pendencias.filter((p) => ["approved", "executed", "failed"].includes(p.status)).length,
        recusados: pendencias.filter((p) => p.status === "rejected").length,
        expirados_sem_resposta: pendencias.filter((p) => p.status === "expired" || p.status === "pending").length,
        enviados: envios.size,
        pulados: conta((e) => e.tipo === "reminder_skipped"),
        respostas: respostas.size,
        parar: conta((e) => e.tipo === "client_replied" && e.detalhe?.intencao === "parar"),
        agendamentos,
        receita_das_os: brl(receita),
        servicos_feitos: conta((e) => e.tipo === "serviced"),
        atraso_medio_dias: atrasos.length ? Math.round(atrasos.reduce((a, b) => a + b, 0) / atrasos.length) : null,
      };
    },
  },
];
