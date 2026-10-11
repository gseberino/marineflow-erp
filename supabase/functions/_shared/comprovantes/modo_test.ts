import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { CHAVE_DO_MODO, lerModoDoComprovante, modoDoValor } from "./modo.ts";

Deno.test("modoDoValor: os três valores, com espaço, maiúscula e aspas", () => {
  assertEquals(modoDoValor("off"), "off");
  assertEquals(modoDoValor("sombra"), "sombra");
  assertEquals(modoDoValor("dono"), "dono");
  assertEquals(modoDoValor("  Dono "), "dono");
  assertEquals(modoDoValor("SOMBRA"), "sombra");
  assertEquals(modoDoValor('"dono"'), "dono");
});

Deno.test("modoDoValor: lixo, vazio e não-texto viram off", () => {
  for (const v of ["", " ", "ligado", "true", "1", "donos", "sombra dono", null, undefined, 1, true, {}, []]) {
    assertEquals(modoDoValor(v), "off", `valor ${JSON.stringify(v)}`);
  }
});

function adminCom(resposta: { data?: unknown; error?: unknown } | Error) {
  const consultas: Array<{ tabela: string; filtros: Array<[string, unknown]> }> = [];
  const admin = {
    from(tabela: string) {
      const c = { tabela, filtros: [] as Array<[string, unknown]> };
      consultas.push(c);
      const q = {
        select: () => q,
        eq: (col: string, v: unknown) => { c.filtros.push([col, v]); return q; },
        maybeSingle: () => resposta instanceof Error ? Promise.reject(resposta) : Promise.resolve({ data: null, error: null, ...resposta }),
      };
      return q;
    },
  };
  return { admin, consultas };
}

Deno.test("lerModoDoComprovante: lê só a chave comprovante_fluxo", async () => {
  const { admin, consultas } = adminCom({ data: { value: "sombra" } });
  assertEquals(await lerModoDoComprovante(admin), "sombra");
  assertEquals(consultas.length, 1);
  assertEquals(consultas[0].tabela, "app_settings");
  assertEquals(consultas[0].filtros, [["key", CHAVE_DO_MODO]]);
});

Deno.test("lerModoDoComprovante: chave ausente, erro do banco ou exceção = off", async () => {
  assertEquals(await lerModoDoComprovante(adminCom({ data: null }).admin), "off");
  assertEquals(await lerModoDoComprovante(adminCom({ data: null, error: { message: "x" } }).admin), "off");
  assertEquals(await lerModoDoComprovante(adminCom(new Error("rede")).admin), "off");
  assertEquals(await lerModoDoComprovante(adminCom({ data: { value: "lixo" } }).admin), "off");
});
