// Ferramentas de acompanhar conversa (06/10/2026). O que se protege: o contato é achado pelo nome
// (cliente ou conversa), número ou cliente; nome ambíguo vira pergunta; pedir de novo atualiza o
// mesmo acompanhamento; "me lembra às 14h" vira lembrete único em Brasília e fora do horário é
// recusado; parar encerra só o que está ativo daquele contato.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { acompanhamentoTools, resolverContato } from "./acompanhamento.ts";

const tool = (n: string) => acompanhamentoTools.find((t) => t.name === n)!;

function banco(opcoes: { clientes?: any[]; leads?: any[]; existente?: any; encerrados?: any[] } = {}) {
  const gravado = { inserts: [] as any[], updates: [] as any[], filtros: [] as any[] };
  const admin = {
    from(t: string) {
      const filtros: any[] = [];
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); gravado.filtros.push([t, c, v]); return q; },
        ilike: (_c: string, v: string) => {
          const termo = v.replace(/%/g, "").toLowerCase();
          const lista = t === "clients" ? (opcoes.clientes ?? []) : (opcoes.leads ?? []);
          return { limit: () => Promise.resolve({ data: lista.filter((r: any) => String(r.name).toLowerCase().includes(termo)), error: null }) };
        },
        maybeSingle: () => {
          if (t === "clients") return Promise.resolve({ data: (opcoes.clientes ?? [])[0] ?? null, error: null });
          if (t === "whatsapp_leads") return Promise.resolve({ data: (opcoes.leads ?? [])[0] ?? null, error: null });
          if (t === "whatsapp_acompanhamentos") return Promise.resolve({ data: opcoes.existente ?? null, error: null });
          return Promise.resolve({ data: null, error: null });
        },
        insert: (v: any) => { gravado.inserts.push(v); return Promise.resolve({ error: null }); },
        update: (v: any) => {
          gravado.updates.push(v);
          const u: any = { eq: (c: string, v: unknown) => { gravado.filtros.push([t, c, v]); return u; }, select: () => Promise.resolve({ data: opcoes.encerrados ?? [], error: null }), then: (ok: any) => Promise.resolve({ error: null }).then(ok) };
          return u;
        },
      };
      return q;
    },
  };
  const ctx = { sb: admin, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as never;
  return { admin, ctx, gravado };
}

Deno.test("contato pelo nome: cliente com WhatsApp, conversa só no WhatsApp, e ambíguo vira pergunta", async () => {
  const cli = await resolverContato(banco({ clientes: [{ name: "Miguel", whatsapp: "+351 966 776 422" }] }), { contato: "miguel" }) as any;
  assertEquals(cli, { phone: "351966776422", nome: "Miguel" });
  const lead = await resolverContato(banco({ leads: [{ name: "Juliano Jds", phone_normalized: "5547991234567" }] }), { contato: "Juliano" }) as any;
  assertEquals(lead, { phone: "5547991234567", nome: "Juliano Jds" });
  const dois = await resolverContato(banco({ leads: [{ name: "Carlos A", phone_normalized: "5547990000001" }, { name: "Carlos B", phone_normalized: "5547990000002" }] }), { contato: "Carlos" }) as any;
  assertStringIncludes(dois.error, "Há 2 conversas");
  assertEquals(dois.opcoes.length, 2);
  assertStringIncludes((await resolverContato(banco(), { contato: "Ninguém" }) as any).error, "Não achei");
});

Deno.test("acompanhar: grava intervalo e prazo; pedir de novo atualiza o mesmo", async () => {
  const novo = banco({ leads: [{ name: "Miguel", phone_normalized: "351966776422" }] });
  const r = await tool("acompanhar_conversa").execute({ phone: "+351 966 776 422", intervalo_horas: 3 }, novo.ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(novo.gravado.inserts[0].modo, "acompanhar");
  assertEquals(novo.gravado.inserts[0].intervalo_min, 180);
  assertEquals(novo.gravado.inserts[0].phone_normalized, "351966776422");
  assertEquals(r.intervalo, "3h");
  const denovo = banco({ leads: [{ name: "Miguel", phone_normalized: "351966776422" }], existente: { id: "a1" } });
  const r2 = await tool("acompanhar_conversa").execute({ phone: "351966776422" }, denovo.ctx) as any;
  assertEquals(r2.atualizado, true);
  assertEquals(denovo.gravado.inserts.length, 0);
  assertEquals(denovo.gravado.updates[0].intervalo_min, 120);
  assertStringIncludes((await tool("acompanhar_conversa").execute({ phone: "351966776422", intervalo_horas: 0.1 }, banco().ctx) as any).error, "Intervalo");
});

Deno.test("lembrete único às 14h em Brasília; fora do horário é recusado", async () => {
  const b = banco({ leads: [{ name: "Nelson", phone_normalized: "5547991455678" }] });
  const r = await tool("acompanhar_conversa").execute({ phone: "47991455678", lembrar_em: "2030-10-08T14:00" }, b.ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.gravado.inserts[0].modo, "lembrar_em");
  assertEquals(b.gravado.inserts[0].lembrar_em, "2030-10-08T17:00:00.000Z");
  assertStringIncludes(r.lembrete, "às 14:00");
  const tarde = await tool("acompanhar_conversa").execute({ phone: "47991455678", lembrar_em: "2030-10-08T22:00" }, banco().ctx) as any;
  assertStringIncludes(tarde.error, "fora do horário comercial");
});

Deno.test("parar: encerra o que está ativo daquele contato", async () => {
  const b = banco({ leads: [{ name: "Miguel", phone_normalized: "351966776422" }], encerrados: [{ id: "a1" }, { id: "a2" }] });
  const r = await tool("parar_acompanhamento").execute({ contato: "Miguel" }, b.ctx) as any;
  assertEquals(r, { ok: true, encerrados: 2 });
  assertEquals(b.gravado.updates[0].status, "encerrado");
  assert(b.gravado.filtros.some(([t, c, v]: any[]) => t === "whatsapp_acompanhamentos" && c === "phone_normalized" && v === "351966776422"));
  const nada = await tool("parar_acompanhamento").execute({ contato: "Miguel" }, banco({ leads: [{ name: "Miguel", phone_normalized: "351966776422" }] }).ctx) as any;
  assertEquals(nada.encerrados, 0);
});
