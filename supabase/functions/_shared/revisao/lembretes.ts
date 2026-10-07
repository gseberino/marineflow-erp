// Lembretes de revisão (07/10/2026) — a parte que lê o banco, usada pela edge lembretes-de-revisao
// e pelas ferramentas do assistente (planos-manutencao.ts). As regras e o texto ficam em texto.ts
// (puros, com teste). Leitura que falha LANÇA: "não achei plano" nunca pode ser um erro engolido.
import { telefoneLegivel, telefoneParaEnvio } from "../ai/tools/agendamento.ts";
import {
  diaMes,
  type EventoDoPlano,
  montarTexto,
  type PlanoDue,
  primeiroNome,
  resumoDoServico,
  rotuloDoToque,
  type Toque,
} from "./texto.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const VIEW_DOS_PLANOS = "v_maintenance_plans_due";
export const ACAO_DE_ENVIO = "enviar_lembrete_de_revisao";

/** Planos ativos com vencimento e situação (a view). Filtros opcionais por plano ou embarcação. */
export async function lerPlanosDue(db: Db, filtro: { planIds?: string[]; vesselIds?: string[] } = {}): Promise<PlanoDue[]> {
  let q = db.from(VIEW_DOS_PLANOS).select("*");
  if (filtro.planIds?.length) q = q.in("plan_id", filtro.planIds);
  if (filtro.vesselIds?.length) q = q.in("vessel_id", filtro.vesselIds);
  const { data, error } = await q.order("next_due_on", { ascending: true }).limit(1000);
  if (error) throw new Error(`Falha ao ler os planos de manutenção: ${error.message}`);
  return (data ?? []) as PlanoDue[];
}

/** Eventos dos planos (de todos os ciclos ainda relevantes: até ~2 anos). */
export async function lerEventos(db: Db, planIds: string[]): Promise<EventoDoPlano[]> {
  if (!planIds.length) return [];
  const { data, error } = await db.from("maintenance_plan_events")
    .select("plan_id, client_id, due_on, tipo, toque, created_at")
    .in("plan_id", planIds)
    .gte("created_at", new Date(Date.now() - 730 * 86_400_000).toISOString())
    .limit(1000);
  if (error) throw new Error(`Falha ao ler o histórico dos planos: ${error.message}`);
  return (data ?? []) as EventoDoPlano[];
}

export interface ClienteDoLembrete {
  id: string;
  name: string | null;
  display_name: string | null;
  type: string | null;
}

export async function clientesPorId(db: Db, ids: string[]): Promise<Record<string, ClienteDoLembrete>> {
  const unicos = [...new Set(ids.filter(Boolean))];
  if (!unicos.length) return {};
  const { data, error } = await db.from("clients").select("id, name, display_name, type").in("id", unicos);
  if (error) throw new Error(`Falha ao ler os clientes: ${error.message}`);
  return Object.fromEntries(((data ?? []) as ClienteDoLembrete[]).map((c) => [c.id, c]));
}

/** O que foi feito na última OS de cada plano ("troca de 4 baterias AGM e teste do carregador"). */
export async function resumosDoUltimoServico(db: Db, osIds: string[]): Promise<Record<string, string | null>> {
  const unicos = [...new Set(osIds.filter(Boolean))];
  if (!unicos.length) return {};
  const { data, error } = await db.from("service_order_services")
    .select("service_order_id, name_snapshot, line_total")
    .in("service_order_id", unicos)
    .limit(1000);
  if (error) throw new Error(`Falha ao ler o último serviço: ${error.message}`);
  const porOs: Record<string, Array<{ name_snapshot: string; line_total: number | null }>> = {};
  for (const s of (data ?? []) as Array<{ service_order_id: string; name_snapshot: string; line_total: number | null }>) {
    (porOs[s.service_order_id] ??= []).push(s);
  }
  return Object.fromEntries(unicos.map((id) => {
    // Os serviços de maior valor primeiro: são os que o cliente lembra.
    const nomes = (porOs[id] ?? []).sort((a, b) => Number(b.line_total ?? 0) - Number(a.line_total ?? 0)).map((s) => s.name_snapshot);
    return [id, resumoDoServico(nomes)];
  }));
}

/** Uma mensagem pronta para o dono aprovar. */
export interface Proposta {
  toque: Toque;
  client_id: string;
  cliente: string;
  /** Planos que a mensagem cobre (vazio na campanha sem plano). */
  planos: PlanoDue[];
  /** Embarcação de referência (a 1ª) — a campanha sem plano vai por ela. */
  vessel_id: string;
  embarcacoes: string[];
  /** Todas as embarcações da campanha (ids), para o evento campaign_proposed. */
  vessel_ids: string[];
  /** Telefone para envio (com 55) ou null. */
  telefone: string | null;
  vence: string | null;
  texto: string;
  titulo: string;
}

