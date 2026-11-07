// O retorno rápido no Secretário (F1, P14): as linhas da manhã e da tarde (ligado, sombra e desligado), a leitura que nunca
// lança (e registra o erro em app_error_logs), "Clientes esperando" que nunca sai da manhã, "Para conferir" que sai primeiro,
// "Ainda esperando hoje" que nunca sai da tarde (nem com semOsExtras e as vagas garantidas da agenda, nem no corte duro, e
// também nas revisões) e o resumo que sai primeiro. "prometi" só para quem ouviu; o prazo é o vigente (o do adiamento); o
// teto da linha deixa o texto abaixo dos 4.000 do banco. Sem o retorno, a manhã e a tarde são as de antes, byte a byte.
// Telefones de teste na faixa 5547900009xxx.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ConferirDoRetorno,
  type EsperandoDoRetorno,
  type ExtraDoFechamento,
  lerExtra,
  lerRetorno,
  linhasDaManha,
  linhaDeContatos,
  linhaDoMandei,
  linhasDoExtra,
  linhasDoFechamento,
  type RetornoDaManha,
  type RetornoDoFechamento,
  TETO_DA_LINHA,
} from "./retorno.ts";
import { candidatosDoDia } from "./secretario-candidatos.ts";
import { selecionar } from "./secretario-selecao.ts";
import { META_DE_CARACTERES, textoDaManha } from "./secretario-texto.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import { montarDosDados } from "./secretario.ts";
import {
  type AgendaDoFechamento,
  type DadosDaTarde,
  LIMITE_DA_TARDE,
  linhaQueFicou,
  PERGUNTA_DA_SEMANA,
  textoDaTarde,
} from "./secretario-tarde-texto.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";
import { type LidoDaTarde, montarTardeDosDados, rodarTurnoDaTarde } from "./secretario-tarde.ts";

/** O CHECK de resumo_manha.texto_novo e de resumo_tarde.texto (char_length <= 4000). */
const LIMITE_DO_BANCO = 4000;

// ─── Dados ──────────────────────────────────────────────────────────────────────────────────────

const MANHA = new Date("2026-11-17T10:30:00Z"); // terça 17/11, 07:30 de Brasília
const MANHA_SEGUINTE = new Date("2026-11-18T10:30:00Z"); // quarta 18/11, 07:30
const TARDE = new Date("2026-11-17T20:30:00Z"); // terça 17/11, 17:30
const SEXTA = new Date("2026-11-27T20:30:00Z"); // sexta 27/11, 17:30 (a de 20/11 é feriado)
const QUINTA = new Date("2026-11-26T20:30:00Z");

function esp(rotulo: string, extra: Partial<EsperandoDoRetorno> = {}): EsperandoDoRetorno {
  return { phone: "5547900009100", rotulo, desde: "2026-11-16T12:00:00Z", prometido_ate: null, venceu: false, com_prazo_hoje: false, ...extra };
}

// os 4 com prazo hoje, na ordem do banco: o vencido primeiro, depois os prometidos para hoje; todos ouviram a promessa
const COM_PRAZO: EsperandoDoRetorno[] = [
  esp("Paulo", { phone: "5547900009101", desde: "2026-11-16T19:02:00Z", prometido_ate: "2026-11-16T22:00:00Z", venceu: true, com_prazo_hoje: true, ouviu: true }),
  esp("número novo", { phone: "5547900009102", desde: "2026-11-17T00:40:00Z", prometido_ate: "2026-11-17T13:00:00Z", com_prazo_hoje: true, ouviu: true }),
  esp("número de 2 clientes", { phone: "5547900009103", desde: "2026-11-17T01:15:00Z", prometido_ate: "2026-11-17T13:00:00Z", com_prazo_hoje: true, ouviu: true }),
  esp("Rita", { phone: "5547900009104", desde: "2026-11-16T12:00:00Z", prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true, ouviu: true }),
];
const COM_PRAZO_LIGADO = [
  "Paulo (venceu ontem, prometi até 19h)",
  "número novo (desde ontem 21:40, prometi hoje até 10h)",
  "número de 2 clientes (desde ontem 22:15, prometi hoje até 10h)",
  "Rita (desde ontem 09:00, prometi hoje até 19h)",
];
const COM_PRAZO_SOMBRA = [
  "Paulo (desde ontem 16:02)",
  "número novo (desde ontem 21:40)",
  "número de 2 clientes (desde ontem 22:15)",
  "Rita (desde ontem 09:00)",
];

/** k sem prazo hoje, de 11/11 em diante (a ordem do banco: aberta_em). */
function semPrazo(k: number): EsperandoDoRetorno[] {
  return Array.from({ length: k }, (_, i) =>
    esp(`Cliente ${i + 1}`, { phone: `554790000920${i + 1}`, desde: `2026-11-1${i + 1}T12:14:00Z` }));
}
const SEM_PRAZO_TEXTO = ["Cliente 1 (desde 11/11 09:14)", "Cliente 2 (desde 12/11 09:14)", "Cliente 3 (desde 13/11 09:14)"];

/** n com prazo hoje que ouviram, com nome comprido (para o teto e para o corte da tarde). */
function muitos(n: number, prometido: string, desde: string): EsperandoDoRetorno[] {
  return Array.from({ length: n }, (_, i) =>
    esp(`Cliente com nome comprido ${i + 1}`, { phone: `55479000093${String(i).padStart(2, "0")}`, prometido_ate: prometido, com_prazo_hoje: true, ouviu: true, desde }));
}

function manha(modo: RetornoDaManha["modo"], esperando: EsperandoDoRetorno[], extra: Partial<RetornoDaManha> = {}): RetornoDaManha {
  return { modo, esperando, esperando_mais: 0, conferir: [], conferir_mais: 0, ...extra };
}

function fechamento(modo: RetornoDoFechamento["modo"], extra: Partial<RetornoDoFechamento> = {}): RetornoDoFechamento {
  return {
    modo, esperando: [], recebidos: 0, no_prazo: 0, adiados: 0, sem_palavra: 0, na_queda: 0,
    sombra: { teria_mandado: 0, por_papel: {}, respondeu_antes: 0 }, alongadas: [], ...extra,
  };
}

const NADA = new Set<string>();

/** Os itens de uma linha: [nomeados, o número do "e mais N" (0 sem ele)]. */
function contarItens(linha: string, cabeca: string): { nomeados: number; mais: number } {
  const partes = linha.slice(cabeca.length + 1, -1).split(" · ");
  let mais = 0;
  const nomeados = partes.filter((p) => {
    const m = /^e mais (\d+)/.exec(p);
    if (m) mais += Number(m[1]);
    return !m;
  });
  return { nomeados: nomeados.length, mais };
}

// ─── Manhã: "Clientes esperando" ────────────────────────────────────────────────────────────────

Deno.test("manhã, ligado: os 4 com prazo hoje sempre aparecem; dos sem prazo (0, 1, 3, 5) vão até 3 e o 'e mais' conta só os sem prazo", () => {
  for (const k of [0, 1, 3, 5]) {
    const { esperando } = linhasDaManha(manha("ligado", [...COM_PRAZO, ...semPrazo(k)]), NADA, MANHA);
    const partes = [...COM_PRAZO_LIGADO, ...SEM_PRAZO_TEXTO.slice(0, Math.min(k, 3)), ...(k > 3 ? [`e mais ${k - 3} sem prazo`] : [])];
    assertEquals(esperando, `Clientes esperando: ${partes.join(" · ")}.`, String(k));
  }
  // a forma que o banco manda (3 sem prazo + esperando_mais) dá a mesma linha
  assertEquals(
    linhasDaManha(manha("ligado", [...COM_PRAZO, ...semPrazo(3)], { esperando_mais: 2 }), NADA, MANHA).esperando,
    linhasDaManha(manha("ligado", [...COM_PRAZO, ...semPrazo(5)]), NADA, MANHA).esperando,
  );
  // só sem prazo: nenhuma promessa, até 3 e o resto contado
  assertEquals(
    linhasDaManha(manha("ligado", semPrazo(5)), NADA, MANHA).esperando,
    `Clientes esperando: ${SEM_PRAZO_TEXTO.join(" · ")} · e mais 2 sem prazo.`,
  );
});

Deno.test("manhã, sombra: nada foi prometido (só 'desde'), os 4 com prazo hoje sempre, e o 'e mais' sem a palavra 'prazo'", () => {
  for (const k of [0, 1, 3, 5]) {
    const { esperando } = linhasDaManha(manha("sombra", [...COM_PRAZO, ...semPrazo(k)]), NADA, MANHA);
    const partes = [...COM_PRAZO_SOMBRA, ...SEM_PRAZO_TEXTO.slice(0, Math.min(k, 3)), ...(k > 3 ? [`e mais ${k - 3}`] : [])];
    assertEquals(esperando, `Clientes esperando (em teste, nada foi prometido): ${partes.join(" · ")}.`, String(k));
    assert(!/\bprometi\b/.test(esperando!) && !esperando!.includes("venceu"), esperando!);
  }
});

