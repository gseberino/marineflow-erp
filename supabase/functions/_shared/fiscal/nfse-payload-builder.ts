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
  /**
   * Informações complementares — `serv/infoCompl/xInfComp` no nacional,
   * `InformacoesComplementares` no ABRASF. Texto livre, ATÉ 2000 caracteres.
   *
   * A Contora RECUSA acima de 2000 em vez de truncar, e o motivo é bom: texto
   * cortado vira nota autorizada com informação pela metade — o erro some e o
   * dano fica. O campo passou a existir em 06/09/2026, a pedido nosso; antes
   * disso a referência da OS era empurrada para dentro da descrição do serviço,
   * disputando os 500 caracteres com ela.
   */
  additionalInfo?: string | null;
}

export interface NfseAmountsInput {
  /**
   * Valor BRUTO do serviço, ANTES dos descontos (`valores/vServPrest/vServ`).
   *
   * Era o líquido até 06/09/2026, quando não havia campo de desconto: a nota
   * saía com o valor certo e o desconto invisível. Agora é o bruto, e o
   * Ambiente Nacional calcula o líquido sozinho.
   */
  serviceAmount?: number | null;
  /**
   * Líquido. PREFIRA OMITIR: sem ele a Contora calcula bruto − descontos −
   * deduções. Mandar os dois e errar a conta gera aviso na análise — a proteção
   * contra o engano mais provável, que é subtrair o desconto do bruto E ainda
   * declarar o desconto, descontando duas vezes.
   */
  netAmount?: number | null;
  /**
   * Desconto INCONDICIONADO — `valores/vDescCondIncond/vDescIncond`.
   * Reduz a base de cálculo do ISS e o valor líquido.
   */
  unconditionalDiscount?: number | null;
  /**
   * Desconto CONDICIONADO — `valores/vDescCondIncond/vDescCond`.
   * Reduz o líquido mas NÃO a base do ISS: depende de condição futura, então
   * não pode tirar imposto.
   */
  conditionalDiscount?: number | null;
  /**
   * Dedução/redução — `valores/vDedRed/vDR`.
   *
   * ⚠️ NÃO USAR NA HBR. A Sefin recusa com **E0441** para prestador ME/EPP
   * optante do Simples quando o município parametriza assim o código de
   * serviço — e é o caso do 14.01 em Itajaí. Confirmado em homologação pela
   * Contora em 06/09/2026. O campo segue aqui porque a regra é municipal: o
   * mesmo 14.01 admite dedução em outro município.
   */
  deductions?: number | null;
  /**
   * ⚠️ Retenções federais: só ZERO é aceito. Desde 06/09/2026 a Contora RECUSA
   * valor diferente de zero, porque a NFS-e ainda não transporta retenção
   * federal — o grupo `tribFederal` do nacional exige CST, base e tipo, não só
   * o valor. Mandar o número não teria efeito no documento.
   * A retenção de ISS não é aqui: é `service.issWithheld`.
   */
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

/** Limite de `serv/infoCompl/xInfComp` — a Contora recusa acima disto. */
export const NFSE_INFO_COMPL_MAX = 2000;

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

  // ── Descontos e deduções (06/09/2026) ─────────────────────────────────────
  // Recusar aqui em vez de deixar o provedor recusar: esta função existe para
  // gastar zero cota de evento fiscal com payload que já se sabe inválido.
  const desconto = Number(amt.unconditionalDiscount ?? 0) + Number(amt.conditionalDiscount ?? 0);
  const abatimentos = desconto + Number(amt.deductions ?? 0);
  for (
    const [rotulo, valor] of [
      ["Desconto incondicionado", amt.unconditionalDiscount],
      ["Desconto condicionado", amt.conditionalDiscount],
      ["Dedução/redução", amt.deductions],
    ] as const
  ) {
    if (valor != null && Number(valor) < 0) {
      errors.push(`${rotulo} não pode ser negativo (recebido ${valor}).`);
    }
  }
  if (abatimentos > servico) {
    errors.push(
      `A soma de descontos e deduções (${round2(abatimentos)}) não pode passar do valor do `
      + `serviço (${round2(servico)}).`,
    );
  }
  // O engano mais provável, e o mais caro: subtrair o desconto do bruto E ainda
  // declarar o desconto. A nota sairia com o valor descontado duas vezes.
  if (amt.netAmount != null && desconto > 0) {
    const esperado = round2(servico - abatimentos);
    if (round2(Number(amt.netAmount)) !== esperado) {
      errors.push(
        `Valor líquido informado (${round2(Number(amt.netAmount))}) não bate com bruto menos `
        + `descontos e deduções (${esperado}). Se o desconto já foi abatido do valor do `
        + `serviço, ele está sendo contado duas vezes — o correto é enviar o valor BRUTO em `
        + `service_amount e omitir o líquido.`,
      );
    }
  }

