import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { aspas, ClienteImap, dataImap, internalDateParaIso, type Fluxo } from "./imap.ts";

/** Servidor de mentira: responde a cada comando com o roteiro dado; guarda o que recebeu. */
function servidor(roteiro: (tag: string, cmd: string) => string): Fluxo & { recebidos: string[] } {
  const enc = new TextEncoder();
  let saida = new Uint8Array(0);
  const recebidos: string[] = [];
  const empurra = (s: string) => {
    const b = enc.encode(s);
    const n = new Uint8Array(saida.length + b.length);
    n.set(saida);
    n.set(b, saida.length);
    saida = n;
  };
  return {
    recebidos,
    async read(p) {
      if (saida.length === 0) return null;
      const n = Math.min(p.length, saida.length, 7); // em pedaços pequenos: o leitor tem de juntar
      p.set(saida.subarray(0, n));
      saida = saida.slice(n);
      return n;
    },
    async write(p) {
      const linha = new TextDecoder().decode(p).replace(/\r\n$/, "");
      recebidos.push(linha);
      const [tag, ...resto] = linha.split(" ");
      empurra(roteiro(tag, resto.join(" ")));
      return p.length;
    },
    close() {},
  };
}

Deno.test("aspas e data do SEARCH", () => {
  assertEquals(aspas('se"nh\\a'), '"se\\"nh\\\\a"');
  assertEquals(dataImap(new Date("2026-07-09T12:00:00Z")), "9-Jul-2026");
  assertEquals(internalDateParaIso("07-Oct-2026 14:30:00 -0300"), "2026-10-07T17:30:00.000Z");
  assertEquals(internalDateParaIso("lixo"), null);
});

Deno.test("examinar (modo leitura), buscar e baixar com literal em pedaços, sem marcar como lido", async () => {
  const fonte = "Subject: Oi\r\nFrom: a@b.com\r\n\r\nCorpo {com chaves}\r\n";
  const s = servidor((tag, cmd) => {
    if (cmd.startsWith("LOGIN")) return `${tag} OK LOGIN completed\r\n`;
    if (cmd.startsWith("EXAMINE")) return `* 3 EXISTS\r\n* OK [UIDVALIDITY 1700000000] UIDs valid\r\n${tag} OK [READ-ONLY] EXAMINE completed\r\n`;
    if (cmd.startsWith("UID SEARCH")) return `* SEARCH 12 15 13\r\n${tag} OK SEARCH completed\r\n`;
    if (cmd.startsWith("UID FETCH 15 (BODY.PEEK[])")) return `* 3 FETCH (UID 15 BODY[] {${fonte.length}}\r\n${fonte})\r\n${tag} OK FETCH completed\r\n`;
    if (cmd.startsWith("UID FETCH 15 (RFC822.SIZE")) return `* 3 FETCH (UID 15 RFC822.SIZE 4321 INTERNALDATE "07-Oct-2026 14:30:00 -0300")\r\n${tag} OK\r\n`;
    if (cmd === "LOGOUT") return `* BYE\r\n${tag} OK\r\n`;
    return `${tag} BAD comando inesperado\r\n`;
  });
  const c = new ClienteImap(s);
  await c.login("financeiro@hbrmarine.com.br", "senha");
  assertEquals(await c.examinar(), { uidValidity: 1700000000, existem: 3 });
  assertEquals(await c.buscarUids("UID 12:*"), [12, 13, 15]);
  assertEquals(await c.tamanho(15), { tamanho: 4321, internalDate: "07-Oct-2026 14:30:00 -0300" });
  const bruto = await c.baixar(15);
  assertEquals(new TextDecoder().decode(bruto!), fonte);
  await c.sair();
  // Nada de SELECT, STORE, EXPUNGE, COPY, MOVE ou BODY[] sem PEEK: a caixa do dono não muda.
  for (const cmd of s.recebidos) assert(!/\b(SELECT|STORE|EXPUNGE|COPY|MOVE|DELETE)\b|BODY\[\]/i.test(cmd.replace(/BODY\.PEEK\[\]/i, "")), cmd);
});

Deno.test("senha recusada vira erro sem repetir a senha", async () => {
  const s = servidor((tag) => `${tag} NO [AUTHENTICATIONFAILED] Invalid credentials for segredo123\r\n`);
  const c = new ClienteImap(s);
  const e = await assertRejects(() => c.login("x@y.com", "segredo123"), Error);
  assert(!String((e as Error).message).includes("segredo123"));
});
