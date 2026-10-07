import type { ToolDef } from "./registry.ts";
import { orContem } from "../filtro-or.ts";
import { formatarCep, formatarTelefone, lerTodosOsCadastros, notaDoCadastro, semAcento } from "../busca-cadastro.ts";
import { mesmoTelefone } from "../phone.ts";
import { ehErro } from "./caixa.ts";

// ── Marina (07/10/2026) ─────────────────────────────────────────────────────────────────────────
// Campos que a tela grava (src/components/MarinaFormDialog.tsx). create_marina só aceitava nome,
// contato, telefone, e-mail, cidade e UF, e não havia como EDITAR marina pelo assistente.
const CAMPOS_MARINA = {
  name: { type: "string" },
  contact_name: { type: "string", description: "Nome do contato na marina." },
  phone: { type: "string", description: "Telefone do contato." },
  email: { type: "string", description: "E-mail do contato." },
  postal_code: { type: "string", description: "CEP." },
  address_line_1: { type: "string", description: "Rua/logradouro (número e complemento à parte)." },
  address_number: { type: "string", description: "Número — só junto com a rua (address_line_1)." },
  address_complement: { type: "string", description: "Complemento — só junto com a rua (address_line_1)." },
  city: { type: "string" },
  state: { type: "string", description: "UF com 2 letras." },
  latitude: { type: "number" },
  longitude: { type: "number" },
  access_notes: { type: "string", description: "Notas de acesso (portaria, horário, onde estacionar...)." },
  billing_notes: { type: "string", description: "Notas de cobrança." },
} as const;

/**
 * Monta o que vai para `marinas` do jeito da tela: rua, número e complemento num campo só
 * (address_line_1 = "Rua X, 123, Sala 2" — a tabela não tem colunas separadas nem bairro),
 * telefone "(47) 99999-9999", CEP "88385-000", UF maiúscula. Só o que veio preenchido.
 */
function montarMarina(args: Record<string, unknown>): Record<string, unknown> | { error: string } {
  const m: Record<string, unknown> = {};
  for (const k of [...Object.keys(CAMPOS_MARINA), "active"]) {
    const v = args[k];
    if (v !== undefined && v !== null && v !== "") m[k] = typeof v === "string" ? v.trim() : v;
  }
  if ((m.address_number || m.address_complement) && !m.address_line_1) {
    return { error: "Diga a rua junto com o número/complemento — a marina guarda rua, número e complemento num campo só." };
  }
  if (m.address_line_1) m.address_line_1 = [m.address_line_1, m.address_number, m.address_complement].filter(Boolean).join(", ");
  delete m.address_number;
  delete m.address_complement;
  if (m.phone) m.phone = formatarTelefone(m.phone);
  if (m.postal_code) m.postal_code = formatarCep(m.postal_code);
  if (typeof m.state === "string") m.state = m.state.toUpperCase();
  return m;
}

// ── Contatos da embarcação (07/10/2026) ──────────────────────────────────────────────────────────
// Tabela vessel_contacts; tela: "Contatos da Embarcação" em src/components/VesselFormDialog.tsx
// (nome, função, telefone, e-mail). Mesmos rótulos de VESSEL_CONTACT_ROLES (use-vessel-contacts.ts).
const FUNCOES: Record<string, string> = {
  owner: "Proprietário",
  captain: "Comandante",
  sailor: "Marinheiro",
  manager: "Administrador",
  mechanic: "Mecânico responsável",
  contact: "Contato geral",
};
const FUNCAO_POR_PALAVRA: Record<string, string> = {
  proprietario: "owner", dono: "owner", armador: "owner",
  comandante: "captain", capitao: "captain", skipper: "captain",
  marinheiro: "sailor", marujo: "sailor",
  administrador: "manager", gerente: "manager", gestor: "manager",
  mecanico: "mechanic", "mecanico responsavel": "mechanic",
  contato: "contact", "contato geral": "contact", outro: "contact",
};

/** Função dita em português ou o código da tela → código gravado. Desconhecida = recusa. */
function traduzirFuncao(v: unknown): string | undefined | { error: string } {
  if (v === undefined || v === null || v === "") return undefined;
  const t = semAcento(v);
  if (FUNCOES[t]) return t;
  if (FUNCAO_POR_PALAVRA[t]) return FUNCAO_POR_PALAVRA[t];
  return { error: `Função "${String(v)}" não existe. Use: proprietário, comandante, marinheiro, administrador, mecânico ou contato geral.` };
}

const FUNCAO_DESC =
  "Função: proprietário, comandante, marinheiro, administrador, mecânico ou contato geral (padrão: contato geral).";

