import type { RiskLevel, ToolDef } from "./registry.ts";
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

/** O telefone e o WhatsApp do cliente: pelo assistente dá para trocar, não apagar. */
const NUMEROS_DE_CONTATO = ["phone", "whatsapp"] as const;

/** Número que veio vazio, nulo ou só com espaços: não é troca. (`undefined` é "não veio".) */
function numeroEmBranco(v: unknown): boolean {
  return v === null || (typeof v === "string" && v.trim() === "");
}

/** O que sobra do pedido para gravar: sem o que veio vazio ou nulo e sem o número de contato em branco. */
function camposParaGravar(campos: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(campos).filter(([c, v]) =>
    v !== undefined && v !== null && v !== "" && !((NUMEROS_DE_CONTATO as readonly string[]).includes(c) && numeroEmBranco(v))
  ));
}

/** O pedido que só apaga o telefone ou o WhatsApp (nada mais para gravar): recusa dita, no cartão e na execução. */
export const RECUSA_DE_APAGAR_CONTATO =
  "Telefone ou WhatsApp vazio: pelo assistente dá para trocar o número do cliente, mas não apagar (isso é na tela do cliente). Nada foi alterado.";

/**
 * O pedido de update_client como a execução o lê: sem o que veio vazio ou nulo, e no formato que a tela grava. O cartão
 * do "sim" (resumirTrocaDeContato) e o risco (riscoDeAtualizarCliente) usam a mesma leitura: o que o cartão mostra é o
 * que vai ser gravado.
 *
 * Telefone ou WhatsApp em branco (vazio, nulo ou SÓ ESPAÇOS) é descartado e o resto do pedido segue: o modelo costuma
 * mandar "" nos campos que não quer mudar. Só espaços entra na conta desde 24/11/2026 (acabamento da leva A,
 * NOVO-p1-s3-01): antes passava pelo filtro, formatarTelefone devolvia null e o número era APAGADO sem aviso. Quando o
 * número em branco é tudo o que o pedido traz, é um pedido de apagar: recusa dita (RECUSA_DE_APAGAR_CONTATO).
 */
function pedidoDeAtualizacao(
  args: unknown,
): { client_id: unknown; motivo: unknown; patch: Record<string, unknown> } | { error: string } {
  const { client_id, motivo, ...campos } = (args ?? {}) as Record<string, unknown>;
  const patch = camposParaGravar(campos);
  if (Object.keys(patch).length === 0) {
    const pediuApagar = NUMEROS_DE_CONTATO.some((c) => numeroEmBranco(campos[c]));
    return { error: pediuApagar ? RECUSA_DE_APAGAR_CONTATO : "Nada para atualizar — informe ao menos um campo." };
  }
  const recusa = normalizarCampos(patch);
  if (recusa) return recusa;
  return { client_id, motivo, patch };
}

/** Do que só o escritório muda, o que este pedido mudaria de fato: o que veio IGUAL ao gravado não é troca. */
function mudariaSoDoEscritorio(
  patch: Record<string, unknown>,
  antes: Record<string, unknown>,
): (keyof typeof SO_DO_ESCRITORIO)[] {
  return (Object.keys(SO_DO_ESCRITORIO) as (keyof typeof SO_DO_ESCRITORIO)[])
    .filter((c) => c in patch && !mesmoValorGravado(c, patch[c], antes[c]));
}

/** A recusa ao técnico que tenta mudar nome, CPF/CNPJ ou tipo: a mesma frase na execução e antes do cartão do "sim". */
function recusaAoTecnico(mudaria: (keyof typeof SO_DO_ESCRITORIO)[]): string {
  return `Só o escritório muda ${emLista(mudaria.map((c) => SO_DO_ESCRITORIO[c]))} de um cliente — peça ao escritório.`;
}

// ── Troca de contato pede o "sim" (pacote 1, S3, 24/11/2026) ───────────────────────────────────
//
// update_client rodava direto (risco low) e trocava telefone, WhatsApp e a marca de "não receber mensagens" sem o dono
// ver — e é para esse número que vão orçamento, cobrança e PDF. Tocou num dos três, o risco sobe para medium e o cartão
// mostra o antes e o depois. O resto do cadastro (e-mail, endereço, documento) segue como era.

