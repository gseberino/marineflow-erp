import type { ToolDef } from "./registry.ts";
import {
  buscarCadastro,
  digitosDoDocumento,
  formatarCep,
  formatarDocumento,
  formatarTelefone,
  lerTodosOsCadastros,
  semAcento,
  traduzirIndicadorIE,
} from "../busca-cadastro.ts";
import { mesmoTelefone } from "../phone.ts";

// Campos de endereço/fiscais aceitos no cadastro e na atualização do cliente.
// NÃO são cosméticos: sem documento e endereço completo a SEFAZ rejeita a NF-e — um cliente
// criado sem eles nasce impossível de faturar (era o que acontecia antes destes campos).
const CAMPOS_ENDERECO_FISCAL = {
  cpf_cnpj: { type: "string", description: "CPF ou CNPJ — OBRIGATÓRIO para emitir nota fiscal." },
  address_line_1: { type: "string", description: "Rua/logradouro — obrigatório para nota fiscal." },
  address_number: { type: "string", description: "Número." },
  address_complement: { type: "string", description: "Complemento (apto, bloco...)." },
  neighborhood: { type: "string", description: "Bairro." },
  city: { type: "string", description: "Cidade — obrigatório para nota fiscal." },
  state: { type: "string", description: "UF com 2 letras (ex.: SC) — obrigatório para nota fiscal." },
  postal_code: { type: "string", description: "CEP — obrigatório para nota fiscal." },
  state_registration: { type: "string", description: "Inscrição estadual (empresa)." },
  ie_indicator: { type: "string", description: "Indicador de IE: 'contribuinte' (1), 'isento' (2) ou 'não contribuinte' (9). Outro valor é recusado." },
  notes: { type: "string", description: "Observações livres (ex.: data de nascimento, referências)." },
} as const;

/** Diz o que ainda falta para o cliente poder receber nota fiscal. */
function pendenciasFiscais(c: Record<string, unknown>): string[] {
  const faltando: string[] = [];
  if (!c.cpf_cnpj) faltando.push("CPF/CNPJ");
  if (!c.address_line_1) faltando.push("rua");
  if (!c.city) faltando.push("cidade");
  if (!c.state) faltando.push("UF");
  if (!c.postal_code) faltando.push("CEP");
  return faltando;
}

/**
 * Deixa documento, telefone e indicador de IE no formato que a TELA grava (ClientFormDialog:
 * maskCPF/maskCNPJ/maskPhone, ie_indicator 1/2/9) — 07/10/2026. O assistente gravava como o modelo
 * escrevia ("47991455558", "+55 47 …", "isento"), o mesmo cliente aparecia em formatos diferentes,
 * e o CHECK chk_clients_ie_indicator recusava o "isento" com mensagem técnica.
 */
function normalizarCampos(patch: Record<string, unknown>): { error: string } | null {
  if ("cpf_cnpj" in patch) patch.cpf_cnpj = formatarDocumento(patch.cpf_cnpj);
  if ("phone" in patch) patch.phone = formatarTelefone(patch.phone);
  if ("whatsapp" in patch) patch.whatsapp = formatarTelefone(patch.whatsapp);
  if ("postal_code" in patch) patch.postal_code = formatarCep(patch.postal_code);
  if ("ie_indicator" in patch) {
    const ie = traduzirIndicadorIE(patch.ie_indicator);
    if (typeof ie === "object") return ie;
    if (ie === undefined) delete patch.ie_indicator;
    else patch.ie_indicator = ie;
  }
  return null;
}

/**
 * O que o técnico não muda num cliente já cadastrado (dono, 22/10/2026): o nome, o CPF/CNPJ e o
 * tipo (pessoa física/jurídica) — é quem o cliente é e em nome de quem sai a nota. Telefone,
 * e-mail e endereço ele continua podendo. A tela trava os mesmos campos e o banco recusa (gatilho
 * em clients), mas o assistente no WhatsApp grava com service_role, onde o gatilho não pega: a
 * porta, aqui, é a ferramenta.
 */
const SO_DO_ESCRITORIO: Record<"name" | "cpf_cnpj" | "type", string> = {
  name: "o nome",
  cpf_cnpj: "o CPF/CNPJ",
  type: "o tipo (pessoa física/jurídica)",
};

