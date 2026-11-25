import { assert, assertEquals, assertMatch, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ADENDO_DO_MAX,
  assinanteDoMax,
  CHAVE_DOS_ASSINANTES,
  desfechoDoPainel,
  idDoAssinante,
  linhaDoJob,
  modeloDoMax,
  naoAssinanteSemReserva,
  novoTokenDoMcp,
  provedorDoTurno,
  reservaLigada,
  sha256Hex,
  textoDoSistema,
  TIPO_DO_JOB,
  TIPO_DO_PAINEL,
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

Deno.test("painel: chave e modelo próprios, também só para o admin; a chave do WhatsApp não liga o painel", () => {
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "claude_max" }, "admin", "panel"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_painel: "claude_max" }, "admin", "panel"), "claude_max");
  assertEquals(provedorDoTurno({ ai_provedor_painel: "claude_max" }, "admin"), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_painel: "claude_max" }, "financial", "panel"), "openrouter");
  assertEquals(modeloDoMax({ ai_whatsapp_max_modelo: "opus" }, "panel"), "sonnet");
  assertEquals(modeloDoMax({ ai_painel_max_modelo: "haiku" }, "panel"), "haiku");
});

Deno.test("linha do job do painel: tipo próprio, sem telefone, prazo curto e teto que cabe na edge", () => {
  const linha = linhaDoJob(
    {
      sessionId: "s2",
      appUserId: "u1",
      phone: "",
      modelo: "opus",
      system: [{ type: "text", text: "SISTEMA" }],
      messages: conversa,
      ferramentas: { tools: [{ name: "get_financial_dre" }] as never, toolsByName: {}, alcancaveisPelaRede: {} },
      texto: "manda o PDF pro cliente",
      canal: "panel",
    },
    "TOKEN",
    "HASH",
    Date.parse("2026-10-03T20:00:00Z"),
  ) as Record<string, any>;
  assertEquals(linha.metadata, { tipo: TIPO_DO_PAINEL, versao: 1, effort: "medium", session_id: "s2", user_id: "u1", mcp_token_sha256: "HASH" });
  assertEquals(linha.input.canal, "panel");
  assertEquals(linha.model, "opus");
  assertEquals(linha.priority, 60);
  assertEquals(linha.timeout_seconds, 110);
  assertEquals(linha.deadline_at, "2026-10-03T20:00:20.000Z");
  assertStringIncludes(linha.prompt, "Conversa recente no chat do app");
});

Deno.test("desfecho do painel: pronto, reserva, tarde ou esperar", () => {
  const lim = { pegarMs: 20_000, esperarMs: 110_000 };
  assertEquals(desfechoDoPainel(null, 1_000, lim), { tipo: "reserva", motivo: "job sumiu" });
  assertEquals(desfechoDoPainel({ status: "completed" }, 500, lim), { tipo: "pronto" });
  assertEquals(desfechoDoPainel({ status: "failed", error_code: "rate_limited" }, 5_000, lim), { tipo: "reserva", motivo: "rate_limited" });
  assertEquals(desfechoDoPainel({ status: "cancelled" }, 5_000, lim), { tipo: "reserva", motivo: "cancelled" });
  assertEquals(desfechoDoPainel({ status: "pending" }, 19_000, lim), { tipo: "esperar" });
  assertEquals(desfechoDoPainel({ status: "pending" }, 21_000, lim).tipo, "reserva");
  // Pego pelo gateway: espera até o teto, mesmo passando do prazo de pegar.
  assertEquals(desfechoDoPainel({ status: "processing", started_at: "x" }, 60_000, lim), { tipo: "esperar" });
  assertEquals(desfechoDoPainel({ status: "processing", started_at: "x" }, 111_000, lim), { tipo: "tarde" });
});

// ─── Pacote 1, S5 (24/11/2026): a assinatura Claude é da PESSOA do assinante, e não do cargo ─────────────────────────
// O que se protege: com a chave ai_max_assinantes, só quem está na lista vai pelo Max, seja qual for o cargo (um
// administrador reativado não entra sozinho); a chave vazia não libera ninguém; sem a chave vale a regra antiga, para o
// deploy poder sair antes da migration; e quem não é assinante, com a reserva desligada, não tem para onde ir.
// Os ids são fictícios: nenhum id de pessoa mora no código nem nos testes.
const DONO = "11111111-1111-4111-8111-111111111111";
const OUTRO_ADMIN = "22222222-2222-4222-8222-222222222222";
const TECNICO = "33333333-3333-4333-8333-333333333333";
const noMax = (lista: string) => ({ ai_provedor_whatsapp: "claude_max", ai_provedor_painel: "claude_max", [CHAVE_DOS_ASSINANTES]: lista });

