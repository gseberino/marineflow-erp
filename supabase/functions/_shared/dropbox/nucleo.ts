// Peças puras da integração com o Dropbox (Fase 2, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
// Sem rede e sem banco: tudo aqui tem teste em nucleo_test.ts.

/**
 * O Dropbox-API-Arg vai num cabeçalho HTTP, e cabeçalho só carrega ASCII: todo caractere a partir
 * de 0x7F precisa virar \uXXXX (docs.dropboxapi.com › json-encoding). Sem isso, "ORÇ" e "Ã" chegam
 * corrompidos — o Deno aceita Latin-1 no Headers e manda os bytes crus, sem erro nenhum.
 * Emoji já sai como par de surrogates do charCodeAt, que é JSON válido.
 */
export function argParaCabecalho(arg: unknown): string {
  return JSON.stringify(arg).replace(
    /[\u007f-￿]/g,
    (c) => "\\u" + ("000" + c.charCodeAt(0).toString(16)).slice(-4),
  );
}

// ---------------------------------------------------------------------------------------------
// Base64 (padrão e URL-safe) sobre bytes
// ---------------------------------------------------------------------------------------------
export function paraBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

export function deBase64(texto: string): Uint8Array<ArrayBuffer> {
  const s = atob(texto);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

function paraBase64Url(bytes: Uint8Array): string {
  return paraBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function deBase64Url(texto: string): Uint8Array<ArrayBuffer> {
  const b = texto.replace(/-/g, "+").replace(/_/g, "/");
  return deBase64(b + "===".slice((b.length + 3) % 4));
}

// ---------------------------------------------------------------------------------------------
// Cifra do refresh token (AES-GCM 256). A chave é o segredo DROPBOX_TOKEN_KEY (32 bytes em
// base64). Formato guardado: base64(iv[12] || texto cifrado com a etiqueta).
// ---------------------------------------------------------------------------------------------
async function chaveAes(chaveB64: string): Promise<CryptoKey> {
  const bruta = deBase64(chaveB64.trim());
  if (bruta.length !== 32) throw new Error("DROPBOX_TOKEN_KEY precisa ter 32 bytes em base64");
  return await crypto.subtle.importKey("raw", bruta, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function cifrar(texto: string, chaveB64: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cifrado = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await chaveAes(chaveB64), new TextEncoder().encode(texto)),
  );
  const tudo = new Uint8Array(iv.length + cifrado.length);
  tudo.set(iv);
  tudo.set(cifrado, iv.length);
  return paraBase64(tudo);
}

export async function decifrar(guardado: string, chaveB64: string): Promise<string> {
  const tudo = deBase64(guardado);
  const claro = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: tudo.slice(0, 12) },
    await chaveAes(chaveB64),
    tudo.slice(12),
  );
  return new TextDecoder().decode(claro);
}

// ---------------------------------------------------------------------------------------------
// "state" do OAuth: prova que a volta do Dropbox foi pedida por um admin nosso, há pouco tempo.
// Formato: base64url(json) + "." + base64url(HMAC-SHA256(json, segredo)). O segredo é o
// DROPBOX_APP_SECRET (só o servidor conhece).
// ---------------------------------------------------------------------------------------------
export type Estado = { uid: string; exp: number; n: string };

async function hmac(dados: string, segredo: string): Promise<Uint8Array> {
  const chave = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(segredo),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", chave, new TextEncoder().encode(dados)));
}

