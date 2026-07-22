/**
 * Casamento de telefone — fonte única da regra.
 *
 * Por que os ÚLTIMOS 8 DÍGITOS: números brasileiros variam no "nono dígito" (o mesmo celular
 * aparece como 5547999159654 e 554799159654), e o WhatsApp/Evolution normaliza de um jeito que
 * não bate com o que está cadastrado. Os 8 dígitos finais são estáveis nas duas formas, então
 * são a chave de casamento confiável. Foi um bug real: uma mensagem entregue a
 * 554799159654 enquanto o cadastro dizia 5547999159654.
 *
 * Ficava duplicado em quotes.ts e entity-360.ts — centralizado aqui para não divergir.
 */

/** Só os dígitos do telefone (remove +, espaço, parênteses, traço). */
export function somenteDigitos(tel: string | null | undefined): string {
  return String(tel || "").replace(/\D/g, "");
}

/** Chave de casamento: últimos 8 dígitos, ou null se o número for curto demais. */
export function chaveTelefone(tel: string | null | undefined): string | null {
  const d = somenteDigitos(tel);
  return d.length >= 8 ? d.slice(-8) : null;
}

/** Padrão para usar com `.like("phone_normalized", ...)` no supabase-js. */
export function padraoLikeTelefone(tel: string | null | undefined): string | null {
  const k = chaveTelefone(tel);
  return k ? `%${k}` : null;
}

/** Dois telefones são o mesmo contato? (compara pela chave, tolerando formatos diferentes) */
export function mesmoTelefone(a: string | null | undefined, b: string | null | undefined): boolean {
  const ka = chaveTelefone(a);
  const kb = chaveTelefone(b);
  return ka !== null && ka === kb;
}
