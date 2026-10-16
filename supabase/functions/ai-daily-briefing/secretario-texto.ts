// O texto da manhã nova (secretário, Passo 2, 15/10/2026) — puro, sem banco e sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md §5.
//
//   Bom dia! Quinta, 15/10. Hoje 3 coisas pedem você.
//   Na rua: R$ 21.026,00 vencidos (5).
//
//   *A.* <quem (barco, OS)>: <o que é e por que hoje>. <recomendação> *A* = <faço> · *A espera* = <alternativa>
//   …
//
//   Hoje: <agenda> <promessa> <vence hoje/amanhã> <falha da noite>
//   Logo abaixo ficaram <1–2 que quase entraram>, mais N assuntos. *lista*
//
// Domingo e feriado: uma linha. Meta: até ~1.000 caracteres — acima disso, primeiro o "Hoje" encurta
// (sem o texto da promessa e da agenda), depois saem os nomes do "logo abaixo" (nunca some um item da manhã).

import { brl, ddmm, nomeDoDia, umaLinha } from "../_shared/secretario/base.ts";
import type { TipoDoDia } from "../_shared/secretario/feriados.ts";
import { type GrupoDoDia, type Selecao, textosDoPacote } from "./secretario-selecao.ts";
import { blocoDaFolga, blocoDaManha, type PlanoDoGuardado } from "../_shared/uma-voz/guardado.ts";

export const META_DE_CARACTERES = 1000;

export interface DadosDeHoje {
  /** compromissos com hora (ou do dia) — agenda de Brasília */
  agenda: Array<{ hora: string | null; titulo: string }>;
  /** promessas do dono que vencem hoje */
  promessas: Array<{ contato: string; promessa: string | null }>;
  /** a receber e a pagar que vencem hoje ou amanhã */
  vencimentos: Array<{ lado: "receber" | "pagar"; quando: "hoje" | "amanha"; valor: number; nome: string }>;
  /** envios do sistema que falharam desde 20:00 de ontem */
  falhasDeEnvio: number;
  /** erros do servidor vistos desde 20:00 de ontem e ainda abertos */
  errosDaNoite: number;
}

export interface NaRua {
  total: number;
  n: number;
}

function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

/** A linha de um item da manhã: "*A.* … *A* = … · *A espera* = …". */
export function linhaDoItem(g: GrupoDoDia): string {
  const [p, ...resto] = g.membros;
  const c = p.c;
  const l = g.letra ?? "?";
  if (g.pacote) {
    // 2+ orçamentos montados e não enviados: um item só; a letra sozinha lista todos (com o atalho do PDF)
    const t = textosDoPacote(g.membros);
    return `*${l}.* ${comNovidade(t.titulo, g.membros.some((m) => m.estado.fatoNovo))} Recomendo revisar e enviar, começando pelo maior.` +
      ` *${l}* = te mostro os ${g.membros.length} · *${l} espera* = até segunda`;
  }
  // a cobrança grande que veio junto aparece primeiro no "Também" (ela fica todo dia)
  const outros = [...resto.filter((m) => m.c.todoDia), ...resto.filter((m) => !m.c.todoDia)];
  const tambem = outros.length ? ` Também: ${outros[0].c.rotulo}${outros.length > 1 ? ` e mais ${outros.length - 1}` : ""}.` : "";
  const resposta = c.faco
    ? ` *${l}* = ${c.faco}${c.alternativa ? ` · *${l} ${c.comandoAlternativo}* = ${c.alternativa}` : ""}`
    : "";
  return `*${l}.* ${comNovidade(c.titulo, p.estado.fatoNovo)}${tambem}${c.recomendacao ? ` ${c.recomendacao}` : ""}${resposta}`;
}

/** "… e não entrou (novidade desde a última vez)." — antes do ponto final, não depois. */
function comNovidade(titulo: string, novo: boolean): string {
  return novo ? titulo.replace(/\.?$/, " (novidade desde a última vez).") : titulo;
}

/** O nome curto do grupo no "logo abaixo ficaram…". */
export function rotuloDoGrupo(g: GrupoDoDia): string {
  return g.pacote ? textosDoPacote(g.membros).rotulo : g.membros[0].c.rotulo;
}

