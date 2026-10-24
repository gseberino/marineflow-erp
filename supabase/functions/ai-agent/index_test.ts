// Os comandos do resumo da manhã no turno do WhatsApp (secretário, Passo 2, 15/10/2026) — pelo texto da
// fonte (importar index.ts subiria o servidor). O que se protege: a camada roda DEPOIS da trava do
// comprovante e da confirmação (o "sim"/"1"/"não"/"2" nunca chega a ela como comando) e ANTES do atalho do
// PDF e do modelo; só com o formato novo; só do dono; a resposta sem modelo volta antes do turno do modelo.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { camadaDaAgenda, executarComandoDaAgenda, modoDaLeituraNoBanco } from "../_shared/agenda/executar.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const inicio = fonte.indexOf("async function handleWhatsAppTurn(");
const fim = fonte.indexOf("interface TurnoDoModelo");
const turno = fonte.slice(inicio, fim);

Deno.test("a camada do secretário fica depois da trava e da confirmação e antes do atalho do PDF e do modelo", () => {
  const camada = turno.indexOf("comandos do resumo da manhã (secretário");
  assert(camada > 0, "camada ausente");
  assert(turno.indexOf("textoDaTravaDoComprovante(") < camada, "depois da trava do comprovante");
  assert(turno.indexOf("const confirmation = parseConfirmationReply(text);") < camada, "depois da confirmação");
  assert(turno.indexOf("parseOptionReply(text, pendingOptions.length)") < camada, "depois da lista de opções");
  assert(camada < turno.indexOf("lerPedidoDePdf(effectiveText)"), "antes do atalho do PDF (o rascunho abre por ele)");
  assert(camada < turno.indexOf("return await turnoDoModeloNoWhatsApp("), "antes do modelo");
});

Deno.test("só com o formato novo, só se a lista de opções não consumiu o texto, e só do dono", () => {
  assertStringIncludes(turno, 'effectiveText === text && lerFormatoDoResumo(settings.resumo_formato) === "novo"');
  assertStringIncludes(turno, "dono && dono.id === appUser.id && dono.phone === phoneNormalized");
});

Deno.test("resposta sem modelo grava o turno e volta; a letra sozinha só troca o texto do turno", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  assertStringIncludes(bloco, 'if (r.tipo === "resposta") {');
  assertStringIncludes(bloco, 'role: "user", content: text, source: "whatsapp"');
  assertStringIncludes(bloco, "return jr({ ok: true, secretario: comandoDoResumo.comando });");
  assertStringIncludes(bloco, 'if (r.tipo === "pedido") effectiveText = r.texto;');
  // nada de aprovar/rejeitar pendência aqui
  assert(!bloco.includes("resolveWhatsAppConfirmation"), "a camada não mexe em pendência");
});

Deno.test("Passo 3: 'seguir' (não era comando) deixa o texto do turno como veio", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  // só o pedido troca o texto; nenhuma outra atribuição a effectiveText na camada
  assert((bloco.match(/effectiveText = /g) ?? []).length === 1, "uma única troca do texto do turno");
});

Deno.test("Passo 5: o *lote* abre a confirmação de sempre (pendência + sessão + pergunta ativa) e volta sem o modelo; o 'sim' é da camada de confirmação", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  const confirmar = bloco.indexOf('if (r.tipo === "confirmar") {');
  assert(confirmar > 0, "ramo confirmar ausente");
  // dentro da porta do dono e antes da resposta comum
  assert(bloco.indexOf("dono && dono.id === appUser.id && dono.phone === phoneNormalized") < confirmar, "só do dono");
  assert(confirmar < bloco.indexOf('if (r.tipo === "resposta") {'), "antes da resposta comum");
  const ramo = bloco.slice(confirmar, bloco.indexOf('if (r.tipo === "resposta") {'));
  assertStringIncludes(ramo, "abrirConfirmacaoDoSecretario(admin, {");
  assertStringIncludes(ramo, "ligada: conversaLigada");
  assertStringIncludes(ramo, "return jr({ ok: true, secretario: comandoDoResumo.comando });");
  // a camada abre, nunca executa: quem executa é o "sim" lá em cima
  assert(!ramo.includes("approveAndExecutePendingAction") && !ramo.includes("resolveWhatsAppConfirmation"), "o ramo não executa nada");
});