Deno.test("manhã: a exclusão por jaNaLista vale só para os sem prazo (quem tem prazo hoje aparece mesmo com letra na manhã)", () => {
  const r = manha("ligado", [...COM_PRAZO, ...semPrazo(5)]);
  // Paulo (com prazo) e o Cliente 1 e o Cliente 2 (sem prazo) já são item da manhã
  const ja = new Set(["5547900009101", "5547900009201", "5547900009202"]);
  const { esperando } = linhasDaManha(r, ja, MANHA);
  assertEquals(esperando, `Clientes esperando: ${[...COM_PRAZO_LIGADO, "Cliente 3 (desde 13/11 09:14)",
    "Cliente 4 (desde 14/11 09:14)", "Cliente 5 (desde 15/11 09:14)"].join(" · ")}.`);
  // os de fora não entram no "e mais" (já estão na manhã com letra)
  assert(!esperando!.includes("e mais"));
  // todos os sem prazo já na manhã e mais 2 contados pelo banco: a contagem fica sozinha
  const todos = new Set(semPrazo(3).map((e) => e.phone));
  assertEquals(linhasDaManha(manha("ligado", semPrazo(3), { esperando_mais: 2 }), todos, MANHA).esperando,
    "Clientes esperando: 2 contatos sem prazo.");
  assertEquals(linhasDaManha(manha("ligado", semPrazo(3)), todos, MANHA).esperando, null, "nada sobrou");
});

Deno.test("manhã: 'venceu ontem', o prazo de amanhã, o rótulo limpo e o que não tem data", () => {
  const r = manha("ligado", [
    esp("Paulo", { venceu: true, com_prazo_hoje: true, prometido_ate: "2026-11-16T22:00:00Z", ouviu: true }),
    esp("Bia", { venceu: true, com_prazo_hoje: true, prometido_ate: "2026-11-13T22:30:00Z", ouviu: true }),
    esp("Caio", { desde: "2026-11-16T15:00:00Z", prometido_ate: "2026-11-18T13:00:00Z", ouviu: true }),
    esp("Davi", { desde: "data inválida" }),
  ]);
  assertEquals(linhasDaManha(r, NADA, MANHA).esperando, "Clientes esperando: Paulo (venceu ontem, prometi até 19h) · " +
    "Bia (venceu 13/11, prometi até 19:30) · Caio (desde ontem 12:00, prometi amanhã até 10h) · Davi.");
});

Deno.test("manhã: 'Para conferir' com os três motivos e o 'e mais'; nada = null; sem leitura = null", () => {
  const conferir: ConferirDoRetorno[] = [
    { phone: "5547900009111", rotulo: "Paulo", motivo: "parar_largo", desde: "2026-11-16T20:00:00Z" },
    { phone: "5547900009112", rotulo: "número novo", motivo: "opt_out", desde: "2026-11-16T21:00:00Z" },
    { phone: "5547900009113", rotulo: "Rita", motivo: "atraso_longo", desde: "2026-11-15T12:00:00Z" },
  ];
  const esperado = "Para conferir: Paulo (pediu para parar?) · número novo (pediu PARAR e voltou a escrever) · " +
    "Rita (escreveu na queda, há 2 dias) · e mais 1.";
  assertEquals(linhasDaManha(manha("ligado", [], { conferir, conferir_mais: 1 }), NADA, MANHA), { esperando: null, conferir: esperado });
  // a sombra mostra o mesmo "Para conferir" (o PARAR estreito vale desde a F0b; o largo pede o olho do dono)
  assertEquals(linhasDaManha(manha("sombra", [], { conferir, conferir_mais: 1 }), NADA, MANHA).conferir, esperado);
  // 4 no array: 3 nomeados e "e mais 1"
  const quatro = [...conferir, { ...conferir[0], rotulo: "Zé" }];
  assertEquals(linhasDaManha(manha("ligado", [], { conferir: quatro }), NADA, MANHA).conferir, esperado);
  // ontem e hoje
  const atraso = (desde: string) => linhasDaManha(manha("ligado", [], { conferir: [{ ...conferir[2], desde }] }), NADA, MANHA).conferir;
  assertEquals(atraso("2026-11-16T12:00:00Z"), "Para conferir: Rita (escreveu na queda, ontem).");
  assertEquals(atraso("2026-11-17T09:00:00Z"), "Para conferir: Rita (escreveu na queda).");
  assertEquals(linhasDaManha(manha("ligado", COM_PRAZO), NADA, MANHA).conferir, null);
  assertEquals(linhasDaManha(null, NADA, MANHA), { esperando: null, conferir: null });
});

// (correção, problema 2) o ligado entra por grupo (seção 8): só o recibo de dia útil das 07:00 às 15:29 sai ligado, e os
// outros casos têm prometido_ate simulado. "prometi" só para quem ouviu.
Deno.test("manhã, ligado misto: 'prometi' só para quem ouviu; quem ficou em sombra sai com 'nada prometido'", () => {
  const r = manha("ligado", [
    esp("Paulo", { desde: "2026-11-16T12:00:00Z", prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true, ouviu: true }),
    esp("Bia", { desde: "2026-11-17T00:40:00Z", prometido_ate: "2026-11-17T13:00:00Z", com_prazo_hoje: true }),
    esp("Caio", { desde: "2026-11-16T19:02:00Z", prometido_ate: "2026-11-16T22:00:00Z", venceu: true, com_prazo_hoje: true, ouviu: false }),
    esp("Davi"),
  ]);
  const { esperando } = linhasDaManha(r, NADA, MANHA);
  assertEquals(esperando, "Clientes esperando: Paulo (desde ontem 09:00, prometi hoje até 19h) · Bia (desde ontem 21:40, nada prometido) · " +
    "Caio (desde ontem 16:02, nada prometido) · Davi (desde ontem 09:00).");
  // ninguém ouviu: nenhum "prometi", nenhum "venceu"
  const ninguem = linhasDaManha(manha("ligado", r.esperando.slice(1)), NADA, MANHA).esperando!;
  assert(!/\bprometi\b/.test(ninguem) && !ninguem.includes("venceu"), ninguem);
});

// (correção, problema 3) o adiamento grava segundo_prazo (X2) e mantém prometido_ate: o cliente ouviu a 2ª hora
Deno.test("caso adiado (10h para 19h): a manhã e a tarde mostram a promessa de pé, 'prometi até 19h'", () => {
  const adiado = esp("Paulo", {
    desde: "2026-11-17T12:14:00Z", prometido_ate: "2026-11-17T13:00:00Z", segundo_prazo: "2026-11-17T22:00:00Z", com_prazo_hoje: true, ouviu: true,
  });
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: [adiado] }), TARDE).esperando, "Ainda esperando hoje: Paulo (prometi até 19h).");
  assertEquals(linhasDaManha(manha("ligado", [adiado]), NADA, MANHA).esperando, "Clientes esperando: Paulo (desde 09:14, prometi hoje até 19h).");
  // na manhã seguinte, vencido: venceu o X2
  const vencido = { ...adiado, venceu: true };
  assertEquals(linhasDaManha(manha("ligado", [vencido]), NADA, MANHA_SEGUINTE).esperando, "Clientes esperando: Paulo (venceu ontem, prometi até 19h).");
  // sem segundo_prazo, a P9 já pôs o vigente em prometido_ate: a mesma linha
  const vigente = { ...adiado, prometido_ate: adiado.segundo_prazo!, segundo_prazo: undefined };
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: [vigente] }), TARDE).esperando, "Ainda esperando hoje: Paulo (prometi até 19h).");
});

// (correção, problema 7) o rótulo do número novo com a coleta 2 enviada é o nome que ele disse ("Ana")
Deno.test("número novo com nome: 'número novo' ao lado do nome, na manhã, na tarde e na sombra; sem repetir no rótulo 'número novo'", () => {
  const ana = esp("Ana", { papel: "numero_novo", desde: "2026-11-17T00:40:00Z", prometido_ate: "2026-11-17T13:00:00Z", com_prazo_hoje: true, ouviu: true });
  assertEquals(linhasDaManha(manha("ligado", [ana]), NADA, MANHA).esperando,
    "Clientes esperando: Ana (número novo, desde ontem 21:40, prometi hoje até 10h).");
  assertEquals(linhasDaManha(manha("sombra", [ana]), NADA, MANHA).esperando,
    "Clientes esperando (em teste, nada foi prometido): Ana (número novo, desde ontem 21:40).");
  const ate19 = { ...ana, prometido_ate: "2026-11-17T22:00:00Z" };
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: [ate19] }), TARDE).esperando, "Ainda esperando hoje: Ana (número novo, prometi até 19h).");
  // o rótulo já é "número novo" (a coleta 2 não saiu): não repete
  assertEquals(linhasDaManha(manha("ligado", [{ ...ana, rotulo: "número novo" }]), NADA, MANHA).esperando,
    "Clientes esperando: número novo (desde ontem 21:40, prometi hoje até 10h).");
  // cliente cadastrado: nada a acrescentar
  assertEquals(linhasDaManha(manha("ligado", [{ ...ana, papel: "cliente" }]), NADA, MANHA).esperando,
    "Clientes esperando: Ana (desde ontem 21:40, prometi hoje até 10h).");
});

// (correção, problema 9) 'desligado' é a alavanca de recuo: o vigia para, e quem já ouviu a promessa continua esperando
Deno.test("manhã, desligado: só quem ouviu a promessa, na forma ligada e marcada; sem 'Para conferir'; ninguém que ouviu = null", () => {
  const conferir: ConferirDoRetorno[] = [{ phone: "5547900009161", rotulo: "Zé", motivo: "parar_largo", desde: "2026-11-16T20:00:00Z" }];
  const naoOuviu = esp("Bia", { phone: "5547900009162", prometido_ate: "2026-11-17T13:00:00Z", com_prazo_hoje: true });
  const r = manha("desligado", [...COM_PRAZO, naoOuviu, ...semPrazo(2)], { conferir, esperando_mais: 4 });
  assertEquals(linhasDaManha(r, NADA, MANHA), {
    esperando: `Clientes esperando (retorno desligado): ${COM_PRAZO_LIGADO.join(" · ")}.`,
    conferir: null,
  });
  assertEquals(linhasDaManha(manha("desligado", [naoOuviu, ...semPrazo(2)], { conferir }), NADA, MANHA), { esperando: null, conferir: null });
});

