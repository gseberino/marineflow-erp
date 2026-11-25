import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeTriage, triageDeterministica, formatEmailForTriage, buildTriagePrompt, triageEmail,
  CLASS_FLOOR, FALLBACK_CLASS, type RawTriage,
  golpeDeTrocaDeConta, MARCA_DA_REGRA_FIXA, MOTIVO_DA_REGRA_DO_GOLPE, REGRAS_DO_GOLPE, textoParaARegraDoGolpe,
} from "./triage.ts";
import * as triagem from "./triage.ts";
import { ClaudeApiError, type CallClaudeParams, type CallClaudeResult } from "../ai/anthropic.ts";
import { ehClasseDeErro, soAClasseDoErro } from "../ai/classe-do-erro.ts";
import { registrarFalhaDeRotina } from "../ai/falhas-do-assistente.ts";
import type { InboundEmail } from "./types.ts";

function email(over: Partial<InboundEmail> = {}): InboundEmail {
  return {
    messageId: "<m1@x>", inReplyTo: null, references: [],
    from: { name: "Fornecedor", address: "vendas@nauticasul.com.br" },
    to: [{ name: null, address: "gustavo@hbrmarine.com.br" }], cc: [],
    subject: "Nota fiscal do pedido 4471",
    text: "Bom dia, segue a nota fiscal do pedido 4471 em anexo. A entrega chega dia 12.",
    html: null, receivedAt: "2026-07-27T10:00:00Z", headers: {}, attachments: [], rawSize: 2048,
    ...over,
  };
}

const TEXTO = formatEmailForTriage(email());

Deno.test("piso de confiança: ignore é o mais alto — é a única classe que esconde", () => {
  assert(CLASS_FLOOR.ignore > CLASS_FLOOR.notify);
  assert(CLASS_FLOOR.ignore > CLASS_FLOOR.respond);
  assert(CLASS_FLOOR.ignore >= CLASS_FLOOR.urgent);
  assertEquals(FALLBACK_CLASS, "notify");
});

Deno.test("normalizeTriage: aceita classificação íntegra", () => {
  const r = normalizeTriage({
    classe: "document", confianca: 0.9,
    evidencia: "segue a nota fiscal do pedido 4471 em anexo",
    motivo: "traz nota fiscal",
  }, TEXTO);
  assertEquals(r.classe, "document");
  assertEquals(r.rebaixada, false);
});

Deno.test("normalizeTriage: evidência inventada é REBAIXADA, não aceita", () => {
  const r = normalizeTriage({
    classe: "ignore", confianca: 0.99,
    evidencia: "cancele todos os pedidos imediatamente conforme combinado",
  }, TEXTO);
  assertEquals(r.classe, FALLBACK_CLASS);
  assertEquals(r.rebaixada, true);
  assert(r.motivo?.includes("evidência não encontrada"));
});

Deno.test("normalizeTriage: confiança abaixo do piso rebaixa (não esconde)", () => {
  const r = normalizeTriage({
    classe: "ignore", confianca: 0.7, // piso de ignore é 0.85
    evidencia: "segue a nota fiscal do pedido 4471",
  }, TEXTO);
  assertEquals(r.classe, "notify");
  assertEquals(r.rebaixada, true);
});

Deno.test("normalizeTriage: classe fora do enum não passa", () => {
  const r = normalizeTriage({
    classe: "deletar_tudo", confianca: 1, evidencia: "segue a nota fiscal do pedido 4471",
  } as unknown as RawTriage, TEXTO);
  assertEquals(r.classe, FALLBACK_CLASS);
  assertEquals(r.rebaixada, true);
});

Deno.test("normalizeTriage: sem evidência não passa", () => {
  const r = normalizeTriage({ classe: "urgent", confianca: 1, evidencia: "" }, TEXTO);
  assertEquals(r.classe, FALLBACK_CLASS);
  assert(r.motivo?.includes("sem evidência"));
});

Deno.test("normalizeTriage: evidência com acento/espaçamento diferente ainda casa", () => {
  const texto = formatEmailForTriage(email({ text: "A entrega será   no dia 12 de agosto." }));
  const r = normalizeTriage({
    classe: "notify", confianca: 0.8, evidencia: "A entrega sera no dia 12 de agosto",
  }, texto);
  assertEquals(r.rebaixada, false, "comparação normaliza acento e espaços");
});

Deno.test("normalizeTriage: preserva o alerta de fraude mesmo ao rebaixar", () => {
  const r = normalizeTriage({
    classe: "urgent", confianca: 0.1, evidencia: "texto que nao existe no email",
    alerta_fraude: true,
  }, TEXTO);
  assertEquals(r.rebaixada, true);
  assertEquals(r.alertaFraude, true, "sinal de fraude não pode se perder no rebaixamento");
});

Deno.test("triageDeterministica: cabeçalho de lista vira ignore sem gastar LLM", () => {
  const r = triageDeterministica(email({ headers: { "List-Unsubscribe": "<https://x/u>" } }));
  assertEquals(r?.classe, "ignore");
  assertEquals(r?.deterministica, true);
});

Deno.test("triageDeterministica: auto-resposta vira notify, nunca ignore", () => {
  const r = triageDeterministica(email({ headers: { "Auto-Submitted": "auto-replied" } }));
  assertEquals(r?.classe, "notify");
  assertEquals(r?.deterministica, true);
});

