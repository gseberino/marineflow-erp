// Resolves the IBGE municipality code (7 digits) required by SEFAZ on NF-e
// addresses, from state (UF) + city name. Uses IBGE's public "localidades" API
// — the same source the frontend's use-address hook already uses for state/city
// pickers — kept server-side here so the emission payload always carries a
// valid city_code even though the shared AddressFields UI doesn't expose it.
//
// 15/10/2026: em 06/10 o IBGE trocou o certificado e o servidor deles passou a mandar
// só o certificado final, sem o intermediário da Sectigo. Navegador completa a cadeia
// sozinho; o Deno do Supabase não ("invalid peer certificate: UnknownIssuer"). Como
// toda falha virava `null` em silêncio, NF-e e NFS-e travaram com "Código IBGE do
// município do tomador não foi resolvido" para cliente com cidade e UF corretas.
// Agora há timeout, log da falha e fontes de reserva: ViaCEP pelo CEP (campo `ibge`)
// e BrasilAPI (mesma lista do IBGE, outro servidor). Só devolve código de 7 dígitos.
export async function resolveIbgeCityCode(
  stateCode: string,
  cityName: string,
  postalCode?: string | null,
): Promise<string | null> {
  const uf = (stateCode ?? "").trim().toUpperCase();
  const target = normalize(cityName ?? "");

  if (uf && target) {
    const ibge = await buscarJson<Array<{ id: number; nome: string }>>(
      `https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios`,
    );
    const viaIbge = Array.isArray(ibge) ? ibge.find((c) => normalize(c.nome) === target) : undefined;
    if (viaIbge && valido(String(viaIbge.id))) return String(viaIbge.id);
  }

  // ViaCEP: aceito de imediato quando a cidade do CEP é a do cadastro.
  const cep = (postalCode ?? "").replace(/\D/g, "");
  const viaCep = cep.length === 8
    ? await buscarJson<{ ibge?: string; uf?: string; localidade?: string; erro?: unknown }>(
      `https://viacep.com.br/ws/${cep}/json/`,
    )
    : null;
  const cepOk = !!viaCep && !viaCep.erro && valido(viaCep.ibge ?? "")
    && (!uf || (viaCep.uf ?? "").toUpperCase() === uf);
  if (cepOk && target && normalize(viaCep!.localidade ?? "") === target) return viaCep!.ibge!;

  if (uf && target) {
    const brasilApi = await buscarJson<Array<{ nome: string; codigo_ibge: string }>>(
      `https://brasilapi.com.br/api/ibge/municipios/v1/${uf}`,
    );
    const viaBrasilApi = Array.isArray(brasilApi)
      ? brasilApi.find((c) => normalize(c.nome) === target)
      : undefined;
    if (viaBrasilApi && valido(String(viaBrasilApi.codigo_ibge))) {
      return String(viaBrasilApi.codigo_ibge);
    }
  }

  // Último recurso: o município do CEP, desde que na MESMA UF do cadastro — um CEP
  // digitado errado não troca o tomador de estado.
  if (cepOk) return viaCep!.ibge!;

  console.warn(`[ibge] código não resolvido para ${cityName}/${stateCode} (CEP ${postalCode ?? "-"})`);
  return null;
}

async function buscarJson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      console.warn(`[ibge] ${url} respondeu ${res.status}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (e) {
    console.warn(`[ibge] ${url} falhou: ${(e as Error)?.message ?? e}`);
    return null;
  }
}

function valido(codigo: string): boolean {
  return /^\d{7}$/.test(codigo);
}

// Strips diacritics (accents) for loose city-name matching against the IBGE
// list. Uses the explicit ̀-ͯ combining-mark range (NFD output).
function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toLowerCase();
}
