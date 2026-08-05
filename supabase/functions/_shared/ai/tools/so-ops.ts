import { NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

/**
 * Paridade entre a TELA de edição da OS e o assistente.
 *
 * Levantamento de 05/08/2026 cruzando o que a tela faz com o que o agente sabia
 * fazer: despesa, hora trabalhada, duplicar a OS e boa parte do roteiro (iniciar,
 * pular, reabrir) só existiam na tela. O agente conseguia criar a OS, editar itens
 * e concluir passo, mas não registrar o que se gasta nem o tempo que se trabalha —
 * justamente o que se informa de campo, pelo celular, onde a tela é o pior lugar.
 *
 * Despesa e hora passam por RPC (`so_expense_add`, `so_time_entry_add`) em vez de
 * insert direto por um motivo duro: as duas mexem no VALOR da OS, e o recálculo é
 * encadeado — `recalc_so_totals` LÊ o custo operacional em vez de somá-lo das
 * despesas. Inserir sem recalcular deixaria o total errado no que se cobra do
 * cliente.
 */

/** Minutos a partir de texto solto: "2h", "1h30", "90", "45 min". */
export function parseMinutes(entrada: string | number | null | undefined): number | null {
  if (typeof entrada === "number") return Number.isFinite(entrada) && entrada > 0 ? Math.round(entrada) : null;
  if (!entrada) return null;
  const txt = String(entrada).toLowerCase().replace(/\s+/g, "");

  // "1h30" / "1h30min" / "1:30"
  const composto = txt.match(/^(\d+)[h:](\d{1,2})/);
  if (composto) return parseInt(composto[1], 10) * 60 + parseInt(composto[2], 10);

  // "2h" / "2hs" / "2horas"
  const horas = txt.match(/^(\d+(?:[.,]\d+)?)h/);
  if (horas) return Math.round(parseFloat(horas[1].replace(",", ".")) * 60);

  // "90min" / "90m" / "90"
  const min = txt.match(/^(\d+)(?:min|m)?$/);
  if (min) return parseInt(min[1], 10);

  return null;
}

export const soOpsTools: ToolDef[] = [
  {
    name: "add_service_order_expense",
    description:
      "Lança uma DESPESA na ordem de serviço (pedágio, combustível, estacionamento, alimentação, material comprado na hora, frete). " +
      "Use quando disserem 'gastei X com Y nessa OS', 'paguei o pedágio', 'coloquei R$80 de gasolina'. " +
      "O total da OS é recalculado sozinho. Por padrão a despesa é FATURÁVEL (entra no que o cliente paga); " +
      "se disserem que é por conta da casa, passe billable=false — aí ela fica registrada para margem e reembolso, sem inflar a conta do cliente.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        description: { type: "string", description: "O que foi gasto, em linguagem natural ('pedágio Anchieta', 'almoço da equipe')." },
        amount: { type: "number", description: "Valor em reais." },
        category: {
          type: "string",
          description: "Tipo: travel (deslocamento/pedágio/combustível), meal (alimentação), material, freight (frete), other. Na dúvida use other.",
        },
        billable: { type: "boolean", description: "Repassa ao cliente? Padrão true." },
        expense_date: { type: "string", description: "Data ISO (AAAA-MM-DD). Padrão: hoje." },
        supplier_id: { type: "string", description: "Fornecedor, se a despesa veio de um." },
        notes: { type: "string" },
      },
      required: ["service_order_id", "description", "amount"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      const { data, error } = await sb.rpc("so_expense_add", {
        p_so_id: args.service_order_id,
        p_category: args.category || "other",
        p_description: args.description,
        p_amount: args.amount,
        p_expense_date: args.expense_date ?? null,
        p_paid_by: "company",
        p_billable: args.billable !== false,
        p_supplier_id: args.supplier_id ?? null,
        p_notes: args.notes ?? null,
      });
      if (error) throw error;
      const r = (data ?? {}) as any;
      return {
        ok: true,
        despesa_id: r.id,
        novo_total_da_os: r.grand_total,
        faturavel: args.billable !== false,
      };
    },
  },
  {
    name: "remove_service_order_expense",
    description:
      "Remove uma despesa lançada na OS e recalcula o total. Use quando disserem 'apaga aquela despesa', 'lancei errado'. " +
      "Precisa do id da despesa — pegue em get_service_order, que traz as despesas.",
    input_schema: {
      type: "object",
      properties: { expense_id: { type: "string", description: "UUID da despesa." } },
      required: ["expense_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      const { data, error } = await sb.rpc("so_expense_remove", { p_expense_id: args.expense_id });
      if (error) throw error;
      const r = (data ?? {}) as any;
      return { ok: true, novo_total_da_os: r.grand_total };
    },
  },
  {
    name: "log_service_order_hours",
    description:
      "Aponta HORA TRABALHADA na OS. Use quando disserem 'trabalhei 2h nessa OS', 'fiquei 1h30 lá', 'foram 45 minutos'. " +
      "Aceita duração em texto ('2h', '1h30', '90min') ou minutos. Sem técnico informado, é de quem está falando. " +
      "Sem horário de início, conta para trás a partir de agora — é como se aponta hora na prática, depois do trabalho feito.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        duration: { type: "string", description: "Duração: '2h', '1h30', '90min' ou número de minutos." },
        technician_user_id: { type: "string", description: "UUID do técnico. Omita para usar quem está falando." },
        started_at: { type: "string", description: "Início em ISO, se souber. Omita para contar para trás a partir de agora." },
        billable: { type: "boolean", description: "Hora cobrável? Padrão true." },
        notes: { type: "string", description: "O que foi feito nesse tempo." },
      },
      required: ["service_order_id", "duration"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const minutos = parseMinutes(args.duration);
      if (!minutos) {
        return { error: `Não entendi a duração "${args.duration}". Diga como '2h', '1h30' ou '90min'.` };
      }
      const { data, error } = await sb.rpc("so_time_entry_add", {
        p_so_id: args.service_order_id,
        p_minutes: minutos,
        p_technician: args.technician_user_id ?? null,
        p_started_at: args.started_at ?? null,
        p_billable: args.billable !== false,
        p_notes: args.notes ?? null,
      });
      if (error) throw error;
      const horas = Math.floor(minutos / 60);
      const resto = minutos % 60;
      return {
        ok: true,
        apontado: horas ? `${horas}h${resto ? String(resto).padStart(2, "0") : ""}` : `${minutos}min`,
        minutos,
        registro_id: (data as any)?.id,
      };
    },
  },
  {
    name: "start_service_order_step",
    description:
      "Marca um passo do roteiro como EM ANDAMENTO ('comecei o passo 3', 'estou fazendo a isolação'). " +
      "Se outro passo estiver rodando, ele é pausado automaticamente e o tempo dele é somado — o relógio não fica correndo em dois lugares.",
    input_schema: {
      type: "object",
      properties: { step_id: { type: "string", description: "UUID do passo (de get_service_order_route)." } },
      required: ["step_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, status, service_order_id, service_orders(status)")
        .eq("id", args.step_id)
        .maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).service_orders?.status === "cancelled") {
        return { error: "Esta OS está cancelada — não dá para mexer no roteiro dela." };
      }
      if (step.status === "in_progress") return { ok: true, ja_em_andamento: true, passo: step.seq, titulo: step.title };

      const agora = new Date().toISOString();

      // Mesma pausa implícita da tela: fecha o trecho do passo que estava correndo,
      // somando ao acumulado, para o tempo não ser contado duas vezes.
      const { data: rodando } = await sb
        .from("service_order_steps")
        .select("id, actual_minutes, started_at")
        .eq("service_order_id", step.service_order_id)
        .eq("status", "in_progress")
        .neq("id", step.id);

      for (const outro of (rodando || []) as any[]) {
        const decorrido = outro.started_at
          ? Math.max(0, Math.round((Date.now() - new Date(outro.started_at).getTime()) / 60000))
          : 0;
        await sb.from("service_order_steps").update({
          status: "pending",
          actual_minutes: (outro.actual_minutes ?? 0) + decorrido,
          started_at: null,
        }).eq("id", outro.id);
      }

      const { error } = await sb.from("service_order_steps")
        .update({ status: "in_progress", started_at: agora })
        .eq("id", step.id);
      if (error) throw error;

      return {
        ok: true,
        passo: step.seq,
        titulo: step.title,
        ...(rodando?.length ? { pausei_tambem: rodando.length } : {}),
      };
    },
  },
  {
    name: "skip_service_order_step",
    description:
      "Marca um passo como NÃO SE APLICA, com o motivo ('esse passo não vale aqui porque o barco não tem esse sistema'). " +
      "Diferente de concluir: não foi feito, e não precisava ser. O motivo é obrigatório — é o que explica a lacuna depois.",
    input_schema: {
      type: "object",
      properties: {
        step_id: { type: "string" },
        reason: { type: "string", description: "Por que não se aplica. Vai para o histórico da OS." },
      },
      required: ["step_id", "reason"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const motivo = String(args.reason || "").trim();
      if (!motivo) return { error: "Diga por que o passo não se aplica — sem motivo isso vira buraco no histórico." };

      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, status, service_orders(status)")
        .eq("id", args.step_id)
        .maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).service_orders?.status === "cancelled") {
        return { error: "Esta OS está cancelada — não dá para mexer no roteiro dela." };
      }

      const { error } = await sb.from("service_order_steps").update({
        status: "not_applicable",
        na_reason: motivo,
        completed_at: new Date().toISOString(),
      }).eq("id", step.id);
      if (error) throw error;
      return { ok: true, passo: step.seq, titulo: step.title, motivo };
    },
  },
  {
    name: "reopen_service_order_step",
    description:
      "Volta um passo para PENDENTE ('reabre o passo 5', 'marquei errado, desfaz'). Zera o tempo e a conclusão registrados.",
    input_schema: {
      type: "object",
      properties: { step_id: { type: "string" } },
      required: ["step_id"],
    },
    risk: "medium",
    async execute(args, { sb }) {
      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, status, service_orders(status)")
        .eq("id", args.step_id)
        .maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).service_orders?.status === "cancelled") {
        return { error: "Esta OS está cancelada — não dá para mexer no roteiro dela." };
      }

      const { error } = await sb.from("service_order_steps").update({
        status: "pending",
        completed_at: null,
        actual_minutes: null,
        started_at: null,
        na_reason: null,
      }).eq("id", step.id);
      if (error) throw error;
      return { ok: true, passo: step.seq, titulo: step.title, estado: "pendente" };
    },
  },
  {
    name: "remove_service_order_hours",
    description:
      "Remove um apontamento de hora da OS e recalcula o total. Use com 'apaga aquela hora', 'apontei errado'. " +
      "O id vem de get_service_order.",
    input_schema: {
      type: "object",
      properties: { time_entry_id: { type: "string", description: "UUID do apontamento." } },
      required: ["time_entry_id"],
    },
    risk: "medium",
    async execute(args, { sb }) {
      const { data: entrada } = await sb
        .from("time_entries").select("id, service_order_id, duration_minutes")
        .eq("id", args.time_entry_id).maybeSingle();
      if (!entrada) return { error: "Apontamento não encontrado." };

      const { error } = await sb.from("time_entries").delete().eq("id", args.time_entry_id);
      if (error) throw error;
      // O total da OS conta hora cobrável — remover sem recalcular deixaria o valor
      // do serviço maior do que o trabalho registrado.
      await sb.rpc("recalc_so_totals", { so_id: (entrada as any).service_order_id });
      return { ok: true, minutos_removidos: (entrada as any).duration_minutes };
    },
  },
  {
    name: "add_service_order_step",
    description:
      "Acrescenta um passo ao roteiro da OS ('adiciona um passo de teste de estanqueidade no fim'). " +
      "Entra no fim da sequência, como passo MANUAL (não sugerido pela IA), já aprovado.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        title: { type: "string", description: "O que fazer, curto e no imperativo ('Testar estanqueidade')." },
        detail: { type: "string", description: "Detalhe/critério de aceite, se houver." },
        standard_minutes: { type: "number", description: "Tempo previsto em minutos." },
      },
      required: ["service_order_id", "title"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: ultimo } = await sb
        .from("service_order_steps").select("seq")
        .eq("service_order_id", args.service_order_id)
        .order("seq", { ascending: false }).limit(1);
      const seq = ((ultimo?.[0] as any)?.seq ?? 0) + 1;

      const { data, error } = await sb.from("service_order_steps").insert({
        origin: "manual",
        service_order_id: args.service_order_id,
        seq,
        title: args.title,
        detail: args.detail ?? null,
        standard_minutes: args.standard_minutes ?? null,
        status: "pending",
      }).select("id, seq, title").single();
      if (error) throw error;
      return { ok: true, passo: (data as any).seq, titulo: (data as any).title, id: (data as any).id };
    },
  },
  {
    name: "remove_service_order_step",
    description:
      "Exclui um passo do roteiro ('tira o passo 4, não faz sentido aqui'). " +
      "Se o passo JÁ FOI FEITO, prefira não excluir — o histórico da execução some junto; nesse caso use skip com o motivo.",
    input_schema: {
      type: "object",
      properties: { step_id: { type: "string" } },
      required: ["step_id"],
    },
    risk: "medium",
    async execute(args, { sb }) {
      const { data: step } = await sb
        .from("service_order_steps").select("id, seq, title, status")
        .eq("id", args.step_id).maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).status === "done") {
        return {
          error: `O passo ${(step as any).seq} já foi executado — excluir apagaria o registro do que foi feito. ` +
            `Se ele não deveria constar, reabra e marque como não aplicável, com o motivo.`,
        };
      }
      const { error } = await sb.from("service_order_steps").delete().eq("id", args.step_id);
      if (error) throw error;
      return { ok: true, removido: (step as any).seq, titulo: (step as any).title };
    },
  },
  {
    name: "reorder_service_order_step",
    description:
      "Troca a posição de um passo no roteiro ('sobe o passo 5', 'o teste tem que vir antes da montagem'). " +
      "Move uma posição por vez, para cima ou para baixo.",
    input_schema: {
      type: "object",
      properties: {
        step_id: { type: "string" },
        direction: { type: "string", enum: ["up", "down"], description: "up = executar antes; down = depois." },
      },
      required: ["step_id", "direction"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: alvo } = await sb
        .from("service_order_steps").select("id, seq, title, service_order_id")
        .eq("id", args.step_id).maybeSingle();
      if (!alvo) return { error: "Passo não encontrado." };

      const subindo = args.direction === "up";
      const { data: vizinhos } = await sb
        .from("service_order_steps")
        .select("id, seq, title")
        .eq("service_order_id", (alvo as any).service_order_id)
        [subindo ? "lt" : "gt"]("seq", (alvo as any).seq)
        .order("seq", { ascending: !subindo })
        .limit(1);

      const vizinho = vizinhos?.[0] as any;
      if (!vizinho) {
        return { ok: true, sem_mudanca: true, motivo: subindo ? "já é o primeiro" : "já é o último" };
      }

      // Troca direta das sequências: seq só tem restrição de unicidade no template,
      // não aqui — por isso não precisa de posição temporária.
      await sb.from("service_order_steps").update({ seq: vizinho.seq }).eq("id", (alvo as any).id);
      await sb.from("service_order_steps").update({ seq: (alvo as any).seq }).eq("id", vizinho.id);

      return { ok: true, passo: (alvo as any).title, nova_posicao: vizinho.seq, trocou_com: vizinho.title };
    },
  },
  {
    name: "review_ai_step",
    description:
      "Aprova ou descarta um passo que a IA rascunhou ('aprova esses passos', 'descarta o passo 3 que você sugeriu'). " +
      "Descartar APAGA o passo. Toda decisão vira registro de aprendizado — é assim que as sugestões melhoram.",
    input_schema: {
      type: "object",
      properties: {
        step_id: { type: "string" },
        verdict: { type: "string", enum: ["accepted", "edited", "rejected"], description: "accepted = como está; edited = a ideia servia mas o texto mudou; rejected = descartar." },
        change_summary: { type: "string", description: "Com 'edited', o que mudou — é o sinal mais útil para o aprendizado." },
      },
      required: ["step_id", "verdict"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, userId }) {
      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, detail, kind, standard_minutes, block")
        .eq("id", args.step_id).maybeSingle();
      if (!step) return { error: "Passo não encontrado." };

      const s = step as any;
      if (args.verdict === "rejected") {
        const { error } = await sb.from("service_order_steps").delete().eq("id", args.step_id);
        if (error) throw error;
      } else {
        const { error } = await sb.from("service_order_steps")
          .update({ approved_by: userId ?? null, approved_at: new Date().toISOString() })
          .eq("id", args.step_id);
        if (error) throw error;
      }

      await sb.from("ai_suggestion_reviews").insert({
        suggestion_type: "step",
        target_table: "service_order_steps",
        target_id: args.step_id,
        suggested: { title: s.title, detail: s.detail, kind: s.kind, standard_minutes: s.standard_minutes, block: s.block },
        approved: args.verdict === "rejected" ? null : { title: s.title, standard_minutes: s.standard_minutes },
        verdict: args.verdict,
        change_summary: args.change_summary ?? null,
        reviewer_id: userId ?? null,
      });

      return { ok: true, passo: s.seq, titulo: s.title, decisao: args.verdict };
    },
  },
  {
    name: "duplicate_service_order",
    description:
      "Duplica uma OS com todos os itens (peças, serviços), gerando um novo orçamento em rascunho. " +
      "Use quando disserem 'faz igual àquela', 'repete o orçamento do fulano para esse cliente'. " +
      "Não copia execução: o roteiro, as horas, as despesas e o histórico ficam na original.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS a duplicar." },
        client_id: { type: "string", description: "Cliente da cópia, se for para outro. Padrão: o mesmo." },
        vessel_id: { type: "string", description: "Embarcação/veículo da cópia, se mudar." },
      },
      required: ["service_order_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, admin }) {
      const { data: origem } = await sb
        .from("service_orders")
        .select("*")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!origem) return { error: "Ordem de serviço não encontrada." };

      // Numeração: mesmo esquema das demais criações (não-atômico, como o front).
      const { data: ultima } = await admin
        .from("service_orders").select("service_order_number")
        .order("created_at", { ascending: false }).limit(1);
      let seq = 1;
      const ref = ultima?.[0]?.service_order_number;
      if (ref) {
        const m = String(ref).match(/(\d+)$/);
        if (m) seq = parseInt(m[1], 10) + 1;
      }
      const numero = `ORÇ-${String(seq).padStart(5, "0")}`;

      const o = origem as any;
      const { data: nova, error: errNova } = await sb.from("service_orders").insert({
        service_order_number: numero,
        client_id: args.client_id || o.client_id,
        vessel_id: args.vessel_id || o.vessel_id,
        marina_id: o.marina_id,
        description: o.description,
        status: "draft",
        labor_cost_total: o.labor_cost_total,
        parts_cost_total: o.parts_cost_total,
        travel_cost_total: o.travel_cost_total,
        is_travel_billable: o.is_travel_billable,
        subcontract_cost_total: o.subcontract_cost_total,
        discount_amount: o.discount_amount,
        tax_amount: o.tax_amount,
        grand_total: o.grand_total,
      }).select("id, service_order_number").single();
      if (errNova) throw errNova;

      const novoId = (nova as any).id;

      const { data: pecas } = await sb.from("service_order_parts")
        .select("product_id, quantity, unit_cost_snapshot, line_total_cost, line_total_sale")
        .eq("service_order_id", args.service_order_id);
      if (pecas?.length) {
        await sb.from("service_order_parts").insert(
          (pecas as any[]).map((p) => ({ ...p, service_order_id: novoId })),
        );
      }

      const { data: servicos } = await sb.from("service_order_services")
        .select("service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total")
        .eq("service_order_id", args.service_order_id);
      if (servicos?.length) {
        await sb.from("service_order_services").insert(
          (servicos as any[]).map((s) => ({ ...s, service_order_id: novoId })),
        );
      }

      await sb.rpc("recalc_so_totals", { so_id: novoId });

      return {
        ok: true,
        nova_os_id: novoId,
        numero: (nova as any).service_order_number,
        copiados: { pecas: pecas?.length ?? 0, servicos: servicos?.length ?? 0 },
        aviso: "Criada em rascunho. Roteiro, horas e despesas NÃO são copiados.",
      };
    },
  },
];