// ─── Fechamento ─────────────────────────────────────────────────────────────────────────────────

const DO_FECHAMENTO: EsperandoDoRetorno[] = [
  esp("Paulo", { desde: "2026-11-17T12:14:00Z", prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true, ouviu: true }),
  esp("Ana", { desde: "2026-11-16T19:02:00Z", prometido_ate: "2026-11-16T22:00:00Z", venceu: true, com_prazo_hoje: true, ouviu: true }),
];

Deno.test("fechamento: 'Ainda esperando hoje' com todos os itens, ligado e sombra; 'venceu hoje às 10h'; nada = null", () => {
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: DO_FECHAMENTO }), TARDE),
    { esperando: "Ainda esperando hoje: Paulo (prometi até 19h) · Ana (venceu ontem).", resumo: null, fixa: true });
  // na sombra nada foi prometido: a linha é extra (fixa = false)
  assertEquals(linhasDoFechamento(fechamento("sombra", { esperando: DO_FECHAMENTO }), TARDE),
    { esperando: "Ainda esperando hoje (em teste): Paulo (desde 09:14) · Ana (desde ontem 16:02).", resumo: null, fixa: false });
  const rui = esp("Rui", { prometido_ate: "2026-11-17T13:00:00Z", venceu: true, com_prazo_hoje: true, ouviu: true });
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: [rui] }), TARDE).esperando, "Ainda esperando hoje: Rui (venceu hoje às 10h).");
  // sem limite: 12 itens, os 12 na linha
  const doze = Array.from({ length: 12 }, (_, i) => esp(`C${i}`, { prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true, ouviu: true }));
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: doze }), TARDE).esperando!.split(" · ").length, 12);
  assertEquals(linhasDoFechamento(fechamento("ligado"), TARDE), { esperando: null, resumo: null, fixa: false });
  assertEquals(linhasDoFechamento(null, TARDE), { esperando: null, resumo: null, fixa: false });
});

Deno.test("fechamento, ligado misto: 'prometi' só para quem ouviu; a linha é fixa só com alguém que ouviu", () => {
  const bia = esp("Bia", { desde: "2026-11-17T12:14:00Z", prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true });
  assertEquals(linhasDoFechamento(fechamento("ligado", { esperando: [DO_FECHAMENTO[0], bia] }), TARDE),
    { esperando: "Ainda esperando hoje: Paulo (prometi até 19h) · Bia (desde 09:14, nada prometido).", resumo: null, fixa: true });
  const so = linhasDoFechamento(fechamento("ligado", { esperando: [bia] }), TARDE);
  assertEquals(so, { esperando: "Ainda esperando hoje: Bia (desde 09:14, nada prometido).", resumo: null, fixa: false });
});

Deno.test("fechamento, desligado: só quem ouviu, marcada e fixa; sem resumo; ninguém que ouviu = null", () => {
  const bia = esp("Bia", { prometido_ate: "2026-11-17T22:00:00Z", com_prazo_hoje: true });
  assertEquals(linhasDoFechamento(fechamento("desligado", { esperando: [...DO_FECHAMENTO, bia], recebidos: 3, no_prazo: 2 }), TARDE), {
    esperando: "Ainda esperando hoje (retorno desligado): Paulo (prometi até 19h) · Ana (venceu ontem).", resumo: null, fixa: true,
  });
  assertEquals(linhasDoFechamento(fechamento("desligado", { esperando: [bia], recebidos: 3 }), TARDE), { esperando: null, resumo: null, fixa: false });
});

Deno.test("fechamento, ligado: 'Retorno hoje' com singular e plural certos e a queda à parte; sem recebidos = null", () => {
  const resumo = (x: Partial<RetornoDoFechamento>) => linhasDoFechamento(fechamento("ligado", x), TARDE).resumo;
  assertEquals(resumo({ recebidos: 9, no_prazo: 7, adiados: 1, sem_palavra: 0 }), "Retorno hoje: 9 recebidos, 7 no prazo, 1 adiado, 0 sem palavra.");
  assertEquals(resumo({ recebidos: 9, no_prazo: 7, adiados: 1, sem_palavra: 0, na_queda: 1 }),
    "Retorno hoje: 9 recebidos, 7 no prazo, 1 adiado, 0 sem palavra. (1 venceu com o WhatsApp fora.)");
  assertEquals(resumo({ recebidos: 1, no_prazo: 0, adiados: 2, sem_palavra: 1, na_queda: 2 }),
    "Retorno hoje: 1 recebido, 0 no prazo, 2 adiados, 1 sem palavra. (2 venceram com o WhatsApp fora.)");
  assertEquals(resumo({ recebidos: 0 }), null);
  // no ligado, a frase da sombra não aparece
  assertEquals(resumo({ recebidos: 0, sombra: { teria_mandado: 3, por_papel: { cliente: 3 }, respondeu_antes: 1 } }), null);
  // sem palavra de ação (*ver retorno* é da F2)
  assert(!resumo({ recebidos: 9, no_prazo: 7, adiados: 1 })!.includes("*"));
});

Deno.test("fechamento, sombra: 'eu teria mandado' com os papéis na ordem fixa, singular e plural; nada a dizer = null", () => {
  const resumo = (s: RetornoDoFechamento["sombra"]) => linhasDoFechamento(fechamento("sombra", { sombra: s }), TARDE).resumo;
  // a ordem é a fixa, não a do objeto
  assertEquals(resumo({ teria_mandado: 6, por_papel: { numero_novo: 2, cliente: 4 }, respondeu_antes: 2 }),
    "Em teste (retorno): eu teria mandado 6 recibos hoje (4 a clientes, 2 a números novos); você respondeu 2 antes.");
  assertEquals(resumo({ teria_mandado: 1, por_papel: { cliente: 1 }, respondeu_antes: 0 }),
    "Em teste (retorno): eu teria mandado 1 recibo hoje (1 a cliente).");
  assertEquals(resumo({ teria_mandado: 4, por_papel: { cliente_parceiro: 1, numero_novo: 1, cliente_ambiguo: 1, cliente: 1 }, respondeu_antes: 1 }),
    "Em teste (retorno): eu teria mandado 4 recibos hoje (1 a cliente, 1 a número de mais de um cliente, 1 a número novo, " +
      "1 a cliente de parceiro); você respondeu 1 antes.");
  // o que o banco não pôs em papel nenhum (ou pôs num papel desconhecido) aparece como "outros": a soma fecha
  assertEquals(resumo({ teria_mandado: 5, por_papel: { cliente: 2, x: 1 }, respondeu_antes: 0 }),
    "Em teste (retorno): eu teria mandado 5 recibos hoje (2 a clientes, 3 a outros).");
  assertEquals(resumo({ teria_mandado: 2, por_papel: {}, respondeu_antes: 0 }), "Em teste (retorno): eu teria mandado 2 recibos hoje.");
  assertEquals(resumo({ teria_mandado: 0, por_papel: {}, respondeu_antes: 2 }),
    "Em teste (retorno): eu não teria mandado nenhum recibo hoje; você respondeu 2 antes.");
  assertEquals(resumo({ teria_mandado: 0, por_papel: {}, respondeu_antes: 0 }), null);
  // a sombra não diz "Retorno hoje" (nada saiu)
  assertEquals(linhasDoFechamento(fechamento("sombra", { recebidos: 5, no_prazo: 3 }), TARDE).resumo, null);
});

Deno.test("fechamento: as alongadas, uma frase por faixa, só na sexta", () => {
  const alongadas: RetornoDoFechamento["alongadas"] = [
    { faixa: "manha_cedo", de: { dias: 0, hora: "19:00" }, para: { dias: 1, hora: "10:00" }, casos: 25, pct: 0.72 },
    { faixa: "tarde", de: { dias: 0, hora: "10:00" }, para: { dias: 0, hora: "19:00" }, casos: 20, pct: 0.75 },
  ];
  const sexta = linhasDoFechamento(fechamento("ligado", { alongadas }), SEXTA).resumo;
  assertEquals(sexta, 'Prazo alongado: quem escreve de manhã passa a ouvir "amanhã até as 10h" (você cumpriu 72% de 25). ' +
    'Prazo alongado: quem escreve à tarde passa a ouvir "amanhã até as 19h" (você cumpriu 75% de 20).');
  assertEquals(linhasDoFechamento(fechamento("ligado", { alongadas }), QUINTA).resumo, null, "fora da sexta, nada");
  // junto com o "Retorno hoje"
  assertEquals(linhasDoFechamento(fechamento("ligado", { recebidos: 2, no_prazo: 2, alongadas: alongadas.slice(0, 1) }), SEXTA).resumo,
    'Retorno hoje: 2 recebidos, 2 no prazo, 0 adiados, 0 sem palavra. Prazo alongado: quem escreve de manhã passa a ouvir ' +
      '"amanhã até as 10h" (você cumpriu 72% de 25).');
});

// ─── Teto da linha (o CHECK de 4.000 caracteres do texto gravado) ──────────────────────────────