// Prospecção (SALES_COPY_PROMPT): o texto vai a CLIENTE, e a HBR atende barco E motorhome (dono,
// 22/10/2026: "seu motorhome", "sua lancha", "seu trailer"; nada de barquinho para motorhome).
Deno.test("prospecção: público inclui motorhome e a unidade vai pelo tipo", () => {
  const ini = fonte.indexOf("const SALES_COPY_PROMPT = `");
  const prompt = fonte.slice(ini, fonte.indexOf("`;", ini));
  assert(ini > 0, "SALES_COPY_PROMPT ausente");
  assertStringIncludes(prompt, "proprietários de embarcações e motorhomes, marinas e estaleiros");
  assertStringIncludes(prompt, '"sua lancha", "seu motorhome", "seu trailer"');
  assertStringIncludes(prompt, "🚐 para motorhome, trailer ou camper");
  assert(!prompt.includes("Vendas Náuticas") && !prompt.includes("valorização do barco"), "texto só náutico voltou");
});

// ─── Agenda de Produção, Fase 1 (P6, 24/10/2026): as palavras da agenda sem o modelo ─────────────────────────────
// O que se protege: no WhatsApp a camada roda DEPOIS do secretário (e, portanto, da trava, da confirmação e da lista de
// opções) e ANTES do atalho do PDF e do modelo; só do dono; o modo desligado não intercepta; a resposta grava o par no
// histórico e volta sem o modelo. No painel: só o administrador, só o texto novo do turno, antes do Max e do modelo.

const camadaWa = turno.indexOf("palavras da agenda de produção (Fase 1, P6");
const blocoWa = turno.slice(camadaWa, turno.indexOf("lerPedidoDePdf(effectiveText)"));

Deno.test("agenda (WhatsApp): depois do secretário, da confirmação e da lista de opções; antes do atalho do PDF e do modelo", () => {
  assert(camadaWa > 0, "camada da agenda ausente");
  assert(turno.indexOf("comandos do resumo da manhã (secretário") < camadaWa, "depois do secretário");
  assert(turno.indexOf("textoDaTravaDoComprovante(") < camadaWa, "depois da trava do comprovante");
  assert(turno.indexOf("const confirmation = parseConfirmationReply(text);") < camadaWa, "depois da confirmação");
  assert(turno.indexOf("parseOptionReply(text, pendingOptions.length)") < camadaWa, "depois da lista de opções");
  assert(camadaWa < turno.indexOf("lerPedidoDePdf(effectiveText)"), "antes do atalho do PDF");
  assert(camadaWa < turno.indexOf("return await turnoDoModeloNoWhatsApp("), "antes do modelo");
});

