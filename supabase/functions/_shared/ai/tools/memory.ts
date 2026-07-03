import type { ToolDef } from "./registry.ts";

// Adaptado ao schema real de ai_operator_memory_notes (scope é vessel/client/global,
// não user/global como o plano original supunha — ver migration
// 20260703140000_ai_operator_tables.sql). Grava sempre scope='global' por enquanto
// (não há conceito de nota por-usuário no schema existente). verification_status vai
// direto para 'verified': um humano pediu explicitamente "lembre disso" na conversa,
// então já houve aprovação humana implícita — não faz sentido deixar como 'candidate'
// esperando uma revisão que não existe ainda (isso é trabalho de UI de fase futura).
export const memoryTools: ToolDef[] = [
  {
    name: "remember_note",
    description:
      "Grava uma nota permanente que o assistente deve lembrar em conversas futuras (ex: preferências da empresa, regras de negócio não documentadas em outro lugar). Use quando o usuário disser algo como 'lembre disso', 'sempre faça X', 'anote que...'.",
    input_schema: {
      type: "object",
      properties: {
        content: { type: "string", description: "O que lembrar, em texto claro e direto." },
        category: { type: "string", description: "Categoria curta para organizar a nota (ex: 'financeiro', 'atendimento', 'precos')." },
      },
      required: ["content", "category"],
    },
    risk: "low",
    async execute(args, { admin, userId }) {
      const body = String(args.content || "").trim();
      const topic = String(args.category || "geral").trim();
      const title = body.length > 60 ? `${body.slice(0, 57)}...` : body;
      const { data, error } = await admin
        .from("ai_operator_memory_notes")
        .insert({
          scope: "global",
          topic,
          title,
          body,
          source: "ai",
          verification_status: "verified",
          created_by: userId,
        })
        .select("id")
        .single();
      if (error) return { error: error.message };
      return { ok: true, note_id: data.id };
    },
  },
];