Deno.test("teto: 60 com prazo hoje vão na forma curta, todos nomeados; 90, os nomes até caber e o resto contado (ninguém some)", () => {
  const cabeca = "Clientes esperando:";
  // 4 com prazo: a forma de sempre, longe do teto
  assert(linhasDaManha(manha("ligado", COM_PRAZO), NADA, MANHA).esperando!.length < 300);
  const sessenta = linhasDaManha(manha("ligado", muitos(60, "2026-11-17T22:00:00Z", "2026-11-16T12:00:00Z")), NADA, MANHA).esperando!;
  assert(sessenta.length <= TETO_DA_LINHA, `${sessenta.length}`);
  assert(!sessenta.includes("prometi"), "a forma curta é só o nome");
  assertEquals(contarItens(sessenta, cabeca), { nomeados: 60, mais: 0 });
  // 90 com prazo e 5 sem prazo (3 nomeáveis + 2 do banco): os sem prazo saem primeiro para a contagem
  const r90 = manha("ligado", [...muitos(90, "2026-11-17T22:00:00Z", "2026-11-16T12:00:00Z"), ...semPrazo(3)], { esperando_mais: 2 });
  const noventa = linhasDaManha(r90, NADA, MANHA).esperando!;
  assert(noventa.length <= TETO_DA_LINHA, `${noventa.length}`);
  const c = contarItens(noventa, cabeca);
  assertEquals(c.nomeados + c.mais, 90 + 5, noventa);
  assert(/e mais \d+ com prazo hoje · e mais 5 sem prazo\.$/.test(noventa), noventa);
  // a tarde, com o mesmo teto
  const tarde = linhasDoFechamento(fechamento("ligado", { esperando: muitos(90, "2026-11-17T22:00:00Z", "2026-11-17T12:00:00Z") }), TARDE).esperando!;
  assert(tarde.length <= TETO_DA_LINHA, `${tarde.length}`);
  const ct = contarItens(tarde, "Ainda esperando hoje:");
  assertEquals(ct.nomeados + ct.mais, 90);
});

// ─── Leitura (C-RESUMO) ─────────────────────────────────────────────────────────────────────────

function falsoRpc(resposta: { data?: unknown; error?: unknown } | "lanca") {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: unknown) {
        chamadas.push({ nome, args });
        if (resposta === "lanca") throw new Error("rede");
        return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
      },
    },
  };
}

Deno.test("lerRetorno: chama retorno_resumo_do_dia com p_turno e p_agora e confere a forma (rótulo limpo, venceu = com prazo hoje)", async () => {
  const f = falsoRpc({
    data: {
      modo: "ligado",
      esperando: [
        { phone: "5547900009121", rotulo: "(número de 2 clientes)", desde: "2026-11-16T12:00:00Z", prometido_ate: "2026-11-16T22:00:00Z", venceu: true, com_prazo_hoje: false },
        { phone: "5547900009122", rotulo: "*Ana*  \n🙂 Souza", desde: "2026-11-16T12:00:00Z", prometido_ate: null, venceu: false, com_prazo_hoje: false },
        "lixo",
      ],
      esperando_mais: "2",
      conferir: [{ phone: "5547900009123", rotulo: "", motivo: "parar_largo", desde: "2026-11-16T12:00:00Z" }, { motivo: "outro" }],
      conferir_mais: 1,
    },
  });
  const r = await lerRetorno(f.admin, "manha", MANHA);
  assertEquals(f.chamadas, [{ nome: "retorno_resumo_do_dia", args: { p_turno: "manha", p_agora: MANHA.toISOString() } }]);
  assertEquals(r, {
    modo: "ligado",
    esperando: [
      { phone: "5547900009121", rotulo: "número de 2 clientes", desde: "2026-11-16T12:00:00Z", prometido_ate: "2026-11-16T22:00:00Z", venceu: true, com_prazo_hoje: true },
      { phone: "5547900009122", rotulo: "Ana Souza", desde: "2026-11-16T12:00:00Z", prometido_ate: null, venceu: false, com_prazo_hoje: false },
    ],
    esperando_mais: 2,
    conferir: [{ phone: "5547900009123", rotulo: "sem nome", motivo: "parar_largo", desde: "2026-11-16T12:00:00Z" }],
    // o motivo desconhecido não some calado: vai para o "e mais"
    conferir_mais: 2,
  });
});

Deno.test("lerRetorno: os campos que a P9 acrescenta (segundo_prazo, ouviu, papel) passam; ouviu que não é true fica de fora", async () => {
  const item = { phone: "5547900009124", rotulo: "Ana", desde: "2026-11-17T00:40:00Z", prometido_ate: "2026-11-17T13:00:00Z", venceu: false, com_prazo_hoje: true };
  const f = falsoRpc({
    data: {
      modo: "ligado", conferir: [],
      esperando: [
        { ...item, segundo_prazo: "2026-11-17T22:00:00Z", ouviu: true, papel: "numero_novo" },
        { ...item, phone: "5547900009125", ouviu: "sim", segundo_prazo: null, papel: "" },
      ],
    },
  });
  const r = await lerRetorno(f.admin, "manha", MANHA);
  assertEquals(r?.esperando, [
    { ...item, segundo_prazo: "2026-11-17T22:00:00Z", ouviu: true, papel: "numero_novo" },
    { ...item, phone: "5547900009125" },
  ]);
  assertEquals(linhasDaManha(r, NADA, MANHA).esperando,
    "Clientes esperando: Ana (número novo, desde ontem 21:40, prometi hoje até 19h) · Ana (desde ontem 21:40, nada prometido).");
});

Deno.test("lerRetorno: erro, função ausente, exceção, sem rpc e forma inesperada = null (nunca lança)", async () => {
  const casos: Array<[string, { data?: unknown; error?: unknown } | "lanca"]> = [
    ["função ausente", { error: { code: "PGRST202", message: "Could not find the function" } }],
    ["erro do banco", { error: { code: "XX000" } }],
    ["exceção", "lanca"],
    ["vazio", { data: null }],
    ["turno errado", { data: { erro: "turno" } }],
    ["modo desconhecido", { data: { modo: "talvez", esperando: [], conferir: [] } }],
    ["esperando não é lista", { data: { modo: "ligado", esperando: {}, conferir: [] } }],
    ["conferir é texto", { data: { modo: "ligado", esperando: [], conferir: "x" } }],
    ["lista em vez de objeto", { data: [] }],
  ];
  for (const [nome, resposta] of casos) {
    assertEquals(await lerRetorno(falsoRpc(resposta).admin, "manha", MANHA), null, nome);
  }
  assertEquals(await lerRetorno({}, "fechamento", TARDE), null, "sem rpc");
  assertEquals(await lerRetorno(falsoRpc({ data: { modo: "ligado", esperando: "x" } }).admin, "fechamento", TARDE), null);
  // desligado é lido (e, sem ninguém que ouviu, as linhas ficam nulas)
  const desl = await lerRetorno(falsoRpc({ data: { modo: "desligado", esperando: [], conferir: [] } }).admin, "manha", MANHA);
  assertEquals(desl?.modo, "desligado");
  assertEquals(linhasDaManha(desl, NADA, MANHA), { esperando: null, conferir: null });
});

// (correção, problemas 4 e 13) jsonb_agg de zero linhas é NULL: uma lista vazia que chega como null não apaga a outra
Deno.test("lerRetorno: lista null ou ausente vale vazia — 'Clientes esperando' fica sem conferir; o resumo fica sem esperando", async () => {
  const item = { phone: "5547900009126", rotulo: "Paulo", desde: "2026-11-16T12:00:00Z", prometido_ate: "2026-11-17T22:00:00Z", venceu: false, com_prazo_hoje: true, ouviu: true };
  for (const conferir of [null, undefined]) {
    const r = await lerRetorno(falsoRpc({ data: { modo: "ligado", esperando: [item], conferir } }).admin, "manha", MANHA);
    assertEquals(linhasDaManha(r, NADA, MANHA), { esperando: "Clientes esperando: Paulo (desde ontem 09:00, prometi hoje até 19h).", conferir: null }, String(conferir));
  }
  const soConferir = await lerRetorno(falsoRpc({
    data: { modo: "ligado", esperando: null, conferir: [{ phone: "5547900009127", rotulo: "Zé", motivo: "opt_out", desde: "2026-11-16T12:00:00Z" }] },
  }).admin, "manha", MANHA);
  assertEquals(linhasDaManha(soConferir, NADA, MANHA), { esperando: null, conferir: "Para conferir: Zé (pediu PARAR e voltou a escrever)." });
  const tarde = await lerRetorno(falsoRpc({
    data: { modo: "sombra", esperando: null, sombra: { teria_mandado: 2, por_papel: { cliente: 2 }, respondeu_antes: 0 } },
  }).admin, "fechamento", TARDE);
  assertEquals(linhasDoFechamento(tarde, TARDE), { esperando: null, resumo: "Em teste (retorno): eu teria mandado 2 recibos hoje (2 a clientes).", fixa: false });
});

