// Edge Function: agenda-inbox-detector (Agenda Autônoma — Fase 9)
// Lê as conversas de WhatsApp da janela recente, extrai COMPROMISSOS e grava
// SUGESTÕES (nunca tarefas) na Caixa de Entrada da Agenda.
// Escopo autorizado pelo usuário (26/07/2026): todas as conversas do número da HBR,
// com lista de exclusão por contato (agenda_detector_exclusions).
// Cursor em app_settings.agenda_detector_cursor evita reprocessar e limita custo.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  detectInConversation, shouldAutoCreate, loopKeyFromTitle,
  type ConversationMessage, type DetectorStats,
} from "../_shared/ai/inbox-detector.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const CURSOR_KEY = "agenda_detector_cursor";
const MAX_CONVERSATIONS_PER_RUN = 12; // teto de custo por execução

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret && ...)`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "agenda-inbox-detector");
  if (recusa) return recusa;

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    const { data: settingsRows } = await db.from("app_settings").select("key, value")
      .in("key", [CURSOR_KEY, "agenda_detector_enabled", "agenda_autonomy_enabled"]);
    const settings = Object.fromEntries((settingsRows || []).map((s: any) => [s.key, s.value]));

    if ((settings["agenda_detector_enabled"] ?? "true") !== "true") {
      return jr({ ok: true, skipped: "disabled" });
    }
    // Autonomia graduada (Fase 11): nasce LIGADA, mas só age em detector que já provou
    // acerto (≥8 decisões e ≥80% de aceite). Até lá, tudo continua indo para a caixa.
    const autonomyEnabled = (settings["agenda_autonomy_enabled"] ?? "true") === "true";

    // Histórico de decisões por detector — a evidência que libera (ou não) a autonomia
    const { data: hist } = await db.from("agenda_suggestions")
      .select("detector, status").in("status", ["accepted", "dismissed"]).limit(1000);
    const statsByDetector: Record<string, DetectorStats> = {};
    for (const s of ((hist as any[]) || [])) {
      statsByDetector[s.detector] = statsByDetector[s.detector] || { accepted: 0, dismissed: 0 };
      if (s.status === "accepted") statsByDetector[s.detector].accepted++;
      else statsByDetector[s.detector].dismissed++;
    }

    // Janela: do cursor até agora (com piso de 24h para não varrer histórico inteiro)
    const floor = new Date(Date.now() - 24 * 3600000).toISOString();
    const cursor = settings[CURSOR_KEY] && settings[CURSOR_KEY] > floor ? settings[CURSOR_KEY] : floor;
    const runAt = new Date().toISOString();

    const { data: msgs } = await db.from("whatsapp_messages")
      .select("id, direction, body, occurred_at, message_type, phone_normalized, client_id")
      .gt("occurred_at", cursor)
      .lte("occurred_at", runAt)
      .order("occurred_at", { ascending: true })
      .limit(400);

    const rows = (msgs as any[]) || [];
    if (rows.length === 0) {
      await db.from("app_settings").upsert({ key: CURSOR_KEY, value: runAt }, { onConflict: "key" });
      return jr({ ok: true, novas_mensagens: 0, sugestoes: 0 });
    }

    // Exclusões (contatos que o detector nunca lê)
    const { data: excl } = await db.from("agenda_detector_exclusions").select("phone_normalized");
    const excluded = new Set(((excl as any[]) || []).map((e) => e.phone_normalized));

    // Destinatário da caixa de entrada: piloto = o dono (admin ativo com canal IA)
    const { data: owner } = await db.from("app_users")
      .select("id").eq("active", true).eq("ai_whatsapp_enabled", true)
      .order("created_at", { ascending: true }).limit(1).maybeSingle();
    const targetUserId = (owner as any)?.id ?? null;

    // Agrupa por conversa (telefone)
    const byPhone = new Map<string, any[]>();
    for (const m of rows) {
      const phone = m.phone_normalized || "desconhecido";
      if (excluded.has(phone)) continue;
      if (!byPhone.has(phone)) byPhone.set(phone, []);
      byPhone.get(phone)!.push(m);
    }

    // Conversas mais movimentadas primeiro (mais provável conter compromisso)
    const conversations = Array.from(byPhone.entries())
      .sort((a, b) => b[1].length - a[1].length)
      .slice(0, MAX_CONVERSATIONS_PER_RUN);

    let created = 0;
    let autoCreated = 0;
    // Menções que caíram num fio já aberto — não viraram sugestão nova. Este número subindo
    // enquanto 'sugestoes' fica estável é o sinal de que o agrupamento está funcionando.
    let reforcados = 0;
    // Propostas descartadas por virem de mensagem que já rendeu sugestão viva.
    let repetidas = 0;
    const detalhes: any[] = [];

    for (const [phone, convMsgs] of conversations) {
      try {
        // Identidade do contato (Fase 12): resolve telefone → cliente/fornecedor/lead
        // pela RPC, não só pelo que a mensagem já trazia. Sem isso o detector escrevia
        // "acompanhar entrega das baterias" sem saber de quem nem de qual OS.
        let contactLabel = phone;
        let clientId: string | null = null;
        let supplierId: string | null = null;
        let identityKind: string | null = null;
        const { data: ident } = await db.rpc("resolve_contact_identity", { p_phone: phone });
        const id0 = ((ident as any[]) || [])[0];
        if (id0) {
          identityKind = id0.kind;
          contactLabel = id0.entity_name || phone;
          if (id0.kind === "client") clientId = id0.entity_id;
          else if (id0.kind === "supplier") supplierId = id0.entity_id;
        } else {
          const withClient = convMsgs.find((m: any) => m.client_id);
          if (withClient) {
            clientId = withClient.client_id;
            const { data: c } = await db.from("clients").select("name").eq("id", clientId).maybeSingle();
            if ((c as any)?.name) { contactLabel = (c as any).name; identityKind = "client"; }
          }
        }

        // Contexto do ERP: o que já está aberto com este contato. É o que permite ao
        // detector falar do CONJUNTO ("materiais da OS-1042") em vez de um item solto.
        let erpContext = "";
        // Fios abertos com códigos [L1], [L2]… — o modelo devolve o código para dizer
        // "isto atualiza aquele fio" em vez de propor uma segunda tarefa quase igual.
        const loopsPorCodigo = new Map<string, { id: string; title: string; service_order_id: string | null }>();
        // OS conhecidas deste contato, para converter "OS-1042" em id de verdade.
        const osPorNumero = new Map<string, string>();

        const loopEntityType = identityKind === "supplier" ? "supplier" : "client";
        const loopEntityId = loopEntityType === "supplier" ? supplierId : clientId;

        if (loopEntityId) {
          const { data: loops } = await db.rpc("get_entity_open_loops", {
            p_entity_type: loopEntityType, p_entity_id: loopEntityId, p_limit: 12,
          });
          ((loops as any[]) || []).forEach((l, i) => {
            const codigo = `L${i + 1}`;
            loopsPorCodigo.set(codigo, {
              id: l.id, title: l.title, service_order_id: l.service_order_id ?? null,
            });
            if (l.service_order_number) osPorNumero.set(String(l.service_order_number).toUpperCase(), l.service_order_id);
          });
        }

        if (clientId) {
          // Status reais da tabela. A lista anterior citava valores inexistentes
          // ('waiting_parts', 'waiting_approval', 'reopened') e omitia 'open'/'awaiting_parts',
          // então o detector enxergava só parte das OS ativas.
          const { data: openSos } = await db.from("service_orders")
            .select("id, service_order_number, status, problem_description")
            .eq("client_id", clientId)
            .in("status", ["open", "approved", "scheduled", "in_progress", "awaiting_parts"])
            .order("created_at", { ascending: false }).limit(5);
          const { data: openTasks } = await db.from("agenda_tasks")
            .select("title").eq("client_id", clientId)
            .in("status", ["pending", "in_progress"]).limit(8);
          const partes: string[] = [];
          if (openSos && openSos.length) {
            for (const o of (openSos as any[])) {
              if (o.service_order_number) osPorNumero.set(String(o.service_order_number).toUpperCase(), o.id);
            }
            partes.push("OS abertas deste cliente:\n" + (openSos as any[]).map((o) =>
              `- ${o.service_order_number} (${o.status})${o.problem_description ? `: ${String(o.problem_description).slice(0, 90)}` : ""}`,
            ).join("\n"));
          }
          if (openTasks && openTasks.length) {
            partes.push("Tarefas JÁ existentes para este cliente (não duplique):\n" +
              (openTasks as any[]).map((t) => `- ${t.title}`).join("\n"));
          }
          erpContext = partes.join("\n\n");
        }

        if (loopsPorCodigo.size > 0) {
          const lista = Array.from(loopsPorCodigo.entries())
            .map(([codigo, l]) => `[${codigo}] ${l.title}`).join("\n");
          erpContext = [erpContext,
            "FIOS JÁ ABERTOS com este contato — se a conversa for sobre um destes, preencha " +
            "updates_open_loop com o código e NÃO crie proposta nova:\n" + lista,
          ].filter(Boolean).join("\n\n");
        }

        // Contexto: inclui até 10 mensagens anteriores da MESMA conversa (fora da janela),
        // senão "vou te mandar amanhã" isolado perde o assunto.
        const { data: prev } = await db.from("whatsapp_messages")
          .select("id, direction, body, occurred_at, message_type")
          .eq("phone_normalized", phone)
          .lte("occurred_at", convMsgs[0].occurred_at)
          .order("occurred_at", { ascending: false })
          .limit(10);
        const contextMsgs: ConversationMessage[] = [
          ...(((prev as any[]) || []).reverse()),
          ...convMsgs,
        ].filter((m, i, arr) => arr.findIndex((x) => x.id === m.id) === i);

        // Sugestões que JÁ estão esperando decisão para este contato.
        // Duas funções, e as duas importam:
        //  (a) entram no prompt, para o modelo não propor de novo o mesmo assunto;
        //  (b) viram uma trava determinística logo abaixo — o modelo pode desobedecer,
        //      a trava não.
        // Isto cobre o contato NÃO IDENTIFICADO, que é justamente onde o fio solto não
        // existe (fio exige cliente/fornecedor) e a duplicata passava batido.
        const { data: pendentes } = await db.from("agenda_suggestions")
          .select("title, source_message_id")
          .eq("source_phone", phone).eq("status", "pending").limit(20);
        const jaPropostas = ((pendentes as any[]) || []);
        // Fotografado ANTES do laço: duas propostas da mesma mensagem na MESMA execução
        // continuam valendo (um áudio pode conter dois pedidos). O que fica barrado é a
        // mensagem voltar a gerar sugestão numa execução POSTERIOR, com outras palavras.
        const mensagensJaUsadas = new Set(
          jaPropostas.map((s) => s.source_message_id).filter(Boolean),
        );
        if (jaPropostas.length > 0) {
          erpContext = [erpContext,
            "JÁ ESPERANDO DECISÃO deste contato (não proponha de novo):\n" +
            jaPropostas.map((s) => `- ${s.title}`).join("\n"),
          ].filter(Boolean).join("\n\n");
        }

        const proposals = await detectInConversation(contextMsgs, contactLabel, new Date(), erpContext);

        for (const p of proposals) {
          // A mensagem que originou esta proposta já rendeu sugestão viva num ciclo
          // anterior? Então é a mesma coisa dita de outro jeito — descarta.
          if (p.source_message_id && mensagensJaUsadas.has(p.source_message_id)) {
            repetidas++;
            continue;
          }

          // Fase 14 — o assunto já tem fio? Então isto é uma COBRANÇA, não um compromisso
          // novo: reforça o fio existente (mentions +1, evidência mais recente) e segue.
          // É o que impede a segunda sugestão quase idêntica.
          const alvo = p.updates_open_loop
            ? loopsPorCodigo.get(String(p.updates_open_loop).replace(/[^A-Za-z0-9]/g, "").toUpperCase())
            : undefined;
          if (alvo) {
            await db.rpc("touch_open_loop", {
              p_loop_id: alvo.id,
              p_evidence: p.evidence,
              p_evidence_at: p.evidence_at,
              p_source_message_id: p.source_message_id,
            });
            reforcados++;
            continue;
          }

          // OS citada pelo modelo → id real (só aceita número que exista para este contato)
          const osId = p.service_order_number
            ? (osPorNumero.get(String(p.service_order_number).toUpperCase()) ?? null)
            : null;

          const auto = shouldAutoCreate(p, statsByDetector, autonomyEnabled);
          const { data: sugg, error } = await db.from("agenda_suggestions").insert({
            title: p.title,
            kind: p.kind,
            suggested_due_at: p.suggested_due_at,
            suggested_start_at: p.suggested_start_at,
            priority: p.priority || "normal",
            evidence: p.evidence,
            evidence_at: p.evidence_at,
            confidence: p.confidence,
            detector: p.detector,
            origin: "whatsapp",
            source_message_id: p.source_message_id,
            source_phone: phone,
            contact_label: contactLabel,
            client_id: clientId,
            // Vincular à OS é mais preciso que vincular ao cliente: abre direto no trabalho
            // de que a conversa tratava. Só cai no cliente quando não há OS identificada.
            related_entity_type: osId ? "service_order" : (clientId ? "client" : null),
            related_entity_id: osId ?? clientId ?? supplierId,
            target_user_id: targetUserId,
          }).select("id").single();
          // 23505 = já existe sugestão viva idêntica para a mesma mensagem
          if (error) {
            if ((error as any).code !== "23505") console.error("insert suggestion:", error);
            continue;
          }
          created++;

          // Abre (ou reforça) o fio solto correspondente. A chave vem do título normalizado:
          // é a rede de segurança para quando o modelo não apontar updates_open_loop mas
          // repetir um assunto equivalente.
          let loopId: string | null = null;
          if (loopEntityId) {
            try {
              const { data: loop } = await db.rpc("record_conversation_loop", {
                p_entity_type: loopEntityType,
                p_entity_id: loopEntityId,
                p_loop_key: loopKeyFromTitle(p.title),
                p_kind: p.detector === "client_request" ? "request" : "promise",
                p_title: p.title,
                p_detail: null,
                p_service_order_id: osId,
                p_due_at: p.suggested_due_at ?? p.suggested_start_at,
                p_priority: p.priority || "normal",
                p_evidence: p.evidence,
                p_evidence_at: p.evidence_at,
                p_source_message_id: p.source_message_id,
              });
              loopId = ((loop as any[]) || [])[0]?.loop_id ?? null;
            } catch (e) { console.error("record loop:", e); }

            // Guarda o vínculo NA SUGESTÃO. É por aqui que o fio fecha quando você conclui a
            // tarefa: sugestão → created_task_id → tarefa concluída. Serve tanto para o
            // aceite manual na caixa de entrada quanto para a criação automática abaixo.
            if (loopId) {
              await db.from("agenda_suggestions")
                .update({ open_loop_id: loopId }).eq("id", (sugg as any).id);
            }
          }

          // Autonomia conquistada: cria a tarefa direto e marca a sugestão como aceita.
          // O card continua existindo (com o vínculo), então desfazer é 1 clique.
          if (auto) {
            const { data: task } = await db.from("agenda_tasks").insert({
              title: p.title,
              kind: p.kind,
              status: "pending",
              priority: p.priority || "normal",
              assignee_user_id: targetUserId,
              due_at: p.suggested_due_at,
              scheduled_start_at: p.suggested_start_at,
              client_id: clientId,
              // Mesmo vínculo da sugestão: se a conversa era sobre uma OS, a tarefa abre na
              // OS. Antes a sugestão apontava para a OS e a tarefa para o cliente — aceitar
              // o card e deixar a autonomia agir levavam a lugares diferentes.
              related_entity_type: osId ? "service_order" : (clientId ? "client" : null),
              related_entity_id: osId ?? clientId,
              notes: `Criada automaticamente da conversa com ${contactLabel}\n"${p.evidence}"`,
              source: "ai",
            }).select("id").single();
            if (task) {
              // Vínculo direto fio→tarefa, além do caminho pela sugestão: aqui a tarefa é
              // criada sem passar pelo aceite, então vale fechar as duas pontas.
              if (loopId) {
                await db.from("entity_open_loops")
                  .update({ task_id: (task as any).id }).eq("id", loopId);
              }
              await db.from("agenda_suggestions").update({
                status: "accepted",
                resolved_at: new Date().toISOString(),
                created_task_id: (task as any).id,
                dismiss_reason: "auto:autonomia",
              }).eq("id", (sugg as any).id);
              autoCreated++;
            }
          }
        }
        if (proposals.length > 0) {
          detalhes.push({ contato: contactLabel, propostas: proposals.length });
        }
      } catch (e) {
        console.error(`detector falhou na conversa ${phone}:`, e);
      }
    }

    await db.from("app_settings").upsert({ key: CURSOR_KEY, value: runAt }, { onConflict: "key" });

    if (created > 0 || reforcados > 0) {
      await db.from("ai_operator_audit").insert({
        actor_kind: "system", event_type: "agenda_inbox_detector_run", event_category: "data",
        payload: {
          mensagens: rows.length, conversas: conversations.length,
          sugestoes: created, fios_reforcados: reforcados,
          repetidas_descartadas: repetidas, detalhes,
        },
      }).then(() => {}, () => {});
    }

    return jr({
      ok: true,
      novas_mensagens: rows.length,
      conversas_analisadas: conversations.length,
      sugestoes: created,
      fios_reforcados: reforcados,
      // Sobe quando a mesma mensagem tenta virar sugestão de novo, com outras palavras.
      repetidas_descartadas: repetidas,
      criadas_automaticamente: autoCreated,
      autonomia: Object.fromEntries(Object.entries(statsByDetector).map(([k, v]) => [
        k, `${v.accepted}/${v.accepted + v.dismissed}`,
      ])),
      detalhes,
    });
  } catch (e) {
    console.error("[agenda-inbox-detector] fatal", e);
    return jr({ ok: false, error: String(e) }, 500);
  }
});