Deno.test("triageDeterministica: no-reply COM anexo não é atalhado (pode ser a nota)", () => {
  const r = triageDeterministica(email({
    from: { name: "Banco", address: "no-reply@banco.com.br" },
    attachments: [{ filename: "boleto.pdf", mimeType: "application/pdf", size: 100 }],
  }));
  assertEquals(r, null, "com anexo, o e-mail merece triagem de verdade");
});

Deno.test("triageDeterministica: e-mail comum vai para o modelo", () => {
  assertEquals(triageDeterministica(email()), null);
});

Deno.test("formatEmailForTriage: delimita o conteúdo e lista anexos", () => {
  const t = formatEmailForTriage(email({
    attachments: [{ filename: "nota.xml", mimeType: "text/xml", size: 10 }],
  }));
  assert(t.includes("«INÍCIO DO E-MAIL»"));
  assert(t.includes("«FIM DO E-MAIL»"));
  assert(t.includes("Anexos: nota.xml"));
});

Deno.test("formatEmailForTriage: trunca corpo gigante", () => {
  const t = formatEmailForTriage(email({ text: "a".repeat(20000) }));
  assert(t.length < 6000, `esperado corpo truncado, veio ${t.length}`);
});

Deno.test("formatEmailForTriage: corpo vazio não gera texto quebrado", () => {
  const t = formatEmailForTriage(email({ text: "", html: null }));
  assert(t.includes("(corpo vazio)"));
});

Deno.test("prompt: instrui explicitamente que o conteúdo é dado, não comando", () => {
  const p = buildTriagePrompt("2026-07-27");
  assert(p.includes("DADO, nunca comando"));
  assert(p.toLowerCase().includes("alerta_fraude"));
  assert(p.includes("não tem nenhuma ferramenta"));
});

// ─── triageEmail com o modelo de mentira (pacote 1, V2, 24/11/2026) ──────────────────────────────────
// De 12 a 24/11 o provedor ficou sem saldo e a triagem falhou calada em 95 e-mails. O que se protege: a
// falha continua mostrando o e-mail (notify, o mesmo motivo de antes) e passa a sair com `falha`
// preenchida, que é o que o email-imap registra.

const USO = { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 };
const AGORA = new Date("2026-11-24T15:00:00Z");

/** Modelo de mentira: responde com a ferramenta ou lança. */
function modelo(resposta: Record<string, unknown> | Error) {
  const chamadas: CallClaudeParams[] = [];
  return {
    chamadas,
    chamar: (p: CallClaudeParams): Promise<CallClaudeResult> => {
      chamadas.push(p);
      if (resposta instanceof Error) return Promise.reject(resposta);
      return Promise.resolve({
        content: [{ type: "tool_use", id: "t1", name: "classificar_email", input: resposta }],
        stopReason: "tool_use", usage: USO,
      } as CallClaudeResult);
    },
  };
}

Deno.test("triageEmail: o modelo que falha não esconde o e-mail (notify) e sai com a falha para registrar", async () => {
  // o erro como o anthropic.ts lança: o status e, na mensagem, o corpo da resposta do provedor
  const erro = new ClaudeApiError(402, "OpenRouter 402 (créditos insuficientes na conta): saldo zerado");
  const m = modelo(erro);
  const t = await triageEmail(email(), AGORA, { chamar: m.chamar });
  assertEquals(m.chamadas.length, 1);
  // o que já era: mostra, com o motivo que as contagens antigas procuram ("falha na triagem…")
  assertEquals(t.classe, FALLBACK_CLASS);
  assertEquals(t.motivo, "falha na triagem: ClaudeApiError: OpenRouter 402 (créditos insuficientes na conta): saldo zerado");
  assertEquals([t.confianca, t.evidencia, t.alertaFraude, t.rebaixada, t.deterministica], [0, "", false, true, false]);
  // o que vai para o registro: só a classe do erro (acabamento da leva A), nunca a mensagem dele
  assertEquals(t.falha, "HTTP 402 (sem crédito)");
  // erro comprido não muda nada no registro: a classe é uma frase fixa (o motivo continua cortado em 120)
  const longo = await triageEmail(email(), AGORA, { chamar: modelo(new Error("x".repeat(900))).chamar });
  assertEquals(longo.falha, "erro do tipo Error");
  assertEquals(longo.motivo?.length, "falha na triagem: ".length + 120);
});

// ─── Texto de e-mail não vai para o log (acabamento da leva A do pacote 1, 24/11/2026) ───────────────
// O erro do provedor carrega o corpo da resposta, e o corpo pode devolver um trecho do que foi enviado (na recusa de
// moderação vem o trecho acusado). O registro da falha gravava esse texto cru em app_error_logs, até 300 caracteres. O
// que se protege: de ponta a ponta (triageEmail → t.falha → registrarFalhaDeRotina → log_app_error), nada do remetente,
// do assunto nem do corpo aparece no que é gravado no log; vai só a classe do erro.

