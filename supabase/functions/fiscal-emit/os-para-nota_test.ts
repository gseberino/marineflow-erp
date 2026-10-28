// Run: deno test supabase/functions/fiscal-emit/os-para-nota_test.ts
//
// [FECHAR-JUNTAS 0b, itens 4 e 5] O que se protege aqui:
//  - a ponte da NFS-e lê o "Pedido do cliente" da OS (antes o select não trazia a coluna);
//  - nota com origem em OS só sai de OS de verdade (fora do rascunho), não agrupada e concluída —
//    a NFS-e nº 6 saiu autorizada para o ORÇ-00109 em rascunho;
//  - a revalidação roda em TODA criação com origin_type "service_order", inclusive a emissão
//    detalhada que manda `items`/`service` próprios e não passa pela ponte.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  COLUNAS_OS_PONTE_NFSE,
  STATUS_OS_EMITIVEL,
  conferirOsParaNota,
  motivoOsSemNota,
} from "./os-para-nota.ts";

const OS_OK = {
  service_order_number: "OS-00060",
  status: "completed",
  converted_to_os_at: "2026-08-01T10:00:00Z",
  merged_into_id: null,
};

// ── Item 4 ─────────────────────────────────────────────────────────────────────

Deno.test("a ponte da NFS-e lê customer_po_number (e as colunas que já lia)", () => {
  const colunas = COLUNAS_OS_PONTE_NFSE.split(",").map((c) => c.trim());
  assert(colunas.includes("customer_po_number"));
  for (const c of [
    "id", "service_order_number", "status", "client_id", "discount_amount", "is_travel_billable",
    "travel_cost_total", "operational_cost_total", "subcontract_cost_total", "card_fee_amount", "tax_amount",
  ]) assert(colunas.includes(c), `faltou ${c}`);
});

// ── Item 5: regra pura ─────────────────────────────────────────────────────────

Deno.test("OS concluída ou faturada, convertida e não agrupada pode gerar nota", () => {
  assertEquals([...STATUS_OS_EMITIVEL].sort(), ["completed", "invoiced"]);
  assertEquals(motivoOsSemNota(OS_OK), null);
  assertEquals(motivoOsSemNota({ ...OS_OK, status: "invoiced" }), null);
});

Deno.test("orçamento não convertido é recusado (caso ORÇ-00109)", () => {
  const m = motivoOsSemNota({ service_order_number: "ORÇ-00109", status: "draft", converted_to_os_at: null, merged_into_id: null });
  assert(m);
  assertStringIncludes(m!, "ORÇ-00109 ainda é orçamento");
});

Deno.test("OS concluída antiga sem converted_to_os_at pode gerar nota (caso ORÇ-00070)", () => {
  // Mesmo critério do banco: fora do rascunho é OS, mesmo sem a data de conversão.
  assertEquals(
    motivoOsSemNota({ service_order_number: "ORÇ-00070", status: "completed", converted_to_os_at: null, merged_into_id: null }),
    null,
  );
  assertEquals(motivoOsSemNota({ ...OS_OK, status: "invoiced", converted_to_os_at: null }), null);
});

Deno.test("rascunho sem conversão continua recusado como orçamento", () => {
  const m = motivoOsSemNota({ ...OS_OK, status: "draft", converted_to_os_at: null });
  assert(m);
  assertStringIncludes(m!, "ainda é orçamento");
});

Deno.test("OS sem a data e fora de concluída é recusada pelo status, não como orçamento", () => {
  // A cópia do "Duplicar" nasce 'open' sem converted_to_os_at: é OS, só não está concluída.
  const m = motivoOsSemNota({ ...OS_OK, status: "open", converted_to_os_at: null });
  assert(m);
  assertStringIncludes(m!, "OS-00060 está aberta");
});

Deno.test("OS agrupada sem a data continua recusada como agrupada", () => {
  const m = motivoOsSemNota({ ...OS_OK, status: "cancelled", converted_to_os_at: null, merged_into_id: "d" }, "OS-00090");
  assert(m);
  assertStringIncludes(m!, "agrupada na OS-00090");
});

Deno.test("OS agrupada é recusada e a mensagem aponta a OS de destino", () => {
  const m = motivoOsSemNota({ ...OS_OK, status: "cancelled", merged_into_id: "dest-1" }, "OS-00090");
  assert(m);
  assertStringIncludes(m!, "agrupada na OS-00090");
});

Deno.test("OS cancelada mantém a mensagem de sempre", () => {
  assertEquals(motivoOsSemNota({ ...OS_OK, status: "cancelled" }), "OS cancelada não pode gerar nota.");
});

Deno.test("OS não concluída é recusada com o status em português", () => {
  for (const [status, rotulo] of [
    ["in_progress", "em execução"],
    ["scheduled", "agendada"],
    ["open", "aberta"],
    ["awaiting_parts", "aguardando peças"],
    ["awaiting_client", "aguardando o cliente"],
    ["approved", "aprovada"],
    ["draft", "em rascunho"],
  ]) {
    const m = motivoOsSemNota({ ...OS_OK, status });
    assert(m, status);
    assertStringIncludes(m!, `OS-00060 está ${rotulo}`);
    assertStringIncludes(m!, "Conclua a OS");
  }
});

Deno.test("status desconhecido também é recusado (lista fechada)", () => {
  const m = motivoOsSemNota({ ...OS_OK, status: "reopened" });
  assert(m);
  assertStringIncludes(m!, 'status "reopened"');
});

