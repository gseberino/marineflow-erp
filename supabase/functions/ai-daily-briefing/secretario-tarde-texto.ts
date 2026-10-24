// O texto da tarde (secretário, Passo 3, 15/10/2026) — puro, sem banco e sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md §4.
//
//   Fechamento de quinta, 15/10. Ficaram 2 de hoje; sem resposta, vão para a revisão de segunda.
//
//   *B.* <a linha curta de agora>. *B* = <faço> · *B espera* = <alternativa>
//   …
//
//   Amanhã (sexta, 16/10): <agenda e compra que precisa sair> | nada marcado; 6 OS ativas sem data (ou com a data vencida) | agenda livre.
//   (24/10/2026, agenda de produção LIGADA) a cauda sem nada marcado vem dela: "nada marcado; nenhum serviço pronto, 7
//   esperando você (*agenda*)"; na quinta, logo abaixo, até 3 linhas "Semana que vem (projeção): …" se sobrou vaga
//   (contam como 1 dos REGRAS.maxManha). Na sombra (como nasce), nada disso: o texto é o de antes e vai para o detalhe.
//   Fornecedores esperando há mais de 1 dia: <nomes>.
//   Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 25 min. *escritório*
//   (sexta) Esta semana o resumo ajudou? Responda *ajudou*, *pouco* ou *atrapalhou*.
//
// Revisão da semana: até 5 parados com a letra do dia, a forma de responder de uma vez e o panorama (mês
// corrigido, vigia, semana). Revisão do mês: o mês que fechou e as cobranças de 30+ dias.
// Sem jargão ("conciliação", "pendência", "ferramenta"), sem emoji, "parece" para dedução (vem dos candidatos).
// Meta ~900 caracteres; corte duro em 1.000 (as linhas encurtam primeiro).

import { brl, ddmm, nomeDoDia, somarDias, umaLinha } from "../_shared/secretario/base.ts";
import { type TurnoDaTarde, turnoDaTarde } from "../_shared/secretario/turno.ts";
import type { CobrancasAntigas, LinhaComLetra, SemRespostaDeHoje } from "./secretario-tarde-regras.ts";
import { blocoDoFechamento, type PlanoDoGuardado } from "../_shared/uma-voz/guardado.ts";
import type { DadosDoEscritorio } from "./secretario-texto.ts";
import { linhaDoLote, type LoteParaTexto } from "../_shared/papelada/texto.ts";
import { REGRAS } from "./secretario-candidatos.ts";

export const META_DA_TARDE = 900;
export const LIMITE_DA_TARDE = 1000;

export const PERGUNTA_DA_SEMANA = "Esta semana o resumo ajudou? Responda *ajudou*, *pouco* ou *atrapalhou*.";

const FMT0 = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
/** "R$ 38.729" (sem centavos, espaço comum): o panorama fala em ordem de grandeza. */
export function reais0(v: number): string {
  return FMT0.format(Math.round(v)).replace(/\u00a0/g, " ");
}

const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
/** 'aaaa-mm' → "outubro". */
export function nomeDoMes(aaaaMm: string): string {
  return MESES[Number(aaaaMm.slice(5, 7)) - 1] ?? aaaaMm;
}

function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

function lista(nomes: string[], max = 3): string {
  const v = nomes.slice(0, max);
  const resto = nomes.length - v.length;
  if (resto > 0) return `${v.join(", ")} e mais ${resto}`;
  return v.length <= 1 ? v.join("") : `${v.slice(0, -1).join(", ")} e ${v[v.length - 1]}`;
}

// ─── Pedaços ────────────────────────────────────────────────────────────────────────────────────

/** "*B.* <texto>. *B* = <faço> · *B espera* = <alternativa>" — a linha do fechamento. */
export function linhaQueFicou(l: LinhaComLetra, max = 150): string {
  const resposta = l.faco
    ? ` *${l.letra}* = ${l.faco}${l.alternativa ? ` · *${l.letra} ${l.comandoAlternativo}* = ${l.alternativa}` : ""}`
    : "";
  return `*${l.letra}.* ${umaLinha(l.texto, max)}.${resposta}`;
}

/** "*G.* <texto>" — a linha das revisões (a resposta vem uma vez, no fim). */
export function linhaDaRevisao(l: LinhaComLetra, max = 140): string {
  return `*${l.letra}.* ${umaLinha(l.texto, max)}`;
}

