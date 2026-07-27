import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Ferramentas do "vendedor autônomo" — curadoria e agendamento de Status/Stories.
// list_promo_candidates é read-only (risco baixo). schedule_status_post publica algo EXTERNO
// (status é visível aos contatos), então é risk "high": o sistema pede sua confirmação antes
// de efetivar — o agente nunca dispara um status real sozinho.
export const statusTools: ToolDef[] = [
  {
    name: "list_promo_candidates",
    description:
      "Lista os produtos com maior POTENCIAL DE PROMOÇÃO para postar no status do WhatsApp — ranqueados por disponível em estoque, margem, se têm foto e há quanto tempo estão parados. Use quando o dono perguntar 'o que promover?' ou para montar a programação de status. AVISA quais NÃO têm foto (sem foto não dá para postar imagem no status — peça a foto e anexe com update_product(image_url)).",
    input_schema: {
      type: "object",
      properties: { limit: { type: "number", description: "Quantos candidatos (padrão 8, teto 20)." } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const limit = Math.min(Number(args.limit) || 8, 20);
      const { data, error } = await ctx.sb.rpc("get_promo_candidates", { p_limit: limit });
      if (error) throw error;
      const rows = (data as any[]) || [];
      const semFoto = rows.filter((r) => !r.has_image).map((r) => r.name);
      return {
        candidatos: rows.map((r) => ({
          product_id: r.product_id,
          nome: r.name,
          sku: r.sku || null,
          preco: r.sale_price != null ? Number(r.sale_price) : null,
          margem_pct: r.margin_pct != null ? Number(r.margin_pct) : null,
          disponivel: Number(r.available),
          dias_parado: r.days_since_sold,
          tem_foto: !!r.has_image,
          image_url: r.image_url || null,
          score: Number(r.score),
        })),
        sem_foto: semFoto,
        instrucao: semFoto.length
          ? `${semFoto.length} candidato(s) SEM foto não viram status de imagem — peça a foto ao dono e anexe com update_product(image_url) antes de agendar.`
          : "Todos os candidatos têm foto — prontos para virar status.",
      };
    },
  },
  {
    name: "schedule_status_post",
    description:
      "Agenda a publicação de um STATUS/STORY do WhatsApp (promoção de produto, dica, vídeo, agenda livre da semana). O status é PÚBLICO aos contatos — não é mensagem privada nem lista de transmissão. Para promoção de produto use content_type='image' com a foto do produto e o texto com nome + preço. scheduled_at no futuro programa; sem ele, entra na próxima rodada do worker. Por ser divulgação externa, o sistema pede sua confirmação antes de efetivar.",
    input_schema: {
      type: "object",
      properties: {
        content_type: { type: "string", enum: ["text", "image", "video"], description: "text=aviso escrito; image/video=mídia com legenda." },
        text_content: { type: "string", description: "Texto do status (type=text) OU legenda (image/video)." },
        media_url: { type: "string", description: "URL da imagem/vídeo (obrigatório para image/video)." },
        scheduled_at: { type: "string", description: "ISO 8601 no fuso America/Sao_Paulo. Ausente = próxima rodada do worker." },
        background_color: { type: "string", description: "Cor de fundo (só type=text). Ex.: #0f6e78." },
      },
      required: ["content_type"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const ct = String(args.content_type);
      if ((ct === "image" || ct === "video") && !args.media_url) {
        return { error: "media_url é obrigatório para status de imagem/vídeo." };
      }
      if (ct === "text" && !args.text_content) {
        return { error: "text_content é obrigatório para status de texto." };
      }
      const row: Record<string, unknown> = {
        content_type: ct,
        text_content: args.text_content ?? null,
        media_url: args.media_url ?? null,
        background_color: args.background_color ?? null,
        scheduled_at: args.scheduled_at ?? new Date().toISOString(),
        status: "pending",
        created_by: ctx.userId ?? null,
      };
      const { data, error } = await ctx.sb
        .from("whatsapp_status_scheduled")
        .insert(row)
        .select("id, scheduled_at")
        .single();
      if (error) throw error;
      return {
        ok: true,
        status_id: (data as any).id,
        agendado_para: (data as any).scheduled_at,
        efeito: "Status agendado (pending). O worker publica no horário; até lá pode ser cancelado no painel.",
      };
    },
  },
];