// (correção, problemas 5 e 12) como a agenda do fechamento depois de 28/10 (falhouNaAgenda): o erro fica consultável
Deno.test("lerRetorno: o erro e a forma inesperada vão para app_error_logs (retorno:<turno>); a função ausente e o vazio, não", async () => {
  const logs = (f: ReturnType<typeof falsoRpc>) =>
    f.chamadas.filter((c) => c.nome === "log_app_error").map((c) => c.args as Record<string, unknown>);
  const erro = falsoRpc({ error: { code: "XX000", message: "deu errado" } });
  assertEquals(await lerRetorno(erro.admin, "manha", MANHA), null);
  const l = logs(erro);
  assertEquals(l.length, 1);
  assertEquals([l[0].p_source, l[0].p_context, l[0].p_action, l[0].p_level], ["edge", "ai-daily-briefing", "retorno:manha", "error"]);
  assertEquals(l[0].p_details, { codigo: "XX000" });
  assertEquals(l[0].p_message, "retorno: a leitura de retorno_resumo_do_dia (manha) falhou: deu errado");
  const tempo = falsoRpc({ error: { code: "57014", message: "canceling statement due to statement timeout" } });
  await lerRetorno(tempo.admin, "fechamento", TARDE);
  assertEquals(logs(tempo).map((x) => [x.p_action, String(x.p_message).includes("por tempo esgotado")]), [["retorno:fechamento", true]]);
  const forma = falsoRpc({ data: { modo: "talvez", esperando: [] } });
  await lerRetorno(forma.admin, "fechamento", TARDE);
  assertEquals(logs(forma).map((x) => [x.p_action, x.p_details]), [["retorno:fechamento", { codigo: "forma_inesperada" }]]);
  // a exceção também; o log que falha não lança
  const lanca = falsoRpc("lanca");
  assertEquals(await lerRetorno(lanca.admin, "manha", MANHA), null);
  assertEquals(lanca.chamadas.map((c) => c.nome), ["retorno_resumo_do_dia", "log_app_error"]);
  // a função ainda não publicada (antes de 16/11) e o vazio: nada a registrar
  for (const resposta of [{ error: { code: "PGRST202", message: "Could not find the function" } }, { error: { code: "42883" } }, { data: null }]) {
    const f = falsoRpc(resposta);
    await lerRetorno(f.admin, "manha", MANHA);
    assertEquals(logs(f), [], JSON.stringify(resposta));
  }
});

// ─── textoDaManha: "Clientes esperando" nunca sai; "Para conferir" sai primeiro ─────────────────

function base1510() {
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  return { hoje: HOJE_1510, tipoDoDia: "util" as const, feriado: null, selecao, naRua: { total: 21026, n: 5 }, deHoje: deHoje1510() };
}

Deno.test("textoDaManha: sem o retorno (ou com as duas linhas nulas) o texto é o de antes, byte a byte", () => {
  const b = base1510();
  const antes = textoDaManha(b);
  assertEquals(textoDaManha({ ...b, retorno: null }), antes);
  assertEquals(textoDaManha({ ...b, retorno: { esperando: null, conferir: null } }), antes);
  const vazio = { ...b, selecao: selecionar([], [], HOJE_1510), naRua: { total: 0, n: 0 } };
  assertEquals(textoDaManha({ ...vazio, retorno: { esperando: null, conferir: null } }), textoDaManha(vazio));
  // domingo e feriado: a linha de sempre (o retorno não entra)
  const domingo = { ...b, hoje: "2026-10-18", tipoDoDia: "domingo" as const };
  assertEquals(textoDaManha({ ...domingo, retorno: { esperando: "Clientes esperando: X.", conferir: "Para conferir: Y." } }), textoDaManha(domingo));
});

Deno.test("textoDaManha: o retorno entra logo depois da abertura e do 'Na rua', antes dos itens; sem item, a abertura não diz 'Nada precisa de você'", () => {
  const b = { ...base1510(), selecao: selecionar([], [], HOJE_1510) };
  const t = textoDaManha({ ...b, retorno: { esperando: "Clientes esperando: Paulo (venceu ontem, prometi até 19h).", conferir: "Para conferir: Rita (pediu para parar?)." } });
  assertEquals(t.split("\n"), [
    "Bom dia! Quinta, 15/10.",
    "Na rua: R$ 21.026,00 vencidos (5).",
    "Clientes esperando: Paulo (venceu ontem, prometi até 19h).",
    "Para conferir: Rita (pediu para parar?).",
    "",
    "Hoje: nada na agenda. Promessa sua: Eng.⁰ Rafael Borges DOMETIC (Claro, te passo agora!). Amanhã vence: R$ 5.237,99 a receber (APOLO INDUSTRIA E COMER…).",
  ]);
  // só "Para conferir": a abertura de antes
  const so = textoDaManha({ ...b, retorno: { esperando: null, conferir: "Para conferir: Rita (pediu para parar?)." } });
  assertEquals(so.split("\n")[0], "Bom dia! Quinta, 15/10. Nada precisa de você hoje.");
  // com itens, a abertura é a de sempre
  assertEquals(textoDaManha({ ...base1510(), retorno: { esperando: "Clientes esperando: X.", conferir: null } }).split("\n")[0],
    textoDaManha(base1510()).split("\n")[0]);
});

Deno.test("textoDaManha estourando a meta: 'Para conferir' fica enquanto o resto encurta, sai antes de 'Clientes esperando', que nunca sai", () => {
  const b = base1510();
  // 1) só "Para conferir": o laço com ela encurta o resto (o "logo abaixo" perde os nomes) e ela fica
  const conferirCurto = "Para conferir: Paulo (pediu para parar?).";
  const t1 = textoDaManha({ ...b, retorno: { esperando: null, conferir: conferirCurto } });
  assertStringIncludes(t1, conferirCurto);
  assertStringIncludes(t1, "Guardei 14 assuntos. *lista*");
  assert(t1.length <= META_DE_CARACTERES, `${t1.length}`);
  // 2) "Clientes esperando" + um "Para conferir" que não cabe junto em combinação nenhuma: sai o "Para conferir", só ele
  const esperando = linhasDaManha(manha("ligado", COM_PRAZO.slice(0, 1)), NADA, AGORA_1510).esperando!;
  const conferirLongo = linhasDaManha(manha("ligado", [], {
    conferir: [
      { phone: "5547900009131", rotulo: "Paulo Henrique", motivo: "parar_largo", desde: "2026-10-14T20:00:00Z" },
      { phone: "5547900009132", rotulo: "número novo", motivo: "opt_out", desde: "2026-10-14T20:00:00Z" },
      { phone: "5547900009133", rotulo: "Rita de Cássia", motivo: "atraso_longo", desde: "2026-10-13T20:00:00Z" },
    ],
    conferir_mais: 4,
  }), NADA, AGORA_1510).conferir!;
  const t2 = textoDaManha({ ...b, retorno: { esperando, conferir: conferirLongo } });
  assertStringIncludes(t2, esperando);
  assert(!t2.includes("Para conferir"), t2);
  assertEquals(t2, textoDaManha({ ...b, retorno: { esperando, conferir: null } }));
  assert(t2.length <= META_DE_CARACTERES, `${t2.length}`);
  // 3) "Clientes esperando" enorme (16 com prazo hoje): nada cabe, e ela continua inteira, mesmo passando da meta
  const dezesseis = muitos(16, "2026-10-15T22:00:00Z", "2026-10-14T20:00:00Z");
  const enorme = linhasDaManha(manha("ligado", dezesseis), NADA, AGORA_1510).esperando!;
  const t3 = textoDaManha({ ...b, retorno: { esperando: enorme, conferir: conferirCurto } });
  assert(t3.length > META_DE_CARACTERES, `${t3.length}`);
  assertStringIncludes(t3, enorme);
  assert(!t3.includes("Para conferir"), "sai primeiro");
  // a forma mais curta de tudo: "Hoje" curto, "logo abaixo" sem nomes, e os 3 itens da manhã (nunca some um item)
  assertStringIncludes(t3, "Guardei 14 assuntos. *lista*");
  for (const l of ["*A.*", "*B.*", "*C.*"]) assertStringIncludes(t3, l);
});

// (correção, problemas 6 e 11) o CHECK de resumo_manha.texto_novo: 90 com prazo hoje não derrubam a manhã
Deno.test("textoDaManha com 90 com prazo hoje: o texto fica abaixo dos 4.000 do banco, com os 3 itens da manhã", () => {
  const linha = linhasDaManha(manha("ligado", muitos(90, "2026-10-15T22:00:00Z", "2026-10-14T20:00:00Z")), NADA, AGORA_1510).esperando!;
  const t = textoDaManha({ ...base1510(), retorno: { esperando: linha, conferir: "Para conferir: Paulo (pediu para parar?)." } });
  assert(t.length <= LIMITE_DO_BANCO, `${t.length}`);
  assertStringIncludes(t, linha);
  for (const l of ["*A.*", "*B.*", "*C.*"]) assertStringIncludes(t, l);
});

Deno.test("montarDosDados: o retorno da manhã passa por linhasDaManha com os telefones da manhã; sem ele, o texto de antes", () => {
  const b = { hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
    escritorio: { propostas: null, alertas: 0, regras: null, debitosSemLoja: 0, entradas: null } };
  const antes = montarDosDados(b).texto;
  assertEquals(montarDosDados({ ...b, retorno: null }).texto, antes);
  // o Jorge (item B da manhã, com prazo hoje) aparece; o Cesar (item A, sem prazo) não repete; o Lírio (sem prazo) aparece
  const r = manha("sombra", [
    esp("Jorge", { phone: "5547900000001", desde: "2026-10-14T17:53:05Z", prometido_ate: "2026-10-15T13:00:00Z", com_prazo_hoje: true }),
    esp("Cesar", { phone: "5511900000002", desde: "2026-10-14T15:23:16Z" }),
    esp("Lírio", { phone: "5547900009141", desde: "2026-10-13T12:00:00Z" }),
  ]);
  const t = montarDosDados({ ...b, retorno: r }).texto;
  assertStringIncludes(t, "Clientes esperando (em teste, nada foi prometido): Jorge (desde ontem 14:53) · Lírio (desde 13/10 09:00).");
  assertEquals(t.split("\n")[2], "Clientes esperando (em teste, nada foi prometido): Jorge (desde ontem 14:53) · Lírio (desde 13/10 09:00).");
});

