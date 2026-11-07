// Retorno rápido, F2 (P2.2): a matriz de colisão do vocabulário, rodada contra os leitores REAIS.
//
// Fica fora de _shared/retorno/ porque importa _shared/ai/, e o isolamento_test.ts varre aquela pasta, testes inclusive.
// Todas as frases são inventadas: nenhuma vem de whatsapp_messages nem de ai_operator_messages. Os números 4321 e 7391
// também são inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ComandoDoRetorno,
  ehComandoDeCartao,
  frasesDoRetorno,
  LETRAS_DO_RETORNO,
  lerComandoDoRetorno,
  NAO_E_ALVO_DO_LIBERA,
} from "../retorno/comandos.ts";
import { frasesDaAgenda, lerComandoDaAgenda } from "../agenda/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerPedidoDePdf } from "../ai/atalho-pdf.ts";
import {
  type EstadoDoTelefone,
  lerNumero,
  lerSimNao,
  normalizarResposta,
  pareceRespostaCurta,
  quemResponde,
} from "./pergunta-ativa.ts";

const TABELA: Array<[string, ComandoDoRetorno]> = [
  ["retorno", { comando: "retorno" }],
  ["*Retorno*", { comando: "retorno" }],
  ["🎤 Retorno.", { comando: "retorno" }],
  ["ver retorno", { comando: "retorno" }],
  ["retorno?", { comando: "retorno" }],
  ["pessoal", { comando: "pessoal", n: null }],
  ["pessoal 2", { comando: "pessoal", n: 2 }],
  ["2 pessoal", { comando: "pessoal", n: 2 }],
  ["Pessoal não", { comando: "pessoal_desfaz" }],
  ["fora até quarta", { comando: "fora_ate", dia: "quarta" }],
  ["Fora até 25/11.", { comando: "fora_ate", dia: "25/11" }],
  ["fora até hoje", { comando: "fora_ate", dia: "hoje" }],
  ["segura recibos", { comando: "segura", alvo: "recibos" }],
  ["segura tudo", { comando: "segura", alvo: "tudo" }],
  ["Solta recibos.", { comando: "solta", alvo: "recibos" }],
  ["*solta tudo*", { comando: "solta", alvo: "tudo" }],
  ["libera Rodrigo", { comando: "libera", alvo: "rodrigo", desfaz: false }],
  ["libera o Rodrigo", { comando: "libera", alvo: "rodrigo", desfaz: false }],
  ["libera OS-00161", { comando: "libera", alvo: "os-00161", desfaz: false }],
  ["libera Rodrigo não", { comando: "libera", alvo: "rodrigo", desfaz: true }],
  ["errado Z", { comando: "errado", letra: "Z" }],
  ["Errado v.", { comando: "errado", letra: "V" }],
  ["1 A", { comando: "escolher", n: 1, letra: "A", resto: null, pin: null }],
  ["2 B", { comando: "escolher", n: 2, letra: "B", resto: null, pin: null }],
  ["3 b", { comando: "escolher", n: 3, letra: "B", resto: null, pin: null }],
  ["1 C", { comando: "escolher", n: 1, letra: "C", resto: null, pin: null }],
  ["3 C dia 14", { comando: "escolher", n: 3, letra: "C", resto: "dia 14", pin: null }],
  ["3 c 14/12", { comando: "escolher", n: 3, letra: "C", resto: "14/12", pin: null }],
  ["1 A sim 7391", { comando: "escolher", n: 1, letra: "A", resto: null, pin: "7391" }],
  ["1 c sim 7391", { comando: "escolher", n: 1, letra: "C", resto: null, pin: "7391" }],
  ["dita 2 pode buscar amanhã", { comando: "ditar", n: 2, texto: "pode buscar amanhã" }],
  ["🎤 Dita 2, pode buscar amanhã", { comando: "ditar", n: 2, texto: "pode buscar amanhã" }],
  ["Dita 3: Ok, Sr. Rodrigo!", { comando: "ditar", n: 3, texto: "Ok, Sr. Rodrigo!" }],
  ["*dita* 1 - consegue vir às 15h?", { comando: "ditar", n: 1, texto: "consegue vir às 15h?" }],
  ["dita 2", { comando: "ditar", n: 2, texto: "" }],
  ["só 3", { comando: "so", ns: [3], pin: null }],
  ["só 1 e 3", { comando: "so", ns: [1, 3], pin: null }],
  ["só 1, 3", { comando: "so", ns: [1, 3], pin: null }],
  ["só 1 3", { comando: "so", ns: [1, 3], pin: null }],
  ["só 3 sim 7391", { comando: "so", ns: [3], pin: "7391" }],
  ["sim sem 2", { comando: "sem", ns: [2], pin: null }],
  ["sim sem 1 e 3", { comando: "sem", ns: [1, 3], pin: null }],
  ["sim 7391 sem 2", { comando: "sem", ns: [2], pin: "7391" }],
  ["não 2", { comando: "tirar", ns: [2] }],
  ["não 1 e 3", { comando: "tirar", ns: [1, 3] }],
  ["ver 1", { comando: "ver", n: 1 }],
  ["ver 1?", { comando: "ver", n: 1 }],
];

