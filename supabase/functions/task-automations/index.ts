// Edge Function: task-automations — o motor da Agenda & Tarefas 2.0.
// Cron */15min. Faz, nesta ordem:
//   0. Conferência do material da Agenda de Produção (material-da-agenda.ts, Fase 1 P2): guarda em
//      os_material o que o estoque e as OCs dizem de cada item de compra da carteira, antes de a R16 ler
//      a conta. Passo à parte: erro vai para app_error_logs (agenda:material) e não derruba o resto.
//   0b. A rotina da equipe e da diária (agenda-rotina.ts, Fase 3 P4): agenda_rotina_rodar manda a ficha da véspera,
//      a confirmação da manhã e o "como foi hoje?" (só com agenda_config.modo_equipe ligado, na janela e no teto que o
//      banco confere), remaneja pelo silêncio, lança a diária (modo_diaria) e devolve os acordes. Antes da vigia: a
//      vigia lê o que ela mudou. Passo à parte: nunca lança (agenda:rotina).
//   0b2. A rodada do aprendizado (agenda-aprender.ts, Fase 6 P8): agenda_aprender roda uma vez por dia, no 1º tique a
//      partir de agenda_config.aprender_hora (o banco decide; nos outros tiques devolve cedo ou ja_rodou): mede as OS
//      concluídas SEMPRE e, com modo_aprendizado fora de desligado, calcula o que aprendeu (o uso só com o modo ligado e o
//      item na lista). Depois da rotina (a conferência do dia em dia) e antes da vigia (que lê o que ela aprendeu). Passo à
//      parte: nunca lança (agenda:aprender); a função ausente (código antes da migration) é pulada calada.
//   0c. A vigia da Agenda de Produção (agenda-vigia.ts, Fase 2 P3): agenda_vigiar publica a semana na quinta,
//      replaneja quando algo muda, promove e solta reservas, pergunta o que só o dono sabe e devolve os acordes
//      (a perda de hoje ou amanhã), que vão ao dono pelo portão. Passo à parte: nunca lança (agenda:vigia).
//   0c2. O aviso do gestor ao dono (agenda-aviso.ts, correção de 29/10 P4): logo depois da vigia e com o MESMO instante dela
//      (uma mensagem por rodada), o que a agenda mudou sozinha (publicou, encaixou, promoveu ou soltou reserva, remanejou),
//      o que ficou de fora e as perguntas que destravam, pela fila (source agenda-dono), só na janela do aviso e no teto do
//      dia (o banco decide: agenda_aviso_pecas e agenda_aviso_enfileirar); antes, agenda_aviso_conferir conta o que a fila
//      mandou e devolve o que não saiu. Passo à parte: nunca lança (agenda:aviso).
//   0d. A rodada da mensagem ao cliente (agenda-cliente.ts, Fase 5 P3): agenda_cliente_vigiar roda SEMPRE o passo "fila"
//      (o que ficou velho na fila do cliente não sai) e, com agenda_config.modo_cliente fora de desligado, decide qual
//      mensagem-modelo vai a quem e quando (o banco escreve o texto e confere a janela, o teto e a aprovação dos 3
//      primeiros dias). Depois da vigia (lê o plano já replanejado) e antes das regras. Passo à parte: nunca lança
//      (agenda:cliente-vigia).
//   1. Regras de rules.ts (RULES): criam tarefas (dedupe por automation_key) e auto-resolvem
//      as que a condição sumiu ("Resolvido automaticamente: ..."). A R1 e a R16 saem com a agenda automática
//      ligada (agenda_config.modo_proposta) e a R2 com a vigia ligada (modo_vigia) — o mesmo interruptor da
//      substituta (agenda-modos.ts); as tarefas vivas delas se resolvem com o motivo da agenda. A R15 sai com a
//      confirmação da agenda ligada (modo_cliente = 'ligado' e 'confirmar' nas ondas: a onda 2).
//   2. R10: lembrete interno (WhatsApp equipe) de OS agendada para amanhã. Sai com a ficha da agenda ligada
//      (modo_equipe = 'ligado', decisão d13): o resumo diz "desligada: a ficha da agenda substitui".
//   3. Processa task_reminders vencidos → app_notifications + WhatsApp interno.
//   4. Materializa recorrências (rrule) para os próximos 30 dias.
// As regras não mandam nada a cliente. O lembrete automático de agendamento (R9) e a pesquisa
// pós-serviço (R13), que nasciam desligados, foram aposentados em 23/10/2026 (decisão d13): a
// confirmação com o cliente é a R15, uma tarefa que só envia com o clique do dono — até a onda 2 da
// Agenda de Produção (Fase 5), quando ela passa a ser a mensagem-modelo da agenda (0d, decidida no banco).
// Plano: plans/marineflow-agenda-tarefas.md §6-§7.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  RULES, isRuleEnabled, ruleById, ruleIdFromKey, isManualDismissal, dismissCooldownDays,
  dispensaSemFatoNovo, textoDoLembreteDaOs, type RuleCandidate, candidatosDaRegra, resolucaoDaTarefa,
} from "./rules.ts";
import { resolveAssignee } from "./responsavel.ts";
import { sincronizarMaterialDaAgenda } from "./material-da-agenda.ts";
import { lerModosDaAgenda, lerModosDaEquipe, lerModosDoCliente, r10DesligadaPelaAgenda } from "./agenda-modos.ts";
import { vigiarAgenda } from "./agenda-vigia.ts";
import { avisarDonoDaAgenda } from "./agenda-aviso.ts";
import { rodarRotinaDaAgenda } from "./agenda-rotina.ts";
import { vigiarMaterialDaAgenda } from "./agenda-material.ts";
import { vigiarClienteDaAgenda } from "./agenda-cliente.ts";
import { aprenderDaAgenda } from "./agenda-aprender.ts";
import { expandOccurrences } from "../_shared/recurrence.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

