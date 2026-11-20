// "imprime as vias de amanhã" (20/11/2026, a sugestão das 19:30 da véspera): o documento 'amanha' lê a agenda do DIA SEGUINTE
// em Brasília, pela mesma regra das vias de hoje. O papel em si (abrir a via, a fila do PC) é o mesmo caminho de "hoje".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { diaDasVias, imprimirParaQuemPediu } from "./impressao.ts";
import { bancoFalso } from "../../impressao/banco-falso-de-teste.ts";
import { WORKER_DA_IMPRESSORA } from "../../impressao/fila.ts";
import { hojeEmBrasilia } from "../../pdf/via-do-tecnico-dados.ts";
import { diaSeguinte } from "../../impressao/agenda.ts";
import type { ToolCtx } from "./registry.ts";

Deno.test("diaDasVias: hoje, amanhã (com e sem acento) e o resto", () => {
  for (const s of ["hoje", "as vias de hoje", "vias de hoje", "do dia"]) assertEquals(diaDasVias(s), "hoje", s);
  for (const s of ["amanha", "amanhã", "Amanhã", "as vias de amanhã", "vias de amanha", "via de amanhã"]) assertEquals(diaDasVias(s), "amanha", s);
  for (const s of ["86", "OS-00136", "ultimo", "hoje e amanhã", "depois de amanhã", ""]) assertEquals(diaDasVias(s), null, s);
});

Deno.test("documento 'amanha': lê a agenda do dia seguinte e diz que não há OS amanhã", async () => {
  const { admin, chamadas } = bancoFalso((c) => {
    if (c.tabela === "ai_gateway_workers") {
      return { data: { enabled: true, last_seen_at: new Date().toISOString(), estado: {} } };
    }
    if (c.tabela === "agenda_alocacoes") return { data: [] };
    return { data: null };
  });
  const ctx = { admin, sb: admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  const r = await imprimirParaQuemPediu({ documento: "amanha", via: "tecnico", destino: "impressora" }, ctx);
  assertEquals(r.frase, "Não há OS na agenda de amanhã; nada a imprimir.");
  const agenda = chamadas.find((c) => c.tabela === "agenda_alocacoes")!;
  assertEquals(agenda.filtros.find(([nome, col]) => nome === "eq" && col === "dia")?.[2], diaSeguinte(hojeEmBrasilia()));
  assertEquals(chamadas.some((c) => c.tabela === "ai_gateway_workers" && c.filtros.some(([, , v]) => v === WORKER_DA_IMPRESSORA)), true);
});

Deno.test("documento 'hoje' continua lendo o dia de hoje", async () => {
  const { admin, chamadas } = bancoFalso((c) => {
    if (c.tabela === "ai_gateway_workers") return { data: { enabled: true, last_seen_at: new Date().toISOString(), estado: {} } };
    return { data: [] };
  });
  const ctx = { admin, sb: admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  const r = await imprimirParaQuemPediu({ documento: "hoje", via: "tecnico", destino: "impressora" }, ctx);
  assertEquals(r.frase, "Não há OS na agenda de hoje; nada a imprimir.");
  const agenda = chamadas.find((c) => c.tabela === "agenda_alocacoes")!;
  assertEquals(agenda.filtros.find(([nome, col]) => nome === "eq" && col === "dia")?.[2], hojeEmBrasilia());
});
