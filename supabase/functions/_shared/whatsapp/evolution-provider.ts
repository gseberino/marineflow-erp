// EvolutionProvider — implements WhatsAppProvider against Evolution API v2.
// Activated when WHATSAPP_PROVIDER=evolution (cutover B6).
import type { WhatsAppProvider, SendResult, IncomingMessageEvent } from "./types.ts";
import { normalizePhoneNumber } from "./normalize.ts";

export interface EvolutionConfig {
  apiUrl: string;     // e.g. "https://evo.meu-servidor.com" — no trailing slash
  apiKey: string;     // AUTHENTICATION_API_KEY set on the Evolution instance
  instance: string;   // Instance name configured in Evolution (e.g. "marineflow")
}

// Evolution API returns numeric delivery statuses on messages.update events.
const EVOLUTION_STATUS_MAP: Record<number, string> = {
  1: "pending",
  2: "sent",
  3: "delivered",
  4: "read",
  5: "played",
};

export class EvolutionProvider implements WhatsAppProvider {
  private readonly baseUrl: string;
  private readonly headers: Record<string, string>;
  private readonly instance: string;

  constructor(config: EvolutionConfig) {
    this.baseUrl = config.apiUrl.replace(/\/$/, "");
    this.headers = {
      "Content-Type": "application/json",
      "apikey": config.apiKey,
    };
    this.instance = config.instance;
  }

