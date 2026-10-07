// A rodada diária da edge lembretes-de-revisao (07/10/2026): acha os toques devidos e a campanha,
// registra o que foi pulado e prepara as mensagens. Nada sai para o cliente aqui: cada mensagem
// vira uma pendência do dono (index.ts), e só o "sim" dele executa enviar_lembrete_de_revisao.
import {
  agruparPorCliente,
  dentroDaCampanha,
  diasEntre,
  montarTexto,
  type PlanoDue,
  primeiroNome,
  type ToqueDevido,
  toqueDevido,
} from "./texto.ts";
import { clientesPorId, lerEventos, lerPlanosDue, prepararMensagem, type Proposta, tituloDoLembrete } from "./lembretes.ts";
import { telefoneParaEnvio } from "../ai/tools/agendamento.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Volume baixíssimo (47 embarcações): mais que isto num dia é sinal de erro, não de demanda. */
export const MAX_PROPOSTAS_POR_RODADA = 6;
/** A campanha vai a conta-gotas: 3 por dia de terça a quinta cobre a base em ~2 semanas. */
export const MAX_CAMPANHA_POR_RODADA = 3;

const ABERTAS = ["scheduled", "open", "in_progress", "awaiting_parts", "awaiting_client", "approved"];
const FEITAS = ["completed", "invoiced"];
const BRASILIA_MS = 3 * 60 * 60 * 1000;

export interface Pulado {
  plano: PlanoDue;
  toque: 1 | 2 | 3;
  motivo: NonNullable<ToqueDevido["pular"]>;
}

/** Os toques devidos hoje, já agrupados por cliente, e os pulados (para registrar uma vez). */
export async function proporToques(db: Db, hoje: string): Promise<{ propostas: Proposta[]; pulados: Pulado[]; planos: PlanoDue[] }> {
  const planos = await lerPlanosDue(db);
  const eventos = await lerEventos(db, planos.map((p) => p.plan_id));
  const devidos: Array<{ plano: PlanoDue; toque: 1 | 2 | 3 }> = [];
  const pulados: Pulado[] = [];
  for (const p of planos) {
    if (!p.client_id) continue;
    const t = toqueDevido(p, eventos);
    if (!t) continue;
    if (t.pular) pulados.push({ plano: p, toque: t.toque, motivo: t.pular });
    else devidos.push({ plano: p, toque: t.toque });
  }
  const grupos = agruparPorCliente(devidos, planos, eventos);
  const clientes = await clientesPorId(db, grupos.map((g) => g.client_id));
  const propostas: Proposta[] = [];
  for (const g of grupos) propostas.push(await prepararMensagem(db, g, hoje, clientes[g.client_id]));
  return { propostas, pulados, planos };
}

/**
 * A campanha de temporada (15/09–31/10): uma mensagem por cliente que tem embarcação com serviço
 * concluído e NENHUM plano vencendo de outubro a dezembro. Fora: opt-out, sem telefone, quem já
 * recebeu (ou teve proposta) neste ano, quem recebeu lembrete nos últimos 30 dias, embarcação com
 * OS aberta e embarcação atendida nos últimos 90 dias (o RPC confere tudo de novo no envio).
 */
