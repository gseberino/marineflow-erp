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
}
