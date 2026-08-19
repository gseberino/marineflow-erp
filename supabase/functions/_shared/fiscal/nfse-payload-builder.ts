// [F-NFSE-01] Monta e valida o payload de NFS-e no contrato único da Contora.
//
// POR QUE VALIDAR ANTES DE ENVIAR
// Cada tentativa de emissão consome numeração fiscal que não volta, e as rejeições do
// Sistema Nacional chegam por código — "E0712" não diz a ninguém o que fazer. Aqui cada
// regra conhecida vira uma frase que diz o QUE está errado e ONDE se corrige. O que sobrar
// (rejeição que só a prefeitura conhece) volta pelo status, e tudo bem: o objetivo não é
// prever tudo, é não gastar nota com o que já dá para saber daqui.
//
// OS DOIS CAMINHOS
// A NFS-e tem padrão NACIONAL e layout MUNICIPAL, e quem decide é o município, não o regime
// da empresa. Os campos obrigatórios mudam entre os dois — por isso `standard` entra no
// input e não é adivinhado. Confirme em GET /companies/{id}/nfse/health antes da primeira
// emissão.

export type NfseStandard = "nacional" | "municipal";

/** 1 não optante · 2 optante MEI · 3 optante ME/EPP. */
export type SimplesNacionalOption = 1 | 2 | 3;

export interface NfseTakerAddressInput {
  street?: string | null;
  number?: string | null;
  complement?: string | null;
  district?: string | null;
  /** IBGE, 7 dígitos. Resolvido por resolveIbgeCityCode(uf, cidade). */
  cityCode?: string | null;
  cityName?: string | null;
  stateCode?: string | null;
  postalCode?: string | null;
}

export interface NfseTakerInput {
  name?: string | null;
  /** CPF (11) ou CNPJ (14). */
  document?: string | null;
  email?: string | null;
  address?: NfseTakerAddressInput | null;
}

export interface NfseServiceInput {
  description?: string | null;
  /** Nacional: 6 dígitos, obrigatório. */
  nationalTaxCode?: string | null;
  /** Municipal: código do serviço no formato do município. No nacional é informativo. */
  serviceCode?: string | null;
  /** Nacional: opcional, exatamente 3 dígitos. Municipal: código de tributação (ex.: CTISS). */
  municipalTaxCode?: string | null;
  /** Municipal com reforma: NBS, 9 dígitos. */
  nbsCode?: string | null;
  /** Municipal: item da lista da LC 116 (ex.: "1401"). */
  itemListCode?: string | null;
  /** 7 dígitos. */
  cnae?: string | null;
  /** Percentual (5 = 5%). */
  issRate?: number | null;
  issWithheld?: boolean;
  /** Percentual TOTAL de tributos do Simples. Obrigatório para ME/EPP no nacional (E0712). */
  totalTaxRateSn?: number | null;
}

export interface NfseAmountsInput {
  serviceAmount?: number | null;
  /** Quando ausente, é derivado de serviceAmount menos as retenções. */
  netAmount?: number | null;
  /** Retenções federais, quando houver. */
  deductions?: number | null;
  pisAmount?: number | null;
  cofinsAmount?: number | null;
  inssAmount?: number | null;
  irAmount?: number | null;
  csllAmount?: number | null;
}

export interface BuildNfsePayloadInput {
  standard: NfseStandard;
  service: NfseServiceInput;
  taker: NfseTakerInput;
  amounts: NfseAmountsInput;
  series?: number | null;
  number?: number | null;
  /** Regime da empresa: decide se totalTaxRateSn é exigido (E0712). */
  taxRegime?: string | null;
  /** Preenchido só quando o regime cadastrado diverge do cadastro do Simples (E0160). */
  simplesNacionalOption?: SimplesNacionalOption | null;
  /** Inscrição municipal da empresa. Só é enviada quando registrada no CNC (E0120). */
  municipalRegistration?: string | null;
  municipalRegistrationInCnc?: boolean;
}

function onlyDigits(s: string | null | undefined): string {
  return String(s ?? "").replace(/\D/g, "");
}

function round2(n: number): number {
  return Math.round((Number(n) || 0) * 100) / 100;
}

