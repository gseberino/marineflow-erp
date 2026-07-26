import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isWorthAnalyzing, normalizeProposal, formatConversation, CONFIDENCE_FLOOR,
  type ConversationMessage, type RawProposal,
} from "./inbox-detector.ts";

const NOW = new Date("2026-07-26T15:00:00Z"); // 12:00 BRT

const msgs: ConversationMessage[] = [
  { id: "m1", direction: "inbound", body: "Bom dia! Consegue olhar o motor da minha lancha essa semana?", occurred_at: "2026-07-26T13:00:00Z" },
  { id: "m2", direction: "outbound", body: "Bom dia Carlos! Vou te mandar o orçamento amanhã de manhã.", occurred_at: "2026-07-26T13:05:00Z" },
];

Deno.test("isWorthAnalyzing: ignora conversa vazia, curta ou só de mídia", () => {
  assertEquals(isWorthAnalyzing([]), false);
  assertEquals(isWorthAnalyzing([{ id: "a", direction: "inbound", body: "ok", occurred_at: NOW.toISOString() }]), false);
  assertEquals(isWorthAnalyzing([{ id: "a", direction: "inbound", body: "[audio]", occurred_at: NOW.toISOString() }]), false);
  assertEquals(isWorthAnalyzing([{ id: "a", direction: "inbound", body: null, occurred_at: NOW.toISOString() }]), false);
  assertEquals(isWorthAnalyzing(msgs), true);
});

Deno.test("normalizeProposal: aceita proposta com evidência literal presente na conversa", () => {
  const raw: RawProposal = {
    title: "Enviar orçamento do motor para o Carlos",
    evidence: "Vou te mandar o orçamento amanhã de manhã",
    detector: "promise",
    confidence: 0.9,
    due_date: "2026-07-27",
    evidence_message_index: 1,
  };
  const p = normalizeProposal(raw, msgs, NOW)!;
  assertEquals(p.title, "Enviar orçamento do motor para o Carlos");
  assertEquals(p.source_message_id, "m2");
  assertEquals(p.kind, "task");
  assertEquals(p.suggested_due_at, "2026-07-27T11:00:00.000Z"); // 08:00 BRT
  assertEquals(p.evidence_at, "2026-07-26T13:05:00Z");
});

Deno.test("normalizeProposal: REJEITA evidência inventada (anti-alucinação)", () => {
  const raw: RawProposal = {
    title: "Comprar hélice nova",
    evidence: "preciso de uma hélice nova urgente para o barco",
    detector: "client_request",
    confidence: 0.95,
  };
  assertEquals(normalizeProposal(raw, msgs, NOW), null);
});

Deno.test("normalizeProposal: REJEITA abaixo do limiar do detector", () => {
  const base: RawProposal = {
    title: "Ligar para o Carlos",
    evidence: "Consegue olhar o motor da minha lancha essa semana?",
    detector: "followup",
    confidence: 0.7, // followup exige 0.75
  };
  assertEquals(normalizeProposal(base, msgs, NOW), null);
  assertEquals(normalizeProposal({ ...base, confidence: 0.8 }, msgs, NOW) !== null, true);
  // client_request exige 0.65
  assertEquals(normalizeProposal({ ...base, detector: "client_request", confidence: 0.66 }, msgs, NOW) !== null, true);
});

Deno.test("normalizeProposal: REJEITA título vazio/curto e evidência curta", () => {
  const ok: RawProposal = { title: "Enviar orçamento", evidence: "Vou te mandar o orçamento amanhã", detector: "promise", confidence: 0.9 };
  assertEquals(normalizeProposal({ ...ok, title: "ok" }, msgs, NOW), null);
  assertEquals(normalizeProposal({ ...ok, evidence: "amanhã" }, msgs, NOW), null);
});

Deno.test("normalizeProposal: hora explícita vira appointment; data no passado é descartada", () => {
  const comHora = normalizeProposal({
    title: "Visita técnica na marina",
    evidence: "Consegue olhar o motor da minha lancha essa semana?",
    detector: "client_request", confidence: 0.9,
    due_date: "2026-07-28", time: "14:00",
  }, msgs, NOW)!;
  assertEquals(comHora.kind, "appointment");
  assertEquals(comHora.suggested_start_at, "2026-07-28T17:00:00.000Z"); // 14:00 BRT

  const passado = normalizeProposal({
    title: "Enviar orçamento do motor",
    evidence: "Vou te mandar o orçamento amanhã de manhã",
    detector: "promise", confidence: 0.9,
    due_date: "2020-01-01",
  }, msgs, NOW)!;
  assertEquals(passado.suggested_due_at, null); // data ignorada, tarefa mantida
  assertEquals(passado.kind, "task");
});

Deno.test("normalizeProposal: detector desconhecido é rejeitado", () => {
  const raw = {
    title: "Fazer alguma coisa", evidence: "Vou te mandar o orçamento amanhã",
    detector: "chute" as any, confidence: 0.99,
  };
  assertEquals(normalizeProposal(raw, msgs, NOW), null);
});

Deno.test("formatConversation: indexa e rotula quem falou", () => {
  const out = formatConversation(msgs);
  assertEquals(out.includes("[0]"), true);
  assertEquals(out.includes("CLIENTE:"), true);
  assertEquals(out.includes("[1]"), true);
  assertEquals(out.includes("HBR:"), true);
});

Deno.test("CONFIDENCE_FLOOR: followup é o mais exigente", () => {
  assertEquals(CONFIDENCE_FLOOR.followup > CONFIDENCE_FLOOR.promise, true);
  assertEquals(CONFIDENCE_FLOOR.third_party_deadline > CONFIDENCE_FLOOR.client_request, true);
});
