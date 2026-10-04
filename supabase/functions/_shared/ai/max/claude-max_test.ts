import { assert, assertEquals, assertMatch, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ADENDO_DO_MAX,
  linhaDoJob,
  modeloDoMax,
  novoTokenDoMcp,
  provedorDoTurno,
  reservaLigada,
  sha256Hex,
  textoDoSistema,
  TIPO_DO_JOB,
  transcreverConversa,
} from "./claude-max.ts";
import type { ClaudeMessage } from "../anthropic.ts";

Deno.test("provedor: OpenRouter por padrão; Max só com a chave E só para o admin (uso individual da assinatura)", () => {
  assertEquals(provedorDoTurno({}, "admin"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "openrouter" }, "admin"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: " Claude_Max " }, "admin"), "claude_max");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "claude_max" }, "technician"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "claude_max" }, "financial"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "max" }, "admin"), "openrouter");
});

Deno.test("modelo e reserva", () => {
  assertEquals(modeloDoMax({}), "sonnet");
  assertEquals(modeloDoMax({ ai_whatsapp_max_modelo: "opus" }), "opus");
  assertEquals(modeloDoMax({ ai_whatsapp_max_modelo: "gpt-5" }), "sonnet");
  assertEquals(reservaLigada({}), true);
  assertEquals(reservaLigada({ ai_whatsapp_max_reserva: "off" }), false);
});

const conversa: ClaudeMessage[] = [
  { role: "user", content: [{ type: "text", text: "quanto deu o ORÇ-00110?" }] },
  { role: "assistant", content: [{ type: "text", text: "Vou ver." }, { type: "tool_use", id: "t1", name: "get_service_order", input: { numero: "ORÇ-00110" } }] },
  { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: JSON.stringify({ total: 4321.09 }) }] },
  { role: "assistant", content: [{ type: "text", text: "Deu R$ 4.321,09." }] },
  { role: "user", content: [{ type: "text", text: "manda o PDF pro cliente" }] },
] as ClaudeMessage[];

Deno.test("transcrição: quem falou, ferramentas, resultados e a mensagem atual separada", () => {
  const t = transcreverConversa(conversa);
  assertStringIncludes(t, "Usuário: quanto deu o ORÇ-00110?");
  assertStringIncludes(t, "Assistente: Vou ver.");
  assertStringIncludes(t, '[ferramenta get_service_order] {"numero":"ORÇ-00110"}');
  assertStringIncludes(t, '[resultado] {"total":4321.09}');
  assertMatch(t, /<mensagem>\nmanda o PDF pro cliente\n<\/mensagem>$/);
  assert(!t.slice(0, t.indexOf("<mensagem>")).includes("manda o PDF"), "a mensagem atual não entra no histórico");
});

Deno.test("transcrição: só a mensagem atual quando não há histórico; resultado enorme é cortado", () => {
  assertEquals(
    transcreverConversa([{ role: "user", content: [{ type: "text", text: "oi" }] }] as ClaudeMessage[]),
    "\nMensagem atual do usuário — responda a ela:\n<mensagem>\noi\n</mensagem>",
  );
  const grande = transcreverConversa([
    { role: "user", content: [{ type: "tool_result", tool_use_id: "x", content: "a".repeat(5000) }] },
    { role: "user", content: [{ type: "text", text: "e aí?" }] },
  ] as ClaudeMessage[]);
  assertStringIncludes(grande, "… [cortado]");
  assert(grande.length < 2000);
});

Deno.test("sistema leva o adendo das ferramentas MCP", () => {
  const s = textoDoSistema([{ type: "text", text: "ESTÁVEL" }, { type: "text", text: "VOLÁTIL" }]);
  assert(s.startsWith("ESTÁVEL\n\nVOLÁTIL"));
  assert(s.endsWith(ADENDO_DO_MAX));
  assertStringIncludes(ADENDO_DO_MAX, "mcp__erp__");
});

Deno.test("token de uso único e hash", async () => {
  const a = novoTokenDoMcp();
  const b = novoTokenDoMcp();
  assert(a !== b);
  assertMatch(a, /^[A-Za-z0-9_-]{43}$/);
  assertEquals(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

Deno.test("linha do job: perfil erp_agent, token só como hash no metadata, prazo e prioridade do WhatsApp", () => {
  const linha = linhaDoJob(
    {
      sessionId: "s1",
      appUserId: "u1",
      phone: "5547999990000",
      modelo: "sonnet",
      system: [{ type: "text", text: "SISTEMA" }],
      messages: conversa,
      ferramentas: {
        tools: [{ name: "get_service_order" }, { name: "search_clients" }] as never,
        toolsByName: {},
        alcancaveisPelaRede: { send_document_pdf_to_self: {} as never },
      },
      texto: "manda o PDF pro cliente",
    },
    "TOKEN",
    "HASH",
    Date.parse("2026-10-03T20:00:00Z"),
  ) as Record<string, any>;
  assertEquals(linha.task_profile, "erp_agent");
  assertEquals(linha.provider, "claude-local");
  assertEquals(linha.requested_by, "u1");
  assertEquals(linha.response_format, "text");
  assertEquals(linha.max_attempts, 1);
  assertEquals(linha.priority, 50);
  assertEquals(linha.deadline_at, "2026-10-03T20:01:15.000Z");
  assertEquals(linha.input.ferramentas, { visiveis: ["get_service_order", "search_clients"], rede: ["send_document_pdf_to_self"] });
  assertEquals(linha.input.mcp_token, "TOKEN");
  assertEquals(linha.input.texto, "manda o PDF pro cliente");
  assertStringIncludes(linha.input.system, "SISTEMA");
  assertEquals(linha.metadata, { tipo: TIPO_DO_JOB, versao: 1, effort: "low", session_id: "s1", phone: "5547999990000", user_id: "u1", mcp_token_sha256: "HASH" });
  assert(!JSON.stringify(linha.metadata).includes("TOKEN"), "o token em claro nunca vai ao metadata");
  assertStringIncludes(linha.prompt, "<mensagem>\nmanda o PDF pro cliente");
});
