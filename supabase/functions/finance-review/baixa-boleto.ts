// O que vence, fatia 2 (22/11/2026): a conta com boleto conhecido é BAIXADA quando o banco mostra o pagamento.
//
// A exceção que o dono abriu em 22/11/2026 à regra dele de 26/09 ("ligar dinheiro a conta deve sempre questionar",
// _shared/banking/vinculo.ts): só no caso seguro — saída por boleto, valor igual no centavo, banco do boleto igual ao
// banco da saída, uma conta só (ou a parcela de vencimento mais próximo do mesmo fornecedor). Todo o resto continua
// sendo pergunta na fila.
//
// O lado do CLIENTE (24/11/2026): a segunda exceção à mesma regra, aprovada pelo dono em 24/11/2026 ("sim, quero").
// A conta a RECEBER nascida de NF-e com duplicata/boleto é baixada quando o banco mostra o 'CREDITO DE BOLETO' de
// mesmo valor no dia do vencimento, com uma conta candidata só. O crédito não traz o nome de quem pagou — a identidade
// é só valor + dia —, por isso o caso é mais estreito que o das contas a pagar e todo o resto continua pergunta.
// Aqui NÃO se cria receita: baixa-se uma conta que já existe (a entrada continua sem "lançar sozinho").
//
// Quem decide tudo é o banco (baixar_pelo_boleto, migration 20270222100000; baixar_recebido_pelo_boleto, migration
// 20270228100000). Aqui só se chama a RPC, na varredura, ANTES do "lançar sozinho" — para a saída que paga uma conta
// existente não virar despesa nova ao lado dela:
//   · baixarPeloBoleto(admin, reservadas): NUNCA lança — a varredura não pode cair por causa disto. O erro vai para
//     app_error_logs (context finance-review, action baixa-pelo-boleto). A função ausente (migration ainda não
//     aplicada) é silêncio, como antes.
//   · conta que a RPC não conseguiu baixar (barradas > 0, ex.: mês fechado) também vai para app_error_logs.
//   · as linhas reservadas da rodada (comprovante, anotação do dono) não entram: quem decide essas é o dono.
//   · baixarRecebidoPeloBoleto(admin, reservadas): o mesmo molde para o lado do cliente, com action própria
//     (baixa-recebido-pelo-boleto) para os dois erros não se misturarem em app_error_logs. Cada lado tem a sua chave
//     de desligar no banco (boleto_baixa_modo / boleto_recebido_baixa_modo): desligado, a RPC devolve { pulado: true }.

import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_BAIXA = "baixar_pelo_boleto";
/** A RPC do lado do cliente (24/11/2026): baixa a conta a RECEBER de NF-e quando o banco mostra o crédito do boleto. */
export const RPC_BAIXA_RECEBIDO = "baixar_recebido_pelo_boleto";

export interface BaixaPeloBoleto {
  /** Quantas contas foram baixadas nesta rodada. */
  baixadas: number;
  /** As linhas do banco que saíram da fila por isso. */
  transacoes: string[];
}

const NADA: BaixaPeloBoleto = { baixadas: 0, transacoes: [] };

/**
 * O que muda de um lado para o outro (24/11/2026): a RPC, a action do registro de erro e as duas frases dele. O
 * resto — nunca lançar, função ausente = silêncio, barradas registradas — é uma regra só, escrita uma vez, para os
 * dois lados não divergirem quando alguém mexer num deles.
 */
interface Lado {
  rpc: string;
  action: string;
  /** Começo da mensagem quando a RPC não conseguiu baixar alguma conta. */
  barradas: (quantas: unknown) => string;
  /** Começo da mensagem quando a RPC nem rodou. */
  naoRodou: string;
}

const A_PAGAR: Lado = {
  rpc: RPC_BAIXA,
  action: "baixa-pelo-boleto",
  barradas: (n) => `${n} conta(s) com boleto não foram baixadas`,
  naoRodou: "baixa pelo boleto não rodou",
};

const A_RECEBER: Lado = {
  rpc: RPC_BAIXA_RECEBIDO,
  action: "baixa-recebido-pelo-boleto",
  barradas: (n) => `${n} recebimento(s) com boleto não foram baixados`,
  naoRodou: "baixa do recebimento pelo boleto não rodou",
};

/** A função ainda não existe (a migration não foi aplicada): como antes, sem erro. */
function semAMigration(error: { code?: string } | null | undefined): boolean {
  return ["PGRST202", "42883"].includes(String(error?.code ?? ""));
}

/** A chamada de um dos lados. Devolve o que foi baixado (zero em qualquer falha, já registrada). Nunca lança. */
async function baixar(admin: Db, reservadas: Iterable<string>, lado: Lado): Promise<BaixaPeloBoleto> {
  try {
    const { data, error } = await admin.rpc(lado.rpc, { p_exceto: [...new Set(reservadas)] });
    if (error) {
      if (semAMigration(error)) return NADA;
      throw new Error(`${error.code ?? "?"}: ${error.message}`);
    }
    const r = (data ?? {}) as Record<string, unknown>;
    if (Number(r.barradas ?? 0) > 0) {
      await logEdgeError(admin, {
        context: "finance-review", action: lado.action, level: "error",
        message: `${lado.barradas(r.barradas)}: ${(Array.isArray(r.erros) ? r.erros : []).join(" | ")}`.slice(0, 500),
        details: { resultado: r },
      });
    }
    const itens = Array.isArray(r.itens) ? r.itens as { transacao?: unknown }[] : [];
    return {
      baixadas: Number(r.baixadas ?? 0) || 0,
      transacoes: itens.map((i) => String(i?.transacao ?? "")).filter(Boolean),
    };
  } catch (e) {
    await logEdgeError(admin, {
      context: "finance-review", action: lado.action, level: "error",
      message: `${lado.naoRodou}: ${(e as Error)?.message ?? e}`,
      error: e,
    });
    return NADA;
  }
}

/** A RPC da baixa. Devolve o que foi baixado (zero em qualquer falha, já registrada). Nunca lança. */
export function baixarPeloBoleto(admin: Db, reservadas: Iterable<string> = []): Promise<BaixaPeloBoleto> {
  return baixar(admin, reservadas, A_PAGAR);
}

/**
 * A RPC da baixa do lado do cliente (24/11/2026). Mesmas garantias de baixarPeloBoleto: nunca lança, função ausente
 * é silêncio, chave desligada ({ pulado: true }) não é erro e devolve zero.
 */
export function baixarRecebidoPeloBoleto(admin: Db, reservadas: Iterable<string> = []): Promise<BaixaPeloBoleto> {
  return baixar(admin, reservadas, A_RECEBER);
}

/** A frase da varredura (vazia quando nada foi baixado). */
export function mensagemDaBaixa(baixadas: number): string {
  if (!(baixadas > 0)) return "";
  return baixadas === 1
    ? `1 conta baixada pelo boleto — veja em "Lançados sozinhos"`
    : `${baixadas} contas baixadas pelo boleto — veja em "Lançados sozinhos"`;
}

/**
 * A frase da varredura para o lado do cliente (24/11/2026; vazia quando nada foi baixado). A palavra para o dono é
 * "recebimento": "conta baixada" continua querendo dizer conta a pagar.
 */
export function mensagemDoRecebimento(baixados: number): string {
  if (!(baixados > 0)) return "";
  return baixados === 1
    ? `1 recebimento baixado pelo boleto — veja em "Lançados sozinhos"`
    : `${baixados} recebimentos baixados pelo boleto — veja em "Lançados sozinhos"`;
}