// ─── textoDaTarde: "Ainda esperando hoje" nunca sai; o resumo sai primeiro ──────────────────────

const ESCRITORIO = { propostas: { saidas: 46, entradas: 4, transferencias: 0, outras: 0 }, alertas: 15, regras: 103, debitosSemLoja: 6, entradas: { doMes: 4, sinais: 2, antigas: 6 } };

function dados(extra: Partial<DadosDaTarde> = {}): DadosDaTarde {
  return {
    hoje: "2026-10-15", turno: "fechamento", ficaram: [], amanha: { dia: "2026-10-16", itens: [] }, fornecedores: [], escritorio: ESCRITORIO,
    parados: [], panorama: null, antigas: null, mesQueFechou: null, faturamento: null, pergunta: false, ...extra,
  };
}

function linha(letra: string, texto: string, extra: Partial<LinhaComLetra> = {}): LinhaComLetra {
  return {
    letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto",
    alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13", ...extra,
  };
}

const ESPERANDO_TARDE = "Ainda esperando hoje: Paulo (prometi até 19h) · Ana (venceu ontem).";
const RESUMO_TARDE = "Em teste (retorno): eu teria mandado 6 recibos hoje (4 a clientes, 2 a números novos); você respondeu 2 antes.";
const ABERTURA_COM_ESPERANDO = "Fechamento de quinta, 15/10: nada ficou de hoje, fora quem espera resposta.";

Deno.test("textoDaTarde: 'Ainda esperando hoje' logo depois da abertura; o resumo antes da pergunta da sexta", () => {
  const t = textoDaTarde(dados({ fornecedores: ["SR Contabilidade"], retorno: { esperando: ESPERANDO_TARDE, resumo: RESUMO_TARDE } })).texto!;
  assertEquals(t.split("\n"), [
    ABERTURA_COM_ESPERANDO,
    ESPERANDO_TARDE,
    "",
    "Amanhã (sexta, 16/10): nada marcado.",
    "Fornecedores esperando há mais de 1 dia: SR Contabilidade.",
    "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 30 min. *escritório*",
    RESUMO_TARDE,
  ]);
  const sexta = textoDaTarde(dados({ hoje: "2026-10-16", amanha: { dia: "2026-10-17", itens: [] }, pergunta: true, retorno: { esperando: null, resumo: RESUMO_TARDE } })).texto!;
  assert(sexta.endsWith(`${RESUMO_TARDE}\n${PERGUNTA_DA_SEMANA}`), sexta);
});

Deno.test("textoDaTarde: 'Ainda esperando hoje' sozinha já é 'há algo'; o resumo sozinho, não", () => {
  assertEquals(textoDaTarde(dados()).texto, null);
  assertEquals(textoDaTarde(dados({ retorno: { esperando: null, resumo: RESUMO_TARDE } })).texto, null);
  const so = textoDaTarde(dados({ retorno: { esperando: ESPERANDO_TARDE, resumo: null } })).texto!;
  assertEquals(so.split("\n").slice(0, 2), [ABERTURA_COM_ESPERANDO, ESPERANDO_TARDE]);
});

Deno.test("textoDaTarde: sem o retorno (ou com as duas nulas) o texto é o de antes, byte a byte; nas revisões, o resumo não entra", () => {
  const varios = [
    dados({ fornecedores: ["SR Contabilidade"] }),
    dados({ hoje: "2026-10-16", amanha: { dia: "2026-10-17", itens: [] }, pergunta: true }),
    dados({ ficaram: [linha("B", "Marcelo B. (OS-00038): R$ 16.890,00, venceu 13/10 (2 dias); ainda não entrou")] }),
    cheio([]),
    cheio([PERGUNTAS], 2),
    dados({ turno: "revisao_semana", hoje: "2026-10-19" }),
    dados({ turno: "revisao_mes", hoje: "2026-11-03" }),
  ];
  for (const [i, d] of varios.entries()) {
    const antes = textoDaTarde(d);
    assertEquals(textoDaTarde({ ...d, retorno: null }), antes, String(i));
    assertEquals(textoDaTarde({ ...d, retorno: { esperando: null, resumo: null } }), antes, String(i));
  }
  for (const turno of ["revisao_semana", "revisao_mes"] as const) {
    const d = dados({ turno, hoje: "2026-10-19" });
    assertEquals(textoDaTarde({ ...d, retorno: { esperando: null, resumo: RESUMO_TARDE } }), textoDaTarde(d), turno);
  }
});

// (correção, problema 1) às segundas (revisão da semana) e no 1º dia útil do mês (revisão do mês) não há fechamento: é a
// revisão das 17:30 que cumpre o "hoje até as 19h" de quem escreveu entre 11:00 e 15:29
Deno.test("textoDaTarde nas revisões: 'Ainda esperando hoje' logo depois da abertura, e o resumo fica de fora", () => {
  const semana = textoDaTarde(dados({ turno: "revisao_semana", hoje: "2026-10-19", retorno: { esperando: ESPERANDO_TARDE, resumo: RESUMO_TARDE } })).texto!;
  assertEquals(semana.split("\n").slice(0, 2), ["Revisão da semana, segunda, 19/10. Nada parado.", ESPERANDO_TARDE]);
  assert(!semana.includes(RESUMO_TARDE), semana);
  const mes = textoDaTarde(dados({ turno: "revisao_mes", hoje: "2026-11-03", retorno: { esperando: ESPERANDO_TARDE, resumo: RESUMO_TARDE } })).texto!;
  assertEquals(mes.split("\n").slice(0, 2), ["Revisão do mês, terça, 03/11.", ESPERANDO_TARDE]);
  assert(!mes.includes(RESUMO_TARDE), mes);
});

// o fechamento de produção de qui 29/10 (3 que ficaram, "sem resposta", fornecedores e o escritório; ~900 caracteres), como em
// secretario-tarde-texto_test.ts (Correção 2 da 7a), com a linha das perguntas do gestor garantida
const FICARAM_REAL = [
  linha("A", "OS-00112 Nelson (Santo Inácio 7.8): 4 itens a comprar até seg 26/10", { faco: "te mando a lista do que falta", alternativa: "já comprei", comandoAlternativo: "feito" }),
  linha("B", "Marcelo Marco Bertoldi (OS-00038): R$ 16.890,00, venceu 13/10 (16 dias); ainda não entrou"),
  linha("C", "APOLO INDUSTRIA E COMERCIO DE…: R$ 5.237,99, venceu 16/10 (13 dias); ainda não entrou"),
];
const ESCRITORIO_REAL = { propostas: { saidas: 107, entradas: 10, transferencias: 1, outras: 0 }, alertas: 33, regras: 0, debitosSemLoja: 8, entradas: null };
type Linha2 = NonNullable<AgendaDoFechamento["linhas"]>[number];
const PERGUNTAS: Linha2 = {
  tipo: "pergunta", perda: 76, pergunta_id: "q-pergunta", acao_ids: [], modo: "ligado",
  texto: "Agenda: Sem resposta até qua 04/11 18:00: Flávio (OS-00104) 3,5 dias; Nelson (OS-00112) 4 dias; Vanderlei (OS-00069) " +
    "7,5 dias; MP (ORÇ-00095) 1 dia. Espero você (não marco sozinho): Giancarlo (OS-00130).",
  texto_curto: "Agenda: Sem resposta até qua 04/11 18:00, conto: Flávio (OS-00104) 3,5 dias; Nelson (OS-00112) 4 dias; Vanderlei " +
    "(OS-00069) 7,5 dias; MP (ORÇ-00095) 1 dia.",
};
function cheio(linhas: Linha2[], vagas?: number): DadosDaTarde {
  return dados({
    hoje: "2026-11-04", ficaram: FICARAM_REAL, fornecedores: ["Mateus Honório", "Benjamin"], escritorio: ESCRITORIO_REAL,
    semResposta: [{ phone: "5547900000301", nome: "MP MOTOR HOMES", desde: "10:29", acordei: null },
                  { phone: "5547900000302", nome: "Jorge Girardon", desde: "10:51", acordei: null }],
    amanha: { dia: "2026-11-05", itens: [], carteira: { semData: 6 },
              agenda: { modo: "ligado", cauda: null, semana: [], linhas, ...(vagas === undefined ? {} : { vagas_garantidas: vagas }) } },
  });
}
const AS_1730_DE_0411 = new Date("2026-11-04T20:30:00Z");

/** As linhas com letra do que ficou, inteiras (na forma longa ou na curta do enxuto). */
function letrasInteiras(texto: string): boolean {
  const linhas = texto.split("\n");
  return FICARAM_REAL.every((l) => linhas.includes(linhaQueFicou(l, 150)) || linhas.includes(linhaQueFicou(l, 90)));
}

Deno.test("textoDaTarde: o resumo é o primeiro a sair — só fica se o fechamento inteiro couber com ele", () => {
  const d = { ...cheio([]), retorno: { esperando: ESPERANDO_TARDE, resumo: RESUMO_TARDE } };
  const t = textoDaTarde(d);
  assert(!(t.texto ?? "").includes(RESUMO_TARDE), "o resumo saiu");
  assertEquals(t, textoDaTarde({ ...d, retorno: { esperando: ESPERANDO_TARDE, resumo: null } }));
  assertEquals((t.texto ?? "").split("\n")[1], ESPERANDO_TARDE);
  // num fechamento curto ele cabe e fica
  assertStringIncludes(textoDaTarde(dados({ fornecedores: ["X"], retorno: { esperando: null, resumo: RESUMO_TARDE } })).texto!, RESUMO_TARDE);
});

