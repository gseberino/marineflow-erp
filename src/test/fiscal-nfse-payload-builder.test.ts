// [F-NFSE-01] Builder da NFS-e — o que ele evita é rejeição com nota queimada.
//
// Cada tentativa de emissão consome numeração fiscal que não volta, e o Sistema Nacional
// responde por código: "E0712" não diz a ninguém o que fazer. Estes testes travam as quatro
// regras que já custaram nota a quem integrou antes, e travam também o formato do payload —
// um campo com o nome errado só aparece como rejeição da prefeitura, minutos depois.
import { describe, it, expect } from "vitest";
import {
  buildNfseDraftPayload,
  validateNfseDraftInput,
  ehMeEpp,
  type BuildNfsePayloadInput,
} from "../../supabase/functions/_shared/fiscal/nfse-payload-builder";

/** Cenário real da HBR: manutenção de motores elétricos, tomador em Itajaí/SC. */
function base(over: Partial<BuildNfsePayloadInput> = {}): BuildNfsePayloadInput {
  return {
    standard: "nacional",
    taxRegime: "simples",
    service: {
      description: "Manutenção de sistema elétrico de embarcação",
      nationalTaxCode: "140101",
      cnae: "3313901",
      issRate: 5,
      issWithheld: false,
      totalTaxRateSn: 6,
    },
    taker: {
      name: "Cliente Náutico LTDA",
      document: "12.345.678/0001-99",
      email: "cliente@exemplo.com.br",
      address: {
        street: "Rua das Embarcações",
        number: "100",
        district: "Centro",
        cityCode: "4208203", // Itajaí/SC
        cityName: "Itajaí",
        stateCode: "SC",
        postalCode: "88301-000",
      },
    },
    amounts: { serviceAmount: 1500 },
    ...over,
  };
}

describe("validação da NFS-e — cenário completo", () => {
  it("não reclama de um cenário correto", () => {
    expect(validateNfseDraftInput(base())).toEqual([]);
  });
});

describe("E0310 — código de tributação nacional", () => {
  it("exige o código no padrão nacional", () => {
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, nationalTaxCode: null },
    }));
    expect(erros.join(" ")).toContain("E0310");
  });

  it("ensina que o nacional NÃO é o municipal sem os pontos", () => {
    // A confusão que gera E0310: "14.01" vira 140101, não 140100. Sem essa frase, quem
    // recebe a rejeição tira os pontos do código municipal e erra de novo.
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, nationalTaxCode: null },
    }));
    expect(erros.join(" ")).toContain("140101");
  });

  it("recusa código com número de dígitos diferente de 6", () => {
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, nationalTaxCode: "1401" },
    }));
    expect(erros.join(" ")).toMatch(/6 dígitos/);
  });

  it("no padrão nacional, código municipal só vale com exatamente 3 dígitos", () => {
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, municipalTaxCode: "1401001" },
    }));
    expect(erros.join(" ")).toMatch(/3 dígitos/);
  });
});

describe("E0712 — ME/EPP exige o percentual do Simples", () => {
  it("bloqueia empresa do Simples sem total_tax_rate_sn", () => {
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, totalTaxRateSn: null },
    }));
    expect(erros.join(" ")).toContain("E0712");
  });

  it("deixa claro que NÃO é a alíquota de ISS", () => {
    // O erro natural de quem lê "percentual de tributos" é repetir os 5% do ISS. A carga da
    // faixa do Simples é outra coisa, e só a contabilidade sabe.
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, totalTaxRateSn: null },
    }));
    expect(erros.join(" ")).toMatch(/NÃO é a alíquota de ISS/);
  });

  it("não exige de quem não é ME/EPP", () => {
    const erros = validateNfseDraftInput(base({
      taxRegime: "lucro_presumido",
      service: { ...base().service, totalTaxRateSn: null },
    }));
    expect(erros.join(" ")).not.toContain("E0712");
  });

  it("a opção explícita do Simples vence o regime cadastrado", () => {
    // É exatamente para isso que o campo existe: quando o cadastro daqui diverge do
    // cadastro do Simples, o do Simples é que vale.
    expect(ehMeEpp("simples", 1)).toBe(false); // cadastro diz simples, mas é não optante
    expect(ehMeEpp("lucro_presumido", 3)).toBe(true); // e o contrário também
    expect(ehMeEpp("simples", null)).toBe(true);
  });

  it("MEI (opção 2) não é ME/EPP e não cai no E0712", () => {
    const erros = validateNfseDraftInput(base({
      simplesNacionalOption: 2,
      service: { ...base().service, totalTaxRateSn: null },
    }));
    expect(erros.join(" ")).not.toContain("E0712");
  });
});