export interface DiaDeAmanha {
  /** o próximo dia com manhã (seg–sáb, sem feriado) */
  dia: string;
  /** compromissos (OS marcada, tarefa com hora) e compras que precisam sair, na ordem */
  itens: Array<{ hora: string | null; texto: string }>;
  /** (16/10/2026, F3) contas a pagar que vencem até `dia` (depois de hoje): quantas e o total. Ausente = não leu */
  pagar?: { n: number; total: number } | null;
  /**
   * (23/10/2026, D11b) A carteira: quantas OS ativas (fora as que esperam o cliente) não têm data, ou têm data que já
   * passou. É o trabalho que existe e não está em dia nenhum. Ausente ou null = não leu.
   */
  carteira?: { semData: number } | null;
  /**
   * (24/10/2026, Agenda de Produção Fase 1, P6) O que a agenda diria no fechamento (agenda_textos_do_fechamento). Só
   * com modo 'ligado' alguma coisa muda no texto; com 'sombra' (como nasce) ou ausente, o texto é o de antes, byte a
   * byte, e o que ela diria vai para o detalhe.
   */
  agenda?: AgendaDoFechamento | null;
}

/** As linhas da agenda para o fechamento (agenda_textos_do_fechamento, migration 20261024160500), já conferidas. */
export interface AgendaDoFechamento {
  modo: "sombra" | "ligado";
  /** a cauda do "Amanhã" sem nada marcado ("nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)"); null = a agenda vê algo marcado */
  cauda: string | null;
  /** só no dia do plano (quinta): até 3 linhas "Semana que vem (projeção)", cada uma com até 160 caracteres */
  semana: string[];
}

/** Até quantos caracteres cada item vai na linha "Amanhã" (a coleta monta o da OS para caber nisso). */
export const CORTE_DO_ITEM_DE_AMANHA = 50;

/**
 * O "Amanhã" sem nada marcado. "agenda livre" SÓ quando a carteira foi lida e não há OS sem data: até 23/10/2026 a
 * frase saía sempre, e era falsa — o trabalho de verdade estava nas OS sem data (6 delas nesse dia).
 *
 * O texto diz o que osSemData conta (revisão de 23/10/2026): OS ATIVA (aberta, aprovada, agendada, em andamento,
 * aguardando peças) sem data OU com a janela já vencida. Até então dizia "aprovadas sem data", e não era nem uma
 * coisa nem outra: a OS-00104 aguarda peças e tem data (06–08/10, vencida); as OS-00069/74/100 estão abertas.
 *
 * (24/10/2026, P6) Com a agenda de produção LIGADA, a cauda vem dela ("nada marcado; prontos para começar: Lenine e
 * Flávio (*agenda*)" ou "…, 7 esperando você (*agenda*)"): diz o que está pronto e quem espera o dono, em vez de só
 * contar as OS. Na sombra, ou se a agenda vê algo marcado no dia (cauda null), fica a frase de antes.
 */
function semNadaMarcado(c: DiaDeAmanha["carteira"], agenda?: AgendaDoFechamento | null): string {
  if (agenda?.modo === "ligado" && agenda.cauda) return agenda.cauda;
  if (!c) return "nada marcado";
  return c.semData > 0
    ? `nada marcado; ${plural(c.semData, "OS ativa sem data (ou com a data vencida)", "OS ativas sem data (ou com a data vencida)")}`
    : "agenda livre";
}

/** "Amanhã (sexta, 16/10): 08:00 OS-00112 (Santo Inácio 7.8); comprar 4 itens da OS-00112." */
export function linhaDeAmanha(hoje: string, a: DiaDeAmanha): string {
  const rotulo = a.dia === somarDias(hoje, 1)
    ? `Amanhã (${nomeDoDia(a.dia).toLowerCase()}, ${ddmm(a.dia)})`
    : `${nomeDoDia(a.dia)} (${ddmm(a.dia)})`;
  // F3 (16/10/2026): a conta a pagar que vence até a próxima manhã
  const pagar = a.pagar && a.pagar.n > 0 ? `; a pagar: ${plural(a.pagar.n, "conta", "contas")}, ${brl(a.pagar.total)}` : "";
  if (!a.itens.length) return `${rotulo}: ${semNadaMarcado(a.carteira, a.agenda)}${pagar}.`;
  const itens = a.itens.slice(0, 3).map((i) => `${i.hora ? `${i.hora} ` : ""}${umaLinha(i.texto, CORTE_DO_ITEM_DE_AMANHA)}`);
  return `${rotulo}: ${itens.join("; ")}${a.itens.length > 3 ? ` (e mais ${a.itens.length - 3})` : ""}${pagar}.`;
}

