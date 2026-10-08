// Ferramentas do Dropbox (Fase 5, 08/10/2026). O que se protege: só admin; o barco sai do nome do
// barco ou do dono; a busca filtra por texto (sem acento) e extensão e devolve o id; a pasta traz o
// número, o link e a contagem por subpasta; o envio de não-PDF e o do painel voltam como link, sem
// tocar no Dropbox nem no WhatsApp.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dropboxTools } from "./dropbox.ts";

// deno-lint-ignore no-explicit-any
function bancoFalso(tabelas: Record<string, any[]>) {
  return {
    from(tabela: string) {
      const filtros: ((l: Record<string, unknown>) => boolean)[] = [];
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l))).map((l) => ({ ...l }));
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        order: () => q,
        limit: () => q,
        eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
        in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any, falha: any) => Promise.resolve({ data: linhas(), error: null }).then(ok, falha),
      };
      return q;
    },
  };
}

const BASE = "/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona V";
const banco = () =>
  bancoFalso({
    vessels: [
      { id: "v1", name: "Donna V", active: true, clients: { name: "Acrisio Lopes Cançado Filho" } },
      { id: "v2", name: "Madu I", active: true, clients: { name: "Edson Luiz Rudek Junior" } },
    ],
    pastas_dropbox: [{ id: "p1", vessel_id: "v1", caminho: BASE, codigo_projeto: "0016.013.25", situacao: "vinculada" }],
    arquivos_dropbox: [
      { id: "00000000-0000-0000-0000-0000000000a1", pasta_id: "p1", apagado: false, nome: "Esboço Paineis Donna V _REV01.dwg", extensao: "dwg", tamanho: 2774373, modificado_em: "2026-01-23T12:11:04Z", caminho: `${BASE}/2- ELÉTRICA/2- DWG/2- PAINEIS/1- Desenhos/Esboço Paineis Donna V _REV01.dwg`, dropbox_id: "id:a1" },
      { id: "00000000-0000-0000-0000-0000000000a2", pasta_id: "p1", apagado: false, nome: "EmpirBus - Dona V.pdf", extensao: "pdf", tamanho: 104301, modificado_em: "2025-10-07T16:31:57Z", caminho: `${BASE}/2- ELÉTRICA/1- DOC'S/2- EMPIRBUS MARINEXPRESS/EmpirBus - Dona V.pdf`, dropbox_id: "id:a2" },
      { id: "00000000-0000-0000-0000-0000000000a3", pasta_id: "p1", apagado: true, nome: "velho.pdf", extensao: "pdf", tamanho: 1, modificado_em: null, caminho: `${BASE}/velho.pdf`, dropbox_id: "id:a3" },
    ],
  });
const ctx = (db: unknown, userRole = "admin", canal?: string) =>
  ({ sb: db, admin: db, userId: "dono-1", userRole, jwt: "", appOrigin: "", settings: {}, ...(canal ? { canal } : {}) }) as never;
const tool = (n: string) => dropboxTools.find((t) => t.name === n)!;

Deno.test("só o administrador usa", async () => {
  const r = await tool("buscar_arquivos_do_barco").execute({ barco: "Donna V" }, ctx(banco(), "financial")) as { error: string };
  assertStringIncludes(r.error, "só do administrador");
});

Deno.test("buscar: pelo nome com grafia diferente, filtra por texto sem acento, ignora apagado", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await tool("buscar_arquivos_do_barco").execute({ barco: "dona v", busca: "paineis" }, ctx(banco())) as any;
  assertEquals(r.barco, "Donna V");
  assertEquals(r.arquivos.length, 1);
  assertEquals(r.arquivos[0].nome, "Esboço Paineis Donna V _REV01.dwg");
  assertEquals(r.arquivos[0].subpasta, "2- ELÉTRICA/2- DWG/2- PAINEIS/1- Desenhos");
  assertEquals(r.arquivos[0].id, "00000000-0000-0000-0000-0000000000a1");
  // deno-lint-ignore no-explicit-any
  const todos = await tool("buscar_arquivos_do_barco").execute({ barco: "Acrisio Lopes Cançado Filho" }, ctx(banco())) as any;
  assertEquals(todos.total, 2, "o apagado não entra");
});

Deno.test("buscar: barco sem pasta avisa, sem inventar", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await tool("buscar_arquivos_do_barco").execute({ barco: "Madu I" }, ctx(banco())) as any;
  assertEquals(r.arquivos, []);
  assertStringIncludes(r.aviso, "ainda não tem pasta");
});

Deno.test("pasta: número, link e contagem por subpasta", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await tool("consultar_pasta_do_barco").execute({ barco: "Donna V" }, ctx(banco())) as any;
  assertEquals(r.numero_do_projeto, "0016.013.25");
  assertEquals(r.link, "https://www.dropbox.com/home/MANAGEMENT/COMMERCIAL/B2C/0016.013.25_Dona%20V");
  assertEquals(r.por_subpasta, { "2- ELÉTRICA": 2 });
});

Deno.test("enviar: DWG volta como link (só PDF vai pelo WhatsApp)", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await tool("enviar_arquivo_do_dropbox").execute({ arquivo_id: "00000000-0000-0000-0000-0000000000a1" }, ctx(banco())) as any;
  assertStringIncludes(r.observacao, "Só mando PDF");
  assertStringIncludes(r.link, "?preview=");
});

Deno.test("enviar: no painel devolve o link em vez de mandar", async () => {
  // deno-lint-ignore no-explicit-any
  const r = await tool("enviar_arquivo_do_dropbox").execute({ arquivo_id: "00000000-0000-0000-0000-0000000000a2" }, ctx(banco(), "admin", "panel")) as any;
  assertEquals(r.arquivo, "EmpirBus - Dona V.pdf");
  assertStringIncludes(r.link, "EmpirBus%20-%20Dona%20V.pdf");
});

Deno.test("enviar: arquivo apagado e id inválido são recusados", async () => {
  // deno-lint-ignore no-explicit-any
  const apagado = await tool("enviar_arquivo_do_dropbox").execute({ arquivo_id: "00000000-0000-0000-0000-0000000000a3" }, ctx(banco())) as any;
  assertStringIncludes(apagado.error, "não está mais");
  // deno-lint-ignore no-explicit-any
  const ruim = await tool("enviar_arquivo_do_dropbox").execute({ arquivo_id: "EmpirBus" }, ctx(banco())) as any;
  assertStringIncludes(ruim.error, "id do arquivo");
});