Deno.test("textoDaTarde com semOsExtras e as vagas garantidas da agenda (7a): 'Ainda esperando hoje' continua e o resumo sai", () => {
  const semRetorno = textoDaTarde(cheio([PERGUNTAS], 2));
  // a base: com a linha garantida, o fechamento cheio vai no enxuto (sem escritório, fornecedores e "sem resposta")
  assertEquals(semRetorno.agenda?.linhas?.map((l) => l.tipo), ["pergunta"]);
  assert(!(semRetorno.texto ?? "").includes("Escritório:"), semRetorno.texto ?? "");
  const t = textoDaTarde({ ...cheio([PERGUNTAS], 2), retorno: { esperando: ESPERANDO_TARDE, resumo: RESUMO_TARDE } });
  const texto = t.texto ?? "";
  assertEquals(texto.split("\n")[1], ESPERANDO_TARDE);
  assert(!texto.includes(RESUMO_TARDE), "o resumo saiu");
  assert(!texto.includes("Escritório:") && !texto.includes("Fornecedores esperando") && !texto.includes("Sem resposta desde hoje"), texto);
  // a linha garantida da agenda e as letras do Secretário continuam
  assertEquals(t.agenda?.linhas?.map((l) => l.tipo), ["pergunta"]);
  for (const l of ["*A.*", "*B.*", "*C.*"]) assertStringIncludes(texto, l);
  assert(texto.length <= LIMITE_DA_TARDE, `${texto.length}`);
});

// (correção, problema 10) antes, com a linha de quem espera, o fechamento sem linha da agenda (L = 0) ia direto ao corte duro
// de 1.000 caracteres: a linha do escritório saía cortada no meio e, com 14 ligados, a letra C perdia as opções
Deno.test("textoDaTarde, sombra: a linha '(em teste)' é extra — no fechamento cheio de 04/11 ela sai e o texto é o de antes", () => {
  const cinco = muitos(5, "2026-11-04T22:00:00Z", "2026-11-04T12:14:00Z").map((e) => ({ ...e, ouviu: false }));
  const r = linhasDoFechamento(fechamento("sombra", { esperando: cinco }), AS_1730_DE_0411);
  assertEquals(r.fixa, false);
  const t = textoDaTarde({ ...cheio([]), retorno: r });
  assertEquals(t, textoDaTarde(cheio([])));
  assertStringIncludes(t.texto!, "*escritório*");
  assert(!t.texto!.includes("Ainda esperando"));
  // num fechamento que cabe, ela fica
  const curto = textoDaTarde(dados({ fornecedores: ["X"], retorno: linhasDoFechamento(fechamento("sombra", { esperando: cinco.slice(0, 2) }), TARDE) })).texto!;
  assertStringIncludes(curto, "Ainda esperando hoje (em teste):");
});

Deno.test("textoDaTarde, ligado: com a linha que sustenta promessa, nunca o corte duro — o enxuto, e as letras A, B e C inteiras", () => {
  const quatorze = linhasDoFechamento(fechamento("ligado", { esperando: muitos(14, "2026-11-04T22:00:00Z", "2026-11-04T12:14:00Z") }), AS_1730_DE_0411);
  assertEquals(quatorze.fixa, true);
  const t = textoDaTarde({ ...cheio([]), retorno: quatorze });
  const texto = t.texto!;
  assertEquals(texto.split("\n")[1], quatorze.esperando);
  assert(letrasInteiras(texto), texto);
  assertEquals(t.letras.map((l) => l.letra), ["A", "B", "C"]);
  assert(!texto.endsWith("…"), texto);
  // o enxuto: sai o que é do Secretário e não perde hoje
  assert(!texto.includes("Escritório:") && !texto.includes("Fornecedores esperando"), texto);
  // com a linha garantida da agenda também (30 itens: a linha passa sozinha do limite da tarde)
  const trinta = linhasDoFechamento(fechamento("ligado", { esperando: muitos(30, "2026-11-04T22:00:00Z", "2026-11-04T12:14:00Z") }), AS_1730_DE_0411);
  assert(trinta.esperando!.length > LIMITE_DA_TARDE, `${trinta.esperando!.length}`);
  const t30 = textoDaTarde({ ...cheio([PERGUNTAS], 2), retorno: { ...trinta, resumo: RESUMO_TARDE } }).texto!;
  assertStringIncludes(t30, trinta.esperando!);
  assert(!t30.includes(RESUMO_TARDE));
  assert(letrasInteiras(t30), t30);
  assert(t30.length <= LIMITE_DO_BANCO, `${t30.length}`);
  // sem o retorno, o corte de sempre (1.000)
  assert(textoDaTarde(cheio([PERGUNTAS], 2)).texto!.length <= LIMITE_DA_TARDE);
});

// (correção, problemas 6 e 11) o CHECK de resumo_tarde.texto: 90 com prazo hoje não derrubam o fechamento
Deno.test("textoDaTarde com 90 com prazo hoje: o texto fica abaixo dos 4.000 do banco, com as letras inteiras", () => {
  const noventa = linhasDoFechamento(fechamento("ligado", { esperando: muitos(90, "2026-11-04T22:00:00Z", "2026-11-04T12:14:00Z") }), AS_1730_DE_0411);
  for (const d of [cheio([]), cheio([PERGUNTAS], 2)]) {
    const texto = textoDaTarde({ ...d, retorno: noventa }).texto!;
    assert(texto.length <= LIMITE_DO_BANCO, `${texto.length}`);
    assertStringIncludes(texto, noventa.esperando!);
    assert(letrasInteiras(texto), texto);
  }
});

// ─── secretario-tarde.ts: os três turnos ────────────────────────────────────────────────────────

const AS_1730 = new Date("2026-10-15T20:30:00Z"); // quinta 15/10, 17:30
const FECHAMENTO_SOMBRA = {
  modo: "sombra",
  esperando: [{ phone: "5547900009151", rotulo: "Paulo", desde: "2026-10-15T12:14:00Z", prometido_ate: "2026-10-15T22:00:00Z", venceu: false, com_prazo_hoje: true }],
  recebidos: 0, no_prazo: 0, adiados: 0, sem_palavra: 0, na_queda: 0,
  sombra: { teria_mandado: 1, por_papel: { cliente: 1 }, respondeu_antes: 0 }, alongadas: [],
};
// a segunda 19/10 (revisão da semana), com o retorno ligado: Paulo escreveu às 11:14 e ouviu "hoje até as 19h"
const SEGUNDA_LIGADO = {
  modo: "ligado",
  esperando: [{ phone: "5547900009152", rotulo: "Paulo", desde: "2026-10-19T14:14:00Z", prometido_ate: "2026-10-19T22:00:00Z", venceu: false, com_prazo_hoje: true, ouviu: true }],
  recebidos: 2, no_prazo: 1, adiados: 0, sem_palavra: 0, na_queda: 0,
  sombra: { teria_mandado: 0, por_papel: {}, respondeu_antes: 0 }, alongadas: [],
};

function lido(retorno?: RetornoDoFechamento | null): LidoDaTarde {
  return {
    coleta: { cobrancas: [], conversas: [], orcamentos: [], oss: [] }, historico: [], esperando: [], recebidas: null,
    amanha: { dia: "2026-10-16", itens: [] }, escritorio: null, panorama: null, mesQueFechou: null,
    ...(retorno === undefined ? {} : { retorno }),
  };
}

Deno.test("montarTardeDosDados: o retorno lido entra no fechamento e nas revisões (sem o resumo); sem ele, o texto de antes", () => {
  const r = fechamento("sombra", {
    esperando: [esp("Paulo", { desde: "2026-10-15T12:14:00Z", com_prazo_hoje: true })],
    sombra: { teria_mandado: 1, por_papel: { cliente: 1 }, respondeu_antes: 0 },
  });
  const p = { hoje: "2026-10-15", agora: AS_1730, turno: "fechamento" as const, itens: [], pergunta: false };
  const com = montarTardeDosDados({ ...p, lido: lido(r) }).texto!;
  assertEquals(com.split("\n").slice(0, 2), ["Fechamento de quinta, 15/10: nada ficou de hoje, fora quem espera resposta.", "Ainda esperando hoje (em teste): Paulo (desde 09:14)."]);
  assertStringIncludes(com, "Em teste (retorno): eu teria mandado 1 recibo hoje (1 a cliente).");
  assertEquals(montarTardeDosDados({ ...p, lido: lido(null) }).texto, montarTardeDosDados({ ...p, lido: lido() }).texto);
  // desligado sem ninguém que ouviu: o texto de antes
  assertEquals(montarTardeDosDados({ ...p, lido: lido(fechamento("desligado", { esperando: r.esperando })) }).texto, montarTardeDosDados({ ...p, lido: lido() }).texto);
  // a revisão da semana: a linha logo depois da abertura, e o resumo não
  const rev = { ...p, hoje: "2026-10-19", agora: new Date("2026-10-19T20:30:00Z"), turno: "revisao_semana" as const };
  const ligado = fechamento("ligado", { esperando: [esp("Paulo", { desde: "2026-10-19T14:14:00Z", prometido_ate: "2026-10-19T22:00:00Z", com_prazo_hoje: true, ouviu: true })], recebidos: 1 });
  const t = montarTardeDosDados({ ...rev, lido: lido(ligado) }).texto!;
  assertEquals(t.split("\n")[1], "Ainda esperando hoje: Paulo (prometi até 19h).");
  assert(!t.includes("Retorno hoje"), t);
  assertEquals(montarTardeDosDados({ ...rev, lido: lido(null) }).texto, montarTardeDosDados({ ...rev, lido: lido() }).texto);
});

