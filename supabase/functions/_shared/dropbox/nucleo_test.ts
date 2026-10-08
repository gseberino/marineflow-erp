import { assert, assertEquals, assertNotEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  argParaCabecalho,
  assinarEstado,
  cifrar,
  conferirEstado,
  decidirErro,
  decifrar,
  linkNoSite,
  paraBase64,
  urlDeAutorizacao,
} from "./nucleo.ts";

const CHAVE = paraBase64(new Uint8Array(32).map((_, i) => i + 1));

Deno.test("cabeçalho: acentos viram \\uXXXX e o resto fica igual", () => {
  const s = argParaCabecalho({ path: "/MANAGEMENT/COMMERCIAL/B2C/0026.007.26_Ônibus/ORÇ-00112 Ã.pdf", mode: "add" });
  assert(/^[\x20-\x7e]+$/.test(s), "só ASCII imprimível");
  assert(s.includes("\\u00d4nibus"));
  assert(s.includes("OR\\u00c7-00112"));
  assert(s.includes("\\u00c3.pdf"));
  assertEquals(JSON.parse(s).path, "/MANAGEMENT/COMMERCIAL/B2C/0026.007.26_Ônibus/ORÇ-00112 Ã.pdf");
});

Deno.test("cabeçalho: emoji e DEL também escapam e o JSON volta igual", () => {
  const original = { path: "/a/barco ⛵ 🚤\u007f.pdf" };
  const s = argParaCabecalho(original);
  assert(/^[\x20-\x7e]+$/.test(s));
  assertEquals(JSON.parse(s), original);
});

Deno.test("cifra: ida e volta, e cada cifra sai diferente (iv aleatório)", async () => {
  const a = await cifrar("refresh-token-de-teste", CHAVE);
  const b = await cifrar("refresh-token-de-teste", CHAVE);
  assertNotEquals(a, b);
  assertEquals(await decifrar(a, CHAVE), "refresh-token-de-teste");
});

Deno.test("cifra: chave errada não decifra", async () => {
  const outra = paraBase64(new Uint8Array(32).fill(9));
  const c = await cifrar("x", CHAVE);
  await assertRejects(() => decifrar(c, outra));
});

Deno.test("cifra: chave de tamanho errado é recusada", async () => {
  await assertRejects(() => cifrar("x", paraBase64(new Uint8Array(16))), Error, "32 bytes");
});

Deno.test("estado: confere, vence e não aceita adulteração", async () => {
  const agora = 1_800_000_000_000;
  const e = await assinarEstado("user-1", "segredo", agora, 10);
  assertEquals((await conferirEstado(e, "segredo", agora + 60_000))?.uid, "user-1");
  assertEquals(await conferirEstado(e, "segredo", agora + 11 * 60_000), null, "venceu");
  assertEquals(await conferirEstado(e, "outro-segredo", agora), null, "segredo errado");
  const [corpo, ass] = e.split(".");
  const forjado = btoa(JSON.stringify({ uid: "intruso", exp: agora + 1e9, n: "x" })).replace(/=+$/, "");
  assertEquals(await conferirEstado(`${forjado}.${ass}`, "segredo", agora), null, "corpo trocado");
  assertEquals(await conferirEstado(corpo, "segredo", agora), null, "sem assinatura");
  assertEquals(await conferirEstado("", "segredo", agora), null);
});

Deno.test("erros: 401 renova, 429 espera o Retry-After, 5xx repete depois, 409 desiste", () => {
  assertEquals(decidirErro(401, null), { tipo: "renovar_token" });
  assertEquals(decidirErro(429, "7"), { tipo: "esperar", segundos: 7 });
  assertEquals(decidirErro(429, null), { tipo: "esperar", segundos: 5 });
  assertEquals(decidirErro(429, "99999"), { tipo: "esperar", segundos: 300 });
  assertEquals(decidirErro(503, null), { tipo: "repetir_depois" });
  assertEquals(decidirErro(409, null), { tipo: "desistir" });
  assertEquals(decidirErro(400, null), { tipo: "desistir" });
});

Deno.test("autorização: pede refresh token (offline) e manda o redirect e o state", () => {
  const u = new URL(urlDeAutorizacao({ appKey: "abc", redirectUri: "https://x.supabase.co/functions/v1/dropbox-conectar", estado: "e.s" }));
  assertEquals(u.origin + u.pathname, "https://www.dropbox.com/oauth2/authorize");
  assertEquals(u.searchParams.get("token_access_type"), "offline");
  assertEquals(u.searchParams.get("response_type"), "code");
  assertEquals(u.searchParams.get("client_id"), "abc");
  assertEquals(u.searchParams.get("state"), "e.s");
  assertEquals(u.searchParams.get("redirect_uri"), "https://x.supabase.co/functions/v1/dropbox-conectar");
});

Deno.test("link no site: codifica cada parte do caminho", () => {
  assertEquals(
    linkNoSite("/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V"),
    "https://www.dropbox.com/home/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona%20V",
  );
});

import { clienteGenerico, dataEmSaoPaulo, nomeDaPasta, nomeDoPdf, nomeDoPdfAssinado, trechoDeNome } from "./nucleo.ts";