// deno-lint-ignore no-explicit-any
type Db = any; // mesmo padrão das demais functions: client supabase-js sem schema tipado

async function loadSettings(db: Db): Promise<Record<string, string>> {
  const { data } = await db.from("app_settings").select("key, value");
  return Object.fromEntries((data || []).map((s: any) => [s.key, s.value]));
}

async function audit(db: Db, event_type: string, payload: unknown) {
  try {
    await db.from("ai_operator_audit").insert({
      actor_kind: "system", event_type, event_category: "data", payload,
    });
  } catch (_) { /* auditoria nunca derruba o motor */ }
}

async function createTaskFromCandidate(db: Db, c: RuleCandidate, assigneeId: string | null): Promise<boolean> {
  const { error } = await db.from("agenda_tasks").insert({
    title: c.title,
    kind: "task",
    status: "pending",
    priority: c.priority,
    source: "automation",
    automation_key: c.automation_key,
    assignee_user_id: assigneeId,
    due_at: c.due_at,
    related_entity_type: c.related_entity_type,
    related_entity_id: c.related_entity_id,
    client_id: c.client_id ?? null,
    notes: c.notes ?? null,
  });
  if (error) {
    // 23505 = já existe tarefa viva para esta chave (dedupe) — esperado
    if ((error as any).code === "23505") return false;
    throw error;
  }
  return true;
}

