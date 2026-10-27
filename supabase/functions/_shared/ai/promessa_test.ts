// Detector de promessas do dono (06/10/2026). O que se protege: acha as promessas comuns, ignora
// pergunta e conversa sem compromisso, e marca o lembrete dentro da janela (8h–20h, seg–sáb).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dentroDaJanela, detectarPrazoDeFornecedor, detectarPromessa, expressoesDeData, type PrazoDoFornecedor, quandoLembrar,
  semAsDatasDitas,
} from "./promessa.ts";

// Terça 06/10/2026, 18:40 em Brasília.
const TER_1840 = new Date("2026-10-06T21:40:00.000Z");
const iso = (d: Date | null | undefined) => d?.toISOString();

Deno.test("acha as promessas comuns e devolve a frase que promete", () => {
  const casos: Array<[string, string]> = [
    ["Beleza Nelson! Amanhã te mando o orçamento atualizado.", "Amanhã te mando o orçamento atualizado."],
    ["Vou ver com o fornecedor e te retorno", "Vou ver com o fornecedor e te retorno"],
    ["Fechado. Segunda envio as fotos", "Segunda envio as fotos"],
    ["Assim que a peça chegar te aviso!", "Assim que a peça chegar te aviso!"],
    ["Deixa comigo", "Deixa comigo"],
    ["Fico de te passar o valor do frete", "Fico de te passar o valor do frete"],
  ];
  for (const [texto, trecho] of casos) assertEquals(detectarPromessa(texto, TER_1840)?.trecho, trecho, texto);
});

Deno.test("não é promessa: pergunta, agradecimento, mídia, conversa sem compromisso", () => {
  for (const texto of ["Te mando amanhã?", "Obrigado, Miguel!", "[audio]", "O radar é da Raymarine", "Bom dia! Tudo bem?", "", null]) {
    assertEquals(detectarPromessa(texto as string, TER_1840), null, String(texto));
  }
});

Deno.test("quando lembrar: amanhã, dia da semana, mais tarde e o padrão de 24h", () => {
  // amanhã → quarta 09:00
  assertEquals(iso(quandoLembrar("amanhã te mando", TER_1840)), "2026-10-07T12:00:00.000Z");
  // sexta → sexta 09/10 09:00
  assertEquals(iso(quandoLembrar("sexta envio", TER_1840)), "2026-10-09T12:00:00.000Z");
  // "terça" dita numa terça → a PRÓXIMA terça
  assertEquals(iso(quandoLembrar("terça passo", TER_1840)), "2026-10-13T12:00:00.000Z");
  // mais tarde às 18:40 → +3h = 21:40, fora da janela → quarta 09:00
  assertEquals(iso(quandoLembrar("mais tarde te ligo", TER_1840)), "2026-10-07T12:00:00.000Z");
  // sem tempo → +24h (quarta 18:40, dentro da janela)
  assertEquals(iso(quandoLembrar("vou ver e te retorno", TER_1840)), "2026-10-07T21:40:00.000Z");
});

Deno.test("janela: madrugada, noite e domingo vão para 09:00 do próximo dia útil", () => {
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-07T08:00:00Z"))).toISOString(), "2026-10-07T12:00:00.000Z"); // 05:00 → 09:00
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-10T23:30:00Z"))).toISOString(), "2026-10-12T12:00:00.000Z"); // sáb 20:30 → seg 09:00
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-11T15:00:00Z"))).toISOString(), "2026-10-12T12:00:00.000Z"); // domingo → seg
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-07T17:00:00Z"))).toISOString(), "2026-10-07T17:00:00.000Z"); // 14:00 fica
});

// ── O prazo do fornecedor (Agenda de Produção, Fase 4, P4) ─────────────────────────────────────────────────────────
// O que se protege: o detector acha o prazo que o fornecedor (ou a HBR) disse e devolve só a EXPRESSÃO (a data sai do
// banco); erra para o lado de não achar — pergunta, negação, cobrança, "vou ver o prazo" e o que não é material são nada.
// Os 20 trechos de int-compras-prazos §4.7 (a conversa real do compressor da OS-00104, a do fornecedor de fabricação, a
// cobrança da Kamell e a pergunta à Marine Center) com o resultado esperado de cada um; depois os padrões da spec §5.4.1 e
// 15 negativos. A detectarPromessa não muda (os testes de cima continuam).

const TER_13_1719 = new Date("2026-10-13T20:19:00.000Z");
type Esperado = Pick<PrazoDoFornecedor, "tipo" | "expressao" | "condicional"> | null;
const sem = (r: PrazoDoFornecedor | null): Esperado => (r ? { tipo: r.tipo, expressao: r.expressao, condicional: r.condicional } : null);

