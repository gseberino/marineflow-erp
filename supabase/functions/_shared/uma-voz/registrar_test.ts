// A ponte das fontes com o portão (secretário, Passo 4, 15/10/2026), com um banco de mentira. O que se
// protege: COM A CHAVE DESLIGADA NADA MUDA (nenhuma chamada ao portão); erro de leitura = desligado; o
// registro nunca derruba a fonte (erro e exceção viram null); o mesmo telefone não é registrado duas
// vezes; o freio só conta quando a leitura dá certo; quem registra o acompanhamento em cada combinação.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisosDestaMensagem, lerPortao, modoDoRegistroDoAcompanhamento, portaoDasConfiguracoes, registrarNoPortao, registrarParaTodos,
} from "./registrar.ts";
import type { AvisoDaFonte } from "./portao.ts";

const AVISO: AvisoDaFonte = { fonte: "email", chave: "golpe:x@y", assunto: "golpe:x@y", destino: "acorde", texto: "t" };

// deno-lint-ignore no-explicit-any
function bancoDeMentira(opcoes: { settings?: Array<{ key: string; value: string }>; erroSettings?: boolean; rpc?: (nome: string, args: any) => any; count?: number | null; erroCount?: boolean } = {}) {
  // deno-lint-ignore no-explicit-any
  const chamadas: Array<{ nome: string; args: any }> = [];
  const admin = {
    from(tabela: string) {
      const q = {
        select() { return q; },
        in() {
          return Promise.resolve(opcoes.erroSettings ? { data: null, error: { message: "falhou" } } : { data: opcoes.settings ?? [], error: null });
        },
        eq() { return q; },
        then(resolver: (v: unknown) => void) {
          resolver(opcoes.erroCount ? { count: null, error: { message: "falhou" } } : { count: opcoes.count ?? 0, error: null });
        },
        tabela,
      };
      return q;
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      chamadas.push({ nome, args });
      return Promise.resolve(opcoes.rpc ? opcoes.rpc(nome, args) : { data: { ok: true, decisao: "acordar" }, error: null });
    },
  };
  return { admin, chamadas };
}

Deno.test("desligado: registrarNoPortao e registrarParaTodos não chamam o portão", async () => {
  const { admin, chamadas } = bancoDeMentira();
  assertEquals(await registrarNoPortao(admin, null, "5547999990001", AVISO), null);
  assertEquals(await registrarParaTodos(admin, null, ["5547999990001"], [AVISO]), 0);
  assertEquals(chamadas.length, 0);
});

Deno.test("lerPortao: sem as chaves = desligado e freio desligado; erro de leitura = desligado", async () => {
  const vazio = await lerPortao(bancoDeMentira().admin);
  assertEquals([vazio.voz, vazio.modo, vazio.freio], ["desligado", null, false]);
  const erro = await lerPortao(bancoDeMentira({ erroSettings: true, settings: [{ key: "voz_unica", value: "sombra" }] }).admin);
  assertEquals([erro.voz, erro.modo], ["desligado", null]);
  const sombra = await lerPortao(bancoDeMentira({ settings: [{ key: "voz_unica", value: "sombra" }, { key: "acompanhar_freio", value: "ligado" }] }).admin);
  assertEquals([sombra.voz, sombra.modo, sombra.freio], ["sombra", "sombra", true]);
});

Deno.test("sombra: chama aviso_registrar com o pedido completo", async () => {
  const { admin, chamadas } = bancoDeMentira();
  const r = await registrarNoPortao(admin, "sombra", "5547999990001", AVISO, new Date("2026-10-21T13:00:00Z"));
  assertEquals(r?.decisao, "acordar");
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].nome, "aviso_registrar");
  assertEquals(chamadas[0].args.p.phone, "5547999990001");
  assertEquals(chamadas[0].args.p.modo, "sombra");
  assertEquals(chamadas[0].args.p.chave, "golpe:x@y");
  assertEquals(chamadas[0].args.p.agora, "2026-10-21T13:00:00.000Z");
});

Deno.test("o registro nunca derruba a fonte: erro do banco e exceção viram null", async () => {
  const comErro = bancoDeMentira({ rpc: () => ({ data: null, error: { message: "permission denied" } }) });
  assertEquals(await registrarNoPortao(comErro.admin, "sombra", "5547999990001", AVISO), null);
  const explode = bancoDeMentira({ rpc: () => { throw new Error("rede caiu"); } });
  assertEquals(await registrarNoPortao(explode.admin, "sombra", "5547999990001", AVISO), null);
  assertEquals(await registrarNoPortao(comErro.admin, "sombra", null, AVISO), null, "sem telefone não registra");
});

Deno.test("registrarParaTodos: um registro por telefone (sem repetir nem vazio) e por aviso", async () => {
  const { admin, chamadas } = bancoDeMentira();
  const n = await registrarParaTodos(admin, "sombra", ["5547999990001", "5547999990001", null, "", "5547999990002"], [AVISO, { ...AVISO, chave: "outra" }]);
  assertEquals(n, 4);
  assertEquals(chamadas.map((c) => `${c.args.p.phone}/${c.args.p.chave}`), [
    "5547999990001/golpe:x@y", "5547999990001/outra", "5547999990002/golpe:x@y", "5547999990002/outra",
  ]);
});

Deno.test("avisosDestaMensagem: a contagem; erro = null (o freio não age)", async () => {
  assertEquals(await avisosDestaMensagem(bancoDeMentira({ count: 2 }).admin, "acomp:a1:x"), 2);
  assertEquals(await avisosDestaMensagem(bancoDeMentira({ erroCount: true }).admin, "acomp:a1:x"), null);
});

Deno.test("acompanhamento: quem registra em cada combinação de voz única e freio", () => {
  const voz = (v: string, f: string) => portaoDasConfiguracoes({ voz_unica: v, acompanhar_freio: f });
  // tudo desligado: nada muda
  assertEquals(modoDoRegistroDoAcompanhamento(voz("desligado", "desligado"), "acompanhar"), null);
  assertEquals(modoDoRegistroDoAcompanhamento(voz("desligado", "desligado"), "promessa"), null);
  // só o freio: só o acompanhar registra (é a conta do freio)
  assertEquals(modoDoRegistroDoAcompanhamento(voz("desligado", "ligado"), "acompanhar"), "sombra");
  assertEquals(modoDoRegistroDoAcompanhamento(voz("desligado", "ligado"), "promessa"), null);
  assertEquals(modoDoRegistroDoAcompanhamento(voz("desligado", "ligado"), "lembrar_em"), null);
  // voz única em sombra: todos registram
  assertEquals(modoDoRegistroDoAcompanhamento(voz("sombra", "desligado"), "promessa"), "sombra");
  assertEquals(modoDoRegistroDoAcompanhamento(voz("ligado", "ligado"), "lembrar_em"), "sombra");
});