/** O valor pedido é o que já está gravado? CPF/CNPJ por dígitos, nome sem espaço nas pontas. */
function mesmoValorGravado(campo: string, pedido: unknown, gravado: unknown): boolean {
  if (campo === "cpf_cnpj") {
    const d = digitosDoDocumento(pedido);
    return d.length > 0 && d === digitosDoDocumento(gravado);
  }
  if (campo === "name") return String(pedido ?? "").trim() === String(gravado ?? "").trim();
  return pedido === gravado;
}

/** "o nome", "o nome e o CPF/CNPJ", "o nome, o CPF/CNPJ e o tipo (…)". */
function emLista(itens: string[]): string {
  return itens.length <= 1 ? (itens[0] ?? "") : `${itens.slice(0, -1).join(", ")} e ${itens[itens.length - 1]}`;
}

const COLUNAS_DUPLICADO = "id, name, cpf_cnpj, phone, whatsapp, city, active";

/** Resumo de um cliente para o dono reconhecer quem é. */
function quem(c: Record<string, unknown>) {
  return {
    client_id: c.id,
    nome: c.name,
    documento: c.cpf_cnpj || null,
    telefone: c.whatsapp || c.phone || null,
    cidade: c.city || null,
    ativo: c.active !== false,
  };
}

/**
 * Procura quem já está cadastrado com o mesmo documento (dígitos), o mesmo telefone (8 dígitos
 * finais, regra de phone.ts) ou o MESMO nome (sem acento). Caso real: "Flávio da Igreja" criado
 * duas vezes com o mesmo CPF. Inclui inativos — o caminho certo pode ser reativar.
 */
// deno-lint-ignore no-explicit-any
async function procurarDuplicados(sb: any, dados: Record<string, unknown>, excetoId?: string) {
  const todos = await lerTodosOsCadastros(sb, "clients", COLUNAS_DUPLICADO);
  const doc = digitosDoDocumento(dados.cpf_cnpj);
  const fones = [dados.phone, dados.whatsapp].filter(Boolean) as string[];
  const nome = semAcento(dados.name);
  const mesmoDocumento: Record<string, unknown>[] = [];
  const parecidos: { c: Record<string, unknown>; motivo: string }[] = [];
  for (const c of todos) {
    if (excetoId && c.id === excetoId) continue;
    if (doc.length >= 11 && digitosDoDocumento(c.cpf_cnpj) === doc) {
      mesmoDocumento.push(c);
      continue;
    }
    if (fones.some((f) => mesmoTelefone(f, c.phone as string) || mesmoTelefone(f, c.whatsapp as string))) {
      parecidos.push({ c, motivo: "mesmo telefone" });
    } else if (nome && semAcento(c.name) === nome) {
      parecidos.push({ c, motivo: "mesmo nome" });
    }
  }
  return { mesmoDocumento, parecidos };
}

