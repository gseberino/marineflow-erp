import { describe, it, expect } from "vitest";
import { parseLegacyAddress } from "../lib/address-legacy";

describe("parseLegacyAddress", () => {
  it("Apolo: line_1='Rodovia 418, 12000' line_2='12000, Campestre'", () => {
    const r = parseLegacyAddress("Rodovia 418, 12000", "12000, Campestre");
    expect(r).toEqual({ street: "Rodovia 418", number: "12000", neighborhood: "Campestre", complement: "" });
  });

  it("Marine Center: number, bairro, complemento", () => {
    const r = parseLegacyAddress("ROD GOVERNADOR MARIO COVAS", "4251, PLANALTO DE CARAPINA, loja 02");
    expect(r).toEqual({
      street: "ROD GOVERNADOR MARIO COVAS",
      number: "4251",
      neighborhood: "PLANALTO DE CARAPINA",
      complement: "loja 02",
    });
  });

  it("Kamell: complemento com múltiplas partes é reunido", () => {
    const r = parseLegacyAddress("R TENENTE SETUBAL", "55, ITAPUA, EDIF TORRIELLI SALA 101");
    expect(r).toEqual({
      street: "R TENENTE SETUBAL",
      number: "55",
      neighborhood: "ITAPUA",
      complement: "EDIF TORRIELLI SALA 101",
    });
  });

  it("line_2 sem número inicial → tudo vira bairro/complemento", () => {
    const r = parseLegacyAddress("Rua X", "Centro, Sala 3");
    expect(r).toEqual({ street: "Rua X", number: "", neighborhood: "Centro", complement: "Sala 3" });
  });

  it("sem line_2 mas número no fim da line_1", () => {
    const r = parseLegacyAddress("Avenida Brasil, 1500", "");
    expect(r).toEqual({ street: "Avenida Brasil", number: "1500", neighborhood: "", complement: "" });
  });

  it("vazio → tudo vazio", () => {
    expect(parseLegacyAddress("", "")).toEqual({ street: "", number: "", neighborhood: "", complement: "" });
    expect(parseLegacyAddress(null, null)).toEqual({ street: "", number: "", neighborhood: "", complement: "" });
  });

  it("logradouro simples sem número em lugar nenhum", () => {
    const r = parseLegacyAddress("Rua das Flores", null);
    expect(r).toEqual({ street: "Rua das Flores", number: "", neighborhood: "", complement: "" });
  });
});