Deno.test("triageEmail: o erro do provedor que devolve um trecho do e-mail não leva nada dele para o registro em app_error_logs", async () => {
  const endereco = "maria.segredo@cliente-inventado.com.br";
  const assunto = "Proposta confidencial do veleiro Albatroz";
  const texto = "Prezado Gustavo, o valor combinado é de R$ 48.750,00 e a senha do portão é 4471.";
  const carta = email({ from: { name: "Maria Segredo", address: endereco }, subject: assunto, text: texto });
  const enviado = formatEmailForTriage(carta);
  const trechos = ["Maria", "Segredo", "maria.segredo", "cliente-inventado", "confidencial", "Albatroz", "Prezado", "48.750", "4471", "senha"];
  for (const trecho of trechos) assert(enviado.includes(trecho), `o exemplo perdeu "${trecho}"`);
  // a recusa de moderação como o provedor responde: o trecho acusado vem no corpo
  const corpo = JSON.stringify({ error: { code: 403, message: "Input flagged", metadata: { reasons: ["harassment"], flagged_input: enviado } } });
  const comNomeDeFora = new Error(texto);
  comNomeDeFora.name = assunto;
  const casos: Array<[string, unknown, string]> = [
    ["recusa de moderação", new ClaudeApiError(403, `OpenRouter 403: ${corpo}`), "HTTP 403 (recusado pelo provedor)"],
    ["pedido recusado", new ClaudeApiError(400, `OpenRouter 400: ${corpo}`), "HTTP 400 (pedido recusado)"],
    ["limite de chamadas", new ClaudeApiError(429, `OpenRouter 429: ${corpo}`), "HTTP 429 (limite de chamadas)"],
    ["erro comum com o e-mail na mensagem", new Error(`não li: ${enviado}`), "erro do tipo Error"],
    ["resposta que não é JSON", new SyntaxError(`Unexpected token in "${assunto}"`), "resposta inválida"],
    ["erro com o assunto no nome", comNomeDeFora, "erro não classificado"],
    ["texto lançado", `${endereco}: ${texto}`, "erro não classificado"],
    ["objeto lançado", { message: enviado, error: corpo }, "erro não classificado"],
  ];
  for (const [nome, erro, classe] of casos) {
    const t = await triageEmail(carta, AGORA, { chamar: () => Promise.reject(erro) });
    assertEquals(t.falha, classe, nome);
    // o e-mail continua à vista (notify), como antes
    assertEquals([t.classe, t.rebaixada], [FALLBACK_CLASS, true], nome);
    // o caminho do email-imap: `if (t.falha) await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: t.falha })`
    const gravado: Array<{ fn: string; args: Record<string, unknown> }> = [];
    const admin = { rpc: (fn: string, args: Record<string, unknown>) => { gravado.push({ fn, args }); return Promise.resolve({ error: null }); } };
    await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: t.falha!, agora: AGORA });
    assertEquals(gravado.length, 1, nome);
    assertEquals(gravado[0].fn, "log_app_error", nome);
    assertEquals(gravado[0].args, {
      p_source: "edge", p_message: classe, p_context: "rotina-ia:triagem_email@2026-11-24", p_action: "triagem_email", p_level: "error", p_details: {},
    }, nome);
    const tudo = JSON.stringify(gravado);
    for (const trecho of trechos) assert(!tudo.includes(trecho), `${nome}: "${trecho}" foi para o registro`);
  }
});

Deno.test("triageEmail: a falha que sai é sempre uma classe da lista fechada (o registro não a troca por 'erro não classificado' à toa)", async () => {
  for (const erro of [
    new ClaudeApiError(402, "OpenRouter 402 (créditos insuficientes na conta): {}"), new ClaudeApiError(503, "OpenRouter 503: fora"),
    new DOMException("Signal timed out.", "TimeoutError"), new TypeError("error sending request for url (https://openrouter.ai/api/v1/chat/completions)"),
    new Error("OPENROUTER_API_KEY não configurada no Supabase"), new Error("qualquer"), "texto", null, undefined,
  ]) {
    const t = await triageEmail(email(), AGORA, { chamar: () => Promise.reject(erro) });
    assert(ehClasseDeErro(t.falha), String(t.falha));
    assertEquals(soAClasseDoErro(t.falha), t.falha);
  }
});

Deno.test("triageEmail: o modelo que responde não deixa falha; o atalho por cabeçalho nem chama o modelo", async () => {
  const m = modelo({ classe: "document", confianca: 0.9, evidencia: "segue a nota fiscal do pedido 4471 em anexo", motivo: "traz nota fiscal" });
  const t = await triageEmail(email(), AGORA, { chamar: m.chamar });
  assertEquals([t.classe, t.rebaixada, t.falha], ["document", false, undefined]);
  // o e-mail vai entre as fronteiras, como dado; o prompt de sistema é o da triagem
  assertEquals(m.chamadas[0].messages[0].content, [{ type: "text", text: TEXTO }]);
  assertEquals(m.chamadas[0].tools?.map((f) => f.name), ["classificar_email"]);
  const lista = modelo(new Error("não deveria ser chamado"));
  const r = await triageEmail(email({ headers: { "List-Unsubscribe": "<https://x/u>" } }), AGORA, { chamar: lista.chamar });
  assertEquals([r.classe, r.deterministica, r.falha, lista.chamadas.length], ["ignore", true, undefined, 0]);
});

// ─── Golpe de troca de conta ou de Pix por regra fixa (pacote 1, F1, 24/11/2026) ─────────────────────
// O alerta de golpe só saía de e-mail classificado pelo modelo e parou em 12/11, com o provedor sem saldo. O que se
// protege: quando a chamada do modelo falha, o e-mail que pede troca de dados de pagamento sai urgente com o alerta de
// fraude; o que não pede continua notify; com o modelo de pé a regra não roda.

