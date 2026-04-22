// Shared helper that builds a WhatsApp collection message tailored
// to the payment method configured on the linked service order.

export type RenderTemplateFn = (
  body: string,
  ctx: {
    nome: string;
    numero_os: string;
    valor: number;
    vencimento: string;
    pix: string;
    empresa: string;
  },
) => string;

interface BuildArgs {
  template: string;
  renderTemplate: RenderTemplateFn;
  collection: any; // expanded collection row (may include client + service_order)
  paymentMethod?: string | null;
  cardInstallments?: number | null;
  settings: Record<string, string>;
}

export function buildCollectionMessage(args: BuildArgs): string {
  const { template, renderTemplate, collection: c, settings } = args;
  const paymentMethod = (args.paymentMethod || 'pix').toLowerCase();
  const installments = args.cardInstallments || 1;

  const companyName = settings['company_name'] || 'HBR Marine';
  const pixKey = settings['pix_key'] || settings['company_pix'] || '';

  const baseCtx = {
    nome:
      c.contact_name || c.client?.full_name_or_company_name || 'Cliente',
    numero_os: c.service_order?.service_order_number || 'Avulso',
    valor: Number(c.amount),
    vencimento: c.due_date,
    empresa: companyName,
  };

  let message = '';

  if (paymentMethod === 'pix' || paymentMethod === 'bank_transfer') {
    const bankName = settings['bank_name'] || '';
    const bankAgency = settings['bank_agency'] || '';
    const bankAccount = settings['bank_account'] || '';

    message = renderTemplate(template, { ...baseCtx, pix: pixKey });

    if (pixKey || bankName || bankAccount) {
      message += `\n\n💳 *Dados para pagamento:*\n`;
      if (pixKey) message += `🔑 Chave PIX: *${pixKey}*\n`;
      if (bankName) message += `🏦 Banco: ${bankName}\n`;
      if (bankAgency) message += `Agência: ${bankAgency}\n`;
      if (bankAccount) message += `Conta: ${bankAccount}\n`;
    }
  } else if (
    paymentMethod === 'credit_card' ||
    paymentMethod === 'debit_card'
  ) {
    const isCredit = paymentMethod === 'credit_card';
    const cardType = isCredit ? 'crédito' : 'débito';

    message = renderTemplate(template, { ...baseCtx, pix: '' });
    message += `\n\n💳 *Forma de pagamento: Cartão de ${cardType}*`;
    if (isCredit && installments > 1) {
      message += `\nParcelamento em até *${installments}x*`;
    }
    message += `\n\nO pagamento pode ser realizado:`;
    message += `\n• Presencialmente via maquininha`;
    message += `\n• Via link de pagamento (solicite ao atendente)`;
  } else if (paymentMethod === 'cash') {
    message = renderTemplate(template, { ...baseCtx, pix: '' });
    message += `\n\n💵 *Forma de pagamento: Dinheiro*`;
    message += `\nAguardamos seu contato para combinar a entrega.`;
  } else if (paymentMethod === 'boleto') {
    message = renderTemplate(template, { ...baseCtx, pix: '' });
    message += `\n\n🏦 *Forma de pagamento: Boleto Bancário*`;
    message += `\nO boleto será enviado em breve ao seu email.`;
  } else {
    message = renderTemplate(template, { ...baseCtx, pix: pixKey });
  }

  return message;
}
