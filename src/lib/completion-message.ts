// Texto padrão (editável) da mensagem de CONCLUSÃO de serviço enviada ao cliente — com o saldo
// pendente, quando houver. É o momento recomendado para avisar/cobrar (job completion notification).
// O usuário revisa e decide enviar (opt-in) no CompletionSendDialog.
import { format, parseISO, isValid } from 'date-fns';

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

function firstName(name?: string | null): string {
  return (name || '').trim().split(/\s+/)[0] || 'Cliente';
}

function duePhrase(dueDate?: string | null): string {
  if (!dueDate) return '';
  const d = parseISO(dueDate.slice(0, 10));
  return isValid(d) ? `, com vencimento em ${format(d, 'dd/MM/yyyy')}` : '';
}

export interface CompletionMessageInput {
  clientName?: string | null;
  osNumber: string;
  /** saldo em aberto (0 ou ausente = tudo quitado). */
  balance?: number | null;
  /** vencimento do saldo (ISO 'yyyy-MM-dd'); usa a conclusão real quando o saldo é "na entrega". */
  dueDate?: string | null;
}

/** Monta a mensagem padrão de conclusão. Com saldo em aberto, inclui valor e vencimento. */
export function buildCompletionMessage({ clientName, osNumber, balance, dueDate }: CompletionMessageInput): string {
  const nome = firstName(clientName);
  const saldo = Number(balance || 0);
  if (saldo > 0.009) {
    return (
      `Olá ${nome}! 🚤\n\n` +
      `Concluímos o serviço da ${osNumber}. Ficou um saldo de *${brl(saldo)}*${duePhrase(dueDate)}.\n\n` +
      `Qualquer dúvida sobre o pagamento ou o serviço, estamos à disposição. Obrigado pela confiança!`
    );
  }
  return (
    `Olá ${nome}! 🚤\n\n` +
    `Concluímos o serviço da ${osNumber} e está tudo certo/quitado.\n\n` +
    `Obrigado pela confiança — qualquer coisa, é só chamar!`
  );
}