/** Contato no formato de resposta (com o id, para editar/remover depois). */
// deno-lint-ignore no-explicit-any
function contatoResumo(c: any) {
  return {
    contact_id: c.id,
    nome: c.full_name,
    funcao: FUNCOES[c.role] || c.role,
    telefone: c.phone || null,
    email: c.email || null,
    obs: c.notes || null,
  };
}

/** Contatos ativos de várias embarcações, agrupados por vessel_id. Erro LANÇA. */
// deno-lint-ignore no-explicit-any
export async function contatosDasEmbarcacoes(sb: any, vesselIds: string[]): Promise<Record<string, ReturnType<typeof contatoResumo>[]>> {
  const porEmbarcacao: Record<string, ReturnType<typeof contatoResumo>[]> = {};
  if (vesselIds.length === 0) return porEmbarcacao;
  const { data, error } = await sb
    .from("vessel_contacts")
    .select("id, vessel_id, full_name, role, phone, email, notes")
    .in("vessel_id", vesselIds)
    .eq("active", true)
    .order("full_name");
  if (error) throw error;
  for (const c of (data as any[]) || []) (porEmbarcacao[c.vessel_id] ??= []).push(contatoResumo(c));
  return porEmbarcacao;
}

export const vesselTools: ToolDef[] = [
  {
    name: "search_vessels",
    description: "Busca embarcações por nome/modelo. Pode filtrar por client_id.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" }, client_id: { type: "string" } },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      let query = sb
        .from("vessels")
        .select("id, name, manufacturer, model, year, client_id, marina_id")
        .eq("active", true)
        .or(orContem(["name", "model", "manufacturer"], q))
        .limit(15);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "get_vessel_history",
    description:
      "Retorna o histórico completo de serviços realizados em uma embarcação, os CONTATOS da embarcação (marinheiro, comandante... com o contact_id) e a marina onde ela fica (com o contato da marina). Use para 'quem é o marinheiro da Netuno?'.",
    input_schema: {
      type: "object",
      properties: { vessel_id: { type: "string" } },
      required: ["vessel_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(name)")
        .eq("vessel_id", args.vessel_id)
        .order("created_at", { ascending: false })
        .limit(30);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        cliente: so.clients?.name || "—",
        problema: so.problem_description || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));

      // Contatos e marina (07/10/2026): "quem é o contato da embarcação?" tinha de ser respondido
      // daqui. Leitura que falha lança — "sem contato" por erro levaria a cadastrar de novo.
      const { data: barco, error: barcoErr } = await sb
        .from("vessels")
        .select("id, name, marina_id, marinas(name, contact_name, phone)")
        .eq("id", args.vessel_id)
        .maybeSingle();
      if (barcoErr) throw barcoErr;
      const contatos = barco ? (await contatosDasEmbarcacoes(sb, [barco.id]))[barco.id] ?? [] : [];
      const marina = barco?.marinas
        ? { nome: barco.marinas.name, contato: barco.marinas.contact_name || null, telefone: barco.marinas.phone || null }
        : null;
      return { history: mapped, contatos, marina };
    },
  },
  {
    name: "list_marinas",
    description:
      "Lista marinas cadastradas (com contato e telefone). query busca por nome, cidade ou contato, sem precisar de acento. incluir_inativas=true para achar uma desativada (ex.: para reativar).",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string" },
        incluir_inativas: { type: "boolean" },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      // Poucas marinas (9 em 07/10/2026): lê todas e filtra sem acento — o ILIKE não achava
      // "Marina Itajaí" por "itajai".
      const todas = await lerTodosOsCadastros(
        sb,
        "marinas",
        "id, name, contact_name, phone, email, address_line_1, city, state, active",
        args.incluir_inativas === true ? {} : { active: true },
      );
      const results = (q ? todas.filter((m) => notaDoCadastro(m, q, { texto: ["name", "city", "contact_name"], telefone: ["phone"] }) > 0) : todas)
        .sort((a, b) => String(a.name ?? "").localeCompare(String(b.name ?? "")))
        .slice(0, 20);
      return { results };
    },
  },
  {
    name: "create_vessel",
    description: "Cadastra uma nova unidade/ativo (embarcação ou motorhome) para um cliente.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string" },
        name: { type: "string", description: "Nome da embarcação ou identificação do motorhome" },
        manufacturer: { type: "string" },
        model: { type: "string" },
        year: { type: "number" },
        asset_type: { type: "string", description: "Exemplo: Lancha, Veleiro, Motorhome, Camper, Jet Ski" },
        marina_id: { type: "string" },
      },
      required: ["client_id", "name", "asset_type"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("vessels").insert(args).select().single();
      if (error) throw error;
      return { ok: true, vessel: data };
    },
  },
  {
    name: "create_marina",
    description:
      "Cadastra uma nova marina com os mesmos campos da tela: contato, telefone, e-mail, endereço (rua, número, complemento, CEP, cidade, UF), notas de acesso e de cobrança. Se já existir marina com o mesmo nome, devolve a existente e você PERGUNTA — confirmar_duplicado=true só se o usuário disser que é outra.",
    input_schema: {
      type: "object",
      properties: {
        ...CAMPOS_MARINA,
        confirmar_duplicado: { type: "boolean", description: "true só depois que o usuário confirmou que é outra marina com o mesmo nome." },
      },
      required: ["name"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const dados = montarMarina(args as Record<string, unknown>);
      if (ehErro(dados)) return dados;
      if (!dados.name) return { error: "Informe o nome da marina." };
      const todas = await lerTodosOsCadastros(sb, "marinas", "id, name, city, active");
      const iguais = todas.filter((m) => semAcento(m.name) === semAcento(dados.name));
      if (iguais.length && args.confirmar_duplicado !== true) {
        return {
          ok: false,
          ja_cadastrada: iguais.map((m) => ({ marina_id: m.id, nome: m.name, cidade: m.city || null, ativa: m.active !== false })),
          pergunta: "Já existe marina com esse nome. É a mesma? Para mudar dados dela use update_marina.",
        };
      }
      const { data, error } = await sb.from("marinas").insert(dados).select().single();
      if (error) throw error;
      return { ok: true, marina: data };
    },
  },
  {
    name: "update_marina",
    description:
      "Edita uma marina (o que a tela de marina grava): nome, contato, telefone, e-mail, endereço (rua com número/complemento, CEP, cidade, UF), notas de acesso e de cobrança; active=false desativa, active=true reativa. Identifique pela marina (o nome ATUAL, como o usuário disse) ou marina_id. Ex.: 'atualiza o telefone da Marina Porto Belo' → marina='Porto Belo', phone=…. Só envie o que muda (name = nome NOVO).",
    input_schema: {
      type: "object",
      properties: {
        marina: { type: "string", description: "Nome atual da marina, como o usuário disse (ex.: 'Porto Belo')." },
        marina_id: { type: "string", description: "UUID da marina, se já souber." },
        ...CAMPOS_MARINA,
        active: { type: "boolean", description: "false = desativar, true = reativar (chave 'Ativo' da tela)." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      const patch = montarMarina(args as Record<string, unknown>);
      if (ehErro(patch)) return patch;
      if (Object.keys(patch).length === 0) return { error: "Nada para atualizar — informe ao menos um campo." };

      // IA pensa, sistema preenche: o dono diz o nome da marina; o id sai daqui. Só nome igual ou
      // contido (todas as palavras) identifica — mais de uma casando, devolve as opções.
      let id = String(args.marina_id ?? "").trim();
      if (!id) {
        const dito = String(args.marina ?? "").trim();
        if (!dito) return { error: "Diga qual marina (o nome dela) ou marina_id." };
        const todas = await lerTodosOsCadastros(sb, "marinas", "id, name, city, active");
        const casam = todas.filter((m) => notaDoCadastro(m, dito, { texto: ["name"] }) > 0);
        const exatas = casam.filter((m) => semAcento(m.name) === semAcento(dito) || semAcento(m.name) === semAcento(`marina ${dito}`));
        const escolha = exatas.length === 1 ? exatas : casam;
        if (escolha.length === 0) {
          return { error: `Nenhuma marina com o nome "${dito}".`, marinas_cadastradas: todas.map((m) => m.name) };
        }
        if (escolha.length > 1) {
          return {
            error: `Mais de uma marina casa com "${dito}" — qual delas?`,
            opcoes: escolha.map((m) => ({ marina_id: m.id, nome: m.name, cidade: m.city || null, ativa: m.active !== false })),
          };
        }
        id = String(escolha[0].id);
      }

      const { data: antes, error: lerErr } = await sb.from("marinas").select("*").eq("id", id).maybeSingle();
      if (lerErr) throw lerErr;
      if (!antes) return { error: "Marina não encontrada." };

      const { data, error } = await sb.from("marinas").update(patch).eq("id", id).select().single();
      if (error) throw error;
      const alterado: Record<string, unknown> = {};
      for (const k of Object.keys(patch)) alterado[k] = { de: antes[k] ?? null, para: data[k] ?? null };
      return { ok: true, marina: data.name, alterado };
    },
  },
  {
    name: "add_vessel_contact",
    description:
      "Adiciona um contato à embarcação (marinheiro, comandante, proprietário, administrador, mecânico) — o mesmo 'Contatos da Embarcação' da tela. Ex.: 'adiciona o marinheiro Carlos como contato da lancha Netuno, 47 9…'. Ache o vessel_id com search_vessels. Se a pessoa já é contato dessa embarcação (mesmo nome ou telefone), não duplica.",
    input_schema: {
      type: "object",
      properties: {
        vessel_id: { type: "string", description: "UUID da embarcação (search_vessels)." },
        full_name: { type: "string", description: "Nome do contato." },
        role: { type: "string", description: FUNCAO_DESC },
        phone: { type: "string" },
        email: { type: "string" },
        notes: { type: "string", description: "Observação (ex.: 'só atende de manhã')." },
      },
      required: ["vessel_id", "full_name"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const nome = String(args.full_name ?? "").trim();
      if (!nome) return { error: "Informe o nome do contato." };
      const funcao = traduzirFuncao(args.role);
      if (typeof funcao === "object") return funcao;

      const { data: barco, error: barcoErr } = await sb.from("vessels").select("id, name").eq("id", args.vessel_id).maybeSingle();
      if (barcoErr) throw barcoErr;
      if (!barco) return { error: "Embarcação não encontrada (use search_vessels)." };

      const telefone = formatarTelefone(args.phone);
      const atuais = (await contatosDasEmbarcacoes(sb, [barco.id]))[barco.id] ?? [];
      const mesmo = atuais.find((c) => semAcento(c.nome) === semAcento(nome) || (telefone && mesmoTelefone(telefone, c.telefone)));
      if (mesmo) {
        return {
          ok: false,
          ja_e_contato: mesmo,
          aviso: `${mesmo.nome} já é contato da ${barco.name}. Para mudar telefone/função use update_vessel_contact.`,
        };
      }

      const linha: Record<string, unknown> = { vessel_id: barco.id, full_name: nome, role: funcao ?? "contact" };
      if (telefone) linha.phone = telefone;
      if (String(args.email ?? "").trim()) linha.email = String(args.email).trim();
      if (String(args.notes ?? "").trim()) linha.notes = String(args.notes).trim();
      const { data, error } = await sb.from("vessel_contacts").insert(linha).select().single();
      if (error) throw error;
      return { ok: true, embarcacao: barco.name, contato: contatoResumo(data) };
    },
  },
  {
    name: "update_vessel_contact",
    description:
      "Corrige um contato da embarcação (nome, função, telefone, e-mail, observação) ou o REMOVE da lista (ativo=false; ativo=true devolve). O contact_id vem de get_vessel_history ou get_client_360.",
    input_schema: {
      type: "object",
      properties: {
        contact_id: { type: "string", description: "UUID do contato (get_vessel_history / get_client_360)." },
        full_name: { type: "string" },
        role: { type: "string", description: FUNCAO_DESC },
        phone: { type: "string" },
        email: { type: "string" },
        notes: { type: "string" },
        ativo: { type: "boolean", description: "false = remover da lista de contatos da embarcação; true = devolver." },
      },
      required: ["contact_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const patch: Record<string, unknown> = {};
      for (const k of ["full_name", "email", "notes"]) {
        if (String(args[k] ?? "").trim()) patch[k] = String(args[k]).trim();
      }
      if (String(args.phone ?? "").trim()) patch.phone = formatarTelefone(args.phone);
      const funcao = traduzirFuncao(args.role);
      if (typeof funcao === "object") return funcao;
      if (funcao) patch.role = funcao;
      // Remover = desativar, não apagar: a OS guarda quem pediu (service_orders.requested_by_contact_id
      // aponta para cá), e a tela só lista os ativos — some da lista sem quebrar o histórico.
      if (typeof args.ativo === "boolean") patch.active = args.ativo;
      if (Object.keys(patch).length === 0) return { error: "Nada para atualizar — informe ao menos um campo." };

      const { data: antes, error: lerErr } = await sb
        .from("vessel_contacts").select("id, vessel_id, full_name, role, phone, email, notes, active").eq("id", args.contact_id).maybeSingle();
      if (lerErr) throw lerErr;
      if (!antes) return { error: "Contato não encontrado." };

      const { data, error } = await sb.from("vessel_contacts").update(patch).eq("id", args.contact_id).select().single();
      if (error) throw error;
      return {
        ok: true,
        contato: contatoResumo(data),
        ...(patch.active === false ? { removido: true, nota: "Saiu da lista de contatos da embarcação (o histórico das OS continua)." } : {}),
        alterado: Object.keys(patch),
      };
    },
  },
];
