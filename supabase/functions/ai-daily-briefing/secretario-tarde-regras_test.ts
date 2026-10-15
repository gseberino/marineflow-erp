// O que a tarde mostra (secretário, Passo 3): com a manhã de 15/10 do fixture (o dia real reconstruído) e a
// coleta das 17:30 com o que mudou durante o dia. Regras puras: sem banco.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { candidatosDoDia, type Candidato, type ColetaDoSecretario } from "./secretario-candidatos.ts";
import type { PassagemDoHistorico } from "./secretario-selecao.ts";
import { montarDosDados } from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import { cobrancasAntigas, ficaramDeHoje, type ItemDaManha, manhaSemResposta, paradosDaSemana } from "./secretario-tarde-regras.ts";

const ESCRITORIO = { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null };
const TARDE_1510 = new Date("2026-10-15T20:30:00Z"); // 17:30 de Brasília

/** A manhã gravada (o que resumo_itens teria), sem ação do dono. */
function manhaGravada(coleta: ColetaDoSecretario = coleta1510(), hoje = HOJE_1510, agora = AGORA_1510, historico: PassagemDoHistorico[] = []): ItemDaManha[] {
  const m = montarDosDados({ hoje, agora, coleta, historico, naRua: { total: 0, n: 0 }, deHoje: deHoje1510(), escritorio: ESCRITORIO });
  return m.itens.map((i) => ({
    ...i, secao: i.secao as ItemDaManha["secao"], posicao: i.posicao, acao: null, adiado_ate: null,
    detalhe: i.detalhe, valor: i.valor,
  }));
}

function mapa(coleta: ColetaDoSecretario, agora: Date, hoje: string): Map<string, Candidato> {
  return new Map(candidatosDoDia(coleta, agora, hoje).map((c) => [c.referencia, c]));
}

Deno.test("ficaramDeHoje: os 3 de manhã continuam às 17:30 se nada mudou, na ordem e com a letra da manhã", () => {
  const itens = manhaGravada();
  const de = itens.filter((i) => i.principal && i.posicao === "manha").map((i) => [i.letra, i.nome]);
  const f = ficaramDeHoje(itens, mapa(coleta1510(), TARDE_1510, HOJE_1510));
  assertEquals(f.map((l) => [l.letra, l.parte]), de.map(([l]) => [l, "ficou"]));
  // a cobrança diz que não entrou; o cliente, há quanto tempo (de agora, 17:30)
  const c = f.find((l) => l.tipo === "cobranca_grande")!;
  assert(c.texto.endsWith("; ainda não entrou"), c.texto);
  assertEquals(c.faco, "te mostro o lembrete pronto");
});

Deno.test("ficaramDeHoje: pago, respondido, ação do dono e 'abriu' — só o que ainda pede o dono volta", () => {
  const itens = manhaGravada();
  const letraDe = (pred: (i: ItemDaManha) => boolean) => itens.find((i) => i.principal && i.posicao === "manha" && pred(i))!.letra;
  const marcelo = letraDe((i) => i.tipo === "cobranca_grande");
  const jorge = letraDe((i) => i.nome.startsWith("Jorge"));
  const cesar = letraDe((i) => i.nome.startsWith("Cesar"));
  const coleta = coleta1510();
  coleta.cobrancas = coleta.cobrancas.filter((c) => c.id !== "r-marcelo"); // pagou de tarde
  // o dono respondeu ao Jorge: sai da lista de quem espera
  coleta.conversas = coleta.conversas.filter((w) => !w.contato.startsWith("Jorge"));
  // "A feito" no Cesar
  const comAcao = itens.map((i) => i.letra === cesar ? { ...i, acao: "feito" } : i);
  assertEquals(ficaramDeHoje(comAcao, mapa(coleta, TARDE_1510, HOJE_1510)), []);
  // só abriu o cartão (acao continua nula): ainda volta
  const f = ficaramDeHoje(itens, mapa(coleta, TARDE_1510, HOJE_1510));
  assertEquals(f.map((l) => l.letra), [cesar]);
  assert(![marcelo, jorge].includes(f[0].letra));
});