describe("E0160 — situação no Simples Nacional", () => {
  it("recusa valor fora de 1/2/3", () => {
    const erros = validateNfseDraftInput(base({
      simplesNacionalOption: 9 as never,
    }));
    expect(erros.join(" ")).toContain("E0160");
  });

  it("só declara a situação quando ela foi informada de propósito", () => {
    // A plataforma deriva do regime por padrão; sobrepor sem motivo CRIA a divergência que
    // o campo existe para resolver.
    const semOpcao = buildNfseDraftPayload(base());
    expect(semOpcao.simples_nacional_option).toBeUndefined();

    const comOpcao = buildNfseDraftPayload(base({ simplesNacionalOption: 3 }));
    expect(comOpcao.simples_nacional_option).toBe(3);
  });
});

describe("E0120 — inscrição municipal e o CNC", () => {
  it("avisa quando a inscrição vai ser enviada", () => {
    const erros = validateNfseDraftInput(base({
      municipalRegistration: "123456",
      municipalRegistrationInCnc: true,
    }));
    expect(erros.join(" ")).toContain("E0120");
  });

  it("cala quando o município não tem dados no CNC — e aí a IM não é enviada", () => {
    const input = base({ municipalRegistration: "123456", municipalRegistrationInCnc: false });
    expect(validateNfseDraftInput(input).join(" ")).not.toContain("E0120");
    expect(buildNfseDraftPayload(input).municipal_registration).toBeUndefined();
  });

  it("para o MEI a inscrição NUNCA é enviada", () => {
    // O cadastro nacional responde pelos dados do prestador.
    const payload = buildNfseDraftPayload(base({
      simplesNacionalOption: 2,
      municipalRegistration: "123456",
      municipalRegistrationInCnc: true,
    }));
    expect(payload.municipal_registration).toBeUndefined();
  });
});

describe("payload no contrato da Contora", () => {
  it("usa os nomes de campo exatos da doc", () => {
    const p = buildNfseDraftPayload(base()) as Record<string, any>;
    expect(Object.keys(p).sort()).toEqual(["amounts", "service", "taker"]);
    expect(p.service).toMatchObject({
      description: "Manutenção de sistema elétrico de embarcação",
      national_tax_code: "140101",
      cnae: "3313901",
      iss_rate: 5,
      iss_withheld: false,
      total_tax_rate_sn: 6,
    });
    expect(p.amounts).toMatchObject({ service_amount: 1500, net_amount: 1500 });
  });

  it("limpa a máscara de documento, CEP e código IBGE", () => {
    const p = buildNfseDraftPayload(base()) as Record<string, any>;
    expect(p.taker.document).toBe("12345678000199");
    expect(p.taker.address.postal_code).toBe("88301000");
    expect(p.taker.address.city_code).toBe("4208203");
  });

  it("omite campo ausente em vez de mandar null", () => {
    // O Sistema Nacional trata "presente e vazio" diferente de "ausente"; mandar null onde
    // a regra pede omissão é rejeição fácil de causar e difícil de achar.
    const p = buildNfseDraftPayload(base({
      taker: { ...base().taker, email: null },
      service: { ...base().service, serviceCode: null, municipalTaxCode: null },
    })) as Record<string, any>;
    expect("email" in p.taker).toBe(false);
    expect("service_code" in p.service).toBe(false);
    expect("municipal_tax_code" in p.service).toBe(false);
  });

  it("deriva o líquido descontando as retenções", () => {
    const p = buildNfseDraftPayload(base({
      amounts: { serviceAmount: 1000, pisAmount: 6.5, cofinsAmount: 30, inssAmount: 110 },
    })) as Record<string, any>;
    expect(p.amounts.net_amount).toBe(853.5);
  });

  it("número sem casa decimal não vira dízima", () => {
    const p = buildNfseDraftPayload(base({
      amounts: { serviceAmount: 1000 / 3 },
    })) as Record<string, any>;
    expect(p.amounts.service_amount).toBe(333.33);
  });

  it("endereço sem número vira S/N, não string vazia", () => {
    const p = buildNfseDraftPayload(base({
      taker: { ...base().taker, address: { ...base().taker.address!, number: null } },
    })) as Record<string, any>;
    expect(p.taker.address.number).toBe("S/N");
  });
});

