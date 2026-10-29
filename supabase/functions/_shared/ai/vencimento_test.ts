// A linha que o vencimento deixa na conversa (aprovação em lote, Fase 1, 29/10/2026). Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/vencimento_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { conversaOndeOModeloLe, textoDoVencimento, vencidasPorConversa } from "./vencimento.ts";

Deno.test("uma vencida: o título, a hora do pedido em Brasília e 'nada foi feito'", () => {
  assertEquals(textoDoVencimento([{ title: "Cadastrar serviço", created_at: "2026-10-28T21:54:34Z" }]),
    "⏰ Venceu sem resposta: *Cadastrar serviço* (pedido de 28/10, 18:54). Nada foi feito.");
});

Deno.test("várias da mesma conversa (as 10 diárias de 29/09): uma linha só, com a lista; acima de 10, 'e mais'", () => {
  const diarias = Array.from({ length: 12 }, () => ({ title: "Registrar diária", created_at: "2026-09-29T15:55:00Z" }));
  const t = textoDoVencimento(diarias);
  assertStringIncludes(t, "⏰ Venceram sem resposta 12 pedidos (nada foi feito):");
  assertEquals(t.split("\n").length, 1 + 10 + 1);
  assertStringIncludes(t, "- e mais 2");
  assertEquals(textoDoVencimento([]), "");
  assertEquals(textoDoVencimento([{ title: null, created_at: null }]), "⏰ Venceu sem resposta: *ação pendente*. Nada foi feito.");
});

Deno.test("agrupa por conversa e deixa de fora a pendência sem sessão", () => {
  const g = vencidasPorConversa([
    { id: "a", session_id: "s1" }, { id: "b", session_id: "s2" }, { id: "c", session_id: "s1" }, { id: "d", session_id: null },
  ]);
  assertEquals([...g.entries()].map(([s, l]) => [s, l.map((x) => x.id)]), [["s1", ["a", "c"]], ["s2", ["b"]]]);
});

Deno.test("revisão de 29/10: no WhatsApp a linha vai para a conversa aberta mais recente do mesmo telefone (a que o modelo lê)", async () => {
  const sessoes = [
    { id: "s-velha", channel: "whatsapp", external_thread_key: "5547999990000", status: "closed", last_activity_at: "2026-10-28T00:00:00Z" },
    { id: "s-atual", channel: "whatsapp", external_thread_key: "5547999990000", status: "open", last_activity_at: "2026-10-29T10:00:00Z" },
    { id: "s-painel", channel: "web", external_thread_key: null, status: "open", last_activity_at: "2026-10-29T10:00:00Z" },
  ];
  const admin = {
    from: () => {
      let linhas = [...sessoes];
      const q: Record<string, unknown> = {};
      q.select = () => q;
      q.eq = (c: string, v: unknown) => { linhas = linhas.filter((l) => (l as Record<string, unknown>)[c] === v); return q; };
      q.order = () => { linhas.sort((a, b) => b.last_activity_at.localeCompare(a.last_activity_at)); return q; };
      q.limit = () => q;
      q.maybeSingle = async () => ({ data: linhas[0] ?? null, error: null });
      return q;
    },
  };
  assertEquals(await conversaOndeOModeloLe(admin, "s-velha"), "s-atual");
  assertEquals(await conversaOndeOModeloLe(admin, "s-painel"), "s-painel", "no painel, a conversa da pendência");
  assertEquals(await conversaOndeOModeloLe(admin, "sumiu"), "sumiu", "na dúvida, a conversa da pendência");
  const quebrado = { from: () => { throw new Error("rede"); } };
  assertEquals(await conversaOndeOModeloLe(quebrado, "s-velha"), "s-velha");
});