Deno.test("agenda (WhatsApp): só se nada acima trocou o texto, só do dono (id e telefone) e com o modo lido do banco", () => {
  assert(/effectiveText === text\r?\n\s*\? await camadaDaAgenda\(text, \{/.test(blocoWa), "só com o texto como veio");
  assertStringIncludes(blocoWa, "return !!dono && dono.id === appUser.id && dono.phone === phoneNormalized;");
  assertStringIncludes(blocoWa, "modo: () => modoDaLeituraNoBanco(admin),");
  assertStringIncludes(blocoWa, "executarComandoDaAgenda(admin, cmd, { autor: appUser.id, log: admin, canal: \"whatsapp\" })");
});

Deno.test("agenda (WhatsApp): responde sem o modelo — grava o par no histórico, responde e volta; nunca mexe em pendência", () => {
  assertStringIncludes(blocoWa, 'role: "user", content: text, source: "whatsapp"');
  assertStringIncludes(blocoWa, 'role: "assistant", content: doAgenda.texto, source: "whatsapp"');
  assertStringIncludes(blocoWa, "await queueWhatsAppReply(admin, phoneNormalized, doAgenda.texto);");
  assertStringIncludes(blocoWa, "return jr({ ok: true, agenda: doAgenda.comando.comando });");
  assert(!blocoWa.includes("resolveWhatsAppConfirmation") && !blocoWa.includes("approveAndExecutePendingAction"), "a camada não decide pendência");
  assert(!/effectiveText = /.test(blocoWa), "a camada da agenda não troca o texto do turno");
  assert(!blocoWa.includes("runAgentLoop") && !blocoWa.includes("turnoDoModeloNoWhatsApp"), "sem modelo");
});

const painelIni = fonte.indexOf("palavras da agenda de produção no painel (Fase 1, P6");
const painel = fonte.slice(painelIni, fonte.indexOf("// ---- Notas de memória ativas ----", painelIni));

Deno.test("agenda (painel): depois de resolver a sessão, antes das notas de memória, do Max e do modelo; só admin", () => {
  assert(painelIni > 0, "camada do painel ausente");
  assert(fonte.indexOf("const resolvedSessionId: string = sessionId!;") < painelIni, "depois da sessão");
  assert(painelIni < fonte.indexOf("// ---- Notas de memória ativas ----"), "antes das notas de memória");
  assert(painelIni < fonte.indexOf("await turnoDoPainelPeloMax("), "antes do Max");
  assert(painelIni < fonte.indexOf("await runAgentLoop({ ...loopParams"), "antes do modelo");
  assertStringIncludes(painel, 'ehDoDono: () => userRole === "admin",');
  assertStringIncludes(painel, "modo: () => modoDaLeituraNoBanco(admin),");
  // pelo JWT do dono (o banco usa o login); o log pelo service role
  assertStringIncludes(painel, 'executarComandoDaAgenda(sb, cmd, { autor: userId, log: admin, canal: "painel" })');
});

Deno.test("agenda (painel): lê só o texto NOVO do turno, grava no histórico e devolve a resposta sem o modelo", () => {
  assertStringIncludes(painel, "const m = alreadyPersistedCount > 0 ? newUserMsg : incoming[incoming.length - 1];");
  assertStringIncludes(painel, 'm && m.role === "user" && typeof m.content === "string" ? m.content : null');
  assertStringIncludes(painel, 'role: "assistant", content: doAgendaNoPainel.texto, source: "web"');
  assertStringIncludes(painel, 'return jr({ message: { role: "assistant", content: doAgendaNoPainel.texto }, tool_events: [], session_id: resolvedSessionId });');
  assert(!painel.includes("runAgentLoop") && !painel.includes("callClaude"), "sem modelo");
});

// O comportamento da camada como o index.ts a monta (WhatsApp): um banco de mentira com o dono, a chave e as RPCs.
const DONO = { id: "u-dono", phone: "5547999990000" };

function bancoDoTurno(p: { modo: string; donoId?: string }) {
  const rpcs: string[] = [];
  const admin = {
    from(tabela: string) {
      const q: Record<string, unknown> = {
        select: () => q, eq: () => q, not: () => q, order: () => q,
        limit: () => Promise.resolve({ data: tabela === "app_users" ? [{ id: p.donoId ?? DONO.id, phone_normalized: DONO.phone }] : [], error: null }),
        maybeSingle: () => Promise.resolve({ data: tabela === "agenda_config" ? { modo_leitura: p.modo } : null, error: null }),
      };
      return q;
    },
    rpc(nome: string) {
      rpcs.push(nome);
      return Promise.resolve({ data: { ok: true, texto: "Gravado. Agora:\n• Lenine: falta você dizer se tem peça a comprar." }, error: null });
    },
  };
  return { admin, rpcs };
}

async function turnoDaAgenda(texto: string, p: { modo: string; donoId?: string; appUserId?: string; phone?: string }) {
  const { admin, rpcs } = bancoDoTurno(p);
  const appUser = { id: p.appUserId ?? DONO.id };
  const phoneNormalized = p.phone ?? DONO.phone;
  const { donoDoWhatsApp } = await import("../_shared/whatsapp/dono.ts");
  const r = await camadaDaAgenda(texto, {
    ehDoDono: async () => {
      const dono = await donoDoWhatsApp(admin);
      return !!dono && dono.id === appUser.id && dono.phone === phoneNormalized;
    },
    modo: () => modoDaLeituraNoBanco(admin),
    executar: (cmd) => executarComandoDaAgenda(admin, cmd, { autor: appUser.id, log: admin, canal: "whatsapp" }),
  });
  return { r, rpcs };
}

Deno.test("agenda (WhatsApp): o comando do dono responde sem o modelo; quem não é o dono segue ao modelo; desligado não intercepta", async () => {
  const ok = await turnoDaAgenda("grava", { modo: "sombra" });
  assertEquals(ok.r?.texto, "Gravado. Agora:\n• Lenine: falta você dizer se tem peça a comprar.");
  assertEquals(ok.rpcs, ["agenda_rascunho_gravar"]);
  // outro admin (ou o telefone de outro): o texto segue ao modelo, nada é chamado
  for (const outro of [{ appUserId: "u-outro" }, { phone: "5547900000001" }]) {
    const r = await turnoDaAgenda("grava", { modo: "sombra", ...outro });
    assertEquals([r.r, r.rpcs], [null, []], JSON.stringify(outro));
  }
  const desligado = await turnoDaAgenda("agenda", { modo: "desligado" });
  assertEquals([desligado.r, desligado.rpcs], [null, []]);
  // conversa comum: nem dono nem chave são lidos
  const conversa = await turnoDaAgenda("como tá a semana?", { modo: "ligado" });
  assertEquals([conversa.r, conversa.rpcs], [null, []]);
});

// ─── Agenda de Produção, Fase 2 (P5, 24/10/2026): as palavras da conferência e do desfazer, sem o modelo ──────────────
// A camada é a mesma (index.ts não muda): *dia feito*, *dia não* + motivo, *choveu* e *desfaz* do dono respondem sem o
// modelo pela RPC deles; de outro número (ou outro login) seguem ao modelo; com a agenda desligada, não interceptam.
Deno.test("agenda Fase 2 (WhatsApp): *dia feito*, *dia não cliente*, *choveu* e *desfaz Nelson* do dono respondem sem o modelo", async () => {
  const casos: Array<[string, string]> = [
    ["dia feito", "agenda_conferir_dia"], ["Dia não cliente", "agenda_conferir_dia"], ["dia parcial imprevisto ontem", "agenda_conferir_dia"],
    ["choveu", "agenda_choveu"], ["desfaz Nelson", "agenda_desfazer_dito"], ["desfaz a semana", "agenda_desfazer_dito"],
    ["o que mudou?", "agenda_ver"], ["agenda pendências", "agenda_ver"], ["agenda plano", "agenda_ver"],
  ];
  for (const [texto, rpc] of casos) {
    const r = await turnoDaAgenda(texto, { modo: "ligado" });
    assert(r.r?.ok, texto);
    assertEquals(r.rpcs, [rpc], texto);
  }
  // de outro número (ou outro login): segue ao modelo, nada é chamado
  for (const outro of [{ appUserId: "u-outro" }, { phone: "5547900000001" }]) {
    const r = await turnoDaAgenda("dia feito", { modo: "ligado", ...outro });
    assertEquals([r.r, r.rpcs], [null, []], JSON.stringify(outro));
  }
  // agenda desligada: o *dia feito* vai ao modelo como conversa
  const desligado = await turnoDaAgenda("dia feito", { modo: "desligado" });
  assertEquals([desligado.r, desligado.rpcs], [null, []]);
  // "desfaz B" é do secretário (a letra do dia), não da agenda
  const letra = await turnoDaAgenda("desfaz B", { modo: "ligado" });
  assertEquals([letra.r, letra.rpcs], [null, []]);
});
