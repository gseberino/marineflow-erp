import { describe, it, expect } from "vitest";
import { buildDanfeFilename } from "../lib/danfe-filename";

describe("buildDanfeFilename", () => {
  it("monta <natureza> <nº> - <2 palavras do destinatário>.pdf", () => {
    expect(buildDanfeFilename({ nature: "Devolução de compra", number: 25, recipient: "KAMELL COMERCIO E SERVICOS LTDA" }))
      .toBe("Devolução 25 - KAMELL COMERCIO.pdf");
  });

  it("usa só a 1ª palavra da natureza e as 2 primeiras do destinatário", () => {
    expect(buildDanfeFilename({ nature: "Venda de mercadoria", number: 1042, recipient: "Marina Azul Nautica Ltda" }))
      .toBe("Venda 1042 - Marina Azul.pdf");
  });

  it("aceita número formatado (000.000.025) e usa só os dígitos", () => {
    expect(buildDanfeFilename({ nature: "Devolução de compra", number: "000.000.025", recipient: "Kamell" }))
      .toBe("Devolução 25 - Kamell.pdf");
  });

  it("remove caracteres inválidos de nome de arquivo (/ \\ : * ? etc.)", () => {
    const f = buildDanfeFilename({ nature: "Remessa", number: 7, recipient: 'A/B:C*D?"E' });
    expect(f).not.toMatch(/[<>:"/\\|?*]/);
    expect(f.endsWith(".pdf")).toBe(true);
  });

  it("cai em defaults quando faltam dados", () => {
    expect(buildDanfeFilename({})).toBe("NF-e.pdf");
    expect(buildDanfeFilename({ number: 9 })).toBe("NF-e 9.pdf");
    expect(buildDanfeFilename({ recipient: "Fulano" })).toBe("NF-e - Fulano.pdf");
  });

  it("respeita a extensão (xml) e continua .pdf por padrão", () => {
    expect(buildDanfeFilename({ nature: "Devolução", number: 25, recipient: "Kamell", extension: "xml" }))
      .toBe("Devolução 25 - Kamell.xml");
  });

  it("evita nome reservado do Windows", () => {
    expect(buildDanfeFilename({ nature: "CON" }).startsWith("_")).toBe(true);
  });
});