// ── Item 5: leitura no banco ───────────────────────────────────────────────────

function bancoFalso(linhas: Record<string, Record<string, unknown> | null>, erro: unknown = null) {
  const lidas: string[] = [];
  return {
    lidas,
    from(tabela: string) {
      assertEquals(tabela, "service_orders");
      return {
        select: (_colunas: string) => ({
          eq: (_coluna: string, id: string) => ({
            maybeSingle: () => {
              lidas.push(id);
              return Promise.resolve({ data: erro ? null : (linhas[id] ?? null), error: erro });
            },
          }),
        }),
      };
    },
  };
}

Deno.test("sem origin_id: recusa sem consultar nada", async () => {
  const banco = bancoFalso({});
  const r = await conferirOsParaNota(banco, null);
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.status, 422);
    assertStringIncludes(r.error, "Nada foi emitido");
  }
  assertEquals(banco.lidas, []);
});

Deno.test("OS válida passa", async () => {
  const r = await conferirOsParaNota(bancoFalso({ "os-1": { id: "os-1", ...OS_OK } }), "os-1");
  assertEquals(r, { ok: true });
});

Deno.test("OS inexistente: 404", async () => {
  const r = await conferirOsParaNota(bancoFalso({}), "nao-existe");
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.status, 404);
});

Deno.test("erro do banco: 500 com o motivo (não vira 'OS válida')", async () => {
  const r = await conferirOsParaNota(bancoFalso({}, { message: "timeout" }), "os-1");
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.status, 500);
    assertStringIncludes(r.error, "timeout");
  }
});

Deno.test("orçamento em rascunho: 422 e nada emitido", async () => {
  const banco = bancoFalso({
    "orc-109": { id: "orc-109", service_order_number: "ORÇ-00109", status: "draft", converted_to_os_at: null, merged_into_id: null },
  });
  const r = await conferirOsParaNota(banco, "orc-109");
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.status, 422);
    assertStringIncludes(r.error, "ORÇ-00109 ainda é orçamento");
    assertStringIncludes(r.error, "Nada foi emitido");
  }
});

Deno.test("OS agrupada: lê o número do destino para a mensagem", async () => {
  const banco = bancoFalso({
    "os-a": { id: "os-a", service_order_number: "OS-00081", status: "cancelled", converted_to_os_at: "2026-10-01T00:00:00Z", merged_into_id: "os-b" },
    "os-b": { service_order_number: "OS-00090" },
  });
  const r = await conferirOsParaNota(banco, "os-a");
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.error, "OS-00081 foi agrupada na OS-00090");
  assertEquals(banco.lidas, ["os-a", "os-b"]);
});

// ── Ligação com o index.ts ─────────────────────────────────────────────────────
// O index.ts sobe o servidor ao ser importado, então a ligação é conferida no fonte: as duas
// criações (NF-e e NFS-e) chamam a revalidação ANTES de reservar número, e a ponte da NFS-e
// usa as colunas com o pedido do cliente.

function trechoDaFuncao(fonte: string, nome: string): string {
  const inicio = fonte.indexOf(`async function ${nome}(`);
  assert(inicio >= 0, `não achei ${nome}`);
  const fim = fonte.indexOf("\nasync function ", inicio + 10);
  return fonte.slice(inicio, fim > 0 ? fim : undefined);
}

Deno.test("handleCreate e handleCreateNfse revalidam a OS antes de reservar número", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (const nome of ["handleCreate", "handleCreateNfse"]) {
    const corpo = trechoDaFuncao(fonte, nome);
    const guarda = corpo.indexOf("conferirOsParaNota(admin, originId)");
    const numero = corpo.indexOf('rpc("next_fiscal_number"');
    const duplicidade = corpo.indexOf("findActiveDocument(");
    assert(guarda > 0, `${nome} não revalida a OS`);
    assert(numero > guarda, `${nome} reserva número antes de revalidar`);
    assert(duplicidade > guarda, `${nome} reaproveita/descarta rascunho antes de revalidar`);
    assertStringIncludes(corpo, 'originType === "service_order"');
  }
});

Deno.test("o pré-voo do Faturar aplica a mesma revalidação antes de montar as pontes", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const corpo = trechoDaFuncao(fonte, "handleBillingPreflight");
  const guarda = corpo.indexOf("conferirOsParaNota(admin, soId)");
  assert(guarda > 0, "handleBillingPreflight não revalida a OS");
  assert(corpo.indexOf("buildNfseBodyFromServiceOrder(") > guarda, "pré-voo monta a NFS-e antes de revalidar");
  assert(corpo.indexOf("buildBodyFromServiceOrder(") > guarda, "pré-voo monta a NF-e antes de revalidar");
  // Recusa vira pendência dos dois cartões (pronto: false), sem esconder os documentos já emitidos.
  const recusa = corpo.slice(guarda, corpo.indexOf("// ── NFS-e (serviços) ──"));
  assertStringIncludes(recusa, "pronto: false, erro: valida.error");
  assertStringIncludes(recusa, "documentos: docs ?? []");
});

Deno.test("a ponte da NFS-e usa as colunas com customer_po_number", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const corpo = trechoDaFuncao(fonte, "buildNfseBodyFromServiceOrder");
  assertStringIncludes(corpo, ".select(COLUNAS_OS_PONTE_NFSE)");
  assertStringIncludes(corpo, "pedidoCliente: so.customer_po_number");
});
