// A mídia do comprovante (F1, 11/10/2026): o tipo REAL pelos bytes, o hash e o download da
// Evolution. Sem IA e sem banco.
//
// O download segue o caminho do whatsapp-read-media (POST /chat/getBase64FromMediaMessage com a
// key da mensagem): o webhook não traz o binário; a Evolution decifra. A mídia do WhatsApp expira
// em ~2 semanas, por isso o fluxo baixa na chegada e guarda no bucket.
import { deBase64 } from "../dropbox/nucleo.ts";
import { normalizePhoneNumber } from "../whatsapp/normalize.ts";
import type { Extensao } from "./nucleo.ts";

/** Maior arquivo aceito (o CHECK de comprovantes.arquivo_bytes é o mesmo). */
export const LIMITE_BYTES = 15 * 1024 * 1024;
/** Base64 de LIMITE_BYTES, com folga para o resto do JSON da Evolution. */
const LIMITE_RESPOSTA = Math.ceil(LIMITE_BYTES / 3) * 4 + 64 * 1024;

export type TipoReal = { mime: string; ext: Extensao };

const PDF: TipoReal = { mime: "application/pdf", ext: "pdf" };
/** As mesmas marcas do leitor (hbr-doc-worker, tipo-real.ts): a edge não pode recusar o que ele lê. */
const MARCAS_HEIC = new Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]);
/** NF-e/CF-e/NFS-e sem a declaração "<?xml" (o leitor aceita; a edge também). */
const RAIZ_DE_NOTA = /^<(nfeProc|NFe|procNFe|CFe|nfseProc|CompNfse)\b/;

function comeca(bytes: Uint8Array, assinatura: number[], deslocamento = 0): boolean {
  if (bytes.length < deslocamento + assinatura.length) return false;
  return assinatura.every((b, i) => bytes[deslocamento + i] === b);
}

function ascii(bytes: Uint8Array, inicio: number, fim: number): string {
  return String.fromCharCode(...bytes.subarray(inicio, Math.min(fim, bytes.length)));
}

/** "%PDF-" nos primeiros 1024 bytes (a norma tolera lixo antes do cabeçalho). */
function pdfNoComeco(bytes: Uint8Array): boolean {
  const alvo = [0x25, 0x50, 0x44, 0x46, 0x2d];
  const ate = Math.min(bytes.length - alvo.length, 1024);
  for (let i = 0; i <= ate; i++) if (comeca(bytes, alvo, i)) return true;
  return false;
}

/** O começo do arquivo como texto, sem BOM e sem espaço inicial (para reconhecer XML). */
function comecoDeTexto(bytes: Uint8Array): string {
  const semBom = comeca(bytes, [0xef, 0xbb, 0xbf]) ? 3 : 0;
  return new TextDecoder("utf-8", { fatal: false }).decode(bytes.subarray(semBom, Math.min(bytes.length, 2048))).trimStart();
}

/**
 * O tipo pelos bytes, nunca pelo que o WhatsApp declarou:
 * %PDF → pdf; FFD8FF → jpeg; 89504E47 → png; RIFF....WEBP → webp;
 * ftyp(heic|heix|hevc|hevx|heim|heis|mif1|msf1) → heic; "<?xml" ou a raiz de uma nota fiscal
 * (<nfeProc, <NFe, <CFe…), com ou sem BOM/espaço antes → xml. O resto = null.
 * Mesmas regras do leitor (hbr-doc-worker, tipo-real.ts).
 */