/**
 * (24/10/2026, P6) A linha "Amanhã" que a agenda LIGADA mandaria, ou null quando ela não muda nada (o dia tem
 * compromisso, a agenda vê algo marcado, ou não leu). Na sombra é o que vai para o detalhe, para comparar.
 */
export function amanhaComAAgenda(hoje: string, a: DiaDeAmanha | null): string | null {
  if (!a?.agenda?.cauda || a.itens.length) return null;
  return linhaDeAmanha(hoje, { ...a, agenda: { ...a.agenda, modo: "ligado" } });
}

/**
 * (24/10/2026, P6) As linhas "Semana que vem (projeção)" cabem no fechamento? A agenda só as manda no dia do plano
 * (quinta), e elas contam como 1 dos REGRAS.maxManha itens do Secretário: com 3 que ficaram de hoje não há vaga, e
 * elas ficam no detalhe e em *agenda semana que vem* (não passam para a sexta).
 */
export function semanaCabe(ficaram: number, agenda: AgendaDoFechamento | null | undefined): boolean {
  return !!agenda && agenda.semana.length > 0 && ficaram < REGRAS.maxManha;
}

/** Quanto tempo a papelada leva: 20 s por lançamento ou alerta, 1 min por débito sem loja (arredonda em 5). */
export function minutosDoEscritorio(d: DadosDoEscritorio): number {
  const p = d.propostas;
  const lancamentos = p ? p.saidas + p.entradas + p.transferencias + p.outras : 0;
  const segundos = (lancamentos + (d.alertas ?? 0)) * 20 + (d.debitosSemLoja ?? 0) * 60;
  if (segundos <= 0) return 0;
  return Math.max(5, Math.round(segundos / 300) * 5);
}

/**
 * "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 25 min. *escritório*".
 * (16/10/2026) `guardado` = o que o portão mandou para o escritório (saldo do banco que não bate…): entra na mesma
 * linha ("…, e o saldo do banco C6 não bate…"), sem mudar os minutos.
 */
export function linhaDoEscritorio(d: DadosDoEscritorio | null, guardado: string[] = []): string | null {
  const extra = guardado.length ? guardado.slice(0, 2).join("; ") + (guardado.length > 2 ? ` e mais ${guardado.length - 2}` : "") : "";
  if (!d) return extra ? `Escritório: ${extra}. *escritório*` : null;
  const p = d.propostas;
  const lanc = p
    ? [
      p.saidas ? plural(p.saidas, "despesa", "despesas") : "",
      p.entradas ? plural(p.entradas, "entrada", "entradas") : "",
      p.transferencias ? plural(p.transferencias, "transferência", "transferências") : "",
      p.outras ? plural(p.outras, "outro lançamento", "outros lançamentos") : "",
    ].filter(Boolean)
    : [];
  const partes = [
    lanc.length ? `${lista(lanc, 4)} para conferir` : "",
    d.alertas ? plural(d.alertas, "alerta", "alertas") : "",
    d.debitosSemLoja ? plural(d.debitosSemLoja, "débito sem loja", "débitos sem loja") : "",
  ].filter(Boolean);
  if (!partes.length) return extra ? `Escritório: ${extra}. *escritório*` : null;
  return `Escritório: ${partes.join(", ")}${extra ? `, e ${extra}` : ""}; uns ${minutosDoEscritorio(d)} min. *escritório*`;
}

/** O nome da próxima revisão da semana depois de `hoje` ("segunda"; "quarta (04/11)" quando não é segunda). */
export function proximaRevisaoDaSemana(hoje: string): string | null {
  for (let i = 1; i <= 14; i++) {
    const d = somarDias(hoje, i);
    if (turnoDaTarde(d) === "revisao_semana") {
      const nome = nomeDoDia(d).toLowerCase();
      return nome === "segunda" ? nome : `${nome} (${ddmm(d)})`;
    }
  }
  return null;
}

