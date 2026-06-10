import type {
  WhatsAppProvider,
  SendResult,
  IncomingMessageEvent,
} from "./types.ts";
import { normalizePhoneNumber } from "./normalize.ts";

export interface ZapiConfig {
  instanceId: string;
  token: string;
  clientToken?: string | null;
}

const IGNORED_TYPES = new Set([
  "PresenceChatCallback",
  "ChatStateCallback",
  "PresenceCallback",
  "ChatPresence",
  "Presence",
  "typing",
  "recording",
  "MessageStatusCallback",
  "MessageStatus",
]);

export class ZapiProvider implements WhatsAppProvider {
  private readonly base: string;
  private readonly headers: Record<string, string>;

  constructor(config: ZapiConfig) {
    this.base =
      `https://api.z-api.io/instances/${config.instanceId}/token/${config.token}`;
    this.headers = { "Content-Type": "application/json" };
    if (config.clientToken) this.headers["Client-Token"] = config.clientToken;
  }

  private async post(
    path: string,
    payload: unknown,
  ): Promise<SendResult> {
    try {
      const res = await fetch(`${this.base}/${path}`, {
        method: "POST",
        headers: this.headers,
        body: JSON.stringify(payload),
      });
      const body = (await res.json().catch(() => ({}))) as Record<
        string,
        unknown
      >;
      if (res.ok && !body["error"]) {
        return {
          ok: true,
          providerMessageId: String(
            body["messageId"] ?? body["id"] ?? "",
          ),
        };
      }
      return {
        ok: false,
        error: String(body["error"] ?? `HTTP ${res.status}`),
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
    return this.post("send-text", {
      phone: normalizePhoneNumber(to),
      message,
    });
  }

  async sendLink(
    to: string,
    message: string,
    linkUrl: string,
    title?: string,
    description?: string,
    imageUrl?: string,
  ): Promise<SendResult> {
    const payload: Record<string, unknown> = {
      phone: normalizePhoneNumber(to),
      message,
      linkUrl,
      title: title ?? "",
      linkDescription: description ?? "",
    };
    if (imageUrl) payload["image"] = imageUrl;
    return this.post("send-link", payload);
  }

  async sendDocument(
    to: string,
    fileUrl: string,
    fileName: string,
    caption?: string,
  ): Promise<SendResult> {
    return this.post("send-document/pdf", {
      phone: normalizePhoneNumber(to),
      document: fileUrl,
      fileName,
      caption: caption ?? "",
    });
  }

  async checkNumberExists(to: string): Promise<boolean> {
    try {
      const phone = normalizePhoneNumber(to);
      const res = await fetch(`${this.base}/phone-exists/${phone}`, {
        headers: this.headers,
      });
      if (!res.ok) return false;
      const body = (await res.json().catch(() => ({}))) as Record<
        string,
        unknown
      >;
      return body["exists"] === true;
    } catch {
      return false;
    }
  }

  parseIncomingWebhook(payload: unknown): IncomingMessageEvent | null {
    try {
      const p = payload as Record<string, unknown>;
      const type = String((p["type"] ?? p["event"]) ?? "");

      // Status callbacks and presence events are not message events.
      // MessageStatusCallback is handled separately in the webhook handler.
      if (IGNORED_TYPES.has(type)) return null;
      if (p["isGroup"] === true) return null;

      const fromMe = p["fromMe"] === true;
      const phoneRaw = fromMe
        ? String(p["to"] ?? p["chatId"] ?? p["phone"] ?? "")
        : String(p["phone"] ?? p["chatId"] ?? p["senderLid"] ?? "");
      const from = normalizePhoneNumber(phoneRaw);
      if (!from) return null;

      const messageId = String(p["messageId"] ?? p["id"] ?? "");

      let text: string | null = null;
      let messageType: IncomingMessageEvent["messageType"] = "text";
      let mediaUrl: string | null = null;

      const img = p["image"] as Record<string, unknown> | undefined;
      const aud = p["audio"] as Record<string, unknown> | undefined;
      const vid = p["video"] as Record<string, unknown> | undefined;
      const doc = p["document"] as Record<string, unknown> | undefined;

      if (img) {
        text = String(img["caption"] ?? "") || null;
        messageType = "image";
        mediaUrl = String(img["imageUrl"] ?? img["url"] ?? "") || null;
      } else if (aud) {
        messageType = "audio";
        mediaUrl = String(aud["audioUrl"] ?? aud["url"] ?? "") || null;
      } else if (vid) {
        text = String(vid["caption"] ?? "") || null;
        messageType = "video";
        mediaUrl = String(vid["videoUrl"] ?? vid["url"] ?? "") || null;
      } else if (doc) {
        text = String(doc["caption"] ?? "") || null;
        messageType = "document";
        mediaUrl = String(doc["documentUrl"] ?? doc["url"] ?? "") || null;
      } else {
        const msg = p["message"] as Record<string, unknown> | undefined;
        const textObj = p["text"] as
          | Record<string, unknown>
          | string
          | undefined;
        const raw =
          (typeof textObj === "object" ? textObj?.["message"] : textObj) ??
          msg?.["conversation"] ??
          (msg?.["extendedTextMessage"] as Record<string, unknown>)?.["text"] ??
          p["body"] ??
          p["caption"] ??
          "";
        text = String(raw).trim() || null;
      }

      return {
        from,
        messageId,
        fromMe,
        text,
        messageType,
        mediaUrl,
        senderName:
          String(p["senderName"] ?? p["notifyName"] ?? "") || null,
        timestamp: Date.now(),
      };
    } catch {
      return null;
    }
  }
}