export function tipoReal(bytes: Uint8Array): TipoReal | null {
  if (!bytes || bytes.length < 4) return null;
  if (comeca(bytes, [0x25, 0x50, 0x44, 0x46])) return PDF;
  if (comeca(bytes, [0xff, 0xd8, 0xff])) return { mime: "image/jpeg", ext: "jpg" };
  if (comeca(bytes, [0x89, 0x50, 0x4e, 0x47])) return { mime: "image/png", ext: "png" };
  if (comeca(bytes, [0x52, 0x49, 0x46, 0x46]) && ascii(bytes, 8, 12) === "WEBP") return { mime: "image/webp", ext: "webp" };
  if (ascii(bytes, 4, 8) === "ftyp" && MARCAS_HEIC.has(ascii(bytes, 8, 12))) return { mime: "image/heic", ext: "heic" };
  if (pdfNoComeco(bytes)) return PDF;
  const texto = comecoDeTexto(bytes);
  if (texto.startsWith("<?xml") || RAIZ_DE_NOTA.test(texto)) return { mime: "application/xml", ext: "xml" };
  return null;
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const copia = new Uint8Array(bytes); // digest exige ArrayBuffer próprio (não SharedArrayBuffer)
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", copia));
  return [...h].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// deno-lint-ignore no-explicit-any
type Qualquer = any;

/** A mensagem de mídia de dentro do payload (desembrulha ephemeral/viewOnce/documentWithCaption). */
function mensagemDeMidia(raw: Qualquer): Record<string, unknown> | null {
  let m = raw?.data?.message;
  for (let nivel = 0; nivel < 3 && m && typeof m === "object"; nivel++) {
    const envelope = ["ephemeralMessage", "viewOnceMessage", "viewOnceMessageV2", "viewOnceMessageV2Extension", "documentWithCaptionMessage"]
      .map((k) => m[k]?.message)
      .find((x) => x && typeof x === "object");
    if (!envelope) break;
    m = envelope;
  }
  if (!m || typeof m !== "object") return null;
  const midia = m.imageMessage ?? m.documentMessage;
  return midia && typeof midia === "object" ? midia : null;
}

/**
 * O tamanho que o WhatsApp declarou (fileLength), para recusar arquivo grande ANTES de baixar:
 * um PDF de 100 MB em base64 derrubaria a função por memória, e a linha ficaria voltando ao vigia.
 * Vem como número, texto ou {low, high} (Long do protobuf). Desconhecido = null.
 */
export function tamanhoDeclarado(raw: unknown): number | null {
  const v = (mensagemDeMidia(raw) as Qualquer)?.fileLength;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && /^\d+$/.test(v)) return Number(v);
  if (v && typeof v === "object" && typeof v.low === "number") return (v.low >>> 0) + (Number(v.high) || 0) * 0x100000000;
  return null;
}

// ---------------------------------------------------------------------------------------------
// A key da mensagem na Evolution (o que o download pede)
// ---------------------------------------------------------------------------------------------

/** O que o fluxo guarda da key (comprovantes.wa_key): o suficiente para baixar e para conferir. */
export type ChaveDaMensagem = { id: string; remoteJid: string; fromMe: boolean; senderPn?: string; remoteJidAlt?: string };

function textoOuNada(v: unknown): string | undefined {
  return typeof v === "string" && v ? v.slice(0, 128) : undefined;
}

/** A key de raw_payload.data.key, só com as chaves que o download usa; sem id/remoteJid = null. */
export function chaveDoPayload(raw: unknown): ChaveDaMensagem | null {
  const k = (raw as Qualquer)?.data?.key;
  if (!k || typeof k !== "object") return null;
  const id = textoOuNada(k.id);
  const remoteJid = textoOuNada(k.remoteJid);
  if (!id || !remoteJid) return null;
  const chave: ChaveDaMensagem = { id, remoteJid, fromMe: k.fromMe === true };
  const senderPn = textoOuNada(k.senderPn);
  const remoteJidAlt = textoOuNada(k.remoteJidAlt);
  if (senderPn) chave.senderPn = senderPn;
  if (remoteJidAlt) chave.remoteJidAlt = remoteJidAlt;
  return chave;
}

/** O telefone da conversa pela key, com a MESMA regra do parser do webhook (LID → senderPn/remoteJidAlt). */
export function telefoneDaChave(chave: Pick<ChaveDaMensagem, "remoteJid" | "senderPn" | "remoteJidAlt">): string {
  const fonte = chave.remoteJid.endsWith("@lid") ? (chave.senderPn || chave.remoteJidAlt || chave.remoteJid) : chave.remoteJid;
  return normalizePhoneNumber(fonte);
}

/**
 * A key pode ser usada para baixar a mídia DESTA linha? Recebida (fromMe falso), com o id da
 * mensagem da linha e da conversa do telefone da linha. Sem isso, uma key trocada faria a edge
 * baixar da Evolution a mídia de outra conversa (a foto de um cliente) e guardá-la como CMP.
 */
export function chaveConfere(chave: unknown, phone: string | null | undefined, waMessageId: string | null | undefined): chave is ChaveDaMensagem {
  const c = chave as Partial<ChaveDaMensagem> | null;
  if (!c || typeof c !== "object" || typeof c.id !== "string" || typeof c.remoteJid !== "string") return false;
  if (c.fromMe === true || !phone || !waMessageId || c.id !== waMessageId) return false;
  return telefoneDaChave(c as ChaveDaMensagem) === phone;
}

