/**
 * O orçamento escrito no corpo da mensagem de WhatsApp.
 *
 * POR QUE ISTO EXISTE: até aqui o orçamento só ia por link ou PDF anexado — nos dois casos
 * o cliente precisa ABRIR alguma coisa para descobrir quanto custa. Quem está no celular,
 * no meio do dia, frequentemente não abre; e a pergunta que trava a decisão ("quanto é, e
 * quanto eu pago agora?") fica sem resposta à vista.
 *
 * Aqui os números vão no texto: total, quanto é o sinal, o que ele cobre, quanto fica para
 * a entrega e como pagar. SEM link e sem anexo — o dono foi explícito (24/09/2026): este
 * modo é para mandar os valores, e mais nada. Quem quiser o documento usa os outros dois
 * modos de envio, que continuam ali ao lado.
 *
 * DUAS REGRAS QUE ESTE ARQUIVO NÃO PODE QUEBRAR:
 *
 *  1. O sinal e o saldo saem de `computeSchedule` (src/lib/quote-deposit.ts), a fonte única
 *     que o formulário, o PDF e o diálogo "Receber sinal" já usam. Recalcular aqui seria
 *     recriar exatamente o bug que aquela lib foi escrita para matar: a mesma condição
 *     mostrando valores diferentes em telas diferentes.
 *
 *  2. O que o gestor escolheu ESCONDER do cliente continua escondido. As opções de
 *     documento (`pdf_options_quote`) valem aqui igual: se os preços de peça não aparecem
 *     no PDF, não podem vazar pela mensagem.
 */
import { computeSchedule, type DepositInstallment, type DepositOrderLike } from './quote-deposit';

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

/** Só o primeiro nome: a mensagem é uma conversa, não um ofício. */
function primeiroNome(nome?: string | null): string {
  const limpo = (nome || '').trim();
  if (!limpo) return 'Olá';
  return limpo.split(/\s+/)[0];
}

/** O que o gestor decidiu mostrar ao cliente — mesmas chaves do PDF. */
export interface OpcoesDeExibicao {
  showServicePrices?: boolean;
  showPartsPrices?: boolean;
  showTravelCost?: boolean;
  showDiscount?: boolean;
  showBankDetails?: boolean;
  showPaymentInstructions?: boolean;
  hideFinancials?: boolean;
}

export interface DadosDaEmpresa {
  nome?: string | null;
  pixKey?: string | null;
  bankName?: string | null;
  bankAgency?: string | null;
  bankAccount?: string | null;
}

export interface ResumoDeOrcamentoInput {
  numero: string;
  clienteNome?: string | null;
  /** Embarcação, motorhome ou equipamento — ajuda o cliente a saber de qual orçamento se trata. */
  ativoNome?: string | null;
  /** O orçamento, com os totais por categoria (mesma forma que o resto do sistema usa). */
  orcamento: DepositOrderLike & { grand_total?: number | null };
  /** As parcelas da condição de pagamento escolhida. */
  parcelas?: DepositInstallment[] | null;
  /** Rótulo da condição, como aparece na tela ("50% mão de obra + 100% materiais"). */
  condicaoLabel?: string | null;
  validadeDias?: number | null;
  /**
   * Data fixa de validade, já em dd/mm/aaaa. Quando vem, vence os dias: é o que o PDF do mesmo
   * envio imprime ("Válido até …"), e o texto não pode dizer outra coisa (26/09/2026).
   */
  validadeAte?: string | null;
  empresa?: DadosDaEmpresa;
  opcoes?: OpcoesDeExibicao;
}

/**
 * Traduz os percentuais da entrada para uma frase que o cliente entende.
 *
 * "100% dos materiais + 50% da mão de obra" responde sozinho a pergunta que vem depois de
 * todo sinal — "por que esse valor?" — e evita a ligação perguntando.
 */