/** ME/EPP no padrão nacional: é este o caso que dispara a exigência do E0712. */
export function ehMeEpp(
  taxRegime: string | null | undefined,
  option: SimplesNacionalOption | null | undefined,
): boolean {
  // A opção explícita VENCE o regime cadastrado — ela existe justamente para os casos em
  // que os dois divergem, e é o cadastro do Simples que vale.
  if (option != null) return option === 3;
  return String(taxRegime ?? "").toLowerCase() === "simples";
}

/**
 * Valida o input ANTES de gastar cota. Devolve mensagens em pt-BR; array vazio = pronto.
 *
 * Cada mensagem cita o código da rejeição que ela evita. Isso não é enfeite: quando a nota
 * for recusada por algo que NÃO está aqui, o código na mensagem é o que permite dizer
 * "essa não é a mesma coisa" em vez de procurar no lugar errado.
 */
export function validateNfseDraftInput(input: BuildNfsePayloadInput): string[] {
  const errors: string[] = [];
  const s = input.service ?? {};
  const t = input.taker ?? {};
  const a = t.address ?? {};
  const amt = input.amounts ?? {};

  // ── Serviço ────────────────────────────────────────────────────────────────
  if (!s.description?.trim()) {
    errors.push("Descrição do serviço é obrigatória.");
  }

  if (input.standard === "nacional") {
    const nacional = onlyDigits(s.nationalTaxCode);
    if (!nacional) {
      errors.push(
        "Código de tributação nacional é obrigatório (6 dígitos). Ele vem da lista do "
        + "Sistema Nacional e NÃO é o código municipal sem os pontos: \"14.01\" corresponde "
        + "a 140101, não 140100. [E0310]",
      );
    } else if (nacional.length !== 6) {
      errors.push(
        `Código de tributação nacional deve ter 6 dígitos — recebido "${nacional}" `
        + `(${nacional.length}). Um código que não exista na lista volta como E0310.`,
      );
    }
    // No nacional o municipal é OPCIONAL, mas quando enviado tem tamanho fixo.
    const municipal = onlyDigits(s.municipalTaxCode);
    if (municipal && municipal.length !== 3) {
      errors.push(
        `No padrão nacional, o código municipal complementar deve ter exatamente 3 dígitos `
        + `— recebido "${municipal}" (${municipal.length}). Se não existir, deixe em branco.`,
      );
    }
  } else {
    if (!s.serviceCode?.trim() && !s.municipalTaxCode?.trim()) {
      errors.push(
        "No layout municipal é obrigatório o código de tributação do município. "
        + "Atenção: ele não é o item da lista — enviar o item no lugar do código faz a "
        + "prefeitura recusar com E163.",
      );
    }
  }

  const cnae = onlyDigits(s.cnae);
  if (!cnae) {
    errors.push("CNAE do serviço é obrigatório (7 dígitos).");
  } else if (cnae.length !== 7) {
    errors.push(`CNAE deve ter 7 dígitos — recebido "${cnae}" (${cnae.length}).`);
  }

  if (s.issRate == null) {
    errors.push("Alíquota de ISS é obrigatória (percentual; 0 é aceito quando for o caso).");
  } else if (s.issRate < 0 || s.issRate > 100) {
    errors.push(`Alíquota de ISS fora da faixa: ${s.issRate}. É percentual (5 = 5%), não fração.`);
  }

  // ── E0712: ME/EPP exige o percentual total do Simples ───────────────────────
  if (input.standard === "nacional" && ehMeEpp(input.taxRegime, input.simplesNacionalOption)) {
    const total = s.totalTaxRateSn;
    if (total == null) {
      errors.push(
        "Falta o percentual total de tributos do Simples Nacional. O padrão nacional não "
        + "aceita o indicador de valor total de tributos para ME/EPP e exige esse percentual "
        + "no lugar. Ele NÃO é a alíquota de ISS: é a carga total da faixa do Simples na "
        + "competência, que só a contabilidade sabe. Preencha no cadastro fiscal da empresa "
        + "(nfse_total_tax_rate_sn) ou no serviço. [E0712]",
      );
    } else if (total < 0 || total > 100) {
      errors.push(
        `Percentual total de tributos do Simples fora da faixa: ${total}. É percentual. [E0712]`,
      );
    }
  }

  // ── E0160: opção do Simples declarada fora do conjunto válido ──────────────
  if (input.simplesNacionalOption != null
    && ![1, 2, 3].includes(input.simplesNacionalOption)) {
    errors.push(
      `Situação no Simples Nacional inválida: ${input.simplesNacionalOption}. Use 1 (não `
      + "optante), 2 (optante MEI) ou 3 (optante ME/EPP). Declarar situação diferente do "
      + "cadastro do Simples na competência resulta em rejeição — o cadastro é que vale. [E0160]",
    );
  }

  // ── E0120: inscrição municipal só entra se o município a tiver no CNC ──────
  if (input.standard === "nacional"
    && input.municipalRegistration?.trim()
    && input.municipalRegistrationInCnc !== false
    && input.simplesNacionalOption !== 2) {
    // Aviso, não bloqueio: só a consulta ao CNC (ou a própria rejeição) confirma. Barrar
    // aqui impediria de emitir em município que ESTÁ no CNC, que é o caso comum.
    errors.push(
      "AVISO: a inscrição municipal será enviada. Se o município não tiver informações "
      + "complementares no CNC NFS-e, o Sistema Nacional recusa o envio. Nesse caso "
      + "desmarque 'inscrição municipal registrada no CNC' no cadastro fiscal e emita de "
      + "novo — a inscrição deixa de ser enviada e de ser exigida. [E0120]",
    );
  }

  // ── Tomador ────────────────────────────────────────────────────────────────
  if (!t.name?.trim()) errors.push("Nome do tomador é obrigatório.");
  const doc = onlyDigits(t.document);
  if (!doc) {
    errors.push("CPF/CNPJ do tomador é obrigatório.");
  } else if (doc.length !== 11 && doc.length !== 14) {
    errors.push(`CPF/CNPJ do tomador deve ter 11 (CPF) ou 14 (CNPJ) dígitos — recebido ${doc.length}.`);
  }
  if (!a.street?.trim()) errors.push("Logradouro do tomador é obrigatório.");
  if (!a.district?.trim()) errors.push("Bairro do tomador é obrigatório.");
  const cityCode = onlyDigits(a.cityCode);
  if (!cityCode) {
    errors.push("Código IBGE do município do tomador não foi resolvido — confira UF e cidade.");
  } else if (cityCode.length !== 7) {
    errors.push(`Código IBGE deve ter 7 dígitos — recebido "${cityCode}".`);
  }
  if (!a.stateCode?.trim()) errors.push("UF do tomador é obrigatória.");
  const cep = onlyDigits(a.postalCode);
  if (!cep) {
    errors.push("CEP do tomador é obrigatório.");
  } else if (cep.length !== 8) {
    errors.push(`CEP deve ter 8 dígitos — recebido "${cep}".`);
  }

  // ── Valores ────────────────────────────────────────────────────────────────
  const servico = Number(amt.serviceAmount ?? 0);
  if (!(servico > 0)) {
    errors.push("Valor do serviço deve ser maior que zero.");
  }
  if (amt.netAmount != null && Number(amt.netAmount) > servico) {
    errors.push(
      `Valor líquido (${amt.netAmount}) não pode ser maior que o valor do serviço (${servico}).`,
    );
  }

  return errors;
}

