// Retorno rápido ao cliente, F4 (P13): o leitor do parceiro no whatsapp-webhook (contrato C-LER).
//
// Logo depois de gravar a recebida, e antes de qualquer outro leitor, o webhook pergunta ao banco se a mensagem é uma
// palavra do parceiro ou do cliente final: o NÃO <sigla> do cliente (vale em qualquer parceiro_modo), a resposta ao aviso
// que pode ser um "não" (retida), e o *pátio*, *pausar* e *retomar* do número confirmado de parceiro. Quem decide é
// parceiro_ler_mensagem (P7), no banco; aqui só se chama e se lê o booleano.
//
// Consumida = nenhum outro leitor vê a mensagem (o "não" tem um dono só: agenda_resposta_do_cliente leria o mesmo "não"),
// e o retorno_abrir ainda registra, com p_consumida verdadeiro. Nunca lança: a função ausente (o webhook pode subir antes
// das migrations da F4) é silêncio e o caminho de hoje; outro erro, um console.warn só com o código, nunca com telefone ou
// texto. A RPC recebe só o id da mensagem: o banco lê o resto.
//
// Este arquivo não importa _shared/ai/ nem _shared/agenda/ (congelados).
//
// Reverter: em index.ts, tirar a linha do doParceiro e o if (!doParceiro.consumida) (os leitores voltam ao nível de
// antes) e o "doParceiro.consumida ||" do callback do abrirNoRetorno; depois, apagar este arquivo e parceiro_test.ts.

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_LER = "parceiro_ler_mensagem";

/** As ações de C-LER: só elas voltam ao chamador (nunca um texto do banco). */
const ACAO = /^[a-z_]{1,32}$/;

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha): o mesmo teste do retorno.ts. */
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

export type LeituraDoParceiro = { consumida: boolean; acao?: string };

/**
 * Pergunta ao banco se a mensagem gravada é do parceiro (C-LER). `consumida` só com o booleano verdadeiro da RPC; tudo o
 * mais (falso, ausente, erro, resposta estranha, exceção) vale não consumida, e o webhook segue o caminho de hoje.
 */
export async function lerNoParceiro(admin: Db, p: { msgId: string }): Promise<LeituraDoParceiro> {
  const nada: LeituraDoParceiro = { consumida: false };
  try {
    if (typeof p?.msgId !== "string" || !p.msgId) return nada;
    const { data, error } = await admin.rpc(RPC_LER, { p_msg: p.msgId });
    if (error) {
      if (!funcaoAusente(error)) console.warn(`[whatsapp-webhook] ${RPC_LER} falhou: ${codigoDoErro(error)}`);
      return nada;
    }
    if (data === null || typeof data !== "object" || Array.isArray(data)) return nada;
    const d = data as Record<string, unknown>;
    if (d.consumida !== true) return nada;
    return typeof d.acao === "string" && ACAO.test(d.acao) ? { consumida: true, acao: d.acao } : { consumida: true };
  } catch (e) {
    console.warn(`[whatsapp-webhook] ${RPC_LER} falhou: ${codigoDoErro(e)}`);
    return nada;
  }
}