function iguais(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

export async function assinarEstado(uid: string, segredo: string, agoraMs = Date.now(), validadeMin = 10): Promise<string> {
  const corpo: Estado = {
    uid,
    exp: agoraMs + validadeMin * 60_000,
    n: paraBase64Url(crypto.getRandomValues(new Uint8Array(9))),
  };
  const json = JSON.stringify(corpo);
  return `${paraBase64Url(new TextEncoder().encode(json))}.${paraBase64Url(await hmac(json, segredo))}`;
}

/** Devolve o estado se a assinatura confere e não venceu; senão null. */
export async function conferirEstado(estado: string, segredo: string, agoraMs = Date.now()): Promise<Estado | null> {
  const [corpoB64, assinaturaB64] = (estado || "").split(".");
  if (!corpoB64 || !assinaturaB64) return null;
  let json: string;
  let assinatura: Uint8Array;
  try {
    json = new TextDecoder().decode(deBase64Url(corpoB64));
    assinatura = deBase64Url(assinaturaB64);
  } catch {
    return null;
  }
  if (!iguais(assinatura, await hmac(json, segredo))) return null;
  try {
    const e = JSON.parse(json) as Estado;
    if (typeof e.uid !== "string" || typeof e.exp !== "number" || e.exp < agoraMs) return null;
    return e;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------
// Erros da API: o que fazer com cada resposta
// ---------------------------------------------------------------------------------------------
export type DecisaoDeErro =
  | { tipo: "renovar_token" }
  | { tipo: "esperar"; segundos: number }
  | { tipo: "repetir_depois" }
  | { tipo: "desistir" };

/** 401 renova uma vez; 429 respeita o Retry-After; 5xx tenta mais tarde; o resto não adianta repetir. */
export function decidirErro(status: number, retryAfter: string | null): DecisaoDeErro {
  if (status === 401) return { tipo: "renovar_token" };
  if (status === 429) {
    const s = Number(retryAfter);
    return { tipo: "esperar", segundos: Number.isFinite(s) && s > 0 ? Math.min(s, 300) : 5 };
  }
  if (status >= 500) return { tipo: "repetir_depois" };
  return { tipo: "desistir" };
}

/** A URL de autorização (fluxo com código, refresh token que não expira). */
export function urlDeAutorizacao(p: { appKey: string; redirectUri: string; estado: string }): string {
  const q = new URLSearchParams({
    client_id: p.appKey,
    response_type: "code",
    token_access_type: "offline",
    redirect_uri: p.redirectUri,
    state: p.estado,
  });
  return `https://www.dropbox.com/oauth2/authorize?${q.toString()}`;
}

/** Link para o dono abrir a pasta no site (precisa estar logado na conta). */
export function linkNoSite(caminho: string): string {
  return "https://www.dropbox.com/home" + caminho.split("/").map((p) => encodeURIComponent(p)).join("/");
}

// ---------------------------------------------------------------------------------------------
// Nomes de pasta e de arquivo (Fase 2B/2C)
// ---------------------------------------------------------------------------------------------

/** O estilo das pastas do dono: sem acento, palavras unidas por "_" ("0021.002.26_Onibus_Cris_e_Talyta"). */
export function trechoDeNome(texto: string): string {
  return (texto || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9.-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^[_.-]+|[_.-]+$/g, "")
    .slice(0, 60);
}

// Nome de barco que não identifica ninguém sozinho: a pasta leva o cliente junto
// ("0015.012.25_Sandro_Poeta_Motorhome").
const GENERICOS = new Set([
  "motorhome", "motor home", "mh", "lancha", "barco", "bote", "onibus", "trailer", "camper",
  "catamara", "veleiro", "embarcacao", "veiculo", "equipamento", "automovel", "teste",
]);

export function nomeDaPasta(codigo: string, barco: string | null, cliente: string | null): string {
  const b = trechoDeNome(barco ?? "");
  const c = trechoDeNome(cliente ?? "");
  const generico = !b || GENERICOS.has(b.toLowerCase().replace(/_/g, " "));
  const partes = generico ? [c, b] : [b];
  const nome = partes.filter(Boolean).join("_") || "Sem_nome";
  return `${codigo}_${nome}`;
}

/** As subpastas do modelo do dono (a da 0016.013.25_Dona V), mais as fotos. */
export const SUBPASTAS = [
  "1- DOC's",
  "1- DOC's/Orçamentos e OS",
  "2- ELÉTRICA",
  "2- ELÉTRICA/1- DOC'S",
  "2- ELÉTRICA/2- DWG",
  "2- ELÉTRICA/3- PDF",
  "2- ELÉTRICA/4- CONFIG",
  "3- FOTOS",
];

export const PASTA_DOS_PDFS = "1- DOC's/Orçamentos e OS";

/** A data de hoje em São Paulo, AAAA-MM-DD (o nome do arquivo usa o dia do dono, não o UTC). */
export function dataEmSaoPaulo(agora = new Date()): string {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(agora);
  return p; // en-CA já sai AAAA-MM-DD
}

/** "2026-10-08 ORÇ-00112 v2.pdf" — o número fica com o Ç (o cabeçalho escapa). */
export function nomeDoPdf(data: string, numero: string, versao: number): string {
  const n = (numero || "documento").replace(/[\/:*?"<>|]+/g, "-").trim();
  return `${data} ${n} v${versao}.pdf`;
}

export function nomeDoPdfAssinado(data: string, numero: string): string {
  const n = (numero || "documento").replace(/[\/:*?"<>|]+/g, "-").trim();
  return `${data} ${n} assinado.pdf`;
}

/** Cliente genérico não ganha pasta (é um balaio de orçamentos avulsos). */
export function clienteGenerico(nome: string | null | undefined): boolean {
  const n = trechoDeNome(nome ?? "").toLowerCase();
  return n === "cliente_final" || n.startsWith("cliente_final_") || n.startsWith("teste");
}

// ---------------------------------------------------------------------------------------------
// Índice (Fase 3)
// ---------------------------------------------------------------------------------------------

/** A pasta registrada mais funda que contém o caminho (chaves do mapa em minúsculas). */
export function pastaQueContem<T>(caminhoLower: string, pastas: Map<string, T>): T | null {
  const partes = caminhoLower.split("/");
  for (let n = partes.length - 1; n > 1; n--) {
    const p = pastas.get(partes.slice(0, n).join("/"));
    if (p) return p;
  }
  return null;
}

/** "0026.007.26_Madu_I" → "0026.007.26"; nome sem número → null. */
export function codigoNoNome(nome: string): string | null {
  const m = /^(\d{4}\.\d{3}\.\d{2})(?:[_\s-]|$)/.exec(nome.trim());
  return m ? m[1] : null;
}

/** O caminho é filho direto (não neto) da pasta? Tudo em minúsculas. */
export function filhaDireta(caminhoLower: string, paiLower: string): boolean {
  const pai = paiLower.replace(/\/+$/, "");
  if (!caminhoLower.startsWith(pai + "/")) return false;
  return !caminhoLower.slice(pai.length + 1).includes("/");
}

export function extensaoDe(nome: string): string | null {
  const i = nome.lastIndexOf(".");
  return i > 0 && i < nome.length - 1 ? nome.slice(i + 1).toLowerCase().slice(0, 10) : null;
}