// A seção 7.3 da spec: conversa que tem de continuar conversa.
const CONVERSA = [
  "1 não entendi", "2 sim", "2 baterias", "2 dias", "1 dia", "3 dias", "1 hora", "2 pessoas", "2 peças", "1 ok", "3 meses",
  "2 vezes", "2 a 3 dias", "3 a 5", "2 ou 3", "1 de 3", "o retorno do cliente", "retorno do Paulo", "dá retorno", "pessoal da MP",
  "pessoal, bom dia", "pessoal chegou", "libera o pagamento", "libera a nota", "libera o pix", "libera pro Alex", "libera aí",
  "libera todos", "libera ele", "libera amanhã", "errado o valor", "fora de hora", "fora do ar", "segura aí", "segura o pagamento",
  "solta o Alex", "ver o orçamento", "ver 2 fotos", "ver depois", "dita a mensagem", "só isso", "só um", "só 2 peças", "só 1 hora",
  "sim sem pressa", "sim sem problema", "sim, mas 4321", "sim 4321 reais", "como estamos de agenda",
  // o número sem a palavra sim não é PIN e não é comando
  "1 A 7391", "3 b 500", "só 3 300", "só 3 7391", "3 c 7391", "3 c dia 14 sim 7391",
  // as letras fora do alfabeto do plano
  "1 s", "2 n", "1 e", "1 o", "2 i",
  // sem a palavra, sem o comando
  "1", "2", "3", "sim", "não", "1: pode", "sim 7391", "4 B", "0 B", "ver 4", "ver", "só 4", "só 1 e 1", "não 1 e 1",
  // o que age, dito como pergunta
  "segura tudo?", "solta recibos?", "libera Rodrigo?", "fora até quarta?", "pessoal 2?", "errado Z?", "1 A?", "só 3?", "não 2?",
  "sim sem 2?",
  // outras do libera
  "liberar", "libera", "libera o sinal", "libera o saldo", "libera o boleto", "libera a fatura", "libera a NF", "libera o recibo",
  "libera o acesso", "libera agora", "libera não", "libera do cliente do barco azul da marina", "fora até", "errado", "",
];

const ANTES_DA_MATRIZ = TABELA.map(([t]) => t);

/** As formas fixas cruas e como chegam (negrito, maiúscula, ponto), mais as da tabela. */
function todasAsFormas(): string[] {
  const base = frasesDoRetorno();
  return [...base, ...base.map((f) => `*${f}*`), ...base.map((f) => `${f[0].toUpperCase()}${f.slice(1)}.`), ...ANTES_DA_MATRIZ];
}

Deno.test("lerComandoDoRetorno: lê cada linha da tabela da P2.1, com acento, maiúscula, negrito, ponto e 🎤", () => {
  for (const [t, esperado] of TABELA) assertEquals(lerComandoDoRetorno(t), esperado, t);
});

Deno.test("a conversa da seção 7.3 continua conversa", () => {
  for (const t of CONVERSA) assertEquals(lerComandoDoRetorno(t), null, t);
});

Deno.test("nada mais longo que o ditado é palavra", () => {
  assertEquals(lerComandoDoRetorno(`dita 2 ${"a".repeat(1200)}`), null);
  const lido = lerComandoDoRetorno(`dita 2 ${"a".repeat(1050)}`);
  assert(lido?.comando === "ditar" && lido.texto.length === 1050, "o ditado longo chega à camada, que recusa com o motivo");
});

Deno.test("o que depende de cartão vivo é só escolher, ditar, so, sem, tirar, ver e pessoal com número", () => {
  const deCartao = (t: string) => ehComandoDeCartao(lerComandoDoRetorno(t)!);
  for (const t of ["1 A", "dita 2 ok", "só 3", "sim sem 2", "não 2", "ver 1", "pessoal 2"]) assert(deCartao(t), t);
  for (const t of ["retorno", "pessoal", "pessoal não", "fora até quarta", "segura tudo", "solta tudo", "libera Rodrigo", "errado Z"]) {
    assert(!deCartao(t), t);
  }
});

