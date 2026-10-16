// Os textos do lote da papelada (secretário, Passo 5, 16/10/2026) — puros, sem banco e sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md §3.5–3.8.
//
//   Escritório da semana: 24 itens prontos para um sim só (16 despesas, R$ 2.670,92; 1 transferência; 7 avisos) e
//   44 que precisam de você; uns 25 min. *lote*
//
// Sem jargão ("conciliação", "pendência", "ferramenta"), sem emoji, números do banco.

import type { GrupoDoLote, ItemDeFora, ItemDoLote } from "./lote.ts";

export type FormatoDaPapelada = "desligado" | "sombra" | "ligado";
export const CHAVE_DA_PAPELADA = "papelada_lote";
/** A tool que o "sim <PIN>" do lote executa (só pela pendência; fora da lista do modelo). */
export const NOME_DA_TOOL_DO_LOTE = "aprovar_lote_da_papelada";

/** A chave app_settings.papelada_lote. Ausente ou estranha = desligado (nada muda por engano). */
export function lerFormatoDaPapelada(v: unknown): FormatoDaPapelada {
  const s = String(v ?? "").trim().toLowerCase().replace(/"/g, "");
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

const FMT = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
export function reais(v: number): string {
  return FMT.format(Number(v) || 0).replace(/\u00a0/g, " ");
}

function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

function juntar(partes: string[]): string {
  const p = partes.filter(Boolean);
  return p.length <= 1 ? p.join("") : `${p.slice(0, -1).join(", ")} e ${p[p.length - 1]}`;
}

/** O que a linha e o detalhe precisam do lote (o montado ou o gravado). */
export interface LoteParaTexto {
  dia?: string | null;
  itens: ItemDoLote[];
  fora: ItemDeFora[];
  total: number;
  minutos: number;
}

/**
 * A linha do escritório no fechamento do último dia útil da semana (no lugar de "Escritório: …").
 * null = nada pronto e nada de fora (a linha some, como a do escritório vazio).
 */
export function linhaDoLote(l: LoteParaTexto): string | null {
  const desp = l.itens.filter((i) => i.grupo === "despesa").length;
  const transf = l.itens.filter((i) => i.grupo === "transferencia").length;
  const avisos = l.itens.filter((i) => i.grupo === "aviso").length;
  if (!l.itens.length && !l.fora.length) return null;
  const minutos = l.minutos > 0 ? `; uns ${l.minutos} min` : "";
  if (!l.itens.length) {
    return `Escritório da semana: nada pronto para um sim só; ${plural(l.fora.length, "item precisa", "itens precisam")} de você${minutos}. *escritório*`;
  }
  const partes = [
    desp ? `${plural(desp, "despesa", "despesas")}, ${reais(l.total)}` : "",
    transf ? plural(transf, "transferência", "transferências") : "",
    avisos ? plural(avisos, "aviso", "avisos") : "",
  ].filter(Boolean).join("; ");
  const fora = l.fora.length ? ` e ${l.fora.length} que ${l.fora.length === 1 ? "precisa" : "precisam"} de você` : "";
  return `Escritório da semana: ${plural(l.itens.length, "item pronto", "itens prontos")} para um sim só (${partes})${fora}${minutos}. *lote*`;
}

/** A linha do item no detalhe: "2. Fatura C6, R$ 400,00 (15 de 15 sem troca)". */
export function linhaDoItem(i: ItemDoLote): string {
  if (i.grupo === "aviso") return `${i.n}. ${i.titulo}${i.codigo === "aviso_lancado" ? " (já lançado)" : ""}`;
  const categoria = i.grupo === "despesa" && i.categoria && !/^Fatura /.test(i.titulo) ? ` — ${i.categoria}` : "";
  const motivo = i.grupo === "transferencia" ? "" : ` (${i.motivo})`;
  return `${i.n}. ${i.titulo}, ${reais(i.valor)}${categoria}${motivo}`;
}

/** O resumo do que ficou fora, por motivo, numa frase. */
export function resumoDeFora(fora: ItemDeFora[]): string | null {
  if (!fora.length) return null;
  const n = (...cs: string[]) => fora.filter((f) => cs.includes(f.codigo)).length;
  const soma = (...cs: string[]) => fora.filter((f) => cs.includes(f.codigo)).reduce((s, f) => s + f.valor, 0);
  const avisos = fora.filter((f) => f.grupo === "aviso");
  const dobro = n("duplicidade");
  const sinais = n("sinal_ja_lancado");
  const outrasEntradas = fora.filter((f) => f.grupo === "entrada").length - sinais;
  const partes = [
    n("sem_categoria") ? `${n("sem_categoria")} que não sei o que ${n("sem_categoria") === 1 ? "é" : "são"}` : "",
    n("sem_loja") ? plural(n("sem_loja"), "débito sem loja", "débitos sem loja") : "",
    n("com_aviso") ? `${plural(n("com_aviso"), "despesa", "despesas")} com aviso de gasto junto` : "",
    avisos.length ? `${plural(avisos.length, "aviso", "avisos")}${dobro ? ` (${dobro} de cobrança em dobro)` : ""}` : "",
    sinais ? `${sinais === 1 ? "1 entrada que parece sinal já lançado" : `${sinais} entradas que parecem sinais já lançados`} (${reais(soma("sinal_ja_lancado"))})` : "",
    outrasEntradas > 0 ? plural(outrasEntradas, sinais ? "outra entrada" : "entrada", sinais ? "outras entradas" : "entradas") : "",
    n("contradiz") ? `${n("contradiz")} em que você costuma lançar outra categoria` : "",
    n("acima_do_limite") ? `${n("acima_do_limite")} de R$ 500 ou mais` : "",
    n("vinculo", "os_oc", "terceiro") ? `${n("vinculo", "os_oc", "terceiro")} com vínculo, OS ou serviço de terceiro` : "",
    n("sem_historico") ? `${n("sem_historico")} ainda sem histórico` : "",
    n("ja_lancado") ? `${n("ja_lancado")} já lançados` : "",
    n("comprovante") ? `${n("comprovante")} com comprovante a caminho` : "",
  ].filter(Boolean);
  return `Ficaram de fora ${fora.length}, com você no *escritório*: ${partes.join("; ")}.`;
}

const NOME_DO_GRUPO: Record<GrupoDoLote, string> = { despesa: "despesas", transferencia: "transferências", aviso: "avisos" };

/** Os motivos da conferência na hora do "sim" (papelada_lote_conferir), em palavras. */
export function motivoDaConferencia(codigo: string): string {
  switch (codigo) {
    case "ja_decidido_approved": return "você já aprovou";
    case "ja_decidido_rejected": return "você recusou";
    case "ja_decidido_superseded": return "já foi lançada por outro caminho";
    case "mudou": return "mudou desde que montei o lote";
    case "ja_lancado": return "a linha do banco já foi lançada";
    case "aviso_novo": return "ganhou um aviso de gasto";
    case "sumiu": return "saiu da fila";
    default: return codigo.replace(/_/g, " ");
  }
}

/** O porquê de não dar para usar o lote agora (o erro da conferência), em palavras. */
export function textoDoErroDoLote(erro: string | null | undefined): string {
  switch (erro) {
    case "lote_aplicado": return "Esse lote já foi aprovado. O próximo sai na sexta, às 17:30.";
    case "lote_aplicando": return "Esse lote está sendo aprovado agora. Daqui a pouco escreva *lote* para ver o resultado.";
    case "lote_vencido": return "Esse lote venceu. O próximo sai na sexta, às 17:30; *escritório* mostra a papelada de hoje.";
    case "lote_substituido": return "Há um lote mais novo: escreva *lote* de novo.";
    case "sombra": return "O lote está em ensaio: ainda não aprovo nada por aqui.";
    case "nada_valido": return "Nada do lote continua igual a quando eu o montei: não há o que aprovar.";
    case "nada_escolhido": return "Com esse recorte não sobrou nenhum item.";
    case "item_fora_do_lote": return "Um dos itens não está no lote. Escreva *lote* para ver a lista.";
    case "so_admin": return "Só o dono aprova o lote.";
    case "sem_lote": return "Não há lote pronto agora. O próximo sai na sexta, às 17:30; *escritório* mostra a papelada de hoje.";
    default: return "Não consegui conferir o lote agora. Tente *lote* de novo daqui a pouco.";
  }
}

export interface OpcoesDoDetalhe {
  /** "sexta, 16/10" */
  quando?: string | null;
  /** os itens escolhidos (o recorte); ausente = todos */
  escolhidos?: ItemDoLote[];
  /** "sem os itens 3 e 18" / "só despesas" */
  recorte?: string | null;
  /** o que a conferência de agora tirou (por número) */
  saiuAgora?: Array<{ n: number; codigo: string }>;
  formato: "sombra" | "ligado";
  /** quantas regras sugeridas ficam guardadas (fora do lote) */
  regrasGuardadas?: number | null;
}

/** O detalhe do lote (*lote*): o cabeçalho, os itens numerados, o que ficou de fora e como aprovar. */
export function textoDoLote(l: LoteParaTexto, o: OpcoesDoDetalhe): string {
  const saiu = new Map((o.saiuAgora ?? []).map((s) => [s.n, s.codigo]));
  const escolhidos = (o.escolhidos ?? l.itens).filter((i) => !saiu.has(i.n));
  const despesas = escolhidos.filter((i) => i.grupo === "despesa");
  const total = Math.round(despesas.reduce((s, i) => s + i.valor, 0) * 100) / 100;
  const quando = o.quando ? ` (${o.quando})` : "";
  const recorte = o.recorte ? `, ${o.recorte}` : "";
  const linhas: string[] = [
    `Lote da semana${quando}${recorte}: ${plural(escolhidos.length, "item pronto", "itens prontos")} para um sim só. ` +
    "Só registra o que já saiu do banco; nenhum dinheiro se move.",
  ];
  const blocos: Array<[GrupoDoLote, string]> = [
    ["despesa", `Despesas: ${despesas.length}, ${reais(total)}`],
    ["transferencia", "Transferência entre contas suas"],
    ["aviso", "Avisos para dar ciente (saem da lista)"],
  ];
  for (const [grupo, titulo] of blocos) {
    const doGrupo = escolhidos.filter((i) => i.grupo === grupo);
    if (!doGrupo.length) continue;
    linhas.push("", titulo, ...doGrupo.map(linhaDoItem));
  }
  if (saiu.size) {
    const tirados = [...saiu.entries()].map(([n, c]) => `${n} (${motivoDaConferencia(c)})`);
    linhas.push("", `Saíram desde que montei: ${juntar(tirados)}.`);
  }
  const fora = resumoDeFora(l.fora);
  if (fora) linhas.push("", fora);
  if (o.regrasGuardadas && o.regrasGuardadas > 0) {
    linhas.push(`${plural(o.regrasGuardadas, "regra sugerida fica guardada", "regras sugeridas ficam guardadas")} até você decidir (não entram no lote).`);
  }
  linhas.push("");
  if (!escolhidos.length) {
    linhas.push("Nada para aprovar neste recorte.");
  } else if (o.formato === "sombra") {
    linhas.push("(Ensaio: o lote está guardado para comparar; ainda não aprovo nada por aqui.)");
  } else {
    linhas.push(`Para aprovar ${escolhidos.length === 1 ? "o item" : `os ${escolhidos.length}`}: *sim <seu PIN>*. ` +
      "Para tirar algum: *lote sem 3, 7* ou *lote sem avisos*.");
  }
  return linhas.join("\n");
}

/** O título da confirmação (o cartão do "sim <PIN>"). */
export function tituloDaConfirmacao(itens: ItemDoLote[]): string {
  const desp = itens.filter((i) => i.grupo === "despesa");
  const total = desp.reduce((s, i) => s + i.valor, 0);
  return `Aprovar o lote da papelada: ${plural(itens.length, "item", "itens")}${desp.length ? `, ${reais(total)} em despesas` : ""}`;
}

export interface ResultadoDoLote {
  itens: Array<{ n: number; id: string; situacao: string; motivo?: string | null }>;
  entrou: number;
  falhou: number;
  fora: number;
  valor_entrou: number;
}

/** O relatório depois do "sim": o que entrou e o que não entrou, item por item. */
export function textoDoResultado(r: ResultadoDoLote, titulos: Map<number, string>): string {
  const total = r.itens.length;
  const nome = (n: number) => `${n}. ${titulos.get(n) ?? "item"}`;
  const naoEntrou = r.itens.filter((i) => i.situacao !== "entrou").sort((a, b) => a.n - b.n);
  const cab = `Entraram ${r.entrou} de ${total}${r.valor_entrou > 0 ? ` (despesas: ${reais(r.valor_entrou)})` : ""}.`;
  if (!naoEntrou.length) return `${cab} Para desfazer alguma despesa, é pelo Extrato ou me pedindo.`;
  const porQue = (i: { situacao: string; motivo?: string | null }) =>
    i.situacao === "fora" ? motivoDaConferencia(String(i.motivo ?? ""))
    : i.situacao === "incompleto" ? "ficou pela metade: o lançamento nasceu e a linha não saiu da fila; confira no Extrato"
    : String(i.motivo ?? "não entrou");
  const lista = naoEntrou.slice(0, 6).map((i) => `${nome(i.n)} (${porQue(i)})`);
  const resto = naoEntrou.length - lista.length;
  return `${cab} Não entraram ${naoEntrou.length}: ${lista.join("; ")}${resto > 0 ? `; e mais ${resto}` : ""}.`;
}

export { NOME_DO_GRUPO };
