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
  {
    name: "list_memory_notes",
    description:
      "Lista as notas de memória — a 'constituição viva': regras e preferências que você já aprendeu com o usuário. Use quando ele perguntar 'o que você já aprendeu?', 'quais suas regras?', 'o que você lembra sobre mim/a empresa?', ou antes de guardar uma lição parecida (evita duplicar).",
    input_schema: {
      type: "object",
      properties: { category: { type: "string", description: "Opcional: filtrar por categoria (topic)." } },
    },
    risk: "low",
    async execute(args, { admin }) {
      let q = admin
        .from("ai_operator_memory_notes")
        .select("id, topic, body, created_at")
        .order("created_at", { ascending: false })
        .limit(50);
      const cat = String(args.category || "").trim();
      if (cat) q = q.eq("topic", cat);
      const { data, error } = await q;
      if (error) return { error: error.message };
      return { count: data?.length ?? 0, notes: (data || []).map((n: any) => ({ id: n.id, categoria: n.topic, licao: n.body })) };
    },
  },
  {
    name: "forget_note",
    description:
      "Remove uma nota de memória errada/obsoleta (uma 'regra' que não vale mais). Use quando o usuário disser 'esquece isso', 'essa regra não vale mais', 'apaga o que você aprendeu sobre X'. Informe note_id (de list_memory_notes) OU um trecho do conteúdo para localizar.",
    input_schema: {
      type: "object",
      properties: {
        note_id: { type: "string", description: "UUID da nota (preferível)." },
        content_match: { type: "string", description: "Trecho do texto da nota, se não tiver o id." },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
      if (args.note_id) {
        const { error } = await admin.from("ai_operator_memory_notes").delete().eq("id", args.note_id);
        if (error) return { error: error.message };
        return { ok: true, removed_id: args.note_id };
      }
      const match = String(args.content_match || "").trim();
      if (!match) return { error: "Informe o note_id ou um trecho do conteúdo da nota." };
      const { data: found } = await admin
        .from("ai_operator_memory_notes")
        .select("id, body")
        .ilike("body", `%${match}%`)
        .limit(5);
      if (!found || found.length === 0) return { error: `Não encontrei nota com "${match}".` };
      if (found.length > 1) {
        return { precisa_desambiguar: true, opcoes: found.map((n: any) => ({ id: n.id, licao: String(n.body).slice(0, 80) })) };
      }
      const { error } = await admin.from("ai_operator_memory_notes").delete().eq("id", found[0].id);
      if (error) return { error: error.message };
      return { ok: true, removed_id: found[0].id, licao: String(found[0].body).slice(0, 80) };
    },
  },
];
