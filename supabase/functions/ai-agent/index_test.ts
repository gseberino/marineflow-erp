// Os comandos do resumo da manhã no turno do WhatsApp (secretário, Passo 2, 15/10/2026) — pelo texto da
// fonte (importar index.ts subiria o servidor). O que se protege: a camada roda DEPOIS da trava do
// comprovante e da confirmação (o "sim"/"1"/"não"/"2" nunca chega a ela como comando) e ANTES do atalho do
// PDF e do modelo; só com o formato novo; só do dono; a resposta sem modelo volta antes do turno do modelo.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { camadaDaAgenda, executarComandoDaAgenda, modoDaLeituraNoBanco, modosDaAgendaNoBanco } from "../_shared/agenda/executar.ts";
import { rotaDaResposta } from "../_shared/ai/rota-da-mensagem.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const inicio = fonte.indexOf("async function handleWhatsAppTurn(");
const fim = fonte.indexOf("interface TurnoDoModelo");
const turno = fonte.slice(inicio, fim);

Deno.test("a camada do secretário fica depois da trava e da confirmação e antes do atalho do PDF e do modelo", () => {
  const camada = turno.indexOf("comandos do resumo da manhã (secretário");
  assert(camada > 0, "camada ausente");
  assert(turno.indexOf("textoDaTravaDoComprovante(") < camada, "depois da trava do comprovante");
  assert(turno.indexOf("const confirmation = parseConfirmationReply(text") < camada, "depois da confirmação");
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
  assert(turno.indexOf("const confirmation = parseConfirmationReply(text") < camadaWa, "depois da confirmação");
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

function bancoDoTurno(p: { modo: string; donoId?: string; fase2?: string }) {
  const rpcs: string[] = [];
  const admin = {
    from(tabela: string) {
      const q: Record<string, unknown> = {
        select: () => q, eq: () => q, not: () => q, order: () => q,
        limit: () => Promise.resolve({ data: tabela === "app_users" ? [{ id: p.donoId ?? DONO.id, phone_normalized: DONO.phone }] : [], error: null }),
        maybeSingle: () => Promise.resolve({
          data: tabela === "agenda_config" ? { modo_leitura: p.modo, modo_proposta: p.fase2 ?? "desligado", modo_vigia: "desligado" } : null,
          error: null,
        }),
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

async function turnoDaAgenda(texto: string, p: { modo: string; donoId?: string; appUserId?: string; phone?: string; fase2?: string }) {
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
    modosDaFase2: () => modosDaAgendaNoBanco(admin),
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
    const r = await turnoDaAgenda(texto, { modo: "ligado", fase2: "ligado" });
    assert(r.r?.ok, texto);
    assertEquals(r.rpcs, [rpc], texto);
    // (revisão da Fase 2) com a leitura ligada e a agenda automática desligada, as palavras da Fase 2 vão ao modelo
    const semFase2 = await turnoDaAgenda(texto, { modo: "ligado", fase2: "desligado" });
    assertEquals([semFase2.r, semFase2.rpcs], [null, []], `sem a agenda automática: ${texto}`);
  }
  // de outro número (ou outro login): segue ao modelo, nada é chamado
  for (const outro of [{ appUserId: "u-outro" }, { phone: "5547900000001" }]) {
    const r = await turnoDaAgenda("dia feito", { modo: "ligado", fase2: "ligado", ...outro });
    assertEquals([r.r, r.rpcs], [null, []], JSON.stringify(outro));
  }
  // agenda desligada: o *dia feito* vai ao modelo como conversa
  const desligado = await turnoDaAgenda("dia feito", { modo: "desligado" });
  assertEquals([desligado.r, desligado.rpcs], [null, []]);
  // "desfaz B" é do secretário (a letra do dia), não da agenda
  const letra = await turnoDaAgenda("desfaz B", { modo: "ligado", fase2: "ligado" });
  assertEquals([letra.r, letra.rpcs], [null, []]);
});

Deno.test("agenda Fase 2 (revisão): os dois canais passam o modo da agenda automática à camada", () => {
  assertEquals(fonte.split("modosDaFase2: () => modosDaAgendaNoBanco(admin)").length - 1, 2);
});

// Revisão da Fase 2: o "sim" de uma pendência que só deixou o rascunho da agenda (schedule_service_order com a agenda
// automática ligada, so_rascunho) nunca diz "executado". Os dois caminhos (WhatsApp e painel) montam a mensagem por
// textoDoSim, que mostra a releitura e o *grava*; o "✅ … executado." solto não volta.
Deno.test("aprovação (WhatsApp e painel): a mensagem do sim sai de textoDoSim, nunca do '— executado.' montado à mão", () => {
  assertEquals((fonte.match(/textoDoSim\(pending\.title, execResult\)/g) ?? []).length, 2);
  assertEquals(fonte.includes("— executado.${"), false, "a mensagem de executado montada à mão voltou");
});

// Fase 3 (P6): a carona da agenda (_shared/agenda/carona.ts; a decisão é do banco, agenda_carona). Nos quatro caminhos do
// turno do dono — WhatsApp pelo OpenRouter e pelo Claude Max, painel pelo OpenRouter e pelo Claude Max —, depois da
// resposta do modelo e ANTES de gravar e de mandar: o texto do turno ganha a carona no fim, uma vez, e o histórico também.
const modeloWa = fonte.slice(fonte.indexOf("async function turnoDoModeloNoWhatsApp("), fonte.indexOf("async function handleEntregaDoMax("));
const entregaMax = fonte.slice(fonte.indexOf("async function handleEntregaDoMax("), fonte.indexOf("async function gravarTurnoDoMax("));
const painelMax = fonte.slice(fonte.indexOf("async function turnoDoPainelPeloMax("), fonte.indexOf("// ---------------- HANDLER ----------------"));
const painelLoop = fonte.slice(fonte.indexOf("const peloMax = await turnoDoPainelPeloMax("));

Deno.test("carona (WhatsApp pelo OpenRouter): depois do loop, antes de gravar as mensagens e de montar a resposta; só o admin", () => {
  const c = modeloWa.indexOf('caronaDoTurno(admin, appUser.id, osDoTurno(result.toolEvents), result, { canal: "whatsapp" })');
  assert(c > 0, "carona ausente");
  assert(modeloWa.indexOf("const result = await runAgentLoop(loopParams);") < c, "depois do loop");
  assert(c < modeloWa.indexOf("const newNativeSlice = result.messages.slice(alreadyPersistedCount);"), "antes de gravar (o histórico leva a carona)");
  assert(c < modeloWa.indexOf("respostaDoTurnoNoWhatsApp("), "antes da resposta ao WhatsApp");
  assertStringIncludes(modeloWa, 'if (appUser.role === "admin") {');
  assertStringIncludes(modeloWa, "if (carona) aplicarCarona(result, carona);");
});

Deno.test("carona (WhatsApp pelo Claude Max): pelas OS que o erp-mcp guardou no job, antes de gravar e de responder", () => {
  const c = entregaMax.indexOf('comCarona(admin, appUser.id, osDoJob(job.metadata), respostaDoMax, interrupcao, { canal: "whatsapp" })');
  assert(c > 0, "carona ausente");
  // 29/10/2026: a gravação leva também o "Conferido pelo sistema"
  assert(c < entregaMax.indexOf('await gravarTurnoDoMax(admin, sessionId, texto, [aviso, resposta, conferido].filter(Boolean).join("\\n\\n"), job, "whatsapp");'), "antes de gravar");
  assert(c < entregaMax.indexOf("respostaDoTurnoNoWhatsApp("), "antes da resposta ao WhatsApp");
  assertStringIncludes(entregaMax, 'appUser.role === "admin" && job.status === "completed"');
});

Deno.test("carona (painel): pelo OpenRouter depois do loop e antes de gravar; pelo Claude Max antes de gravar e devolver", () => {
  const c = painelLoop.indexOf('caronaDoTurno(admin, userId, osDoTurno(result.toolEvents), result, { canal: "painel" })');
  assert(c > 0, "carona do painel ausente");
  assert(painelLoop.indexOf("const result = await runAgentLoop({ ...loopParams") < c, "depois do loop");
  assert(c < painelLoop.indexOf("const newNativeSlice = result.messages.slice(alreadyPersistedCount);"), "antes de gravar");
  assertStringIncludes(painelLoop, 'if (userRole === "admin") {');
  const m = painelMax.indexOf('comCarona(p.admin, p.userId, osDoJob((job as any).metadata), respostaDoMax, interrupcao, { canal: "painel" })');
  assert(m > 0, "carona do painel pelo Max ausente");
  // 29/10/2026: a gravação e a resposta levam também o "Conferido pelo sistema"
  assert(m < painelMax.indexOf('await gravarTurnoDoMax(p.admin, p.loopParams.sessionId, p.texto, comConferido, job as any, "web")'), "antes de gravar");
  assert(m < painelMax.indexOf("const message = { role: \"assistant\", content: comConferido };"), "antes de devolver");
});

Deno.test("carona: uma vez por turno (um caminho cada) e nunca na camada das palavras nem na confirmação", () => {
  assertEquals((fonte.match(/aplicarCarona\(result, carona\)/g) ?? []).length, 2);
  assertEquals((fonte.match(/await comCarona\(/g) ?? []).length, 2);
  assert(!turno.includes("caronaDoTurno(") && !turno.includes("comCarona("), "a carona não entra antes do modelo (palavras, sim, secretário)");
});

// ─── Aprovação em lote, Fase 1 (29/10/2026): a fiação no turno ─────────────────────────────────────────────────────────
const confirmacao = turno.slice(turno.indexOf("const confirmation = parseConfirmationReply(text"), turno.indexOf("parseOptionReply(text, pendingOptions.length)"));

Deno.test("lote F1: toda resposta da camada de confirmação do WhatsApp entra na conversa (PIN mascarado) antes de sair", () => {
  // as quatro saídas: ajuste junto, herdada reapresentada, decisão, e "sim <PIN>" sem nada esperando
  const gravacoes = confirmacao.split("await gravarDecisaoNaConversa(admin, { sessionId, resposta: text, texto:").length - 1;
  assertEquals(gravacoes, 4);
  for (const [grava, envia] of [
    ["texto: naoExecutei", "queueWhatsAppReply(admin, phoneNormalized, naoExecutei)"],
    ["texto: reapresentada", "queueWhatsAppReply(admin, phoneNormalized, reapresentada)"],
    ["texto: resolved.message", "await enviarComRegistro("],
    ["texto: nadaEsperando", "queueWhatsAppReply(admin, phoneNormalized, nadaEsperando)"],
  ]) {
    const g = confirmacao.indexOf(grava);
    assert(g > 0 && confirmacao.indexOf(envia, g) > g, `${grava}: grava antes de enviar`);
  }
});

Deno.test("lote F1: 'já decidida' diz o desfecho real e segue a fila; o painel responde 409 em português com o resultado", () => {
  const resolver = fonte.slice(fonte.indexOf("async function resolveWhatsAppConfirmation("), fonte.indexOf("async function comAProximaPendencia("));
  assertStringIncludes(resolver, "return await comAProximaPendencia(admin, pending, textoDoDesfecho(pending), clearedMetadata);");
  assert(!fonte.includes("Essa pendência não existe mais ou já foi decidida"), "a frase vaga saiu");
  assertStringIncludes(fonte, "return jr({ error: textoDoDesfecho(pending), resultado: pending.status }, 409);");
  assert(!fonte.includes('"processada" : pending.status'), "nada de 'já foi rejected'");
});

Deno.test("lote F1: confirm_action devolve o desfecho de verdade (o cartão e o sino deixam de dizer 'executada' na falha)", () => {
  const confirm = fonte.slice(fonte.indexOf('if (body.type === "confirm_action") {'), fonte.indexOf("// ---------- MODO SALES COPY"));
  assertStringIncludes(confirm, 'resultado: execError ? "failed" : "executed",');
  assertStringIncludes(confirm, 'resultado: "rejected",');
});

Deno.test("lote F1: tipo desconhecido é recusado antes do turno do modelo", () => {
  const recusa = fonte.indexOf('body.type !== "load_history" && body.type !== "confirm_action"');
  assert(recusa > 0 && recusa < fonte.indexOf('if (body.type === "load_history") {'), "antes do load_history");
  assert(recusa < fonte.indexOf("const result = await runAgentLoop({ ...loopParams"), "antes do modelo do painel");
});

Deno.test("lote F1: o 'Conferido pelo sistema' nos quatro caminhos (OpenRouter e Max, WhatsApp e painel)", () => {
  assertEquals(fonte.split("reciboDasGravacoes(falhasDosEventos(result.toolEvents))").length - 1, 2, "OpenRouter: WhatsApp e painel");
  assertStringIncludes(fonte, "reciboDasGravacoes(await falhasDaAuditoria(admin, sessionId, jobId))");
  assertEquals(fonte.split("reciboDasGravacoes(await falhasDaAuditoria(p.admin, p.loopParams.sessionId, jobId))").length - 1, 2,
    "painel pelo Max: pronto e parado no meio");
  // no OpenRouter, vai para o histórico ANTES de gravar as mensagens do turno
  for (const inicio of ["async function turnoDoModeloNoWhatsApp(", "// ---------- MODO SALES COPY"]) {
    const bloco = fonte.slice(fonte.indexOf(inicio));
    const anexa = bloco.indexOf("anexarAoHistoricoDoTurno(result.messages, conferido)");
    assert(anexa > 0 && anexa < bloco.indexOf('from("ai_operator_messages").insert(rowsToInsert)'), `${inicio}: anexa antes de gravar`);
  }
});

Deno.test("lote F1: guarda da reserva — o Max que já gravou ou criou pendência não é refeito pelo OpenRouter", () => {
  const entrega = fonte.slice(fonte.indexOf("async function handleEntregaDoMax("), fonte.indexOf("async function gravarTurnoDoMax("));
  const guarda = entrega.indexOf("jobDeixouTrabalho(meta) || await trabalhoNaAuditoria(admin, sessionId, jobId)");
  assert(guarda > 0 && guarda < entrega.indexOf("refazendo pelo OpenRouter"), "WhatsApp: confere antes de refazer");
  assertStringIncludes(entrega, 'const aviso = parouNoMeio ? avisoDoTurnoInterrompido(job.error_code) : "";');
  // o aviso vai pelo campo próprio: no topo também da lista de opções que o Max deixou (revisão de 29/10)
  assertStringIncludes(entrega, "texto: resposta, conferido, aviso }");
  // a entrega tardia do painel também confere e não manda "peça de novo" a quem já gravou (revisão de 29/10)
  const tardia = fonte.slice(fonte.indexOf("async function handleEntregaDoPainel("), fonte.indexOf("const dormir ="));
  assertStringIncludes(tardia, "reciboDasGravacoes(await falhasDaAuditoria(admin, sessionId, String(job.id)))");
  assertStringIncludes(tardia, "jobDeixouTrabalho(meta) || await trabalhoNaAuditoria(admin, sessionId, String(job.id))");
  const painel = fonte.slice(fonte.indexOf("async function turnoDoPainelPeloMax("), fonte.indexOf("// ---------------- HANDLER"));
  // e o painel parado no meio ainda devolve a lista de opções
  assertStringIncludes(painel, "if (interrompido.options) return jr({ message, options: interrompido.options");
  const guardaDoPainel = painel.indexOf("jobDeixouTrabalho((job as any).metadata) || await trabalhoNaAuditoria(p.admin, p.loopParams.sessionId, jobId)");
  assert(guardaDoPainel > 0 && guardaDoPainel < painel.indexOf("vai pelo OpenRouter"), "painel: confere antes de seguir pelo OpenRouter");
});

Deno.test("lote F1: no painel, a frase do assistente acima do cartão (OpenRouter e Max)", () => {
  assertStringIncludes(fonte, "textoAcimaDoCartao(result.message.content, 2000)");
  assertStringIncludes(fonte, "textoAcimaDoCartao(resposta, 2000)");
});

// Retorno F0a-2 (05/11/2026): as falhas do assistente ficavam só no console (0 linhas de ai-agent em app_error_logs em 05/11).
// O que se protege: todo turno que termina sem resposta conta para o aviso do vigia; o Max que falha com a reserva ligada é
// só aviso, porque a reserva ainda pode responder; o log nunca troca o 500 do handler por outro erro.
Deno.test("F0a-2: turno sem resposta entra na conta, nos quatro caminhos (e no do Max fora sem reserva, C2)", () => {
  // revisão da leva B (25/11/2026): o turno do WhatsApp registra como "turno_whatsapp" ou "turno_whatsapp_com_causa"
  // (ondeDoTurnoSemResposta, em causa-da-falha.ts). Os dois contam: a conta por hora soma pelo contexto, não pelo nome.
  assertStringIncludes(fonte, "if (result.error) await registrarFalhaDoAssistente(admin, { onde: ondeDoTurnoSemResposta(turno.causaDoMax)");
  assertStringIncludes(fonte, 'registrarFalhaDoAssistente(admin, { onde: "turno_painel"');
  assertStringIncludes(fonte, 'registrarFalhaDoAssistente(admin, { onde: "max_sem_reserva"');
  assertStringIncludes(fonte, 'registrarFalhaDoAssistente(admin, { onde: "handler"');
  // C2 (24/11/2026): o registro que diz ao vigia de queda (V1) que o dono já soube pelo WhatsApp. O vigia filtra por este
  // nome exato (ele vira a coluna action do log): não renomear sem mexer no vigia.
  assertStringIncludes(fonte, 'registrarFalhaDoAssistente(admin, { onde: "max_fora_sem_reserva"');
});

Deno.test("F0a-2: o Max que falha com a reserva ligada é só aviso e não conta", () => {
  const ini = fonte.indexOf('onde: "max_sem_reserva"');
  const trecho = fonte.slice(ini, fonte.indexOf("turnoDoModeloNoWhatsApp({", ini));
  assertStringIncludes(trecho, 'action: "max_falhou", level: "warn"');
  // C2: o retorno do aviso ganhou a causa. A saída do aviso tem de existir (indexOf -1 passaria na comparação) e vir antes
  // do log da reserva.
  const saidaDoAviso = trecho.indexOf('return jr({ ok: true, entregue: "aviso", causa: causa.codigo });');
  assert(saidaDoAviso > 0, "a saída do aviso sumiu");
  assert(saidaDoAviso < trecho.indexOf('action: "max_falhou"'), "o aviso é do caminho que segue pela reserva");
  assertEquals((trecho.match(/return jr\(/g) ?? []).length, 1, "uma saída só antes da reserva: a do aviso");
});

// ─── Pacote 1, C2 (24/11/2026): a causa dita e a reserva desligada de verdade ─────────────────────────────────────────
// O que se protege: com app_settings.ai_whatsapp_max_reserva = 'off', nenhum caminho em que o Claude da assinatura não
// atende chega ao laço do OpenRouter, nos dois canais; o aviso leva a causa em frase (causa-da-falha.ts), nunca o código
// cru, e entra na conversa antes de sair; com a chave ligada, o caminho é o de sempre.
const entregaDoMax = fonte.slice(fonte.indexOf("async function handleEntregaDoMax("), fonte.indexOf("async function gravarTurnoDoMax("));

Deno.test("C2 (WhatsApp): Max indisponível ou falha ao enfileirar, com a reserva desligada, fecha com o aviso antes do laço do OpenRouter", () => {
  const ramoDoMax = modeloWa.slice(modeloWa.indexOf("// ---- Claude Max (assinatura do dono"), modeloWa.indexOf("// ---- OpenRouter (loop aqui na edge) ----"));
  assert(ramoDoMax.length > 0 && modeloWa.indexOf("// ---- OpenRouter (loop aqui na edge) ----") < modeloWa.indexOf("const result = await runAgentLoop(loopParams);"), "o ramo do Max vem antes do laço");
  assert(!ramoDoMax.includes("runAgentLoop("), "o laço não roda dentro do ramo do Max");
  // falha ao enfileirar: a guarda é a PRIMEIRA coisa do catch, antes do log que diz "turno pelo OpenRouter"
  const pegou = ramoDoMax.indexOf("} catch (e) {");
  const fora = ramoDoMax.indexOf("} else {", pegou);
  assert(pegou > 0 && fora > pegou, "os dois ramos existem");
  const ramoDeEnfileirar = ramoDoMax.slice(pegou, fora);
  const guardaDeEnfileirar = ramoDeEnfileirar.indexOf("if (!reservaLigada(settings)) {");
  assert(guardaDeEnfileirar > 0 && guardaDeEnfileirar < ramoDeEnfileirar.indexOf('action: "enfileirar_max"'), "enfileirar: a guarda vem antes de seguir pela reserva");
  assertStringIncludes(ramoDeEnfileirar, 'return await avisarQueOMaxNaoAtende(turno, await lerCausaDaFalha(admin, { motivo: "enfileirar" }), e);');
  // Max indisponível
  const ramoDeFora = ramoDoMax.slice(fora);
  const guardaDeFora = ramoDeFora.indexOf("if (!reservaLigada(settings)) {");
  assert(guardaDeFora > 0 && guardaDeFora < ramoDeFora.indexOf("turno pelo OpenRouter"), "Max fora: a guarda vem antes de seguir pela reserva");
  assertStringIncludes(ramoDeFora, "return await avisarQueOMaxNaoAtende(turno, await lerCausaDaFalha(admin));");
  // duas guardas, duas saídas: nenhuma terceira porta para o laço com a reserva desligada
  assertEquals((ramoDoMax.match(/if \(!reservaLigada\(settings\)\) \{/g) ?? []).length, 2);
  assertEquals((ramoDoMax.match(/return await avisarQueOMaxNaoAtende\(/g) ?? []).length, 2);
  // o turno que foi para a fila do Max continua saindo como sempre
  assertStringIncludes(ramoDoMax, "return jr({ ok: true, session_id: sessionId, claude_max: jobId });");
});

Deno.test("C2 (WhatsApp): o aviso do Max fora conta para o vigia, entra na conversa e só então sai; não roda o modelo nem mexe na sessão", () => {
  const aviso = fonte.slice(fonte.indexOf("async function avisarQueOMaxNaoAtende("), fonte.indexOf("async function turnoDoModeloNoWhatsApp("));
  assert(aviso.length > 0, "falta a função do aviso");
  const registra = aviso.indexOf('await registrarFalhaDoAssistente(admin, { onde: "max_fora_sem_reserva"');
  const grava = aviso.indexOf('await gravarTurnoDoMax(admin, sessionId, effectiveText, aviso, {}, "whatsapp");');
  const envia = aviso.indexOf("await queueWhatsAppReply(admin, phoneNormalized, aviso);");
  assert(registra > 0 && registra < grava && grava < envia, "registra, grava na conversa e só então envia");
  assertStringIncludes(aviso, "const aviso = textoDaFalhaParaODono(causa);");
  assertStringIncludes(aviso, 'return jr({ ok: true, entregue: "aviso", causa: causa.codigo });');
  assert(!aviso.includes("runAgentLoop") && !aviso.includes("enfileirarTurnoNoMax"), "sem modelo");
  // o turno não aconteceu: o estado das camadas (lista de opções, pendência) fica como estava
  assert(!aviso.includes("ai_operator_sessions"), "não grava a sessão");
  // o registro do log leva o código da causa, nunca o texto do erro do PC
  assertStringIncludes(aviso, "mensagem: `Claude Max fora e sem reserva: ${rotuloDaCausaNoLog(causa)}`");
});

Deno.test("C2 (WhatsApp): o job que falhou sem reserva sai com a causa em frase e entra na conversa antes do envio", () => {
  const ini = entregaDoMax.indexOf("if (!reservaLigada(settings) || !texto) {");
  const ramo = entregaDoMax.slice(ini, entregaDoMax.indexOf('action: "max_falhou"'));
  assert(ini > 0, "falta o ramo do aviso");
  // a causa é lida uma vez, antes do ramo, com o job (o erro dele só escolhe a frase)
  const leCausa = entregaDoMax.indexOf("const causa = await lerCausaDaFalha(admin, { job });");
  assert(leCausa > 0 && leCausa < ini, "lê a causa antes de decidir");
  assertStringIncludes(entregaDoMax, "error, error_code, model_used, usage, timeout_seconds");
  const grava = ramo.indexOf('await gravarTurnoDoMax(admin, sessionId, texto, avisoDaCausa, job, "whatsapp");');
  const envia = ramo.indexOf("await queueWhatsAppReply(admin, phoneNormalized, avisoDaCausa);");
  assert(grava > 0 && envia > grava, "grava na conversa antes de enviar");
  assertStringIncludes(ramo, "const avisoDaCausa = textoDaFalhaParaODono(causa);");
  // sem texto do pedido não há turno a gravar (uma linha de usuário vazia quebraria a conversa)
  assertStringIncludes(ramo, "if (texto) await gravarTurnoDoMax(");
  // o código cru não vai mais ao dono
  assert(!entregaDoMax.includes("Não consegui responder pelo Claude agora"), "o aviso com o código cru saiu");
  assert(!/queueWhatsAppReply\([^;]*error_code/.test(entregaDoMax), "nenhum envio leva o código do job");
});

Deno.test("C2 (WhatsApp): com a reserva ligada, a causa segue com o turno e só aparece se a reserva também falhar", () => {
  assert(/effectiveText: texto, permitirMax: false,\r?\n\s+causaDoMax: causa,/.test(entregaDoMax), "a reserva recebe a causa do Max");
  assertStringIncludes(modeloWa, "aviso: result.error && turno.causaDoMax ? avisoDeQueOClaudeNaoRespondeu(turno.causaDoMax) : undefined,");
  // só neste ponto: o turno normal (sem causa do Max) não ganha aviso nenhum
  assertEquals((fonte.match(/avisoDeQueOClaudeNaoRespondeu\(/g) ?? []).length, 1);
});

// Revisão da leva B (25/11/2026). O que se protege: com a reserva LIGADA, o turno que cai no laço porque o Claude já
// estava fora (ou porque o pedido não entrou na fila) também leva a causa, lida antes do laço; e o registro do turno sem
// resposta sai com o nome que diz se a causa foi junto. Sem isso o dono lia só "erro do sistema" e o vigia de queda (V1)
// contava esse turno como "o dono já soube": o aviso do login caído nunca saía.
Deno.test("revisão B (WhatsApp): com a reserva ligada, Max fora ou falha ao enfileirar também levam a causa para o laço", () => {
  const ramoDoMax = modeloWa.slice(modeloWa.indexOf("// ---- Claude Max (assinatura do dono"), modeloWa.indexOf("// ---- OpenRouter (loop aqui na edge) ----"));
  const pegou = ramoDoMax.indexOf("} catch (e) {");
  const fora = ramoDoMax.indexOf("} else {", pegou);
  assert(pegou > 0 && fora > pegou, "os dois ramos existem");
  // falha ao enfileirar: depois da guarda da reserva desligada (que sai com o aviso) e do log de "só aviso"
  const ramoDeEnfileirar = ramoDoMax.slice(pegou, fora);
  const causaDeEnfileirar = ramoDeEnfileirar.indexOf('turno.causaDoMax = await lerCausaDaFalha(admin, { motivo: "enfileirar" });');
  assert(causaDeEnfileirar > ramoDeEnfileirar.indexOf('action: "enfileirar_max"'), "enfileirar: a causa é guardada no caminho que segue pela reserva");
  assert(causaDeEnfileirar > ramoDeEnfileirar.indexOf("return await avisarQueOMaxNaoAtende("), "enfileirar: depois da saída da reserva desligada");
  // Max indisponível: a causa é lida do estado do PC (sem pedido e sem motivo), depois da saída da reserva desligada
  const ramoDeFora = ramoDoMax.slice(fora);
  const causaDeFora = ramoDeFora.indexOf("turno.causaDoMax = await lerCausaDaFalha(admin);");
  assert(causaDeFora > ramoDeFora.indexOf("return await avisarQueOMaxNaoAtende(turno, await lerCausaDaFalha(admin));"), "Max fora: depois da saída da reserva desligada");
  // só estes dois pontos escrevem a causa dentro do turno, e os dois antes do laço
  assertEquals((modeloWa.match(/turno\.causaDoMax = /g) ?? []).length, 2);
  assert(modeloWa.lastIndexOf("turno.causaDoMax = ") < modeloWa.indexOf("const result = await runAgentLoop(loopParams);"), "antes do laço");
  // a mesma causa decide as duas coisas: a linha no topo da resposta e o nome do registro
  assertStringIncludes(modeloWa, "aviso: result.error && turno.causaDoMax ? avisoDeQueOClaudeNaoRespondeu(turno.causaDoMax) : undefined,");
  assertStringIncludes(modeloWa, "onde: ondeDoTurnoSemResposta(turno.causaDoMax), mensagem: `Turno do WhatsApp sem resposta: ${result.error}`");
  // o nome antigo não é mais escrito à mão em lugar nenhum do ai-agent
  assert(!fonte.includes('onde: "turno_whatsapp"'), "o registro do turno sai só por ondeDoTurnoSemResposta");
});

Deno.test("C2 (painel): depois de escolhido o Max, nenhum 'return null' sem conferir a reserva", () => {
  const corpo = painelMax;
  const partes = corpo.split("return null");
  // quatro saídas para o OpenRouter: (1) o provedor do turno não é o Max; (2) Max fora; (3) falha ao enfileirar; (4) o job falhou
  assertEquals(partes.length - 1, 4);
  // S5: a pessoa entra na conta (p.userId); quem não é assinante e está sem reserva já saiu antes, com a frase do titular
  // (teste do S5, abaixo), então o 'return null' desta linha só é alcançado com a reserva ligada ou com o canal fora do Claude
  assert(partes[0].trimEnd().endsWith('if (provedorDoTurno(p.settings, p.userRole, "panel", p.userId) !== "claude_max")'), "a primeira saída é a de quem não vai pelo Max");
  assert(!partes[0].includes("reservaLigada"), "antes de escolhido o Max, a reserva só é conferida dentro de naoAssinanteSemReserva");
  assert(partes[0].includes('if (naoAssinanteSemReserva(p.settings, p.userRole, "panel", p.userId)) {'), "S5: a guarda de quem não é o titular vem antes da primeira saída");
  const esperado: Array<[string, string]> = [
    ["Max fora", "return await semOMaxESemReservaNoPainel(p, await lerCausaDaFalha(p.admin));"],
    ["falha ao enfileirar", 'return await semOMaxESemReservaNoPainel(p, await lerCausaDaFalha(p.admin, { motivo: "enfileirar" }), e);'],
    ["job que falhou", "return await avisarNoPainelQueOMaxNaoAtende(p, await lerCausaDaFalha(p.admin, { job: jobDaCausa }), job ?? {});"],
  ];
  esperado.forEach(([nome, saida], i) => {
    const trecho = partes[i + 1];
    const guarda = trecho.lastIndexOf("if (!reservaLigada(p.settings)) {");
    assert(guarda > 0, `${nome}: falta a guarda da reserva antes do 'return null'`);
    // entre a guarda e o 'return null' está a saída com a causa: com a reserva desligada o 'return null' não é alcançado
    assertStringIncludes(trecho.slice(guarda), saida, nome);
  });
});

Deno.test("C2 (painel): o aviso leva a causa em frase, entra na conversa e conta como turno do painel sem resposta", () => {
  const helpers = fonte.slice(fonte.indexOf("async function avisarNoPainelQueOMaxNaoAtende("), fonte.indexOf("async function turnoDoPainelPeloMax("));
  assertStringIncludes(helpers, "const aviso = textoDaFalhaParaODono(causa);");
  const grava = helpers.indexOf('await gravarTurnoDoMax(p.admin, p.loopParams.sessionId, p.texto, aviso, job, "web");');
  assert(grava > 0 && grava < helpers.indexOf('return jr({ message: { role: "assistant", content: aviso }, tool_events: [], session_id: p.loopParams.sessionId });'), "grava antes de devolver");
  // o Max fora antes do job já contava (como falha do OpenRouter); continua contando, e fora da lista que o vigia lê como "o dono soube pelo WhatsApp"
  assertStringIncludes(helpers, 'await registrarFalhaDoAssistente(p.admin, { onde: "turno_painel", mensagem: `Turno do painel sem resposta: Claude Max fora e sem reserva: ${rotuloDaCausaNoLog(causa)}`, erro });');
  assert(!helpers.includes("max_fora_sem_reserva"), "o registro do WhatsApp não é usado no painel");
  assert(!helpers.includes("runAgentLoop"), "sem modelo");
  // o motivo cru e a frase da reserva saíram da tela
  assert(!painelMax.includes("a reserva pelo OpenRouter está desligada"), "a frase que falava da reserva saiu");
  assert(!/content: `[^`]*\$\{d\.motivo\}/.test(painelMax), "o motivo cru não vai mais para a tela");
  // o pedido que ninguém pegou (cancelado pela edge) é prazo vencido na fila; e a leitura traz o que a causa precisa
  assertStringIncludes(painelMax, 'const jobDaCausa = job?.status === "pending" ? { ...job, error_code: "deadline_exceeded" } : job;');
  assertStringIncludes(painelMax, '.select("id, status, started_at, error_code, error, timeout_seconds, response, metadata, model_used, usage")');
});

Deno.test("C2: nenhum aviso ao dono fala da reserva nem do saldo dela, e a chave da reserva não é escrita por aqui", () => {
  // decisão do dono de 24/11/2026: ele não vai pôr crédito na reserva e não quer ser lembrado disso
  const doMax = fonte.slice(fonte.indexOf("async function avisarQueOMaxNaoAtende("), fonte.indexOf("// ---------------- HANDLER ----------------"));
  const avisos = [...doMax.matchAll(/`[^`]*`|"[^"\r\n]*"/g)].map((m) => m[0]).filter((t) => /^.(⚠️|⏳)/.test(t));
  assert(avisos.some((t) => t.includes("Ainda estou trabalhando nisso")), "a varredura acha os avisos escritos aqui");
  for (const t of avisos) assert(!/cr[eé]dito|recarg|saldo|reserva|openrouter/i.test(t), t);
  // quem liga ou desliga a reserva é o dono, pela tela: o ai-agent só lê a chave (reservaLigada)
  assert(!doMax.includes('from("app_settings").update') && !doMax.includes('from("app_settings").upsert') && !doMax.includes("CHAVE_DA_RESERVA"), "o ai-agent não grava a chave da reserva");
});

// ─── Pacote 1, S5 (24/11/2026): a assinatura Claude pela pessoa do assinante, e não pelo cargo ───────────────────────
// O que se protege: as duas chamadas de provedorDoTurno levam o id de quem fala (sem ele, com a chave ai_max_assinantes
// gravada, ninguém iria pelo Max); e quem não é assinante, com a reserva desligada, recebe a frase do titular ANTES de
// qualquer caminho que leve ao laço do OpenRouter, nos dois canais. A regra em si (lista, chave ausente, reserva) é
// provada em _shared/ai/max/claude-max_test.ts.
Deno.test("S5: as duas chamadas de provedorDoTurno levam o id da pessoa", () => {
  assertStringIncludes(modeloWa, 'if (turno.permitirMax && provedorDoTurno(settings, appUser.role, "whatsapp", appUser.id) === "claude_max") {');
  assertStringIncludes(painelMax, 'if (provedorDoTurno(p.settings, p.userRole, "panel", p.userId) !== "claude_max") return null;');
  // nenhuma chamada sobrou sem a pessoa
  const chamadas = [...fonte.matchAll(/provedorDoTurno\(([^)]*)\)/g)].map((m) => m[1]);
  assertEquals(chamadas.length, 2);
  for (const c of chamadas) assert(/\.(id|userId)$/.test(c.trim()), `provedorDoTurno(${c}) sem o id de quem fala`);
  // o id é o de app_users, o mesmo que vai em ai_jobs.requested_by (o que o gateway confere)
  assertStringIncludes(modeloWa, "appUserId: appUser.id,");
  assertStringIncludes(painelMax, "appUserId: p.userId,");
});

Deno.test("S5 (WhatsApp): quem não é o titular e está sem reserva recebe a frase antes de ler a conversa, do Max e do laço", () => {
  const guarda = modeloWa.indexOf('if (naoAssinanteSemReserva(settings, appUser.role, "whatsapp", appUser.id)) {');
  assert(guarda > 0, "falta a guarda de quem não é o titular");
  assert(guarda < modeloWa.indexOf("carregarJanela(admin, sessionId)"), "antes de ler a conversa");
  assert(guarda < modeloWa.indexOf("// ---- Claude Max (assinatura do dono"), "antes do ramo do Max");
  assert(guarda < modeloWa.indexOf("const result = await runAgentLoop(loopParams);"), "antes do laço do OpenRouter");
  const ramo = modeloWa.slice(guarda, modeloWa.indexOf("// ---- Turno normal do LLM ----"));
  assertStringIncludes(ramo, 'await queueWhatsAppReply(admin, phoneNormalized, await fraseParaQuemNaoEOTitular(admin, "whatsapp", appUser.id));');
  assertStringIncludes(ramo, 'return jr({ ok: true, entregue: "aviso", causa: "nao_assinante" });');
  assertEquals((ramo.match(/return /g) ?? []).length, 1, "uma saída só, e ela não segue adiante");
  // o turno não aconteceu: não roda o modelo, não entra na fila e não mexe na sessão nem na conversa
  for (const proibido of ["runAgentLoop", "enfileirarTurnoNoMax", "ai_operator_sessions", "ai_operator_messages", "gravarTurnoDoMax"]) {
    assert(!ramo.includes(proibido), `o ramo de quem não é o titular não usa ${proibido}`);
  }
  // uma guarda só no turno do WhatsApp (a reserva que refaz o turno é sempre do assinante)
  assertEquals((modeloWa.match(/naoAssinanteSemReserva\(/g) ?? []).length, 1);
});

Deno.test("S5 (painel): quem não é o titular e está sem reserva recebe a frase na tela, antes de qualquer 'return null'", () => {
  const guarda = painelMax.indexOf('if (naoAssinanteSemReserva(p.settings, p.userRole, "panel", p.userId)) {');
  assert(guarda > 0, "falta a guarda de quem não é o titular");
  assert(guarda < painelMax.indexOf("return null"), "antes da primeira saída para o OpenRouter");
  assert(guarda < painelMax.indexOf("maxDisponivel(p.admin)"), "antes de consultar o Max");
  const ramo = painelMax.slice(guarda, painelMax.indexOf('if (provedorDoTurno(p.settings, p.userRole, "panel", p.userId)'));
  assertStringIncludes(ramo, 'const aviso = await fraseParaQuemNaoEOTitular(p.admin, "panel", p.userId);');
  assertStringIncludes(ramo, 'return jr({ message: { role: "assistant", content: aviso }, tool_events: [], session_id: p.loopParams.sessionId });');
  assert(!ramo.includes("return null") && !ramo.includes("runAgentLoop") && !ramo.includes("gravarTurnoDoMax"), "não segue para o OpenRouter nem grava a conversa");
  assertEquals((painelMax.match(/naoAssinanteSemReserva\(/g) ?? []).length, 1);
});

Deno.test("S5: a frase é a do código nao_assinante (causa-da-falha.ts), não conta como falha do assistente e deixa um aviso consultável", () => {
  const ini = fonte.indexOf("async function fraseParaQuemNaoEOTitular(");
  assert(ini > 0, "falta a função da frase");
  // só o corpo da função: até o comentário da função seguinte (a do C2)
  const fn = fonte.slice(ini, fonte.indexOf("/**", ini));
  assert(fn.length > 0 && fn.length < fonte.indexOf("async function avisarQueOMaxNaoAtende(") - ini, "o recorte é o corpo da função");
  // a frase vem da fonte única do C2: nenhum texto para o usuário é escrito aqui
  assertStringIncludes(fn, 'const causa = await lerCausaDaFalha(admin, { motivo: "nao_assinante" });');
  assertStringIncludes(fn, "return textoDaFalhaParaODono(causa);");
  assert(!fn.includes("Este assistente funciona"), "a frase mora em causa-da-falha.ts");
  // não é queda do Claude: fora da conta do vigia e fora do registro que diz ao vigia de queda que o dono já soube
  assert(!fn.includes("registrarFalhaDoAssistente(admin") && !fn.includes('onde: "max_fora_sem_reserva"'), "não conta como falha do assistente");
  assertStringIncludes(fn, 'context: "ai-agent", action: "nao_assinante", level: "warn",');
  // o id de quem pediu vai só nos detalhes do log (é por ali que se acha um id errado na lista); nunca na frase
  assertStringIncludes(fn, "details: { canal, user_id: userId },");
  assert(!fn.includes("gravarTurnoDoMax") && !fn.includes("ai_operator_messages"), "a recusa não entra na conversa");
  // as duas guardas e mais ninguém usam a frase
  assertEquals((fonte.match(/await fraseParaQuemNaoEOTitular\(/g) ?? []).length, 2);
});

Deno.test("F0a-2: o log do handler vem antes do 500 e não pode lançar", () => {
  assert(fonte.indexOf("await registrarFalhaDoHandler(e);") < fonte.indexOf('return jr({ error: e?.message || "internal error" }, 500);'), "log antes do 500");
  const fn = fonte.slice(fonte.indexOf("async function registrarFalhaDoHandler"), fonte.indexOf("// ---------------- HANDLER"));
  assertStringIncludes(fn, "try {");
  assertStringIncludes(fn, "} catch {");
});

// Retorno (05/11/2026): a guarda do PIN. O que se protege: ela vem depois do bloco de confirmação (senão *sim <PIN>* com
// pendência nunca aprovaria) e antes de tudo o que leva o texto ao modelo; não grava o texto na conversa.
Deno.test("guarda do PIN: depois da confirmação, antes do modelo e sem gravar o texto", () => {
  const guarda = fonte.indexOf("if (await pinNoTexto(text, appUser.ai_whatsapp_pin_hash)) {");
  assert(guarda > 0, "falta a guarda");
  assert(fonte.indexOf("const confirmation = parseConfirmationReply(text") < guarda, "depois da confirmação");
  assert(guarda < fonte.indexOf("let effectiveText = text;"), "antes de o texto seguir adiante");
  const bloco = fonte.slice(guarda, fonte.indexOf("let effectiveText = text;"));
  assertStringIncludes(bloco, "queueWhatsAppReply(admin, phoneNormalized, PIN_NA_MENSAGEM)");
  assert(!bloco.includes("gravarDecisaoNaConversa"), "o texto não entra na conversa");
  assert(!bloco.includes("ai_operator_messages"), "o texto não entra na conversa");
  assert(!bloco.includes("pin_attempts"), "não conta como tentativa errada");
});

// Fase 7d, correção R1 (06/11/2026): a trava do "1" da agenda. O que se protege: ela vem depois da trava do comprovante e antes da confirmação (senão o "1" aprova o
// pedido sem PIN e o "2" o rejeita); responde e volta sem mexer na pendência nem na sessão.
Deno.test("trava do 1 da agenda: depois da trava do comprovante, antes da confirmação; responde e volta sem tocar na pendência", () => {
  const chamada = turno.indexOf("await textoDaTravaDaAgenda(admin, { sessionId, phone: phoneNormalized, texto: text, citado, metadata });");
  assert(chamada > 0, "falta a trava");
  assert(turno.indexOf("textoDaTravaDoComprovante(") < chamada, "depois da trava do comprovante");
  assert(chamada < turno.indexOf("const confirmation = parseConfirmationReply(text"), "antes da confirmação");
  const bloco = turno.slice(chamada, turno.indexOf("const confirmation = parseConfirmationReply(text"));
  assertStringIncludes(bloco, "await queueWhatsAppReply(admin, phoneNormalized, travaDaAgenda);");
  // correção T3: entra na conversa antes de sair, senão o "está certo" seguinte não tem a que se referir
  const naConversa = bloco.indexOf("await gravarDecisaoNaConversa(admin, { sessionId, resposta: text, texto: travaDaAgenda });");
  assert(naConversa > 0 && naConversa < bloco.indexOf("await queueWhatsAppReply(admin, phoneNormalized, travaDaAgenda);"), "grava na conversa antes do envio");
  assertStringIncludes(bloco, 'return jr({ ok: true, travado: "agenda" });');
  assert(!bloco.includes("resolveWhatsAppConfirmation"), "não decide a pendência");
  assert(!bloco.includes("ai_operator_sessions"), "não mexe na sessão");
  assert(!bloco.includes("metadata."), "não consome nada");
  assertEquals((fonte.match(/textoDaTravaDaAgenda\(/g) ?? []).length, 1, "só no turno do WhatsApp");
});

// Retorno F3 (P8.2): o sim do ditado passa pela mesma saída de toda pendência, e o cartão guardado volta para o ponteiro.
Deno.test("Retorno F3: depois do sim do ditado, comAProximaPendencia devolve o ponteiro do cartão", () => {
  const resolver = fonte.slice(fonte.indexOf("async function resolveWhatsAppConfirmation("), fonte.indexOf("async function comAProximaPendencia("));
  assertStringIncludes(resolver, "return await comAProximaPendencia(admin, pending, message, clearedMetadata);");
  const proxima = fonte.slice(fonte.indexOf("async function comAProximaPendencia("));
  assertStringIncludes(proxima, "proximaPendenciaGuardada(admin, metadataLimpa)");
  assertStringIncludes(proxima, "pending_confirm_action_id: guardada.pendencia.id");
});

// ─── Pacote 1, C4 (25/11/2026): o rastro por mensagem recebida ────────────────────────────────────────────────────────
// O que se protege: handleWhatsAppTurn virou o envoltório e as camadas foram para tratarMensagemDoWhatsApp SEM mudar de
// ordem; o corte é fixo (o "um turno por vez", C1, vai pedir a vez no envoltório, antes das camadas); toda saída do
// envoltório deixa a rota, num ponto só, fora do caminho da resposta; o que vai para a rota são rótulos e ids, nunca o
// texto, o telefone ou o PIN; e toda saída do tratador devolve uma chave que a rota sabe ler. O que é gravado, e que a
// gravação nunca lança, é provado em _shared/ai/rota-da-mensagem_test.ts.
const inicioDoTratador = fonte.indexOf("async function tratarMensagemDoWhatsApp(");
const envoltorio = fonte.slice(inicio, inicioDoTratador);
const tratador = fonte.slice(inicioDoTratador, fim);

Deno.test("C4: o corte do envoltório — fora do tratador ficam o segredo, o corpo, o limite, o usuário, a sessão e as configurações", () => {
  assert(inicio > 0 && inicioDoTratador > inicio && inicioDoTratador < fim, "o tratador fica entre handleWhatsAppTurn e o turno do modelo");
  // fora, e nesta ordem
  const fora = [
    'Deno.env.get("AI_INTERNAL_SECRET")',
    "await req.json()",
    "await checkWhatsAppRateLimit(admin, phoneNormalized)",
    '.from("app_users")',
    "await resolveOrCreateWhatsAppSession(admin, phoneNormalized, appUserId)",
    'await admin.from("app_settings").select("key, value")',
    "await tratarMensagemDoWhatsApp({",
  ];
  let anterior = 0;
  for (const marca of fora) {
    const p = envoltorio.indexOf(marca);
    assert(p > anterior, `no envoltório, na ordem: ${marca}`);
    anterior = p;
    assert(!tratador.includes(marca), `fora do tratador: ${marca}`);
  }
  // o tratador recebe pronto o que o envoltório resolveu e não lê o pedido
  assert(!/\breq\b|\bbody\./.test(tratador), "o tratador não lê o pedido HTTP");
  assertStringIncludes(tratador, "const { admin, text, phoneNormalized, appUser, sessionId, metadata, settings, toolCtx, messageId, citado } = entrada;");
  // dentro, de depsDoRetorno em diante: é a primeira coisa que o tratador faz, antes de qualquer espera
  const primeira = tratador.indexOf("const depsRetorno = depsDoRetorno(admin, { appUser, phone: phoneNormalized, sessionId, toolCtx, texto: text, settings });");
  assert(primeira > 0, "o tratador começa por depsDoRetorno");
  assert(!tratador.slice(0, primeira).includes("await "), "nada espera antes de depsDoRetorno");
  assert(!envoltorio.includes("depsDoRetorno("), "depsDoRetorno é do tratador");
});

Deno.test("C4: as camadas ficaram na mesma ordem (retorno, travas, confirmação, PIN solto, opções, secretário, agenda, PDF, modelo)", () => {
  const ordem = [
    "await camadaDoOrcamento(text,",
    "await camadaDoParceiro(text,",
    "await camadaDoRetorno(text,",
    "await textoDaTravaDoComprovante(admin,",
    "await textoDaTravaDaAgenda(admin,",
    "const confirmation = parseConfirmationReply(text",
    "if (await pinNoTexto(text, appUser.ai_whatsapp_pin_hash)) {",
    "parseOptionReply(text, pendingOptions.length)",
    "lerComandoDoSecretario(text)",
    "await camadaDaAgenda(text, {",
    "lerPedidoDePdf(effectiveText)",
    "return await turnoDoModeloNoWhatsApp({",
  ];
  let anterior = 0;
  for (const marca of ordem) {
    const p = tratador.indexOf(marca);
    assert(p > anterior, `no tratador, na ordem: ${marca}`);
    anterior = p;
    assert(!envoltorio.includes(marca), `nenhuma camada ficou no envoltório: ${marca}`);
    assertEquals(turno.split(marca).length - 1, 1, `uma vez só: ${marca}`);
  }
});

Deno.test("C4: toda saída do envoltório deixa a rota, num ponto só, sem esperar a gravação", () => {
  const marca = envoltorio.indexOf("o rastro da mensagem ----");
  assert(marca > 0, "falta o bloco do rastro");
  // antes do bloco só saem o segredo errado e o pedido malformado: não são mensagem de ninguém
  const antes = envoltorio.slice(0, marca);
  assertEquals((antes.match(/return jr\(/g) ?? []).length, 2);
  assertStringIncludes(antes, 'return jr({ error: "Não autorizado" }, 401);');
  assertStringIncludes(antes, "}, 400);");
  // do bloco em diante, nenhuma saída escapa: ou é o `return res` de dentro do comRota, ou passa por ele
  const depois = envoltorio.slice(marca);
  const saidas = [...depois.matchAll(/\breturn ([^\r\n]*)/g)].map((m) => m[1]);
  assertEquals(saidas.length, 4);
  assertEquals(saidas[0], "res;");
  assertEquals(saidas[1], 'comRota(jr({ ok: true, skipped: "rate_limited" }));');
  assertEquals(saidas[2], 'comRota(jr({ error: "Usuário não autorizado para o canal WhatsApp" }, 403));');
  assertEquals(saidas[3], "comRota(await tratarMensagemDoWhatsApp({");
  // o turno que lança também deixa a rota (erro), e o erro sobe como sempre
  assert(/\} catch \(e\) \{\r?\n\s+comRota\(null\);[^\r\n]*\r?\n\s+throw e;\r?\n\s+\}/.test(depois), "exceção: rota e relança");
  // um ponto só grava, e ninguém espera por ele (a gravação segue no fundo, dentro de rastrearResposta)
  assertEquals((turno.match(/rastrearResposta\(/g) ?? []).length, 1);
  assert(!/await\s+(comRota|rastrearResposta)\(/.test(fonte), "a rota não fica no caminho da resposta");
  // a sessão entra na rota assim que existe
  assert(/const sessionId = await resolveOrCreateWhatsAppSession\([^\r\n]*\r?\n\s+sessaoDaRota = sessionId;/.test(depois));
});

Deno.test("C4: a rota leva ids, tempo e status — nunca o texto, o telefone, o corpo do pedido ou o usuário", () => {
  const ini = envoltorio.indexOf("rastrearResposta(admin, res, {");
  const chamada = envoltorio.slice(ini, envoltorio.indexOf("return res;", ini));
  assert(ini > 0 && chamada.length > 0, "falta a chamada");
  for (const campo of ["sessionId: sessaoDaRota,", "mensagemId: messageId,", "ms: Date.now() - inicioDoTurno,", 'status: res ? Number(res.headers.get("X-Actual-Status")) || res.status : undefined,']) {
    assertStringIncludes(chamada, campo);
  }
  assert(!/\b(text|phoneNormalized|body|citado|appUserId|appUser|metadata|settings)\b/.test(chamada), "só ids, tempo e status");
  // o tratador não sabe do rastro: quem grava é o envoltório, lendo o que sai dele
  for (const proibido of ["registrarRota", "rastrearResposta", "comRota", "noFundoDaRota", "ai_operator_audit"]) {
    assert(!tratador.includes(proibido), `o tratador não usa ${proibido}`);
  }
  // fora do envoltório, toda gravação de rota vai para o fundo (nunca com await)
  assertEquals((fonte.match(/registrarRota\(admin, /g) ?? []).length, (fonte.match(/noFundoDaRota\(registrarRota\(admin, /g) ?? []).length);
  assert(!/await\s+registrarRota\(/.test(fonte), "nenhuma rota é esperada");
});

Deno.test("C4: as quatro saídas da confirmação e a do PIN solto têm chave própria, e a rota fica fora do bloco do PIN", () => {
  // cada saída diz qual foi, logo depois do envio dela
  for (const [envia, chave] of [
    ["queueWhatsAppReply(admin, phoneNormalized, naoExecutei)", 'return jr({ ok: true, confirmacao: "recusar_ajuste" });'],
    ["queueWhatsAppReply(admin, phoneNormalized, reapresentada)", 'return jr({ ok: true, confirmacao: "reapresentada" });'],
    ["await enviarComRegistro(", 'return jr({ ok: true, confirmacao: "resolvida" });'],
    ["queueWhatsAppReply(admin, phoneNormalized, nadaEsperando)", 'return jr({ ok: true, confirmacao: "nada_esperando" });'],
  ]) {
    const e = confirmacao.indexOf(envia);
    const c = confirmacao.indexOf(chave);
    assert(e > 0 && c > e, `${chave}: depois do envio`);
    assertEquals(confirmacao.split(chave).length - 1, 1, chave);
    assert(!confirmacao.slice(e, c).includes("return "), `${chave}: é a saída daquele envio`);
  }
  assertEquals((confirmacao.match(/return jr\(/g) ?? []).length, 5, "as quatro da confirmação e a do PIN solto");
  // o PIN solto: a chave é um rótulo fixo, e o bloco continua sem gravar nada (o teste da guarda do PIN segue valendo)
  const guarda = tratador.indexOf("if (await pinNoTexto(text, appUser.ai_whatsapp_pin_hash)) {");
  const blocoDoPin = tratador.slice(guarda, tratador.indexOf("let effectiveText = text;"));
  assert(guarda > 0 && blocoDoPin.length > 0, "falta a guarda do PIN");
  assertStringIncludes(blocoDoPin, "return jr({ ok: true, pin_na_frase: true });");
  assertEquals((blocoDoPin.match(/return /g) ?? []).length, 1);
  for (const proibido of ["registrarRota", "rastrearResposta", "comRota", "ai_operator_audit", "gravarDecisaoNaConversa", "ai_operator_messages", "pin_attempts"]) {
    assert(!blocoDoPin.includes(proibido), `o bloco do PIN não usa ${proibido}`);
  }
  // nenhuma saída muda sobrou no tratador
  assert(!tratador.includes("return jr({ ok: true });"), "saída sem chave cairia na rota desconhecida");
});

Deno.test("C4: toda saída do turno do WhatsApp devolve uma chave que a rota sabe ler (nenhuma cai em 'desconhecida')", () => {
  const amostra: Record<string, unknown> = {
    skipped: "rate_limited", travado: "agenda", pin_na_frase: true, entregue: "aviso",
    session_id: "aaaaaaaa-0000-4000-8000-000000000001", claude_max: "cccccccc-0000-4000-8000-000000000003",
  };
  // as saídas do envoltório e do tratador, e as do turno do modelo (que o tratador devolve como vieram)
  const saidas = [...(turno + modeloWa + fonte.slice(fonte.indexOf("async function avisarQueOMaxNaoAtende("), fonte.indexOf("async function turnoDoModeloNoWhatsApp(")))
    .matchAll(/jr\(\{ ok: true, (\w+): /g)].map((m) => m[1]);
  const chaves = [...new Set(saidas)].sort();
  assertEquals(chaves, ["agenda", "atalho", "confirmacao", "entregue", "orcamento", "parceiro", "pin_na_frase", "retorno", "secretario", "session_id", "skipped", "travado"]);
  for (const chave of chaves) {
    const { camada } = rotaDaResposta({ ok: true, [chave]: amostra[chave] ?? "rotulo" }, 200);
    assert(camada !== "desconhecida" && camada !== "erro", `a rota não conhece a saída '${chave}'`);
  }
  // e o que o tratador põe nessas chaves é o comando da camada (um rótulo), nunca o texto que o dono mandou
  for (const m of tratador.matchAll(/return jr\(\{ ok: true, \w+: ([^}]*)\}\);/g)) {
    assert(!/\b(text|effectiveText|texto|phoneNormalized|pin)\b/.test(m[1]), `saída que levaria texto: ${m[0]}`);
  }
});

Deno.test("C4: a entrega do Claude Max deixa a rota depois de cada envio, ligada pelo pedido e sem texto", () => {
  const rotas = [...entregaDoMax.matchAll(/noFundoDaRota\(registrarRota\(admin, \{[\s\S]*?\}\)\);/g)];
  assertEquals(rotas.length, 3, "resposta do Max, aviso da causa e turno refeito");
  for (const r of rotas) {
    assertStringIncludes(r[0], 'camada: "entrega"');
    assertStringIncludes(r[0], "mensagemId: null");
    assert(/\bsessionId\b/.test(r[0]) && /\bjobId\b/.test(r[0]), "sessão e pedido");
    assert(!/\b(texto|text|phoneNormalized|replyText|resposta|respostaDoMax|avisoDaCausa|effectiveText)\b/.test(r[0]), `a rota não leva texto nem telefone: ${r[0]}`);
  }
  // 1) a resposta (ou o cartão, a lista, o fluxo, o turno que parou no meio): depois do envio com registro
  const envio = entregaDoMax.indexOf("await enviarComRegistro(");
  assert(envio > 0 && rotas[0].index! > envio && rotas[0].index! < entregaDoMax.indexOf('return jr({ ok: true, entregue: "claude_max" });'), "depois do envio, antes de voltar");
  assertStringIncludes(rotas[0][0], "detalhe: detalheDaEntrega({ interrompido: Boolean(parouNoMeio), codigo: job.error_code ?? job.status, interrupcao }),");
  // 2) o aviso da causa: depois de mandar
  const aviso = entregaDoMax.indexOf("await queueWhatsAppReply(admin, phoneNormalized, avisoDaCausa);");
  assert(aviso > 0 && rotas[1].index! > aviso && rotas[1].index! < entregaDoMax.indexOf('return jr({ ok: true, entregue: "aviso", causa: causa.codigo });'), "depois do aviso, antes de voltar");
  assertStringIncludes(rotas[1][0], 'detalhe: detalheComCodigo("aviso", causa.codigo),');
  // 3) o turno refeito: depois de ele terminar
  const refeito = entregaDoMax.indexOf("const daReserva = await turnoDoModeloNoWhatsApp({");
  assert(refeito > 0 && rotas[2].index! > refeito && rotas[2].index! < entregaDoMax.indexOf("return daReserva;"), "depois do turno refeito, antes de voltar");
  assertStringIncludes(rotas[2][0], 'detalhe: "reserva"');
  // a chave `turno` não entra na rota: trabalhoNaAuditoria lê essa chave para saber o que um pedido gravou
  assert(!/registrarRota\(admin, \{[^}]*\bturno\b/.test(fonte), "a rota não usa a chave turno");
});
