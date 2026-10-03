/**
 * O que dizer, e o que oferecer, para um lançamento ligado a uma linha do extrato.
 *
 * Pedido do dono (02/10/2026): no "Mês pronto?", o lançamento que não batia com o banco só
 * dizia "Veio do extrato. Para mudar, desfaça a aprovação" — sem dizer qual aprovação, o que
 * acontece ao desfazer, nem oferecer o conserto. O caso: sinal do ORÇ-00073 de R$ 1.865,47, e
 * o cliente pagou R$ 1.866,00.
 *
 * O ajuste automático só existe no caso inequívoco: conta a receber com UM pagamento, e é o que
 * a linha do banco registrou (a função do banco recusa o resto). Com mais de um pagamento, a
 * diferença pode ser um pagamento por fora (dinheiro, outro Pix) ou um vínculo trocado — aí o
 * texto mostra os pagamentos e não há botão de ajuste.
 */

export type TipoDoLancamento = 'payable' | 'receivable';

export interface LinhaDoBanco {
  data: string;
  descricao: string;
  valor: number;
  /** O pagamento que a conciliação registrou para esta linha. */
  pagamentoId: string | null;
}

export interface PagamentoDoLancamento {
  id: string;
  valor: number;
  data: string;
}

export interface DiagnosticoDoVinculo {
  situacao: 'bate' | 'banco_maior' | 'banco_menor' | 'varios_pagamentos' | 'conta_a_pagar' | 'varias_contas';
  /** O que está acontecendo, em uma ou duas frases. */
  texto: string;
  diferenca: number;
  podeAjustar: boolean;
  rotuloDoAjuste?: string;
  /** O que o ajuste faz, para a confirmação. */
  efeitoDoAjuste?: string;
  /** O que desfazer faz NESTE lançamento (nasceu do extrato ou foi só casado). */
  efeitoDoDesfazer: string;
  /** Sobrou parte da entrada sem conta: dá para aplicar em outra (forma A, F2). */
  podeAplicarSobra: boolean;
  rotuloDaSobra?: string;
}

/** Outra conta que a mesma entrada pagou (um Pix para várias contas, 02/10/2026). */
export interface OutraContaDaEntrada {
  descricao: string;
  valor: number;
}

const centavos = (v: number) => Math.round(v * 100);
/** Dono, 02/10/2026: até R$ 10 a mais é receita; acima disso, avaliar o porquê. */
const TOLERANCIA = 10;

