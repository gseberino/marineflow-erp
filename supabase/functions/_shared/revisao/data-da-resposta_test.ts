// A data que o cliente responde ao lembrete (07/10/2026): o webhook lê aqui e a RPC adia o plano.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerDataDaResposta } from "./data-da-resposta.ts";

const quarta = new Date("2026-10-07T15:00:00Z"); // qua 07/10/2026, 12h em Brasília

Deno.test("data da resposta: dia do mês, dd/mm e dd/mm/aaaa, sempre no futuro", () => {
  assertEquals(lerDataDaResposta("dia 15", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("Pode ser dia 15?", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("15", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("dia 5", quarta), "2026-11-05", "dia que já passou neste mês vai para o próximo");
  assertEquals(lerDataDaResposta("dia 7", quarta), "2026-11-07", "hoje não é futuro");
  assertEquals(lerDataDaResposta("15/10", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("05/10", quarta), "2027-10-05", "dd/mm que já passou é do ano que vem");
  assertEquals(lerDataDaResposta("15/10/2026", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("15/10/26", quarta), "2026-10-15");
  assertEquals(lerDataDaResposta("01/10/2026", quarta), null, "data com ano no passado não vale");
  assertEquals(lerDataDaResposta("31/02", quarta), null);
  assertEquals(lerDataDaResposta("dia 31", quarta), "2026-10-31");
  assertEquals(lerDataDaResposta("dia 31", new Date("2026-11-07T15:00:00Z")), "2026-12-31", "novembro não tem 31: vai para dezembro");
});

Deno.test("data da resposta: semana que vem, mês que vem, daqui a N", () => {
  assertEquals(lerDataDaResposta("semana que vem", quarta), "2026-10-12");
  assertEquals(lerDataDaResposta("Próxima semana!", quarta), "2026-10-12");
  assertEquals(lerDataDaResposta("semana que vem", new Date("2026-10-12T15:00:00Z")), "2026-10-19", "na segunda, a semana que vem é a outra segunda");
  assertEquals(lerDataDaResposta("mês que vem", quarta), "2026-11-01");
  assertEquals(lerDataDaResposta("mes que vem", new Date("2026-12-20T15:00:00Z")), "2027-01-01");
  assertEquals(lerDataDaResposta("dia 5", new Date("2026-12-20T15:00:00Z")), "2027-01-05");
  assertEquals(lerDataDaResposta("daqui a 2 semanas", quarta), "2026-10-21");
  assertEquals(lerDataDaResposta("daqui 10 dias", quarta), "2026-10-17");
});

Deno.test("data da resposta: o que não é data volta null", () => {
  assertEquals(lerDataDaResposta("sim", quarta), null);
  assertEquals(lerDataDaResposta("PARAR", quarta), null);
  assertEquals(lerDataDaResposta("", quarta), null);
  assertEquals(lerDataDaResposta(null, quarta), null);
  assertEquals(lerDataDaResposta("pode ser", quarta), null);
  assertEquals(
    lerDataDaResposta("Bom dia! Estou viajando agora, depois do dia 15 eu volto e a gente vê com calma isso tudo, obrigado", quarta),
    null,
    "mensagem longa: 'dia 15' pode ser qualquer coisa",
  );
  // Fuso: 23h30 de 07/10 em Brasília ainda é dia 07 — "dia 8" é amanhã.
  assertEquals(lerDataDaResposta("dia 8", new Date("2026-10-08T02:30:00Z")), "2026-10-08");
});
