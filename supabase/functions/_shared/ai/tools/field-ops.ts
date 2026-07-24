import type { ToolDef } from "./registry.ts";

// Operação de campo + agenda inteligente (Fase 2) — SEM schema novo.
// O schema já tinha o necessário: service_orders.check_in_at / check_out_at / technician_notes,
// agenda_tasks e service_order_technicians.
//
// Estas tools são PARA O TÉCNICO usar pelo WhatsApp — por isso NÃO têm restrição de cargo
// (ao contrário das financeiras). Nenhuma delas expõe preço, custo ou margem.

/** Carimbo curto pt-BR para a linha de progresso. */
function carimbo(): string {
  const d = new Date();
  const data = d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo" });
  const hora = d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
  return `[${data} ${hora}]`;
}

/** Anexa uma linha ao technician_notes preservando o que já estava lá. */
async function anexarNota(sb: any, soId: string, linha: string): Promise<string> {
  const { data: so } = await sb.from("service_orders").select("technician_notes").eq("id", soId).maybeSingle();
  const atual = (so?.technician_notes || "").trim();
  const novo = atual ? `${atual}\n${linha}` : linha;
  await sb.from("service_orders").update({ technician_notes: novo.slice(0, 8000) }).eq("id", soId);
  return novo;
}

export const fieldOpsTools: ToolDef[] = [
  {
    name: "check_in_service_order",
    description:
      "Registra a CHEGADA do técnico no serviço (check-in): marca a hora e move a OS para 'em andamento'. Use quando o técnico disser 'cheguei', 'comecei o serviço', 'estou no barco'. Não mexe em preço nem conclui a OS.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "Observação inicial opcional (ex.: 'cliente pediu para ver o inversor também')." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, check_in_at")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não dá para fazer check-in." };
      if (so.check_in_at) {
        return { ok: true, ja_feito: true, os: so.service_order_number, check_in_em: so.check_in_at, mensagem: "Check-in já estava registrado." };
      }

      const agora = new Date().toISOString();
      const patch: Record<string, unknown> = { check_in_at: agora };
      // Só promove para "em andamento" a partir de estados de trabalho — não mexe em concluída/faturada.
      if (["open", "scheduled", "approved", "pending", "awaiting_parts"].includes(so.status)) {
        patch.status = "in_progress";
      }
      const { error } = await sb.from("service_orders").update(patch).eq("id", so.id);
      if (error) throw error;

      if (args.note) await anexarNota(sb, so.id, `${carimbo()} Check-in: ${args.note}`);
      else await anexarNota(sb, so.id, `${carimbo()} Check-in do técnico.`);

      return { ok: true, os: so.service_order_number, check_in_em: agora, status: patch.status || so.status };
    },
  },
  {
    name: "check_out_service_order",
    description:
      "Registra a SAÍDA do técnico (check-out): marca a hora de término e grava o relato do que foi feito. Use quando o técnico disser 'terminei', 'saí do barco', 'finalizei o serviço'. NÃO conclui a OS nem fatura — concluir é update_service_order_status, decisão de quem administra.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "Relato do que foi feito (recomendado)." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, check_in_at, check_out_at")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não dá para fazer check-out." };

      const agora = new Date().toISOString();
      const { error } = await sb.from("service_orders").update({ check_out_at: agora }).eq("id", so.id);
      if (error) throw error;

      const linha = args.note ? `${carimbo()} Check-out: ${args.note}` : `${carimbo()} Check-out do técnico.`;
      await anexarNota(sb, so.id, linha);

      // Duração só faz sentido se houve check-in.
      let duracao: string | null = null;
      if (so.check_in_at) {
        const min = Math.max(0, Math.round((new Date(agora).getTime() - new Date(so.check_in_at).getTime()) / 60000));
        duracao = min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${String(min % 60).padStart(2, "0")}`;
      }
      return {
        ok: true,
        os: so.service_order_number,
        check_out_em: agora,
        duracao_no_local: duracao,
        lembrete: "A OS continua no status atual — concluir/faturar é decisão de quem administra.",
      };
    },
  },
  {
    name: "log_service_order_progress",
    description:
      "Registra uma nota de PROGRESSO do serviço na OS (fica no histórico do técnico, com data e hora). Use para relatos do dia a dia: 'troquei as duas baterias', 'faltou peça X', 'cliente pediu mais um serviço'. Se veio de áudio, registre o que foi falado.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "O que aconteceu / foi feito." },
      },
      required: ["service_order_id", "note"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb.from("service_orders").select("id, service_order_number, status").eq("id", args.service_order_id).maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não aceita novas notas." };
      await anexarNota(sb, so.id, `${carimbo()} ${args.note}`);
      return { ok: true, os: so.service_order_number, registrado: args.note };
    },
  },
  {
    name: "attach_photo_to_service_order",
    description:
      "Vincula uma FOTO/arquivo recebido no WhatsApp a uma OS (fica anexado ao serviço, ex.: 'antes' e 'depois'). Use o message_id que veio de read_supplier_messages ou da conversa. Não copia o arquivo — apenas amarra a mensagem à OS.",
    input_schema: {
      type: "object",
      properties: {
        message_id: { type: "string", description: "UUID da mensagem do WhatsApp que contém a foto/arquivo." },
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "Legenda opcional (ex.: 'antes da troca')." },
      },
      required: ["message_id", "service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: msg } = await sb
        .from("whatsapp_messages")
        .select("id, message_type, body, service_order_id")
        .eq("id", args.message_id)
        .maybeSingle();
      if (!msg) return { error: "Mensagem não encontrada." };
      const { data: so } = await sb.from("service_orders").select("id, service_order_number").eq("id", args.service_order_id).maybeSingle();
      if (!so) return { error: "OS não encontrada." };

      const { error } = await sb.from("whatsapp_messages").update({ service_order_id: so.id }).eq("id", msg.id);
      if (error) throw error;
      if (args.note) await anexarNota(sb, so.id, `${carimbo()} Foto anexada: ${args.note}`);

      return { ok: true, os: so.service_order_number, tipo: msg.message_type, legenda: args.note || null };
    },
  },
  {
    name: "check_technician_availability",
    description:
      "Mostra a AGENDA de um técnico num dia: tarefas da agenda e OS agendadas, em ordem de horário — e avisa se um horário proposto conflita. Use antes de agendar ('dá pra encaixar o João amanhã 14h?').",
    input_schema: {
      type: "object",
      properties: {
        technician_user_id: { type: "string", description: "UUID do técnico (use list_technicians)." },
        date: { type: "string", description: "Dia a consultar (YYYY-MM-DD). Padrão: hoje." },
        proposed_start: { type: "string", description: "Horário proposto (ISO) para checar conflito, opcional." },
        proposed_end: { type: "string", description: "Fim do horário proposto (ISO), opcional." },
      },
      required: ["technician_user_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const dia = String(args.date || new Date().toISOString().slice(0, 10));
      const ini = `${dia}T00:00:00`;
      const fim = `${dia}T23:59:59`;

      const { data: tarefas } = await sb
        .from("agenda_tasks")
        .select("id, title, scheduled_start_at, scheduled_end_at, status, location")
        .eq("assignee_user_id", args.technician_user_id)
        .gte("scheduled_start_at", ini)
        .lte("scheduled_start_at", fim);

      // OS agendadas para este técnico (vínculo em service_order_technicians).
      const { data: vinc } = await sb
        .from("service_order_technicians")
        .select("service_order_id")
        .eq("user_id", args.technician_user_id);
      const soIds = ((vinc as any[]) || []).map((v) => v.service_order_id).filter(Boolean);
      let oss: any[] = [];
      if (soIds.length) {
        const { data } = await sb
          .from("service_orders")
          .select("id, service_order_number, scheduled_start_at, scheduled_end_at, status, clients(name)")
          .in("id", soIds)
          .gte("scheduled_start_at", ini)
          .lte("scheduled_start_at", fim)
          .neq("status", "cancelled");
        oss = (data as any[]) || [];
      }

      const compromissos = [
        ...((tarefas as any[]) || []).map((t) => ({
          tipo: "tarefa", titulo: t.title, inicio: t.scheduled_start_at, fim: t.scheduled_end_at, status: t.status, local: t.location || null,
        })),
        ...oss.map((o) => ({
          tipo: "OS", titulo: `${o.service_order_number}${o.clients?.name ? ` — ${o.clients.name}` : ""}`,
          inicio: o.scheduled_start_at, fim: o.scheduled_end_at, status: o.status, local: null,
        })),
      ].sort((a, b) => new Date(a.inicio || 0).getTime() - new Date(b.inicio || 0).getTime());

      // Conflito = sobreposição real de intervalos.
      let conflito: any = null;
      if (args.proposed_start) {
        const pIni = new Date(args.proposed_start).getTime();
        const pFim = args.proposed_end ? new Date(args.proposed_end).getTime() : pIni + 60 * 60000;
        for (const c of compromissos) {
          const cIni = c.inicio ? new Date(c.inicio).getTime() : null;
          if (cIni === null) continue;
          const cFim = c.fim ? new Date(c.fim).getTime() : cIni + 60 * 60000;
          if (pIni < cFim && cIni < pFim) { conflito = c; break; }
        }
      }

      return {
        dia,
        compromissos,
        total: compromissos.length,
        horario_proposto: args.proposed_start || null,
        conflito,
        livre: args.proposed_start ? !conflito : null,
      };
    },
  },
];