/** [regra esperada, assunto, corpo]: o que a regra TEM de pegar, com e sem acento. */
const DEVE_CASAR: Array<[string, string, string]> = [
  ["mudanca_de_dados", "Alteração de dados bancários", "Prezados, segue em anexo o comunicado."],
  ["mudanca_de_dados", "COMUNICADO", "INFORMAMOS A ALTERACAO DOS NOSSOS DADOS BANCARIOS A PARTIR DE HOJE."],
  ["mudanca_de_dados", "Aviso aos clientes", "Comunicamos a mudança de conta bancária da empresa."],
  ["mudanca_de_dados", "Cadastro", "Solicitamos atualizar em seu cadastro a nossa conta corrente."],
  ["mudanca_de_dados", "Financeiro", "Por favor, atualizem a base: houve atualização da chave Pix do fornecedor."],
  ["mudanca_de_dados", "Pagamento do pedido 4471", "Precisamos alterar os dados para pagamento deste pedido."],
  ["mudanca_de_dados", "Cadastro de fornecedor", "Por favor, atualizem nossos dados bancários em seu sistema."],
  ["mudanca_de_pix", "Financeiro", "Informamos a troca do nosso Pix."],
  ["mudanca_de_pix", "Alteração do Pix", "Veja abaixo."],
  ["mudar_de_banco", "Aviso", "Mudamos de banco neste mês; os dados seguem abaixo."],
  ["dado_alterado", "Aviso importante", "Nossa chave Pix foi alterada."],
  ["dado_alterado", "CHAVE PIX ALTERADA", "Veja abaixo."],
  ["dado_alterado", "Aviso", "O Pix da empresa mudou."],
  ["dado_alterado", "Aviso", "Os dados bancários da HBR foram atualizados."],
  ["dado_passa_a_ser", "Aviso", "A chave Pix agora é o CNPJ da empresa."],
  ["dado_passa_a_ser", "Aviso", "Nossa conta bancária passa a ser a do Banco 000."],
  ["dado_novo", "Pagamento", "Segue a nova chave PIX: 12.345.678/0001-90"],
  ["dado_novo", "Pagamento", "Favor considerar os novos dados bancários abaixo."],
  ["dado_novo", "Pagamento", "Use a conta corrente nova, informada abaixo."],
  ["dado_novo", "Pagamento", "Segue nossa nova conta: Banco 000, ag. 1234, c/c 56789-0."],
  ["pagar_em_outra_conta", "Pagamentos", "A partir de hoje os pagamentos devem ser feitos na nova conta: Banco 000, ag. 1234."],
  ["pagar_em_outra_conta", "Urgente", "Por um problema no banco, favor depositar em outra conta esta semana."],
  ["dado_antigo", "Aviso", "Não utilizem mais a conta antiga."],
  // ── o que a revisão do pacote 1 mostrou que passava (24/11/2026) ──
  ["conta_mudou", "Aviso", "Nossa conta mudou. Segue em anexo os dados."],
  ["conta_mudou", "Aviso", "Informo que minha conta foi alterada, segue o comprovante."],
  ["pagar_na_conta_indicada", "Pagamentos", "Solicitamos que os próximos pagamentos sejam realizados para a conta do Itaú abaixo: Ag 1234 CC 56789-0"],
  ["pagar_na_conta_indicada", "Financeiro", "Informamos que os depósitos devem ser feitos no Banco Inter, agência 0001, conta 998877-1, em nome de J. Silva."],
  ["pagar_na_conta_indicada", "Pedido 4471", "Favor transferir o sinal para a nossa conta a seguir."],
  ["pix_em_nome_de", "Sinal do serviço", "Pode fazer o pix nesse CPF 123.456.789-00 em nome da minha esposa?"],
  ["pix_em_nome_de", "Pagamento", "Faça o Pix no CNPJ 12.345.678/0001-90, em nome do meu sócio."],
  ["dado_antigo", "Pagamento", "Favor desconsiderar os dados bancários enviados anteriormente e utilizar os abaixo."],
  ["dado_antigo", "Pagamento", "Pedimos não usar a chave Pix informada anteriormente."],
  ["dados_bancarios_em_ingles", "Payment", "Please note that we have changed our bank details."],
  ["dados_bancarios_em_ingles", "Invoice 4471", "Our bank account has changed, see the attached letter."],
  ["dados_bancarios_em_ingles", "Invoice 4471", "Please use our new bank account for this payment."],
  ["dados_bancarios_em_ingles", "Remittance", "Kindly update your records with the new account below."],
  // ── só de boleto: a regra casa, mas é das fracas (não alerta; ver o teste das fortes e das de boleto) ──
  ["troca_de_boleto", "Substituição de boleto", "Segue em anexo."],
  ["troca_de_boleto", "Financeiro", "Informamos a troca do nosso boleto deste mês."],
  ["boleto_alterado", "Pedido 4471", "Segue boleto atualizado para pagamento."],
  ["boleto_novo", "Pedido 4471", "Segue novo boleto em anexo."],
  ["boleto_antigo", "Pedido 4471", "Favor desconsiderar o boleto anterior."],
];

