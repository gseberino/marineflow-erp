// Mensagem agendada pelo assistente (05/10/2026) — as regras que schedule_whatsapp_message aplica.
//
// Pedido do dono: "se depois do horário comercial eu lembrar de um contato, peço ao agente para
// mandar amanhã cedo — inclusive para quem ainda não está cadastrado, pelo número e pelo nome.
// Sempre com confirmação, para garantir que está tudo certo."
//
// O que estava errado antes:
//  · HORA: "2026-10-06T08:00:00" sem fuso era lida como UTC — saía às 05:00 em Brasília (o disparo,
//    whatsapp-process-scheduled, manda na hora gravada, sem olhar horário comercial);
//  · NÚMERO: só tirava os não-dígitos — "47 99915-9654" ia sem o 55;
//  · CONFIRMAÇÃO: mostrava os argumentos crus (ISO, número solto), não para quem e quando;
//  · CONTATO NOVO: não havia como dar nome a quem não está cadastrado.
import { normalizePhoneNumber } from "../../whatsapp/normalize.ts";
import { comFusoDeBrasilia } from "../fuso.ts";
import { chaveTelefone, mesmoTelefone } from "../phone.ts";

/** Janela em que se manda mensagem a terceiro (a mesma do portão de comunicação). */
export const JANELA_DE_ENVIO = { de: 8, ate: 20 } as const;

const BRASILIA_MS = 3 * 60 * 60 * 1000;
const DIAS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];

/** "terça, 06/10 às 08:00" no horário de Brasília. */
export function quandoPorExtenso(iso: string): string {
  const d = new Date(new Date(iso).getTime() - BRASILIA_MS);
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  return `${DIAS[d.getUTCDay()]}, ${dd}/${mm} às ${hh}:${mi}`;
}

/**
 * O horário do envio, em ISO com fuso. Sem fuso = Brasília (fuso.ts); só a data = 08:00. Recusa o
 * passado e fora da janela 8h–20h: a mensagem vai para outra pessoa, e o disparo não confere hora.
 */
export function horarioDoAgendamento(bruto: unknown, agora: Date = new Date()): { iso: string } | { error: string } {
  const comFuso = comFusoDeBrasilia(bruto);
  const ms = typeof comFuso === "string" ? new Date(comFuso).getTime() : NaN;
  if (!Number.isFinite(ms)) return { error: `Data/hora "${String(bruto ?? "")}" não entendida. Use AAAA-MM-DDTHH:MM (horário de Brasília).` };
  if (ms < agora.getTime() + 60_000) return { error: `${quandoPorExtenso(new Date(ms).toISOString())} já passou. Escolha um horário futuro.` };
  const horaBrasilia = new Date(ms - BRASILIA_MS);
  const minutos = horaBrasilia.getUTCHours() * 60 + horaBrasilia.getUTCMinutes();
  if (minutos < JANELA_DE_ENVIO.de * 60 || minutos > JANELA_DE_ENVIO.ate * 60) {
    return {
      error: `${quandoPorExtenso(new Date(ms).toISOString())} está fora do horário comercial (8h às 20h). Sugira 08:00 do próximo dia útil.`,
    };
  }
  return { iso: new Date(ms).toISOString() };
}

/** O número como o WhatsApp precisa (DDI + DDD + número); null = não dá para mandar. */
export function telefoneParaEnvio(bruto: unknown): string | null {
  const n = normalizePhoneNumber(String(bruto ?? ""));
  return n.length >= 12 && n.length <= 15 ? n : null;
}

/** "+55 (47) 99915-9654" — o número inteiro, para o dono conferir na confirmação. */
export function telefoneLegivel(digitos: string): string {
  if (/^55\d{11}$/.test(digitos)) return `+55 (${digitos.slice(2, 4)}) ${digitos.slice(4, 9)}-${digitos.slice(9)}`;
  if (/^55\d{10}$/.test(digitos)) return `+55 (${digitos.slice(2, 4)}) ${digitos.slice(4, 8)}-${digitos.slice(8)}`;
  return `+${digitos}`;
}