Deno.test("nome da pasta: no estilo do dono, sem acento e com _", () => {
  assertEquals(nomeDaPasta("0026.007.26", "Madu I", "Edson Luiz Rudek Junior"), "0026.007.26_Madu_I");
  assertEquals(nomeDaPasta("0026.007.26", "Comandante Zepi", "Ribas"), "0026.007.26_Comandante_Zepi");
  assertEquals(nomeDaPasta("0026.007.26", "S.I. 8.5 Automático", "x"), "0026.007.26_S.I._8.5_Automatico");
});

Deno.test("nome da pasta: barco genérico leva o cliente junto", () => {
  assertEquals(nomeDaPasta("0026.007.26", "Motorhome", "Sandro Poeta"), "0026.007.26_Sandro_Poeta_Motorhome");
  assertEquals(nomeDaPasta("0026.007.26", "Ônibus", "Cris e Talyta"), "0026.007.26_Cris_e_Talyta_Onibus");
  assertEquals(nomeDaPasta("0026.007.26", "", "José"), "0026.007.26_Jose");
  assertEquals(nomeDaPasta("0026.007.26", null, null), "0026.007.26_Sem_nome");
});

Deno.test("trecho de nome: tira barra, aspas e espaços duplos", () => {
  assertEquals(trechoDeNome('  A/B "C"  d  '), "A_B_C_d");
});

Deno.test("nome do PDF: data, número com Ç e versão", () => {
  assertEquals(nomeDoPdf("2026-10-08", "ORÇ-00112", 2), "2026-10-08 ORÇ-00112 v2.pdf");
  assertEquals(nomeDoPdf("2026-10-08", "OS/00112", 1), "2026-10-08 OS-00112 v1.pdf");
  assertEquals(nomeDoPdfAssinado("2026-10-08", "OS-00112"), "2026-10-08 OS-00112 assinado.pdf");
});

Deno.test("data em São Paulo: 02:00 UTC ainda é o dia anterior", () => {
  assertEquals(dataEmSaoPaulo(new Date("2026-10-08T02:00:00Z")), "2026-10-07");
  assertEquals(dataEmSaoPaulo(new Date("2026-10-08T15:00:00Z")), "2026-10-08");
});

Deno.test("cliente genérico não ganha pasta", () => {
  assertEquals(clienteGenerico("Cliente Final"), true);
  assertEquals(clienteGenerico("TESTE AUDITORIA CLAUDE"), true);
  assertEquals(clienteGenerico("Acrisio Lopes Cançado Filho"), false);
});

import { codigoNoNome, extensaoDe, filhaDireta, pastaQueContem } from "./nucleo.ts";

Deno.test("índice: arquivo cai na pasta registrada mais funda", () => {
  const pastas = new Map([
    ["/management/commercial/b2c/0020.001.26_la_osadia", "principal"],
    ["/management/commercial/b2c/0020.001.26_la_osadia/1- doc's", "subpasta"],
    ["/management/commercial/b2c/0016.013.25_dona v", "dona v"],
  ]);
  assertEquals(pastaQueContem("/management/commercial/b2c/0020.001.26_la_osadia/1- doc's/x.pdf", pastas), "subpasta");
  assertEquals(pastaQueContem("/management/commercial/b2c/0020.001.26_la_osadia/1- elétrica/a/b.dwg", pastas), "principal");
  assertEquals(pastaQueContem("/management/commercial/b2c/0016.013.25_dona v/2- elétrica/x.pdf", pastas), "dona v");
  assertEquals(pastaQueContem("/management/commercial/b2c/solto.pdf", pastas), null);
  // "dona v" não pode casar com "dona vitória" (prefixo de texto, não de pasta)
  assertEquals(pastaQueContem("/management/commercial/b2c/0016.013.25_dona vitoria/x.pdf", pastas), null);
});

Deno.test("índice: número no nome da pasta nova", () => {
  assertEquals(codigoNoNome("0026.007.26_Madu_I"), "0026.007.26");
  assertEquals(codigoNoNome("0016.013.25_Dona V"), "0016.013.25");
  assertEquals(codigoNoNome("0026.007.26"), "0026.007.26");
  assertEquals(codigoNoNome("MH - Rosangela"), null);
  assertEquals(codigoNoNome("0026.007.267_x"), null);
});

Deno.test("índice: filha direta de B2C", () => {
  const b2c = "/management/commercial/b2c";
  assertEquals(filhaDireta("/management/commercial/b2c/0026.007.26_x", b2c), true);
  assertEquals(filhaDireta("/management/commercial/b2c/0026.007.26_x/1- doc's", b2c), false);
  assertEquals(filhaDireta("/management/commercial/b2b/fibrafort", b2c), false);
  assertEquals(filhaDireta("/management/commercial/b2c", b2c), false);
});

Deno.test("índice: extensão", () => {
  assertEquals(extensaoDe("ORÇ-00113 v1.PDF"), "pdf");
  assertEquals(extensaoDe("sem_extensao"), null);
  assertEquals(extensaoDe(".oculto"), null);
});
