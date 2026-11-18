// converter_sem_sinal (27/10/2026): orçamento vira OS sem sinal, valor inteiro na conclusão.
// O que se protege: a ordem das gravações (condição + aprovado, depois a conversão), o número
// (ORÇ-00042 → OS-00042, como a tela — não um número novo), o retrato do "sim", e as recusas
// (já é OS, reprovado, técnico). Depois do merge com a agenda (28/10/2026), a conversão é da porta única de status
// (os_transicionar_status, via 'assistente'); sem a porta no banco, o PLANO B (porta-ausente.ts) com o mesmo número.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  converterSemSinalNucleo, converterSemSinalTools, numeroDaOS, recusaDoJaFeito, resumirConversaoSemSinal,
} from "./converter-sem-sinal.ts";
import { CHAVE_DO_RETRATO } from "./registry.ts";
import { diaFeitoValido, motivoDoAviso, sinaisDeJaFeito } from "../../sinais-de-ja-feito.ts";

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

// ─── Retorno F5 (P11.1, C-CONV): o núcleo exportado, a via do dono e o total do cartão ─────────────────────────────

Deno.test("F5 núcleo, via dono: a porta recebe p_via 'dono', o autor e o motivo (até 200 caracteres)", async () => {
  const b = banco(ORC);
  const motivo = "Aceite por texto do cliente, mensagem wamid.ABC123";
  // deno-lint-ignore no-explicit-any
  const r = await converterSemSinalNucleo((b.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "dono", autor: "u-dono", motivo, totalVisto: 4200 }) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.documento, "OS-00042");
  assertEquals(b.rpcs, [{ nome: "os_transicionar_status",
    params: { p_os: ORC.id, p_para: "approved", p_via: "dono", p_check_out: null, p_autor: "u-dono", p_motivo: motivo } }]);
  assertEquals(b.updates[0].quote_status, "approved");
  // o motivo longo é cortado em 200
  const c = banco(ORC);
  await converterSemSinalNucleo((c.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "dono", autor: "u-dono", motivo: "x".repeat(300) });
  assertEquals(String(c.rpcs[0].params.p_motivo).length, 200);
});

Deno.test("F5 núcleo: total do cartão diferente do atual (mais de R$ 0,01) recusa antes de mexer na condição", async () => {
  for (const visto of [4199.98, 4200.02, 0, 5000]) {
    const b = banco(ORC);
    // deno-lint-ignore no-explicit-any
    const r = await converterSemSinalNucleo((b.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "dono", autor: "u-dono", totalVisto: visto }) as any;
    assertEquals(r.error, "O orçamento mudou desde o cartão.", String(visto));
    assertEquals(r.codigo, "mudou");
    assertEquals(b.updates.length, 0, "a condição não foi tocada");
    assertEquals(b.rpcs.length, 0);
  }
  // até R$ 0,01 de diferença, converte
  for (const visto of [4200, 4200.01, 4199.99]) {
    const b = banco(ORC);
    // deno-lint-ignore no-explicit-any
    const r = await converterSemSinalNucleo((b.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "dono", autor: "u-dono", totalVisto: visto }) as any;
    assertEquals(r.ok, true, String(visto));
  }
});