// ─── Pacote 1, S1 (24/11/2026): o número que VAI receber, por uma regra só ──────────────────────────────────────────
// Antes, com client_id E número nos argumentos, send_whatsapp_message mandava ao número dito e o cartão mostrava o do
// cadastro: o dono aprovaria (com PIN) um número e a mensagem iria a outro. E o agendamento, sem número no cadastro, caía
// calado no número dito, com o cartão dizendo "será recusado". Agora o cartão, o risco e o envio perguntam aqui:
//   · só o número: vale o número (normalizado);
//   · só client_id: vale o número do cadastro; cliente sem número ou que não existe = recusa clara;
//   · os dois: só passa se forem o MESMO número; diferentes = recusa que ensina (nunca escolher um dos dois calado).

/** O campo do número em cada ferramenta: to_phone (send_whatsapp_message) ou phone (schedule_whatsapp_message). */
export type CampoDoNumero = "to_phone" | "phone";

export type NumeroDoEnvio =
  | { ok: true; telefone: string; cliente: { id: string; nome: string | null } | null }
  | { ok: false; erro: string };

/**
 * O destino de uma mensagem de texto livre. `db` é quem lê o cadastro (o service-role no cartão e no risco; o cliente
 * do usuário no envio). Leitura que falha LANÇA: quem chama decide o lado seguro. `erro` é uma linha só, escrita para o
 * modelo corrigir o pedido.
 */
export async function numeroDoEnvio(
  // deno-lint-ignore no-explicit-any
  db: any,
  alvo: { client_id?: unknown; telefone?: unknown } | null | undefined,
  campo: CampoDoNumero,
): Promise<NumeroDoEnvio> {
  const nada = campo === "phone" ? "Nada foi agendado." : "Nada foi enviado.";
  const dito = String(alvo?.telefone ?? "").trim();
  // "Tem client_id" pela mesma conta do risco pelos argumentos, da validação e do cartão (`args?.client_id` verdadeiro):
  // os quatro têm de concordar, senão o cartão mostraria um destino e o envio usaria outro.
  if (!alvo?.client_id) {
    const telefone = telefoneParaEnvio(dito);
    if (telefone) return { ok: true, telefone, cliente: null };
    return { ok: false, erro: `Número "${dito}" inválido. ${nada} Peça o WhatsApp com DDD (ex.: 47 99915-9654).` };
  }
  const clientId = String(alvo.client_id).trim();
  const naoAchado: NumeroDoEnvio = {
    ok: false,
    erro: `Não achei cliente com o client_id "${clientId}" no cadastro. ${nada} Confira o id do cliente, ou mande só o ${campo} com o número.`,
  };
  if (!clientId) return naoAchado;
  const { data: c, error } = await db.from("clients").select("id, name, display_name, whatsapp, phone").eq("id", clientId).maybeSingle();
  if (error) {
    // 22P02 = o texto não é um uuid: não é falha do banco, é um id que não existe.
    if ((error as { code?: string }).code === "22P02") return naoAchado;
    throw new Error(`leitura do cliente falhou: ${(error as { message?: string }).message ?? "erro desconhecido"}`);
  }
  if (!c) return naoAchado;
  const nome = String(c.display_name || c.name || "").trim() || null;
  const doCadastro = telefoneParaEnvio(c.whatsapp || c.phone);
  if (!doCadastro) {
    return {
      ok: false,
      erro: `O cliente ${nome ?? "(sem nome)"} não tem WhatsApp nem telefone válido no cadastro. ${nada} ` +
        `Peça o número ao usuário e mande só o ${campo} (sem client_id), ou corrija o cadastro antes.`,
    };
  }
  if (dito && telefoneParaEnvio(dito) !== doCadastro) {
    return {
      ok: false,
      erro: `Vieram client_id e ${campo}, e eles apontam números diferentes: o cadastro de ${nome ?? "(sem nome)"} tem ` +
        `${telefoneLegivel(doCadastro)} e o ${campo} é "${dito}". ${nada} Mande só o client_id para usar o número do cadastro, ` +
        `ou só o ${campo} para mandar a outro número.`,
    };
  }
  return { ok: true, telefone: doCadastro, cliente: { id: String(c.id ?? clientId), nome } };
}

