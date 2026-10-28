// Run: deno test supabase/functions/banking-reconcile/cobranca-quitada_test.ts
//
// [FECHAR-JUNTAS 0b, item 2] A cobrança avulsa conciliada pelo extrato ficava `pending` porque o
// valor gravado em payment_confirmed_by ("conciliacao") era recusado pelo CHECK e o erro não era
// conferido. O que se protege aqui: o valor é um dos aceitos pelo CHECK, e erro ou nenhuma linha
// alterada viram falha explícita em vez de sucesso silencioso.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CONFIRMADO_PELA_CONCILIACAO,
  dadosDaCobrancaQuitada,
  mensagemCobrancaNaoFechou,
  quitarCobrancaConciliada,
} from "./cobranca-quitada.ts";

// Os valores que collections_payment_confirmed_by_check aceita (02-tabelas.sql:1099).
const ACEITOS_PELO_CHECK = ["manual", "whatsapp", "auto"];

function bancoFalso(resposta: { data: unknown; error: unknown }) {
  const chamadas: Array<{ tabela: string; valores: Record<string, unknown>; filtro: [string, string]; colunas: string }> = [];
  return {
    chamadas,
    from(tabela: string) {
      return {
        update: (valores: Record<string, unknown>) => ({
          eq: (coluna: string, valor: string) => ({
            select: (colunas: string) => {
              chamadas.push({ tabela, valores, filtro: [coluna, valor], colunas });
              return Promise.resolve(resposta);
            },
          }),
        }),
      };
    },
  };
}

const AGORA = new Date("2026-10-28T12:00:00.000Z");

Deno.test("quem confirmou é um valor que o CHECK da tabela aceita", () => {
  assert(ACEITOS_PELO_CHECK.includes(CONFIRMADO_PELA_CONCILIACAO));
  const dados = dadosDaCobrancaQuitada("rec-1", 150, AGORA);
  assert(ACEITOS_PELO_CHECK.includes(String(dados.payment_confirmed_by)));
  assert(dados.payment_confirmed_by !== "conciliacao");
});

Deno.test("os dados fecham a cobrança e a ligam à conta criada", () => {
  assertEquals(dadosDaCobrancaQuitada("rec-1", 150, AGORA), {
    receivable_id: "rec-1",
    status: "paid",
    paid_at: "2026-10-28T12:00:00.000Z",
    paid_amount: 150,
    paid_method: "bank_transfer",
    payment_confirmed_by: "auto",
  });
});

Deno.test("sucesso: grava na cobrança certa e pede a linha de volta para conferir", async () => {
  const banco = bancoFalso({ data: [{ id: "cob-1" }], error: null });
  const r = await quitarCobrancaConciliada(banco, "cob-1", "rec-1", 150, AGORA);
  assertEquals(r, { ok: true });
  assertEquals(banco.chamadas.length, 1);
  assertEquals(banco.chamadas[0].tabela, "collections");
  assertEquals(banco.chamadas[0].filtro, ["id", "cob-1"]);
  assertEquals(banco.chamadas[0].colunas, "id");
  assertEquals(banco.chamadas[0].valores.payment_confirmed_by, "auto");
});

Deno.test("erro do banco (ex.: CHECK) vira falha com o motivo, não sucesso silencioso", async () => {
  const banco = bancoFalso({
    data: null,
    error: { message: 'new row for relation "collections" violates check constraint "collections_payment_confirmed_by_check"' },
  });
  const r = await quitarCobrancaConciliada(banco, "cob-1", "rec-1", 150, AGORA);
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.message, "collections_payment_confirmed_by_check");
});

Deno.test("nenhuma linha alterada também é falha", async () => {
  const banco = bancoFalso({ data: [], error: null });
  const r = await quitarCobrancaConciliada(banco, "cob-x", "rec-1", 150, AGORA);
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.message, "não foi encontrada");
});

Deno.test("a mensagem de falha avisa que o dinheiro entrou e manda NÃO conciliar de novo", () => {
  const m = mensagemCobrancaNaoFechou("Cobrança — Fulano", "erro x");
  assertStringIncludes(m, "Recebimento lançado");
  assertStringIncludes(m, "Cobrança — Fulano");
  assertStringIncludes(m, "erro x");
  assertStringIncludes(m, "Não concilie de novo");
});

Deno.test("a função não grava mais o valor recusado e passa pelo fechamento conferido", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(!/payment_confirmed_by:\s*["']conciliacao["']/.test(fonte), "index.ts ainda grava 'conciliacao'");
  assertStringIncludes(fonte, "quitarCobrancaConciliada(");
});