export type ResultadoDoDownload =
  | { ok: true; bytes: Uint8Array; mimeDeclarado: string | null }
  | { ok: false; erro: "sem_chave" | "midia_indisponivel" | "evolution_fora" | "arquivo_grande" };

/** Lê o corpo em pedaços e para no teto (sem content-length, res.json() leria tudo antes de medir). */
async function corpoComTeto(res: Response, teto: number): Promise<Uint8Array | "grande"> {
  if (!res.body) return new Uint8Array(0);
  const leitor = res.body.getReader();
  const partes: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    total += value.length;
    if (total > teto) {
      await leitor.cancel().catch(() => {});
      return "grande";
    }
    partes.push(value);
  }
  const tudo = new Uint8Array(total);
  let pos = 0;
  for (const p of partes) {
    tudo.set(p, pos);
    pos += p.length;
  }
  return tudo;
}

/** baixarMidiaPelaChave com a key de raw_payload.data.key (o caminho do whatsapp-read-media). */
export function baixarMidia(
  rawPayload: unknown,
  opts: { fetch?: typeof fetch; timeoutMs?: number } = {},
): Promise<ResultadoDoDownload> {
  return baixarMidiaPelaChave((rawPayload as Qualquer)?.data?.key, opts);
}

/**
 * Baixa a mídia pela Evolution com a key dada. Sem IA, timeout de 30 s.
 * Sem key = sem_chave (final); 5xx, rede ou tempo = evolution_fora (tenta de novo);
 * 4xx ou corpo sem base64 = midia_indisponivel; resposta maior que o limite = arquivo_grande
 * (pelo content-length ou contando os bytes enquanto lê: nunca carrega mais que o teto).
 */
export async function baixarMidiaPelaChave(
  chave: unknown,
  opts: { fetch?: typeof fetch; timeoutMs?: number } = {},
): Promise<ResultadoDoDownload> {
  const key = chave as Qualquer;
  if (!key || typeof key !== "object" || !key.id) return { ok: false, erro: "sem_chave" };

  const evoUrl = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/$/, "");
  const evoKey = Deno.env.get("EVOLUTION_API_KEY") || "";
  const instancia = Deno.env.get("EVOLUTION_INSTANCE") || "hbr-local";
  if (!evoUrl || !evoKey) return { ok: false, erro: "evolution_fora" };

  const f = opts.fetch ?? fetch;
  let res: Response;
  try {
    res = await f(`${evoUrl}/chat/getBase64FromMediaMessage/${instancia}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: evoKey },
      body: JSON.stringify({ message: { key } }),
      signal: AbortSignal.timeout(opts.timeoutMs ?? 30_000),
    });
  } catch {
    return { ok: false, erro: "evolution_fora" };
  }
  if (!res.ok) {
    await res.body?.cancel().catch(() => {});
    return { ok: false, erro: res.status >= 500 ? "evolution_fora" : "midia_indisponivel" };
  }
  if (Number(res.headers.get("content-length") ?? "0") > LIMITE_RESPOSTA) {
    await res.body?.cancel().catch(() => {});
    return { ok: false, erro: "arquivo_grande" };
  }

  let corpo: Qualquer;
  try {
    const bruto = await corpoComTeto(res, LIMITE_RESPOSTA);
    if (bruto === "grande") return { ok: false, erro: "arquivo_grande" };
    corpo = JSON.parse(new TextDecoder().decode(bruto));
  } catch (e) {
    const nome = (e as Error)?.name ?? "";
    return { ok: false, erro: nome === "TimeoutError" || nome === "AbortError" ? "evolution_fora" : "midia_indisponivel" };
  }
  const b64 = typeof corpo?.base64 === "string" ? corpo.base64 : typeof corpo === "string" ? corpo : null;
  if (!b64) return { ok: false, erro: "midia_indisponivel" };
  if (b64.length > LIMITE_RESPOSTA) return { ok: false, erro: "arquivo_grande" };

  let bytes: Uint8Array;
  try {
    bytes = deBase64(b64.replace(/^data:[^,]*,/, "").replace(/\s+/g, ""));
  } catch {
    return { ok: false, erro: "midia_indisponivel" };
  }
  if (bytes.length === 0) return { ok: false, erro: "midia_indisponivel" };
  const mime = typeof corpo?.mimetype === "string" ? corpo.mimetype.split(";")[0].trim().toLowerCase() : "";
  return { ok: true, bytes, mimeDeclarado: mime || null };
}