  private async post(path: string, payload: unknown): Promise<SendResult> {
    try {
      const res = await fetch(`${this.baseUrl}/${path}`, {
        method: "POST",
        headers: this.headers,
        body: JSON.stringify(payload),
      });
      const body = await res.json().catch(() => ({})) as Record<string, unknown>;
      if (res.ok && !body["error"]) {
        // Evolution wraps the message ID as body.key.id
        const key = body["key"] as Record<string, unknown> | undefined;
        const msgId = String(key?.["id"] ?? body["id"] ?? body["messageId"] ?? "");
        return { ok: true, providerMessageId: msgId };
      }
      // Evolution nests the real detail in body.response.message
      const nested = (body["response"] as Record<string, unknown> | undefined);
      const detail = nested?.["message"] ?? nested?.["error"];
      const errMsg = detail
        ? `${body["error"] ?? `HTTP ${res.status}`}: ${detail}`
        : String(body["error"] ?? body["message"] ?? `HTTP ${res.status}`);
      return {
        ok: false,
        error: errMsg,
        retryable: res.status >= 500,
      };
    } catch (err) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : String(err),
        retryable: true,
      };
    }
  }

  async sendText(to: string, message: string): Promise<SendResult> {
    // Evolution v2: flat payload { number, text } (v1 used { textMessage: { text } }).
    return this.post(`message/sendText/${this.instance}`, {
      number: normalizePhoneNumber(to),
      text: message,
    });
  }

  async sendLink(
    to: string,
    message: string,
    linkUrl: string,
    _title?: string,
    _description?: string,
    _imageUrl?: string,
  ): Promise<SendResult> {
    // Evolution has no /send-link equivalent. The URL is embedded in the message
    // body and linkPreview:true lets WhatsApp fetch OG metadata automatically.
    // title, description, imageUrl are not customisable via the Evolution API.
    const text = message.includes(linkUrl) ? message : `${message}\n${linkUrl}`;
    // Evolution v2: flat payload { number, text, linkPreview }.
    return this.post(`message/sendText/${this.instance}`, {
      number: normalizePhoneNumber(to),
      text,
      linkPreview: true,
    });
  }

  async sendDocument(
    to: string,
    fileUrl: string,
    fileName: string,
    caption?: string,
  ): Promise<SendResult> {
    return this.post(`message/sendMedia/${this.instance}`, {
      number: normalizePhoneNumber(to),
      mediatype: "document",
      mimetype: "application/pdf",
      media: fileUrl,
      fileName,
      caption: caption ?? "",
    });
  }

  async checkNumberExists(to: string): Promise<boolean> {
    try {
      const phone = normalizePhoneNumber(to);
      const res = await fetch(
        `${this.baseUrl}/chat/whatsappNumbers/${this.instance}`,
        {
          method: "POST",
          headers: this.headers,
          body: JSON.stringify({ numbers: [phone] }),
        },
      );
      if (!res.ok) return false;
      const body = await res.json().catch(() => []);
      if (!Array.isArray(body) || body.length === 0) return false;
      return (body[0] as Record<string, unknown>)["exists"] === true;
    } catch {
      return false;
    }
  }

  parseIncomingWebhook(payload: unknown): IncomingMessageEvent | null {
    try {
      const p = payload as Record<string, unknown>;
      const eventRaw = String(p["event"] ?? p["type"] ?? "");
      const event = eventRaw.replace(/_/g, ".").toLowerCase();

      // Only MESSAGES_UPSERT carries new inbound/outbound content.
      if (event !== "messages.upsert") return null;

      const data = p["data"] as Record<string, unknown> | undefined;
      if (!data) return null;

      const key = data["key"] as Record<string, unknown> | undefined;
      if (!key) return null;

      const remoteJid = String(key["remoteJid"] ?? "");
      // Groups have @g.us JIDs — not handled here.
      if (remoteJid.endsWith("@g.us")) return null;

      const fromMe = key["fromMe"] === true;
      const messageId = String(key["id"] ?? "");

      // WhatsApp multi-device: when remoteJid is a LID ("<id>@lid"), it is NOT a
      // phone number. The real phone is delivered separately in key.senderPn
      // (inbound) or key.remoteJidAlt. Fall back to remoteJid only as a last resort.
      const senderPn = String(key["senderPn"] ?? "");
      const remoteJidAlt = String(key["remoteJidAlt"] ?? "");
      const phoneSource = remoteJid.endsWith("@lid")
        ? (senderPn || remoteJidAlt || remoteJid)
        : remoteJid;

      // normalizePhoneNumber strips @s.whatsapp.net and normalises DDI.
      const from = normalizePhoneNumber(phoneSource);
      if (!from) return null;

      const senderName = String(data["pushName"] ?? "") || null;

      const msgObj = data["message"] as Record<string, unknown> | undefined;
      if (!msgObj) return null;

      let text: string | null = null;
      let messageType: IncomingMessageEvent["messageType"] = "text";
      let mediaUrl: string | null = null;

      const imgMsg = msgObj["imageMessage"] as Record<string, unknown> | undefined;
      const audMsg = msgObj["audioMessage"] as Record<string, unknown> | undefined;
      const vidMsg = msgObj["videoMessage"] as Record<string, unknown> | undefined;
      const docMsg = msgObj["documentMessage"] as Record<string, unknown> | undefined;

      if (imgMsg) {
        messageType = "image";
        text = String(imgMsg["caption"] ?? "") || null;
        mediaUrl = String(imgMsg["url"] ?? imgMsg["mediaUrl"] ?? "") || null;
      } else if (audMsg) {
        messageType = "audio";
        mediaUrl = String(audMsg["url"] ?? audMsg["mediaUrl"] ?? "") || null;
      } else if (vidMsg) {
        messageType = "video";
        text = String(vidMsg["caption"] ?? "") || null;
        mediaUrl = String(vidMsg["url"] ?? vidMsg["mediaUrl"] ?? "") || null;
      } else if (docMsg) {
        messageType = "document";
        text = String(docMsg["caption"] ?? docMsg["fileName"] ?? "") || null;
        mediaUrl = String(docMsg["url"] ?? docMsg["mediaUrl"] ?? "") || null;
      } else {
        const raw =
          msgObj["conversation"] ??
          (msgObj["extendedTextMessage"] as Record<string, unknown> | undefined)?.["text"] ??
          "";
        text = String(raw).trim() || null;
      }

      // Evolution timestamps are in seconds; convert to ms.
      const ts = data["messageTimestamp"];
      const timestamp = typeof ts === "number" ? ts * 1000 : Date.now();

      return { from, messageId, fromMe, text, messageType, mediaUrl, senderName, timestamp };
    } catch {
      return null;
    }
  }
}

export { EVOLUTION_STATUS_MAP };