async function runRules(db: Db, settings: Record<string, string>) {
  const created: string[] = [];
  const resolved: string[] = [];
  // Falhas por regra. Antes o catch abaixo só fazia console.error e a função devolvia
  // {created, resolved}: uma regra quebrada ficava indistinguível de uma regra sem
  // gatilho, e o cron reportava 200. Foi assim que a R17 passou dias sem efeito.
  const falhas: { rule: string; code?: string; msg: string }[] = [];
  const assigneeCache = new Map<string, string | null>();
  // Os modos da Agenda de Produção (Fase 2): com a substituta ligada, a regra antiga sai (rules.ts,
  // desligadaPelaAgenda). Ilegíveis = desligado: as regras ficam como hoje.
  const modos = await lerModosDaAgenda(db);
  // (Fase 5, P3) o modo da mensagem ao cliente, num SELECT à parte (as colunas da Fase 5): a R15 sai com a confirmação da
  // agenda ligada. Ilegível = desligado: a R15 fica como hoje.
  modos.cliente = await lerModosDoCliente(db);

  const cooldownDays = dismissCooldownDays(settings);
  const cutoffISO = new Date(Date.now() - cooldownDays * 86400000).toISOString();

  for (const rule of RULES) {
    if (!isRuleEnabled(settings, rule)) continue;
    try {
      let candidates = await candidatosDaRegra(db, rule, modos);

      // Dispensa manual: não recriar o que um humano concluiu/cancelou há pouco
      // com a condição ainda de pé (senão a tarefa "volta do nada" a cada 15min).
      // Regra com voltaSoComFatoNovo (R16): a dispensa não tem prazo enquanto o título for o
      // mesmo (15/10/2026).
      if (candidates.length > 0 && (cooldownDays > 0 || rule.voltaSoComFatoNovo)) {
        const keys = candidates.map((c) => c.automation_key);
        // Só as fechadas À MÃO: as fechadas sozinhas não dispensam nada, e a OS-00104 tinha 1.142
        // delas — passava do teto de 1.000 linhas do PostgREST, que corta calado.
        const { data: closed, error: closedErr } = await db.from("agenda_tasks")
          .select("automation_key, title, status, completed_by, completed_at, updated_at")
          .in("automation_key", keys)
          .in("status", ["done", "cancelled"])
          .or("status.eq.cancelled,completed_by.not.is.null");
        // Sem a leitura, recriar seria desfazer a dispensa do dono: a regra falha nesta rodada.
        if (closedErr) throw closedErr;
        const tituloPorChave = new Map(candidates.map((c) => [c.automation_key, c.title]));
        const fechadas = (closed as any[]) || [];
        const dismissed = new Set(
          fechadas.filter((r) => cooldownDays > 0 && isManualDismissal(r, cutoffISO)).map((r) => r.automation_key),
        );
        if (rule.voltaSoComFatoNovo) {
          for (const r of fechadas) {
            const titulo = tituloPorChave.get(r.automation_key) ?? "";
            if (dismissed.has(r.automation_key) || !dispensaSemFatoNovo(r, titulo)) continue;
            // Título igual não basta (revisão de 15/10/2026): o título da R16 só traz a contagem, e
            // um item NOVO com a mesma contagem ficaria sem tarefa para sempre. A regra diz se a
            // entidade mudou desde que o dono fechou (rule.mudouDesde); sem data, vale a dispensa.
            const desde = r.completed_at || r.updated_at;
            const mudou = !!desde && !!rule.mudouDesde &&
              await rule.mudouDesde(db, r.automation_key, new Date(desde).toISOString());
            if (dispensaSemFatoNovo(r, titulo, mudou)) dismissed.add(r.automation_key);
          }
        }
        candidates = candidates.filter((c) => !dismissed.has(c.automation_key));
      }

      for (const c of candidates) {
        const assigneeId = await resolveAssignee(db, c.assignee, assigneeCache);
        const inserted = await createTaskFromCandidate(db, c, assigneeId);
        if (inserted) {
          created.push(c.automation_key);
          // planos de manutenção (07/10/2026): a trilha do plano registra a tarefa da R14. Best-effort.
          if (c.automation_key.startsWith("r14:")) {
            await db.from("maintenance_plan_events").insert({
              plan_id: c.automation_key.split(":")[2], vessel_id: c.related_entity_id, client_id: c.client_id ?? null,
              tipo: "task_created", detalhe: { automation_key: c.automation_key },
            });
          }
          // lembrete padrão no app quando a tarefa tem prazo
          if (c.due_at && assigneeId) {
            const { data: t } = await db.from("agenda_tasks")
              .select("id").eq("automation_key", c.automation_key)
              .in("status", ["pending", "in_progress"]).maybeSingle();
            if (t) {
              await db.from("task_reminders").insert({
                task_id: (t as any).id, remind_at: c.due_at, channel: "app",
              });
            }
          }
        }
      }
    } catch (e) {
      const code = (e as any)?.code as string | undefined;
      const msg = String((e as any)?.message ?? e);
      console.error(`rule ${rule.id} find/create failed:`, e);
      falhas.push({ rule: rule.id, code, msg });
      // 23514 = violação de CHECK. Aqui só há um CHECK que uma regra consegue violar:
      // related_entity_type fora da lista fechada. Nunca é esperado (o único erro
      // esperado, 23505 do dedupe, é tratado no createTaskFromCandidate), então vai
      // para a tabela de erros — é o que transforma "sumiu em silêncio" em "consultável".
      if (code === "23514") {
        await logEdgeError(db, {
          context: "task-automations",
          action: `rule:${rule.id}`,
          message: `regra ${rule.id}: related_entity_type fora do CHECK de agenda_tasks (23514)`,
          details: { rule: rule.id, code, msg },
          error: e,
        });
      }
    }
  }

  // Auto-resolução: reavalia TODAS as tarefas vivas de automação (mesmo de regra
  // desabilitada — desligar a regra não deve deixar tarefa fantasma para sempre)
  const { data: live } = await db.from("agenda_tasks")
    .select("id, automation_key, notes")
    .eq("source", "automation")
    .not("automation_key", "is", null)
    .in("status", ["pending", "in_progress"])
    .limit(300);
  for (const task of (live as any[]) || []) {
    const rule = ruleById(ruleIdFromKey(task.automation_key));
    if (!rule) continue;
    try {
      const reason = await resolucaoDaTarefa(db, rule, task, modos);
      if (reason) {
        await db.from("agenda_tasks").update({
          status: "done",
          completed_at: new Date().toISOString(),
          notes: [task.notes, `Resolvido automaticamente: ${reason}`].filter(Boolean).join("\n"),
        }).eq("id", task.id).in("status", ["pending", "in_progress"]);
        resolved.push(task.automation_key);
      }
    } catch (e) {
      console.error(`rule ${rule.id} isResolved failed:`, e);
    }
  }

  return { created, resolved, falhas, agenda_modos: modos };
}

