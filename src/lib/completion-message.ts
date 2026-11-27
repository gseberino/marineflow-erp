// Texto padrão (editável) da mensagem de CONCLUSÃO de serviço enviada ao cliente: o aviso de que o serviço terminou.
// Não fala de dinheiro (dono, 26/11/2026: "2. A"). O saldo, o vencimento e a chave Pix iam aqui, para um número que se
// digita à mão e sem as travas da cobrança; cobrar é pelo "Cobrar o cliente" do CompletionSendDialog, que abre a
// conferência da ficha. O usuário revisa e decide enviar (opt-in) no CompletionSendDialog.
import { emojiDaUnidade } from '@/lib/unidade';

function firstName(name?: string | null): string {
  return (name || '').trim().split(/\s+/)[0] || 'Cliente';
}

export interface CompletionMessageInput {
  clientName?: string | null;
  osNumber: string;
  /** vessels.asset_type: o emoji vem do tipo (🛥️ barco, 🚐 veículo; nada no resto) — nunca lancha para motorhome. */
  assetType?: string | null;
}

/** Monta a mensagem padrão de conclusão: o serviço da OS terminou. Sem valor, vencimento nem Pix. */
export function buildCompletionMessage({ clientName, osNumber, assetType }: CompletionMessageInput): string {
  const nome = firstName(clientName);
  // Era 🚤 fixo para todos (22/10/2026: motorhome recebia lancha).
  const emoji = emojiDaUnidade(assetType);
  return (
    `Olá ${nome}!${emoji ? ` ${emoji}` : ''}\n\n` +
    `Concluímos o serviço da ${osNumber}.\n\n` +
    `Obrigado pela confiança — qualquer coisa, é só chamar!`
  );
}
