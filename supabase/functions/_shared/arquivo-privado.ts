// Arquivos em bucket PRIVADO: o banco guarda o CAMINHO dentro do bucket, e quem mostra gera um
// link temporário (createSignedUrl) na hora.
//
// Até 29/09/2026 os buckets `signatures` e `expense-receipts` eram públicos e as colunas *_url
// guardavam o link público: quem tivesse o link baixava o PDF assinado com nome, CPF/CNPJ e
// endereço do cliente, sem login e para sempre. As colunas mantêm o nome (*_url), mas passam a
// guardar o caminho; os links antigos ainda gravados continuam sendo reconhecidos aqui.
//
// Usado pelas edges (submit-signature, assinatura-do-link) e pela tela (src/lib/arquivo-privado.tsx).

export type BucketPrivado = "signatures" | "expense-receipts";

/**
 * O caminho do arquivo dentro do bucket, a partir do que está gravado: o caminho (formato
 * novo) ou um link público/assinado antigo deste bucket. `null` quando não há nada ou quando o
 * valor é um link de outro lugar (quem chama decide se usa o link como está).
 */
export function caminhoNoBucket(valor: string | null | undefined, bucket: BucketPrivado): string | null {
  if (!valor) return null;
  const v = valor.trim();
  if (!v) return null;
  if (!/^https?:\/\//i.test(v)) return v.replace(/^\/+/, "");
  const marca = `/object/`;
  const i = v.indexOf(marca);
  if (i < 0) return null;
  const resto = v.slice(i + marca.length).split(/[?#]/)[0];
  const [tipo, nomeDoBucket, ...partes] = resto.split("/");
  if ((tipo !== "public" && tipo !== "sign") || nomeDoBucket !== bucket || partes.length === 0) return null;
  try {
    return decodeURIComponent(partes.join("/"));
  } catch {
    return partes.join("/");
  }
}

/** Um link de fora do nosso Storage (legado), usado como está. */
export function linkExterno(valor: string | null | undefined): string | null {
  if (!valor) return null;
  const v = valor.trim();
  return /^https?:\/\//i.test(v) && !v.includes("/storage/v1/object/") ? v : null;
}
