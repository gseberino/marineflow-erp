// (Agenda de Produção, Fase 7d, P5 — migration 20261107100400, R6.7c-3) O que o Secretário faz com a pergunta combinar que perde em até 2 dias úteis: a 75, ela ganha a vaga
// garantida e aparece com a carteira cheia. A 30, ela caía atrás de tudo no sort por perda: as vagas são REGRAS.maxManha − as que ficaram + as garantidas. O TS do Secretário não
// muda; este teste fixa o que ele faz com o número novo (a perda e o vagas_garantidas de verdade saem do banco: C8a e C8b de agenda_fase7d_combinar.sql).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type AgendaDoFechamento, type DadosDaTarde, LIMITE_DA_TARDE, linhasDaAgendaQueCabem, textoDaTarde } from "./secretario-tarde-texto.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";

type Linha = NonNullable<AgendaDoFechamento["linhas"]>[number];
const l = (tipo: Linha["tipo"], texto: string, perda: number, extra: Partial<Linha> = {}): Linha => ({
  tipo, texto, perda, pergunta_id: null, acao_ids: [], modo: "ligado", ...extra,
});
function ficou(letra: string, texto: string): LinhaComLetra {
  return { letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto",
           alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13" } as LinhaComLetra;
}
const COMBINAR = "Agenda: A vaga de serviço na Marina Itajaí para o barco de Nelson (ter 20/07) já está combinada? O prazo era sex 16/07. 1) Já combinei; 2) Ainda não.";
const FICARAM = [
  ficou("A", "OS-00112 Nelson (Santo Inácio 7.8): 4 itens a comprar até seg 26/10"),
  ficou("B", "Marcelo Marco Bertoldi (OS-00038): R$ 16.890,00, venceu 13/10 (16 dias); ainda não entrou"),
  ficou("C", "APOLO INDUSTRIA E COMERCIO DE…: R$ 5.237,99, venceu 16/10 (13 dias); ainda não entrou"),
];
const SEMANA = l("semana", "Agenda: semana publicada: Lenine seg e ter; Nelson qua.", 60);
const DIA = l("dia", "Hoje a agenda tinha Lenine com o Alex. Foi isso? Responda *dia feito* ou conte o que mudou.", 70);
const MUDOU = l("mudancas", "Agenda, mudei sozinho. Nelson (OS-00112): de ter 10/11 para qua 11/11.", 40);
const combinar = (perda: number) => l("pergunta", COMBINAR, perda, { pergunta_id: "q-comb" });

function dados(linhas: Linha[], vagas: number): DadosDaTarde {
  return {
    hoje: "2027-07-19", turno: "fechamento", ficaram: FICARAM, fornecedores: [], parados: [], panorama: null, antigas: null,
    mesQueFechou: null, faturamento: null, pergunta: false,
    escritorio: { propostas: { saidas: 107, entradas: 10, transferencias: 1, outras: 0 }, alertas: 33, regras: 0, debitosSemLoja: 8, entradas: null },
    amanha: { dia: "2027-07-20", itens: [], carteira: { semData: 6 }, agenda: { modo: "ligado", cauda: null, semana: [], linhas, vagas_garantidas: vagas } },
  } as unknown as DadosDaTarde;
}

Deno.test("7d P5, R6.7c-3: com a carteira cheia (3 que ficaram), a combinar a 30 não aparece: é o defeito", () => {
  const linhas = [DIA, SEMANA, MUDOU, combinar(30)];
  assertEquals(linhasDaAgendaQueCabem(3, { modo: "ligado", cauda: null, semana: [], linhas } as unknown as AgendaDoFechamento), []);
  // nem com vaga: ela é a última pela perda
  const comVaga = linhasDaAgendaQueCabem(2, { modo: "ligado", cauda: null, semana: [], linhas } as unknown as AgendaDoFechamento);
  assertEquals(comVaga.map((x) => x.tipo), ["dia"]);
  const t = textoDaTarde(dados(linhas, 0));
  assert(!(t.texto ?? "").includes("já está combinada"), "antes, a pergunta não chegava ao dono");
});

Deno.test("7d P5, R6.7c-3: a 75, com a vaga garantida que os 75 dão, a combinar aparece com a carteira cheia, na frente do que não perde", () => {
  const linhas = [DIA, SEMANA, MUDOU, combinar(75)];
  assertEquals(linhasDaAgendaQueCabem(3, { modo: "ligado", cauda: null, semana: [], linhas, vagas_garantidas: 1 } as unknown as AgendaDoFechamento)
    .map((x) => `${x.tipo} ${x.perda}`), ["pergunta 75"]);
  const t = textoDaTarde(dados(linhas, 1));
  assert((t.texto?.length ?? 0) <= LIMITE_DA_TARDE, `passou de ${LIMITE_DA_TARDE}: ${t.texto?.length}`);
  assert((t.texto ?? "").includes("A vaga de serviço na Marina Itajaí para o barco de Nelson"), `a pergunta tem de chegar: ${t.texto}`);
  assert((t.agenda?.linhas ?? []).some((x) => x.pergunta_id === "q-comb"), "a linha mostrada conta como vista");
});

Deno.test("7d P5, R6.7c-3: longe do dia, a 30, ela segue atrás e não tira o lugar de ninguém", () => {
  const linhas = [DIA, combinar(30)];
  assertEquals(linhasDaAgendaQueCabem(2, { modo: "ligado", cauda: null, semana: [], linhas } as unknown as AgendaDoFechamento).map((x) => x.tipo), ["dia"]);
});