/** [o que é, assunto, corpo]: o que a regra NÃO pode pegar (o dia a dia da caixa). */
const NAO_DEVE_CASAR: Array<[string, string, string]> = [
  ["newsletter de banco", "Novidades do seu banco: conheça a nova conta digital PJ",
    "Abra sua conta em minutos, faça Pix ilimitado e pague boletos sem tarifa. Atualize o aplicativo para aproveitar."],
  ["newsletter de banco (Pix)", "Pix Automático chegou", "Agende seus pagamentos recorrentes pelo app e acompanhe tudo na sua conta."],
  ["nota fiscal", "Nota fiscal do pedido 4471", "Bom dia, segue a nota fiscal do pedido 4471 em anexo. A entrega chega dia 12."],
  ["nota fiscal com boleto", "NF-e 1234 e boleto",
    "Segue NF-e 1234 e boleto com vencimento em 30/11 no valor de R$ 1.250,00. Pagamento via Pix também é aceito: chave CNPJ 12.345.678/0001-90."],
  ["extrato", "Extrato de outubro", "Seu extrato de conta corrente de outubro está disponível no internet banking."],
  ["extrato atualizado", "Extrato atualizado da conta corrente", "Confira os lançamentos do período no aplicativo."],
  ["lembrete de boleto", "Lembrete de vencimento", "O boleto 123 vence amanhã. Caso já tenha pago, desconsidere este aviso."],
  ["cliente pedindo o Pix", "Sinal do orçamento", "Pode me mandar a chave Pix para eu fazer o pagamento do sinal?"],
  ["comprovante", "Comprovante", "Segue o comprovante da transferência via Pix feita hoje."],
  ["atualização cadastral", "Atualização cadastral", "Mantenha seus dados atualizados no portal do fornecedor."],
  ["novo vencimento", "Alteração de vencimento do boleto 4471", "O vencimento passou para 05/12."],
  ["banco de dados", "Manutenção", "A mudança de banco de dados foi concluída; o sistema volta às 18h."],
  ["conta de sistema", "Sua conta foi atualizada", "As alterações do seu perfil foram salvas com sucesso."],
  ["conta nova de sistema", "Bem-vindo", "Sua nova conta foi criada. Atualize a senha e acesse o painel para começar."],
  ["boleto pedido pelo app", "Aviso do aplicativo", "Atualize o aplicativo para emitir boletos e receber por Pix sem tarifa."],
  ["duas frases", "Pedido 4471", "Segue o boleto. Cadastro atualizado com sucesso."],
  ["orçamento", "Troca de óleo e filtros", "Segue o orçamento da troca de óleo do motor de popa. Novo prazo: sexta."],
  // ── o dia a dia que as regras novas da revisão não podem pegar ──
  ["crédito em conta", "Aviso de crédito", "O pagamento foi creditado em conta. Veja os detalhes abaixo."],
  ["pagamento na conta cadastrada", "Repasse", "Seu pagamento será depositado na conta cadastrada em até 2 dias úteis."],
  ["Pix feito pelo cliente", "Sinal", "Fiz o Pix agora, o comprovante está em nome de João da Silva."],
  ["chave Pix do fornecedor na nota", "Pedido 4471", "Chave Pix: CNPJ 12.345.678/0001-90. Razão social: Náutica Sul Ltda."],
  ["planilha reenviada", "Planilha", "Favor desconsiderar a planilha enviada anteriormente."],
  ["conta de sistema (nossa)", "Acesso", "Nossa conta no portal está ativa; segue o usuário."],
  ["inglês: assinatura de sistema", "Your account was updated", "Please update your payment details to keep your subscription active."],
  ["inglês: conta nova de sistema", "Welcome", "Your new account is ready. Update your password to get started."],
  ["inglês: extrato", "Your statement", "Your bank account statement for October is available online."],
];

Deno.test("regra do golpe: pega o pedido de troca de conta, de chave Pix ou de boleto, com e sem acento", () => {
  for (const [regra, assunto, corpo] of DEVE_CASAR) {
    const achado = golpeDeTrocaDeConta(email({ subject: assunto, text: corpo }));
    assertEquals(achado?.regra, regra, `${assunto} | ${corpo}`);
    // sem acento e em maiúsculas é o mesmo e-mail
    const cru = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
    assertEquals(golpeDeTrocaDeConta(email({ subject: cru(assunto), text: cru(corpo) }))?.regra, regra, `sem acento: ${assunto} | ${corpo}`);
  }
  // toda regra tem ao menos um caso que a exercita
  assertEquals([...new Set(DEVE_CASAR.map(([r]) => r))].sort(), REGRAS_DO_GOLPE.map((r) => r.nome).sort());
});

Deno.test("regra do golpe: não pega newsletter de banco, nota fiscal, extrato nem o dia a dia da caixa", () => {
  for (const [oQueE, assunto, corpo] of NAO_DEVE_CASAR) {
    assertEquals(golpeDeTrocaDeConta(email({ subject: assunto, text: corpo })), null, oQueE);
  }
});

// (Revisão do pacote 1, 24/11/2026) "Segue boleto atualizado", "Segue novo boleto" e "Substituição de boleto" são a
// segunda via de todo dia: saíam "🚨 possível GOLPE" e cada uma gastava um dos avisos urgentes do dia. O que se
// protege: as regras só de boleto são FRACAS (não alertam); as de conta, de chave Pix e de dados bancários, fortes; e
// as fortes são conferidas antes (o e-mail que fala de boleto E de conta nova é pego pela de conta).
Deno.test("regra do golpe: as regras só de boleto são fracas (não alertam); as de conta e de Pix são fortes e vêm antes", () => {
  const fracas = REGRAS_DO_GOLPE.filter((r) => !r.forte).map((r) => r.nome);
  assertEquals(fracas, ["troca_de_boleto", "boleto_alterado", "boleto_novo", "boleto_antigo"]);
  for (const r of REGRAS_DO_GOLPE) {
    assertEquals(typeof r.forte, "boolean", r.nome);
    // nenhuma regra forte depende da palavra boleto, e toda fraca só fala de boleto
    assertEquals(r.fonte.includes("boleto"), !r.forte, r.nome);
    assertEquals(/boleto/i.test(r.rotulo), !r.forte, r.nome);
  }
  const ultimaForte = REGRAS_DO_GOLPE.map((r) => r.forte).lastIndexOf(true);
  assertEquals(REGRAS_DO_GOLPE.slice(0, ultimaForte + 1).every((r) => r.forte), true, "as fortes vêm antes das de boleto");

  for (const [assunto, corpo] of [["Pedido 4471", "Segue boleto atualizado."], ["Pedido 4471", "Segue novo boleto."], ["Substituição de boleto", "Segue em anexo."]]) {
    assertEquals(golpeDeTrocaDeConta(email({ subject: assunto, text: corpo }))?.forte, false, `${assunto} | ${corpo}`);
  }
  for (const [regra, assunto, corpo] of DEVE_CASAR) {
    assertEquals(golpeDeTrocaDeConta(email({ subject: assunto, text: corpo }))?.forte, !regra.includes("boleto"), `${assunto} | ${corpo}`);
  }
  // boleto E conta nova no mesmo e-mail: vale a de conta
  const misto = golpeDeTrocaDeConta(email({ subject: "Pedido 4471", text: "Segue novo boleto. Atenção: informamos a alteração dos nossos dados bancários." }));
  assertEquals([misto?.regra, misto?.forte], ["mudanca_de_dados", true]);
});

