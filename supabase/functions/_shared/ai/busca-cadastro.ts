// Busca e normalização de cadastro (cliente, fornecedor, marina, contato da embarcação) — 07/10/2026.
//
// POR QUE EXISTE: search_clients prometia "tolerante a erros", mas era um ILIKE cru — "Joao" não
// achava "João", e CPF/telefone ditos só com dígitos não achavam o gravado com pontos e traço
// (a tela grava com máscara: "508.421.889-91", "(47) 99165-3158"; o WhatsApp grava "+55 47 …";
// importação antiga gravou só dígitos). E create_client não procurava duplicado: "Flávio da Igreja"
// foi criado duas vezes com o MESMO CPF.
//
// COMO: o banco tem unaccent, mas o formato misto dos números não se resolve com ILIKE. São ~530
// clientes e ~530 fornecedores, então a busca lê os candidatos em páginas de 1000 (o PostgREST corta
// em 1000 em silêncio) e compara aqui, sem acento e por dígitos. Se a base crescer a ponto de pesar,
// o caminho é uma função no banco com unaccent + regexp_replace — a regra de casamento é esta.

import { chaveTelefone, somenteDigitos } from "./phone.ts";

/** Minúsculas, sem acento e com espaços simples — "  JOÃO  da Silva" → "joao da silva". */
export function semAcento(s: unknown): string {
  return String(s ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Documento só com dígitos, devolvendo o zero da frente que planilha comeu (mesma regra de
 * public._doc_normalizado no banco: 10 dígitos → CPF, 13 → CNPJ).
 */
export function digitosDoDocumento(doc: unknown): string {
  const d = somenteDigitos(String(doc ?? ""));
  if (d.length === 10) return d.padStart(11, "0");
  if (d.length === 13) return d.padStart(14, "0");
  return d;
}

/** CPF/CNPJ no MESMO formato que a tela grava (maskCPF/maskCNPJ de src/lib/masks.ts). */
export function formatarDocumento(doc: unknown): string | null {
  const bruto = String(doc ?? "").trim();
  if (!bruto) return null;
  const d = digitosDoDocumento(bruto);
  if (d.length === 11) return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
  if (d.length === 14) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
  return bruto; // tamanho estranho: grava como veio (a tela também aceita) — quem confere é o dono
}

/**
 * Telefone no MESMO formato que a tela grava (maskPhone: "(47) 99999-9999"). O +55 sai: a tela
 * não tem campo de DDI. Número estrangeiro ou curto demais fica como veio — mascarar estragaria.
 */
export function formatarTelefone(tel: unknown): string | null {
  const bruto = String(tel ?? "").trim();
  if (!bruto) return null;
  let d = somenteDigitos(bruto);
  if (d.startsWith("00")) d = d.slice(2);
  const temDdi = /^\s*\+/.test(bruto) || d.length >= 12;
  if (temDdi) {
    if (!d.startsWith("55")) return bruto; // estrangeiro (+351…): fica como veio
    d = d.slice(2);
  }
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  return bruto;
}

/** CEP como o AddressFields da tela grava ("88385-000"); fora de 8 dígitos fica como veio. */
export function formatarCep(cep: unknown): string | null {
  const bruto = String(cep ?? "").trim();
  if (!bruto) return null;
  const d = somenteDigitos(bruto);
  return d.length === 8 ? `${d.slice(0, 5)}-${d.slice(5)}` : bruto;
}

/** O termo é um número (CPF, CNPJ, telefone)? Só dígitos e pontuação de número, com 4+ dígitos. */
export function termoNumerico(termo: string): string | null {
  if (!/^[\d\s().\-/+]+$/.test(termo)) return null;
  const d = somenteDigitos(termo);
  return d.length >= 4 ? d : null;
}

export interface CamposDaBusca {
  /** Colunas comparadas como texto (sem acento, todas as palavras do termo presentes). */
  texto: string[];
  /** Colunas de documento (CPF/CNPJ), comparadas por dígitos. */
  documento?: string[];
  /** Colunas de telefone, comparadas por dígitos e pelos 8 finais (nono dígito/DDI). */
  telefone?: string[];
}

/**
 * Nota de 0 (não casa) a 100. Nome igual vale mais que "começa com", que vale mais que "contém" —
 * a lista sai ordenada e o "Joao" exato não fica atrás de "Joaozinho" no corte do limite.
 */
export function notaDoCadastro(linha: Record<string, unknown>, termo: string, campos: CamposDaBusca): number {
  const num = termoNumerico(termo);
  if (num) {
    const docDoTermo = digitosDoDocumento(num);
    for (const c of campos.documento ?? []) {
      const d = digitosDoDocumento(linha[c]);
      if (d && d === docDoTermo) return 100;
      if (d && d.includes(num)) return 70;
    }
    const chave = num.length >= 8 ? chaveTelefone(num) : null;
    for (const c of campos.telefone ?? []) {
      const d = somenteDigitos(String(linha[c] ?? ""));
      if (!d) continue;
      if (chave && chaveTelefone(d) === chave) return 90;
      if (d.includes(num)) return 60;
    }
    // Número também pode estar no texto (ex.: "Marina 3 Ilhas", CEP no endereço) — cai no texto.
  }
  const t = semAcento(termo);
  if (!t) return 0;
  const palavras = t.split(" ");
  let melhor = 0;
  for (const c of campos.texto) {
    const v = semAcento(linha[c]);
    if (!v) continue;
    if (v === t) melhor = Math.max(melhor, 95);
    else if (v.startsWith(t)) melhor = Math.max(melhor, 80);
    else if (v.includes(t)) melhor = Math.max(melhor, 65);
    else if (palavras.every((p) => v.includes(p))) melhor = Math.max(melhor, 50);
  }
  return melhor;
}

const PAGINA = 1000; // teto do PostgREST: acima disso o .limit() corta em silêncio
const MAX_PAGINAS = 20;

/**
 * Lê TODAS as linhas da tabela (em páginas de 1000), com os filtros de igualdade dados. Erro de
 * leitura LANÇA — virar "nenhum cliente" faria o assistente cadastrar de novo quem já existe.
 */
// deno-lint-ignore no-explicit-any
export async function lerTodosOsCadastros(sb: any, tabela: string, colunas: string, iguais: Record<string, unknown> = {}): Promise<Record<string, unknown>[]> {
  const todas: Record<string, unknown>[] = [];
  for (let p = 0; p < MAX_PAGINAS; p++) {
    let q = sb.from(tabela).select(colunas);
    for (const [c, v] of Object.entries(iguais)) q = q.eq(c, v);
    const { data, error } = await q.order("id").range(p * PAGINA, p * PAGINA + PAGINA - 1);
    if (error) throw error;
    const lote = (data as Record<string, unknown>[]) || [];
    todas.push(...lote);
    if (lote.length < PAGINA) break;
  }
  return todas;
}

/** Busca tolerante: lê os candidatos e devolve os que casam, do mais parecido ao menos, até `limite`. */
export async function buscarCadastro(
  // deno-lint-ignore no-explicit-any
  sb: any,
  tabela: string,
  colunas: string,
  termo: string,
  campos: CamposDaBusca,
  opcoes: { limite: number; iguais?: Record<string, unknown> },
): Promise<Record<string, unknown>[]> {
  const linhas = await lerTodosOsCadastros(sb, tabela, colunas, opcoes.iguais ?? {});
  return linhas
    .map((l) => ({ l, n: notaDoCadastro(l, termo, campos) }))
    .filter((x) => x.n > 0)
    .sort((a, b) => b.n - a.n || String(a.l.name ?? "").localeCompare(String(b.l.name ?? "")))
    .slice(0, opcoes.limite)
    .map((x) => x.l);
}

/**
 * Indicador de IE dito em palavras → o número que o CHECK chk_clients_ie_indicator aceita (1, 2, 9).
 * undefined = não veio; { error } = veio algo que não é nenhum dos três (recusa em vez de o banco
 * recusar com mensagem técnica — ou pior, o modelo mandar "isento" e a nota sair errada).
 */
export function traduzirIndicadorIE(v: unknown): number | undefined | { error: string } {
  if (v === undefined || v === null || v === "") return undefined;
  const t = semAcento(v).replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
  if (t === "1" || t === "contribuinte" || t === "contribuinte do icms" || t === "contribuinte icms") return 1;
  if (t === "2" || t === "isento" || t === "contribuinte isento" || t === "isento de ie" || t === "isenta") return 2;
  if (t === "9" || t === "nao contribuinte" || t === "consumidor" || t === "consumidor final" || t === "pessoa fisica") return 9;
  return {
    error: `Indicador de IE "${String(v)}" não existe. Use: contribuinte (1), isento (2) ou não contribuinte (9).`,
  };
}
