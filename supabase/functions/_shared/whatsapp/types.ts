// Canonical types for the WhatsApp provider abstraction layer.
// Both ZapiProvider and EvolutionProvider implement WhatsAppProvider.

export type SendResult =
  | { ok: true; providerMessageId: string }
  | { ok: false; error: string; retryable: boolean };

// Canonical inbound event — fields actually used by the MarineFlow webhook handler.
export type IncomingMessageEvent = {
  from: string;          // normalized phone digits with DDI (e.g. "5547999999999")
  messageId: string;     // provider-specific message ID
  fromMe: boolean;
  text: string | null;
  messageType: "text" | "image" | "audio" | "video" | "document";
  mediaUrl: string | null;
  senderName: string | null;
  timestamp: number;     // ms since epoch
};

// Conteúdo de um Status/Stories do WhatsApp.
export type StatusContent = {
  type: "text" | "image" | "video";
  content: string;            // texto (type=text) OU URL da mídia (image/video)
  caption?: string;           // legenda (image/video)
  backgroundColor?: string;   // só type=text
  font?: number;              // só type=text
  allContacts?: boolean;      // default true — publica para todos os contatos
  statusJidList?: string[];   // opcional: segmenta quem vê (JIDs)
};

export interface WhatsAppProvider {
  sendText(to: string, message: string): Promise<SendResult>;
  sendLink(
    to: string,
    message: string,
    linkUrl: string,
    title?: string,
    description?: string,
    imageUrl?: string,
  ): Promise<SendResult>;
  sendDocument(
    to: string,
    fileUrl: string,
    fileName: string,
    caption?: string,
  ): Promise<SendResult>;
  checkNumberExists(to: string): Promise<boolean>;
  // Returns null for unrecognized/ignored payloads (presence, typing, groups, etc.)
  parseIncomingWebhook(payload: unknown): IncomingMessageEvent | null;

  // ─── Capacidades OPCIONAIS (aditivas) ──────────────────────────────────────
  // O EvolutionProvider implementa; o ZapiProvider pode não implementar. Os callers
  // DEVEM usar feature-guard (ex.: provider.sendImage?.(...)). Nunca quebra o caminho
  // vivo de mensagens: só adiciona.
  /** Envia uma imagem ao chat (vitrine de produto, arte promocional). */
  sendImage?(to: string, imageUrl: string, caption?: string): Promise<SendResult>;
  /** Publica um Status/Stories (texto/imagem/vídeo). */
  sendStatus?(content: StatusContent): Promise<SendResult>;
  /** Envia uma enquete tappável (agendamento, qualificação). */
  sendPoll?(to: string, name: string, options: string[], selectableCount?: number): Promise<SendResult>;
  /** Reage a uma mensagem existente (acuse de recebimento humano). */
  sendReaction?(to: string, messageId: string, fromMe: boolean, emoji: string): Promise<SendResult>;
  /** Sinaliza presença ("digitando…"/"gravando…"). */
  sendPresence?(to: string, presence: "composing" | "recording" | "paused", delayMs?: number): Promise<SendResult>;
  /** Marca uma mensagem como lida (dá o "visto" natural ao assumir o atendimento). */
  markRead?(to: string, messageId: string, fromMe: boolean): Promise<SendResult>;
}
