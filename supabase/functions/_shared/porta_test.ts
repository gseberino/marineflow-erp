// Run: deno test -A supabase/functions/_shared/porta_test.ts
//
// O que se protege: a chave anônima (pública no site) não passa; só a chave de serviço é chamada
// interna; usuário inativo ou de outro cargo é recusado; leitura do cadastro que falha recusa.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chamadaInterna, usuarioAtivo } from "./porta.ts";

const req = (auth?: string) => new Request("https://x/functions/v1/f", { method: "POST", headers: auth ? { Authorization: auth } : {} });

function ambiente() {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  Deno.env.set("SUPABASE_ANON_KEY", "anon-publica");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
}

/** Auth devolve o usuário do token "Bearer user-<id>"; app_users devolve o cadastro dado. */
function redeFalsa(cadastros: Record<string, { role: string; active: boolean } | "erro">) {
  return ((entrada: string | URL | Request, init?: RequestInit) => {
    const url = typeof entrada === "string" ? entrada : entrada instanceof URL ? entrada.href : entrada.url;
    const headers = new Headers(init?.headers ?? (entrada instanceof Request ? entrada.headers : undefined));
    const json = (corpo: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } }));
    if (url.includes("/auth/v1/user")) {
      const m = /Bearer user-(\w+)/.exec(headers.get("Authorization") ?? "");
      return m ? json({ id: m[1], aud: "authenticated" }) : json({ message: "invalid" }, 401);
    }
    if (url.includes("/rest/v1/app_users")) {
      const id = /id=eq\.(\w+)/.exec(decodeURIComponent(url))?.[1] ?? "";
      const c = cadastros[id];
      if (c === "erro") return json({ message: "falha" }, 500);
      return json(c ? [c] : []);
    }
    return json({}, 404);
  }) as typeof fetch;
}

Deno.test("chamadaInterna: só a chave de serviço; a anônima e a ausência, não", () => {
  ambiente();
  assertEquals(chamadaInterna(req("Bearer chave-de-servico")), true);
  assertEquals(chamadaInterna(req("Bearer anon-publica")), false);
  assertEquals(chamadaInterna(req()), false);
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  assertEquals(chamadaInterna(req("Bearer ")), false); // sem chave configurada, nunca
});

Deno.test("usuarioAtivo: anônimo 401, inativo 403, cargo errado 403, falha na leitura 403", async () => {
  ambiente();
  const original = globalThis.fetch;
  globalThis.fetch = redeFalsa({
    adm: { role: "admin", active: true },
    fin: { role: "financial", active: true },
    tec: { role: "technician", active: true },
    velho: { role: "admin", active: false },
    quebra: "erro",
  });
  try {
    assertEquals((await usuarioAtivo(req())).ok, false);
    const anon = await usuarioAtivo(req("Bearer anon-publica"));
    assertEquals(anon.ok ? 0 : anon.status, 401);
    assertEquals(await usuarioAtivo(req("Bearer user-adm")), { ok: true, userId: "adm", role: "admin" });
    const inativo = await usuarioAtivo(req("Bearer user-velho"));
    assertEquals(inativo.ok ? 0 : inativo.status, 403);
    const tecnico = await usuarioAtivo(req("Bearer user-tec"), ["admin", "financial"]);
    assertEquals(tecnico.ok ? 0 : tecnico.status, 403);
    assertEquals((await usuarioAtivo(req("Bearer user-fin"), ["admin", "financial"])).ok, true);
    const quebra = await usuarioAtivo(req("Bearer user-quebra"));
    assertEquals(quebra.ok ? 0 : quebra.status, 403);
  } finally {
    globalThis.fetch = original;
  }
});
