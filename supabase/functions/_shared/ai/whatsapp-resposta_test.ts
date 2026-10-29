import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ERRO_DO_SISTEMA_PARA_O_DONO, erroParaODono, LINHA_SEM_RETOMADA, respostaDoTurnoNoWhatsApp, textoAcimaDoCartao } from "./whatsapp-resposta.ts";

const antes = { pendencia_herdada: true, pending_confirm_action_id: "velha", pending_options: [{ label: "x", value: "y" }], outro: 1 };

Deno.test("texto: zera a pendência e mantém o resto do metadata", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "Pronto." }, antes);
  assertEquals(r.replyText, "Pronto.");
  assertEquals(r.metadata.pending_confirm_action_id, null);
  assertEquals(r.metadata.pendencia_herdada, false);
  assertEquals(r.metadata.outro, 1);
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "" }, {}).replyText, "Ok.");
});

Deno.test("pendência: pede confirmação e guarda o id para o SIM", () => {
  const r = respostaDoTurnoNoWhatsApp(
    { texto: "", proposal: { pending_action_id: "p1", title: "Enviar PDF ao cliente", summary_markdown: "ORÇ-00110 para Lenine", risk_level: "high" } },
    antes,
  );
  // 15/10/2026: sem ⚠️ — o ícone é dos erros e dos riscos, não de toda confirmação.
  assertEquals(r.replyText.startsWith("*Enviar PDF ao cliente*\nORÇ-00110 para Lenine"), true, r.replyText);
  assertEquals(r.replyText.includes("⚠️"), false);
  assertEquals(r.metadata.pending_confirm_action_id, "p1");
  assertEquals(r.metadata.pin_attempts, 0);
  assertEquals(r.metadata.pending_options, null);
});

Deno.test("opções: lista numerada e guarda as opções", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "", options: { question: "Qual cliente?", options: [{ label: "A", value: "1" }, { label: "B", value: "2" }] } }, {});
  assertStringIncludes(r.replyText, "Qual cliente?");
  assertEquals(r.metadata.pending_options, [{ label: "A", value: "1" }, { label: "B", value: "2" }]);
});

Deno.test("erro vem na frente de tudo — e o técnico cru não chega ao dono", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "x", error: "Falha ao chamar a Anthropic API" }, antes);
  assertEquals(r.replyText, `⚠️ ${ERRO_DO_SISTEMA_PARA_O_DONO}`);
  assertEquals(r.metadata.pending_confirm_action_id, null);
  // Erro de negócio passa como veio.
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "", error: "A cotação COT-00012 está fechada" }, {}).replyText, "⚠️ A cotação COT-00012 está fechada");
});

Deno.test("erroParaODono: marcas técnicas viram frase; mensagem de negócio passa", () => {
  for (const tecnico of [
    "Falha ao chamar a Anthropic API",
    "HTTP 530",
    'new row for relation "payments" violates check constraint "payments_status_check"',
    'column "foo" does not exist',
    "PGRST201: Could not embed",
    "TypeError: Cannot read properties of undefined",
    "fetch failed",
    "OpenRouter 429",
    "Pendência 8830f06c-1d2e-4f5a-9b8c-7d6e5f4a3b2c não encontrada",
    "",
  ]) assertEquals(erroParaODono(tecnico), ERRO_DO_SISTEMA_PARA_O_DONO, tecnico);
  for (const negocio of ["A cotação COT-00012 está fechada", "Cobrança não encontrada", "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)."]) {
    assertEquals(erroParaODono(negocio), negocio);
  }
  assertEquals(erroParaODono({ code: "23505" }), ERRO_DO_SISTEMA_PARA_O_DONO, "objeto de erro é técnico");
});

Deno.test("texto com pendência VIVA: guarda a referência e lembra dela (05/10/2026)", () => {
  const viva = { title: "Enviar orçamento/OS ao cliente (WhatsApp)", risk_level: "high" };
  const t = respostaDoTurnoNoWhatsApp({ texto: "Não consigo tirar o link desse formato." }, antes, viva);
  assertEquals(t.metadata.pending_confirm_action_id, "velha");
  assertEquals(t.metadata.pendencia_herdada, true, "sim sem PIN reapresenta em vez de executar");
  assertStringIncludes(t.replyText, "Não consigo tirar o link desse formato.");
  assertStringIncludes(t.replyText, "⏳ Ainda espera a sua resposta: *Enviar orçamento/OS ao cliente (WhatsApp)*");
  assertStringIncludes(t.replyText, "Para rejeitar: *não*");
  // Sem pendência viva (resolvida ou expirada), zera como sempre.
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "ok" }, antes, null).metadata.pending_confirm_action_id, null);
  // Pendência nova manda sobre a viva.
  const nova = respostaDoTurnoNoWhatsApp(
    { texto: "", proposal: { pending_action_id: "p2", title: "Enviar só o PDF", summary_markdown: "ORÇ-00113", risk_level: "high" } },
    antes,
    viva,
  );
  assertEquals(nova.metadata.pending_confirm_action_id, "p2");
});