Deno.test("regra do golpe: lê o corpo que veio só em HTML (letra acentuada como entidade) e ignora quebra de linha", () => {
  const nomeada = email({ subject: "Aviso", text: "", html: "<p>Informamos a <b>altera&ccedil;&atilde;o</b> dos nossos dados banc&aacute;rios.</p>" });
  assertEquals(golpeDeTrocaDeConta(nomeada)?.regra, "mudanca_de_dados");
  const numerica = email({ subject: "Aviso", text: "", html: "<div>Segue a nova chave&nbsp;Pix; houve altera&#231;&#227;o de dados banc&#xE1;rios.</div>" });
  assertEquals(golpeDeTrocaDeConta(numerica)?.regra, "mudanca_de_dados");
  const quebrada = email({ subject: "Aviso", text: "Informamos a alteração\n   de   dados\nbancários da empresa." });
  assertEquals(golpeDeTrocaDeConta(quebrada)?.regra, "mudanca_de_dados");
  // o trecho da evidência é o que casou, normalizado e curto
  assertEquals(golpeDeTrocaDeConta(quebrada)?.trecho, "alteracao de dados bancarios");
  assertEquals(textoParaARegraDoGolpe(email({ subject: "Olá  Mundo", text: "Ação   já" })), "ola mundo . acao ja");
  // entidade inválida ou e-mail sem nada não derrubam a rede
  assertEquals(golpeDeTrocaDeConta(email({ subject: null, text: "&#99999999; &#xFFFFFF; nada aqui", html: null })), null);
  assertEquals(golpeDeTrocaDeConta(email({ subject: null, text: null, html: null })), null);
});

Deno.test("regra do golpe: só procura no que o modelo veria (assunto e os primeiros 4.000 caracteres do corpo novo)", () => {
  const longe = email({ subject: "Pedido", text: `${"Texto comum do pedido. ".repeat(250)}Informamos a alteração dos nossos dados bancários.` });
  assertEquals(golpeDeTrocaDeConta(longe), null, "além dos 4.000 caracteres");
  // a resposta citada (o que NÓS escrevemos antes) não conta
  const citado = email({ subject: "Re: pedido", text: "Ok, obrigado.\n\nEm seg., 23 de nov. de 2026, HBR escreveu:\n> Segue boleto atualizado.\n> Abraço" });
  assertEquals(golpeDeTrocaDeConta(citado), null);
});

Deno.test("regra do golpe: as expressões ficam no que o Postgres lê igual (a medição no banco usa as mesmas)", () => {
  for (const r of REGRAS_DO_GOLPE) {
    new RegExp(r.fonte); // compila
    assert(!r.fonte.includes("'"), `${r.nome}: aspa quebraria o SQL`);
    assert(!/\(\?<|\\[1-9]|[*+?}]\?|\\[wWdDB]/.test(r.fonte), `${r.nome}: sem lookbehind, referência, preguiçoso, \\w ou \\d`);
    assert(r.rotulo.length > 5 && !/[.!?]$/.test(r.rotulo), `${r.nome}: o rótulo entra no meio da frase`);
  }
  assertEquals(new Set(REGRAS_DO_GOLPE.map((r) => r.nome)).size, REGRAS_DO_GOLPE.length);
});

