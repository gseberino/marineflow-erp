import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { chaveTelefone, padraoLikeTelefone, somenteDigitos } from "../phone.ts";
import { normalizePhoneNumber } from "../../whatsapp/normalize.ts";

// Resolução de contato: de quem é este número? (Fase 3 · Etapa 2)
// Ver plans/marineflow-contexto-unificado-escopo.md
//
// Contexto medido: 96,7% das mensagens recebidas não tinham entidade vinculada. `client_id`
// já existia em whatsapp_messages; `supplier_id` foi adicionado (migration aditiva). Ensinar o
// vínculo UMA vez passa a valer também para as mensagens ANTERIORES daquele número.

type Achado = { tipo: "cliente" | "fornecedor" | "equipe"; id: string; nome: string; motivo: string; ativo?: boolean };

/**
 * Procura o dono do número em clientes, fornecedores e equipe. Pode achar mais de um. Leitura com erro LANÇA: antes
 * virava "número desconhecido", e o modelo pedia ao dono para ensinar um número que já estava cadastrado.
 */
async function resolverTelefone(sb: any, telefone: string): Promise<Achado[]> {
  const chave = chaveTelefone(telefone);
  if (!chave) return [];
  const achados: Achado[] = [];

  const { data: clientes, error: erroClientes } = await sb.from("clients").select("id, name, phone, whatsapp, active").limit(2000);
  if (erroClientes) throw new Error(`Não consegui ler os clientes: ${erroClientes.message}`);
  for (const c of (clientes as any[]) || []) {
    if (chaveTelefone(c.whatsapp) === chave || chaveTelefone(c.phone) === chave) {
      achados.push({ tipo: "cliente", id: c.id, nome: c.name, motivo: "telefone bate com o cadastro do cliente", ativo: c.active !== false });
    }
  }

  const { data: forns, error: erroForns } = await sb.from("suppliers").select("id, name, phone").limit(2000);
  if (erroForns) throw new Error(`Não consegui ler os fornecedores: ${erroForns.message}`);
  for (const f of (forns as any[]) || []) {
    if (chaveTelefone(f.phone) === chave) {
      achados.push({ tipo: "fornecedor", id: f.id, nome: f.name, motivo: "telefone bate com o cadastro do fornecedor" });
    }
  }

  const { data: users, error: erroUsers } = await sb.from("app_users").select("id, full_name, phone_normalized").eq("active", true).limit(200);
  if (erroUsers) throw new Error(`Não consegui ler a equipe: ${erroUsers.message}`);
  for (const u of (users as any[]) || []) {
    if (chaveTelefone(u.phone_normalized) === chave) {
      achados.push({ tipo: "equipe", id: u.id, nome: u.full_name || "(sem nome)", motivo: "é um usuário do sistema" });
    }
  }
  return achados;
}

/**
 * As próximas mensagens do número chegam ligadas ao cadastro? Só se o número estiver nele (o webhook identifica o
 * cliente pelo telefone/whatsapp). Cadastro sem número nenhum: grava este (o pedido do dono é a confirmação).
 * Cadastro com OUTRO número: não troca ("vínculo sempre pergunta") e devolve a pergunta. Outro cliente com o mesmo
 * número: não grava — dois cadastros com o mesmo número deixam a chegada ambígua (quem_escreve não escolhe).
 */
async function numeroNoCadastro(
  sb: any,
  tabela: "clients" | "suppliers",
  cad: { id: string; phone?: string | null; whatsapp?: string | null },
  telefone: string,
  ehCliente: boolean,
): Promise<Record<string, unknown>> {
  const chave = chaveTelefone(telefone);
  const numeros = ehCliente ? [cad.whatsapp, cad.phone] : [cad.phone];
  const doFornecedor = ehCliente
    ? ""
    : " Atenção: na chegada o WhatsApp só reconhece CLIENTE; mensagens novas deste número são reconhecidas como do fornecedor pelo identify_contact, mas não ganham o fornecedor sozinhas.";

  if (ehCliente && chave) {
    const outros = (await resolverTelefone(sb, telefone)).filter((a) => a.tipo === "cliente" && a.ativo !== false && a.id !== cad.id);
    if (outros.length) {
      return {
        numero_no_cadastro: "nao_gravado",
        proximas_mensagens:
          `As mensagens antigas foram ligadas, mas o número também está no cadastro de ${outros.map((o) => o.nome).join(", ")}. ` +
          "Enquanto dois cadastros tiverem o mesmo número, as PRÓXIMAS mensagens chegam sem dono. Pergunte ao usuário de qual cadastro tirar o número.",
      };
    }
  }
  if (chave && numeros.some((n) => chaveTelefone(n) === chave)) {
    return { numero_no_cadastro: "ja_estava", proximas_mensagens: "O número já está no cadastro: as próximas mensagens chegam ligadas a ele." + doFornecedor };
  }
  if (numeros.some((n) => somenteDigitos(n).length > 0)) {
    return {
      numero_no_cadastro: "nao_trocado",
      numero_atual_no_cadastro: (ehCliente ? cad.whatsapp || cad.phone : cad.phone) ?? null,
      proximas_mensagens:
        "As mensagens antigas foram ligadas, mas o cadastro já tem OUTRO número e ele não foi trocado. As PRÓXIMAS mensagens deste número " +
        `só chegam ligadas se o número for trocado ou adicionado no cadastro. Pergunte ao usuário se quer trocar (${ehCliente ? "update_client" : "update_supplier"}).`,
    };
  }
  const campo = ehCliente ? "whatsapp" : "phone";
  const numero = normalizePhoneNumber(telefone);
  const { data: gravou, error } = await sb.from(tabela).update({ [campo]: numero }).eq("id", cad.id).select("id");
  if (error || !Array.isArray(gravou) || gravou.length === 0) {
    return {
      numero_no_cadastro: "falhou",
      proximas_mensagens:
        `As mensagens antigas foram ligadas, mas NÃO consegui gravar o número no cadastro (${error?.message ?? "sem permissão"}); ` +
        "as próximas mensagens chegam sem dono até o número estar no cadastro.",
    };
  }
  return {
    numero_no_cadastro: `gravado (${campo})`,
    proximas_mensagens: `O cadastro não tinha número: gravei ${numero} nele, e as próximas mensagens chegam ligadas.` + doFornecedor,
  };
}