Deno.test("nenhuma palavra é lida pelo Secretário, pela agenda, pelo comprovante ou pelo PDF", () => {
  for (const t of todasAsFormas()) {
    assertEquals(lerComandoDoSecretario(t), null, `secretário: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, `agenda: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
  }
});

/** Os comandos do secretário, lidos da fonte, para acompanhar quando a lista crescer. */
async function comandosDoSecretario(): Promise<string[]> {
  const fonte = await Deno.readTextFile(new URL("../secretario/comandos_test.ts", import.meta.url));
  const ini = fonte.indexOf("const COMANDOS");
  const fim = fonte.indexOf("];", ini);
  assert(ini > 0 && fim > ini, "a lista COMANDOS do secretário sumiu de comandos_test.ts");
  return [...fonte.slice(ini, fim).matchAll(/^\s*\["((?:[^"\\]|\\.)*)",/gm)].map((m) => m[1]);
}

Deno.test("nenhuma frase da agenda nem comando do Secretário é lido aqui", async () => {
  const lista = await comandosDoSecretario();
  assert(lista.length >= 30, `lista do secretário curta demais (${lista.length})`);
  for (const t of [...lista, ...frasesDaAgenda()]) assertEquals(lerComandoDoRetorno(t), null, t);
});

Deno.test("as formas fixas não são sim, não, número de menu nem resposta curta", () => {
  for (const t of frasesDoRetorno().filter((f) => !/^[1-3] /.test(f))) {
    assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
    assertEquals(parseOptionReply(t, 9), null, `opção: ${t}`);
    const n = normalizarResposta(t);
    assertEquals(lerNumero(n, 99), null, `número: ${t}`);
    assertEquals(lerSimNao(n), null, `sim/não: ${t}`);
    assertEquals(pareceRespostaCurta(t), false, `curta: ${t}`);
  }
});

Deno.test("1 não, 1 não entendi, 2 sim, 2 B e 2 dias não são sim nem não na confirmação", () => {
  for (const t of ["1 não", "1 não entendi", "2 sim", "2 B", "2 dias", "2 baterias", "2 pessoal", "2 peças"]) {
    assertEquals(parseConfirmationReply(t), null, t);
  }
});

Deno.test("não entendi e companhia: sem a opção, como sempre; com o cartão no ponteiro, conversa", () => {
  for (const t of ["não entendi", "não sei ainda", "não precisa disso agora", "não é esse"]) {
    assertEquals(parseConfirmationReply(t, { naoSoSozinho: true }), null, t);
    assertEquals(parseConfirmationReply(t)?.decision, "reject", t);
  }
  assertEquals(parseConfirmationReply("não, o do Paulo primeiro", { naoSoSozinho: true }), null);
  assertEquals(parseConfirmationReply("2 pode", { naoSoSozinho: true }), null);
  for (const t of ["não", "Não.", "não obrigado", "não, pode cancelar", "não manda", "n", "cancelar"]) {
    assertEquals(parseConfirmationReply(t, { naoSoSozinho: true })?.decision, "reject", t);
  }
});

Deno.test("NAO_E_ALVO_DO_LIBERA contém a NAO_E_ALVO da agenda inteira", async () => {
  const fonte = await Deno.readTextFile(new URL("../agenda/comandos.ts", import.meta.url));
  const bloco = /const NAO_E_ALVO = new Set\(\[([\s\S]*?)\]\);/.exec(fonte);
  assert(bloco, "NAO_E_ALVO sumiu de agenda/comandos.ts");
  const palavras = [...bloco[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  assert(palavras.length >= 30, `lista curta demais (${palavras.length})`);
  for (const p of palavras) assert(NAO_E_ALVO_DO_LIBERA.has(p), `falta no libera: ${p}`);
});

Deno.test("as letras do Mandei sozinho são lidas por *errado*, e só depois dele", () => {
  for (const l of LETRAS_DO_RETORNO) {
    assertEquals(lerComandoDoRetorno(`errado ${l}`), { comando: "errado", letra: l }, l);
    assertEquals(lerComandoDoRetorno(l), null, l);
  }
});

Deno.test("áudio: a transcrição vale como a palavra escrita", () => {
  assertEquals(lerComandoDoRetorno("🎤 Retorno."), { comando: "retorno" });
  assertEquals(lerComandoDoRetorno("🎤 Dita 2, pode buscar amanhã"), { comando: "ditar", n: 2, texto: "pode buscar amanhã" });
  assertEquals(lerComandoDoRetorno("dita 2 pode buscar"), { comando: "ditar", n: 2, texto: "pode buscar" });
});

// ─── Com um CMP aberto no passo "confirmar", quase toda frase vira "ok": a marca do Secretário tira a palavra de lá ──
const AGORA = new Date("2026-11-24T12:00:00.000Z");

function estadoComCmpNoConfirmar(): EstadoDoTelefone {
  return {
    conversa: true, dono: true,
    ativa: {
      id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "confirmar",
      opcoes: [], wa_message_id: "WA-P", aberta_em: "2026-11-24T11:59:00Z",
    },
    citada: null,
    pendencia: { tipo: "confirmacao", id: "pend-1", titulo: "Enviar lembrete", desde: "2026-11-24T11:00:00Z" },
    cmp_em_contexto: null,
  };
}

Deno.test("quemResponde: com o CMP no confirmar, a palavra marcada vai ao assistente; citando a pergunta, vai ao CMP", () => {
  const base = { citado: null, estado: estadoComCmpNoConfirmar(), ehRespostaValida: true, ehComando: null, agora: AGORA };
  for (const texto of ["1 B", "retorno", "segura tudo", "dita 2 ok", "só 3", "não 2"]) {
    assertEquals(quemResponde({ ...base, texto, ehComandoDoSecretario: true }), { destino: "assistente", motivo: "comando_do_secretario" }, texto);
  }
  const citando = quemResponde({
    ...base, texto: "retorno", citado: "WA-P", ehComandoDoSecretario: true,
    estado: { ...estadoComCmpNoConfirmar(), citada: { id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", status: "aberta", passo: "confirmar" } },
  });
  assertEquals(citando.destino, "comprovante");
});
