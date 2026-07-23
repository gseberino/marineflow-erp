// Pure functions that turn UI-friendly input into the Contora NF-e draft
// payload (see https://fiscal.contora.com.br/documentacao/nfe). No fetch, no
// Deno APIs — safe to unit test under Vitest as well as run under Deno.
import {
  cleanText,
  isValidCep,
  isValidCfop,
  isValidNcm,
  NFE_LIMITS,
  resolveGtin,
  roundTo,
} from "./nfe-sanitize.ts";

// Formas de pagamento (tPag da NF-e). Lista alinhada ao leiaute 4.00, focada no
// que um B2B náutico usa (sem os vales alimentação/refeição, raros aqui).
export const PAYMENT_METHODS = [
  { value: "01", label: "Dinheiro" },
  { value: "02", label: "Cheque" },
  { value: "03", label: "Cartão de Crédito" },
  { value: "04", label: "Cartão de Débito" },
  { value: "05", label: "Crédito Loja" },
  { value: "15", label: "Boleto Bancário" },
  { value: "16", label: "Depósito Bancário" },
  { value: "17", label: "PIX" },
  { value: "18", label: "Transferência bancária / Carteira digital" },
  { value: "90", label: "Sem Pagamento" },
  { value: "99", label: "Outros" },
] as const;

// tPag=90 (Sem Pagamento): usado quando não há transação financeira na nota —
// devoluções e remessas (conserto, bonificação, doação, demonstração). Enviar
// forma de pagamento real nesses casos gera a Rejeição 871.
export const NO_PAYMENT_METHOD = "90";

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
  // true só para operações com transação financeira (venda). Devolução e
  // remessas não têm pagamento → tPag=90 (Sem Pagamento), senão Rejeição 871.
  hasPayment: boolean;
}