// ─── Panorama (revisão da semana) e o mês que fechou (revisão do mês) ──────────────────────────

export interface ContaDoMes {
  /** 'aaaa-mm' */
  mes: string;
  receita: number;
  /** custos e despesas já lançados (grupos do resultado) */
  saidas: number;
  /** despesas do mês ainda na fila (create_payable pendente), o "corrigido" */
  pendentes: { n: number; soma: number };
}

export interface Panorama {
  mes: ContaDoMes | null;
  /** a 1ª constatação do vigia, já sem emoji e sem negrito */
  vigia: string | null;
  semana: { entra: number; nEntra: number; sai: number; nSai: number; ate: string } | null;
}

/** "resultado perto de R$ W" / "prejuízo de R$ W" (o ensaio de 01/10: setembro fechou negativo). */
function oResultado(valor: number, estimado: boolean): string {
  const perto = estimado ? "perto de " : "";
  return valor < 0 ? `prejuízo ${perto || "de "}${reais0(-valor)}` : `resultado ${perto}${reais0(valor)}`;
}

/** "Mês até aqui: receita R$ X; custos e despesas R$ Y, com R$ Z ainda para conferir; resultado perto de R$ W." */
export function linhaDoMesAteAqui(m: ContaDoMes): string {
  const custos = m.saidas + m.pendentes.soma;
  const conferir = m.pendentes.n > 0 ? `, com ${reais0(m.pendentes.soma)} ainda para conferir` : "";
  return `Mês até aqui: receita ${reais0(m.receita)}; custos e despesas ${reais0(custos)}${conferir}; ${oResultado(m.receita - custos, m.pendentes.n > 0)}.`;
}

/** "Setembro fechou: receita R$ X; custos e despesas R$ Y (N ainda para conferir, R$ Z); prejuízo perto de R$ W." */
export function linhaDoMesQueFechou(m: ContaDoMes): string {
  const custos = m.saidas + m.pendentes.soma;
  const nome = nomeDoMes(m.mes);
  const conferir = m.pendentes.n > 0
    ? ` (${plural(m.pendentes.n, "despesa", "despesas")} de ${nome} ainda para conferir, ${reais0(m.pendentes.soma)})`
    : "";
  return `${nome[0].toUpperCase()}${nome.slice(1)} fechou: receita ${reais0(m.receita)}; custos e despesas ${reais0(custos)}${conferir}; ${oResultado(m.receita - custos, m.pendentes.n > 0)}.`;
}

/** "Semana até domingo (25/10): a receber nada; a pagar R$ 785 (1 conta) — sai mais do que entra." */
export function linhaDaSemana(s: NonNullable<Panorama["semana"]>): string {
  const receber = s.nEntra ? `${reais0(s.entra)} (${plural(s.nEntra, "cobrança", "cobranças")})` : "nada";
  const pagar = s.nSai ? `${reais0(s.sai)} (${plural(s.nSai, "conta", "contas")})` : "nada";
  const vermelho = s.sai > s.entra ? " — sai mais do que entra" : "";
  return `Semana até ${nomeDoDia(s.ate).toLowerCase()} (${ddmm(s.ate)}): a receber ${receber}; a pagar ${pagar}${vermelho}.`;
}

/** A constatação do vigia numa linha: sem emoji, sem negrito, até ~130 caracteres. */
export function linhaDoVigia(constatacao: string | null): string | null {
  if (!constatacao) return null;
  const limpa = constatacao
    .replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, "")
    .replace(/[*_]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return limpa ? `Vigia: ${umaLinha(limpa, 130)}` : null;
}

// ─── A mensagem inteira ────────────────────────────────────────────────────────────────────────