/** R10 — lembrete interno de OS (equipe, nunca cliente) em DUAS janelas BRT:
 *  véspera 17:00-18:59 ("amanhã às X") e manhã do dia 07:00-08:59 ("hoje às X").
 *  Fora das janelas não envia — sem mensagem interna de madrugada.
 *  Agenda de Produção (Fase 3, P4): com a ficha da agenda ligada (modo_equipe = 'ligado') a R10 não roda — o técnico
 *  receberia as duas. O resumo diz "desligada: a ficha da agenda substitui" (agenda-modos.ts, R10_DESLIGADA). */
async function runTechnicianReminders(db: Db, settings: Record<string, string>) {
  if ((settings["task_rule_r10_enabled"] ?? "true") !== "true") return { sent: 0 };
  const modosDaEquipe = await lerModosDaEquipe(db);
  // (revisão da Fase 3, C1 — R4) a falha da leitura não é engolida: vai a app_error_logs; fora a Fase 3 ausente, a R10
  // pula este tique (r10DesligadaPelaAgenda devolve R10_PULADA)
  if (modosDaEquipe.erro !== undefined) {
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:r10",
      level: r10DesligadaPelaAgenda(modosDaEquipe) ? "error" : "warn",
      message: `R10: não li o modo da equipe (${modosDaEquipe.codigo ?? "?"}): ${modosDaEquipe.erro}`,
      details: { codigo: modosDaEquipe.codigo ?? null },
    });
  }
  const desligada = r10DesligadaPelaAgenda(modosDaEquipe);
  if (desligada) return desligada;

  const nowBRT = new Date(Date.now() - 3 * 3600000); // relógio deslocado p/ ler hora BRT em UTC
  const brtHour = nowBRT.getUTCHours();
  const todayBRT = nowBRT.toISOString().slice(0, 10);
  const dayStartISO = new Date(`${todayBRT}T00:00:00-03:00`).toISOString();

  let offsetDays: number; let quando: string;
  if (brtHour >= 17 && brtHour < 19) { offsetDays = 1; quando = "amanhã"; }
  else if (brtHour >= 7 && brtHour < 9) { offsetDays = 0; quando = "hoje"; }
  else return { sent: 0, skipped: "outside_window" };

  const from = new Date(new Date(dayStartISO).getTime() + offsetDays * 86400000);
  const to = new Date(from.getTime() + 86400000);

  const { data: orders } = await db.from("service_orders")
    .select("id, service_order_number, scheduled_start_at, clients(name), vessels(name, asset_type), service_order_technicians(user_id, app_users(id, full_name, phone_normalized, ai_whatsapp_enabled))")
    .eq("status", "scheduled")
    .gte("scheduled_start_at", from.toISOString())
    .lt("scheduled_start_at", to.toISOString());

  let sent = 0;
  for (const o of (orders as any[]) || []) {
    for (const t of o.service_order_technicians || []) {
      const u = t.app_users;
      if (!u?.ai_whatsapp_enabled || !u?.phone_normalized) continue;
      // dedupe: 1 lembrete por OS+telefone+dia (a janela da manhã é de outro dia → passa)
      const { data: dup } = await db.from("whatsapp_send_queue")
        .select("id").eq("source", "agenda-r10").eq("source_ref_id", o.id)
        .eq("phone_normalized", u.phone_normalized)
        .gte("created_at", dayStartISO).limit(1);
      if (dup && dup.length > 0) continue;
      const hora = new Date(o.scheduled_start_at).toLocaleTimeString("pt-BR", {
        hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo",
      });
      await db.from("whatsapp_send_queue").insert({
        phone_normalized: u.phone_normalized,
        // o número já traz o prefixo ("OS-00060"): o texto mora em rules.ts para ter teste
        message: textoDoLembreteDaOs({
          quando, hora, numero: o.service_order_number, cliente: o.clients?.name, barco: o.vessels?.name, tipo: o.vessels?.asset_type,
        }),
        source: "agenda-r10",
        source_ref_id: o.id,
        priority: 4,
      });
      sent++;
    }
  }
  return { sent, janela: quando };
}