/** A frase da recusa quando nem dá para ler o cadastro do cliente: sem o número conferido, não há cartão. */
export const FALHA_AO_CONFERIR_O_DESTINO = "⚠️ Não consegui conferir o cadastro do cliente agora. Nada foi enviado nem agendado; tente de novo.";

/**
 * Para o cartão (resumirMensagem e resumirAgendamento): com client_id, o destino que não fecha vira uma linha "⚠️ …",
 * que o executor devolve ao modelo como recusa (RESUMO_QUE_RESOLVE em agent.ts), sem pendência. Sem client_id devolve
 * null: o número dito já foi conferido antes do cartão (preValidar) e o resumo segue como sempre. Nunca lança.
 */
export async function recusaDoDestino(
  // deno-lint-ignore no-explicit-any
  admin: any,
  alvo: { client_id?: unknown; telefone?: unknown } | null | undefined,
  campo: CampoDoNumero,
): Promise<string | null> {
  if (!alvo?.client_id) return null;
  try {
    const destino = await numeroDoEnvio(admin, alvo, campo);
    return destino.ok ? null : `⚠️ ${destino.erro}`;
  } catch {
    return FALHA_AO_CONFERIR_O_DESTINO;
  }
}

type Destino = { nome: string | null; origem: "cliente" | "conversa" | "novo"; telefone: string | null };

/**
 * O cliente do cadastro dono deste telefone, pelos últimos 8 dígitos (a régua do "esperando
 * resposta" e de phone.ts). O cadastro guarda o número como foi digitado ("+351 966…", "47 99915-9654"):
 * o filtro do banco usa os 4 últimos dígitos, que vêm juntos em qualquer formato (conferido nos 409
 * telefones de clientes em 15/10/2026), e a comparação certa é feita aqui.
 */
// deno-lint-ignore no-explicit-any
async function clientePeloTelefone(admin: any, telefone: string): Promise<{ name?: string | null; display_name?: string | null } | null> {
  const chave = chaveTelefone(telefone);
  if (!chave) return null;
  const fim = chave.slice(-4);
  const { data } = await admin
    .from("clients")
    .select("name, display_name, whatsapp, phone")
    .or(`whatsapp.ilike.%${fim}%,phone.ilike.%${fim}%`)
    .limit(50);
  // deno-lint-ignore no-explicit-any
  return ((data ?? []) as any[]).find((c) => mesmoTelefone(c.whatsapp, telefone) || mesmoTelefone(c.phone, telefone)) ?? null;
}

/**
 * Para quem vai: o cliente do cadastro, uma conversa que já existe, ou um contato novo.
 *
 * 15/10/2026: sem conversa em whatsapp_leads, procura o cliente pelo telefone e as mensagens do
 * número antes de dizer "novo". O Miguel (cliente do cadastro, 96 mensagens, nenhum lead) aparecia
 * na confirmação como "número que ainda não conversou com a HBR".
 */
// deno-lint-ignore no-explicit-any
export async function destinoDoAgendamento(admin: any, args: Record<string, unknown>): Promise<Destino> {
  if (args?.client_id) {
    const { data: c } = await admin.from("clients").select("name, display_name, whatsapp, phone").eq("id", args.client_id).maybeSingle();
    return { nome: c?.display_name || c?.name || null, origem: "cliente", telefone: telefoneParaEnvio(c?.whatsapp || c?.phone) };
  }
  const telefone = telefoneParaEnvio(args?.phone);
  if (!telefone) return { nome: null, origem: "novo", telefone: null };
  const { data: lead } = await admin.from("whatsapp_leads").select("name").eq("phone_normalized", telefone).maybeSingle();
  if (lead) return { nome: lead.name || (args?.contact_name as string) || null, origem: "conversa", telefone };
  const dito = String(args?.contact_name ?? "").trim() || null;
  const cliente = await clientePeloTelefone(admin, telefone);
  if (cliente) return { nome: cliente.display_name || cliente.name || dito, origem: "cliente", telefone };
  const { data: mensagens } = await admin.from("whatsapp_messages").select("id").eq("phone_normalized", telefone).limit(1);
  if (Array.isArray(mensagens) && mensagens.length > 0) return { nome: dito, origem: "conversa", telefone };
  return { nome: dito, origem: "novo", telefone };
}