export interface DadosDaTarde {
  hoje: string;
  turno: TurnoDaTarde;
  /** fechamento */
  ficaram: LinhaComLetra[];
  amanha: DiaDeAmanha | null;
  fornecedores: string[];
  escritorio: DadosDoEscritorio | null;
  /** revisão da semana */
  parados: LinhaComLetra[];
  panorama: Panorama | null;
  /** revisão do mês */
  antigas: CobrancasAntigas | null;
  mesQueFechou: ContaDoMes | null;
  faturamento: string | null;
  /** a pergunta da sexta vai junto */
  pergunta: boolean;
  /**
   * (16/10/2026) O que o portão guardou para esta tarde (só quando a tarde NÃO sai: sombra). Linhas no topo ("Não te
   * interrompi com: …") e as do escritório na linha dele. Guardado conta como "há algo" (fora o do escritório).
   */
  guardado?: PlanoDoGuardado | null;
  /** (16/10/2026, F1) quem escreveu hoje e está sem resposta (e quem o portão acordou hoje), sem letra */
  semResposta?: SemRespostaDeHoje[];
  /** quantos nomes a linha do F1 cita (o resto vira "e mais N") */
  semRespostaMax?: number;
  /**
   * (16/10/2026, Passo 5) O lote semanal da papelada, no último dia útil da semana: no fechamento a linha do lote fica no
   * lugar da do escritório; nas revisões, uma linha antes da pergunta. Ausente = a tarde de antes, byte a byte.
   */
  lote?: LoteParaTexto | null;
}

/** A linha do escritório da tarde: a do lote (no dia dele) ou a de sempre; o guardado do escritório vai à parte. */
function linhasDoEscritorioDaTarde(d: DadosDaTarde): string[] {
  const guardado = d.guardado?.escritorio ?? [];
  if (!d.lote) return [linhaDoEscritorio(d.escritorio, guardado)].filter((l): l is string => !!l);
  return [linhaDoLote(d.lote) ?? linhaDoEscritorio(d.escritorio), guardado.length ? linhaDoEscritorio(null, guardado) : null]
    .filter((l): l is string => !!l);
}

export interface TextoDaTarde {
  /** null = nada a dizer (o dia calado) */
  texto: string | null;
  /** as linhas com letra mostradas */
  letras: LinhaComLetra[];
  /**
   * (24/10/2026, P6) O que da agenda de produção foi PUBLICADO: a cauda dela no "Amanhã" e quantas linhas da semana que
   * vem. Só existe quando a agenda foi lida (DiaDeAmanha.agenda); na sombra é sempre {cauda: false, semana: 0}.
   */
  agenda?: { cauda: boolean; semana: number };
}

/** As linhas da semana que vem que podem ir no fechamento (agenda ligada, dia do plano, com vaga); senão nenhuma. */
function semanaDoFechamento(d: DadosDaTarde): string[] {
  const ag = d.amanha?.agenda;
  if (d.turno !== "fechamento" || ag?.modo !== "ligado" || !semanaCabe(d.ficaram.length, ag)) return [];
  return ag.semana;
}

/** Acrescenta ao texto montado o que da agenda saiu nele (só quando a agenda foi lida). */
function comAAgenda(t: TextoDaTarde, d: DadosDaTarde, semana: number): TextoDaTarde {
  const a = d.amanha;
  if (!a?.agenda) return t;
  const cauda = !!t.texto && a.agenda.modo === "ligado" && !!a.agenda.cauda && a.itens.length === 0;
  return { ...t, agenda: { cauda, semana: t.texto ? semana : 0 } };
}

/** F1: "Sem resposta desde hoje: Giancarlo S. (10:31); Miguel (09:02, acordei às 09:45) e mais 1." */
export function linhaSemResposta(lista: SemRespostaDeHoje[] | undefined, max = 2): string | null {
  if (!lista?.length) return null;
  const nomes = lista.slice(0, max).map((s) => `${s.nome} (${s.desde}${s.acordei ? `, acordei às ${s.acordei}` : ""})`);
  const resto = lista.length - nomes.length;
  return `Sem resposta desde hoje: ${nomes.join("; ")}${resto > 0 ? ` e mais ${resto}` : ""}.`;
}

/** As linhas do topo da tarde (o guardado e o F1), na ordem. */
function topoDaTarde(d: DadosDaTarde, curto: boolean): string[] {
  return [
    d.guardado ? blocoDoFechamento(d.guardado, curto) : null,
    linhaSemResposta(d.semResposta, curto ? 1 : d.semRespostaMax ?? 2),
  ].filter((l): l is string => !!l);
}

function cabecaDoDia(hoje: string): string {
  return `${nomeDoDia(hoje).toLowerCase()}, ${ddmm(hoje)}`;
}

