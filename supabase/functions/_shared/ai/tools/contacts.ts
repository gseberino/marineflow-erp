import type { ToolDef } from "./registry.ts";
import { chaveTelefone, padraoLikeTelefone } from "../phone.ts";

// Resolução de contato: de quem é este número? (Fase 3 · Etapa 2)
// Ver plans/marineflow-contexto-unificado-escopo.md
//
// Contexto medido: 96,7% das mensagens recebidas não tinham entidade vinculada. `client_id`
// já existia em whatsapp_messages; `supplier_id` foi adicionado (migration aditiva). Ensinar o
// vínculo UMA vez passa a valer também para as mensagens ANTERIORES daquele número.

type Achado = { tipo: "cliente" | "fornecedor" | "equipe"; id: string; nome: string; motivo: string };

/** Procura o dono do número em clientes, fornecedores e equipe. Pode achar mais de um. */
async function resolverTelefone(sb: any, telefone: string): Promise<Achado[]> {
  const chave = chaveTelefone(telefone);
  if (!chave) return [];
  const achados: Achado[] = [];

  const { data: clientes } = await sb.from("clients").select("id, name, phone, whatsapp").limit(2000);
  for (const c of (clientes as any[]) || []) {
    if (chaveTelefone(c.whatsapp) === chave || chaveTelefone(c.phone) === chave) {
      achados.push({ tipo: "cliente", id: c.id, nome: c.name, motivo: "telefone bate com o cadastro do cliente" });
    }
  }

  const { data: forns } = await sb.from("suppliers").select("id, name, phone").limit(2000);
  for (const f of (forns as any[]) || []) {
    if (chaveTelefone(f.phone) === chave) {
      achados.push({ tipo: "fornecedor", id: f.id, nome: f.name, motivo: "telefone bate com o cadastro do fornecedor" });
    }
  }

  const { data: users } = await sb.from("app_users").select("id, full_name, phone_normalized").eq("active", true).limit(200);
  for (const u of (users as any[]) || []) {
    if (chaveTelefone(u.phone_normalized) === chave) {
      achados.push({ tipo: "equipe", id: u.id, nome: u.full_name || "(sem nome)", motivo: "é um usuário do sistema" });
    }
  }
  return achados;
}

/** Resolve o telefone a partir de um message_id (quando o agente só tem a mensagem em mãos). */
async function telefoneDaMensagem(sb: any, messageId: string): Promise<string | null> {
  const { data } = await sb.from("whatsapp_messages").select("phone_normalized").eq("id", messageId).maybeSingle();
  return data?.phone_normalized || null;
}

export const contactTools: ToolDef[] = [
  {
    name: "identify_contact",
    description:
      "Descobre DE QUEM é um número de WhatsApp: cliente, fornecedor, alguém da equipe ou desconhecido. Informe phone OU message_id. Use quando chegar mensagem de um número que você não sabe de quem é, ou antes de registrar resposta de cotação. Se vier 'desconhecido', pergunte ao usuário e depois use link_contact_to_entity para ensinar.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone em qualquer formato." },
        message_id: { type: "string", description: "UUID de uma mensagem (alternativa ao phone)." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      let telefone: string | null = args.phone || null;
      if (!telefone && args.message_id) telefone = await telefoneDaMensagem(sb, args.message_id);
      if (!telefone) return { error: "Informe phone ou message_id." };

      const achados = await resolverTelefone(sb, telefone);
      const like = padraoLikeTelefone(telefone);

      // Vínculo já gravado nas mensagens desse número?
      let vinculoGravado: Record<string, unknown> | null = null;
      if (like) {
        const { data: m } = await sb
          .from("whatsapp_messages")
          .select("client_id, supplier_id")
          .like("phone_normalized", like)
          .or("client_id.not.is.null,supplier_id.not.is.null")
          .limit(1)
          .maybeSingle();
        if (m?.client_id || m?.supplier_id) {
          vinculoGravado = { client_id: m.client_id || null, supplier_id: m.supplier_id || null };
        }
      }

      if (achados.length === 0) {
        return {
          telefone,
          identificado: false,
          vinculo_gravado: vinculoGravado,
          mensagem: "Número não bate com nenhum cadastro. Pergunte ao usuário de quem é e use link_contact_to_entity para ensinar — vale também para as mensagens antigas desse número.",
        };
      }
      return {
        telefone,
        identificado: true,
        candidatos: achados,
        ambiguo: achados.length > 1,
        vinculo_gravado: vinculoGravado,
        nota: achados.length > 1 ? "Mais de um cadastro usa este número — confirme com o usuário qual é o correto." : null,
      };
    },
  },
  {
    name: "link_contact_to_entity",
    description:
      "ENSINA de quem é um número de WhatsApp, gravando o vínculo. Vale para as mensagens futuras E para as anteriores daquele número (por isso 'ensinar uma vez' resolve de vez). Informe client_id OU supplier_id. Use depois que o usuário disser de quem é o número.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone em qualquer formato." },
        message_id: { type: "string", description: "UUID de uma mensagem daquele número (alternativa ao phone)." },
        client_id: { type: "string", description: "UUID do cliente dono do número." },
        supplier_id: { type: "string", description: "UUID do fornecedor dono do número." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      let telefone: string | null = args.phone || null;
      if (!telefone && args.message_id) telefone = await telefoneDaMensagem(sb, args.message_id);
      if (!telefone) return { error: "Informe phone ou message_id." };
      if (!args.client_id && !args.supplier_id) return { error: "Informe client_id ou supplier_id — preciso saber de quem é." };
      if (args.client_id && args.supplier_id) return { error: "Informe apenas um: client_id OU supplier_id." };

      const like = padraoLikeTelefone(telefone);
      if (!like) return { error: "Telefone curto demais para casar mensagens." };

      let nome = "";
      if (args.client_id) {
        const { data: c } = await sb.from("clients").select("name").eq("id", args.client_id).maybeSingle();
        if (!c) return { error: "Cliente não encontrado." };
        nome = c.name;
      } else {
        const { data: f } = await sb.from("suppliers").select("name").eq("id", args.supplier_id).maybeSingle();
        if (!f) return { error: "Fornecedor não encontrado." };
        nome = f.name;
      }

      // Grava o vínculo em TODAS as mensagens daquele número (inclusive as antigas).
      const patch = args.client_id ? { client_id: args.client_id } : { supplier_id: args.supplier_id };
      const { data: atualizadas, error } = await sb
        .from("whatsapp_messages")
        .update(patch)
        .like("phone_normalized", like)
        .select("id");
      if (error) throw error;

      return {
        ok: true,
        telefone,
        vinculado_a: { tipo: args.client_id ? "cliente" : "fornecedor", nome },
        mensagens_atualizadas: (atualizadas as any[])?.length ?? 0,
        efeito: "Vale para as próximas mensagens e também para as anteriores desse número.",
      };
    },
  },
];
