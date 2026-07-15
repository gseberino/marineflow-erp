// Resolves the IBGE municipality code (7 digits) required by SEFAZ on NF-e
// addresses, from state (UF) + city name. Uses IBGE's public "localidades" API
// — the same source the frontend's use-address hook already uses for state/city
// pickers — kept server-side here so the emission payload always carries a
// valid city_code even though the shared AddressFields UI doesn't expose it.
export async function resolveIbgeCityCode(
  stateCode: string,
  cityName: string,
): Promise<string | null> {
  if (!stateCode || !cityName) return null;
  try {
    const res = await fetch(
      `https://servicodados.ibge.gov.br/api/v1/localidades/estados/${stateCode}/municipios`,
    );
    if (!res.ok) return null;
    const list = (await res.json()) as Array<{ id: number; nome: string }>;
    const target = normalize(cityName);
    const match = list.find((c) => normalize(c.nome) === target);
    return match ? String(match.id) : null;
  } catch {
    return null;
  }
}

// Strips diacritics (accents) for loose city-name matching against the IBGE
// list. Uses the explicit ̀-ͯ combining-mark range (NFD output)
// rather than literal combining characters in source, for readability/safety.
function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(new RegExp("[̀-ͯ]", "g"), "")
    .trim()
    .toLowerCase();
}