/** Processa task_reminders vencidos → sino in-app + WhatsApp interno. */
async function processReminders(db: Db) {
  const { data: due } = await db.from("task_reminders")
    .select("id, remind_at, channel, agenda_tasks(id, title, status, assignee_user_id, due_at, scheduled_start_at)")
    .is("sent_at", null)
    .lte("remind_at", new Date().toISOString())
    .limit(100);

  let appN = 0, waN = 0;
  for (const r of (due as any[]) || []) {
    // trava otimista: só processa quem ainda está sent_at IS NULL
    const { data: claimed } = await db.from("task_reminders")
      .update({ sent_at: new Date().toISOString() })
      .eq("id", r.id).is("sent_at", null).select("id");
    if (!claimed || claimed.length === 0) continue;

    const task = r.agenda_tasks;
    if (!task || task.status === "done" || task.status === "cancelled") continue;

    const userId = task.assignee_user_id;
    if (r.channel === "app") {
      if (!userId) continue;
      await db.from("app_notifications").insert({
        user_id: userId,
        type: "task_reminder",
        title: "Lembrete de tarefa",
        body: task.title,
        navigate_to: "/agenda",
      });
      appN++;
    } else if (r.channel === "whatsapp") {
      if (!userId) continue;
      const { data: u } = await db.from("app_users")
        .select("phone_normalized, ai_whatsapp_enabled").eq("id", userId).maybeSingle();
      // canal interno APENAS: exige ai_whatsapp_enabled (nunca cliente)
      if (!(u as any)?.ai_whatsapp_enabled || !(u as any)?.phone_normalized) continue;
      await db.from("whatsapp_send_queue").insert({
        phone_normalized: (u as any).phone_normalized,
        message: `⏰ Lembrete: ${task.title}`,
        source: "task-reminder",
        source_ref_id: task.id,
        priority: 4,
      });
      waN++;
    }
  }
  return { app: appN, whatsapp: waN };
}

