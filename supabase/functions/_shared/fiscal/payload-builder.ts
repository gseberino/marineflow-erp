// Pure functions that turn UI-friendly input into the Contora NF-e draft
// payload (see https://fiscal.contora.com.br/documentacao/nfe). No fetch, no
// Deno APIs — safe to unit test under Vitest as well as run under Deno.

export const PAYMENT_METHODS = [
  { value: "01", label: "Dinheiro" },
  { value: "03", label: "Cartão de Crédito" },
  { value: "04", label: "Cartão de Débito" },
  { value: "05", label: "Crédito Loja" },
  { value: "15", label: "Boleto Bancário" },
  { value: "17", label: "PIX" },
  { value: "99", label: "Outros" },
] as const;

export const DEFAULT_CFOP = "5102"; // venda de mercadoria adquirida/recebida de terceiros

// Catálogo de Natureza de Operação. "Natureza" em si é texto livre (não
// padronizado), mas cada uma corresponde a um CFOP-base diferente — isso sim
// é regulado. baseCfopCode é o sufixo de 3 dígitos comum às 4 variações
// (mesmo estado/outro estado × saída/entrada); o dígito inicial (1/2/5/6) é
// calculado em computeCfop() a partir da UF do emitente x UF da contraparte.
export interface NatureOfOperationOption {
  value: string;
  label: string;
  natureOperation: string;
  baseCfopCode: string;
  operationType: "saida" | "entrada";
}

export const NATURE_OF_OPERATION_OPTIONS: NatureOfOperationOption[] = [
  {
    value: "venda",
    label: "Venda de mercadoria",
    natureOperation: "Venda de mercadoria",
    baseCfopCode: "102",
    operationType: "saida",
  },
  {
    value: "devolucao_compra",
    label: "Devolução ao fornecedor (compra)",
    natureOperation: "Devolução de compra",
    baseCfopCode: "202",
    operationType: "saida",
  },
  {
    value: "remessa_conserto",
    label: "Remessa para conserto/reparo",
    natureOperation: "Remessa para conserto ou reparo",
    baseCfopCode: "915",
    operationType: "saida",
  },
  {
    value: "remessa_bonificacao",
    label: "Remessa em bonificação, doação ou brinde",
    natureOperation: "Remessa em bonificação, doação ou brinde",
    baseCfopCode: "910",
    operationType: "saida",
  },
  {
    value: "remessa_demonstracao",
    label: "Remessa para demonstração",
    natureOperation: "Remessa de mercadoria para demonstração",
    baseCfopCode: "912",
    operationType: "saida",
  },
  {
    value: "devolucao_venda",
    label: "Devolução recebida do cliente",
    natureOperation: "Devolução de venda de mercadoria",
    baseCfopCode: "202",
    operationType: "entrada",
  },
];

export function findNatureOfOperation(value: string | undefined | null): NatureOfOperationOption {
  return NATURE_OF_OPERATION_OPTIONS.find((o) => o.value === value) ?? NATURE_OF_OPERATION_OPTIONS[0];
}

// CFOP muda o primeiro dígito conforme a operação circula dentro do mesmo
// estado ou entre estados diferentes: saída = 5xxx (mesmo estado) / 6xxx
// (outro estado); entrada = 1xxx (mesmo estado) / 2xxx (outro estado). Os
// outros 3 dígitos (baseCfopCode) identificam o tipo de operação e não mudam.
export function computeCfop(
  baseCfopCode: string,
  operationType: "saida" | "entrada",
  companyStateCode: string | null | undefined,
  counterpartStateCode: string | null | undefined,
): string {
  const sameState = !!companyStateCode && !!counterpartStateCode &&
    companyStateCode.trim().toUpperCase() === counterpartStateCode.trim().toUpperCase();
  const prefix = operationType === "entrada"
    ? (sameState ? "1" : "2")
    : (sameState ? "5" : "6");
  return `${prefix}${baseCfopCode}`;
}

export interface NfeAddressInput {
  street: string;
  number: string;
  complement?: string | null;
  district: string;
  cityName: string;
  cityCode: string; // IBGE — resolved server-side, see ibge.ts
  stateCode: string;
  postalCode: string;
}

export interface NfeRecipientInput {
  name: string;
  document: string; // CPF or CNPJ, any formatting
  email?: string | null;
  address: NfeAddressInput;
}

export interface NfeItemInput {
  code: string;
  name: string;
  ncm: string;
  cfop?: string | null;
  unit?: string | null;
  quantity: number;
  unitPrice: number;
}

