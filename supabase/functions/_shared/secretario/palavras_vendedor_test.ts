// (20/10/2026) Quem se apresenta vendendo não acorda o dono — pareceVendedor, com os casos REAIS de 02 a 20/10/2026
// (SELECT em produção nas mensagens recebidas de contatos sem cadastro de cliente). O que se protege:
//   · os dois falsos positivos medidos: a "Consultora Empresarial da Vivo" de 02/10 (Allana) e a de 20/10 (Ketelyn);
//   · o nome que diz que vende (os representantes de fornecedor: Jaison, Regis);
//   · NENHUM cliente/lead de verdade do período é marcado (Josemar 20/10 09:58, o lead do filtro 09/10, o "aprovado,
//     favor seguir" de 13/10, o Cristiano, o Celso, o MP Motorhomes, o SAC da EOS que se apresenta, a nota da HDI
//     SEGUROS que o financeiro de um cliente mandou, o "plano de ação" do MP);
//   · palavras soltas que um cliente usa (proposta, plano de manutenção, comercial, gerente, sem compromisso) não marcam.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pareceVendedor } from "./palavras.ts";

const ALLANA = "Oii Sou a Allana, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a TIM, esta chegando ao fim, e *vai haver reajuste automático de valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?";
const KETELYN = "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a Tim, esta chegando ao fim, e *nesse período tem um reajuste automático no valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?";

Deno.test("vendedor: os falsos positivos de 02/10 e 20/10 — pelo texto (Allana) e pelo nome e pelo texto (Ketelyn)", () => {
  assertEquals(pareceVendedor("Allana Marques", [ALLANA]), true, "o nome não diz; o texto diz");
  assertEquals(pareceVendedor("Ketelyn Consultora empresarial", []), true, "só o nome já diz");
  assertEquals(pareceVendedor("Ketelyn", [KETELYN]), true, "só o texto já diz");
  // cada pedaço da apresentação sozinho também basta
  for (const t of [
    "Sou a Allana, consultora da Vivo", "consultora empresarial", "identifiquei que o seu contrato com a TIM está chegando ao fim",
    "vai haver reajuste automático de valor", "tenho ofertas para você pagar menos", "Me chamo Rodrigo e sou representante da Marine Co.",
    "Aqui é o Paulo, do time comercial da Claro", "temos portabilidade com bônus", "crédito pré-aprovado para sua empresa", "consórcio de imóveis",
    "plano empresarial com 50GB",
  ]) assertEquals(pareceVendedor("Contato", [t]), true, t);
});

Deno.test("vendedor: o nome que diz que vende (representantes de fornecedor no período)", () => {
  assertEquals(pareceVendedor("Jaison Consultor de Vendas Zendel", ["Gustavo bom dia, tudo joia?"]), true);
  assertEquals(pareceVendedor("Regis Takeo Mazzaro - Vendas Solmais", []), true);
  assertEquals(pareceVendedor("Corretora Mar Seguros", []), true);
});

Deno.test("vendedor: nenhum cliente/lead real de 02–20/10 é marcado", () => {
  const reais: Array<[string, string]> = [
    ["Josemar Santos", "Você teria disponibilidade de falarmos hoje?"],
    ["Paulo  Chave Digital", "Tem disponibilidade hoje pela manhã ou início da tarde pra trocar o filtro?"],
    ["fabiolhdi", "Bom Dia, Gustavo. Sobre o serviço na Iveco que falamos. Esta aprovado, favor seguir com os reparos."],
    ["Cristiano", "🎤 Eu entrego na rua, né? Eu tenho avan para entregar, né? Só que hoje eu não estou na cidade, né?"],
    ["Celso Docol", "🎤 Marcelo tudo bem boa tarde Celso ali do motorhome eu trouxe teu carregador aqui mas não deu certo"],
    ["Mp Motorhomes", "🎤 Ô bicho, preciso botar minha tomada aqui, cara, essa mulher vai me comer vivo hoje"],
    ["Mp Motorhomes", "Plano de acao no MH do Everton Sprinter Azul Termino Caminhao"],
    ["Financeiro MP - Milenna", "29.980.158/0001-57 - HDI SEGUROS S.A."],
    ["", "Olá! Bom dia, tudo bem? Meu nome é Manuela Michelon e falo em nome do SAC da EOS. Serei a responsável pelo seu atendimento. Como posso ajudar?"],
    ["flaviodaigreja", "🎤 Pode ser segunda-feira. Porque hoje eu tô em Floripa, amanhã não vou poder também, vou ter feito uns negócios ali."],
    ["Mateus Honório", "Deu tudo certo?"],
    ["Vitor Botelho - Energia Solar", "Bom dia, conseguimos ver aquele sistema hoje?"],
    ["Ricardo Comercial Kamell", "Fechar o pedido somente do cerbo?"],
  ];
  for (const [nome, texto] of reais) assertEquals(pareceVendedor(nome, [texto]), false, `${nome}: ${texto}`);
});

Deno.test("vendedor: palavras soltas que um cliente usa não marcam", () => {
  for (const t of [
    "me manda a proposta hoje", "quero fazer o plano de manutenção", "qual o horário comercial de vocês?", "sou gerente da marina e preciso de um orçamento hoje",
    "pode me passar um orçamento sem compromisso?", "sou o João, executivo da transportadora, precisamos do caminhão hoje", "tenho seguro do barco, cobre?",
    "o contrato do serviço está aprovado", "a oferta de vocês ficou boa, vamos fechar",
  ]) assertEquals(pareceVendedor("Cliente Final", [t]), false, t);
  assertEquals(pareceVendedor(null, [null, undefined, ""]), false);
});