/** "Hoje: …" — não passa pelo corte de itens. `curta` = sem a agenda detalhada nem a promessa por extenso. */
export function linhaDeHoje(d: DadosDeHoje, curta = false): string {
  const partes: string[] = [];
  if (!d.agenda.length) partes.push("nada na agenda.");
  else if (curta) partes.push(`${plural(d.agenda.length, "compromisso", "compromissos")} na agenda.`);
  else {
    const itens = d.agenda.slice(0, 3).map((a) => `${a.hora ? `${a.hora} ` : ""}${umaLinha(a.titulo, 40)}`);
    partes.push(`${itens.join("; ")}${d.agenda.length > 3 ? ` (e mais ${d.agenda.length - 3})` : ""}.`);
  }
  if (d.promessas.length) {
    const ps = d.promessas.slice(0, 2).map((p) =>
      curta || !p.promessa ? umaLinha(p.contato, 30) : `${umaLinha(p.contato, 30)} (${umaLinha(p.promessa, 40)})`
    );
    partes.push(`Promessa sua: ${ps.join("; ")}${d.promessas.length > 2 ? ` e mais ${d.promessas.length - 2}` : ""}.`);
  }
  for (const quando of ["hoje", "amanha"] as const) {
    const vs = d.vencimentos.filter((v) => v.quando === quando).sort((a, b) => b.valor - a.valor);
    if (!vs.length) continue;
    const itens = vs.slice(0, 2).map((v) => `${brl(v.valor)} a ${v.lado} (${umaLinha(v.nome, curta ? 16 : 24)})`);
    partes.push(`${quando === "hoje" ? "Vence hoje" : "Amanhã vence"}: ${itens.join("; ")}${vs.length > 2 ? ` e mais ${vs.length - 2}` : ""}.`);
  }
  const noite: string[] = [];
  if (d.falhasDeEnvio > 0) noite.push(`${plural(d.falhasDeEnvio, "mensagem do sistema não saiu", "mensagens do sistema não saíram")}`);
  if (d.errosDaNoite > 0) noite.push(`${plural(d.errosDaNoite, "erro registrado", "erros registrados")}`);
  if (noite.length) partes.push(`Esta noite: ${noite.join(" e ")}.`);
  return `Hoje: ${partes.join(" ")}`;
}

/**
 * A cobrança grande (R$ 5 mil+) tem lugar garantido na manhã (secretario-selecao.ts). Só quando há MAIS
 * de 3 delas no mesmo dia alguma fica de fora: a linha "Na rua" nomeia a maior, com a letra. Adiada,
 * "não" ou tirada não conta (o dono já decidiu).
 */
function cobrancasGrandesDeFora(sel: Selecao): GrupoDoDia[] {
  const fora = sel.lista.filter((g) => g.quaseEntrou && g.membros.some((m) => m.c.tipo === "cobranca_grande" && m.estado.lugar === "manha"));
  const valor = (g: GrupoDoDia) => Math.max(...g.membros.filter((m) => m.c.tipo === "cobranca_grande").map((m) => m.c.valor));
  return fora.sort((a, b) => valor(b) - valor(a));
}

export function cobrancaGrandeDeFora(sel: Selecao): GrupoDoDia | null {
  return cobrancasGrandesDeFora(sel)[0] ?? null;
}

function linhaNaRua(naRua: NaRua, sel: Selecao): string | null {
  if (naRua.n <= 0) return null;
  const fora = cobrancasGrandesDeFora(sel);
  const g = fora[0];
  const m = g?.membros.find((x) => x.c.tipo === "cobranca_grande");
  const nomeada = g && m ? `${m.c.nome} (${brl(m.c.valor)}${g.letra ? `, *${g.letra}*` : ""})` : "";
  const extra = !nomeada ? ""
    : fora.length === 1 ? `; mais uma grande: ${nomeada}`
    : `; mais ${fora.length} grandes, a maior com ${nomeada}`;
  return `Na rua: ${brl(naRua.total)} vencidos (${naRua.n})${extra}.`;
}

/** "Logo abaixo ficaram X e Y, mais N assuntos. *lista*" (null quando nada ficou guardado). */
export function linhaDeLogoAbaixo(sel: Selecao, comNomes = true): string | null {
  const guardados = sel.lista.length;
  if (!guardados) return null;
  const jaNaRua = cobrancaGrandeDeFora(sel);
  const nomes = comNomes ? sel.logoAbaixo.filter((g) => g !== jaNaRua).slice(0, 2).map(rotuloDoGrupo) : [];
  const resto = guardados - nomes.length;
  if (!nomes.length) return `Guardei ${plural(guardados, "assunto", "assuntos")}. *lista*`;
  const quem = nomes.length === 1 ? `Logo abaixo ficou ${nomes[0]}` : `Logo abaixo ficaram ${nomes[0]} e ${nomes[1]}`;
  return `${quem}${resto > 0 ? `, mais ${plural(resto, "assunto", "assuntos")}` : ""}. *lista*`;
}

function abertura(hoje: string, n: number): string {
  const dia = `${nomeDoDia(hoje)}, ${ddmm(hoje)}`;
  if (!n) return `Bom dia! ${dia}. Nada precisa de você hoje.`;
  return `Bom dia! ${dia}. Hoje ${n === 1 ? "1 coisa pede" : `${n} coisas pedem`} você.`;
}

/** Domingo e feriado: uma linha (a lista do dia continua a uma palavra de distância). */
export function linhaDeFolga(tipo: TipoDoDia, feriado: string | null): string {
  const dia = tipo === "domingo" ? "Domingo" : `Feriado${feriado ? ` (${feriado})` : ""}`;
  return `Bom dia! ${dia}: nada precisa de você hoje. *lista* se quiser ver.`;
}

