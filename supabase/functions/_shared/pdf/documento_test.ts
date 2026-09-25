import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { buildOrderHTML, DEFAULT_PDF_OPTIONS } from "./documento.ts";
import { AGORA, ORCAMENTO, OS_COM_PAGAMENTO } from "./amostras.ts";

// A metade Deno da paridade (a outra é src/lib/pdf-paridade-fuso.test.ts, no vitest).
//
// O assistente do WhatsApp gera o PDF numa Edge Function. Este teste roda o desenho do
// documento no Deno e compara com as MESMAS referências que o teste do navegador usa: se os
// dois passam, o orçamento que o dono recebe no WhatsApp é o que ele baixaria na tela.
//
// A independência de FUSO é provada do lado do vitest, que troca `process.env.TZ` entre
// quatro fusos (o Node respeita). O Deno no Windows IGNORA a variável TZ — conferido em
// 25/09/2026: `TZ=UTC deno eval` continua em Brasília —, então aqui o que se prova é outra
// coisa: que o motor do Deno (Intl, ICU) formata moeda e data byte a byte como o do Node.
// Num Linux, `TZ=UTC deno test --allow-read supabase/functions/_shared/pdf/` roda no fuso
// da Edge Function de verdade.

// fromFileUrl e não `new URL(...).pathname`: o caminho deste repo tem espaço ("Claude Code").
const REFERENCIA = join(dirname(fromFileUrl(import.meta.url)), "__referencia__");
const ler = (arquivo: string) => Deno.readTextFileSync(join(REFERENCIA, arquivo)).replace(/\r\n/g, "\n");

Deno.test("orçamento no Deno = referência do navegador", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    const html = buildOrderHTML(ORCAMENTO, { ...DEFAULT_PDF_OPTIONS, validity: { mode: "days", days: 7 } });
    assertEquals(html, ler("orcamento.html"));
  } finally {
    tempo.restore();
  }
});

Deno.test("OS com pagamento no Deno = referência do navegador", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    assertEquals(buildOrderHTML(OS_COM_PAGAMENTO, { ...DEFAULT_PDF_OPTIONS }), ler("os-com-pagamento.html"));
  } finally {
    tempo.restore();
  }
});