function explicaOSinal(
  p: { servicesPct: number; partsPct: number; expensesPct: number } | null,
  /** O que o orçamento REALMENTE tem: citar categoria zerada confunde. */
  temValor: { servicos: boolean; pecas: boolean; despesas: boolean },
): string {
  if (!p) return '';
  const partes: string[] = [];
  if (p.partsPct > 0 && temValor.pecas) partes.push(`${p.partsPct}% dos materiais`);
  if (p.servicesPct > 0 && temValor.servicos) partes.push(`${p.servicesPct}% da mão de obra`);
  if (p.expensesPct > 0 && temValor.despesas) partes.push(`${p.expensesPct}% das despesas`);
  // "100% das despesas" num orçamento sem despesa nenhuma faz o cliente procurar um custo
  // que não existe -- e a primeira reação a uma linha que não fecha é desconfiar do resto.
  return partes.join(' + ');
}

/** Quando a parcela vence, em português de conversa. */
function quandoVence(row: { dueBasis: 'delivery' | 'days'; days: number }): string {
  if (row.dueBasis === 'delivery') return 'na entrega';
  if (row.days <= 0) return 'na aprovação';
  return `em ${row.days} dias`;
}

/**
 * Monta a mensagem. Devolve texto puro, pronto para o WhatsApp (negrito com *asteriscos*).
 *
 * Nada é enviado por esta função: ela só escreve. Quem envia é o diálogo, depois de a
 * pessoa ler e poder editar — orçamento é conversa comercial, e a última palavra sobre o
 * que vai escrito é de quem está negociando.
 */