function textoDoFechamento(d: DadosDaTarde, curto: boolean, semanaMax: number): TextoDaTarde {
  const topo = topoDaTarde(d, curto);
  // (24/10/2026, P6) a semana que vem da agenda ligada, na quinta e com vaga (uma das REGRAS.maxManha): conta como "há
  // algo" — é o plano da semana. A cauda do "Amanhã" NÃO conta (existe todo dia, como a carteira sem data)
  const semanaToda = semanaDoFechamento(d);
  const semana = semanaToda.slice(0, semanaMax);
  // (16/10/2026) guardado (fora o do escritório), quem está sem resposta desde hoje e a conta a pagar de amanhã contam
  // como "há algo": sem isso, "só se houver algo" viraria descarte do guardado (spec uma voz §6.3-1)
  // (23/10/2026) a carteira sem data NÃO conta: ela existe quase todo dia, e o fechamento passaria a sair sempre
  const temAlgo = d.ficaram.length > 0 || (d.amanha?.itens.length ?? 0) > 0 || (d.amanha?.pagar?.n ?? 0) > 0 ||
    d.fornecedores.length > 0 || d.pergunta || topo.length > 0 || semanaToda.length > 0;
  if (!temAlgo) return comAAgenda({ texto: null, letras: [] }, d, 0);
  const proxima = proximaRevisaoDaSemana(d.hoje);
  const abertura = d.ficaram.length
    ? `Fechamento de ${cabecaDoDia(d.hoje)}. ${d.ficaram.length === 1 ? "Ficou 1" : `Ficaram ${d.ficaram.length}`} de hoje` +
      `${proxima ? `; sem resposta, ${d.ficaram.length === 1 ? "vai" : "vão"} para a revisão de ${proxima}` : ""}.`
    : `Fechamento de ${cabecaDoDia(d.hoje)}: nada ficou de hoje.`;
  const itens = d.ficaram.map((l) => linhaQueFicou(l, curto ? 90 : 150));
  const fim = [
    d.amanha ? linhaDeAmanha(d.hoje, d.amanha) : null,
    // (24/10/2026, P6) logo depois do "Amanhã": a semana que vem (projeção), só na quinta, ligada e com vaga
    ...semana,
    d.fornecedores.length ? `Fornecedores esperando há mais de 1 dia: ${lista(d.fornecedores.map((n) => umaLinha(n, curto ? 18 : 28)))}.` : null,
    ...linhasDoEscritorioDaTarde(d),
    d.pergunta ? PERGUNTA_DA_SEMANA : null,
  ].filter((l): l is string => !!l);
  return comAAgenda(
    { texto: [abertura, ...topo, ...(itens.length ? ["", ...itens] : []), "", ...fim].join("\n"), letras: d.ficaram },
    d,
    semana.length,
  );
}

function exemploDeResposta(ls: LinhaComLetra[]): string {
  const acoes = ["semana", "tira", "15 dias"];
  return ls.slice(0, 3).map((l, i) => `${l.letra} ${acoes[i]}`).join(", ");
}

/** Quantos parados a revisão mostra (decisão do dono, 15/10/2026: "até 5"). */
export const MAX_PARADOS = 5;

function textoDaRevisaoDaSemana(d: DadosDaTarde, curto: boolean): TextoDaTarde {
  const ps = d.parados.slice(0, MAX_PARADOS);
  const resto = d.parados.length - ps.length;
  const abertura = `Revisão da semana, ${cabecaDoDia(d.hoje)}. ` +
    (ps.length ? `${d.parados.length === 1 ? "1 assunto parado" : `${d.parados.length} assuntos parados`}.` : "Nada parado.");
  const itens = ps.map((l) => linhaDaRevisao(l, curto ? 80 : 100));
  if (resto > 0) itens.push(`…e mais ${resto} na *lista*.`);
  const comoResponder = ps.length
    ? [`Responda tudo numa mensagem, ex.: *${exemploDeResposta(ps)}* (semana = faço esta semana; 15 dias = lembro depois). As letras valem até meia-noite.`]
    : [];
  const p = d.panorama;
  const panorama = [
    // (16/10/2026) o "Amanhã" do fechamento também na revisão de segunda (a terça: OS marcada, tarefa, compra, a pagar)
    d.amanha ? linhaDeAmanha(d.hoje, d.amanha) : null,
    p?.mes ? linhaDoMesAteAqui(p.mes) : null,
    curto ? null : linhaDoVigia(p?.vigia ?? null),
    p?.semana ? linhaDaSemana(p.semana) : null,
  ].filter((l): l is string => !!l);
  const blocos = [abertura, ...topoDaTarde(d, curto), ...(itens.length ? ["", ...itens, ...comoResponder] : []), ...(panorama.length ? ["", ...panorama] : [])];
  // (Passo 5) a linha do lote, no último dia útil da semana que caiu numa revisão
  const lote = d.lote ? linhaDoLote(d.lote) : null;
  if (lote) blocos.push("", lote);
  if (d.pergunta) blocos.push("", PERGUNTA_DA_SEMANA);
  // (24/10/2026, P6) a revisão de segunda também traz o "Amanhã": com a agenda ligada, a cauda dela (a semana que vem,
  // nunca: ela é do fechamento de quinta)
  return comAAgenda({ texto: blocos.join("\n"), letras: ps }, d, 0);
}

