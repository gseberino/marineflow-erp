import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { feriadoDoDia, pascoa, tipoDoDia } from "./feriados.ts";

Deno.test("Páscoa (Meeus) nos anos conhecidos", () => {
  assertEquals(pascoa(2024), "2024-03-31");
  assertEquals(pascoa(2025), "2025-04-20");
  assertEquals(pascoa(2026), "2026-04-05");
  assertEquals(pascoa(2027), "2027-03-28");
  assertEquals(pascoa(2028), "2028-04-16");
});

Deno.test("feriados nacionais, a Sexta-feira Santa e o de Itajaí", () => {
  assertEquals(feriadoDoDia("2026-10-12"), "Nossa Senhora Aparecida");
  assertEquals(feriadoDoDia("2026-11-02"), "Finados");
  assertEquals(feriadoDoDia("2026-11-20"), "Consciência Negra");
  assertEquals(feriadoDoDia("2026-04-03"), "Sexta-feira Santa");
  assertEquals(feriadoDoDia("2027-03-26"), "Sexta-feira Santa");
  assertEquals(feriadoDoDia("2026-06-15"), "aniversário de Itajaí");
  assertEquals(feriadoDoDia("2026-12-25"), "Natal");
});

Deno.test("ponto facultativo e o estadual transferido NÃO são feriado (manhã normal)", () => {
  assertEquals(feriadoDoDia("2026-02-16"), null); // segunda de Carnaval
  assertEquals(feriadoDoDia("2026-02-17"), null); // Carnaval
  assertEquals(feriadoDoDia("2026-06-04"), null); // Corpus Christi
  assertEquals(feriadoDoDia("2026-08-11"), null); // SC: vai para o domingo seguinte
  assertEquals(feriadoDoDia("2026-10-28"), null); // Dia do Servidor
});

Deno.test("tipoDoDia: domingo vale antes do feriado; quinta comum é útil; sábado é útil", () => {
  assertEquals(tipoDoDia("2026-10-15"), "util");
  assertEquals(tipoDoDia("2026-10-17"), "util"); // sábado tem manhã
  assertEquals(tipoDoDia("2026-10-18"), "domingo");
  assertEquals(tipoDoDia("2026-10-12"), "feriado"); // segunda
  assertEquals(tipoDoDia("2026-11-15"), "domingo"); // feriado num domingo: "Domingo"
});
