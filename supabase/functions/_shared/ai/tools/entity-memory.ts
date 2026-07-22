import { NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Memória por entidade (Fase 3 · Etapa 3) — ver plans/marineflow-contexto-unificado-escopo.md
//
// REGRA CENTRAL: o banco é dono do DADO; a memória guarda o CONHECIMENTO que o banco não tem
// ("sempre pede desconto", "só responde depois das 14h", "esse inversor já deu problema").
// Uma nota NUNCA contradiz o banco — se o dado mudou, o dado vence.
//
// Toda nota nasce como `candidate` (sugerida). Só nota `verified` é injetada no contexto.
// Aprovar é do dono — o agente não promove a própria memória.

import { ESCOPOS_DE_ENTIDADE as ESCOPOS, colunaDaEntidade } from "../memory-scope.ts";

export const entityMemoryTools: ToolDef[] = [
  {
    name: "remember_about_entity",
    description:
      "Guarda uma observação sobre um CLIENTE, ATIVO ou FORNECEDOR — o tipo de coisa que o cadastro não registra: preferências, acordos, padrões de comportamento ('sempre pede 10% de desconto', 'só responde depois das 14h', 'o inversor desse barco já deu problema duas vezes'). A nota nasce como SUGERIDA e só passa a valer depois que o usuário aprovar. NÃO use para dado que já está no sistema (valor, status, data) — isso o banco já sabe.",
    input_schema: {
      type: "object",
      properties: {
        scope: { type: "string", enum: ["client", "vessel", "supplier"], description: "Sobre o que é a nota." },
        entity_id: { type: "string", description: "UUID do cliente, ativo ou fornecedor." },
        title: { type: "string", description: "Resumo curto (ex.: 'Costuma pedir desconto')." },
        body: { type: "string", description: "A observação em si, com o contexto que a torna útil." },
        topic: { type: "string", description: "Assunto opcional para agrupar (ex.: 'negociação', 'manutenção')." },
        confidence: { type: "string", enum: ["low", "medium", "high"], description: "Quão seguro você está (padrão medium)." },
        from_user: { type: "boolean", description: "true se foi o próprio usuário que ditou a informação (registra a origem como humana)." },
      },
      required: ["scope", "entity_id", "title", "body"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, userId }) {
      const scope = String(args.scope || "");
      if (!(ESCOPOS as readonly string[]).includes(scope)) return { error: "scope deve ser client, vessel ou supplier." };
      const coluna = colunaDaEntidade(scope)!;

      // Confere que a entidade existe — nota órfã é ruído.
      const tabela = scope === "client" ? "clients" : scope === "vessel" ? "vessels" : "suppliers";
      const { data: ent } = await sb.from(tabela).select("id, name").eq("id", args.entity_id).maybeSingle();
      if (!ent) return { error: `Não encontrei esse ${scope === "client" ? "cliente" : scope === "vessel" ? "ativo" : "fornecedor"}.` };

      const { data, error } = await sb
        .from("ai_operator_memory_notes")
        .insert({
          scope,
          [coluna]: args.entity_id,
          title: String(args.title).slice(0, 200),
          body: String(args.body).slice(0, 2000),
          // `topic` é NOT NULL no schema — quando o usuário não classifica, cai em "geral"
          // em vez de estourar a inserção.
          topic: (args.topic && String(args.topic).trim()) || "geral",
          confidence: args.confidence || "medium",
          source: args.from_user ? "human" : "ai",
          verification_status: "candidate", // nasce sugerida — nunca como verdade
          created_by: userId ?? null,
        })
        .select("id, title")
        .single();
      if (error) throw error;

      return {
        ok: true,
        note_id: data.id,
        sobre: ent.name,
        status: "sugerida",
        aviso: "Anotei como SUGESTÃO. Ela só passa a influenciar minhas respostas depois que você aprovar (review_entity_note).",
      };
    },
  },
  {
    name: "list_entity_notes",
    description:
      "Lista o que já foi anotado sobre um cliente, ativo ou fornecedor — separando o que está aprovado do que ainda é sugestão aguardando sua decisão. Use para 'o que você sabe sobre o João?' ou antes de aprovar/rejeitar.",
    input_schema: {
      type: "object",
      properties: {
        scope: { type: "string", enum: ["client", "vessel", "supplier"] },
        entity_id: { type: "string", description: "UUID da entidade." },
      },
      required: ["scope", "entity_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      const coluna = colunaDaEntidade(String(args.scope));
      if (!coluna) return { error: "scope deve ser client, vessel ou supplier." };

      const { data, error } = await sb
        .from("ai_operator_memory_notes")
        .select("id, title, body, topic, confidence, source, verification_status, created_at")
        .eq(coluna, args.entity_id)
        .neq("verification_status", "rejected")
        .order("created_at", { ascending: false })
        .limit(30);
      if (error) throw error;

      const linhas = ((data as any[]) || []).map((n) => ({
        note_id: n.id, titulo: n.title, nota: n.body, assunto: n.topic,
        confianca: n.confidence, origem: n.source === "human" ? "você me disse" : "eu observei",
        quando: n.created_at,
      }));
      return {
        aprovadas: linhas.filter((_, i) => (data as any[])[i].verification_status === "verified"),
        aguardando_sua_aprovacao: linhas.filter((_, i) => (data as any[])[i].verification_status === "candidate"),
        nota: "Só as aprovadas entram no meu contexto automaticamente.",
      };
    },
  },
  {
    name: "review_entity_note",
    description:
      "APROVA ou REJEITA uma observação sugerida. Só chame quando o usuário disser explicitamente o que fazer ('pode guardar', 'isso está errado, apaga'). NUNCA aprove por conta própria — quem decide o que eu lembro é o dono.",
    input_schema: {
      type: "object",
      properties: {
        note_id: { type: "string", description: "UUID da nota (de list_entity_notes)." },
        decision: { type: "string", enum: ["approve", "reject"], description: "approve = passa a valer; reject = descartada." },
      },
      required: ["note_id", "decision"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, userId }) {
      const decisao = String(args.decision);
      if (decisao !== "approve" && decisao !== "reject") return { error: "decision deve ser approve ou reject." };

      const { data: nota } = await sb
        .from("ai_operator_memory_notes")
        .select("id, title, verification_status")
        .eq("id", args.note_id)
        .maybeSingle();
      if (!nota) return { error: "Nota não encontrada." };

      const agora = new Date().toISOString();
      const patch = decisao === "approve"
        ? { verification_status: "verified", verified_by: userId ?? null, verified_at: agora }
        : { verification_status: "rejected", rejected_by: userId ?? null, rejected_at: agora };

      const { error } = await sb.from("ai_operator_memory_notes").update(patch).eq("id", nota.id);
      if (error) throw error;

      return {
        ok: true,
        nota: nota.title,
        resultado: decisao === "approve" ? "aprovada — passa a valer nas próximas conversas" : "rejeitada — descartada",
      };
    },
  },
];