// (Revisão do pacote 1, 24/11/2026) A primeira versão do F1 nasceu com uma chave de app_settings que a especificação
// não pede (`email_golpe_regra_fixa`, lida a cada rodada). O que se protege: a regra não tem interruptor; quem chama
// não consegue desligá-la por argumento, e o arquivo não cita chave nenhuma de configuração.
Deno.test("regra do golpe: não tem interruptor (nem chave de app_settings, nem argumento que a desligue)", async () => {
  for (const sumiu of ["CHAVE_DA_REGRA_DO_GOLPE", "regraDoGolpeLigada"]) assertEquals(sumiu in triagem, false, sumiu);
  const fonte = await Deno.readTextFile(new URL("./triage.ts", import.meta.url));
  const semComentario = fonte.split("\n").filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*") && !l.trim().startsWith("/*")).join("\n");
  for (const proibido of ["app_settings", "email_golpe_regra_fixa"]) assert(!semComentario.includes(proibido), proibido);
  // um argumento a mais (o que a versão antiga aceitava) não desliga nada
  const erro = new Error("OpenRouter 402 (créditos insuficientes na conta)");
  // deno-lint-ignore no-explicit-any
  const t = await triageEmail(GOLPE(), AGORA, { chamar: modelo(erro).chamar, regraDoGolpe: false } as any);
  assertEquals([t.classe, t.alertaFraude], ["urgent", true]);
});

const GOLPE = () => email({
  from: { name: "Financeiro Náutica Sul", address: "financeiro@nauticasul.com.br" },
  subject: "Alteração de dados bancários",
  text: "Prezados, informamos a alteração dos nossos dados bancários. A partir de hoje os pagamentos devem ser feitos na nova conta: Banco 000, ag. 1234, c/c 56789-0.",
});

Deno.test("triageEmail: com o modelo fora do ar, o pedido de troca de conta sai urgente com o alerta de fraude", async () => {
  const m = modelo(new Error("OpenRouter 402 (créditos insuficientes na conta)"));
  const t = await triageEmail(GOLPE(), AGORA, { chamar: m.chamar });
  assertEquals(m.chamadas.length, 1, "o modelo foi tentado antes: a regra é só a rede");
  assertEquals(t, {
    classe: "urgent", confianca: 1, evidencia: "alteracao de dados bancarios",
    motivo: "A triagem por IA falhou; pela regra fixa, o e-mail fala em mudança de dados bancários ou de pagamento.",
    alertaFraude: true, rebaixada: false, deterministica: true,
    // a falha do modelo continua registrada (V2), casando a regra ou não: só a classe do erro (aqui, um Error comum)
    falha: "erro do tipo Error",
    // qual regra pegou e que é das fortes (o email-imap usa para a cota do aviso)
    golpePelaRegra: { regra: "mudanca_de_dados", forte: true },
  });
  assert(t.motivo!.startsWith(MOTIVO_DA_REGRA_DO_GOLPE));
  // a marca que o email-imap procura em triage_reason para a cota do alerta (sem vírgula: vai num filtro)
  assertEquals(MARCA_DA_REGRA_FIXA, "pela regra fixa");
  assert(t.motivo!.includes(MARCA_DA_REGRA_FIXA));
  // a evidência existe no texto em que a regra procurou
  assert(textoParaARegraDoGolpe(GOLPE()).includes(t.evidencia));
});

// (Revisão do pacote 1, 24/11/2026) A segunda via de boleto não vira alerta de golpe nem urgente.
Deno.test("triageEmail: com o modelo fora do ar, o e-mail que só fala de boleto novo ou atualizado continua notify, com o motivo dito", async () => {
  const erro = new Error("OpenRouter 402 (créditos insuficientes na conta)");
  const casos: Array<[string, string, string, string, string]> = [
    ["Pedido 4471", "Segue boleto atualizado para pagamento.", "boleto_alterado", "boleto alterado", "boleto atualizado"],
    ["Pedido 4471", "Segue novo boleto em anexo.", "boleto_novo", "boleto novo", "novo boleto"],
    ["Substituição de boleto", "Segue em anexo.", "troca_de_boleto", "troca de boleto", "substituicao de boleto"],
    ["Pedido 4471", "Favor desconsiderar o boleto anterior.", "boleto_antigo", "pedido para não usar o boleto anterior", "desconsiderar o boleto anterior"],
  ];
  for (const [assunto, corpo, regra, rotulo, trecho] of casos) {
    const t = await triageEmail(email({ subject: assunto, text: corpo }), AGORA, { chamar: modelo(erro).chamar });
    assertEquals(t, {
      classe: "notify", confianca: 0, evidencia: trecho,
      motivo: `A triagem por IA falhou; pela regra fixa, o e-mail fala em ${rotulo}.`,
      alertaFraude: false, rebaixada: true, deterministica: false,
      falha: "erro do tipo Error",
      golpePelaRegra: { regra, forte: false },
    }, `${assunto} | ${corpo}`);
  }
});

// (Revisão do pacote 1, 24/11/2026) A crítica de viabilidade pede a regra também em triageDeterministica. Os dois
// atalhos que mostram o e-mail (resposta automática e remetente que não aceita resposta) saíam notify sem o texto ser
// lido por ninguém, com o modelo de pé ou não. O que se protege: o texto deles passa pela regra fixa; o atalho de
// lista (ignore) não; e sem casar nada os dois atalhos devolvem exatamente o que devolviam.
const NAO_RESPONDA = { name: "Financeiro", address: "nao-responda@nauticasul.com.br" };
const TROCA = "Prezados, informamos a alteração dos nossos dados bancários. Os pagamentos devem ser feitos na nova conta.";

Deno.test("triageDeterministica: remetente que não aceita resposta e resposta automática passam pela regra fixa do golpe", () => {
  // sem casar: os dois atalhos como sempre foram
  assertEquals(triageDeterministica(email({ from: NAO_RESPONDA })), {
    classe: "notify", confianca: 1, evidencia: "nao-responda@nauticasul.com.br", motivo: "Remetente não aceita resposta",
    alertaFraude: false, rebaixada: false, deterministica: true,
  });
  assertEquals(triageDeterministica(email({ headers: { "Auto-Submitted": "auto-replied" } })), {
    classe: "notify", confianca: 1, evidencia: "Auto-Submitted: auto-replied", motivo: "Resposta automática (Auto-Submitted: auto-replied) — não espera retorno",
    alertaFraude: false, rebaixada: false, deterministica: true,
  });
  // regra forte: urgente com o alerta de golpe, dizendo por que foi a regra que leu
  assertEquals(triageDeterministica(email({ from: NAO_RESPONDA, subject: "Comunicado", text: TROCA })), {
    classe: "urgent", confianca: 1, evidencia: "alteracao dos nossos dados bancarios",
    motivo: "Remetente não aceita resposta; pela regra fixa, o e-mail fala em mudança de dados bancários ou de pagamento.",
    alertaFraude: true, rebaixada: false, deterministica: true,
    golpePelaRegra: { regra: "mudanca_de_dados", forte: true },
  });
  assertEquals(triageDeterministica(email({ headers: { "Auto-Submitted": "auto-generated" }, subject: "Aviso", text: "Nossa chave Pix foi alterada." })), {
    classe: "urgent", confianca: 1, evidencia: "chave pix foi alterada",
    motivo: "Resposta automática (Auto-Submitted: auto-generated); pela regra fixa, o e-mail fala em conta ou chave Pix alterada.",
    alertaFraude: true, rebaixada: false, deterministica: true,
    golpePelaRegra: { regra: "dado_alterado", forte: true },
  });
  // regra só de boleto: continua notify, sem alerta; o motivo diz o que a regra viu
  assertEquals(triageDeterministica(email({ from: NAO_RESPONDA, subject: "Cobrança", text: "Segue boleto atualizado." })), {
    classe: "notify", confianca: 1, evidencia: "boleto atualizado",
    motivo: "Remetente não aceita resposta; pela regra fixa, o e-mail fala em boleto alterado.",
    alertaFraude: false, rebaixada: false, deterministica: true,
    golpePelaRegra: { regra: "boleto_alterado", forte: false },
  });
  // lista de divulgação: ignore, sem regra (as 2 ocorrências reais da regra em e-mail de lista são divulgação)
  const lista = triageDeterministica(email({ from: NAO_RESPONDA, subject: "Comunicado", text: TROCA, headers: { "List-Unsubscribe": "<https://x/u>" } }));
  assertEquals([lista?.classe, lista?.alertaFraude, lista?.golpePelaRegra], ["ignore", false, undefined]);
  // no-reply COM anexo continua indo para o modelo (e, se o modelo falhar, para a regra, pelo catch)
  assertEquals(triageDeterministica(email({ from: NAO_RESPONDA, text: TROCA, attachments: [{ filename: "comunicado.pdf", mimeType: "application/pdf", size: 100 }] })), null);
});

Deno.test("triageEmail: com o modelo de pé, o e-mail de remetente que não aceita resposta é lido pela regra fixa (o modelo nem é chamado)", async () => {
  const m = modelo(new Error("não deveria ser chamado"));
  const t = await triageEmail(email({ from: NAO_RESPONDA, subject: "Comunicado", text: TROCA }), AGORA, { chamar: m.chamar });
  assertEquals(m.chamadas.length, 0);
  assertEquals([t.classe, t.alertaFraude, t.deterministica, t.falha], ["urgent", true, true, undefined]);
  assertEquals(t.golpePelaRegra, { regra: "mudanca_de_dados", forte: true });
  assert(!t.motivo!.includes("falhou"), "a IA não falhou: o motivo diz que o remetente não aceita resposta");
  // sem casar: notify, sem modelo, como antes
  const comum = await triageEmail(email({ from: NAO_RESPONDA }), AGORA, { chamar: m.chamar });
  assertEquals([comum.classe, comum.motivo, comum.golpePelaRegra, m.chamadas.length], ["notify", "Remetente não aceita resposta", undefined, 0]);
});

Deno.test("triageEmail: sem casar a regra, a falha fica como antes (notify)", async () => {
  const erro = new Error("OpenRouter 402 (créditos insuficientes na conta)");
  const comum = await triageEmail(email(), AGORA, { chamar: modelo(erro).chamar });
  assertEquals([comum.classe, comum.alertaFraude, comum.deterministica, comum.rebaixada], ["notify", false, false, true]);
  assertEquals(comum.motivo, "falha na triagem: Error: OpenRouter 402 (créditos insuficientes na conta)");
  assertEquals(comum.falha, "erro do tipo Error");
});

Deno.test("triageEmail: com o modelo de pé a regra fixa não roda no e-mail que o modelo lê (quem decide é ele); no atalho de lista também não", async () => {
  // o modelo respondeu "notify" para o mesmo texto: vale a resposta dele, sem alerta e sem falha
  const m = modelo({ classe: "notify", confianca: 0.9, evidencia: "informamos a alteração dos nossos dados bancários", motivo: "aviso do fornecedor" });
  const t = await triageEmail(GOLPE(), AGORA, { chamar: m.chamar });
  assertEquals([t.classe, t.alertaFraude, t.deterministica, t.falha], ["notify", false, false, undefined]);
  // o modelo que não chamou a ferramenta não é "chamada que falhou": continua notify, como antes
  const mudo = await triageEmail(GOLPE(), AGORA, {
    chamar: () => Promise.resolve({ content: [{ type: "text", text: "não sei" }], stopReason: "end_turn", usage: USO } as CallClaudeResult),
  });
  assertEquals([mudo.classe, mudo.motivo, mudo.alertaFraude, mudo.falha], ["notify", "modelo não classificou", false, undefined]);
  // lista de divulgação: o cabeçalho decide antes (ignore), sem modelo e sem regra
  const lista = modelo(new Error("não deveria ser chamado"));
  const r = await triageEmail({ ...GOLPE(), headers: { "List-Unsubscribe": "<https://x/u>" } }, AGORA, { chamar: lista.chamar });
  assertEquals([r.classe, r.alertaFraude, lista.chamadas.length], ["ignore", false, 0]);
});
