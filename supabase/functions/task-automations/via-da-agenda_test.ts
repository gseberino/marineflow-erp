// A via do técnico com a ficha das 19:30: quando vai, quando não vai.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decidirAVia,
  FALHAS_ATE_DESISTIR,
  horaEmBrasilia,
  itensPendentes,
  rotuloDoDia,
  viaDaAgenda,
} from "./via-da-agenda.ts";

const F1 = { id: "f1", payee_id: "alex", dia: "2026-11-26", fila_id: "q1", alocacao_ids: ["a1", "a2"] };
const F2 = { id: "f2", payee_id: "alex", dia: "2026-11-27", fila_id: "q2", alocacao_ids: ["a3"] };
const OS = new Map([["a1", "os119"], ["a2", "os119"], ["a3", "os119"], ["r1", "os200"]]);

Deno.test("só a ficha que a fila ENTREGOU leva a via; uma OS por ficha mesmo com manhã e tarde", () => {
  const { fazer } = itensPendentes([F1, F2], new Set(["q1"]), OS, []);
  assertEquals(fazer.map((i) => `${i.ficha.id}:${i.os}`), ["f1:os119"]);
});

Deno.test("ficha com via enviada ou pulada não volta; falhou volta até desistir", () => {
  const entregues = new Set(["q1", "q2"]);
  const enviada = [{ ficha_id: "f1", service_order_id: "os119", estado: "enviado" }];
  assertEquals(itensPendentes([F1, F2], entregues, OS, enviada).fazer.map((i) => i.ficha.id), ["f2"]);
  const pulada = [{ ficha_id: "f1", service_order_id: "os119", estado: "pulado" }];
  assertEquals(itensPendentes([F1], entregues, OS, pulada).fazer.length, 0);
  const falhou = Array.from({ length: FALHAS_ATE_DESISTIR - 1 }, () => ({ ficha_id: "f1", service_order_id: "os119", estado: "falhou" }));
  assertEquals(itensPendentes([F1], entregues, OS, falhou).fazer.length, 1);
  const desiste = [...falhou, { ficha_id: "f1", service_order_id: "os119", estado: "falhou" }];
  const r = itensPendentes([F1], entregues, OS, desiste);
  assertEquals([r.fazer.length, r.desistir.length], [0, 1]);
});

Deno.test("reserva não é dia de trabalho: alocação fora do mapa (reserva) não gera via", () => {
  const soReserva = { ...F1, alocacao_ids: ["reserva-x"] };
  assertEquals(itensPendentes([soReserva], new Set(["q1"]), OS, []).fazer.length, 0);
});

Deno.test("1º dia: manda, dizendo para que dia", () => {
  assertEquals(decidirAVia(null, "h1", "2026-11-26", false), { acao: "mandar", complemento: "Para qui 26/11, junto da ficha." });
});

Deno.test("mesma versão já recebida (pela agenda ou pelo dono): não repete", () => {
  const r = decidirAVia({ impressao: "h1", criado_em: "2026-11-25T22:45:00Z" }, "h1", "2026-11-27", false);
  assertEquals(r, { acao: "pular", motivo: "já recebeu esta via em 25/11" });
});

Deno.test("a OS mudou: manda de novo, dizendo que substitui a anterior", () => {
  const r = decidirAVia({ impressao: "h1", criado_em: "2026-11-25T22:45:00Z" }, "h2", "2026-11-30", true);
  assertEquals(r, {
    acao: "mandar",
    complemento: "A OS mudou desde a via de 25/11: esta substitui a anterior. Só os seus serviços e os sem responsável.",
  });
});

Deno.test("hora e dia em Brasília", () => {
  assertEquals(horaEmBrasilia(new Date("2026-11-25T22:45:00Z")), 19);
  assertEquals(horaEmBrasilia(new Date("2026-11-25T23:00:00Z")), 20);
  assertEquals(rotuloDoDia("2026-11-28"), "sáb 28/11");
});

Deno.test("desligada pela chave ou fora da janela: nem lê o banco", async () => {
  const semBanco = { from: () => { throw new Error("não devia ler"); } };
  assertEquals(await viaDaAgenda(semBanco, { via_tecnico_na_agenda: "desligado" }, new Date("2026-11-25T22:45:00Z")), { rodou: false, motivo: "desligada" });
  // 21h de Brasília: o whatsapp-send recusaria (janela 8h–20h)
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T00:00:00Z")), { rodou: false, motivo: "fora da janela" });
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T10:59:00Z")), { rodou: false, motivo: "fora da janela" });
});