export function buildQuoteWhatsAppSummary(input: ResumoDeOrcamentoInput): string {
  const {
    numero, clienteNome, ativoNome, orcamento, parcelas, condicaoLabel,
    validadeDias, validadeAte, empresa = {}, opcoes = {},
  } = input;

  const mostrar = {
    servicos: opcoes.showServicePrices !== false,
    pecas: opcoes.showPartsPrices !== false,
    deslocamento: opcoes.showTravelCost !== false,
    desconto: opcoes.showDiscount !== false,
    banco: opcoes.showBankDetails !== false,
    comoPagar: opcoes.showPaymentInstructions !== false,
  };

  const empresaNome = (empresa.nome || 'HBR Marine').trim();
  const linhas: string[] = [];

  linhas.push(`*Orçamento ${numero}* — ${empresaNome}`);
  linhas.push(`Olá, ${primeiroNome(clienteNome)}!`);
  if (ativoNome) linhas.push(`Referente a: ${ativoNome}`);

  // ── Sem valores não há resumo ────────────────────────────────────────────
  // Com os financeiros ocultos sobra um cumprimento, e mandar isso é pior que não
  // mandar nada. O diálogo nem oferece este modo nesse caso; a frase abaixo existe só
  // para a função nunca devolver uma mensagem sem conteúdo.
  if (opcoes.hideFinancials) {
    linhas.push('');
    linhas.push('Preparamos seu orçamento — envio os valores em seguida.');
    return linhas.join('\n');
  }

  const labor = Number(orcamento.labor_cost_total || 0);
  const parts = Number(orcamento.parts_cost_total || 0);
  const operacional = Number(orcamento.operational_cost_total || 0);
  const travel = orcamento.is_travel_billable !== false ? Number(orcamento.travel_cost_total || 0) : 0;
  const subcontrato = Number(orcamento.subcontract_cost_total || 0);
  const desconto = Number(orcamento.discount_amount || 0);

  // O total é o do orçamento quando existe: é o número que o cliente já viu no PDF, e
  // divergir dele por centavo de arredondamento destruiria a confiança na mensagem.
  const totalCalculado = labor + parts + operacional + travel + subcontrato - desconto
    + Number(orcamento.tax_amount || 0);
  const total = Number(orcamento.grand_total ?? totalCalculado);

  linhas.push('');
  linhas.push('*Valores*');
  if (mostrar.servicos && labor > 0) linhas.push(`• Serviços: ${brl(labor)}`);
  if (mostrar.pecas && parts > 0) linhas.push(`• Materiais e peças: ${brl(parts)}`);
  if (mostrar.deslocamento && travel > 0) linhas.push(`• Deslocamento: ${brl(travel)}`);
  if (subcontrato > 0) linhas.push(`• Serviços de terceiros: ${brl(subcontrato)}`);
  if (operacional > 0) linhas.push(`• Custos operacionais: ${brl(operacional)}`);
  if (mostrar.desconto && desconto > 0) linhas.push(`• Desconto: −${brl(desconto)}`);
  linhas.push(`*Total: ${brl(total)}*`);

  // ── Sinal e saldo ────────────────────────────────────────────────────────
  const plano = computeSchedule(orcamento, parcelas);
  const temSinal = plano.signalAmount > 0.009;
  const temSaldo = plano.balance.length > 0;

  if (temSinal || temSaldo) {
    linhas.push('');
    linhas.push('*Como fica o pagamento*');
    if (condicaoLabel) linhas.push(`_${condicaoLabel}_`);

    if (temSinal) {
      // O sinal é a única quantia que o cliente precisa separar AGORA. Ganha destaque
      // próprio, porque é a informação que decide se o trabalho começa ou não.
      const rowsDaCondicao = Array.isArray(parcelas) ? parcelas : [];
      const entrada = rowsDaCondicao.find(
        (r) => r.tipo === 'aprovacao' || (!r.tipo && (r.days_after_approval ?? 0) === 0),
      );
      const explicacao = explicaOSinal(
        entrada
          ? {
              servicesPct: Number(entrada.services_pct ?? entrada.percent ?? 0),
              partsPct: Number(entrada.parts_pct ?? entrada.percent ?? 0),
              expensesPct: Number(entrada.expenses_pct ?? 0),
            }
          : null,
        {
          servicos: labor > 0 && mostrar.servicos,
          pecas: parts > 0 && mostrar.pecas,
          despesas: operacional + travel + subcontrato > 0,
        },
      );
      linhas.push(`💠 *Sinal para iniciar: ${brl(plano.signalAmount)}*`);
      if (explicacao) linhas.push(`   (${explicacao})`);
    }

    for (const parcela of plano.balance) {
      linhas.push(`🔹 ${parcela.label}: ${brl(parcela.amount)} — ${quandoVence(parcela)}`);
    }

    if (!temSinal && temSaldo) {
      linhas.push('_Sem entrada: o pagamento segue o plano acima._');
    }
  }

  // ── Como pagar ───────────────────────────────────────────────────────────
  const pix = (empresa.pixKey || '').trim();
  const banco = (empresa.bankName || '').trim();
  const agencia = (empresa.bankAgency || '').trim();
  const conta = (empresa.bankAccount || '').trim();

  if (mostrar.comoPagar && (pix || (mostrar.banco && (banco || conta)))) {
    linhas.push('');
    linhas.push(temSinal ? '*Para pagar o sinal*' : '*Para pagar*');
    if (pix) linhas.push(`🔑 Chave PIX: *${pix}*`);
    if (mostrar.banco && banco) linhas.push(`🏦 ${banco}`);
    if (mostrar.banco && (agencia || conta)) {
      linhas.push(`   ${[agencia && `Ag ${agencia}`, conta && `Conta ${conta}`].filter(Boolean).join(' · ')}`);
    }
    linhas.push(`_Favorecido: ${empresaNome}_`);
    if (temSinal) {
      // O próximo passo, dito por escrito: sem isso o cliente paga e fica esperando sem
      // saber se alguém viu.
      linhas.push('');
      linhas.push('Assim que o comprovante chegar, confirmamos e agendamos o serviço.');
    }
  }

  if (validadeAte) {
    linhas.push('');
    linhas.push(`⏳ Proposta válida até ${validadeAte}.`);
  } else if (validadeDias && validadeDias > 0) {
    linhas.push('');
    linhas.push(`⏳ Proposta válida por ${validadeDias} ${validadeDias === 1 ? 'dia' : 'dias'}.`);
  }

  linhas.push('');
  linhas.push('_Qualquer dúvida, é só responder por aqui._');

  return linhas.join('\n');
}