Deno.test("S5: com a chave, vale a pessoa: o admin fora da lista vai pelo OpenRouter e quem está na lista vai pelo Max", () => {
  assertEquals(CHAVE_DOS_ASSINANTES, "ai_max_assinantes");
  const s = noMax(DONO);
  assertEquals(provedorDoTurno(s, "admin", "whatsapp", DONO), "claude_max");
  assertEquals(provedorDoTurno(s, "admin", "panel", DONO), "claude_max");
  // o administrador que não é o assinante (o inativo que foi reativado) não entra pelo cargo
  assertEquals(provedorDoTurno(s, "admin", "whatsapp", OUTRO_ADMIN), "openrouter");
  assertEquals(provedorDoTurno(s, "admin", "panel", OUTRO_ADMIN), "openrouter");
  assertEquals(assinanteDoMax(s, OUTRO_ADMIN, "admin"), false);
  // pessoa, não cargo: quem está na lista passa com qualquer cargo
  assertEquals(assinanteDoMax(noMax(`${DONO},${TECNICO}`), TECNICO, "technician"), true);
  assertEquals(provedorDoTurno(noMax(`${DONO},${TECNICO}`), "technician", "whatsapp", TECNICO), "claude_max");
  // a lista não liga o Max sozinha: a chave do canal continua mandando
  assertEquals(provedorDoTurno({ [CHAVE_DOS_ASSINANTES]: DONO }, "admin", "whatsapp", DONO), "openrouter");
  assertEquals(provedorDoTurno({ ai_provedor_whatsapp: "claude_max", [CHAVE_DOS_ASSINANTES]: DONO }, "admin", "panel", DONO), "openrouter");
});

Deno.test("S5: chave presente e vazia = ninguém; sem id de pessoa, ninguém", () => {
  for (const vazia of ["", "   ", ",", " , ;\n"]) {
    assertEquals(assinanteDoMax(noMax(vazia), DONO, "admin"), false, JSON.stringify(vazia));
    assertEquals(provedorDoTurno(noMax(vazia), "admin", "whatsapp", DONO), "openrouter", JSON.stringify(vazia));
  }
  // quem chama sem o id (o jeito antigo de chamar) não passa quando a chave existe
  assertEquals(provedorDoTurno(noMax(DONO), "admin"), "openrouter");
  assertEquals(provedorDoTurno(noMax(DONO), "admin", "panel"), "openrouter");
  assertEquals(assinanteDoMax(noMax(DONO), "", "admin"), false);
  assertEquals(assinanteDoMax(noMax(DONO), "   ", "admin"), false);
  // o que não tem forma de id não é pessoa: não casa com id vazio nem com texto solto
  assertEquals(assinanteDoMax(noMax("admin"), "admin", "admin"), false);
  assertEquals(assinanteDoMax(noMax("*"), DONO, "admin"), false);
  assertEquals(assinanteDoMax(noMax(DONO.slice(0, 8)), DONO, "admin"), false);
});

Deno.test("S5: espaço, maiúscula, quebra de linha e ponto e vírgula na lista são tolerados", () => {
  assertEquals(assinanteDoMax(noMax(`  ${DONO.toUpperCase()}  `), DONO, "admin"), true);
  assertEquals(assinanteDoMax(noMax(DONO), ` ${DONO.toUpperCase()} `, "admin"), true);
  assertEquals(assinanteDoMax(noMax(`${OUTRO_ADMIN} ,\n ${DONO}`), DONO, "admin"), true);
  assertEquals(assinanteDoMax(noMax(`${OUTRO_ADMIN};${DONO}`), DONO, "admin"), true);
  assertEquals(assinanteDoMax(noMax(`lixo, ${DONO}`), DONO, "admin"), true);
  assertEquals(assinanteDoMax(noMax(`lixo, ${DONO}`), TECNICO, "admin"), false);
});

Deno.test("S5: sem a chave vale a regra antiga (cargo admin), com aviso no log uma vez só", async () => {
  // instância nova do módulo: o aviso sai uma vez por instância, e os testes de cima já o gastaram na instância comum
  const novo = await import(new URL("./claude-max.ts?s5-aviso-da-chave", import.meta.url).href) as typeof import("./claude-max.ts");
  const avisos: string[] = [];
  const original = console.warn;
  console.warn = (...a: unknown[]) => { avisos.push(a.map(String).join(" ")); };
  try {
    const s = { ai_provedor_whatsapp: "claude_max" };
    assertEquals(novo.assinanteDoMax(s, DONO, "admin"), true);
    assertEquals(novo.assinanteDoMax(s, OUTRO_ADMIN, "admin"), true, "regra antiga: qualquer admin");
    assertEquals(novo.assinanteDoMax(s, "", "admin"), true, "regra antiga: não olha a pessoa");
    assertEquals(novo.assinanteDoMax(s, TECNICO, "technician"), false);
    assertEquals(novo.provedorDoTurno(s, "admin", "whatsapp", DONO), "claude_max");
    assertEquals(novo.provedorDoTurno(s, "financial", "whatsapp", TECNICO), "openrouter");
    assertEquals(avisos.length, 1, "um aviso por instância, não um por chamada");
    assertStringIncludes(avisos[0], "ai_max_assinantes não existe");
    assertStringIncludes(avisos[0], "regra antiga (cargo admin)");
    assertStringIncludes(avisos[0], "20270301130000_assinatura_max_por_pessoa");
    // com a chave presente não há aviso (nem quando ela está vazia)
    assertEquals(novo.assinanteDoMax({ ...s, ai_max_assinantes: "" }, DONO, "admin"), false);
    assertEquals(avisos.length, 1);
  } finally {
    console.warn = original;
  }
  // quando o canal não pede o Max, ninguém consulta a lista: nem aviso há
  const semPedido = await import(new URL("./claude-max.ts?s5-sem-pedido", import.meta.url).href) as typeof import("./claude-max.ts");
  const outros: string[] = [];
  console.warn = (...a: unknown[]) => { outros.push(a.map(String).join(" ")); };
  try {
    assertEquals(semPedido.provedorDoTurno({}, "admin", "whatsapp", DONO), "openrouter");
    assertEquals(semPedido.naoAssinanteSemReserva({ ai_whatsapp_max_reserva: "off" }, "technician", "whatsapp", TECNICO), false);
    assertEquals(outros.length, 0);
  } finally {
    console.warn = original;
  }
});

