// A via do técnico a partir do servidor (13/11/2026): ler a OS, montar a folha da pessoa,
// renderizar e entregar — o mesmo caminho do PDF do orçamento (gerar-e-guardar.ts).
//
// Quem chama: a tool do assistente (para si e para a equipe, com o SIM) e a agenda (junto da ficha
// das 19:30). A folha é a da tela: montarViaDoTecnico (via-do-tecnico.ts) com os mesmos dados que o
// hook use-via-do-tecnico lê — as consultas daqui espelham as dele, uma a uma:
//   detalhe da OS        → SO_DETAIL_SELECT (use-service-orders), só as colunas que a via usa
//   serviços             → useServiceOrderServices ('*, services(name)', por created_at)
//   passos               → useServiceOrderSteps (STEP_SELECT, por seq)
//   material             → useRouteMaterials (service_order_parts, por created_at)
//   levantamento         → useServiceOrderSurvey (o mais recente)
//   segurança sem roteiro→ seguranca_da_via
//   empresa              → app_settings (company_name, company_logo_url, company_address, phone)

import {
  type DadosDaVia,
  htmlDaVia,
  impressaoDaVia,
  type LinhaDaVia,
  type LinhaDeSeguranca,
  montarViaDoTecnico,
  nomeDoArquivoDaVia,
  type RouteMaterial,
  type ServiceOrderStep,
  viaHeaderFromOrder,
} from "./via-do-tecnico.ts";
import { VALIDADE_DO_LINK_DA_FOTO_S } from "./fotos.ts";
import { nomeDaUnidade } from "../unidade.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** As colunas da OS que a via usa (o embed de SO_DETAIL_SELECT, sem preço nenhum). */
export const SELECT_DA_OS_DA_VIA = `
  id, service_order_number, status, share_token, updated_at, requested_by_name,
  scheduled_start_at, scheduled_end_at, problem_description, technician_instructions, site_access,
  clients(name, phone, whatsapp),
  vessels(name, manufacturer, model, current_dock_position, asset_type, hull_id_or_registration, access_notes,
    battery_bank_summary, inverter_charger_summary, shore_power_type, electrical_system_notes),
  requested_by_contact:vessel_contacts!service_orders_requested_by_contact_id_fkey(full_name, role, phone),
  marinas(name),
  service_order_technicians(app_users(full_name))
`;

/** O mesmo STEP_SELECT de src/hooks/use-service-steps.ts. */
const SELECT_DOS_PASSOS = `
  id, service_order_id, service_order_service_id, template_id, seq, block, block_key, block_note,
  title, detail,
  kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
  measure_value, status, na_reason, blocked_reason_code, blocked_note, assigned_user_id,
  started_at, completed_at, actual_minutes, origin, notes,
  ai_confidence, ai_source, approved_at
`;

/** O que a tool e a agenda precisam da OS além da folha (legenda, token do render). */
export interface OrdemDaVia {
  id: string;
  numero: string;
  status: string | null;
  shareToken: string | null;
  cliente: string;
  /** "Motorhome Itapoã" — o tipo e o nome, como a legenda do PDF do orçamento. */
  unidade: string | null;
}

export type LeituraDaVia =
  | { ok: true; dados: DadosDaVia; ordem: OrdemDaVia }
  | { ok: false; motivo: string };

function falhou(rotulo: string, e: { message?: string } | null | undefined): never {
  throw new Error(`${rotulo}: ${e?.message ?? "sem resposta"}`);
}