export function diagnosticoDoVinculo(p: {
  tipo: TipoDoLancamento;
  valor: number;
  linha: LinhaDoBanco;
  pagamentos: PagamentoDoLancamento[];
  nasceuDoExtrato: boolean;
  formatar: (v: number) => string;
  formatarData: (d: string) => string;
  /** Contas que a mesma entrada também pagou. */
  outrasContas?: OutraContaDaEntrada[];
  /** O que sobra da entrada depois de tudo o que foi aplicado dela. */
  sobraDaEntrada?: number;
}): DiagnosticoDoVinculo {
  const { tipo, valor, linha, pagamentos, nasceuDoExtrato, formatar, formatarData } = p;
  const outras = p.outrasContas ?? [];
  const banco = Math.abs(linha.valor);
  const diferenca = (centavos(banco) - centavos(valor)) / 100;
  const ehReceber = tipo === 'receivable';
  const quem = ehReceber ? 'o cliente' : 'a empresa';
  const sobra = ehReceber ? Math.max(0, centavos(p.sobraDaEntrada ?? 0)) / 100 : 0;
  const sobraDisponivel = sobra > 0
    ? { podeAplicarSobra: true, rotuloDaSobra: `Aplicar os ${formatar(sobra)} que sobraram em outra conta` }
    : { podeAplicarSobra: false };

  const efeitoDoDesfazer = nasceuDoExtrato
    ? 'Desfazer a aprovação cancela este lançamento e devolve a linha do banco para a fila do Extrato, para você aprovar de novo do jeito certo.'
    : outras.length > 0
      ? 'Desfazer o vínculo mantém este lançamento (sem o pagamento que veio desta entrada); a entrada continua pagando as outras contas.'
      : 'Desfazer o vínculo mantém este lançamento (sem o pagamento que o casamento registrou) e devolve a linha do banco para a fila do Extrato, para casar de novo.';

  if (!ehReceber) {
    return {
      situacao: 'conta_a_pagar',
      texto: centavos(diferenca) === 0
        ? 'O lançamento bate com o banco.'
        : `O banco mostra ${formatar(banco)}, ${formatar(Math.abs(diferenca))} ${diferenca > 0 ? 'a mais' : 'a menos'} que este lançamento. `
          + 'Numa conta a pagar, o caminho é desfazer a aprovação e aprovar de novo com o valor certo.',
      diferenca,
      podeAjustar: false,
      efeitoDoDesfazer,
      podeAplicarSobra: false,
    };
  }

  // A entrada pagou também outras contas: o valor dela não é desta conta sozinha, e ajustar ao
  // banco contaria o mesmo dinheiro duas vezes (a função do banco recusa).
  if (outras.length > 0) {
    const lista = outras.map((o) => `${o.descricao} (${formatar(o.valor)})`).join(', ');
    return {
      situacao: 'varias_contas',
      texto: `Esta entrada de ${formatar(banco)} pagou também ${lista}. `
        + (sobra > 0 ? `Sobram ${formatar(sobra)} dela sem conta.` : 'Ela está toda aplicada.'),
      diferenca: 0,
      podeAjustar: false,
      efeitoDoDesfazer,
      ...sobraDisponivel,
    };
  }

  const daLinha = pagamentos.find((x) => x.id === linha.pagamentoId);
  const umSoDaLinha = pagamentos.length === 1 && !!daLinha;

  if (!umSoDaLinha) {
    const lista = pagamentos
      .map((x) => `${formatar(x.valor)} em ${formatarData(x.data)} (${x.id === linha.pagamentoId ? 'por esta linha do banco' : 'sem esta linha do banco'})`)
      .join('; ');
    return {
      situacao: 'varios_pagamentos',
      texto: `Este lançamento de ${formatar(valor)} tem ${pagamentos.length} pagamento(s): ${lista || 'nenhum confirmado'}. `
        + `Esta linha do banco mostra ${formatar(banco)}. Confira se os outros pagamentos entraram mesmo, e por onde, `
        + 'antes de mexer: não há ajuste automático quando a diferença pode ser um pagamento por fora.',
      diferenca,
      podeAjustar: false,
      efeitoDoDesfazer,
      ...sobraDisponivel,
    };
  }

  const pagamentoBate = centavos(daLinha!.valor) === centavos(banco);
  if (centavos(diferenca) === 0) {
    if (pagamentoBate) {
      return { situacao: 'bate', texto: 'O lançamento bate com o banco.', diferenca: 0, podeAjustar: false, efeitoDoDesfazer, podeAplicarSobra: false };
    }
    // O lançamento bate, mas o pagamento registrado não: só o pagamento muda.
    return {
      situacao: daLinha!.valor < banco ? 'banco_maior' : 'banco_menor',
      texto: `O lançamento bate com o banco (${formatar(banco)}), mas o pagamento registrado é de ${formatar(daLinha!.valor)}.`,
      diferenca: 0,
      podeAjustar: true,
      rotuloDoAjuste: `Ajustar o pagamento para ${formatar(banco)}`,
      efeitoDoAjuste: `O pagamento passa a valer ${formatar(banco)}, o que entrou no banco. Fica registrado na trilha.`,
      efeitoDoDesfazer,
      podeAplicarSobra: false,
    };
  }

  if (diferenca > 0) {
    // Mais de R$ 10 além da conta costuma ser outra conta do mesmo cliente paga no mesmo Pix:
    // a sobra vai para ela. Ajustar (pagou a mais de propósito) continua possível.
    const outraConta = centavos(diferenca) > centavos(TOLERANCIA) && sobra > 0;
    return {
      situacao: 'banco_maior',
      texto: `O banco mostra ${formatar(banco)}: ${quem} pagou ${formatar(diferenca)} a mais que este lançamento.`
        + (outraConta ? ' Acima de R$ 10, avalie: se o Pix pagou também outra conta, aplique a sobra nela.' : ''),
      diferenca,
      podeAjustar: true,
      rotuloDoAjuste: `Ajustar para ${formatar(banco)}`,
      efeitoDoAjuste: `O lançamento e o pagamento passam a valer ${formatar(banco)}, o que entrou no banco; `
        + `os ${formatar(diferenca)} contam como recebidos deste cliente. Fica registrado na trilha.`,
      efeitoDoDesfazer,
      ...sobraDisponivel,
    };
  }

  const falta = Math.abs(diferenca);
  return {
    situacao: 'banco_menor',
    texto: `O banco mostra ${formatar(banco)}: ${formatar(falta)} a menos que este lançamento. `
      + 'Se o cliente ainda vai pagar a diferença, não ajuste: o saldo fica em aberto e entra na cobrança.',
    diferenca,
    podeAjustar: true,
    rotuloDoAjuste: `Ajustar para ${formatar(banco)} (desconto de ${formatar(falta)})`,
    efeitoDoAjuste: `Os ${formatar(falta)} deixam de ser cobrados (desconto): o lançamento passa a valer ${formatar(banco)} `
      + 'e fica pago. Fica registrado na trilha.',
    efeitoDoDesfazer,
    podeAplicarSobra: false,
  };
}