/** Resolve o telefone a partir de um message_id (quando o agente só tem a mensagem em mãos). */
async function telefoneDaMensagem(sb: any, messageId: string): Promise<string | null> {
  const { data, error } = await sb.from("whatsapp_messages").select("phone_normalized").eq("id", messageId).maybeSingle();
  if (error) throw new Error(`Não consegui ler a mensagem: ${error.message}`);
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
      "ENSINA de quem é um número de WhatsApp: liga ao cadastro as mensagens ANTERIORES daquele número e, se o cadastro ainda não tem telefone nem WhatsApp, grava este número nele (é o que faz as PRÓXIMAS mensagens chegarem já ligadas). " +
      "Se o cadastro já tem OUTRO número, ele NÃO é trocado: a resposta diz isso — repita ao usuário e pergunte se quer trocar ou adicionar o número (update_client / update_supplier). Informe client_id OU supplier_id. Use depois que o usuário disser de quem é o número.",
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
    // Grava o vínculo e reatribui as mensagens antigas do número: não é tarefa do técnico. Sem
    // `roles` a tool ia a todo cargo, e desde 26/09/2026 ela está no perfil fixo do agente.
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      let telefone: string | null = args.phone || null;
      if (!telefone && args.message_id) telefone = await telefoneDaMensagem(sb, args.message_id);
      if (!telefone) return { error: "Informe phone ou message_id." };
      if (!args.client_id && !args.supplier_id) return { error: "Informe client_id ou supplier_id — preciso saber de quem é." };
      if (args.client_id && args.supplier_id) return { error: "Informe apenas um: client_id OU supplier_id." };

      const like = padraoLikeTelefone(telefone);
      if (!like) return { error: "Telefone curto demais para casar mensagens." };

      const ehCliente = !!args.client_id;
      const tabela = ehCliente ? "clients" : "suppliers";
      const { data: cad, error: erroCad } = await sb
        .from(tabela)
        .select(ehCliente ? "id, name, phone, whatsapp" : "id, name, phone")
        .eq("id", ehCliente ? args.client_id : args.supplier_id)
        .maybeSingle();
      if (erroCad) return { error: `Não consegui ler o cadastro (${erroCad.message}); nada foi vinculado.` };
      if (!cad) return { error: ehCliente ? "Cliente não encontrado." : "Fornecedor não encontrado." };
      const nome = cad.name;

      // Grava o vínculo em TODAS as mensagens daquele número (as antigas).
      const patch = ehCliente ? { client_id: args.client_id } : { supplier_id: args.supplier_id };
      const { data: atualizadas, error } = await sb
        .from("whatsapp_messages")
        .update(patch)
        .like("phone_normalized", like)
        .select("id");
      if (error) throw error;

      // As PRÓXIMAS mensagens: o webhook identifica o cliente pelo telefone/whatsapp do cadastro (whatsapp-webhook,
      // retorno_identificar → quem_escreve, ou o ILIKE em clients.phone/whatsapp). Antes a tool dizia "vale para as
      // próximas" sem mexer no cadastro — a próxima mensagem chegava sem dono de novo.
      const futuras = await numeroNoCadastro(sb, tabela, cad, telefone, ehCliente);

      return {
        ok: true,
        telefone,
        vinculado_a: { tipo: ehCliente ? "cliente" : "fornecedor", nome },
        mensagens_atualizadas: (atualizadas as any[])?.length ?? 0,
        ...futuras,
      };
    },
  },
];