/** Lê tudo o que a via da OS precisa, numa ida só (as leituras correm juntas). */
export async function carregarDadosDaVia(admin: Admin, serviceOrderId: string, settings: Record<string, string>): Promise<LeituraDaVia> {
  try {
    const [os, linhas, passos, materiais, levantamento, seguranca] = await Promise.all([
      admin.from("service_orders").select(SELECT_DA_OS_DA_VIA).eq("id", serviceOrderId).maybeSingle(),
      admin.from("service_order_services").select("*, services(name)").eq("service_order_id", serviceOrderId)
        .order("created_at", { ascending: true }),
      admin.from("service_order_steps").select(SELECT_DOS_PASSOS).eq("service_order_id", serviceOrderId)
        .order("seq", { ascending: true }),
      admin.from("service_order_parts").select("id, quantity, notes, service_order_service_id, products(name, sku, unit)")
        .eq("service_order_id", serviceOrderId).order("created_at"),
      admin.from("service_surveys")
        .select("id, service_survey_answers(seq, question_snapshot, answer_value, skipped_reason, photo_path)")
        .eq("service_order_id", serviceOrderId).order("created_at", { ascending: false }).limit(1).maybeSingle(),
      admin.rpc("seguranca_da_via", { p_service_order_id: serviceOrderId }),
    ]);
    if (os.error) falhou("a OS", os.error);
    if (!os.data) return { ok: false, motivo: "a OS não foi encontrada" };
    if (linhas.error) falhou("os serviços", linhas.error);
    if (passos.error) falhou("o roteiro", passos.error);
    if (materiais.error) falhou("o material", materiais.error);
    if (levantamento.error) falhou("o levantamento", levantamento.error);
    if (seguranca.error) falhou("a segurança por sistema", seguranca.error);

    const linhasDaVia = (linhas.data ?? []) as LinhaDaVia[];
    const ids = [...new Set(linhasDaVia.map((l) => l.responsavel_payee_id).filter((id): id is string => !!id))];
    let nomesDosResponsaveis: Record<string, string> = {};
    if (ids.length) {
      const { data, error } = await admin.from("payees").select("id, name").in("id", ids);
      if (error) falhou("os responsáveis", error);
      nomesDosResponsaveis = Object.fromEntries(((data ?? []) as Array<{ id: string; name: string }>).map((p) => [p.id, p.name]));
    }

    const o = os.data;
    const dados: DadosDaVia = {
      serviceOrderId,
      header: viaHeaderFromOrder(o),
      empresa: {
        nome: settings.company_name || null,
        logoUrl: settings.company_logo_url || null,
        endereco: settings.company_address || null,
        telefone: settings.phone || null,
      },
      linhas: linhasDaVia,
      passos: (passos.data ?? []) as ServiceOrderStep[],
      materiais: (materiais.data ?? []) as RouteMaterial[],
      levantamento: (levantamento.data?.service_survey_answers ?? []) as DadosDaVia["levantamento"],
      seguranca: (seguranca.data ?? []) as LinhaDeSeguranca[],
      nomesDosResponsaveis,
    };
    return {
      ok: true,
      dados,
      ordem: {
        id: o.id,
        numero: o.service_order_number,
        status: o.status ?? null,
        shareToken: o.share_token ?? null,
        cliente: o.clients?.name || "—",
        unidade: o.vessels?.name ? nomeDaUnidade({ name: o.vessels.name, asset_type: o.vessels.asset_type }) : null,
      },
    };
  } catch (e) {
    return { ok: false, motivo: `não consegui ler a OS (${e instanceof Error ? e.message : String(e)})` };
  }
}

/** Links temporários das fotos do levantamento, por caminho (o bucket é privado). */
export async function linksDasFotosDaVia(admin: Admin, d: DadosDaVia): Promise<Record<string, string>> {
  const caminhos = [...new Set(d.levantamento.map((a) => a.photo_path).filter((c): c is string => !!c))];
  if (!caminhos.length) return {};
  const { data, error } = await admin.storage.from("service-order-photos").createSignedUrls(caminhos, VALIDADE_DO_LINK_DA_FOTO_S);
  // Foto sem link só fica fora do papel (como na tela); a via sai mesmo assim.
  if (error) return {};
  const mapa: Record<string, string> = {};
  for (const item of (data ?? []) as Array<{ path?: string | null; signedUrl?: string | null }>) {
    if (item.path && item.signedUrl) mapa[item.path] = item.signedUrl;
  }
  return mapa;
}

/** A via pronta para renderizar: HTML, nome do arquivo e a impressão digital do conteúdo. */
export interface ViaPronta {
  html: string;
  nomeDoArquivo: string;
  impressao: string;
  servicos: number;
  /** Todos os serviços da OS estão com outra pessoa: não se manda (a via dela estaria vazia). */
  semServicoDaPessoa: boolean;
}