/** Os argumentos que dizem para onde vão as mensagens do cliente. */
const CAMPOS_DE_CONTATO = ["phone", "whatsapp", "opt_out_whatsapp"] as const;

/**
 * O risco de update_client. TOTAL: executarChamadaDeTool (agent.ts) chama computeRisk fora de try, e uma exceção aqui
 * derrubaria o turno inteiro — por isso nada de `"phone" in args` (lança com args indefinido). O que não é objeto, ou
 * qualquer surpresa, devolve o risco mais alto do caso.
 *
 * Vale pelo que SOBRA do pedido, na mesma leitura da execução (camposParaGravar); só `undefined` é "não veio":
 *   · a marca de não receber mensagens, com qualquer valor (nulo e torto inclusive)  → medium;
 *   · telefone ou WhatsApp com número                                                → medium;
 *   · telefone ou WhatsApp em branco e NADA mais para gravar (o pedido de apagar)    → medium: não roda direto, e o
 *     cartão recusa (RECUSA_DE_APAGAR_CONTATO);
 *   · telefone ou WhatsApp em branco JUNTO de outro campo (acabamento da leva A, 24/11/2026): o número em branco é
 *     descartado, como a execução sempre fez, e vale o risco do que sobra (o e-mail sozinho roda direto). Na primeira
 *     versão do S3 o vazio contava e recusava o pedido inteiro, e o e-mail que vinha junto deixava de ser gravado.
 */
export function riscoDeAtualizarCliente(args: unknown): RiskLevel {
  try {
    if (args === null || typeof args !== "object" || Array.isArray(args)) return "medium";
    const { client_id: _cliente, motivo: _motivo, ...campos } = args as Record<string, unknown>;
    if (campos.opt_out_whatsapp !== undefined) return "medium";
    const numeros = NUMEROS_DE_CONTATO.filter((c) => campos[c] !== undefined);
    if (numeros.length === 0) return "low";
    if (numeros.some((c) => !numeroEmBranco(campos[c]))) return "medium";
    return Object.keys(camposParaGravar(campos)).length === 0 ? "medium" : "low";
  } catch {
    return "medium";
  }
}

/** Leitura do cliente que falha: o cartão não nasce (sem o antes, o "sim" seria às cegas). */
export const FALHA_AO_CONFERIR_O_CLIENTE = "⚠️ Não consegui conferir o cliente agora. Nada foi alterado; tente de novo.";

/**
 * O cartão do "sim" da troca de contato: o WhatsApp, o telefone e a marca de não receber mensagens, com o antes (lido
 * agora do cadastro) e o depois (o que a execução vai gravar, já no formato da tela).
 *
 * null = o pedido não mexe em contato: quem chamou usa o resumo genérico de sempre.
 * Linha "⚠️" = recusa, e a pendência não nasce (RESUMO_QUE_RESOLVE em agent.ts): leitura que falha, cliente que não
 * existe, o que a execução recusaria de qualquer jeito (técnico mudando nome, CPF/CNPJ ou tipo) e o pedido que SÓ apaga
 * o telefone ou o WhatsApp (vazio, nulo ou só espaço, sem mais nada para gravar). Apagar não é coisa do assistente: a
 * execução descarta o número em branco, então um cartão "→ —" pediria um "sim" sobre algo que não acontece. O risco
 * continua medium nesse caso (riscoDeAtualizarCliente): o pedido nunca roda direto.
 *
 * (Acabamento da leva A, 24/11/2026) O número em branco que vem JUNTO de outra coisa não recusa mais o pedido inteiro:
 * é descartado (pedidoDeAtualizacao) e o cartão mostra o que sobra. Com outro número ou a marca, é o cartão de sempre,
 * sem a linha do número em branco; só com campos que não são de contato, o risco é low e este resumo nem é chamado.
 *
 * `rotulo` vem de quem chama (rotuloDoCampo, agent.ts): os nomes dos outros campos são os mesmos do cartão genérico.
 */