Deno.test("F5 núcleo: as recusas trazem o código (já é OS, reprovado, não achou, só a condição)", async () => {
  const casos: Array<[Record<string, unknown>, string, Porta | undefined]> = [
    [{ ...ORC, status: "approved", converted_to_os_at: "2026-10-01T00:00:00Z" }, "ja_os", undefined],
    [{ ...ORC, quote_status: "rejected" }, "reprovado", undefined],
    [ORC, "so_condicao", { resposta: { ok: false, mudou: false, texto: "Não converti." } }],
  ];
  for (const [ordem, codigo, porta] of casos) {
    const b = banco(ordem, porta ? { porta } : {});
    // deno-lint-ignore no-explicit-any
    const r = await converterSemSinalNucleo((b.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "dono", autor: "u-dono" }) as any;
    assertEquals(r.codigo, codigo, JSON.stringify(r));
    assert(typeof r.error === "string" && r.error.length > 0);
  }
  const nada = banco(ORC);
  // deno-lint-ignore no-explicit-any
  const r = await converterSemSinalNucleo((nada.ctx() as unknown as { sb: never }).sb, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", { via: "dono", autor: "u-dono" }) as any;
  assertEquals(r.codigo, "nao_encontrado");
});

Deno.test("F5 núcleo: a via do assistente é a de antes — o execute chama o núcleo e o resultado não ganha campo novo", async () => {
  const b = banco({ ...ORC, quote_status: "rejected" });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042" }, b.ctx()) as any;
  assertEquals(Object.keys(r), ["error"], "o código fica só no núcleo");
  const c = banco(ORC);
  await converterSemSinalNucleo((c.ctx() as unknown as { sb: never }).sb, ORC.id, { via: "assistente", autor: "u1" });
  assertEquals(c.rpcs[0].params, { p_os: ORC.id, p_para: "approved", p_via: "assistente", p_check_out: null, p_autor: "u1" }, "sem p_motivo");
});

// ── JÁ FOI FEITO (18/11/2026, OS-00129) ──────────────────────────────────────────────────────────────────────────────────────
// O orçamento de 28/10 tinha diagnóstico, nota técnica e o Pix inteiro; foi convertido sem sinal em 16/11 22:00 e entrou na
// agenda. O cartão avisa antes e, com ja_concluida, a porta vai de orçamento direto a concluída.
const NOITE_DA_129 = new Date("2026-11-17T01:00:00Z"); // 16/11 22:00 em Brasília

Deno.test("sinais: a OS-00129 no dia da conversão avisa com a data e os 3 sinais fortes", () => {
  const s = sinaisDeJaFeito({
    criadoEm: "2026-10-28T13:09:39Z", diagnosis: "Diagnóstico do sistema...", technicianNotes: "Foi necessário instalar um conversor",
    checkInAt: null, checkOutAt: null, recebido: 750,
  }, NOITE_DA_129);
  assertEquals(s.idadeDias, 19);
  assertEquals(s.dataDoOrcamento, "28/10");
  assertEquals(s.antigo, true);
  assertEquals(s.avisar, true);
  assertEquals(s.fortes.length, 3);
  const m = motivoDoAviso(s)!;
  assertStringIncludes(m, "orçamento de 28/10 (há 19 dias), já com diagnóstico, nota técnica e R$");
  assertStringIncludes(m, "750,00 já recebido");
});

Deno.test("sinais: orçamento novo sem nada não avisa; 13 dias não é antigo, 14 é; só sinal forte avisa mesmo novo", () => {
  const hoje = new Date("2026-11-18T15:00:00Z");
  const novo = sinaisDeJaFeito({ criadoEm: "2026-11-18T12:00:00Z", recebido: 0, technicianNotes: "  " }, hoje);
  assertEquals([novo.idadeDias, novo.avisar, motivoDoAviso(novo)], [0, false, null]);
  assertEquals(sinaisDeJaFeito({ criadoEm: "2026-11-05T12:00:00Z" }, hoje).antigo, false, "13 dias");
  assertEquals(sinaisDeJaFeito({ criadoEm: "2026-11-04T12:00:00Z" }, hoje).antigo, true, "14 dias");
  const pago = sinaisDeJaFeito({ criadoEm: "2026-11-17T12:00:00Z", recebido: 100 }, hoje);
  assertEquals(pago.avisar, true);
  assertStringIncludes(motivoDoAviso(pago)!, "orçamento de 17/11 (há 1 dia), já com R$");
  // dia em Brasília: 02:00 UTC de 18/11 ainda é 17/11 às 23:00
  assertEquals(sinaisDeJaFeito({ criadoEm: "2026-11-18T02:00:00Z" }, hoje).dataDoOrcamento, "17/11");
  // sem dinheiro conferido (null) não vira sinal
  assertEquals(sinaisDeJaFeito({ criadoEm: "2026-11-18T12:00:00Z", recebido: null }, hoje).avisar, false);
});

Deno.test("dia feito: AAAA-MM-DD de verdade, até hoje em Brasília", () => {
  const hoje = new Date("2026-11-18T02:00:00Z"); // 17/11 23:00 em Brasília
  assertEquals(diaFeitoValido("2026-10-31", hoje), true);
  assertEquals(diaFeitoValido("2026-11-17", hoje), true);
  assertEquals(diaFeitoValido("2026-11-18", hoje), false, "amanhã em Brasília");
  assertEquals(diaFeitoValido("2026-02-30", hoje), false);
  assertEquals(diaFeitoValido("31/10/2026", hoje), false);
});

Deno.test("recusaDoJaFeito: ja_concluida não booleano, dia no futuro ou torto recusam; sem ja_concluida o dia é ignorado", () => {
  const hoje = new Date("2026-11-18T15:00:00Z");
  assert(recusaDoJaFeito({ ja_concluida: "sim" }, hoje));
  assert(recusaDoJaFeito({ ja_concluida: true, concluida_em: "2026-12-01" }, hoje));
  assert(recusaDoJaFeito({ ja_concluida: true, concluida_em: "ontem" }, hoje));
  assertEquals(recusaDoJaFeito({ ja_concluida: true, concluida_em: "2026-10-31" }, hoje), null);
  assertEquals(recusaDoJaFeito({ ja_concluida: true }, hoje), null);
  assertEquals(recusaDoJaFeito({ concluida_em: "ontem" }, hoje), null);
  assertEquals(recusaDoJaFeito({}, hoje), null);
  // o preValidar usa a mesma regra (o dono não vê no sino um pedido que a execução recusaria)
  assert(tool.preValidar!({ service_order_id: "ORÇ-00042", ja_concluida: true, concluida_em: "2099-01-01" }, { userRole: "admin" } as never));
});

const PORTA_CONCLUIU = { ok: true, mudou: true, de: "draft", para: "completed", convertido: true, numero: "OS-00042",
  numero_antes: "ORÇ-00042", check_out_at: "2026-10-31T20:00:00+00:00",
  texto: "Fulano: concluída — saída sex 31/10 17:00. Cobrança: R$ 4.200,00 vence hoje.",
  cobrancas_texto: "Cobrança: R$ 4.200,00 vence hoje." };

Deno.test("já feito: a porta vai de orçamento a concluída, com a saída às 17:00 do dia; o resultado diz que não entra na agenda", async () => {
  const b = banco(ORC, { porta: { resposta: PORTA_CONCLUIU } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042", ja_concluida: true, concluida_em: "2026-10-31" }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.rpcs, [{ nome: "os_transicionar_status", params: {
    p_os: ORC.id, p_para: "completed", p_via: "assistente", p_check_out: "2026-10-31T17:00:00-03:00", p_autor: "u1" } }]);
  assertEquals(b.updates.length, 1, "a condição + aprovado, como sempre");
  assertEquals(r.concluida, true);
  assertEquals(r.documento, "OS-00042");
  assertStringIncludes(r.agenda, "não entra na agenda");
  assertEquals(r.cobranca, "Cobrança: R$ 4.200,00 vence hoje.");
  assertStringIncludes(r.quando_paga, "ligue o pagamento");
});