export const NATURE_OF_OPERATION_OPTIONS: NatureOfOperationOption[] = [
  {
    value: "venda",
    label: "Venda de mercadoria",
    natureOperation: "Venda de mercadoria",
    baseCfopCode: "102",
    operationType: "saida",
    purpose: 1,
    hasPayment: true,
  },
  {
    value: "devolucao_compra",
    label: "Devolução ao fornecedor (compra)",
    natureOperation: "Devolução de compra",
    baseCfopCode: "202",
    operationType: "saida",
    purpose: 4,
    requiresReference: true,
    hasPayment: false,
  },
  {
    value: "remessa_conserto",
    label: "Remessa para conserto/reparo",
    natureOperation: "Remessa para conserto ou reparo",
    baseCfopCode: "915",
    operationType: "saida",
    purpose: 1,
    hasPayment: false,
  },
  {
    value: "remessa_bonificacao",
    label: "Remessa em bonificação, doação ou brinde",
    natureOperation: "Remessa em bonificação, doação ou brinde",
    baseCfopCode: "910",
    operationType: "saida",
    purpose: 1,
    hasPayment: false,
  },
  {
    value: "remessa_demonstracao",
    label: "Remessa para demonstração",
    natureOperation: "Remessa de mercadoria para demonstração",
    baseCfopCode: "912",
    operationType: "saida",
    purpose: 1,
    hasPayment: false,
  },
  {
    value: "devolucao_venda",
    label: "Devolução recebida do cliente",
    natureOperation: "Devolução de venda de mercadoria",
    baseCfopCode: "202",
    operationType: "entrada",
    purpose: 4,
    requiresReference: true,
    hasPayment: false,
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
  // Desconto do item (prod/vDesc). Reduz o valor do item e, portanto, o total
  // da nota (vNF = vProd − vDesc). Campo `discount` confirmado no contrato da
  // Contora (NfeItem.discount → det/prod/vDesc).
  discount?: number | null;
  // Outras despesas acessórias do item (prod/vOutro). SOMAM ao total
  // (vNF = vProd − vDesc + vOutro). Campo `other_expenses` da Contora — usado na
  // devolução ao fornecedor do Simples para repassar o IPI da nota de compra.
  otherExpenses?: number | null;
  barcode?: string | null; // GTIN/EAN do produto → cEAN/cEANTrib ("SEM GTIN" se ausente)
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
  // Referência por item à NF-e original (devolução) — grupo DFeReferenciado da
  // regra VC02-14: chaveAcesso (44 díg.) + nItem da original. Obrigatório em
  // homologação desde 01/07/2026 e em produção a partir de 01/09/2026.
  referencedKey?: string | null;
  referencedItemNumber?: number | null;
}

// Parcela a prazo → vira uma duplicata do grupo cobr (nDup/dVenc/vDup).
export interface NfeInstallmentInput {
  dueDate: string; // vencimento YYYY-MM-DD
  amount: number; // valor da parcela
}

export interface BuildNfePayloadInput {
  natureOperation?: string;
  operationType?: "saida" | "entrada"; // default "saida" (venda) — "entrada" p/ devolução recebida do cliente
  purpose?: number; // finalidade (Contora: campo `purpose`): 1=normal, 2=complementar, 3=ajuste, 4=devolução
  referencedAccessKey?: string | null; // chave da NF-e original (devolução) — enviada só se informada
  recipient: NfeRecipientInput;
  items: NfeItemInput[];
  paymentMethod: string;
  noPayment?: boolean; // true p/ devolução/remessa → tPag=90 (Sem Pagamento), valor 0
  // Venda a prazo (parcelada) → grupo de cobrança (cobr = fatura + duplicatas).
  // Vazio/ausente = à vista (pagamento único). Ver buildNfeDraftPayload.
  installments?: NfeInstallmentInput[] | null;
  invoiceNumber?: string | null; // nFat (número da fatura) — default "1" quando há duplicatas
  // Pedido de compra do CLIENTE, no nível da nota (grupo "compra" da NF-e).
  // A Contora recomenda este caminho quando há um único pedido para a nota
  // inteira; os campos por item (det/prod/xPed) seguem disponíveis para quando
  // cada produto precisar de referência própria.
  purchaseOrder?: string | null;
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
    // CST "49" (Outras Operações de Saída) — valor com o qual a 1ª NF-e do HBR
    // foi autorizada. "99" é uma alternativa recomendada p/ Simples; deixamos
    // configurável em app_settings (default_pis_cst/default_cofins_cst) para a
    // contadora escolher, sem trocar o que já funciona.
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
  // vProd (bruto) = soma de qtd × preço. O desconto por item entra depois.
  const grossAmount = round2(
    input.items.reduce((sum, it) => sum + it.quantity * it.unitPrice, 0),
  );
  const totalDiscount = round2(
    input.items.reduce((sum, it) => sum + Math.max(0, Number(it.discount) || 0), 0),
  );
  // Outras despesas acessórias (vOutro) somam ao total. Na devolução do Simples,
  // carregam o IPI da nota de compra que precisa entrar no total sem destaque.
  const totalOther = round2(
    input.items.reduce((sum, it) => sum + Math.max(0, Number(it.otherExpenses) || 0), 0),
  );
  // vNF = vProd − vDesc + vOutro. É o valor que precisa fechar com a soma dos
  // pagamentos/duplicatas (sem IPI destacado: Simples).
  const totalAmount = round2(grossAmount - totalDiscount + totalOther);

  // Indicador de IE do destinatário (indIEDest): 1=contribuinte, 2=isento, 9=não
  // contribuinte. Default 9 mantém o comportamento antigo; a UI passa a informar.
  const ieIndicator = input.recipient.stateRegistrationIndicator ?? 9;
  const cleanEmail = cleanText(input.recipient.email, NFE_LIMITS.email);
  const recipient: Record<string, unknown> = {
    name: cleanText(input.recipient.name, NFE_LIMITS.recipientName),
    document: documentDigits,
    state_registration_indicator: ieIndicator,
    email: cleanEmail || undefined,
    address: {
      street: cleanText(input.recipient.address.street, NFE_LIMITS.street),
      number: cleanText(input.recipient.address.number, NFE_LIMITS.number) || "S/N",
      complement: cleanText(input.recipient.address.complement, NFE_LIMITS.complement) || undefined,
      district: cleanText(input.recipient.address.district, NFE_LIMITS.district),
      city_name: cleanText(input.recipient.address.cityName, NFE_LIMITS.cityName),
      city_code: input.recipient.address.cityCode,
      state_code: input.recipient.address.stateCode,
      postal_code: onlyDigits(input.recipient.address.postalCode),
    },
  };
  // A IE só faz sentido (e é exigida) quando o destinatário é contribuinte.
  const ie = onlyDigits(input.recipient.stateRegistration);
  if (ieIndicator === 1 && ie) recipient.state_registration = ie;

  const payload: Record<string, unknown> = {
    nature_operation: cleanText(input.natureOperation ?? "Venda de mercadoria", 60),
    operation_type: input.operationType ?? "saida",
    purpose: input.purpose ?? 1, // 1=normal por padrão; 4=devolução
    // CPF (11 dígitos) só existe para pessoa física — tratamos como consumidor
    // final por padrão; CNPJ (revenda/empresa) por padrão não é consumidor final.
    consumer_final: input.consumerFinal ?? documentDigits.length === 11,
    presence_indicator: input.presenceIndicator ?? 1, // 1=presencial por padrão
    recipient,
    items: input.items.map((it) => {
      const gtin = resolveGtin(it.barcode);
      const item: Record<string, unknown> = {
        code: cleanText(it.code, NFE_LIMITS.itemCode) || "ITEM",
        name: cleanText(it.name, NFE_LIMITS.itemName),
        ncm: onlyDigits(it.ncm),
        cfop: (it.cfop || DEFAULT_CFOP).trim(),
        unit: cleanText(it.unit, NFE_LIMITS.unit) || "UN",
        quantity: roundTo(it.quantity, 4),
        unit_price: roundTo(it.unitPrice, 10),
        // cEAN/cEANTrib são obrigatórios: GTIN válido ou "SEM GTIN".
        cean: gtin,
        cean_trib: gtin,
      };
      const desc = round2(Math.max(0, Number(it.discount) || 0));
      if (desc > 0) item.discount = desc; // → det/prod/vDesc
      const outro = round2(Math.max(0, Number(it.otherExpenses) || 0));
      if (outro > 0) item.other_expenses = outro; // → det/prod/vOutro
      const taxes = buildItemTaxes(it);
      if (taxes) item.taxes = taxes;
      // Referência por item à NF-e original (devolução). Nome exato do campo na
      // Contora a confirmar — usamos `referenced_document: {access_key, item}`,
      // que mapeia direto para DFeReferenciado (chaveAcesso + nItem).
      const refKeyItem = onlyDigits(it.referencedKey);
      if (refKeyItem && it.referencedItemNumber && it.referencedItemNumber > 0) {
        item.referenced_document = { access_key: refKeyItem, item: it.referencedItemNumber };
      }
      return item;
    }),
    // Devolução/remessa não têm transação financeira → tPag=90 (Sem Pagamento)
    // com valor 0. Enviar forma de pagamento real gera Rejeição 871.
    payments: input.noPayment
      ? [{ method: NO_PAYMENT_METHOD, amount: 0 }]
      : [{ method: input.paymentMethod, amount: totalAmount }],
  };

  // Grupo de cobrança (cobr = fatura + duplicatas) — só em venda a prazo
  // (parcelada). A Contora exige (doc NF-e modelo 55):
  //   payments com method "14" (Duplicata Mercantil) + indicator 1 (a prazo)
  //   somando o net_amount; a soma das duplicatas = net_amount;
  //   net_amount = original_amount - discount_amount; parcelas numeradas
  //   001,002…; até 120; vencimentos YYYY-MM-DD, não anteriores à emissão e em
  //   ordem crescente. net_amount = totalAmount, que já é o LÍQUIDO (vProd menos
  //   os descontos por item).
  const parcels = (input.noPayment ? [] : (input.installments ?? []))
    .filter((p) => p && p.dueDate && p.amount > 0);
  if (parcels.length) {
    const net = totalAmount;
    // A soma das duplicatas DEVE bater exatamente com net_amount — a diferença
    // de centavos do arredondamento vai na última parcela.
    const rounded = parcels.map((p) => round2(p.amount));
    const drift = round2(net - rounded.reduce((s, v) => s + v, 0));
    const duplicates = parcels.map((p, i) => ({
      number: String(i + 1).padStart(3, "0"),
      due_date: p.dueDate,
      amount: i === parcels.length - 1 ? round2(rounded[i] + drift) : rounded[i],
    }));
    // Fatura FIEL ao desconto: valor original = bruto + despesas acessórias (antes
    // do desconto), desconto = vDesc, líquido = vNF. A Contora exige net_amount =
    // original_amount − discount_amount (satisfeito: net = (net+vDesc) − vDesc) e a
    // soma das duplicatas = net (inalterado). Sem desconto, original = net e
    // discount = 0 (comportamento anterior preservado). Assim o quadro "Fatura" do
    // espelho/DANFE bate com o quadro "Totais" (mesmo desconto nos dois lugares).
    const invoiceDiscount = totalDiscount;
    const invoiceOriginal = round2(net + invoiceDiscount);
    payload.billing = {
      invoice: {
        number: cleanText(input.invoiceNumber, 60) || "1",
        original_amount: invoiceOriginal,
        discount_amount: invoiceDiscount,
        net_amount: net,
      },
      installments: duplicates,
    };
    // pag: Duplicata Mercantil (14), a prazo (indicator 1), somando o net_amount.
    payload.payments = [{ method: "14", indicator: 1, amount: net }];
  }

  // refNFe (nota inteira): além da referência por item acima, mandamos também a
  // lista de chaves no nível da nota — cobre o caso "total" e provedores que só
  // leem a referência agregada. Reúne a chave informada + as chaves por item.
  const noteKeys = new Set<string>();
  const topKey = onlyDigits(input.referencedAccessKey);
  if (topKey) noteKeys.add(topKey);
  for (const it of input.items) {
    const k = onlyDigits(it.referencedKey);
    if (k) noteKeys.add(k);
  }
  if (noteKeys.size) payload.referenced_access_keys = [...noteKeys];

  // Grupo "compra" da NF-e: purchase.order -> compra/xPed (mapeamento confirmado
  // pela Contora). Fica só no XML — o layout padrão do DANFE não imprime esses
  // campos, mas o sistema do cliente consegue ler o pedido automaticamente.
  const purchaseOrder = cleanText(input.purchaseOrder, NFE_LIMITS.purchaseOrder);
  if (purchaseOrder) payload.purchase = { order: purchaseOrder };

  const info = cleanText(input.additionalInfo, NFE_LIMITS.additionalInfo);
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
  if (!onlyDigits(addr?.postalCode)) {
    errors.push("CEP é obrigatório.");
  } else if (!isValidCep(addr?.postalCode)) {
    errors.push("CEP deve ter 8 dígitos.");
  }

  if (!input.items?.length) {
    errors.push("Adicione pelo menos um item.");
  } else {
    input.items.forEach((it, i) => {
      const n = i + 1;
      if (!it.name?.trim()) errors.push(`Item ${n}: descrição é obrigatória.`);
      if (!onlyDigits(it.ncm)) {
        errors.push(`Item ${n}: NCM é obrigatório.`);
      } else if (!isValidNcm(it.ncm)) {
        errors.push(`Item ${n}: NCM deve ter 8 dígitos.`);
      }
      if (!isValidCfop(it.cfop)) errors.push(`Item ${n}: CFOP deve ter 4 dígitos.`);
      if (!(it.quantity > 0)) errors.push(`Item ${n}: quantidade deve ser maior que zero.`);
      if (!(it.unitPrice > 0)) errors.push(`Item ${n}: valor unitário deve ser maior que zero.`);
      // Desconto não pode passar do valor bruto do item (senão vDesc > vProd,
      // rejeição na SEFAZ e total negativo).
      const desc = Number(it.discount) || 0;
      if (desc < 0) errors.push(`Item ${n}: desconto não pode ser negativo.`);
      else if (desc > round2(it.quantity * it.unitPrice) + 0.005) {
        errors.push(`Item ${n}: desconto (${desc.toFixed(2)}) maior que o valor do item.`);
      }
      if ((Number(it.otherExpenses) || 0) < 0) errors.push(`Item ${n}: despesas acessórias não podem ser negativas.`);
    });
  }

  if (!input.paymentMethod) errors.push("Forma de pagamento é obrigatória.");

  // Parcelas (duplicatas) — regras da Contora/SEFAZ: vencimentos não anteriores
  // à emissão, em ordem crescente, valor > 0 e no máximo 120 parcelas.
  const parcels = input.noPayment ? [] : (input.installments ?? []);
  if (parcels.length) {
    if (parcels.length > 120) errors.push("Máximo de 120 parcelas (duplicatas).");
    // "Hoje" no fuso de Brasília (UTC-3; o Brasil não tem horário de verão desde
    // 2019). A edge function roda em UTC: usar a data UTC recusaria por engano um
    // vencimento para HOJE em emissões feitas depois das 21h, quando o UTC já
    // virou o dia seguinte.
    const today = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
    let prev = "";
    parcels.forEach((p, i) => {
      const n = i + 1;
      if (!p?.dueDate) {
        errors.push(`Parcela ${n}: vencimento é obrigatório.`);
      } else {
        if (p.dueDate < today) errors.push(`Parcela ${n}: vencimento não pode ser anterior à data de emissão.`);
        if (prev && p.dueDate < prev) errors.push(`Parcela ${n}: vencimentos devem estar em ordem crescente.`);
        prev = p.dueDate;
      }
      if (!(p?.amount > 0)) errors.push(`Parcela ${n}: valor deve ser maior que zero.`);
    });
  }

  return errors;
}
