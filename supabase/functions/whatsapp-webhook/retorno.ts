// Retorno rápido ao cliente, F1 (P13; sobe no pacote F0b-1 de 10/11/2026): o que o whatsapp-webhook fala com o
// retorno. São duas chamadas ao banco, e nenhuma derruba nem atrasa o webhook.
//
// 1. Identificação nova (F0b-1). Hoje o webhook acha o cliente por `phone ILIKE %fone%` + maybeSingle: telefone
//    gravado sem o 55 ou com máscara, ou o mesmo número em dois cadastros, e o cliente vira lead (4 de 22 números
//    de cliente reconhecidos em 90 dias). retorno_identificar (P1) usa quem_escreve (F0b): a chave de 8 dígitos e o
//    DDD, sem genérico nem inativo, e nunca escolhe entre dois clientes. Fica atrás do interruptor
//    retorno_config.identificacao_nova (nasce false, liga em 11/11 com OK). Desligado, sem a função ou com erro, o
//    webhook faz o ILIKE de sempre. Ligado e ambíguo (ou equipe, fornecedor, número novo), o cliente é nulo.
//
// 2. Abertura do caso (retorno_abrir, P5). Depois de gravar a recebida e de os leitores de hoje terminarem, o
//    webhook chama retorno_abrir com "consumida" = a confirmação do agendamento, a conferência do recibo de diárias
//    ou a resposta à revisão ficou com a mensagem. A equipe e a agenda são aguardadas no caminho principal, como
//    hoje; as três RPCs, só aqui, no fundo. A agenda NÃO entra no booleano: agenda_resposta_do_cliente diz
//    consumiu também quando levou o caso ao dono (ao_dono, ambigua), e o retorno lê o efeito final dela em
//    agenda_cliente_respostas. A equipe também não: retorno_abrir já a ignora pelo quem_escreve.
//    Tudo roda dentro do waitUntil (noFundo): a resposta à Evolution não espera. A função ausente (o webhook pode
//    subir antes das migrations da F1) é silêncio; outro erro é um console.warn só com o código, nunca com
//    telefone ou texto.
//
// Este arquivo não importa _shared/ai/ nem _shared/agenda/ (congelados).
//
// Reverter: em index.ts, a identificação volta ao ILIKE de sempre, o noFundo(abrirNoRetorno(...)) sai e os três
// leitores voltam a `.then(() => {}, () => {})`; depois, apagar este arquivo e retorno_test.ts.

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_IDENTIFICAR = "retorno_identificar";
export const RPC_ABRIR = "retorno_abrir";