/** Monta a via (da OS inteira ou de uma pessoa) com os links das fotos já assinados. */
export function prepararVia(
  d: DadosDaVia,
  numero: string,
  pessoa: { id: string; nome: string } | null,
  linksDasFotos: Record<string, string>,
): ViaPronta {
  const montada = montarViaDoTecnico(d, { modo: "via", pessoa, linksDasFotos });
  return {
    html: htmlDaVia(montada),
    nomeDoArquivo: nomeDoArquivoDaVia(numero, pessoa?.nome ?? null),
    impressao: impressaoDaVia(d, { modo: "via", pessoa }),
    servicos: montada.servicos,
    semServicoDaPessoa: montada.semServicoDaPessoa,
  };
}

// ═══ Quem está na OS ══════════════════════════════════════════════════════════════════════════

/** Uma pessoa da equipe ligada à OS — pela agenda (dias marcados) ou por ser responsável de um serviço. */
export interface PessoaDaOs {
  id: string;
  nome: string;
  /** Só dígitos; vazio = sem telefone no cadastro (não dá para mandar). */
  telefone: string;
  ativo: boolean;
  /** Dias marcados na agenda de hoje em diante (publicados ou fixados; reserva não conta). */
  dias: string[];
  /** Quantas linhas de serviço desta OS estão marcadas para ela. */
  linhas: number;
}

/** Hoje em Brasília (aaaa-mm-dd). */
export function hojeEmBrasilia(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(agora);
}

/** Quem está na OS: a agenda de hoje em diante e os responsáveis marcados nas linhas. */
export async function pessoasDaOs(admin: Admin, d: DadosDaVia, agora: Date = new Date()): Promise<PessoaDaOs[]> {
  const { data: alocs, error: aErr } = await admin.from("agenda_alocacoes")
    .select("payee_id, dia")
    .eq("service_order_id", d.serviceOrderId)
    .in("estado", ["publicada", "fixada"])
    .neq("tipo", "reserva")
    .gte("dia", hojeEmBrasilia(agora));
  if (aErr) throw new Error(`não consegui ler a agenda da OS: ${aErr.message}`);
  const dias = new Map<string, Set<string>>();
  for (const a of (alocs ?? []) as Array<{ payee_id: string | null; dia: string }>) {
    if (!a.payee_id) continue;
    if (!dias.has(a.payee_id)) dias.set(a.payee_id, new Set());
    dias.get(a.payee_id)!.add(a.dia);
  }
  const linhasPorPessoa = new Map<string, number>();
  for (const l of d.linhas) {
    if (l.responsavel_payee_id) linhasPorPessoa.set(l.responsavel_payee_id, (linhasPorPessoa.get(l.responsavel_payee_id) ?? 0) + 1);
  }
  const ids = [...new Set([...dias.keys(), ...linhasPorPessoa.keys()])];
  if (!ids.length) return [];
  const { data: ps, error: pErr } = await admin.from("payees").select("id, name, phone, active").in("id", ids);
  if (pErr) throw new Error(`não consegui ler a equipe: ${pErr.message}`);
  return ((ps ?? []) as Array<{ id: string; name: string; phone: string | null; active: boolean | null }>)
    .map((p) => ({
      id: p.id,
      nome: p.name,
      telefone: String(p.phone ?? "").replace(/\D/g, ""),
      ativo: p.active !== false,
      dias: [...(dias.get(p.id) ?? [])].sort(),
      linhas: linhasPorPessoa.get(p.id) ?? 0,
    }))
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
}

/**
 * A legenda do PDF no WhatsApp: "📄 Via do técnico — OS-00119 · Motorhome Itapoã (Lenine)". De quem é a
 * via e o que ficou com outra pessoa estão no próprio PDF (cabeçalho e o quadro "com outra pessoa").
 */
export function legendaDaVia(ordem: OrdemDaVia, complemento?: string | null): string {
  const unidade = ordem.unidade ? ` · ${ordem.unidade}` : "";
  return `📄 Via do técnico — ${ordem.numero}${unidade} (${ordem.cliente})${complemento ? `\n${complemento}` : ""}`;
}