Deno.test("fluxo (11/10/2026): o fluxo de comprovantes já falou — nada a enviar e as referências de pendência/opções intocadas", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "Anotei! Agora responda 8.", fluxo: { codigo: "CMP-00001" } }, antes);
  assertEquals(r.replyText, "");
  assertEquals(r.metadata.pending_confirm_action_id, "velha");
  assertEquals(r.metadata.pending_options, antes.pending_options);
  assertEquals(r.metadata.pendencia_herdada, false, "como em todo turno que passou pelo modelo");
  assertEquals(r.metadata.outro, 1);
  // com pendência viva também: o turno não a decidiu, e a mensagem é só a do fluxo
  const viva = respostaDoTurnoNoWhatsApp({ texto: "x", fluxo: { codigo: "CMP-00001" } }, antes, { title: "Enviar PDF", risk_level: "high" });
  assertEquals(viva.replyText, "");
  assertEquals(viva.metadata.pending_confirm_action_id, "velha");
  // erro e pendência nova continuam mandando
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "", error: "falhou", fluxo: { codigo: "CMP-00001" } }, antes).replyText, "⚠️ falhou");
});

// ─── Aprovação em lote, Fase 1 (29/10/2026) ──────────────────────────────────────────────────────────────────────────
// A frase do assistente vem acima do cartão (12 das 15 frases do Max que explicavam a fila nunca chegaram ao dono), com a
// linha fixa que desmente a promessa de continuar sozinho; o "Conferido pelo sistema" vem antes do cartão.
const CARTAO_2810 = {
  pending_action_id: "p1",
  title: "Cadastrar serviço",
  summary_markdown: "- Nome: Realocação do banco de baterias\n- Cobrança: por unidade\n- Preço: R$ 1.135,00",
  risk_level: "medium" as const,
};

Deno.test("cartão: a frase real do Max de 28/10 vai em cima, com a linha fixa, e o cartão embaixo", () => {
  const frase = "Pedi sua confirmação para cadastrar o primeiro dos 10 serviços no catálogo. Cada serviço pede um 'sim' seu.";
  const r = respostaDoTurnoNoWhatsApp({ texto: frase, proposal: CARTAO_2810 }, {});
  assertEquals(
    r.replyText,
    `${frase}\n${LINHA_SEM_RETOMADA}\n\n*Cadastrar serviço*\n${CARTAO_2810.summary_markdown}\n\nResponda *sim* para aprovar ou *não* para rejeitar.`,
  );
  assertEquals(r.metadata.pending_confirm_action_id, "p1");
});

Deno.test("cartão: sem frase do modelo, nada em cima (nem a linha fixa)", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "  ", proposal: CARTAO_2810 }, {});
  assertEquals(r.replyText.startsWith("*Cadastrar serviço*\n"), true, r.replyText);
  assertEquals(r.replyText.includes(LINHA_SEM_RETOMADA), false);
});

Deno.test("textoAcimaDoCartao: frase longa é cortada no fim de uma frase (ou palavra), com reticências", () => {
  const longa = "Cadastrei o primeiro. " + "Os outros oito serviços entram depois que você aprovar este, um por vez, como combinado. ".repeat(5);
  const t = textoAcimaDoCartao(longa);
  const [frase, linha] = t.split("\n");
  assertEquals(linha, LINHA_SEM_RETOMADA);
  assertEquals(frase.length <= 281, true, frase);
  assertEquals(frase.endsWith("…"), true, frase);
  assertEquals(/\s…$/.test(frase), false, "sem espaço antes das reticências");
  // no painel cabe inteira
  assertEquals(textoAcimaDoCartao(longa.trim(), 2000).split("\n")[0], longa.trim());
  assertEquals(textoAcimaDoCartao(""), "");
});

Deno.test("conferido: antes do cartão e da lista; no fim do texto e do erro", () => {
  const conferido = "⚠️ Conferido pelo sistema: 1 não entrou.\n- Remover item do orçamento/OS: Item não encontrado";
  const cartao = respostaDoTurnoNoWhatsApp({ texto: "", proposal: CARTAO_2810, conferido }, {}).replyText;
  assertEquals(cartao.startsWith(`${conferido}\n\n*Cadastrar serviço*`), true, cartao);
  const texto = respostaDoTurnoNoWhatsApp({ texto: "✅ Feito!", conferido }, {}).replyText;
  assertEquals(texto, `✅ Feito!\n\n${conferido}`);
  const erro = respostaDoTurnoNoWhatsApp({ texto: "", error: "Resposta truncada por limite de tokens.", conferido }, {}).replyText;
  assertEquals(erro.endsWith(conferido), true, erro);
  const opcoes = respostaDoTurnoNoWhatsApp({ texto: "", options: { question: "Qual?", options: [{ label: "A", value: "a" }] }, conferido }, {}).replyText;
  assertEquals(opcoes.startsWith(conferido), true, opcoes);
  // fluxo: o dono já recebeu a mensagem do fluxo — nada a enviar, nem o conferido
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "", fluxo: { codigo: "CMP-1" }, conferido }, {}).replyText, "");
});

Deno.test("aviso do turno que caiu no meio (revisão de 29/10): no topo do cartão, da lista e do texto", () => {
  const aviso = "⚠️ O assistente parou no meio desta resposta (timeout).";
  const cartao = respostaDoTurnoNoWhatsApp({ texto: "", proposal: CARTAO_2810, aviso }, {}).replyText;
  assertEquals(cartao.startsWith(`${aviso}\n\n*Cadastrar serviço*`), true, cartao);
  const lista = respostaDoTurnoNoWhatsApp({ texto: "", options: { question: "Qual cliente?", options: [{ label: "A", value: "a" }] }, aviso }, {}).replyText;
  assertEquals(lista, `${aviso}\n\nQual cliente?\n1) A`);
  // sem texto do modelo, não sai o "Ok." solto embaixo do aviso
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "", aviso }, {}).replyText, aviso);
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "", aviso, conferido: "⚠️ Conferido" }, {}).replyText, `${aviso}\n\n⚠️ Conferido`);
});