export interface BuildNfePayloadInput {
  natureOperation?: string;
  operationType?: "saida" | "entrada"; // default "saida" (venda) — "entrada" p/ devolução recebida do cliente
  recipient: NfeRecipientInput;
  items: NfeItemInput[];
  paymentMethod: string;
  consumerFinal?: boolean;
}

function onlyDigits(s: string | null | undefined): string {
  return (s ?? "").replace(/\D/g, "");
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export function buildNfeDraftPayload(
  input: BuildNfePayloadInput,
): Record<string, unknown> {
  const documentDigits = onlyDigits(input.recipient.document);
  const totalAmount = round2(
    input.items.reduce((sum, it) => sum + it.quantity * it.unitPrice, 0),
  );

  return {
    nature_operation: input.natureOperation ?? "Venda de mercadoria",
    operation_type: input.operationType ?? "saida",
    // CPF (11 dígitos) só existe para pessoa física — tratamos como consumidor
    // final por padrão; CNPJ (revenda/empresa) por padrão não é consumidor final.
    consumer_final: input.consumerFinal ?? documentDigits.length === 11,
    presence_indicator: 1, // operação presencial — ajustar se a operação for remota
    recipient: {
      name: input.recipient.name,
      document: documentDigits,
      // 9 = não contribuinte do ICMS. Simplificação segura para o piloto:
      // o MarineFlow ainda não coleta a Inscrição Estadual do cliente.
      state_registration_indicator: 9,
      email: input.recipient.email || undefined,
      address: {
        street: input.recipient.address.street,
        number: input.recipient.address.number || "S/N",
        complement: input.recipient.address.complement || undefined,
        district: input.recipient.address.district,
        city_name: input.recipient.address.cityName,
        city_code: input.recipient.address.cityCode,
        state_code: input.recipient.address.stateCode,
        postal_code: onlyDigits(input.recipient.address.postalCode),
      },
    },
    items: input.items.map((it) => ({
      code: it.code,
      name: it.name,
      ncm: onlyDigits(it.ncm),
      cfop: it.cfop || DEFAULT_CFOP,
      unit: it.unit || "UN",
      quantity: it.quantity,
      unit_price: it.unitPrice,
    })),
    payments: [{ method: input.paymentMethod, amount: totalAmount }],
  };
}

// Validates the input before spending a fiscal-event quota unit on the
// provider. Returns a list of human-readable (pt-BR) error messages; empty
// array means the input is ready to submit.
export function validateNfeDraftInput(input: BuildNfePayloadInput): string[] {
  const errors: string[] = [];
  const r = input.recipient;
  const addr = r?.address;

  if (!r?.name?.trim()) errors.push("Nome do destinatário é obrigatório.");
  const documentDigits = onlyDigits(r?.document);
  if (!documentDigits) {
    errors.push("CPF/CNPJ do destinatário é obrigatório.");
  } else if (documentDigits.length !== 11 && documentDigits.length !== 14) {
    errors.push("CPF/CNPJ do destinatário deve ter 11 (CPF) ou 14 (CNPJ) dígitos.");
  }
  if (!addr?.street?.trim()) errors.push("Logradouro é obrigatório.");
  if (!addr?.district?.trim()) errors.push("Bairro é obrigatório.");
  if (!addr?.cityName?.trim()) errors.push("Cidade é obrigatória.");
  if (!addr?.cityCode?.trim()) {
    errors.push("Código IBGE do município não foi resolvido — confira UF e cidade.");
  }
  if (!addr?.stateCode?.trim()) errors.push("UF é obrigatória.");
  if (!onlyDigits(addr?.postalCode)) errors.push("CEP é obrigatório.");

  if (!input.items?.length) {
    errors.push("Adicione pelo menos um item.");
  } else {
    input.items.forEach((it, i) => {
      const n = i + 1;
      if (!it.name?.trim()) errors.push(`Item ${n}: descrição é obrigatória.`);
      if (!onlyDigits(it.ncm)) errors.push(`Item ${n}: NCM é obrigatório.`);
      if (!(it.quantity > 0)) errors.push(`Item ${n}: quantidade deve ser maior que zero.`);
      if (!(it.unitPrice > 0)) errors.push(`Item ${n}: valor unitário deve ser maior que zero.`);
    });
  }

  if (!input.paymentMethod) errors.push("Forma de pagamento é obrigatória.");

  return errors;
}