  // E0441: para ME/EPP do Simples, com o código de serviço parametrizado assim
  // pelo município, a Sefin recusa dedução. É o caso do 14.01 em Itajaí.
  // Não se bloqueia por município aqui — a regra é dele, não nossa —, mas o
  // aviso poupa uma rejeição.
  if (Number(amt.deductions ?? 0) > 0) {
    errors.push(
      "Dedução/redução não é aceita para prestador ME/EPP do Simples Nacional quando o "
      + "município parametriza assim o código de serviço — é o caso do 14.01 em Itajaí, e a "
      + "Sefin recusa com E0441. Se o desconto é comercial, use o desconto incondicionado.",
    );
  }

  // A NFS-e ainda não transporta retenção federal: o grupo tribFederal do
  // nacional exige CST, base e tipo, não só o valor. Mandar o número não teria
  // efeito no documento — melhor recusar do que emitir nota que o omite.
  for (
    const [rotulo, valor] of [
      ["PIS", amt.pisAmount],
      ["COFINS", amt.cofinsAmount],
      ["INSS", amt.inssAmount],
      ["IR", amt.irAmount],
      ["CSLL", amt.csllAmount],
    ] as const
  ) {
    if (valor != null && Number(valor) !== 0) {
      errors.push(
        `Retenção de ${rotulo} (${valor}) não pode ser enviada na NFS-e: o documento ainda `
        + "não transporta retenção federal, e o valor seria descartado sem aparecer na nota. "
        + "A retenção de ISS é declarada em iss_withheld.",
      );
    }
  }

  const infoCompl = String(s.additionalInfo ?? "");
  if (infoCompl.length > NFSE_INFO_COMPL_MAX) {
    errors.push(
      `Informações complementares têm ${infoCompl.length} caracteres e o limite é `
      + `${NFSE_INFO_COMPL_MAX}. O texto NÃO é cortado de propósito: nota autorizada com `
      + "informação pela metade esconde o erro e mantém o dano.",
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

  // Informações complementares — vale nos dois padrões (xInfComp / ABRASF).
  // NÃO se trunca aqui de propósito: o excesso é recusado por
  // `validateNfseDraftInput`, antes de gastar cota. Cortar em silêncio
  // produziria nota autorizada com informação pela metade — o erro sumiria e o
  // dano ficaria. É a mesma razão pela qual a Contora recusa em vez de cortar.
  const infoCompl = String(s.additionalInfo ?? "").trim();
  if (infoCompl) service.additional_info = infoCompl;

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
  const amounts: Record<string, unknown> = {
    // BRUTO, antes dos descontos. Ver NfseAmountsInput.serviceAmount.
    service_amount: servico,
  };

  // Descontos (06/09/2026). O incondicionado reduz a base do ISS; o
  // condicionado só o líquido, porque depende de condição futura.
  if (amt.unconditionalDiscount != null) {
    amounts.unconditional_discount = round2(Number(amt.unconditionalDiscount));
  }
  if (amt.conditionalDiscount != null) {
    amounts.conditional_discount = round2(Number(amt.conditionalDiscount));
  }

  // O líquido só vai quando alguém o afirmou. Omitido, quem calcula é o
  // Ambiente Nacional — bruto − descontos − deduções —, e é a conta que vale.
  // Mandar um líquido nosso junto com o desconto é o caminho curto para
  // descontar duas vezes; a Contora responde com aviso quando os dois não
  // fecham, mas o certo é não criar a divergência.
  if (amt.netAmount != null) amounts.net_amount = round2(Number(amt.netAmount));

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