describe("layout municipal", () => {
  const municipal = (): BuildNfsePayloadInput => base({
    standard: "municipal",
    service: {
      description: "Serviço de manutenção e reparação de motores elétricos",
      itemListCode: "1401",
      municipalTaxCode: "1401001", // CTISS, 7 dígitos
      nbsCode: "120015000",
      cnae: "3313901",
      issRate: 5,
      issWithheld: false,
    },
  });

  it("não usa o código nacional", () => {
    const p = buildNfseDraftPayload(municipal()) as Record<string, any>;
    expect("national_tax_code" in p.service).toBe(false);
    expect(p.service.item_list_code).toBe("1401");
    expect(p.service.municipal_tax_code).toBe("1401001");
    expect(p.service.nbs_code).toBe("120015000");
  });

  it("não exige o código nacional na validação", () => {
    expect(validateNfseDraftInput(municipal())).toEqual([]);
  });

  it("exige o código de tributação do município — e avisa do E163", () => {
    const erros = validateNfseDraftInput(base({
      standard: "municipal",
      service: { ...municipal().service, municipalTaxCode: null, serviceCode: null },
    }));
    expect(erros.join(" ")).toContain("E163");
  });

  it("NÃO envia total_tax_rate_sn — é campo do padrão nacional", () => {
    const p = buildNfseDraftPayload(base({
      standard: "municipal",
      service: { ...municipal().service, totalTaxRateSn: 6 },
    })) as Record<string, any>;
    expect("total_tax_rate_sn" in p.service).toBe(false);
  });
});

describe("tomador e valores", () => {
  it("cobra os campos de endereço que a prefeitura exige", () => {
    const erros = validateNfseDraftInput(base({
      taker: { name: "X", document: "12345678000199", address: {} },
    }));
    const texto = erros.join(" ");
    expect(texto).toMatch(/Logradouro/);
    expect(texto).toMatch(/Bairro/);
    expect(texto).toMatch(/IBGE/);
    expect(texto).toMatch(/UF/);
    expect(texto).toMatch(/CEP/);
  });

  it("recusa documento que não é CPF nem CNPJ", () => {
    const erros = validateNfseDraftInput(base({
      taker: { ...base().taker, document: "123" },
    }));
    expect(erros.join(" ")).toMatch(/11 \(CPF\) ou 14 \(CNPJ\)/);
  });

  it("recusa código IBGE que não tem 7 dígitos", () => {
    const erros = validateNfseDraftInput(base({
      taker: { ...base().taker, address: { ...base().taker.address!, cityCode: "4208" } },
    }));
    expect(erros.join(" ")).toMatch(/7 dígitos/);
  });

  it("recusa valor de serviço zerado", () => {
    const erros = validateNfseDraftInput(base({ amounts: { serviceAmount: 0 } }));
    expect(erros.join(" ")).toMatch(/maior que zero/);
  });

  it("recusa líquido maior que o bruto", () => {
    const erros = validateNfseDraftInput(base({
      amounts: { serviceAmount: 1000, netAmount: 1200 },
    }));
    expect(erros.join(" ")).toMatch(/não pode ser maior/);
  });

  it("alíquota de ISS fora da faixa é percentual mal entendido", () => {
    const erros = validateNfseDraftInput(base({
      service: { ...base().service, issRate: 0.05 * 100 * 100 },
    }));
    expect(erros.join(" ")).toMatch(/percentual/);
  });
});