/**
 * Monta o corpo do rascunho no contrato da Contora.
 *
 * Campo ausente é OMITIDO, nunca enviado como null: o Sistema Nacional trata "campo
 * presente e vazio" diferente de "campo ausente", e enviar null onde a regra pede omissão
 * é uma rejeição fácil de causar e difícil de achar.
 */
export function buildNfseDraftPayload(
  input: BuildNfsePayloadInput,
): Record<string, unknown> {
  const s = input.service ?? {};
  const t = input.taker ?? {};
  const a = t.address ?? {};
  const amt = input.amounts ?? {};

  const service: Record<string, unknown> = {
    description: String(s.description ?? "").trim(),
    cnae: onlyDigits(s.cnae),
    iss_rate: Number(s.issRate ?? 0),
    iss_withheld: s.issWithheld === true,
  };

  if (input.standard === "nacional") {
    service.national_tax_code = onlyDigits(s.nationalTaxCode);
    // Informativo no nacional — vai só quando existe, e mantém a pontuação de origem
    // porque a doc diz que ele "pode ser pontuado, como 01.05.01".
    if (s.serviceCode?.trim()) service.service_code = s.serviceCode.trim();
    const municipal = onlyDigits(s.municipalTaxCode);
    if (municipal) service.municipal_tax_code = municipal;

    // E0712: para ME/EPP entra o percentual da faixa do Simples NO LUGAR do indicador de
    // valor total de tributos. Não é a alíquota de ISS.
    if (ehMeEpp(input.taxRegime, input.simplesNacionalOption) && s.totalTaxRateSn != null) {
      service.total_tax_rate_sn = Number(s.totalTaxRateSn);
    }
  } else {
    // Layout municipal: o nacional não é usado; entram item da lista e código do município.
    if (s.itemListCode?.trim()) service.item_list_code = s.itemListCode.trim();
    if (s.municipalTaxCode?.trim()) service.municipal_tax_code = s.municipalTaxCode.trim();
    if (s.serviceCode?.trim()) service.service_code = s.serviceCode.trim();
    // NBS é o único dos três que não se deriva: ele distingue o tipo de serviço dentro do
    // mesmo item da lista. cClassTrib e INDOP a plataforma deriva do Anexo VIII.
    const nbs = onlyDigits(s.nbsCode);
    if (nbs) service.nbs_code = nbs;
  }

  const address: Record<string, unknown> = {
    street: String(a.street ?? "").trim(),
    number: String(a.number ?? "").trim() || "S/N",
    district: String(a.district ?? "").trim(),
    city_code: onlyDigits(a.cityCode),
    state_code: String(a.stateCode ?? "").trim().toUpperCase(),
    postal_code: onlyDigits(a.postalCode),
  };
  if (a.complement?.trim()) address.complement = a.complement.trim();

  const taker: Record<string, unknown> = {
    name: String(t.name ?? "").trim(),
    document: onlyDigits(t.document),
    address,
  };
  if (t.email?.trim()) taker.email = t.email.trim();

  const servico = round2(Number(amt.serviceAmount ?? 0));
  const retencoes = round2(
    Number(amt.pisAmount ?? 0) + Number(amt.cofinsAmount ?? 0) +
    Number(amt.inssAmount ?? 0) + Number(amt.irAmount ?? 0) +
    Number(amt.csllAmount ?? 0) + Number(amt.deductions ?? 0),
  );
  const amounts: Record<string, unknown> = {
    service_amount: servico,
    // Líquido derivado quando não informado. Explicitar evita que o provedor assuma um
    // valor diferente do que a OS cobrou.
    net_amount: amt.netAmount != null ? round2(Number(amt.netAmount)) : round2(servico - retencoes),
  };
  if (amt.deductions != null) amounts.deductions = round2(Number(amt.deductions));
  if (amt.pisAmount != null) amounts.pis_amount = round2(Number(amt.pisAmount));
  if (amt.cofinsAmount != null) amounts.cofins_amount = round2(Number(amt.cofinsAmount));
  if (amt.inssAmount != null) amounts.inss_amount = round2(Number(amt.inssAmount));
  if (amt.irAmount != null) amounts.ir_amount = round2(Number(amt.irAmount));
  if (amt.csllAmount != null) amounts.csll_amount = round2(Number(amt.csllAmount));

  const payload: Record<string, unknown> = { service, taker, amounts };
  if (input.series != null) payload.series = input.series;
  if (input.number != null) payload.number = input.number;

  // E0160: só declara a situação quando ela foi informada de propósito. A plataforma deriva
  // do regime por padrão, e sobrepor sem motivo é criar a divergência que o campo existe
  // para resolver.
  if (input.simplesNacionalOption != null) {
    payload.simples_nacional_option = input.simplesNacionalOption;
  }

  // A IM do prestador NÃO vai no payload — confirmado pelo suporte da Contora em
  // 14/08/2026, após o incidente E0116/E0121: "CNPJ, IM e regime do prestador vêm da
  // empresa vinculada à emissão; esse campo no payload não é necessário e não corrige a
  // DPS". O valor que vale é settings.municipal_registration NO CADASTRO da Contora, no
  // formato EXATO do CNC (15 posições com zeros à esquerda — o matcher do Ambiente
  // Nacional compara município+CNPJ+IM literalmente; "352217" ≠ "000000000352217" e a
  // divergência volta como E0116 dizendo que a IM "não foi informada").
  // Os campos municipalRegistration/municipalRegistrationInCnc continuam no input só
  // para o VALIDADOR avisar (E0120) — nada deles é enviado.

  return payload;
}
