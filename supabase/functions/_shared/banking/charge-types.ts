// Contrato de emissão de cobrança — a camada trocável entre o ERP e o banco.
//
// Mesmo desenho que deu certo no fiscal (`_shared/fiscal`): o ERP fala com esta interface,
// nunca com o banco direto. Trocar C6 por Asaas, Inter ou Cora vira escrever um arquivo
// novo, não reescrever o financeiro. Isso importa porque a escolha do banco é comercial e
// muda com mais frequência do que o código.

export interface ChargeInput {
  /** Valor a cobrar. */
  amount: number;
  dueDate: string; // YYYY-MM-DD
  /** Some no boleto e no extrato do cliente. */
  description: string;
  payer: {
    name: string;
    /** CPF ou CNPJ, só dígitos. */
    document: string;
    email?: string | null;
    address?: {
      street?: string | null;
      number?: string | null;
      complement?: string | null;
      district?: string | null;
      city?: string | null;
      state?: string | null;
      zipCode?: string | null;
    } | null;
  };
  /** Nosso identificador, devolvido pelo banco nos eventos — é o que liga o retorno ao ERP. */
  externalReference: string;
  kind: "boleto" | "pix" | "bolepix";
  /** Instruções impressas no boleto (juros, multa, "não receber após..."). */
  instructions?: string[];
  fine?: { percent?: number; amount?: number } | null;
  interestPerMonth?: { percent?: number; amount?: number } | null;
  discount?: { amount: number; untilDate: string } | null;
}

export interface ChargeResult {
  /** Identificador da cobrança no banco. */
  providerChargeId: string;
  status: "pending" | "registered" | "failed";
  digitableLine?: string | null;
  barcode?: string | null;
  pixCopyPaste?: string | null;
  pixQrBase64?: string | null;
  pdfUrl?: string | null;
  /** Resposta crua, guardada para investigar divergência depois. */
  raw: unknown;
}

/** Evento de mudança de estado vindo do banco (webhook ou consulta). */
export interface ChargeStatusEvent {
  providerChargeId: string;
  externalReference?: string | null;
  status: "pending" | "registered" | "paid" | "overdue" | "cancelled" | "failed";
  paidAmount?: number | null;
  paidAt?: string | null;
  /** Presente quando o pagamento foi por Pix — casa direto com a linha do extrato. */
  pixEndToEndId?: string | null;
  raw: unknown;
}

/**
 * O que qualquer banco precisa saber fazer para o ERP cobrar por ele.
 *
 * Propositalmente pequeno: emitir, consultar, cancelar e interpretar o retorno. Recursos
 * exclusivos de um banco ficam dentro do provider, não vazam para o ERP.
 */
export interface ChargeProvider {
  readonly name: string;
  createCharge(input: ChargeInput): Promise<ChargeResult>;
  getCharge(providerChargeId: string): Promise<ChargeStatusEvent>;
  cancelCharge(providerChargeId: string): Promise<void>;
  /**
   * Valida e interpreta um webhook. Devolve null quando a requisição não é autêntica —
   * quem chama deve tratar null como 401, nunca como "nada aconteceu".
   */
  parseWebhook(headers: Record<string, string>, rawBody: string): Promise<ChargeStatusEvent[] | null>;
}

/**
 * Credenciais do C6.
 *
 * O certificado é obrigatório: a API exige mTLS, e o par (.crt/.key) só pode ser baixado
 * no momento em que a chave é criada no Web Banking — não há como recuperá-lo depois.
 * Guardar em Supabase secrets, em base64, nunca no repositório.
 */
export interface C6Credentials {
  clientId: string;
  clientSecret: string;
  /** Conteúdo PEM do certificado (.crt). */
  certPem: string;
  /** Conteúdo PEM da chave privada (.key). */
  keyPem: string;
  /** Chave Pix da conta, usada nas cobranças com QR. */
  pixKey?: string | null;
  /** Ambiente: sandbox durante a homologação, produção depois. */
  sandbox: boolean;
}