export async function proporCampanha(db: Db, hoje: string, planos: PlanoDue[]): Promise<Proposta[]> {
  if (!dentroDaCampanha(hoje)) return [];
  const ano = hoje.slice(0, 4);

  const { data: oss, error: eOs } = await db.from("service_orders")
    .select("vessel_id, client_id, status, check_out_at, scheduled_end_at, updated_at")
    .in("status", [...ABERTAS, ...FEITAS])
    .not("vessel_id", "is", null)
    .limit(1000);
  if (eOs) throw new Error(`Falha ao ler as OS: ${eOs.message}`);

  const atendidas = new Set<string>();
  const barradas = new Set<string>();
  for (const o of (oss ?? []) as Array<Record<string, string | null>>) {
    const v = String(o.vessel_id);
    if (ABERTAS.includes(String(o.status))) { barradas.add(v); continue; }
    atendidas.add(v);
    const quando = o.check_out_at || o.scheduled_end_at || o.updated_at;
    if (quando) {
      const dia = new Date(new Date(quando).getTime() - BRASILIA_MS).toISOString().slice(0, 10);
      if (diasEntre(dia, hoje) < 90) barradas.add(v);
    }
  }

  const comPlanoNaTemporada = new Set(
    planos.filter((p) => p.next_due_on >= `${ano}-10-01` && p.next_due_on <= `${ano}-12-31`).map((p) => String(p.client_id)),
  );

  const { data: evs, error: eEv } = await db.from("maintenance_plan_events")
    .select("client_id, tipo, created_at")
    .in("tipo", ["campaign_proposed", "campaign_sent", "reminder_sent"])
    .gte("created_at", `${ano}-01-01T03:00:00Z`)
    .limit(1000);
  if (eEv) throw new Error(`Falha ao ler o histórico da campanha: ${eEv.message}`);
  const jaTocados = new Set<string>();
  const trintaDias = Date.now() - 30 * 86_400_000;
  for (const e of (evs ?? []) as Array<{ client_id: string | null; tipo: string; created_at: string }>) {
    if (!e.client_id) continue;
    if (e.tipo !== "reminder_sent" || Date.parse(e.created_at) > trintaDias) jaTocados.add(e.client_id);
  }

  const candidatas = [...atendidas].filter((v) => !barradas.has(v));
  if (!candidatas.length) return [];
  const { data: barcos, error: eV } = await db.from("vessels").select("id, name, client_id, active").in("id", candidatas);
  if (eV) throw new Error(`Falha ao ler as embarcações: ${eV.message}`);
  const porCliente = new Map<string, Array<{ id: string; name: string }>>();
  for (const b of (barcos ?? []) as Array<{ id: string; name: string; client_id: string | null; active: boolean }>) {
    if (!b.active || !b.client_id || comPlanoNaTemporada.has(b.client_id) || jaTocados.has(b.client_id)) continue;
    const lista = porCliente.get(b.client_id) ?? [];
    lista.push({ id: b.id, name: b.name });
    porCliente.set(b.client_id, lista);
  }
  if (!porCliente.size) return [];

  const { data: clis, error: eC } = await db.from("clients")
    .select("id, name, display_name, type, opt_out_whatsapp, whatsapp, phone, active")
    .in("id", [...porCliente.keys()]);
  if (eC) throw new Error(`Falha ao ler os clientes: ${eC.message}`);

  const propostas: Proposta[] = [];
  for (const c of ((clis ?? []) as Array<Record<string, unknown>>).sort((a, b) => String(a.name).localeCompare(String(b.name)))) {
    if (propostas.length >= MAX_CAMPANHA_POR_RODADA) break;
    if (c.opt_out_whatsapp || c.active === false) continue;
    const telefone = telefoneParaEnvio(c.whatsapp || c.phone);
    if (!telefone) continue;
    const vs = (porCliente.get(String(c.id)) ?? []).slice(0, 3);
    if (!vs.length) continue;
    const nome = String(c.display_name || c.name || "cliente");
    const embarcacoes = vs.map((v) => v.name);
    propostas.push({
      toque: 0,
      client_id: String(c.id),
      cliente: nome,
      planos: [],
      vessel_id: vs[0].id,
      vessel_ids: vs.map((v) => v.id),
      embarcacoes,
      telefone,
      vence: null,
      texto: montarTexto({
        toque: 0,
        nome: primeiroNome(c as { name: string; display_name: string; type: string }),
        hoje,
        itens: [],
        embarcacoes,
      }),
      titulo: tituloDoLembrete(nome, embarcacoes, 0),
    });
  }
  return propostas;
}

/** Registra os pulados (uma vez por toque e ciclo: toqueDevido já não devolve o que foi pulado). */
export async function registrarPulados(db: Db, pulados: Pulado[]): Promise<void> {
  if (!pulados.length) return;
  const { error } = await db.from("maintenance_plan_events").insert(pulados.map((p) => ({
    plan_id: p.plano.plan_id,
    vessel_id: p.plano.vessel_id,
    client_id: p.plano.client_id,
    due_on: p.plano.next_due_on,
    tipo: "reminder_skipped",
    toque: p.toque,
    detalhe: { motivo: p.motivo, origem: "lembretes-de-revisao" },
  })));
  if (error) throw new Error(`Falha ao registrar lembretes pulados: ${error.message}`);
}

/** Os eventos "proposto" de uma proposta já virada pendência. */
export function eventosDaProposta(p: Proposta, pendenciaId: string): Array<Record<string, unknown>> {
  if (p.toque === 0 && !p.planos.length) {
    return p.vessel_ids.map((v) => ({
      vessel_id: v, client_id: p.client_id, tipo: "campaign_proposed",
      detalhe: { pendencia_id: pendenciaId, texto: p.texto },
    }));
  }
  return p.planos.map((x) => ({
    plan_id: x.plan_id, vessel_id: x.vessel_id, client_id: p.client_id, due_on: x.next_due_on,
    tipo: p.toque === 0 ? "campaign_proposed" : "reminder_proposed",
    toque: p.toque === 0 ? null : p.toque,
    detalhe: { pendencia_id: pendenciaId, texto: p.texto },
  }));
}
