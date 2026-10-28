// converter_sem_sinal (27/10/2026): orçamento vira OS sem sinal, valor inteiro na conclusão.
// O que se protege: a ordem das gravações (condição + aprovado, depois a conversão), o número
// (ORÇ-00042 → OS-00042, como a tela — não um número novo), o retrato do "sim", e as recusas
// (já é OS, reprovado, técnico). Depois do merge com a agenda (28/10/2026), a conversão é da porta única de status
// (os_transicionar_status, via 'assistente'); sem a porta no banco, o PLANO B (porta-ausente.ts) com o mesmo número.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { converterSemSinalTools, numeroDaOS } from "./converter-sem-sinal.ts";
import { CHAVE_DO_RETRATO } from "./registry.ts";

const tool = converterSemSinalTools[0];

const PRESETS = [
  { id: "p-50", label: "50% de sinal + 50% na entrega", installments: [
    { tipo: "aprovacao", services_pct: 50, parts_pct: 50, expenses_pct: 50 },
    { tipo: "entrega", services_pct: 50, parts_pct: 50, expenses_pct: 50 },
  ] },
  { id: "p-entrega", label: "100% na entrega", installments: [
    { tipo: "entrega", services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0 },
  ] },
];

const ORC = {
  id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", service_order_number: "ORÇ-00042", status: "draft",
  quote_status: "awaiting_deposit", converted_to_os_at: null, grand_total: 4200, original_quote_amount: null,
  signed_at: null, payment_conditions: "50% de sinal + 50% na entrega",
};

type Porta = { ausente?: boolean; resposta?: Record<string, unknown> };
const PORTA_CONVERTEU = { ok: true, mudou: true, de: "draft", para: "approved", convertido: true, numero: "OS-00042",
  numero_antes: "ORÇ-00042", texto: "Orçamento ORÇ-00042 virou a OS-00042 (aprovada)." };

function banco(ordem: Record<string, unknown>, opts: { conversaoPerdida?: boolean; porta?: Porta } = {}) {
  const updates: Record<string, unknown>[] = [];
  const rpcs: { nome: string; params: Record<string, unknown> }[] = [];
  const sb = {
    rpc(nome: string, params: Record<string, unknown>) {
      rpcs.push({ nome, params });
      if (opts.porta?.ausente) return Promise.resolve({ data: null, error: { code: "PGRST202", message: "Could not find the function" } });
      return Promise.resolve({ data: opts.porta?.resposta ?? PORTA_CONVERTEU, error: null });
    },
    from(tabela: string) {
      const filtros: [string, unknown][] = [];
      let atualizando: Record<string, unknown> | null = null;
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
        is: () => q,
        update: (v: Record<string, unknown>) => { updates.push(v); atualizando = v; return q; },
        single: () => Promise.resolve({ data: { id: ordem.id, ...ordem, ...(atualizando ?? {}) }, error: null }),
        maybeSingle: () => {
          if (atualizando) {
            const perdeu = opts.conversaoPerdida && "converted_to_os_at" in atualizando;
            return Promise.resolve({ data: perdeu ? null : { id: ordem.id, ...atualizando }, error: null });
          }
          return Promise.resolve({ data: filtros.every(([c, v]) => ordem[c] === v) ? ordem : null, error: null });
        },
        then: (ok: (v: unknown) => unknown) =>
          Promise.resolve({ data: tabela === "payment_condition_presets" ? PRESETS : null, error: null }).then(ok),
      };
      return q;
    },
  };
  const ctx = (userRole = "admin") => ({ sb, admin: sb, userId: "u1", userRole, jwt: "", appOrigin: "", settings: {} }) as never;
  return { ctx, updates, rpcs };
}