/** O payload da pendência (o que a tool enviar_lembrete_de_revisao executa depois do "sim"). */
export function payloadDaProposta(p: Proposta): Record<string, unknown> {
  return {
    planos: p.planos.map((x) => x.plan_id),
    toque: p.toque,
    texto: p.texto,
    ...(p.planos.length ? {} : { embarcacao: p.vessel_id }),
  };
}

export function tituloDoLembrete(cliente: string, embarcacoes: string[], toque: Toque): string {
  const barcos = embarcacoes.filter(Boolean).join(", ") || "embarcação";
  return toque === 0 ? `Campanha de temporada para ${cliente} (${barcos})` : `Lembrete de revisão para ${cliente} (${barcos})`;
}

/** Monta a mensagem de um grupo de planos do MESMO cliente (o mesmo toque). */
export async function prepararMensagem(
  db: Db,
  grupo: { toque: 1 | 2 | 3; planos: PlanoDue[] },
  hoje: string,
  cliente?: ClienteDoLembrete | null,
): Promise<Proposta> {
  const planos = [...grupo.planos].sort((a, b) => a.next_due_on.localeCompare(b.next_due_on));
  const p0 = planos[0];
  const resumos = await resumosDoUltimoServico(db, planos.map((p) => p.last_service_order_id).filter(Boolean) as string[]);
  const nomeCliente = cliente?.display_name || cliente?.name || p0.client_name || "cliente";
  const texto = montarTexto({
    toque: grupo.toque,
    nome: primeiroNome(cliente ?? { name: p0.client_name }),
    hoje,
    itens: planos.map((p) => ({
      plano: p.plan_name,
      embarcacao: p.vessel_name || "embarcação",
      vence: p.next_due_on,
      ultimoServicoEm: p.last_service_at,
      resumoUltimo: p.last_service_order_id ? resumos[p.last_service_order_id] ?? null : null,
      valor: p.estimated_value,
    })),
  });
  const embarcacoes = [...new Set(planos.map((p) => p.vessel_name || "embarcação"))];
  return {
    toque: grupo.toque,
    client_id: p0.client_id!,
    cliente: nomeCliente,
    planos,
    vessel_id: p0.vessel_id,
    vessel_ids: [...new Set(planos.map((p) => p.vessel_id))],
    embarcacoes,
    telefone: telefoneParaEnvio(p0.client_phone),
    vence: p0.next_due_on,
    texto,
    titulo: tituloDoLembrete(nomeCliente, embarcacoes, grupo.toque),
  };
}

/** O resumo da pendência (o que o sino e o "próximo pedido" mostram). */
export function resumoDaProposta(p: Pick<Proposta, "cliente" | "telefone" | "toque" | "vence" | "texto">, teste: boolean): string {
  const linhas = [
    `Para: *${p.cliente}* — WhatsApp ${p.telefone ? telefoneLegivel(p.telefone) : "⚠️ sem telefone válido (o envio será recusado)"}`,
    `${rotuloDoToque(p.toque)}${p.vence && p.toque !== 0 ? ` · vence ${diaMes(p.vence)}` : ""}`,
    `Mensagem: "${p.texto}"`,
  ];
  if (teste) linhas.push("⚠️ Modo de teste ligado: vai para o número de teste.");
  linhas.push("Sai na próxima janela de terça a quinta, 9h–11h ou 14h–17h.");
  return linhas.join("\n");
}

/** A pergunta que vai ao dono no WhatsApp (a primeira da leva; as outras encadeiam no "sim"/"não"). */
export function perguntaAoDono(p: Proposta, teste: boolean, total: number): string {
  const cabeca = total > 1 ? `Lembretes de revisão para aprovar hoje: ${total}. O primeiro:\n\n` : "";
  return `${cabeca}Posso mandar este lembrete para ${p.cliente} (${p.embarcacoes.join(", ")})?\n\n${resumoDaProposta(p, teste)}\n\n` +
    // Sem "sim" no exemplo de ajuste: "sim mas troca…" (sem vírgula) é lido como aprovação pelo canal.
    `Responda *sim* para mandar ou *não*. Para mudar algo, diga só o que mudar (ex.: "troca a data para sexta").`;
}

/** A referência que fica no histórico da conversa: o assistente precisa dos ids para refazer o pedido. */
export function referenciaParaOAssistente(p: Proposta): string {
  const planos = p.planos.map((x) => x.plan_id).join(", ");
  return `[lembrete de revisão — ${ACAO_DE_ENVIO}: planos=${planos || "(nenhum)"}; toque=${p.toque}` +
    `${p.planos.length ? "" : `; embarcacao=${p.vessel_id}`}]`;
}