function textoDaRevisaoDoMes(d: DadosDaTarde, curto: boolean): TextoDaTarde {
  const a = d.antigas;
  const linhasDoMes = [
    d.mesQueFechou ? linhaDoMesQueFechou(d.mesQueFechou) : null,
    d.faturamento && !curto ? d.faturamento : null,
  ].filter((l): l is string => !!l);
  const abertura = `Revisão do mês, ${cabecaDoDia(d.hoje)}.${linhasDoMes.length ? ` ${linhasDoMes[0]}` : ""}`;
  const blocos = [abertura, ...linhasDoMes.slice(1), ...topoDaTarde(d, curto)];
  if (a && a.n > 0) {
    blocos.push("", `${a.n === 1 ? "1 cobrança vencida" : `${a.n} cobranças vencidas`} há 30 dias ou mais, ${brl(a.total)}. Cobrar, negociar ou dar baixa?`);
    blocos.push(...a.linhas.map((l) => linhaDaRevisao(l, curto ? 85 : 140)));
    if (a.fora.n > 0) blocos.push(`…e mais ${plural(a.fora.n, "cobrança", "cobranças")} (${brl(a.fora.total)}) sem letra hoje.`);
    const l = a.linhas[0]?.letra;
    if (l) {
      blocos.push(`Responda uma por vez: *${l} cobrar*, *${l} negociar* ou *${l} baixa* (nada sai nem é gravado sem o seu sim). As letras valem até meia-noite.`);
    }
  } else {
    blocos.push("", "Nenhuma cobrança vencida há 30 dias ou mais.");
  }
  const lote = d.lote ? linhaDoLote(d.lote) : null;
  if (lote) blocos.push("", lote);
  if (d.pergunta) blocos.push("", PERGUNTA_DA_SEMANA);
  return { texto: blocos.join("\n"), letras: a?.linhas ?? [] };
}

/**
 * A mensagem da tarde. Passou de 1.000 caracteres: as linhas encurtam (e o vigia/faturamento saem).
 * (24/10/2026, P6) Com a semana que vem da agenda no fechamento, ela é a primeira a ceder: 3 linhas → 1 → nenhuma,
 * antes de qualquer outra linha encurtar (ela é a última das REGRAS.maxManha e está inteira em *agenda semana que
 * vem*). Sem ela, o caminho é o de antes, byte a byte.
 */
export function textoDaTarde(d: DadosDaTarde): TextoDaTarde {
  const montar = (curto: boolean, semanaMax: number) =>
    d.turno === "fechamento" ? textoDoFechamento(d, curto, semanaMax)
    : d.turno === "revisao_semana" ? textoDaRevisaoDaSemana(d, curto)
    : textoDaRevisaoDoMes(d, curto);
  const n = semanaDoFechamento(d).length;
  for (const k of [...new Set([n, Math.min(n, 1), 0])]) {
    const longo = montar(false, k);
    if (!longo.texto || longo.texto.length <= LIMITE_DA_TARDE) return longo;
  }
  const curto = montar(true, 0);
  if (curto.texto && curto.texto.length > LIMITE_DA_TARDE) {
    return { ...curto, texto: `${curto.texto.slice(0, LIMITE_DA_TARDE - 1).trimEnd()}…` };
  }
  return curto;
}