Deno.test("converte: condição 100% na entrega + aprovado, depois a conversão pela porta com o mesmo número", async () => {
  const b = banco(ORC);
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.updates, [{
    payment_condition_preset_id: "p-entrega",
    payment_conditions: "100% na entrega",
    custom_payment_installments: null,
    quote_status: "approved",
  }], "o status não vai num UPDATE: é da porta");
  assertEquals(b.rpcs, [{ nome: "os_transicionar_status",
    params: { p_os: ORC.id, p_para: "approved", p_via: "assistente", p_check_out: null, p_autor: "u1" } }]);
  assertEquals(r.documento, "OS-00042");
  assertEquals(r.condicao_anterior, "50% de sinal + 50% na entrega");
  assertEquals(r.avisos, undefined);
});

Deno.test("PLANO B: sem a porta no banco (PGRST202), a conversão do caminho de antes mantém o número e o valor orçado", async () => {
  const b = banco(ORC, { porta: { ausente: true } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.updates.length, 2);
  assertEquals(b.updates[0].quote_status, "approved");
  assertEquals(b.updates[1].status, "approved");
  assertEquals(b.updates[1].service_order_number, "OS-00042");
  assertEquals(b.updates[1].original_quote_amount, 4200);
  assert(typeof b.updates[1].converted_to_os_at === "string");
  assertEquals(r.documento, "OS-00042");
});

Deno.test("a porta recusa (número de outra OS) ou não deixa: só a condição mudou, e o texto diz por quê", async () => {
  const recusa = banco(ORC, { porta: { resposta: { ok: false, mudou: false, texto: "Não converti: o número OS-00042 já é de outra OS." } } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, recusa.ctx()) as any;
  assertStringIncludes(r.error, "conversão não aconteceu (Não converti: o número OS-00042 já é de outra OS.)");
  assertEquals(recusa.updates.length, 1, "só a condição");
});

Deno.test("orçamento assinado: converte e avisa que o cliente assina de novo", async () => {
  const b = banco({ ...ORC, signed_at: "2026-10-20T10:00:00Z" });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx()) as any;
  assertEquals(r.ok, true);
  assertStringIncludes(r.avisos[0], "assinar de novo");
});

Deno.test("recusas: já é OS, reprovado, técnico — nada gravado", async () => {
  for (const [ordem, papel, trecho] of [
    [{ ...ORC, status: "approved", converted_to_os_at: "2026-10-01T00:00:00Z" }, "admin", "já é OS"],
    [{ ...ORC, quote_status: "rejected" }, "admin", "Reprovado"],
    [ORC, "technician", "Cargo não autorizado"],
  ] as const) {
    const b = banco(ordem);
    // deno-lint-ignore no-explicit-any
    const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx(papel)) as any;
    assertStringIncludes(r.error, trecho);
    assertEquals(b.updates.length, 0, trecho);
  }
});

Deno.test("retrato: total mudou depois do pedido → recusa sem gravar", async () => {
  const b = banco({ ...ORC, grand_total: 5000 });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042", [CHAVE_DO_RETRATO]: { id: ORC.id, total: 4200 } }, b.ctx()) as any;
  assertStringIncludes(r.error, "mudou desde o pedido");
  assertEquals(b.updates.length, 0);
});

Deno.test("conversão perdida para outra sessão: diz que só a condição mudou", async () => {
  // A porta responde ok sem converter: a OS já tinha saído de orçamento quando o "sim" chegou.
  const b = banco(ORC, { porta: { resposta: { ok: true, mudou: false, de: "approved", para: "approved", texto: "Nada mudou." } } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx()) as any;
  assertStringIncludes(r.error, "conversão não aconteceu");
});

Deno.test("retrato da pendência leva id, número e total", async () => {
  const b = banco(ORC);
  const ret = await tool.retratoDaPendencia!({ service_order_id: ORC.id }, b.ctx());
  assertEquals(ret, { id: ORC.id, numero: "ORÇ-00042", total: 4200 });
});

Deno.test("numeroDaOS troca só o prefixo", () => {
  assertEquals(numeroDaOS("ORÇ-00042"), "OS-00042");
  assertEquals(numeroDaOS("OS-00007"), "OS-00007");
});
