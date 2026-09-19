// Contrato provider-agnóstico do e-mail recebido.
//
// POR QUE ISSO EXISTE: a rota de entrada ainda não está decidida (provedor de inbound,
// Worker Cloudflare ou IMAP — ver plans/marineflow-email-agente.md §3). Todo o resto do
// sistema fala com ESTE shape, e cada canal ganha um adaptador fino que converte o payload
// dele para cá. Trocar de canal = reescrever um adaptador, não o sistema.
// Mesmo padrão de camada trocável já usado em _shared/fiscal.

/** Endereço de e-mail já separado em nome + endereço. */
export interface EmailAddress {
  name: string | null;
  address: string;
}

export interface EmailAttachmentInput {
  filename: string | null;
  mimeType: string | null;
  size: number | null;
  /** Conteúdo bruto. Só é lido para anexos pequenos e de tipo conhecido (XML). */
  content?: Uint8Array | null;
}

/** Um e-mail recebido, normalizado pelo adaptador do canal. */
export interface InboundEmail {
  /** Message-ID do RFC 5322, sem os <>. Pode faltar em remetentes malcomportados. */
  messageId: string | null;
  inReplyTo: string | null;
  references: string[];
  from: EmailAddress;
  to: EmailAddress[];
  cc: EmailAddress[];
  subject: string | null;
  text: string | null;
  html: string | null;
  receivedAt: string;
  /** Cabeçalhos crus que importam para triagem determinística e para auditoria. */
  headers: Record<string, string>;
  attachments: EmailAttachmentInput[];
  rawSize: number | null;
}

export type AttachmentKind = "nfe_xml" | "boleto_pdf" | "danfe" | "imagem" | "planilha" | "outro";

/** Resultado do pré-filtro determinístico (roda ANTES de gastar LLM). */
export interface PreClassification {
  /** Quando true, o e-mail é ruído comprovado por cabeçalho — não vai para o modelo. */
  isBulk: boolean;
  /** Resposta automática (férias, no-reply). Nunca merece resposta nossa. */
  isAutoReply: boolean;
  /** Motivo legível, para auditoria e para explicar ao usuário por que sumiu. */
  reason: string | null;
}
