import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isWorthAnalyzing, normalizeProposal, formatConversation, CONFIDENCE_FLOOR, buildDateTable,
  isDetectorAutonomous, shouldAutoCreate, AUTONOMY_MIN_SAMPLE, loopKeyFromTitle,
  DETECTOR_KINDS, detectorFlagKey, enabledDetectors,
  type ConversationMessage, type RawProposal,
} from "./inbox-detector.ts";

Deno.test("isDetectorAutonomous: exige amostra mínima E taxa alta", () => {
  // amostra insuficiente, mesmo com 100% de aceite
  assertEquals(isDetectorAutonomous({ accepted: 5, dismissed: 0 }), false);
  // amostra ok mas taxa baixa (7/10 = 70%)
  assertEquals(isDetectorAutonomous({ accepted: 7, dismissed: 3 }), false);
  // amostra ok e taxa no limite (8/10 = 80%)
  assertEquals(isDetectorAutonomous({ accepted: 8, dismissed: 2 }), true);
  assertEquals(isDetectorAutonomous(undefined), false);
  assertEquals(AUTONOMY_MIN_SAMPLE, 8);
});

Deno.test("shouldAutoCreate: só cria sozinho com detector provado, confiança alta e flag ligada", () => {
  const provado = { promise: { accepted: 9, dismissed: 1 } };
  const alta = { detector: "promise" as const, confidence: 0.9 };
  const media = { detector: "promise" as const, confidence: 0.7 };

  assertEquals(shouldAutoCreate(alta, provado, true), true);
  // confiança abaixo do piso de auto-criação, mesmo com detector provado
  assertEquals(shouldAutoCreate(media, provado, true), false);
  // flag global desligada trava tudo
  assertEquals(shouldAutoCreate(alta, provado, false), false);
  // detector sem histórico nunca cria sozinho
  assertEquals(shouldAutoCreate({ detector: "followup", confidence: 0.99 }, provado, true), false);
  // detector com histórico ruim nunca cria sozinho
  assertEquals(shouldAutoCreate(alta, { promise: { accepted: 4, dismissed: 6 } }, true), false);
});

Deno.test("buildDateTable: converte dia relativo na data certa (domingo 26/07/2026)", () => {
  // 2026-07-26T15:00Z = domingo 26/07 12:00 BRT
  const t = buildDateTable(new Date("2026-07-26T15:00:00Z"));
  assertEquals(t.includes("hoje = 2026-07-26 (domingo)"), true);
  assertEquals(t.includes("amanhã = 2026-07-27 (segunda-feira)"), true);
  assertEquals(t.includes("segunda-feira (a próxima) = 2026-07-27"), true);
  assertEquals(t.includes("sexta-feira (a próxima) = 2026-07-31"), true);
  // dia citado que é HOJE aponta para a próxima semana (nunca para o passado)
  assertEquals(t.includes("domingo (a próxima) = 2026-08-02"), true);
});

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

Deno.test("loopKeyFromTitle: títulos equivalentes colidem na mesma chave", () => {
  // Acento, caixa, pontuação e palavra vazia não podem gerar um segundo fio.
  const a = loopKeyFromTitle("Acompanhar a entrega dos materiais da OS-1042");
  const b = loopKeyFromTitle("acompanhar entrega de materiais da OS 1042");
  assertEquals(a, b);
  // Note o "os" ausente: a sigla OS cai junto com o artigo "os" da lista de palavras
  // vazias. Quem discrimina uma OS da outra é o NÚMERO, que permanece.
  assertEquals(a, "conv:acompanhar-entrega-materiais-1042");
});

Deno.test("loopKeyFromTitle: OS diferentes continuam sendo fios diferentes", () => {
  // Consequência do teste acima: se o número não sobrevivesse, toda OS viraria o mesmo fio.
  assertEquals(
    loopKeyFromTitle("Acompanhar entrega dos materiais da OS-1042") ===
    loopKeyFromTitle("Acompanhar entrega dos materiais da OS-1043"),
    false,
  );
});

Deno.test("loopKeyFromTitle: assuntos diferentes NÃO colidem", () => {
  const entrega = loopKeyFromTitle("Acompanhar entrega dos materiais da OS-1042");
  const orcamento = loopKeyFromTitle("Enviar orçamento do motor para o Vanderlei");
  assertEquals(entrega === orcamento, false);
});

Deno.test("loopKeyFromTitle: título vazio não vira chave coringa", () => {
  // Se virasse "conv:" para qualquer entrada, dois fios sem título se fundiriam.
  assertEquals(loopKeyFromTitle(""), "conv:");
  assertEquals(loopKeyFromTitle("!!!"), "conv:");
});

Deno.test("enabledDetectors: sem linha em app_settings, todo detector nasce ligado", () => {
  // O padrão do repo é ausência = ligado (mesmo de task_rule_<id>_enabled). Se isto
  // invertesse, um banco novo subiria com a caixa de entrada muda e ninguém notaria.
  const ligados = enabledDetectors({});
  assertEquals(ligados.size, DETECTOR_KINDS.length);
  for (const d of DETECTOR_KINDS) assertEquals(ligados.has(d), true);
});

Deno.test("enabledDetectors: 'false' desliga só o detector nomeado", () => {
  const ligados = enabledDetectors({ [detectorFlagKey("promise")]: "false" });
  assertEquals(ligados.has("promise"), false);
  // os outros três seguem intactos — desligar um não pode calar a caixa inteira
  assertEquals(ligados.has("client_request"), true);
  assertEquals(ligados.has("followup"), true);
  assertEquals(ligados.has("third_party_deadline"), true);
});

Deno.test("enabledDetectors: valor vazio ou lixo não desliga por acidente", () => {
  // Só o literal "false" desliga. Um upsert que grave "" (ou "0", ou "não") não pode
  // apagar um detector em silêncio — o efeito de desligar tem que ser deliberado.
  assertEquals(enabledDetectors({ [detectorFlagKey("promise")]: "" }).has("promise"), true);
  assertEquals(enabledDetectors({ [detectorFlagKey("promise")]: "true" }).has("promise"), true);
  assertEquals(enabledDetectors({ [detectorFlagKey("promise")]: "0" }).has("promise"), false);
});

Deno.test("detectorFlagKey espelha o padrão de nome do motor de regras", () => {
  // task_rule_<id>_enabled : agenda_detector_<tipo>_enabled — mesmo formato, para quem
  // já conhece um mecanismo adivinhar o outro.
  assertEquals(detectorFlagKey("promise"), "agenda_detector_promise_enabled");
  assertEquals(detectorFlagKey("client_request"), "agenda_detector_client_request_enabled");
});

Deno.test("CONFIDENCE_FLOOR cobre exatamente os detectores declarados", () => {
  // normalizeProposal usa a presença no CONFIDENCE_FLOOR como whitelist. Se um detector
  // entrasse em DETECTOR_KINDS sem limiar, ele seria rejeitado como "desconhecido" e a
  // flag dele existiria sem nunca ter efeito.
  assertEquals(DETECTOR_KINDS.length, Object.keys(CONFIDENCE_FLOOR).length);
  for (const d of DETECTOR_KINDS) assertEquals(typeof CONFIDENCE_FLOOR[d], "number");
});
