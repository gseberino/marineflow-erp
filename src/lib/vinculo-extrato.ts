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
  situacao: 'bate' | 'banco_maior' | 'banco_menor' | 'varios_pagamentos' | 'conta_a_pagar';
  /** O que está acontecendo, em uma ou duas frases. */
  texto: string;
  diferenca: number;
  podeAjustar: boolean;
  rotuloDoAjuste?: string;
  /** O que o ajuste faz, para a confirmação. */
  efeitoDoAjuste?: string;
  /** O que desfazer faz NESTE lançamento (nasceu do extrato ou foi só casado). */
  efeitoDoDesfazer: string;
}

const centavos = (v: number) => Math.round(v * 100);

export function diagnosticoDoVinculo(p: {
  tipo: TipoDoLancamento;
  valor: number;
  linha: LinhaDoBanco;
  pagamentos: PagamentoDoLancamento[];
  nasceuDoExtrato: boolean;
  formatar: (v: number) => string;
  formatarData: (d: string) => string;
}): DiagnosticoDoVinculo {
  const { tipo, valor, linha, pagamentos, nasceuDoExtrato, formatar, formatarData } = p;
  const banco = Math.abs(linha.valor);
  const diferenca = (centavos(banco) - centavos(valor)) / 100;
  const ehReceber = tipo === 'receivable';
  const quem = ehReceber ? 'o cliente' : 'a empresa';

  const efeitoDoDesfazer = nasceuDoExtrato
    ? 'Desfazer a aprovação cancela este lançamento e devolve a linha do banco para a fila do Extrato, para você aprovar de novo do jeito certo.'
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
    };
  }

  const pagamentoBate = centavos(daLinha!.valor) === centavos(banco);
  if (centavos(diferenca) === 0) {
    if (pagamentoBate) {
      return { situacao: 'bate', texto: 'O lançamento bate com o banco.', diferenca: 0, podeAjustar: false, efeitoDoDesfazer };
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
    };
  }

  if (diferenca > 0) {
    return {
      situacao: 'banco_maior',
      texto: `O banco mostra ${formatar(banco)}: ${quem} pagou ${formatar(diferenca)} a mais que este lançamento.`,
      diferenca,
      podeAjustar: true,
      rotuloDoAjuste: `Ajustar para ${formatar(banco)}`,
      efeitoDoAjuste: `O lançamento e o pagamento passam a valer ${formatar(banco)}, o que entrou no banco; `
        + `os ${formatar(diferenca)} contam como recebidos deste cliente. Fica registrado na trilha.`,
      efeitoDoDesfazer,
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
  };
}
