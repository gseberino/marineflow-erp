/**
 * "Este Pix paga…": as contas que uma entrada do banco paga, e quanto vai para cada uma
 * (forma A, F2 — 02/10/2026).
 *
 * A regra que vale é a da função do banco aplicar_entrada_em_contas; esta é a mesma regra para a
 * tela dizer ANTES do clique o que vai acontecer:
 *   - a entrada é aplicada por inteiro (a sobra como crédito do cliente é a F3);
 *   - até R$ 10 a mais numa conta vira receita dela (regra do dono); acima disso, avaliar;
 *   - até R$ 10 a menos pode ser quitado como desconto ("pode ajustar sozinho"); acima disso,
 *     o saldo fica em aberto;
 *   - um pagamento já lançado à mão (o "Receber sinal") pode ser "este Pix": liga, não cria outro.
 */

/** Dono, 02/10/2026: centavos ou até R$ 10 é receita / desconto sem perguntar. */
export const TOLERANCIA = 10;

export interface ContaEmAberto {
  id: string;
  descricao: string;
  /** Número da OS ou do orçamento. */
  documento: string | null;
  vencimento: string;
  valor: number;
  pago: number;
  saldo: number;
}

export interface PagamentoSemPix {
  id: string;
  contaId: string;
  descricao: string;
  documento: string | null;
  data: string;
  valor: number;
}

export interface ItemDaAplicacao {
  contaId: string;
  saldo: number;
  valor: number;
  quitar: boolean;
}

export interface AnaliseDoItem {
  acrescimo: number;
  falta: number;
  /** A falta cabe na tolerância: dá para quitar com desconto. */
  podeQuitar: boolean;
  desconto: number;
  erro: string | null;
  aviso: string | null;
}

export interface ResumoDaAplicacao {
  aplicado: number;
  sobra: number;
  podeAplicar: boolean;
  /** Por que não dá ainda, ou o que vai acontecer. */
  mensagem: string;
}

const c = (v: number) => Math.round((Number(v) || 0) * 100);
const r = (cents: number) => cents / 100;

export function analisarItem(item: ItemDaAplicacao, formatar: (v: number) => string): AnaliseDoItem {
  const valor = c(item.valor);
  const saldo = c(item.saldo);
  const tol = c(TOLERANCIA);
  if (valor <= 0) {
    return { acrescimo: 0, falta: r(saldo), podeQuitar: false, desconto: 0, erro: 'Ponha o valor que vai para esta conta.', aviso: null };
  }
  const acrescimo = Math.max(0, valor - saldo);
  const falta = Math.max(0, saldo - valor);
  const podeQuitar = falta > 0 && falta <= tol;
  const desconto = item.quitar && podeQuitar ? falta : 0;

  let erro: string | null = null;
  let aviso: string | null = null;
  if (acrescimo > tol) {
    erro = `Passa ${formatar(r(acrescimo))} do que falta receber. Acima de R$ 10, avalie o porquê: pode ser outra conta do cliente.`;
  } else if (acrescimo > 0) {
    aviso = `${formatar(r(acrescimo))} a mais viram receita desta conta.`;
  } else if (falta > 0) {
    aviso = podeQuitar
      ? item.quitar
        ? `Os ${formatar(r(falta))} que faltam viram desconto e a conta fica paga.`
        : `Ficam ${formatar(r(falta))} em aberto nesta conta.`
      : `Ficam ${formatar(r(falta))} em aberto nesta conta.`;
  }
  return { acrescimo: r(acrescimo), falta: r(falta), podeQuitar, desconto: r(desconto), erro, aviso };
}

/**
 * Quanto a escolha aplica da entrada e quanto sobra. `restante` é o que falta aplicar da entrada
 * (o valor dela menos o que outras contas já receberam dela).
 */
export function resumir(
  restante: number,
  itens: ItemDaAplicacao[],
  pagamentosLigados: number[],
  formatar: (v: number) => string,
): ResumoDaAplicacao {
  const aplicado = itens.reduce((s, i) => s + c(i.valor), 0) + pagamentosLigados.reduce((s, v) => s + c(v), 0);
  const sobra = c(restante) - aplicado;
  const base = { aplicado: r(aplicado), sobra: r(sobra) };

  if (itens.length === 0 && pagamentosLigados.length === 0) {
    return { ...base, podeAplicar: false, mensagem: 'Marque as contas que este Pix paga.' };
  }
  const comErro = itens.map((i) => analisarItem(i, formatar)).find((a) => a.erro);
  if (comErro) return { ...base, podeAplicar: false, mensagem: comErro.erro! };
  if (sobra > 0) {
    return {
      ...base, podeAplicar: false,
      mensagem: sobra <= c(TOLERANCIA)
        ? `Sobram ${formatar(r(sobra))}. Se o cliente pagou a mais, ponha esse valor numa das contas (até R$ 10 vira receita dela).`
        : `Sobram ${formatar(r(sobra))} desta entrada. Aplique o valor inteiro: guardar a sobra como crédito do cliente chega na próxima etapa.`,
    };
  }
  if (sobra < 0) {
    return { ...base, podeAplicar: false, mensagem: `Passa ${formatar(r(-sobra))} do que falta aplicar desta entrada (${formatar(restante)}).` };
  }
  return { ...base, podeAplicar: true, mensagem: `A entrada fica toda aplicada.` };
}

/** Preenche pelo vencimento mais antigo: cada conta recebe o que falta nela, até a entrada acabar. */
export function distribuirPeloVencimento(restante: number, contas: ContaEmAberto[]): Record<string, number> {
  let resta = c(restante);
  const out: Record<string, number> = {};
  const ordem = [...contas].sort((a, b) => a.vencimento.localeCompare(b.vencimento) || a.descricao.localeCompare(b.descricao));
  for (const conta of ordem) {
    if (resta <= 0) break;
    const vai = Math.min(c(conta.saldo), resta);
    if (vai <= 0) continue;
    out[conta.id] = r(vai);
    resta -= vai;
  }
  return out;
}

/** O que a função do banco recebe. */
export function montarAplicacoes(
  itens: ItemDaAplicacao[],
  pagamentosIds: string[],
): Array<{ receivable_id: string; valor: number; quitar: boolean } | { pagamento_id: string }> {
  return [
    ...itens.map((i) => {
      const falta = c(i.saldo) - c(i.valor);
      return {
        receivable_id: i.contaId,
        valor: r(c(i.valor)),
        quitar: i.quitar && falta > 0 && falta <= c(TOLERANCIA),
      };
    }),
    ...pagamentosIds.map((id) => ({ pagamento_id: id })),
  ];
}
