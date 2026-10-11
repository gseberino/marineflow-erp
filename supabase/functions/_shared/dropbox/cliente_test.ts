// Os métodos do cliente Dropbox que a F2 dos comprovantes usa (mover, substituir, criarPasta),
// contra um fetch falso: nenhuma chamada sai para o Dropbox de verdade.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { Dropbox, ErroDropbox } from "./cliente.ts";

type Chamada = { url: string; arg: unknown; corpo: unknown };

/** Troca o fetch global pelo roteiro de respostas; devolve as chamadas que chegaram. */
async function comFetch(respostas: Array<() => Response>, f: (dbx: Dropbox) => Promise<void>): Promise<Chamada[]> {
  const chamadas: Chamada[] = [];
  const original = globalThis.fetch;
  let i = 0;
  globalThis.fetch = (async (entrada: Request | URL | string, init?: RequestInit) => {
    const req = entrada instanceof Request ? entrada : new Request(entrada, init);
    const arg = req.headers.get("Dropbox-API-Arg");
    const tipo = req.headers.get("Content-Type") ?? "";
    const corpo = tipo.includes("json") ? await req.json() : null;
    chamadas.push({ url: req.url, arg: arg ? JSON.parse(arg) : null, corpo });
    const r = respostas[i++];
    if (!r) throw new Error("chamada a mais");
    return r();
  }) as typeof fetch;
  try {
    await f(new Dropbox("refresh-de-teste", { appKey: "k", appSecret: "s", chaveDoToken: "x" }, "acesso-de-teste"));
  } finally {
    globalThis.fetch = original;
  }
  return chamadas;
}

const json = (b: unknown, status = 200) => () => new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });
const META = { id: "id:abc", name: "x.jpg", path_display: "/A/x.jpg", rev: "015f01", size: 3 };
const BYTES = new Uint8Array([1, 2, 3]);

Deno.test("mover: files/move_v2 pelo id, com autorename e sem transferir dono; devolve o metadata", async () => {
  let meta: unknown;
  const chamadas = await comFetch([json({ metadata: { ...META, path_display: "/B/Ção.jpg" } })], async (dbx) => {
    meta = await dbx.mover("id:abc", "/B/Ção.jpg");
  });
  assertEquals(chamadas[0].url, "https://api.dropboxapi.com/2/files/move_v2");
  assertEquals(chamadas[0].corpo, { from_path: "id:abc", to_path: "/B/Ção.jpg", autorename: true, allow_ownership_transfer: false });
  assertEquals((meta as { path_display: string }).path_display, "/B/Ção.jpg");
});

Deno.test("mover: erro do Dropbox (from_lookup/not_found) sobe como ErroDropbox com o resumo", async () => {
  await comFetch([json({ error_summary: "from_lookup/not_found/.." }, 409)], async (dbx) => {
    const e = await assertRejects(() => dbx.mover("id:sumiu", "/B/x.jpg"), ErroDropbox);
    assertEquals(e.resumo, "from_lookup/not_found/..");
    assertEquals(e.status, 409);
  });
});

Deno.test("substituir sem rev: add com autorename (primeira vez), conflito=false", async () => {
  let r: unknown;
  const chamadas = await comFetch([json(META)], async (dbx) => {
    r = await dbx.substituir("/C/_INDICE 2026-10.csv", BYTES, null);
  });
  assertEquals(chamadas[0].url, "https://content.dropboxapi.com/2/files/upload");
  assertEquals(chamadas[0].arg, { path: "/C/_INDICE 2026-10.csv", mode: "add", autorename: true, mute: false });
  assertEquals((r as { conflito: boolean }).conflito, false);
});

Deno.test("substituir com rev: update pelo rev, sem autorename", async () => {
  let r: unknown;
  const chamadas = await comFetch([json({ ...META, rev: "016" })], async (dbx) => {
    r = await dbx.substituir("/C/_INDICE 2026-10.csv", BYTES, "015f01");
  });
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].arg, { path: "/C/_INDICE 2026-10.csv", mode: { ".tag": "update", update: "015f01" }, autorename: false, mute: true });
  assertEquals(r, { ...META, rev: "016", conflito: false });
});

Deno.test("substituir: conflito de rev (o dono mexeu) → add com autorename num nome novo, conflito=true", async () => {
  for (const resumo of ["path/conflict/file/..", "path/not_found/.."]) {
    let r: unknown;
    const chamadas = await comFetch([
      json({ error_summary: resumo }, 409),
      json({ ...META, path_display: "/C/_INDICE 2026-10 (1).csv" }),
    ], async (dbx) => {
      r = await dbx.substituir("/C/_INDICE 2026-10.csv", BYTES, "015f01");
    });
    assertEquals(chamadas.length, 2, resumo);
    assertEquals(chamadas[1].arg, { path: "/C/_INDICE 2026-10.csv", mode: "add", autorename: true, mute: false });
    assertEquals((r as { conflito: boolean; path_display: string }).conflito, true);
    assertEquals((r as { path_display: string }).path_display, "/C/_INDICE 2026-10 (1).csv");
  }
});

Deno.test("substituir: outro erro (cota cheia) não cai no add — sobe para o backoff", async () => {
  const chamadas = await comFetch([json({ error_summary: "path/insufficient_space/.." }, 409)], async (dbx) => {
    await assertRejects(() => dbx.substituir("/C/x.csv", BYTES, "015f01"), ErroDropbox);
  });
  assertEquals(chamadas.length, 1);
});

Deno.test("criarPasta: cria; se já existe, devolve a existente pelo get_metadata", async () => {
  let a: unknown, b: unknown;
  const chamadas = await comFetch([
    json({ metadata: { id: "id:p1", path_display: "/Barco/1- DOC's/Compras" } }),
    json({ error_summary: "path/conflict/folder/.." }, 409),
    json({ id: "id:p2", path_display: "/Barco/1- DOC's/Compras" }),
  ], async (dbx) => {
    a = await dbx.criarPasta("/Barco/1- DOC's/Compras");
    b = await dbx.criarPasta("/Barco/1- DOC's/Compras");
  });
  assertEquals(a, { id: "id:p1", path_display: "/Barco/1- DOC's/Compras" });
  assertEquals(b, { id: "id:p2", path_display: "/Barco/1- DOC's/Compras" });
  assertEquals(chamadas.map((c) => c.url.split("/2/")[1]), ["files/create_folder_v2", "files/create_folder_v2", "files/get_metadata"]);
  assertEquals(chamadas[0].corpo, { path: "/Barco/1- DOC's/Compras", autorename: false });
});
