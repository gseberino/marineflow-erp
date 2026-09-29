// Run: deno test supabase/functions/_shared/ai/atalho-pdf_test.ts
//
// O atalho sem modelo só pode pegar o pedido de PDF PARA SI. O que se protege aqui: as formas
// comuns (inclusive a transcrição do áudio de 25/09) caem no atalho, e qualquer frase com algo
// a mais — cliente, desconto, dois documentos — segue para o modelo.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerPedidoDePdf, textoDoAtalhoPdf } from "./atalho-pdf.ts";

Deno.test("pedidos de PDF para si caem no atalho", () => {
  assertEquals(lerPedidoDePdf("pdf 108"), { documento: "108" });
  assertEquals(lerPedidoDePdf("PDF do orçamento 108"), { documento: "108", tipo: "orcamento" });
  assertEquals(lerPedidoDePdf("Me manda o PDF do orçamento 108"), { documento: "108", tipo: "orcamento" });
  // A transcrição do áudio do teste de 25/09/2026:
  assertEquals(lerPedidoDePdf("Me envia o orçamento 108 em PDF."), { documento: "108", tipo: "orcamento" });
  assertEquals(lerPedidoDePdf("manda o pdf da OS 75 por favor"), { documento: "75", tipo: "os" });
  assertEquals(lerPedidoDePdf("pdf ORÇ-00108"), { documento: "108", tipo: "orcamento" });
  assertEquals(lerPedidoDePdf("pdf os-00075"), { documento: "75", tipo: "os" });
  assertEquals(lerPedidoDePdf("pdf da ordem de serviço 75"), { documento: "75", tipo: "os" });
  assertEquals(lerPedidoDePdf("quero ver o pdf do último orçamento"), { documento: "ultimo", tipo: "orcamento" });
  assertEquals(lerPedidoDePdf("pdf 0108"), { documento: "108" });
});

Deno.test("qualquer coisa além do pedido segue para o modelo", () => {
  assertEquals(lerPedidoDePdf("manda o pdf do orçamento 108 pro cliente"), null);
  assertEquals(lerPedidoDePdf("manda o pdf do 108 para o Carlos"), null);
  assertEquals(lerPedidoDePdf("pdf do orçamento 108 com 10% de desconto"), null);
  assertEquals(lerPedidoDePdf("pdf do 108 e do 109"), null);
  assertEquals(lerPedidoDePdf("o orçamento 108 foi aprovado?"), null); // sem "pdf"
  assertEquals(lerPedidoDePdf("pdf"), null); // sem documento
  assertEquals(lerPedidoDePdf("pdf da os do orçamento 108"), null); // tipo contraditório
  assertEquals(lerPedidoDePdf("gera o pdf do orçamento 108 e manda no email"), null);
  assertEquals(lerPedidoDePdf(""), null);
});

Deno.test("texto da resposta: enviado, repetido, ambíguo e falha", () => {
  assertEquals(
    textoDoAtalhoPdf({ ok: true, documento: "ORÇ-00108", cliente: "RF Silva", total: "R$ 1.866,00", enviado_para: "o WhatsApp de quem pediu" }),
    "Pronto: mandei o PDF do ORÇ-00108 (RF Silva, R$ 1.866,00).",
  );
  assertEquals(
    textoDoAtalhoPdf({ ok: true, documento: "ORÇ-00108", enviado_para: "o número de TESTE do WhatsApp (modo de teste ligado)" }).includes("modo de teste"),
    true,
  );
  assertEquals(textoDoAtalhoPdf({ ok: true, deduplicated: true, aviso: "Já mandei há instantes." }), "Já mandei há instantes.");
  assertEquals(
    textoDoAtalhoPdf({ error: "x", opcoes: ["ORÇ-00075", "OS-00075"] }).startsWith("Achei mais de um com esse número: ORÇ-00075 e OS-00075."),
    true,
  );
  assertEquals(
    textoDoAtalhoPdf({ error: "Não achei o orçamento 999", link_interno: "https://x/service-orders/1" }),
    "Não consegui mandar o PDF: Não achei o orçamento 999. Pelo sistema: https://x/service-orders/1",
  );
});
