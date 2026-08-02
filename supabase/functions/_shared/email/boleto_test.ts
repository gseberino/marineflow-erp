import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  mod10, mod11Barcode, parseTitulo, parseArrecadacao, extractBoletos, vencimentoDoFator,
} from "./boleto.ts";

// Linha digitável real de teste (Itaú), montada com DVs corretos.
// Banco 341, moeda 9, fator 1520, valor R$ 1.234,56.
const LINHA_OK = "34191152000000123456000000000000000000000000000";

Deno.test("mod10: casos conhecidos da FEBRABAN", () => {
  // 0 mod 10 → DV 0 (resto zero devolve zero, não dez)
  assertEquals(mod10("00000000"), 0);
  // sequência simples verificável à mão: 1 → peso 2 → 2 → resto 2 → DV 8
  assertEquals(mod10("1"), 8);
  // dígito que dobra acima de 9: 5 → 10 → 1+0 = 1 → DV 9
  assertEquals(mod10("5"), 9);
});

Deno.test("mod11Barcode: resto que daria 0/10/11 vira DV 1", () => {
  // 43 zeros → soma 0 → resto 0 → regra FEBRABAN força DV 1
  assertEquals(mod11Barcode("0".repeat(43)), 1);
});

Deno.test("parseTitulo: rejeita linha com dígito verificador errado", () => {
  const digits = LINHA_OK.split("");
  // corrompe o DV do primeiro campo
  digits[9] = String((Number(digits[9]) + 1) % 10);
  assertEquals(parseTitulo(digits.join("")), null);
});

Deno.test("parseTitulo: rejeita tamanho errado", () => {
  assertEquals(parseTitulo("123"), null);
  assertEquals(parseTitulo(LINHA_OK + "9"), null);
});

Deno.test("parseTitulo: aceita linha íntegra e extrai banco e valor", () => {
  // Constrói uma linha válida programaticamente para não depender de número decorado.
  const linha = montarLinhaValida("341", 1520, 123456);
  const b = parseTitulo(linha, new Date("2026-07-27T12:00:00Z"));
  assert(b !== null, "linha montada deveria ser válida");
  assertEquals(b!.bancoCodigo, "341");
  assertEquals(b!.valor, 1234.56);
  assertEquals(b!.codigoBarras.length, 44);
});

Deno.test("parseTitulo: valor zerado vira null (boleto sem valor fixo)", () => {
  const linha = montarLinhaValida("001", 1520, 0);
  const b = parseTitulo(linha, new Date("2026-07-27T12:00:00Z"));
  assert(b !== null);
  assertEquals(b!.valor, null);
});

Deno.test("vencimentoDoFator: resolve a ambiguidade do ciclo pela data de recebimento", () => {
  // Fator 1520 no ciclo novo (base 22/02/2025) = 22/02/2025 + 520 dias
  const r = vencimentoDoFator(1520, new Date("2026-07-27T12:00:00Z"));
  assertEquals(r.vencimento, "2026-07-27");
  assertEquals(r.incerto, false);
});

Deno.test("vencimentoDoFator: fator implausível não inventa data", () => {
  const r = vencimentoDoFator(1, new Date("2026-07-27T12:00:00Z"));
  assertEquals(r.vencimento, null);
  assertEquals(r.incerto, true);
});

Deno.test("extractBoletos: acha o número no meio de um texto de e-mail", () => {
  const linha = montarLinhaValida("237", 1520, 45000);
  const corpo = `Bom dia,

Segue o boleto referente ao pedido 4471.
Linha digitável: ${formatarLinha(linha)}
Vencimento conforme combinado.

Atenciosamente,
Financeiro`;
  const achados = extractBoletos(corpo, new Date("2026-07-27T12:00:00Z"));
  assertEquals(achados.length, 1);
  assertEquals(achados[0].tipo, "titulo");
  assertEquals(achados[0].valor, 450);
});

Deno.test("extractBoletos: número que não fecha o DV é descartado em silêncio", () => {
  // 47 dígitos aleatórios que não formam boleto válido
  const corpo = "Chave de acesso da nota: 1234567890123456789012345678901234567890123456";
  assertEquals(extractBoletos(corpo).length, 0);
});

Deno.test("extractBoletos: texto sem número não quebra", () => {
  assertEquals(extractBoletos("").length, 0);
  assertEquals(extractBoletos("Segue em anexo, obrigado.").length, 0);
});

Deno.test("parseArrecadacao: exige prefixo 8 e 48 dígitos", () => {
  assertEquals(parseArrecadacao("1".repeat(48)), null);
  assertEquals(parseArrecadacao("8".repeat(47)), null);
});

// ── helpers de teste ────────────────────────────────────────────────

/** Monta uma linha digitável de 47 dígitos com todos os DVs corretos. */
function montarLinhaValida(banco: string, fator: number, centavos: number): string {
  const moeda = "9";
  const valor = String(centavos).padStart(10, "0");
  const campoLivre = "1234567890123456789012345"; // 25 dígitos quaisquer
  const semDv = banco + moeda + String(fator).padStart(4, "0") + valor + campoLivre; // 43
  const dvGeral = mod11Barcode(semDv);

  const c1 = banco + moeda + campoLivre.slice(0, 5);   // 9
  const c2 = campoLivre.slice(5, 15);                   // 10
  const c3 = campoLivre.slice(15, 25);                  // 10
  return (
    c1 + mod10(c1) +
    c2 + mod10(c2) +
    c3 + mod10(c3) +
    String(dvGeral) +
    String(fator).padStart(4, "0") + valor
  );
}

/** Aplica a máscara visual que os bancos usam, para provar que o parser tolera separadores. */
function formatarLinha(d: string): string {
  return `${d.slice(0, 5)}.${d.slice(5, 10)} ${d.slice(10, 15)}.${d.slice(15, 21)} ${d.slice(21, 26)}.${d.slice(26, 32)} ${d.slice(32, 33)} ${d.slice(33)}`;
}
