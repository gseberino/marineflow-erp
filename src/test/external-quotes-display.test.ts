import { describe, expect, it } from "vitest";
import {
  getExternalQuotePartName,
  getExternalQuotePartyName,
  getExternalQuoteServiceName,
  getExternalQuoteVesselName,
} from "@/hooks/use-external-quotes";

describe("external quote display helpers", () => {
  it("renders canonical client, lead and vessel names without obsolete name columns", () => {
    const quote: any = {
      client: { full_name_or_company_name: "CELIO YUDI SHIOKAWA JUNIOR" },
      lead: { full_name_or_company_name: "Lead antigo", boat_name: "Lead Boat" },
      vessel: { boat_name: "Dondoka" },
    };

    expect(getExternalQuotePartyName(quote)).toBe("CELIO YUDI SHIOKAWA JUNIOR");
    expect(getExternalQuoteVesselName(quote)).toBe("Dondoka");
  });

  it("falls back to lead canonical fields when no client or vessel is linked", () => {
    const quote: any = {
      client: null,
      lead: { full_name_or_company_name: "Prospecto Teste", boat_name: "Barco Teste" },
      vessel: null,
    };

    expect(getExternalQuotePartyName(quote)).toBe("Prospecto Teste");
    expect(getExternalQuoteVesselName(quote)).toBe("Barco Teste");
  });

  it("renders formal quote item names from snapshot columns", () => {
    expect(getExternalQuotePartName({ product_name_snapshot: "Raymarine Axiom 12" } as any)).toBe(
      "Raymarine Axiom 12"
    );
    expect(getExternalQuoteServiceName({ service_name_snapshot: "Instalacao" } as any)).toBe("Instalacao");
  });
});
