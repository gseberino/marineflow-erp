import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  baixarMidia,
  baixarMidiaPelaChave,
  chaveConfere,
  chaveDoPayload,
  LIMITE_BYTES,
  sha256Hex,
  tamanhoDeclarado,
  telefoneDaChave,
  tipoReal,
} from "./midia.ts";
import { paraBase64 } from "../dropbox/nucleo.ts";

const b = (...xs: number[]) => new Uint8Array(xs);
const txt = (s: string) => new TextEncoder().encode(s);
function junta(...partes: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(partes.reduce((n, p) => n + p.length, 0));
  let i = 0;
  for (const p of partes) { out.set(p, i); i += p.length; }
  return out;
}

// ─── tipoReal ─────────────────────────────────────────────────────────────────────────────

Deno.test("tipoReal: as assinaturas aceitas", () => {
  assertEquals(tipoReal(txt("%PDF-1.7\n...")), { mime: "application/pdf", ext: "pdf" });
  assertEquals(tipoReal(b(0xff, 0xd8, 0xff, 0xe0, 0, 0)), { mime: "image/jpeg", ext: "jpg" });
  assertEquals(tipoReal(b(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)), { mime: "image/png", ext: "png" });
  assertEquals(tipoReal(junta(txt("RIFF"), b(1, 2, 3, 4), txt("WEBPVP8 "))), { mime: "image/webp", ext: "webp" });
  for (const marca of ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]) {
    assertEquals(tipoReal(junta(b(0, 0, 0, 0x18), txt("ftyp"), txt(marca), b(0, 0, 0, 0))), { mime: "image/heic", ext: "heic" }, marca);
  }
  assertEquals(tipoReal(txt('<?xml version="1.0"?><nfeProc/>')), { mime: "application/xml", ext: "xml" });
  assertEquals(tipoReal(junta(b(0xef, 0xbb, 0xbf), txt("<?xml version"))), { mime: "application/xml", ext: "xml" });
});

Deno.test("tipoReal: NF-e sem a declaração <?xml é XML (como no leitor), com BOM e espaço antes", () => {
  for (const raiz of ["<nfeProc versao=\"4.00\">", "<NFe xmlns=\"x\">", "<procNFe>", "<CFe>", "<nfseProc>", "<CompNfse>"]) {
    assertEquals(tipoReal(txt(raiz)), { mime: "application/xml", ext: "xml" }, raiz);
  }
  assertEquals(tipoReal(junta(b(0xef, 0xbb, 0xbf), txt("\r\n  <nfeProc>"))), { mime: "application/xml", ext: "xml" });
  assertEquals(tipoReal(txt("  <?xml version=\"1.0\"?>")), { mime: "application/xml", ext: "xml" });
  // outro XML/HTML sem declaração continua recusado
  assertEquals(tipoReal(txt("<html><body>")), null);
  assertEquals(tipoReal(txt("<nfeProcessado>")), null);
});

// ─── a key da mensagem ────────────────────────────────────────────────────────────────────

Deno.test("chaveDoPayload: só id, remoteJid, fromMe e (se houver) senderPn/remoteJidAlt", () => {
  const raw = { data: { key: { id: "W1", remoteJid: "5547999990000@s.whatsapp.net", fromMe: false, remoteJidAlt: "123@lid", participant: "x" } } };
  assertEquals(chaveDoPayload(raw), { id: "W1", remoteJid: "5547999990000@s.whatsapp.net", fromMe: false, remoteJidAlt: "123@lid" });
  assertEquals(chaveDoPayload({ data: { key: { remoteJid: "x" } } }), null);
  assertEquals(chaveDoPayload({ data: {} }), null);
  assertEquals(chaveDoPayload(null), null);
});

Deno.test("chaveConfere: recebida, desta mensagem e desta conversa (inclusive LID)", () => {
  const boa = { id: "W1", remoteJid: "5547999990000@s.whatsapp.net", fromMe: false };
  assertEquals(chaveConfere(boa, "5547999990000", "W1"), true);
  // número sem o 9 (12 dígitos) normaliza como o parser do webhook
  assertEquals(chaveConfere({ ...boa, remoteJid: "554799990000@s.whatsapp.net" }, "5547999990000", "W1"), true);
  assertEquals(chaveConfere({ ...boa, fromMe: true }, "5547999990000", "W1"), false);
  assertEquals(chaveConfere({ ...boa, id: "OUTRA" }, "5547999990000", "W1"), false);
  assertEquals(chaveConfere({ ...boa, remoteJid: "5511988887777@s.whatsapp.net" }, "5547999990000", "W1"), false); // foto de cliente
  assertEquals(chaveConfere({ id: "W1", remoteJid: "98765@lid", fromMe: false, senderPn: "5547999990000@s.whatsapp.net" }, "5547999990000", "W1"), true);
  assertEquals(chaveConfere({ id: "W1", remoteJid: "98765@lid", fromMe: false }, "5547999990000", "W1"), false);
  assertEquals(chaveConfere(null, "5547999990000", "W1"), false);
  assertEquals(chaveConfere(boa, null, "W1"), false);
  assertEquals(telefoneDaChave({ remoteJid: "98765@lid", remoteJidAlt: "5547999990000@s.whatsapp.net" }), "5547999990000");
});