/** O resumo da confirmação: para quem, o número inteiro, quando por extenso e a mensagem inteira. */
// deno-lint-ignore no-explicit-any
export async function resumirAgendamento(admin: any, args: Record<string, unknown>, agora: Date = new Date()): Promise<string> {
  // Pacote 1, S1: com client_id, o destino que não fecha (outro número junto, cliente sem número) é recusa, não cartão.
  const recusa = await recusaDoDestino(admin, { client_id: args?.client_id, telefone: args?.phone }, "phone");
  if (recusa) return recusa;
  const destino = await destinoDoAgendamento(admin, args);
  const hora = horarioDoAgendamento(args?.scheduled_at, agora);
  const quem = destino.origem === "cliente"
    ? `*${destino.nome || "cliente"}* (cliente do cadastro)`
    : destino.origem === "conversa"
    ? `*${destino.nome || "sem nome"}* (conversa que já existe no WhatsApp)`
    : `*${destino.nome || "sem nome"}* — contato NOVO, será cadastrado com este nome`;
  const linhas = [
    `Para: ${quem}`,
    destino.telefone ? `WhatsApp: ${telefoneLegivel(destino.telefone)}` : "WhatsApp: ⚠️ número inválido ou ausente — o agendamento será recusado",
    "error" in hora ? `Quando: ⚠️ ${hora.error}` : `Quando: *${quandoPorExtenso(hora.iso)}* (horário de Brasília)`,
  ];
  const rec = String(args?.recurrence_type ?? "once");
  if (rec !== "once") linhas.push(`Repete: ${rec === "daily" ? "todo dia" : rec === "weekly" ? "toda semana" : rec === "monthly" ? "todo mês" : rec}`);
  linhas.push(`Mensagem: "${String(args?.message ?? "").trim()}"`);
  return linhas.join("\n");
}

/**
 * Validação ANTES da pendência (preValidar): número, horário e mensagem. O dono não aprova algo
 * que vai falhar — e o resumo que ele lê é sobre o pedido já resolvido.
 */
export function validarAgendamento(args: Record<string, unknown> | null | undefined, agora: Date = new Date()): { error: string } | null {
  if (!String(args?.message ?? "").trim()) return { error: "A mensagem está vazia." };
  if (!args?.client_id) {
    if (!telefoneParaEnvio(args?.phone)) {
      return { error: `Número "${String(args?.phone ?? "")}" inválido. Peça o WhatsApp com DDD (ex.: 47 99915-9654).` };
    }
  }
  const hora = horarioDoAgendamento(args?.scheduled_at, agora);
  return "error" in hora ? hora : null;
}

/**
 * Contato novo: grava o nome na conversa do WhatsApp (whatsapp_leads), para a caixa de mensagens
 * mostrar quem é — e a resposta dele chegar identificada. Conversa existente sem nome ganha o nome;
 * com nome, não muda. Não cria cliente: isso é decisão do dono, depois de conversar.
 */
// deno-lint-ignore no-explicit-any
export async function cadastrarContatoDoAgendamento(admin: any, telefone: string, nome: string): Promise<"criado" | "nomeado" | "ja_tinha" | null> {
  const n = nome.trim();
  if (!n) return null;
  const { data: lead } = await admin.from("whatsapp_leads").select("id, name").eq("phone_normalized", telefone).maybeSingle();
  if (lead?.name) return "ja_tinha";
  if (lead) {
    await admin.from("whatsapp_leads").update({ name: n }).eq("id", lead.id);
    return "nomeado";
  }
  const { error } = await admin.from("whatsapp_leads").insert({
    phone_normalized: telefone,
    name: n,
    message_count: 0,
    notes: "Contato cadastrado pelo assistente para uma mensagem agendada.",
  });
  return error ? null : "criado";
}