Deno.test("prazo do fornecedor: os 20 trechos reais de int-compras §4.7", () => {
  const casos: Array<[number, "recebida" | "enviada", string, Esperado]> = [
    [1, "recebida", "Faça a R$900,00", null],
    [2, "recebida", "Para a geladeira de 230 litros tem que usar o SS65, custo que consigo fazer para vc é de R$900,00", null],
    [3, "enviada", "vamos fechar então", null],
    [3, "enviada", "voce consegue deixar separado para a transportadora retirar?", null],
    [4, "enviada", "chega aqui amanha se eles retirarem hoje", { tipo: "chegada", expressao: "amanhã", condicional: true }],
    [5, "recebida", "Estou confirmando se tenho disponivel no estoque", null],
    [6, "recebida", "Tenho disponivel", null],
    [7, "recebida", "Vamos emitir a NFe", null],
    [7, "recebida", "Em breve esta pronto para coleta", null],
    [8, "recebida", "NF 1810- HBR.pdf", null],
    [8, "recebida", "[document]", null],
    [9, "recebida", "Já foi coletado", { tipo: "despacho", expressao: null, condicional: false }],
    [10, "recebida", "Recebeu o compressor?", { tipo: "perguntou_chegou", expressao: null, condicional: false }],
    [10, "recebida", "Deu tudo certo?", null],
    [11, "recebida",
      "é para bater certinho ali com o prazo que eu te passei, mais ou menos final do mês. Final do mês ali é para nós estar entregando ele",
      null],
    [12, "recebida", "vou tentar dar uma olhada aqui… se daria para tentar acelerar aí na parte de pintura", null],
    [13, "recebida", "eu teria que pintar e entregar ele pronto, sair daqui tudo prontinho já", null],
    [14, "recebida", "dava para entregar na sexta ou no sábado, que é mais tranquilo",
      { tipo: "chegada", expressao: "sexta ou sábado", condicional: false }],
    [15, "recebida", "Se você quiser eu posso jogar para amanhã de manhã… Agora hoje não dá mais", null],
    [16, "recebida", "já chegou um aqui já para carregar e estamos aguardando o outro. Mas daí vai chegar ali perto das 5", null],
    [17, "recebida", "O outro ali ele é mais de boa, espera até segunda", null],
    [18, "recebida", "podemos contar com o pagamento para hoje desse boleto?", null],
    [19, "recebida", "Consegue enviar o comprovante de pagamento para verificar junto ao banco", null],
    [20, "enviada", "Vc tem kit flap em estoque?", null],
  ];
  for (const [n, direcao, texto, esperado] of casos) {
    assertEquals(sem(detectarPrazoDeFornecedor(texto, TER_13_1719, direcao)), esperado, `#${n}: ${texto}`);
  }
  // o trecho é a frase como foi escrita
  assertEquals(detectarPrazoDeFornecedor("Já foi coletado", TER_13_1719, "recebida")?.trecho, "Já foi coletado");
  assertEquals(detectarPrazoDeFornecedor("Recebeu o compressor? Deu tudo certo?", TER_13_1719, "recebida")?.trecho,
    "Recebeu o compressor?");
});