// PostgREST de mentira (o mesmo molde de secretario-tarde_test.ts), com o registro das chamadas de rpc
type Linha = Record<string, unknown>;
const DONO = { id: "u-dono", phone: "5547999990000" };
function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown>) {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  const admin = {
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      let soContagem = false;
      const resultado = () => soContagem ? { data: null, error: null, count: linhas.length } : { data: linhas, error: null };
      const q: Record<string, unknown> = {
        select: (_c?: string, o?: { head?: boolean }) => ((soContagem = !!o?.head), q),
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        neq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] !== v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        is: (c: string, v: unknown) => ((linhas = linhas.filter((l) => (l[c] ?? null) === v)), q),
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && (l[c] ?? null) === v))), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) < v)), q),
        lte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) <= v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) >= v)), q),
        gt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) > v)), q),
        like: () => q,
        or: () => q,
        order: () => q,
        limit: () => q,
        insert: () => Promise.resolve({ data: null, error: null }),
        update: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado()).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: unknown) {
      chamadas.push({ nome, args });
      const r = rpcs[nome];
      if (r instanceof Error) return Promise.resolve({ data: null, error: { code: "PGRST202", message: r.message } });
      return Promise.resolve({ data: r ?? null, error: null });
    },
  };
  return { admin, chamadas };
}

function banco(dia: string) {
  return {
    app_settings: [{ key: "fechamento_formato", value: "sombra" }, { key: "quote_validity_days", value: "3" }],
    app_users: [{ id: DONO.id, phone_normalized: DONO.phone, role: "admin", active: true, ai_whatsapp_enabled: true }],
    resumo_tarde: [],
    resumo_manha: [{ id: "m-1", dia, phone_normalized: DONO.phone, modo: "sombra" }],
    resumo_itens: [],
    whatsapp_messages: [],
    whatsapp_perguntas: [],
    ai_operator_sessions: [],
  };
}

Deno.test("rodarTurnoDaTarde: o fechamento e a revisão de segunda leem retorno_resumo_do_dia ('fechamento', agora) e mostram 'Ainda esperando hoje'", async () => {
  const f = falsoAdmin(banco("2026-10-15"), { retorno_resumo_do_dia: FECHAMENTO_SOMBRA });
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "fechamento", dry: true });
  assertEquals(r.status, 200);
  const texto = String(r.corpo.texto);
  assertEquals(texto.split("\n").slice(0, 2), ["Fechamento de quinta, 15/10: nada ficou de hoje, fora quem espera resposta.", "Ainda esperando hoje (em teste): Paulo (desde 09:14)."]);
  assertStringIncludes(texto, "Em teste (retorno): eu teria mandado 1 recibo hoje (1 a cliente).");
  assertEquals(f.chamadas.filter((c) => c.nome === "retorno_resumo_do_dia").map((c) => c.args),
    [{ p_turno: "fechamento", p_agora: AS_1730.toISOString() }]);
  // a função ainda não publicada: o fechamento de antes (aqui, calado), sem erro e sem nada em app_error_logs
  const ausente = falsoAdmin(banco("2026-10-15"), { retorno_resumo_do_dia: new Error("Could not find the function") });
  const semFuncao = await rodarTurnoDaTarde(ausente.admin, { agora: AS_1730, pedido: "fechamento", dry: true });
  assertEquals([semFuncao.status, semFuncao.corpo.texto], [200, null]);
  assertEquals(ausente.chamadas.some((c) => c.nome === "log_app_error"), false);
  // a revisão da semana (seg 19/10) também lê, e mostra quem ouviu "hoje até as 19h"; o resumo é só do fechamento
  const agoraSeg = new Date("2026-10-19T20:30:00Z");
  const seg = falsoAdmin(banco("2026-10-19"), { retorno_resumo_do_dia: SEGUNDA_LIGADO });
  const rev = await rodarTurnoDaTarde(seg.admin, { agora: agoraSeg, pedido: "revisao_semana", dry: true });
  assertEquals(rev.corpo.turno, "revisao_semana");
  assertEquals(seg.chamadas.filter((c) => c.nome === "retorno_resumo_do_dia").map((c) => c.args),
    [{ p_turno: "fechamento", p_agora: agoraSeg.toISOString() }]);
  const textoRev = String(rev.corpo.texto);
  assertEquals(textoRev.split("\n")[1], "Ainda esperando hoje: Paulo (prometi até 19h).", textoRev);
  assert(!textoRev.includes("Retorno hoje"), textoRev);
});

// ─── O que a F2 acrescenta (P12.4) ───────────────────────────────────────────────────────────────────────────────────

const MANDEI: ExtraDoFechamento = {
  palavra: true, mandei_mais: 1, promovidos: [], rebaixados: [], suspensos: [], semana: null,
  mandei: [
    { letra: "Z", rotulo: "Rodrigo", tipo_curto: "aguardando peça", saida_id: "s1" },
    { letra: "Y", rotulo: "Paulo", tipo_curto: "pronto", saida_id: "s2" },
  ],
};

Deno.test("F2: a linha do Mandei sozinho, com a letra da última nomeada", () => {
  assertEquals(linhaDoMandei(MANDEI), "Mandei sozinho hoje: Z) 'aguardando peça' ao Rodrigo · Y) 'pronto' ao Paulo · e mais 1 · *errado Y*");
  assertEquals(linhaDoMandei({ ...MANDEI, mandei: [] }), null);
  assertEquals(linhaDoMandei(null), null);
});

Deno.test("F2: os contatos sem recibo", () => {
  assertEquals(linhaDeContatos({ palavra: true, contatos: { vendedores: 3, conhecidos: 2 } }), "Sem recibo ontem: 3 vendedores · 2 contatos conhecidos.");
  assertEquals(linhaDeContatos({ palavra: true, contatos: { vendedores: 1, conhecidos: 0 } }), "Sem recibo ontem: 1 vendedor.");
  assertEquals(linhaDeContatos({ palavra: true, contatos: { vendedores: 0, conhecidos: 0 } }), null);
});

Deno.test("F2: uma extra só, na ordem semana, rebaixado, promovido, fadiga", () => {
  const vazio = { ...MANDEI, mandei: [], mandei_mais: 0 };
  assertEquals(linhasDoExtra(vazio), []);
  assertEquals(linhasDoExtra({ ...vazio, suspensos: ["pronto"] }), ["Aprovações rápidas demais: 'pronto' não promove por 7 dias."]);
  assertEquals(linhasDoExtra({ ...vazio, suspensos: ["pronto"], promovidos: ["aguardando peça"] }),
    ["A partir de amanhã, 'aguardando peça' sai sozinho. *errado <letra>* volta ao cartão."]);
  assertEquals(linhasDoExtra({ ...vazio, promovidos: ["x"], rebaixados: [{ tipo_curto: "pronto", motivo: "errado" }] }),
    ["'pronto' voltou ao cartão: você marcou errado."]);
  const semana = { recibos: 31, recibo_12min: 30, hora_cumprida: 21, hora_casos: 25, vencida_sem_aviso: 0, insistencia: 3, toques: 11, dias_uteis: 5 };
  assertEquals(linhasDoExtra({ ...vazio, rebaixados: [{ tipo_curto: "pronto", motivo: "errado" }], semana }),
    ["Retorno da semana: recibo em até 12 min 97% (de 31) · hora cumprida 84% · 0 vencida sem aviso · insistência 10% · você deu 11 toques novos (2,2 por dia)"]);
  assertEquals(linhasDoExtra({ ...vazio, semana: { ...semana, recibos: 16, recibo_12min: 15, hora_casos: 10, hora_cumprida: 9 } })[0].startsWith("Retorno da semana: recibo em até 12 min 15 de 16 · hora cumprida 9 de 10"), true);
});

Deno.test("F2: a palavra *retorno* só com a chave ligada; sem extra, igual à F1 byte a byte", () => {
  const r: RetornoDaManha = { modo: "ligado", esperando_mais: 0, conferir: [], conferir_mais: 0,
    esperando: [{ phone: "5547900009101", rotulo: "Lenine", desde: "2026-11-24T12:00:00Z", prometido_ate: null, venceu: false, com_prazo_hoje: true }] };
  const agora = new Date("2026-11-24T13:00:00Z");
  const sem = linhasDaManha(r, new Set(), agora);
  assertEquals(linhasDaManha(r, new Set(), agora, null), sem);
  const com = linhasDaManha(r, new Set(), agora, { palavra: true, contatos: { vendedores: 1, conhecidos: 0 } });
  assertEquals(com.esperando, `${sem.esperando} · *retorno*`);
  assertEquals(com.conferir, "Sem recibo ontem: 1 vendedor.");
  assertEquals(linhasDaManha(r, new Set(), agora, { palavra: false, contatos: { vendedores: 0, conhecidos: 0 } }).esperando, sem.esperando);
});

Deno.test("F2: lerExtra falha fechado e nunca lança", async () => {
  const ausente = { rpc: () => Promise.resolve({ data: null, error: { code: "PGRST202" } }) };
  assertEquals(await lerExtra(ausente, "fechamento", new Date()), null);
  assertEquals(await lerExtra({ rpc: () => Promise.reject(new Error("x")) }, "manha", new Date()), null);
  const certo = { rpc: () => Promise.resolve({ data: { palavra: true, contatos: { vendedores: 2 } }, error: null }) };
  assertEquals(await lerExtra(certo, "manha", new Date()), { palavra: true, contatos: { vendedores: 2, conhecidos: 0 } });
});