Deno.test("S5: idDoAssinante devolve o id só quando a lista tem exatamente um", () => {
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: DONO }), DONO);
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: `  ${DONO.toUpperCase()} ,` }), DONO, "normalizado: minúscula e sem espaço");
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: `${DONO}, ${DONO.toUpperCase()}` }), DONO, "o mesmo id repetido é um só");
  // sem assinante definido não há em nome de quem pedir: o pedido automático não entra na fila
  assertEquals(idDoAssinante({}), null, "chave ausente: do cargo não sai um id");
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: "" }), null);
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: "lixo" }), null);
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: `${DONO},${OUTRO_ADMIN}` }), null, "dois assinantes: não se escolhe um");
  // o que não tem forma de id não é pessoa e não conta
  assertEquals(idDoAssinante({ [CHAVE_DOS_ASSINANTES]: `lixo, ${DONO}` }), DONO);
});

Deno.test("S5: quem não é assinante, com a reserva desligada, não tem para onde ir (nos dois canais)", () => {
  const semReserva = { ...noMax(DONO), ai_whatsapp_max_reserva: "off" };
  assertEquals(naoAssinanteSemReserva(semReserva, "admin", "whatsapp", OUTRO_ADMIN), true);
  assertEquals(naoAssinanteSemReserva(semReserva, "technician", "whatsapp", TECNICO), true);
  assertEquals(naoAssinanteSemReserva(semReserva, "financial", "panel", TECNICO), true);
  assertEquals(naoAssinanteSemReserva(semReserva, "admin", "whatsapp", ""), true, "sem id não é assinante");
  // o assinante nunca é barrado aqui: se o Max dele falhar, quem fala é a causa do C2
  assertEquals(naoAssinanteSemReserva(semReserva, "admin", "whatsapp", DONO), false);
  assertEquals(naoAssinanteSemReserva(semReserva, "admin", "panel", DONO), false);
  // com a reserva ligada fica como sempre: a pessoa segue pelo OpenRouter
  assertEquals(naoAssinanteSemReserva(noMax(DONO), "technician", "whatsapp", TECNICO), false);
  assertEquals(naoAssinanteSemReserva({ ...noMax(DONO), ai_whatsapp_max_reserva: "on" }, "admin", "panel", OUTRO_ADMIN), false);
  // o canal fora do Claude: todos vão pelo OpenRouter por escolha do dono, e a chave da reserva não diz nada
  const waForaDoMax = { ai_provedor_painel: "claude_max", ai_whatsapp_max_reserva: "off", [CHAVE_DOS_ASSINANTES]: DONO };
  assertEquals(naoAssinanteSemReserva(waForaDoMax, "technician", "whatsapp", TECNICO), false);
  assertEquals(naoAssinanteSemReserva(waForaDoMax, "technician", "panel", TECNICO), true, "cada canal pela chave dele");
  // lista vazia e sem reserva: nem o dono passa (a chave vazia é "ninguém")
  assertEquals(naoAssinanteSemReserva({ ...noMax(""), ai_whatsapp_max_reserva: "off" }, "admin", "whatsapp", DONO), true);
});

Deno.test("S5: sem a chave e sem reserva, a regra antiga decide quem fica de fora (o cargo)", async () => {
  const novo = await import(new URL("./claude-max.ts?s5-regra-antiga-sem-reserva", import.meta.url).href) as typeof import("./claude-max.ts");
  const original = console.warn;
  console.warn = () => {};
  try {
    const s = { ai_provedor_whatsapp: "claude_max", ai_whatsapp_max_reserva: "off" };
    assertEquals(novo.naoAssinanteSemReserva(s, "admin", "whatsapp", DONO), false);
    assertEquals(novo.naoAssinanteSemReserva(s, "technician", "whatsapp", TECNICO), true);
    assertEquals(novo.idDoAssinante(s), null);
  } finally {
    console.warn = original;
  }
});
