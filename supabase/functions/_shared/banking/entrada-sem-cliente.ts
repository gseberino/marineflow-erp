// Entrada de dinheiro que não tem cliente (observação do dono, 28/09/2026).
//
// Conta a receber exige cliente (receivables.client_id é NOT NULL), e a fila do Extrato pedia
// cliente em TODA entrada. Mas dinheiro das contas da HBR passando de uma para outra, ou o sócio
// pondo dinheiro na empresa, não é receita e não tem cliente: a aprovação travava em "Escolha o
// cliente". Essas duas entradas saem da fila marcadas — como a transferência que o motor já
// reconhece sozinho —, sem lançamento. A regra é uma só para a tela e o servidor.
//
// Por que marcas diferentes: a transferência é dinheiro seu mudando de conta (o fluxo de caixa a
// põe à parte quando acha a outra perna); o aporte é dinheiro NOVO entrando na empresa, e o fluxo
// tem de contar como entrada.
//
// Duas travas (revisão de 28/09/2026): (1) a linha sai da fila SEM receita, então é decisão de
// cada linha, nunca do lote nem do "lançar sozinho" — uma categoria só sugerida (pela IA, pelo
// favorecido) tiraria um Pix de cliente do resultado; (2) entrada ligada a uma OS é pagamento do
// serviço: marcá-la como transferência ou aporte apagaria a resposta e deixaria a OS sem baixa.

export interface EntradaSemCliente {
  /** O que fica gravado em bank_transactions.dismissed_kind. */
  marca: "transferencia" | "aporte_socio";
  /** O motivo que aparece em "Fora da fila". */
  motivo: string;
  /** O que a tela diz no lugar do "De qual cliente veio?". */
  aviso: string;
}

const SEM_CLIENTE: Record<string, EntradaSemCliente> = {
  "Transferência entre contas": {
    marca: "transferencia",
    motivo: "Transferência entre contas próprias",
    aviso: "Dinheiro de outra conta da HBR: não é receita e não tem cliente. Ao aprovar, a linha sai da fila marcada como transferência entre contas.",
  },
  "Aporte de sócio": {
    marca: "aporte_socio",
    motivo: "Aporte de sócio: dinheiro do sócio entrando na empresa",
    aviso: "Dinheiro do sócio entrando na empresa: não é receita e não tem cliente. Ao aprovar, a linha sai da fila marcada como aporte de sócio.",
  },
};

/** A entrada desta categoria dispensa cliente? Devolve como marcá-la, ou null. */
export function entradaSemCliente(categoria: string | null | undefined): EntradaSemCliente | null {
  if (!categoria) return null;
  return SEM_CLIENTE[categoria.trim()] ?? null;
}

/**
 * A proposta sai da fila SEM receita? Só entrada ('create_receivable') de uma das categorias
 * acima, pela categoria EFETIVA (a escolhida na linha ou, sem escolha, a sugerida).
 */
export function saiSemReceita(
  kind: string | null | undefined, categoria: string | null | undefined,
): EntradaSemCliente | null {
  return kind === "create_receivable" ? entradaSemCliente(categoria) : null;
}

export const FRASE_SEM_RECEITA_COM_OS =
  "Esta entrada está ligada a uma OS, mas transferência e aporte de sócio não são receita: tire a OS ou troque a categoria";

export const FRASE_SEM_RECEITA_COM_VINCULO =
  "Casar ou registrar sinal diz que é recebimento de cliente, mas transferência e aporte de sócio saem sem receita: para casar, troque a categoria; para sair sem receita, escolha \"Nenhum destes\"";

export const FRASE_SEM_RECEITA_SOZINHA =
  "Transferência ou aporte de sócio sai da fila sem receita: aprove na própria linha";

/**
 * A entrada está ligada a uma OS? A do saldo escolhido no vínculo ou a respondida ("Sim, é
 * desta", a anotação do dono). null ("não é desta") e undefined (sem resposta) não ligam.
 */
export function entradaLigadaAOS(
  osDoVinculo: string | null | undefined, osRespondida: string | null | undefined,
): boolean {
  return (typeof osDoVinculo === "string" && osDoVinculo.length > 0)
    || (typeof osRespondida === "string" && osRespondida.length > 0);
}

/**
 * A contradição de uma entrada que sai sem receita, ou null. Casar com o que já está lançado,
 * registrar sinal, ligar ao saldo de uma OS ou responder "é desta OS" dizem "é recebimento de
 * cliente"; transferência e aporte dizem o contrário. Com as duas respostas, perguntar de novo em
 * vez de escolher pela pessoa (revisão de 28/09/2026). `vinculo` é o que a pessoa ESCOLHEU.
 */
export function contradicaoSemReceita(
  vinculo: { tipo: string } | null | undefined, osRespondida: string | null | undefined,
): string | null {
  if (vinculo) return vinculo.tipo === "service_order_balance" ? FRASE_SEM_RECEITA_COM_OS : FRASE_SEM_RECEITA_COM_VINCULO;
  return entradaLigadaAOS(null, osRespondida) ? FRASE_SEM_RECEITA_COM_OS : null;
}

/** O motivo gravado na linha, com a observação que a pessoa escreveu (até 300 caracteres). */
export function motivoDaEntradaSemCliente(regra: EntradaSemCliente, observacao: string | null | undefined): string {
  const obs = String(observacao ?? "").replace(/\s+/g, " ").trim();
  return (obs ? `${regra.motivo} — ${obs}` : regra.motivo).slice(0, 300);
}