Deno.test("prazo do fornecedor: os padrões da spec §5.4.1", () => {
  const casos: Array<["recebida" | "enviada", string, Esperado]> = [
    // despacho: a data é a da mensagem (expressão nula)
    ["recebida", "Foi coletado agora há pouco", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Coletaram hoje cedo", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Despachado!", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Foi postado hoje", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Postei agora", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Saiu hoje pela transportadora", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Enviado hoje", { tipo: "despacho", expressao: null, condicional: false }],
    ["recebida", "Nota emitida e já enviada", { tipo: "despacho", expressao: null, condicional: false }],
    // chegada: a expressão de data como foi dita
    ["recebida", "Chega amanhã", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    ["recebida", "Chega aí dia 14", { tipo: "chegada", expressao: "dia 14", condicional: false }],
    ["recebida", "chega 14/10", { tipo: "chegada", expressao: "14/10", condicional: false }],
    ["recebida", "Entrega prevista para sexta-feira", { tipo: "chegada", expressao: "sexta-feira", condicional: false }],
    ["recebida", "Previsão de entrega: 16/10", { tipo: "chegada", expressao: "16/10", condicional: false }],
    ["recebida", "Deve chegar até sexta", { tipo: "chegada", expressao: "até sexta", condicional: false }],
    ["recebida", "Deve chegar terça se a transportadora passar hoje", { tipo: "chegada", expressao: "terça", condicional: true }],
    ["recebida", "Já foi despachado e chega amanhã", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    // prazo em dias
    ["recebida", "O prazo é de 5 dias úteis", { tipo: "prazo", expressao: "5 dias úteis", condicional: false }],
    ["recebida", "De 3 a 5 dias úteis depois que sai", { tipo: "prazo", expressao: "3 a 5 dias úteis", condicional: false }],
    ["recebida", "Prazo de 5 dias", { tipo: "prazo", expressao: "5 dias", condicional: false }],
    ["recebida", "Chega em dois dias", { tipo: "prazo", expressao: "2 dias", condicional: false }],
    ["recebida", "um dia útil", { tipo: "prazo", expressao: "1 dia útil", condicional: false }],
    ["recebida", "em 10 dias corridos", { tipo: "prazo", expressao: "10 dias corridos", condicional: false }],
    // atraso, com a data nova ou sem ela
    ["recebida", "Vai atrasar, só chega sexta", { tipo: "atraso", expressao: "sexta", condicional: false }],
    ["recebida", "Só vai chegar dia 20", { tipo: "atraso", expressao: "dia 20", condicional: false }],
    ["recebida", "Não vai dar pra enviar hoje, só amanhã", { tipo: "atraso", expressao: "amanhã", condicional: false }],
    ["recebida", "Atrasou", { tipo: "atraso", expressao: null, condicional: false }],
    // a pergunta do fornecedor
    ["recebida", "Chegou?", { tipo: "perguntou_chegou", expressao: null, condicional: false }],
    ["recebida", "Bom dia! Já recebeu o material?", { tipo: "perguntou_chegou", expressao: null, condicional: false }],
    // o áudio transcrito vale como texto
    ["recebida", "🎤 olha, já foi coletado, deve chegar amanhã aí", { tipo: "chegada", expressao: "amanhã", condicional: false }],
  ];
  for (const [direcao, texto, esperado] of casos) {
    assertEquals(sem(detectarPrazoDeFornecedor(texto, TER_13_1719, direcao)), esperado, texto);
  }
});

Deno.test("prazo do fornecedor: 15 negativos (pergunta, negação, cobrança, 'vou ver o prazo', o que não é material)", () => {
  const casos: Array<["recebida" | "enviada", string | null]> = [
    ["recebida", "Já foi coletado?"],
    ["recebida", "Chega amanhã?"],
    ["recebida", "Ainda não foi coletado"],
    ["recebida", "Não chega amanhã, infelizmente"],
    ["recebida", "Vou ver o prazo e te falo"],
    ["recebida", "Qual o prazo de entrega?"],
    ["recebida", "O boleto vence dia 14"],
    ["recebida", "O pagamento atrasou, consegue ver?"],
    ["recebida", "Recebeu o boleto?"],
    ["recebida", "Recebeu meu e-mail?"],
    ["recebida", "Chegou a ver o orçamento?"],
    ["recebida", "Vai ser despachado amanhã"],
    ["recebida", "Faz 5 dias que pedi"],
    ["enviada", "Recebeu o compressor?"],
    ["recebida", "[audio]"],
    ["recebida", ""],
    ["recebida", null],
  ];
  for (const [direcao, texto] of casos) {
    assertEquals(detectarPrazoDeFornecedor(texto, TER_13_1719, direcao), null, String(texto));
  }
});

// ── C1 da revisão da Fase 4 (25/10/2026) ────────────────────────────────────────────────────────────────────────────
// O que se protege: (3) o dia da semana com a data não joga a data fora (errava por uma semana); (4) o pedido da HBR
// nunca vira previsão — do lado da HBR só a chegada que ela afirma; (9) "não vai atrasar" não é atraso, e "sem falta" e
// "sem problema" não são negação. Os casos são os de rev-f4/parser.ts e parser2.ts (seg 26/10 e ter 13/10).

Deno.test("prazo do fornecedor (C1): o dia da semana com a data — vale a data", () => {
  const casos: Array<[string, Esperado]> = [
    ["chega quarta dia 04/11", { tipo: "chegada", expressao: "dia 04/11", condicional: false }],
    ["entrega na quarta 04/11", { tipo: "chegada", expressao: "04/11", condicional: false }],
    ["chega quarta, dia 4", { tipo: "chegada", expressao: "dia 4", condicional: false }],
    ["Chega quarta dia 4", { tipo: "chegada", expressao: "dia 4", condicional: false }],
    ["previsão de entrega quarta-feira 04/11", { tipo: "chegada", expressao: "04/11", condicional: false }],
    ["chega sexta 30/10", { tipo: "chegada", expressao: "30/10", condicional: false }],
    ["chega na sexta, dia 30", { tipo: "chegada", expressao: "dia 30", condicional: false }],
    ["só vai chegar na quarta dia 04/11", { tipo: "atraso", expressao: "dia 04/11", condicional: false }],
    // sem a data, o dia da semana continua valendo; o número solto ("4 caixas") não é data
    ["chega quarta que vem", { tipo: "chegada", expressao: "quarta que vem", condicional: false }],
    ["chega quarta 4 caixas", { tipo: "chegada", expressao: "quarta", condicional: false }],
    ["chega dia 4/11", { tipo: "chegada", expressao: "dia 4/11", condicional: false }],
  ];
  for (const [texto, esperado] of casos) {
    assertEquals(sem(detectarPrazoDeFornecedor(texto, TER_13_1719, "recebida")), esperado, texto);
  }
});

Deno.test("prazo do fornecedor (C1): do lado da HBR, só a chegada que ela afirma (o pedido nunca)", () => {
  const nulos = [
    "consegue entregar amanhã",
    "precisa entregar amanhã",
    "preciso que chegue em 3 dias uteis",
    "preciso em 5 dias",
    "Preciso que chegue até sexta",
    "pode mandar amanhã",
    "você poderia entregar sexta",
    "tem como chegar amanhã",
    "dá pra entregar na sexta",
    "quero que chegue amanhã",
    "queria que entregue sexta",
    // prazo, atraso e despacho escritos pela HBR não contam
    "o prazo é de 5 dias úteis",
    "vai atrasar então",
    "já foi coletado então",
  ];
  for (const texto of nulos) {
    assertEquals(detectarPrazoDeFornecedor(texto, TER_13_1719, "enviada"), null, texto);
  }
  // a chegada que a HBR afirma continua (a do replay da OS-00104)
  assertEquals(sem(detectarPrazoDeFornecedor("chega aqui amanha se eles retirarem hoje", TER_13_1719, "enviada")),
    { tipo: "chegada", expressao: "amanhã", condicional: true });
  assertEquals(sem(detectarPrazoDeFornecedor("chega amanhã então", TER_13_1719, "enviada")),
    { tipo: "chegada", expressao: "amanhã", condicional: false });
  // do lado do fornecedor o "pode" é dele: "pode deixar, entregamos na sexta" não é pedido da HBR
  assertEquals(sem(detectarPrazoDeFornecedor("pode deixar, entregamos na sexta", TER_13_1719, "recebida")),
    { tipo: "chegada", expressao: "sexta", condicional: false });
});

Deno.test("prazo do fornecedor (C1): 'não vai atrasar' não é atraso; 'sem falta' e 'sem problema' não negam", () => {
  const casos: Array<[string, Esperado]> = [
    ["Fica tranquilo, não vai atrasar", null],
    ["não vai atrasar", null],
    ["Não atrasou não, saiu ontem", null],
    ["nao vai atrasar, chega amanha", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    ["sem falta chega amanhã", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    ["sem problema chega amanhã", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    ["sem problemas, chega amanhã", { tipo: "chegada", expressao: "amanhã", condicional: false }],
    // o atraso de verdade continua
    ["Vai atrasar, só chega sexta", { tipo: "atraso", expressao: "sexta", condicional: false }],
    ["Não vai dar pra enviar hoje, só amanhã", { tipo: "atraso", expressao: "amanhã", condicional: false }],
    ["Não atrasou, mas só chega sexta", { tipo: "atraso", expressao: "sexta", condicional: false }],
    // a negação de verdade continua negando
    ["Não chega amanhã, infelizmente", null],
    ["sem previsão de chegar amanhã", null],
  ];
  for (const [texto, esperado] of casos) {
    assertEquals(sem(detectarPrazoDeFornecedor(texto, TER_13_1719, "recebida")), esperado, texto);
  }
});

// (Agenda, Fase 5, P4 — 27/10/2026) as datas ditas numa frase do cliente: as MESMAS expressões do prazo do fornecedor.
Deno.test("expressoesDeData: as datas da frase, na ordem, como o banco lê; 'essa semana' só com periodo", () => {
  assertEquals(expressoesDeData("não posso quinta, pode ser sexta?"), ["quinta", "sexta"]);
  assertEquals(expressoesDeData("Quarta dia 04/11 fica melhor"), ["dia 04/11"]);
  assertEquals(expressoesDeData("vou viajar até sexta"), ["até sexta"]);
  assertEquals(expressoesDeData("deixa pra semana que vem"), ["semana que vem"]);
  assertEquals(expressoesDeData("essa semana não dá"), []);
  assertEquals(expressoesDeData("essa semana não dá", { periodo: true }), ["essa semana"]);
  assertEquals(expressoesDeData("a chave fica com o marinheiro"), []);
  assertEquals(expressoesDeData(null), []);
  assertEquals(semAsDatasDitas("Na sexta então"), "entao");
  assertEquals(semAsDatasDitas("pode ser sexta"), "pode ser");
});