Deno.test("ficaramDeHoje: o pacote volta só com os orçamentos que continuam sem envio", () => {
  // uma manhã em que o pacote subiu (sem o Cesar, sem o Jorge e sem a cobrança grande)
  const coleta = coleta1510();
  coleta.conversas = coleta.conversas.filter((w) => !["Cesar", "Jorge Girardon"].includes(w.contato));
  const itens = manhaGravada(coleta);
  const pac = itens.filter((i) => i.tipo === "orcamento_nao_enviado");
  assertEquals(pac.length, 2);
  assert(pac.every((i) => i.posicao === "manha" && i.letra === pac[0].letra));
  const tarde = coleta1510();
  tarde.conversas = coleta.conversas;
  // o ORÇ-00118 saiu às 15h
  tarde.orcamentos = tarde.orcamentos.map((q) => q.numero === "ORÇ-00118" ? { ...q, quote_status: "sent", mexido_em: "2026-10-15T18:00:00Z" } : q);
  const f = ficaramDeHoje(itens, mapa(tarde, TARDE_1510, HOJE_1510)).find((l) => l.letra === pac[0].letra)!;
  assert(f.texto.startsWith("*ORÇ-00117*") || f.texto.startsWith("ORÇ-00117"), f.texto);
  // a letra abre o pacote da manhã (a lista), mesmo com um só ainda não enviado
  assertEquals(f.faco, "te mostro a lista");
  // os dois saíram: a letra não volta
  tarde.orcamentos = tarde.orcamentos.map((q) => q.numero === "ORÇ-00117" ? { ...q, quote_status: "sent", mexido_em: "2026-10-15T18:00:00Z" } : q);
  assertEquals(ficaramDeHoje(itens, mapa(tarde, TARDE_1510, HOJE_1510)).some((l) => l.letra === pac[0].letra), false);
});

// ─── Revisão da semana (segunda, 19/10) ────────────────────────────────────────────────────────

const SEGUNDA = "2026-10-19";
const MANHA_SEGUNDA = new Date("2026-10-19T10:30:00Z");
const TARDE_SEGUNDA = new Date("2026-10-19T20:30:00Z");

function historicoDe(itens: ItemDaManha[], dia: string, criado: string): PassagemDoHistorico[] {
  return itens.map((i) => ({
    referencia: i.referencia, dia, posicao: i.posicao, fato: i.fato,
    acao: i.posicao === "manha" ? "ignorado" : null, acao_em: i.posicao === "manha" ? criado : null,
    adiado_ate: null, voltou_em: null, criado_em: criado,
  }));
}

Deno.test("paradosDaSemana: apareceu de manhã sem resposta ou fato com 7+ dias; contato, fornecedor e cobrança de 30+ dias fora", () => {
  const h15 = historicoDe(manhaGravada(), HOJE_1510, "2026-10-15T10:30:00Z");
  const itens = manhaGravada(coleta1510(), SEGUNDA, MANHA_SEGUNDA, h15);
  const p = paradosDaSemana(itens, mapa(coleta1510(), TARDE_SEGUNDA, SEGUNDA), h15, SEGUNDA);
  assert(p.length > 0);
  const tipos = p.map((l) => l.tipo);
  assert(!tipos.includes("cobranca_antiga") && !tipos.includes("fornecedor"), tipos.join());
  assert(!tipos.some((t) => t.startsWith("contato")), tipos.join());
  // a cobrança grande apareceu de manhã em 15/10 e ficou sem resposta
  assert(p.some((l) => l.tipo === "cobranca_grande"), "Marcelo parado");
  // a OS-00069 está parada desde 03/10
  assert(p.some((l) => l.texto.startsWith("OS-00069")), p.map((l) => l.texto).join(" | "));
  // ordem: maior valor primeiro
  for (let i = 1; i < p.length; i++) assert(p[i - 1].valor >= p[i].valor);
  // a letra é a de HOJE (a da manhã de segunda)
  for (const l of p) assert(itens.some((i) => i.principal && i.letra === l.letra && i.referencia === l.referencia));
});