Deno.test("tipoReal: PDF com lixo antes do cabeçalho (até 1024 bytes)", () => {
  assertEquals(tipoReal(junta(new Uint8Array(500).fill(0x20), txt("%PDF-1.4"))), { mime: "application/pdf", ext: "pdf" });
  assertEquals(tipoReal(junta(new Uint8Array(2000).fill(0x20), txt("%PDF-1.4"))), null);
});

Deno.test("tipoReal: o resto é recusado (zip/xlsx, mp4, texto, vazio)", () => {
  assertEquals(tipoReal(b(0x50, 0x4b, 0x03, 0x04, 0, 0)), null); // zip / xlsx
  assertEquals(tipoReal(junta(b(0, 0, 0, 0x18), txt("ftypmp42"), b(0, 0, 0, 0))), null); // vídeo
  assertEquals(tipoReal(txt("olá, isto é texto")), null);
  assertEquals(tipoReal(new Uint8Array(0)), null);
  assertEquals(tipoReal(b(0xff, 0xd8)), null);
});

Deno.test("sha256Hex: vetor conhecido", async () => {
  assertEquals(await sha256Hex(txt("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

// ─── tamanhoDeclarado ─────────────────────────────────────────────────────────────────────

Deno.test("tamanhoDeclarado: número, texto, Long e envelope", () => {
  assertEquals(tamanhoDeclarado({ data: { message: { imageMessage: { fileLength: 1234 } } } }), 1234);
  assertEquals(tamanhoDeclarado({ data: { message: { documentMessage: { fileLength: "99999999" } } } }), 99999999);
  assertEquals(tamanhoDeclarado({ data: { message: { documentMessage: { fileLength: { low: 10, high: 1 } } } } }), 10 + 0x100000000);
  assertEquals(
    tamanhoDeclarado({ data: { message: { documentWithCaptionMessage: { message: { documentMessage: { fileLength: 77 } } } } } }),
    77,
  );
  assertEquals(tamanhoDeclarado({ data: { message: { conversation: "oi" } } }), null);
  assertEquals(tamanhoDeclarado(null), null);
});

// ─── baixarMidia ──────────────────────────────────────────────────────────────────────────

/** O ambiente é do processo inteiro (outros testes mexem nele): cada teste ajusta o seu. */
function comEvolution() {
  Deno.env.set("EVOLUTION_API_URL", "https://evo.exemplo.test/");
  Deno.env.set("EVOLUTION_API_KEY", "chave-de-fachada");
  Deno.env.set("EVOLUTION_INSTANCE", "hbr-local");
}

const RAW = { data: { key: { id: "WAMSG1", remoteJid: "5547999990000@s.whatsapp.net", fromMe: false }, message: {} } };

function respostaJson(corpo: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json", ...extra } });
}

Deno.test("baixarMidia: sem data.key = sem_chave, sem chamar a Evolution", async () => {
  let chamou = false;
  const f = (() => { chamou = true; return Promise.resolve(respostaJson({})); }) as typeof fetch;
  assertEquals(await baixarMidia({ data: {} }, { fetch: f }), { ok: false, erro: "sem_chave" });
  assertEquals(await baixarMidia(null, { fetch: f }), { ok: false, erro: "sem_chave" });
  assertEquals(chamou, false);
});

Deno.test("baixarMidia: sucesso — mesmo caminho do read-media, bytes e mime declarado", async () => {
  comEvolution();
  const chamadas: Array<{ url: string; init?: RequestInit }> = [];
  const conteudo = txt("%PDF-1.7 conteudo");
  const f = ((url: string, init?: RequestInit) => {
    chamadas.push({ url, init });
    return Promise.resolve(respostaJson({ base64: paraBase64(conteudo), mimetype: "application/pdf; x=1" }));
  }) as typeof fetch;
  const r = await baixarMidia(RAW, { fetch: f });
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.bytes, conteudo);
    assertEquals(r.mimeDeclarado, "application/pdf");
  }
  assertEquals(chamadas[0].url, "https://evo.exemplo.test/chat/getBase64FromMediaMessage/hbr-local");
  assertEquals(JSON.parse(String(chamadas[0].init?.body)), { message: { key: RAW.data.key } });
  assertEquals((chamadas[0].init?.headers as Record<string, string>).apikey, "chave-de-fachada");
});

Deno.test("baixarMidia: 5xx e rede = evolution_fora; 4xx e corpo sem base64 = midia_indisponivel", async () => {
  comEvolution();
  const com =(r: () => Promise<Response>) => ({ fetch: r as unknown as typeof fetch });
  assertEquals(await baixarMidia(RAW, com(() => Promise.resolve(respostaJson({}, 502)))), { ok: false, erro: "evolution_fora" });
  assertEquals(await baixarMidia(RAW, com(() => Promise.reject(new Error("ECONNREFUSED")))), { ok: false, erro: "evolution_fora" });
  assertEquals(await baixarMidia(RAW, com(() => Promise.resolve(respostaJson({ error: "x" }, 400)))), { ok: false, erro: "midia_indisponivel" });
  assertEquals(await baixarMidia(RAW, com(() => Promise.resolve(respostaJson({ message: "sem mídia" })))), { ok: false, erro: "midia_indisponivel" });
  assertEquals(await baixarMidia(RAW, com(() => Promise.resolve(new Response("não é json")))), { ok: false, erro: "midia_indisponivel" });
});

Deno.test("baixarMidia: resposta maior que o limite = arquivo_grande, sem ler o corpo", async () => {
  comEvolution();
  const grande = String(Math.ceil(LIMITE_BYTES / 3) * 4 + 200_000);
  const f = (() => Promise.resolve(respostaJson({ base64: "AAAA" }, 200, { "content-length": grande }))) as unknown as typeof fetch;
  assertEquals(await baixarMidia(RAW, { fetch: f }), { ok: false, erro: "arquivo_grande" });
});

Deno.test("baixarMidia: sem content-length, para de ler no teto (arquivo_grande), sem carregar o resto", async () => {
  comEvolution();
  const teto = Math.ceil(LIMITE_BYTES / 3) * 4 + 64 * 1024;
  let entregues = 0;
  let cancelado = false;
  const pedaco = new Uint8Array(1024 * 1024).fill(0x41);
  const corpo = new ReadableStream<Uint8Array>({
    pull(c) {
      if (entregues > teto + 5 * pedaco.length) { c.close(); return; }
      entregues += pedaco.length;
      c.enqueue(pedaco);
    },
    cancel() { cancelado = true; },
  });
  const f = (() => Promise.resolve(new Response(corpo, { status: 200 }))) as unknown as typeof fetch;
  assertEquals(await baixarMidia(RAW, { fetch: f }), { ok: false, erro: "arquivo_grande" });
  assertEquals(cancelado, true);
  assertEquals(entregues <= teto + 2 * pedaco.length, true);
});

Deno.test("baixarMidiaPelaChave: usa a key dada (a guardada na linha), sem raw_payload", async () => {
  comEvolution();
  const chamadas: Array<RequestInit | undefined> = [];
  const f = ((_u: string, init?: RequestInit) => {
    chamadas.push(init);
    return Promise.resolve(respostaJson({ base64: paraBase64(txt("%PDF-1.7")) }));
  }) as typeof fetch;
  const chave = { id: "W1", remoteJid: "5547999990000@s.whatsapp.net", fromMe: false };
  assertEquals((await baixarMidiaPelaChave(chave, { fetch: f })).ok, true);
  assertEquals(JSON.parse(String(chamadas[0]?.body)), { message: { key: chave } });
  assertEquals(await baixarMidiaPelaChave(null, { fetch: f }), { ok: false, erro: "sem_chave" });
});

Deno.test("baixarMidia: tempo esgotado = evolution_fora", async () => {
  comEvolution();
  const f = ((_u: string, init?: RequestInit) =>
    new Promise<Response>((_ok, falha) => {
      init?.signal?.addEventListener("abort", () => falha(new DOMException("tempo", "TimeoutError")));
    })) as typeof fetch;
  assertEquals(await baixarMidia(RAW, { fetch: f, timeoutMs: 20 }), { ok: false, erro: "evolution_fora" });
});

Deno.test("baixarMidia: sem credencial da Evolution = evolution_fora", async () => {
  comEvolution();
  Deno.env.delete("EVOLUTION_API_KEY");
  try {
    assertEquals(await baixarMidia(RAW, { fetch: (() => Promise.resolve(respostaJson({}))) as unknown as typeof fetch }), { ok: false, erro: "evolution_fora" });
  } finally {
    comEvolution();
  }
});
