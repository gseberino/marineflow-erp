// O leitor da resposta do cliente (Agenda de Produção, Fase 5, P4 — 27/10/2026, spec-fase5 §5.4 e §8.4) e a garantia de
// que o classificador de hoje (classificarResposta: o fornecedor, a cobrança, o "fecha o loop" do webhook) ficou byte a
// byte igual. O corpus abaixo foi gerado com a versão de antes do P4 (HEAD 8b58b8e8) e é comparado inteiro.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classificarResposta, classificarRespostaDoCliente, EXPRESSAO_MAX } from "./reply-router.ts";

// [texto, o que classificarResposta devolvia antes do P4]
const CORPUS_DE_ANTES: Array<[string, unknown]> = [
  ["por favor pare de me mandar mensagem",{"intencao":"opt_out","manejo":"Marque opt_out_whatsapp=true no cliente/fornecedor (update_client/update_supplier) e NÃO envie mais. Confirme educadamente.","sinais":["pare de me mandar"]}],
  ["eu já paguei isso semana passada",{"intencao":"disputa","manejo":"NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.","sinais":["ja paguei"]}],
  ["o serviço deu problema, não vou pagar",{"intencao":"disputa","manejo":"NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.","sinais":["servico deu problema"]}],
  ["essa cobrança está errada",{"intencao":"disputa","manejo":"NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.","sinais":["errada"]}],
  ["pode mandar o pix",{"intencao":"acordo","manejo":"Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.","sinais":["pode mandar o pix"]}],
  ["fechado, vou pagar hoje",{"intencao":"acordo","manejo":"Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.","sinais":["fechado"]}],
  ["só tenho o item 1 e 3",{"intencao":"cotacao_parcial","manejo":"Registre a cotação SÓ dos itens respondidos (record_quote_response) — não cobre o resto do fornecedor.","sinais":["so tenho"]}],
  ["não trabalho com esse modelo",{"intencao":"cotacao_parcial","manejo":"Registre a cotação SÓ dos itens respondidos (record_quote_response) — não cobre o resto do fornecedor.","sinais":["nao trabalho com "]}],
  ["qual a bitola do cabo?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["qual"]}],
  ["vocês têm em estoque",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["voces tem"]}],
  ["bom dia, obrigado",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Sim",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["👍",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["ok",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["sim, mas na quinta não dá",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Pode ser sexta?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["não posso quinta, pode ser sexta?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Não dá pra amanhã",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Quarta dia 04/11 fica melhor pra mim",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["pode ser quarta 04/11?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Vocês vêm amanhã?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Que horas vocês chegam amanhã?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Não vou estar em casa terça",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Vou viajar até sexta",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["O motorhome vai estar fora essa semana",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Não tem ninguém aqui na terça",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Infelizmente não vou poder",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Vamos remarcar?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Pode adiar pra semana que vem?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Deixa pra semana que vem",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["A chave fica com o marinheiro",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Tá na marina, vaga 12, o marinheiro é o Zé",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Onde vocês vão deixar a chave?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["onde"]}],
  ["Está no seco",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["PARAR",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["pare",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Não quero mais receber mensagens",{"intencao":"opt_out","manejo":"Marque opt_out_whatsapp=true no cliente/fornecedor (update_client/update_supplier) e NÃO envie mais. Confirme educadamente.","sinais":["nao quero mais receber"]}],
  ["O compressor não funciona",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Tá apitando de novo",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Está na garantia, né?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Quanto fica?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["quanto"]}],
  ["Tem desconto à vista?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Dá pra parcelar?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Qual o valor final?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["qual"]}],
  ["Combinado, obrigado",{"intencao":"acordo","manejo":"Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.","sinais":["combinado"]}],
  ["Beleza, até lá",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Bom dia",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Obrigado pelo aviso",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Amanhã eu deixo a chave na portaria",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Não dá pra ver o vídeo",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["[audio]",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Sexta",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Pode ser na sexta de manhã",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["terça não posso, só quarta",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Se não der quinta pode ser sexta",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Hoje não vai dar",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Fechado! Pode vir",{"intencao":"acordo","manejo":"Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.","sinais":["fechado"]}],
  ["sim, mas quanto fica?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Vocês têm previsão da peça?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["voces tem"]}],
  ["dia 12 tô de volta, pode ser dia 13?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Essa semana não dá",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Recebeu o compressor?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
  ["Já foi coletado",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Chega aqui amanhã",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["Me tira dessa lista",{"intencao":"opt_out","manejo":"Marque opt_out_whatsapp=true no cliente/fornecedor (update_client/update_supplier) e NÃO envie mais. Confirme educadamente.","sinais":["me tira"]}],
  ["Não reconheço essa cobrança",{"intencao":"disputa","manejo":"NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.","sinais":["nao reconhe"]}],
  ["nota emitida e enviada",{"intencao":"outro","manejo":"Trate normalmente conforme o contexto da conversa.","sinais":[]}],
  ["tá certo, pode fazer",{"intencao":"acordo","manejo":"Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.","sinais":["ta certo"]}],
  ["Quando vocês começam?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["quando"]}],
  ["vocês trabalham com Victron?",{"intencao":"pergunta","manejo":"Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.","sinais":["?"]}],
];

Deno.test("classificarResposta fica byte a byte igual (o corpus inteiro de antes do P4)", () => {
  for (const [texto, antes] of CORPUS_DE_ANTES) {
    assertEquals(JSON.stringify(classificarResposta(texto)), JSON.stringify(antes), texto);
  }
});

// [texto, intenção, expressão] — as do ext §8, as da spec (§8.4) e os casos negativos: a pergunta que não é pedido, a
// negação colada no pedido, o dia da semana com a data, o "não dá" que não é sobre o dia, o acesso perguntado.
const CASOS: Array<[string, string, string | null]> = [
  // o SIM e o "sim, mas…" (quem confirma é o banco, pela concordância curta de 30/09; aqui é só acordo)
  ["Sim", "acordo", null],
  ["👍", "acordo", null],
  ["ok", "acordo", null],
  ["Combinado, obrigado", "acordo", null],
  ["sim, mas tem que ser cedo", "acordo", null],
  ["sim, mas na quinta não dá", "remarcar", "quinta"],
  ["sim, mas quanto fica?", "negociacao", null],
  // o dia pedido
  ["Pode ser sexta?", "data", "sexta"],
  ["não posso quinta, pode ser sexta?", "data", "sexta"],
  ["Não, pode ser sexta", "data", "sexta"],
  ["Se não der quinta pode ser sexta", "data", "sexta"],
  ["terça não posso, só quarta", "data", "quarta"],
  ["sexta não dá, só segunda", "data", "segunda"],
  ["Quarta dia 04/11 fica melhor pra mim", "data", "dia 04/11"],
  ["pode ser quarta 04/11?", "data", "04/11"],
  ["prefiro quarta", "data", "quarta"],
  ["Pode adiar pra semana que vem?", "data", "semana que vem"],
  ["Deixa pra semana que vem", "data", "semana que vem"],
  ["Sexta", "data", "sexta"],
  ["Na sexta então", "data", "sexta"],
  ["e sábado?", "data", "sábado"],
  ["dia 12 tô de volta, pode ser dia 13?", "data", "dia 13"],
  ["não vou poder estar terça, mas quarta pode", "data", "quarta"],
  ["05/11 fica bom", "data", "05/11"],
  // a pergunta sobre o dia combinado não é pedido
  ["Vocês vêm amanhã?", "pergunta", null],
  ["Que horas vocês chegam amanhã?", "pergunta", null],
  ["Amanhã às 9 tá bom?", "pergunta", null],
  ["Amanhã estarei lá", "outro", null],
  // o dia recusado (remarcar e falta)
  ["Não dá pra amanhã", "remarcar", "amanhã"],
  ["não pode ser terça", "remarcar", "terça"],
  ["Hoje não vai dar", "remarcar", "hoje"],
  ["Essa semana não dá", "remarcar", "essa semana"],
  ["Infelizmente não vou poder", "remarcar", null],
  ["Vamos remarcar?", "remarcar", null],
  ["Não vou estar em casa terça", "falta", "terça"],
  ["Vou viajar até sexta", "falta", "até sexta"],
  ["O motorhome vai estar fora essa semana", "falta", "essa semana"],
  ["Não tem ninguém aqui na terça", "falta", "terça"],
  // o "não dá" que não é sobre o dia
  ["Não dá pra ver o vídeo", "outro", null],
  // o acesso (afirmado; o perguntado é pergunta)
  ["A chave fica com o marinheiro", "acesso", null],
  ["Tá na marina, vaga 12, o marinheiro é o Zé", "acesso", null],
  ["Está no seco", "acesso", null],
  ["Amanhã eu deixo a chave na portaria", "acesso", null],
  ["Ok, mas a chave fica na portaria", "acesso", null],
  ["Onde vocês vão deixar a chave?", "pergunta", null],
  // opt-out
  ["PARAR", "opt_out", null],
  ["pare", "opt_out", null],
  ["Não quero mais receber mensagens", "opt_out", null],
  ["Me tira dessa lista", "opt_out", null],
  // reclamação e garantia
  ["O compressor não funciona", "disputa", null],
  ["Tá apitando de novo", "disputa", null],
  ["Está na garantia, né?", "disputa", null],
  ["A bateria desliga sozinha", "disputa", null],
  // negociação (preço, desconto, pagamento)
  ["Quanto fica?", "negociacao", null],
  ["Tem desconto à vista?", "negociacao", null],
  ["Dá pra parcelar?", "negociacao", null],
  ["Qual o valor final?", "negociacao", null],
  // pergunta e o resto
  ["Vocês têm previsão da peça?", "pergunta", null],
  ["Quando vocês começam?", "pergunta", null],
  ["Bom dia", "outro", null],
  ["Obrigado pelo aviso", "outro", null],
  ["[audio]", "outro", null],
  ["", "outro", null],
];

Deno.test("classificarRespostaDoCliente: as intenções e as expressões (com os casos negativos)", () => {
  for (const [texto, intencao, expressao] of CASOS) {
    const r = classificarRespostaDoCliente(texto);
    assertEquals([r.intencao, r.expressao], [intencao, expressao], texto);
  }
  assertEquals(CASOS.length >= 40, true);
});

Deno.test("classificarRespostaDoCliente: os sinais (o trecho que disparou, até 40) e a expressão longa demais não vai", () => {
  assertEquals(classificarRespostaDoCliente("Não posso terça, pode ser sexta?").sinais, ["pode ser sexta"]);
  assertEquals(classificarRespostaDoCliente("PARAR").sinais, ["parar"]);
  for (const t of ["Pode ser sexta?", "Infelizmente não vou poder", "A chave fica com o marinheiro", "Quanto fica?"]) {
    assertEquals(classificarRespostaDoCliente(t).sinais.every((s) => s.length <= 40), true, t);
  }
  assertEquals(EXPRESSAO_MAX, 60);
  assertEquals(classificarRespostaDoCliente(null).intencao, "outro");
});

// ─── Correção C1 da Fase 5 (27/10/2026) ──────────────────────────────────────────────────────────────────────────────
// Item 16: o acesso com negação não é acesso dito (a pergunta do acesso não pode desligar por 90 dias com "não sei onde vai
// estar a chave"): é pergunta, e vai ao dono. Item 2: o PARAR sozinho (e "Pare", "SAIR") é do leitor do cliente; o de hoje
// (classificarResposta) continua sem pegar — o corpus de 70 frases acima prova que ele não mudou.
Deno.test("C1 (item 16): o acesso com negação vira pergunta; o afirmado continua acesso", () => {
  for (const t of ["Não sei onde vai estar a chave ainda", "não tenho a chave", "Ainda não sei quem fica com a chave",
                   "A chave? não sei, vou ver com o marinheiro"]) {
    assertEquals(classificarRespostaDoCliente(t).intencao, "pergunta", t);
  }
  for (const t of ["A chave fica com o marinheiro", "a chave tá com o caseiro", "Tá na garagem, a senha é 1234"]) {
    assertEquals(classificarRespostaDoCliente(t).intencao, "acesso", t);
  }
});

Deno.test("C1 (item 2): PARAR, Pare e SAIR sozinhos são opt-out no leitor do cliente; no de hoje, não (o corpus é o mesmo)", () => {
  for (const t of ["PARAR", "parar", "Pare", "SAIR", "Parar.", "stop"]) {
    assertEquals(classificarRespostaDoCliente(t).intencao, "opt_out", t);
  }
  for (const t of ["PARAR", "pare"]) assertEquals(classificarResposta(t).intencao, "outro", t);
  assertEquals(CORPUS_DE_ANTES.length, 70);
});
