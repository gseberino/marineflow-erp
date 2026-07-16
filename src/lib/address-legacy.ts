// Desempacota endereços legados de clientes que foram gravados em campos
// concatenados. Historicamente:
//   address_line_1 = "logradouro[, número[, complemento]]"
//   address_line_2 = "número, bairro[, complemento...]"
// (ex.: Apolo → line_1 "Rodovia 418, 12000" / line_2 "12000, Campestre").
//
// Usado para (1) o backfill SQL da migração e (2) fallback no ClientFormDialog
// e na emissão de NF-e quando as colunas estruturadas ainda estão vazias.
// Puro, sem dependências — testável no Vitest e espelha a mesma heurística do SQL.

export interface StructuredAddress {
  street: string;
  number: string;
  complement: string;
  neighborhood: string;
}

function splitParts(s: string | null | undefined): string[] {
  return (s ?? "")
    .split(",")
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Extrai logradouro/número/bairro/complemento de address_line_1 + address_line_2
 * legados. A fonte primária de número+bairro é a line_2 ("número, bairro, ...");
 * a line_1 fornece o logradouro (com o número no fim removido quando duplicado).
 */
export function parseLegacyAddress(
  line1: string | null | undefined,
  line2: string | null | undefined,
): StructuredAddress {
  let street = (line1 ?? "").trim();
  let number = "";
  let neighborhood = "";
  let complement = "";

  const p2 = splitParts(line2);
  if (p2.length > 0) {
    if (/^\d/.test(p2[0])) {
      // "número, bairro, complemento..."
      number = p2[0];
      neighborhood = p2[1] ?? "";
      complement = p2.slice(2).join(", ");
    } else {
      // Sem número inicial → assume "bairro, complemento..."
      neighborhood = p2[0];
      complement = p2.slice(1).join(", ");
    }
  }

  if (number) {
    // Remove ", <número>" do fim do logradouro quando duplica o número já achado.
    street = street.replace(new RegExp(",\\s*" + escapeRegExp(number) + "\\s*$"), "").trim();
  } else {
    // Não veio número da line_2 — tenta extrair um número no fim da line_1.
    const m = street.match(/^(.*?),\s*(\d+[^,]*)$/);
    if (m) {
      street = m[1].trim();
      number = m[2].trim();
    }
  }

  return { street, number, complement, neighborhood };
}