Deno.test("paradosDaSemana: adiado, tirado e 'não' do dono ficam de fora", () => {
  const h15 = historicoDe(manhaGravada(), HOJE_1510, "2026-10-15T10:30:00Z");
  const marcelo = h15.find((h) => h.referencia === "recv:r-marcelo")!;
  const itens = manhaGravada(coleta1510(), SEGUNDA, MANHA_SEGUNDA, h15);
  const cand = mapa(coleta1510(), TARDE_SEGUNDA, SEGUNDA);
  for (const acao of ["tirado", "nao"]) {
    const h = h15.map((x) => x === marcelo ? { ...x, acao, acao_em: "2026-10-15T12:00:00Z" } : x);
    assertEquals(paradosDaSemana(itens, cand, h, SEGUNDA).some((l) => l.referencia === "recv:r-marcelo"), false, acao);
  }
  const adiado = h15.map((x) => x === marcelo ? { ...x, acao: "adiado", acao_em: "2026-10-15T12:00:00Z", adiado_ate: "2026-10-30" } : x);
  assertEquals(paradosDaSemana(itens, cand, adiado, SEGUNDA).some((l) => l.referencia === "recv:r-marcelo"), false);
});

Deno.test("manhaSemResposta: o 'volta' zera; a ação depois da manhã também", () => {
  const base: PassagemDoHistorico = {
    referencia: "os:1", dia: "2026-10-15", posicao: "manha", fato: "f", acao: "ignorado", acao_em: "2026-10-16T10:30:00Z",
    adiado_ate: null, voltou_em: null, criado_em: "2026-10-15T10:30:00Z",
  };
  assertEquals(manhaSemResposta("os:1", [base], SEGUNDA), "2026-10-15");
  assertEquals(manhaSemResposta("os:1", [{ ...base, posicao: "lista", acao: null }], SEGUNDA), null);
  assertEquals(manhaSemResposta("os:1", [base, { ...base, dia: "2026-10-16", posicao: "lista", acao: "feito", acao_em: "2026-10-16T12:00:00Z", criado_em: "2026-10-16T10:30:00Z" }], SEGUNDA), null);
  assertEquals(manhaSemResposta("os:1", [{ ...base, voltou_em: "2026-10-17T12:00:00Z" }], SEGUNDA), null);
});

// ─── Revisão do mês ────────────────────────────────────────────────────────────────────────────

Deno.test("cobrancasAntigas: agrupa pela letra de hoje (o mesmo cliente divide a letra) e tira o que o dono decidiu", () => {
  const itens = manhaGravada();
  const cand = mapa(coleta1510(), TARDE_1510, HOJE_1510);
  const a = cobrancasAntigas(itens, coleta1510().cobrancas, cand, [], HOJE_1510);
  assertEquals([a.n, a.total, a.fora.n], [3, 2426, 0]);
  assertEquals(a.linhas.length, 2);
  const mp = a.linhas[0];
  assert(mp.texto.startsWith("MP MOTOR HOMES: R$ 1.670,00 em 2 cobranças; a mais antiga venceu 22/07 (85 dias)"), mp.texto);
  const letraMp = itens.find((i) => i.referencia === "recv:r-mp45")!.letra;
  assertEquals(mp.letra, letraMp);
  assert(a.linhas[1].texto.startsWith("Lírio (OS-00047): R$ 756,00"), a.linhas[1].texto);
  // tirado com o mesmo fato: some
  const lirio = itens.find((i) => i.referencia === "recv:r-lirio")!;
  const hist: PassagemDoHistorico[] = [{
    referencia: lirio.referencia, dia: "2026-10-14", posicao: "lista", fato: lirio.fato, acao: "tirado", acao_em: "2026-10-14T12:00:00Z",
    adiado_ate: null, voltou_em: null, criado_em: "2026-10-14T10:30:00Z",
  }];
  const b = cobrancasAntigas(itens, coleta1510().cobrancas, cand, hist, HOJE_1510);
  assertEquals([b.n, b.linhas.length], [2, 1]);
  // a letra respondida hoje (ex.: "G 15 dias" de manhã) também
  const comAcao = itens.map((i) => i.letra === letraMp ? { ...i, acao: "adiado", adiado_ate: "2026-10-30" } : i);
  assertEquals(cobrancasAntigas(comAcao, coleta1510().cobrancas, cand, [], HOJE_1510).linhas.map((l) => l.letra), [lirio.letra]);
});

Deno.test("cobrancasAntigas: a cobrança sem letra hoje é só contada", () => {
  const itens = manhaGravada().filter((i) => i.referencia !== "recv:r-lirio");
  const a = cobrancasAntigas(itens, coleta1510().cobrancas, mapa(coleta1510(), TARDE_1510, HOJE_1510), [], HOJE_1510);
  assertEquals([a.n, a.linhas.length, a.fora.n, a.fora.total], [3, 1, 1, 756]);
});