export const clientTools: ToolDef[] = [
  {
    name: "search_clients",
    description:
      "Busca clientes por nome (sem precisar de acento: 'Joao' acha 'João'; todas as palavras, em qualquer ordem), e-mail, telefone ou CPF/CNPJ (com ou sem pontos/traço; telefone com ou sem DDD/+55). Por padrão só ativos; incluir_inativos=true para achar quem foi inativado (ex.: para reativar).",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string" },
        limit: { type: "number" },
        incluir_inativos: { type: "boolean", description: "true = inclui clientes inativos (para reativar ou conferir)." },
      },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      // Busca com termo vazio/genérico devolveria "qualquer cliente" e induz escolha errada.
      if (q.length < 2) return { error: "Termo de busca muito curto. Diga o nome (ou parte dele) do cliente." };
      const limit = Math.min(Number(args.limit) || 10, 25);
      // Sem acento e por dígitos (busca-cadastro.ts): o ILIKE de antes não achava "João" por "Joao"
      // nem o CPF "508.421.889-91" por "50842188991" (auditoria de 06/10/2026).
      const data = await buscarCadastro(
        sb,
        "clients",
        "id, name, display_name, type, phone, whatsapp, email, cpf_cnpj, active",
        q,
        { texto: ["name", "display_name", "email"], documento: ["cpf_cnpj"], telefone: ["phone", "whatsapp"] },
        { limite: limit, iguais: args.incluir_inativos === true ? {} : { active: true } },
      );
      return { results: data };
    },
  },
  {
    name: "create_client",
    description:
      "Cadastra um novo cliente. Se o usuário forneceu endereço, CPF/CNPJ ou CEP, GRAVE TUDO — esses campos são o que permite emitir nota fiscal depois. A resposta avisa se ficou faltando algo para faturamento. ANTES de criar, o sistema procura duplicado: mesmo CPF/CNPJ nunca cria de novo (devolve o existente); mesmo telefone ou mesmo nome devolve o existente e você PERGUNTA ao usuário — só chame de novo com confirmar_duplicado=true se ele disser que é outra pessoa.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        type: { type: "string", enum: ["individual", "company"] },
        phone: { type: "string" },
        whatsapp: { type: "string" },
        email: { type: "string" },
        ...CAMPOS_ENDERECO_FISCAL,
        confirmar_duplicado: {
          type: "boolean",
          description: "true SÓ depois que o usuário disse que é outra pessoa com o mesmo telefone/nome. Não vale para CPF/CNPJ igual.",
        },
      },
      required: ["name", "type"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { confirmar_duplicado, ...campos } = args as Record<string, unknown>;
      const dados = Object.fromEntries(Object.entries(campos).filter(([, v]) => v !== undefined && v !== null && v !== ""));
      const recusa = normalizarCampos(dados);
      if (recusa) return recusa;

      // Duplicado ANTES de inserir (07/10/2026). Leitura que falha lança: "ninguém com esse CPF"
      // por erro de leitura era exatamente como a duplicata nascia.
      const { mesmoDocumento, parecidos } = await procurarDuplicados(sb, dados);
      if (mesmoDocumento.length) {
        return {
          ok: false,
          ja_cadastrado: mesmoDocumento.map(quem),
          aviso: `Já existe cliente com o CPF/CNPJ ${dados.cpf_cnpj} — não cadastrei de novo. Use o existente` +
            (mesmoDocumento.some((c) => c.active === false) ? " (está INATIVO: reative com update_client active=true)" : "") +
            " ou pergunte ao usuário se o documento está certo.",
        };
      }
      if (parecidos.length && confirmar_duplicado !== true) {
        return {
          ok: false,
          possiveis_duplicados: parecidos.map((p) => ({ ...quem(p.c), motivo: p.motivo })),
          pergunta: "Já existe cliente com o mesmo telefone ou nome. É a mesma pessoa? Se for, use o cadastro existente; se for outra pessoa, confirme e eu cadastro.",
        };
      }

      const { data, error } = await sb.from("clients").insert(dados).select().single();
      if (error) throw error;
      const faltando = pendenciasFiscais(data);
      return {
        ok: true,
        client: data,
        pronto_para_nota_fiscal: faltando.length === 0,
        falta_para_faturar: faltando.length ? faltando : null,
        aviso: faltando.length
          ? `Cadastrado, mas ainda falta ${faltando.join(", ")} para conseguir emitir nota fiscal para ele.`
          : null,
      };
    },
  },
  {
    name: "update_client",
    description:
      "Atualiza dados de um cliente já cadastrado — especialmente para COMPLETAR o que falta para emitir nota fiscal (CPF/CNPJ, rua, cidade, UF, CEP). Também INATIVA ('inativa o cliente José, vendeu o barco' → active=false e o porquê em motivo) e REATIVA (active=true; ache-o com search_clients incluir_inativos=true), e troca pessoa física/jurídica (type). Só envie os campos que quer mudar.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "UUID do cliente." },
        name: { type: "string" },
        type: { type: "string", enum: ["individual", "company"], description: "individual = pessoa física, company = pessoa jurídica." },
        active: { type: "boolean", description: "false = inativar (some das buscas e listas), true = reativar. Mesma chave 'Ativo' da tela." },
        motivo: { type: "string", description: "Por que inativou/reativou (ex.: 'vendeu o barco') — vai para as observações, com a data." },
        phone: { type: "string" },
        whatsapp: { type: "string" },
        email: { type: "string" },
        display_name: { type: "string", description: "Nome usado na comunicação (fantasia/primeiro nome) — preferido na saudação." },
        communication_tone: { type: "string", description: "Tom preferido na comunicação (ex.: formal, informal)." },
        opt_out_whatsapp: { type: "boolean", description: "true = o cliente NÃO quer mais receber mensagens no WhatsApp (bloqueia envios)." },
        ...CAMPOS_ENDERECO_FISCAL,
      },
      required: ["client_id"],
    },
    risk: "low",
    async execute(args, { sb, userRole }) {
      const { client_id, motivo, ...campos } = args as Record<string, unknown>;
      const patch = Object.fromEntries(Object.entries(campos).filter(([, v]) => v !== undefined && v !== null && v !== ""));
      if (Object.keys(patch).length === 0) return { error: "Nada para atualizar — informe ao menos um campo." };
      const recusa = normalizarCampos(patch);
      if (recusa) return recusa;

      const { data: antes, error: lerErr } = await sb
        .from("clients").select("id, name, cpf_cnpj, type, active, notes").eq("id", client_id).maybeSingle();
      if (lerErr) throw lerErr;
      if (!antes) return { error: "Cliente não encontrado." };

      // Técnico (22/10/2026): nome, CPF/CNPJ e tipo só pelo escritório — inclusive preencher o que
      // estava vazio, como o gatilho do banco. Recusa o pedido inteiro (nada gravado pela metade).
      // O que veio IGUAL ao gravado não é troca: o modelo costuma repetir o nome ao mudar o
      // telefone; sai do patch para não regravar (o CPF sem máscara viraria "outro" valor).
      if (userRole === "technician") {
        const protegidos = Object.keys(SO_DO_ESCRITORIO) as (keyof typeof SO_DO_ESCRITORIO)[];
        const mudaria = protegidos.filter((c) => c in patch && !mesmoValorGravado(c, patch[c], antes[c]));
        if (mudaria.length) {
          return {
            error: `Só o escritório muda ${emLista(mudaria.map((c) => SO_DO_ESCRITORIO[c]))} de um cliente — peça ao escritório.`,
            nada_gravado: true,
            tecnico_pode_mudar: "telefone, WhatsApp, e-mail e endereço (mande de novo só com esses campos)",
          };
        }
        for (const c of protegidos) delete patch[c];
        if (Object.keys(patch).length === 0) {
          return { ok: true, cliente: antes.name, atualizado: [], aviso: "Nada mudou: o que veio já era o que está no cadastro." };
        }
      }

      // CPF/CNPJ que já é de OUTRO cliente: gravar criaria a duplicata por outro caminho.
      if (patch.cpf_cnpj) {
        const { mesmoDocumento } = await procurarDuplicados(sb, { cpf_cnpj: patch.cpf_cnpj }, String(client_id));
        if (mesmoDocumento.length) {
          return { error: `O CPF/CNPJ ${patch.cpf_cnpj} já é de outro cliente — não gravei.`, ja_cadastrado: mesmoDocumento.map(quem) };
        }
      }

      // A tela só liga/desliga "Ativo"; o motivo que o dono falou não pode se perder — vai para as
      // observações, ACRESCENTADO (nunca por cima do que já estava), com a data (07/10/2026).
      if (typeof patch.active === "boolean" && patch.active !== antes.active && String(motivo ?? "").trim()) {
        const dia = new Date().toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
        const linha = `[${dia}] ${patch.active ? "Reativado" : "Inativado"}: ${String(motivo).trim()}`;
        const base = typeof patch.notes === "string" ? patch.notes : (antes.notes as string | null);
        patch.notes = base ? `${base}\n${linha}` : linha;
      }

      const { data, error } = await sb.from("clients").update(patch).eq("id", client_id).select().single();
      if (error) throw error;
      const faltando = pendenciasFiscais(data);
      return {
        ok: true,
        cliente: data.name,
        atualizado: Object.keys(patch),
        ...(typeof patch.active === "boolean"
          ? { situacao: data.active ? "ativo" : "inativo — some das buscas (search_clients com incluir_inativos=true acha)" }
          : {}),
        pronto_para_nota_fiscal: faltando.length === 0,
        falta_para_faturar: faltando.length ? faltando : null,
      };
    },
  },
];
