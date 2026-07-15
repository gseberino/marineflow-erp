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
  // finalidade da NF-e (Contora: `purpose`): 1=normal, 4=devolução. As remessas
  // são finalidade normal (1) — o que muda nelas é o CFOP, não a finalidade.
  purpose: number;
  // quando true, a UI deve pedir a chave da NF-e original (refNFe).
  requiresReference?: boolean;
}

export const NATURE_OF_OPERATION_OPTIONS: NatureOfOperationOption[] = [
  {
    value: "venda",
    label: "Venda de mercadoria",
    natureOperation: "Venda de mercadoria",
    baseCfopCode: "102",
    operationType: "saida",
    purpose: 1,
  },
  {
    value: "devolucao_compra",
    label: "Devolução ao fornecedor (compra)",
    natureOperation: "Devolução de compra",
    baseCfopCode: "202",
    operationType: "saida",
    purpose: 4,
    requiresReference: true,
  },
  {
    value: "remessa_conserto",
    label: "Remessa para conserto/reparo",
    natureOperation: "Remessa para conserto ou reparo",
    baseCfopCode: "915",
    operationType: "saida",
    purpose: 1,
  },
  {
    value: "remessa_bonificacao",
    label: "Remessa em bonificação, doação ou brinde",
    natureOperation: "Remessa em bonificação, doação ou brinde",
    baseCfopCode: "910",
    operationType: "saida",
    purpose: 1,
  },
  {
    value: "remessa_demonstracao",
    label: "Remessa para demonstração",
    natureOperation: "Remessa de mercadoria para demonstração",
    baseCfopCode: "912",
    operationType: "saida",
    purpose: 1,
  },
  {
    value: "devolucao_venda",
    label: "Devolução recebida do cliente",
    natureOperation: "Devolução de venda de mercadoria",
    baseCfopCode: "202",
    operationType: "entrada",
    purpose: 4,
    requiresReference: true,
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
  stateRegistrationIndicator?: number; // indIEDest: 1=contribuinte, 2=isento, 9=não contribuinte
  stateRegistration?: string | null; // IE — obrigatória quando indicador=1
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
  // Grupo tributário resolvido a partir do produto (ver product-fiscal.ts).
  // Quando csosn+origin vêm preenchidos, montamos o bloco `taxes` que a Contora
  // exige para a SEFAZ não rejeitar em produção (215). Todos opcionais para não
  // quebrar chamadas antigas/manuais que ainda não trazem impostos.
  csosn?: string | null; // vira taxes.icms.code
  origin?: number | null; // vira taxes.icms.origin (0-8)
  icmsRate?: number | null; // taxes.icms.aliquot
  pisCst?: string | null; // taxes.pis.code
  pisRate?: number | null; // taxes.pis.aliquot
  cofinsCst?: string | null; // taxes.cofins.code
  cofinsRate?: number | null; // taxes.cofins.aliquot
  ipiCst?: string | null; // taxes.ipi.code (só quando ipiRate > 0)
  ipiRate?: number | null; // taxes.ipi.aliquot
}

export interface BuildNfePayloadInput {
  natureOperation?: string;
  operationType?: "saida" | "entrada"; // default "saida" (venda) — "entrada" p/ devolução recebida do cliente
  purpose?: number; // finalidade (Contora: campo `purpose`): 1=normal, 2=complementar, 3=ajuste, 4=devolução
  referencedAccessKey?: string | null; // chave da NF-e original (devolução) — enviada só se informada
  recipient: NfeRecipientInput;
  items: NfeItemInput[];
  paymentMethod: string;
  consumerFinal?: boolean;
  presenceIndicator?: number; // 0=não se aplica,1=presencial,2=internet,4=domicílio,9=não presencial...
  additionalInfo?: string | null; // informações complementares (infCpl)
}

// Monta o bloco `taxes` de um item no formato da Contora (ver doc de Templates):
//   { icms:{code,origin,aliquot}, pis:{code,aliquot}, cofins:{code,aliquot}, ipi? }
// Retorna undefined quando não há dado tributário suficiente (mantém compat.
// com o fluxo antigo, que não enviava impostos).
export function buildItemTaxes(it: NfeItemInput): Record<string, unknown> | undefined {
  const hasIcms = !!(it.csosn && String(it.csosn).trim());
  if (!hasIcms) return undefined;

  const taxes: Record<string, unknown> = {
    icms: {
      code: String(it.csosn),
      origin: it.origin ?? 0,
      aliquot: it.icmsRate ?? 0,
    },
    pis: {
      code: it.pisCst || "49",
      aliquot: it.pisRate ?? 0,
    },
    cofins: {
      code: it.cofinsCst || "49",
      aliquot: it.cofinsRate ?? 0,
    },
  };
  if ((it.ipiRate ?? 0) > 0) {
    taxes.ipi = { code: it.ipiCst || "99", aliquot: it.ipiRate };
  }
  return taxes;
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

  // Indicador de IE do destinatário (indIEDest): 1=contribuinte, 2=isento, 9=não
  // contribuinte. Default 9 mantém o comportamento antigo; a UI passa a informar.
  const ieIndicator = input.recipient.stateRegistrationIndicator ?? 9;
  const recipient: Record<string, unknown> = {
    name: input.recipient.name,
    document: documentDigits,
    state_registration_indicator: ieIndicator,
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
  };
  // A IE só faz sentido (e é exigida) quando o destinatário é contribuinte.
  const ie = onlyDigits(input.recipient.stateRegistration);
  if (ieIndicator === 1 && ie) recipient.state_registration = ie;

  const payload: Record<string, unknown> = {
    nature_operation: input.natureOperation ?? "Venda de mercadoria",
    operation_type: input.operationType ?? "saida",
    purpose: input.purpose ?? 1, // 1=normal por padrão; 4=devolução
    // CPF (11 dígitos) só existe para pessoa física — tratamos como consumidor
    // final por padrão; CNPJ (revenda/empresa) por padrão não é consumidor final.
    consumer_final: input.consumerFinal ?? documentDigits.length === 11,
    presence_indicator: input.presenceIndicator ?? 1, // 1=presencial por padrão
    recipient,
    items: input.items.map((it) => {
      const item: Record<string, unknown> = {
        code: it.code,
        name: it.name,
        ncm: onlyDigits(it.ncm),
        cfop: it.cfop || DEFAULT_CFOP,
        unit: it.unit || "UN",
        quantity: it.quantity,
        unit_price: it.unitPrice,
      };
      const taxes = buildItemTaxes(it);
      if (taxes) item.taxes = taxes;
      return item;
    }),
    payments: [{ method: input.paymentMethod, amount: totalAmount }],
  };

  // refNFe: chave da NF-e original em devoluções. Enviada só quando informada —
  // o nome do campo ainda precisa ser confirmado com a Contora; usamos
  // `referenced_access_keys` e a SEFAZ/Contora ignoram se não reconhecerem.
  const refKey = onlyDigits(input.referencedAccessKey);
  if (refKey) payload.referenced_access_keys = [refKey];

  const info = (input.additionalInfo ?? "").trim();
  if (info) payload.additional_info = info;

  return payload;
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
  // Destinatário contribuinte do ICMS (indicador de IE = 1) precisa informar a IE,
  // senão a SEFAZ rejeita. Isento (2) e não contribuinte (9) não têm IE.
  if (r?.stateRegistrationIndicator === 1 && !onlyDigits(r?.stateRegistration)) {
    errors.push("Inscrição Estadual do destinatário é obrigatória quando ele é contribuinte do ICMS (indicador 1).");
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