export function textoDaManha(p: {
  hoje: string;
  tipoDoDia: TipoDoDia;
  feriado: string | null;
  selecao: Selecao;
  naRua: NaRua;
  deHoje: DadosDeHoje;
  /**
   * (16/10/2026) O que o portão guardou para a manhã (uma voz só). Só vem quando o texto novo NÃO é enviado (sombra):
   * com a voz única em sombra as fontes ainda avisam o dono por conta própria. Ausente/vazio = o texto de antes.
   */
  guardado?: PlanoDoGuardado | null;
}): string {
  if (p.tipoDoDia !== "util") return linhaDeFolgaComGuardado(p.tipoDoDia, p.feriado, p.guardado);
  const cabeca = [abertura(p.hoje, p.selecao.manha.length)];
  const naRua = linhaNaRua(p.naRua, p.selecao);
  if (naRua) cabeca.push(naRua);
  const itens = p.selecao.manha.map(linhaDoItem);
  const montar = (hojeCurta: boolean, comNomes: boolean, guardadoCurto = false) => {
    const fim = [linhaDeHoje(p.deHoje, hojeCurta), linhaDeLogoAbaixo(p.selecao, comNomes)].filter((l): l is string => !!l);
    // o guardado entra logo depois da abertura (e do "Na rua"): é o que o portão segurou para não interromper
    const guardado = p.guardado ? blocoDaManha(p.guardado, guardadoCurto) : null;
    return [...cabeca, ...(guardado ? [guardado] : []), ...(itens.length ? ["", ...itens] : []), "", ...fim].join("\n");
  };
  // o "logo abaixo" com nomes (o filtro à vista) vale mais que o detalhe da agenda e da promessa; o guardado encurta
  // por último (uma linha e "e mais N")
  for (const [curta, nomes, gCurto] of [
    [false, true, false], [true, true, false], [false, false, false], [true, false, false], [true, false, true],
  ] as const) {
    const t = montar(curta, nomes, gCurto);
    if (t.length <= META_DE_CARACTERES) return t;
  }
  return montar(true, false, true);
}

/**
 * (16/10/2026) Domingo e feriado com o que o portão guardou: "Bom dia! Domingo. 1 coisa ficou de ontem: X. *lista* se
 * quiser ver." Sem guardado, a linha de sempre.
 */
export function linhaDeFolgaComGuardado(tipo: TipoDoDia, feriado: string | null, guardado: PlanoDoGuardado | null | undefined): string {
  const bloco = guardado ? blocoDaFolga(guardado) : null;
  if (!bloco) return linhaDeFolga(tipo, feriado);
  const dia = tipo === "domingo" ? "Domingo" : `Feriado${feriado ? ` (${feriado})` : ""}`;
  return `Bom dia! ${dia}. ${bloco} *lista* se quiser ver.`;
}

// ─── Escritório (o comando *escritório*: a papelada contada na montagem) ───────────────────────

export interface DadosDoEscritorio {
  propostas: { saidas: number; entradas: number; transferencias: number; outras: number } | null;
  alertas: number | null;
  regras: number | null;
  debitosSemLoja: number | null;
  entradas: { doMes: number; sinais: number; antigas: number } | null;
}

export function textoDoEscritorio(d: DadosDoEscritorio, hora: string): string {
  const linhas: string[] = [];
  const p = d.propostas;
  if (p && p.saidas + p.entradas + p.transferencias + p.outras > 0) {
    const partes = [
      p.saidas ? plural(p.saidas, "saída", "saídas") : "",
      p.entradas ? plural(p.entradas, "entrada", "entradas") : "",
      p.transferencias ? plural(p.transferencias, "transferência", "transferências") : "",
      p.outras ? plural(p.outras, "outra", "outras") : "",
    ].filter(Boolean);
    linhas.push(`• Lançamentos do extrato para conferir: ${partes.length > 1 ? `${partes.slice(0, -1).join(", ")} e ${partes[partes.length - 1]}` : partes[0]}`);
  }
  if (d.alertas) linhas.push(`• ${plural(d.alertas, "gasto fora do padrão", "gastos fora do padrão")}`);
  if (d.regras) linhas.push(`• ${plural(d.regras, "regra que aprendi esperando você conferir", "regras que aprendi esperando você conferir")}`);
  if (d.debitosSemLoja) linhas.push(`• ${plural(d.debitosSemLoja, "compra no débito sem loja", "compras no débito sem loja")}`);
  const e = d.entradas;
  if (e && e.doMes + e.sinais + e.antigas > 0) {
    const partes = [
      e.doMes ? `${e.doMes} do mês` : "",
      e.sinais ? `${e.sinais} que ${e.sinais === 1 ? "parece ser sinal já lançado" : "parecem ser sinais já lançados"}` : "",
      e.antigas ? `${e.antigas} ${e.antigas === 1 ? "antiga ou de centavos" : "antigas ou de centavos"}` : "",
    ].filter(Boolean);
    linhas.push(`• Entradas do banco sem identificação: ${partes.join(", ")}`);
  }
  if (!linhas.length) return `Escritório em dia (contado às ${hora}).`;
  return [`Escritório (contado às ${hora}):`, ...linhas, "Fica tudo no Extrato. Me peça um grupo por vez (ex.: \"débitos sem loja\")."].join("\n");
}