export async function resumirTrocaDeContato(
  // deno-lint-ignore no-explicit-any
  admin: any,
  args: unknown,
  opts: { cargo?: string; rotulo?: (campo: string) => string } = {},
): Promise<string | null> {
  if (riscoDeAtualizarCliente(args) === "low") return null;
  if (args === null || typeof args !== "object" || Array.isArray(args)) return "⚠️ Nada para atualizar — informe ao menos um campo.";
  // O pedido que só apaga o número sai daqui como erro (RECUSA_DE_APAGAR_CONTATO), e a linha "⚠️" abaixo o recusa.
  const pedido = pedidoDeAtualizacao(args);
  if ("error" in pedido) return `⚠️ ${String(pedido.error).replace(/\s*\n+\s*/g, " ")}`;
  const { client_id, patch } = pedido;
  const tocados = CAMPOS_DE_CONTATO.filter((c) => c in patch);
  if (tocados.length === 0) return null;
  if ("opt_out_whatsapp" in patch && typeof patch.opt_out_whatsapp !== "boolean") {
    return "⚠️ Não entendi se o cliente quer ou não receber mensagens no WhatsApp: diga sim ou não. Nada foi alterado.";
  }

  if (typeof client_id !== "string" || !client_id.trim()) return "⚠️ Cliente não encontrado.";
  let antes: Record<string, unknown> | null;
  try {
    const { data, error } = await admin
      .from("clients").select("id, name, cpf_cnpj, type, phone, whatsapp, opt_out_whatsapp").eq("id", client_id).maybeSingle();
    if (error) return FALHA_AO_CONFERIR_O_CLIENTE;
    antes = data;
  } catch {
    return FALHA_AO_CONFERIR_O_CLIENTE;
  }
  if (!antes) return "⚠️ Cliente não encontrado.";

  // O técnico: o mesmo corte da execução. O que ela recusaria é recusa já aqui; o que veio igual ao gravado sai.
  if (opts.cargo === "technician") {
    const mudaria = mudariaSoDoEscritorio(patch, antes);
    if (mudaria.length) return `⚠️ ${recusaAoTecnico(mudaria)}`;
    for (const c of Object.keys(SO_DO_ESCRITORIO)) delete patch[c];
  }

  const texto = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : String(v));
  const simOuNao = (v: unknown) => (v === true ? "sim" : "não");
  const linhas = [`Trocar o contato do cliente *${texto(antes.name)}*:`];
  if ("whatsapp" in patch) linhas.push(`- WhatsApp: ${texto(antes.whatsapp)} → *${texto(patch.whatsapp)}*`);
  if ("phone" in patch) linhas.push(`- Telefone: ${texto(antes.phone)} → *${texto(patch.phone)}*`);
  if ("opt_out_whatsapp" in patch) {
    linhas.push(`- Não receber mensagens no WhatsApp: ${simOuNao(antes.opt_out_whatsapp)} → *${simOuNao(patch.opt_out_whatsapp)}*`);
  }
  const outros = Object.keys(patch).filter((c) => !(CAMPOS_DE_CONTATO as readonly string[]).includes(c));
  if (outros.length) linhas.push(`- Também muda: ${outros.map((c) => (opts.rotulo ? opts.rotulo(c) : c)).join(", ")}`);
  return linhas.join("\n");
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
    // S3 (24/11/2026): telefone, WhatsApp ou a marca de não receber mensagens pedem o "sim". O pedido que só apaga o
    // número também não roda direto (o cartão recusa); o número em branco junto de outro campo é descartado.
    computeRisk: riscoDeAtualizarCliente,
    async execute(args, { sb, userRole }) {
      const pedido = pedidoDeAtualizacao(args);
      if ("error" in pedido) return pedido;
      const { client_id, motivo, patch } = pedido;

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
        const mudaria = mudariaSoDoEscritorio(patch, antes);
        if (mudaria.length) {
          return {
            error: recusaAoTecnico(mudaria),
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