/** A resposta à revisão que fica com a mensagem (registrar_resposta_da_revisao → {registrou, intencao}). "outro" não. */
const INTENCOES_DA_REVISAO_QUE_CONSOMEM = new Set(["sim", "data", "parar"]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha): o mesmo teste da agenda. */
function funcaoAusente(e: unknown): boolean {
  const code = String((e as { code?: unknown } | null | undefined)?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

/** Só o código do erro (ou o nome da exceção), para o log: nunca a mensagem, que pode trazer telefone ou texto. */
function codigoDoErro(e: unknown): string {
  const obj = e as { code?: unknown; name?: unknown } | null | undefined;
  for (const c of [obj?.code, obj?.name]) {
    if (typeof c === "string" && /^[A-Za-z0-9_-]{1,32}$/.test(c)) return c;
  }
  return "erro";
}

function campo(v: unknown, nome: string): unknown {
  return v !== null && typeof v === "object" ? (v as Record<string, unknown>)[nome] : undefined;
}

export type Identificacao = { usar: boolean; clientId: string | null };

/**
 * A identificação nova do cliente (contrato C-IDENT). `usar: false` = o webhook faz o ILIKE de hoje (interruptor
 * desligado, função ausente, erro, resposta estranha). `usar: true` = vale o que o banco disse, e o cliente só vem
 * quando o papel é "cliente", com um cliente só e um uuid válido: ambíguo nunca escolhe cliente. Nunca lança.
 */
export async function identificarCliente(admin: Db, phone: string): Promise<Identificacao> {
  const deHoje: Identificacao = { usar: false, clientId: null };
  try {
    const { data, error } = await admin.rpc(RPC_IDENTIFICAR, { p_fone: phone });
    if (error) {
      if (!funcaoAusente(error)) console.warn(`[whatsapp-webhook] retorno_identificar falhou: ${codigoDoErro(error)}`);
      return deHoje;
    }
    if (campo(data, "nova") !== true) return deHoje;
    const clienteId = campo(data, "client_id");
    const clientes = campo(data, "clientes");
    const umSo = !Array.isArray(clientes) || clientes.length <= 1;
    const valido = campo(data, "papel") === "cliente" && umSo && typeof clienteId === "string" && UUID.test(clienteId);
    return { usar: true, clientId: valido ? clienteId : null };
  } catch (e) {
    console.warn(`[whatsapp-webhook] retorno_identificar falhou: ${codigoDoErro(e)}`);
    return deHoje;
  }
}

/**
 * Um dos três leitores de hoje ficou com a mensagem? A confirmação do agendamento ({confirmou}), a conferência do
 * recibo de diárias ({conferiu}) ou a resposta à revisão ({registrou, intencao} com sim, data ou parar). Nada da
 * agenda nem da equipe entra aqui. Valor que não é objeto (a RPC falhou, o leitor nem rodou) = não consumiu.
 */
export function consumidaPelosLeitores(r: { confirmacao: unknown; conferencia: unknown; revisao: unknown }): boolean {
  if (campo(r?.confirmacao, "confirmou") === true) return true;
  if (campo(r?.conferencia, "conferiu") === true) return true;
  const intencao = campo(r?.revisao, "intencao");
  return campo(r?.revisao, "registrou") === true && typeof intencao === "string" &&
    INTENCOES_DA_REVISAO_QUE_CONSOMEM.has(intencao);
}

/**
 * Abre (ou estende, ou reavalia) o caso do retorno para a mensagem gravada (contrato C-ABRIR). Espera os leitores
 * terminarem (o que falhou vale null), calcula "consumida" e só então chama retorno_abrir. Nunca lança: a função
 * ausente é silêncio; outro erro, um console.warn só com o código. Se `consumida` lançar, vale true (falha fecha:
 * na dúvida o retorno não promete nada a quem um leitor pode ter atendido).
 */
export async function abrirNoRetorno(
  admin: Db,
  p: { msgId: string; leitores: PromiseLike<unknown>[]; consumida: (resultados: unknown[]) => boolean },
): Promise<void> {
  try {
    if (typeof p?.msgId !== "string" || !p.msgId) return;
    const resultados = await Promise.allSettled(p.leitores ?? []);
    const valores = resultados.map((r) => (r.status === "fulfilled" ? r.value : null));
    let consumida = true;
    try {
      consumida = p.consumida(valores) === true;
    } catch {
      consumida = true;
    }
    const { error } = await admin.rpc(RPC_ABRIR, { p_msg: p.msgId, p_consumida: consumida });
    if (error && !funcaoAusente(error)) console.warn(`[whatsapp-webhook] retorno_abrir falhou: ${codigoDoErro(error)}`);
  } catch (e) {
    console.warn(`[whatsapp-webhook] retorno_abrir falhou: ${codigoDoErro(e)}`);
  }
}

/**
 * Roda no fundo: EdgeRuntime.waitUntil quando existe (a função só termina quando a promessa termina); fora dele, a
 * promessa segue sozinha. O mesmo padrão do despacho ao ai-agent e da transcrição. Nunca lança, e a promessa que
 * rejeitasse não vira erro solto.
 */
export function noFundo(promessa: Promise<unknown>): void {
  const segura = Promise.resolve(promessa).catch(() => null);
  try {
    const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => unknown } }).EdgeRuntime;
    if (typeof runtime?.waitUntil === "function") runtime.waitUntil(segura);
  } catch {
    // sem waitUntil utilizável: a promessa já segue sozinha
  }
}