/** Materializa ocorrências de tarefas recorrentes (rrule) nos próximos 30 dias. */
async function materializeRecurrences(db: Db) {
  const { data: parents } = await db.from("agenda_tasks")
    .select("*")
    .not("rrule", "is", null)
    .is("recurrence_parent_id", null)
    .neq("status", "cancelled")
    .limit(100);

  const windowStart = new Date();
  const windowEnd = new Date(Date.now() + 30 * 86400000);
  let created = 0;

  for (const p of (parents as any[]) || []) {
    const anchorISO = p.scheduled_start_at || p.due_at;
    if (!anchorISO) continue;
    const dtstart = new Date(anchorISO);
    const durationMs = p.scheduled_start_at && p.scheduled_end_at
      ? new Date(p.scheduled_end_at).getTime() - new Date(p.scheduled_start_at).getTime()
      : 0;

    for (const occ of expandOccurrences(p.rrule, dtstart, windowStart, windowEnd, 40)) {
      const dayKey = occ.toISOString().slice(0, 10);
      const { error } = await db.from("agenda_tasks").insert({
        title: p.title,
        description: p.description,
        kind: p.kind,
        status: "pending",
        priority: p.priority,
        source: "recurrence",
        automation_key: `rec:${p.id}:${dayKey}`,
        recurrence_parent_id: p.id,
        assignee_user_id: p.assignee_user_id,
        scheduled_start_at: p.scheduled_start_at ? occ.toISOString() : null,
        scheduled_end_at: p.scheduled_start_at && durationMs
          ? new Date(occ.getTime() + durationMs).toISOString() : null,
        due_at: p.scheduled_start_at ? null : occ.toISOString(),
        all_day: p.all_day,
        location: p.location,
        client_id: p.client_id,
        related_entity_type: p.related_entity_type,
        related_entity_id: p.related_entity_id,
        is_private: p.is_private,
        checklist: Array.isArray(p.checklist)
          ? p.checklist.map((c: any) => ({ ...c, done: false }))
          : [],
        created_by: p.created_by,
      });
      // 23505 = ocorrência do dia já materializada; 23P01 = conflito de horário — pula
      if (!error) created++;
      else if (!["23505", "23P01"].includes((error as any).code)) {
        console.error("recurrence insert failed:", error);
      }
    }
  }
  return { created };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN: `if (cronSecret && ...)` deixava a função aberta se o env var
  // sumisse — a proteção evaporava em silêncio, que é o pior modo de falhar.
  const recusa = verificarCronSecret(req, corsHeaders, "task-automations");
  if (recusa) return recusa;

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const settings = await loadSettings(db);
    // Identidade dos contatos (Fase 12): liga telefone→cliente/fornecedor/lead nas
    // mensagens que chegaram desde o último ciclo. Barato e idempotente — sem isso o
    // detector volta a falar de "5544991777856" em vez de "Vanderlei".
    let identidade: unknown = null;
    try {
      const { data } = await db.rpc("backfill_message_identity", { p_limit: 500 });
      identidade = ((data as any[]) || [])[0] ?? null;
    } catch (e) { console.error("backfill identity:", e); }

    // Fios soltos (Fase 13): reconcilia "o que está em aberto agora" com o ERP. Abre o que
    // passou a existir e FECHA o que o banco provou que acabou — a mesma mecânica de
    // auto-resolução das regras. SQL puro, sem IA.
    let fios: unknown = null;
    try {
      const { data } = await db.rpc("refresh_entity_open_loops");
      fios = ((data as any[]) || [])[0] ?? null;
    } catch (e) { console.error("refresh open loops:", e); }

    // Material da Agenda de Produção (Fase 1, P2): antes das regras, para a R16 ler a conta com o
    // material em dia. Tem o próprio try/catch (sincronizarMaterialDaAgenda nunca lança: devolve
    // { erro } e grava em app_error_logs); o de fora é a segunda trava, para nada daqui parar as regras.
    let agendaMaterial: unknown = null;
    try {
      agendaMaterial = await sincronizarMaterialDaAgenda(db);
    } catch (e) {
      console.error("agenda:material:", e);
      agendaMaterial = { erro: String((e as any)?.message ?? e) };
    }

    // A vigia do material (Fase 4, P5): depois do material (as linhas em dia) e antes da rotina e da vigia (a vigia lê a
    // previsão que a nota ou o fornecedor atualizou no mesmo tique). A nota, o Pix, a conversa do fornecedor, a pergunta ao
    // fornecedor nos terços e os cadastros, tudo no banco (agenda_material_vigiar); nada é enviado daqui. Tem o próprio
    // try/catch (vigiarMaterialDaAgenda nunca lança: devolve { erro } e grava em app_error_logs); o de fora é a segunda
    // trava, para nada daqui parar a rotina, a vigia e as regras.
    let agendaMaterialVigia: unknown = null;
    try {
      agendaMaterialVigia = await vigiarMaterialDaAgenda(db, new Date());
    } catch (e) {
      console.error("agenda:material-vigia:", e);
      agendaMaterialVigia = { erro: String((e as any)?.message ?? e) };
    }

    // A rotina da equipe e da diária (Fase 3, P4): logo antes da vigia (o "não vou" e o silêncio replanejam, e a vigia
    // lê o plano já mudado). Tem o próprio try/catch (rodarRotinaDaAgenda nunca lança: devolve { erro } e grava em
    // app_error_logs); o de fora é a segunda trava, para nada daqui parar a vigia e as regras.
    let agendaRotina: unknown = null;
    try {
      agendaRotina = await rodarRotinaDaAgenda(db, new Date());
    } catch (e) {
      console.error("agenda:rotina:", e);
      agendaRotina = { erro: String((e as any)?.message ?? e) };
    }

    // A rodada do aprendizado (Fase 6, P8): depois da rotina (a medida lê a conferência do dia em dia) e antes da vigia (a
    // vigia, o motor e a rodada do cliente leem o que ela aprendeu no mesmo tique). Chamada a cada tique: o banco roda uma vez
    // por dia, a partir de aprender_hora (cedo e ja_rodou são o normal). Tem o próprio try/catch (aprenderDaAgenda nunca
    // lança: devolve { erro } e grava em app_error_logs); o de fora é a segunda trava, para nada daqui parar a vigia e as regras.
    let agendaAprender: unknown = null;
    try {
      agendaAprender = await aprenderDaAgenda(db, new Date());
    } catch (e) {
      console.error("agenda:aprender:", e);
      agendaAprender = { erro: String((e as any)?.message ?? e) };
    }

    // A vigia da Agenda de Produção (Fase 2, P3): depois do material (lê a conta em dia) e antes das regras (a R1, a
    // R2 e a R16 leem o que ela fez). Tem o próprio try/catch (vigiarAgenda nunca lança: devolve { erro } e grava em
    // app_error_logs); o de fora é a segunda trava, para nada daqui parar as regras.
    // (correção de 29/10, P4) a vigia e o aviso do gestor com o MESMO instante: a rodada do aviso é a da vigia.
    const agoraDaVigia = new Date();
    let agendaVigia: unknown = null;
    try {
      agendaVigia = await vigiarAgenda(db, agoraDaVigia);
    } catch (e) {
      console.error("agenda:vigia:", e);
      agendaVigia = { erro: String((e as any)?.message ?? e) };
    }

    // O aviso do gestor ao dono (correção de 29/10, P4): logo depois da vigia (conta o que ela acabou de mudar) e antes da
    // rodada do cliente e das regras. Tem o próprio try/catch (avisarDonoDaAgenda nunca lança: devolve { erro } e grava em
    // app_error_logs); o de fora é a segunda trava, para nada daqui parar o resto.
    let agendaAviso: unknown = null;
    try {
      agendaAviso = await avisarDonoDaAgenda(db, agoraDaVigia);
    } catch (e) {
      console.error("agenda:aviso:", e);
      agendaAviso = { erro: String((e as any)?.message ?? e) };
    }

    // A rodada da mensagem ao cliente (Fase 5, P3): depois da vigia (lê o plano já replanejado: a mudança no dia, o aviso de
    // atraso) e antes das regras. Roda SEMPRE (o passo "fila" do banco vale até com tudo desligado); nada é enviado daqui.
    // Tem o próprio try/catch (vigiarClienteDaAgenda nunca lança: devolve { erro } e grava em app_error_logs); o de fora é a
    // segunda trava, para nada daqui parar as regras.
    let agendaClienteVigia: unknown = null;
    try {
      agendaClienteVigia = await vigiarClienteDaAgenda(db, new Date());
    } catch (e) {
      console.error("agenda:cliente-vigia:", e);
      agendaClienteVigia = { erro: String((e as any)?.message ?? e) };
    }

    const rules = await runRules(db, settings);
    const r10 = await runTechnicianReminders(db, settings);
    const reminders = await processReminders(db);
    const recurrence = await materializeRecurrences(db);

    const summary = {
      identidade, fios, agenda_material: agendaMaterial, agenda_material_vigia: agendaMaterialVigia, agenda_rotina: agendaRotina,
      agenda_aprender: agendaAprender, agenda_vigia: agendaVigia, agenda_aviso: agendaAviso, agenda_cliente_vigia: agendaClienteVigia,
      rules, r10, reminders, recurrence,
    };
    // Regra que falhou também é motivo para auditar: sem isto, um tick em que TODAS as
    // regras quebraram não deixaria registro nenhum (created e resolved vazios).
    if (rules.created.length || rules.resolved.length || recurrence.created || rules.falhas.length) {
      await audit(db, "task_automations_run", summary);
    }
    return new Response(JSON.stringify({ success: true, ...summary }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("task-automations failed:", e);
    return new Response(JSON.stringify({ success: false, error: String(e) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