Deno.test("já feito sem o dia: a saída é a de agora (p_check_out nulo, a porta usa o relógio)", async () => {
  const b = banco(ORC, { porta: { resposta: PORTA_CONCLUIU } });
  await tool.execute({ service_order_id: "ORÇ-00042", ja_concluida: true }, b.ctx());
  assertEquals(b.rpcs[0].params, { p_os: ORC.id, p_para: "completed", p_via: "assistente", p_check_out: null, p_autor: "u1" });
});

Deno.test("já feito: a porta recusa a conclusão (levantamento) = nada convertido, só a condição, e o texto diz por quê", async () => {
  const b = banco(ORC, { porta: { resposta: { ok: false, mudou: false, de: "draft", para: "draft",
    texto: "Antes de concluir, responda o levantamento do serviço X." } } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042", ja_concluida: true }, b.ctx()) as any;
  assertEquals(r.ok, undefined);
  assertStringIncludes(r.error, "a conversão não aconteceu");
  assertStringIncludes(r.error, "levantamento");
});

Deno.test("já feito sem a porta no banco (PLANO B): converte e avisa que NÃO concluiu", async () => {
  const b = banco(ORC, { porta: { ausente: true } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042", ja_concluida: true }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(r.concluida, undefined);
  assert((r.avisos as string[]).some((a) => a.includes("NÃO concluí")), JSON.stringify(r.avisos));
});

Deno.test("já feito: dia no futuro recusa sem tocar em nada", async () => {
  const b = banco(ORC, { porta: { resposta: PORTA_CONCLUIU } });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ service_order_id: "ORÇ-00042", ja_concluida: true, concluida_em: "2099-01-01" }, b.ctx()) as any;
  assert(r.error);
  assertEquals([b.updates.length, b.rpcs.length], [0, 0]);
});

// O cartão: um banco só de leitura com o orçamento e as contas a receber.
function bancoDoCartao(o: Record<string, unknown> | null, recebiveis: { paid_amount: number | null; status: string }[] | "erro") {
  return {
    from(tabela: string) {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve({ data: o, error: null }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve(
          tabela === "receivables" && recebiveis === "erro" ? { data: null, error: { message: "falhou" } }
            : { data: tabela === "receivables" ? recebiveis : null, error: null },
        ).then(ok),
      };
      return q;
    },
  };
}
const ORC_129 = { ...ORC, service_order_number: "ORÇ-00129", grand_total: 750, created_at: "2026-10-28T13:09:39Z",
  diagnosis: "Diagnóstico...", technician_notes: "Foi necessário instalar um conversor", check_in_at: null, check_out_at: null,
  clients: { name: "Cliente Teste" } };

Deno.test("cartão: a OS-00129 mostra a data, o aviso com os sinais e o que dizer — e não vira recusa", async () => {
  const r = (await resumirConversaoSemSinal(
    bancoDoCartao(ORC_129, [{ paid_amount: 750, status: "paid" }, { paid_amount: 50, status: "cancelled" }]),
    { service_order_id: "ORÇ-00129" }, NOITE_DA_129))!;
  const linhas = r.split("\n");
  assertEquals(linhas[0], "Converter ORÇ-00129 em OS sem sinal");
  assertEquals(linhas[1], "Cliente: Cliente Teste");
  assert(linhas.includes("Orçamento de 28/10 (há 19 dias)."), r);
  const atencao = linhas.find((l) => l.startsWith("Atenção:"))!;
  assertStringIncludes(atencao, "já com diagnóstico, nota técnica e R$");
  assertStringIncludes(atencao, "750,00 já recebido");
  assertStringIncludes(atencao, "diga *já foi feito*");
  assert(!r.trim().startsWith("⚠️"), "linha única com ⚠️ viraria recusa (resumoQueRecusa)");
});

Deno.test("cartão: com ja_concluida diz JÁ CONCLUÍDA, o dia e que não entra na agenda (sem o aviso)", async () => {
  const r = (await resumirConversaoSemSinal(bancoDoCartao(ORC_129, [{ paid_amount: 750, status: "paid" }]),
    { service_order_id: "ORÇ-00129", ja_concluida: true, concluida_em: "2026-10-31" }, NOITE_DA_129))!;
  assertStringIncludes(r, "Converter ORÇ-00129 em OS JÁ CONCLUÍDA (serviço feito em 31/10)");
  assertStringIncludes(r, "Não entra na agenda");
  assert(!r.includes("Atenção:"));
});

Deno.test("cartão: orçamento novo e limpo não avisa; leitura do dinheiro que falha é dita (não vira R$ 0); não achou = genérico", async () => {
  const novo = { ...ORC_129, created_at: "2026-11-16T12:00:00Z", diagnosis: null, technician_notes: null };
  const limpo = (await resumirConversaoSemSinal(bancoDoCartao(novo, []), { service_order_id: "ORÇ-00129" }, NOITE_DA_129))!;
  assert(!limpo.includes("Atenção:"), limpo);
  assertStringIncludes(limpo, "Orçamento de 16/11 (de hoje).");
  const semDinheiro = (await resumirConversaoSemSinal(bancoDoCartao(novo, "erro"), { service_order_id: "ORÇ-00129" }, NOITE_DA_129))!;
  assertStringIncludes(semDinheiro, "Não consegui conferir se já entrou dinheiro");
  assertEquals(await resumirConversaoSemSinal(bancoDoCartao(null, []), { service_order_id: "ORÇ-00999" }, NOITE_DA_129), null);
});
