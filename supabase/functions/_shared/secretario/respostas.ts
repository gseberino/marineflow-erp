// As respostas dos comandos do dono sobre a manhã nova — texto puro, sem banco e sem IA.
// Números, datas e nomes vêm do que a montagem gravou às 07:30 (resumo_itens / resumo_manha).

import { ddmm, quandoEmPalavras, umaLinha } from "./base.ts";
import { ficaTodoDia, SECOES, type Secao, TITULO_DA_SECAO } from "./tipos.ts";

/** Um item como está gravado em resumo_itens (o que os comandos leem). */
export interface ItemGravado {
  letra: string;
  principal: boolean;
  posicao: "manha" | "lista";
  ordem: number;
  familia: string;
  tipo: string;
  secao: Secao;
  referencia: string;
  nome: string;
  titulo: string;
  recomendacao: string | null;
  motivo: string;
  pedido: string | null;
  detalhe: DetalheDoItem | null;
  acao: string | null;
  adiado_ate: string | null;
}

/** O detalhe gravado: os fatos em ordem (jsonb não guarda a ordem das chaves) e a resposta. */
export interface DetalheDoItem {
  fatos?: Array<[string, string]>;
  /** "*A* = te mostro o texto pronto" sem a letra: "te mostro o texto pronto" (null = sem cartão). */
  faco?: string | null;
  /** a linha curta, para a lista e o *detalhe*. */
  curto?: string;
  /** o nome com o essencial (até ~50 caracteres): o "também" da *lista*. */
  rotulo?: string;
}

/** Uma linha do histórico da mesma referência (30 dias, sem hoje). */
export interface PassagemAnterior {
  dia: string;
  posicao: "manha" | "lista";
  acao: string | null;
  acao_em: string | null;
  adiado_ate: string | null;
}

export function rotuloDaAcao(acao: string | null, adiadoAte: string | null, hoje: string): string | null {
  switch (acao) {
    case "feito": return "feito";
    case "nao": return "você disse não";
    case "tirado": return "tirado";
    case "adiado": return adiadoAte ? `adiado até ${quandoEmPalavras(adiadoAte, hoje)}` : "adiado";
    default: return null;
  }
}

export const TEXTO_SEM_RESUMO =
  "O resumo novo de hoje não está guardado (ele é montado às 07:30). Me pergunte o que precisar que eu procuro.";

export function textoNaoAchei(letra: string): string {
  return `Não achei o item ${letra} de hoje. *lista* mostra os de hoje.`;
}

function linhaDoItem(i: ItemGravado, hoje: string, doMesmoAssunto: ItemGravado[] = []): string {
  const r = rotuloDaAcao(i.acao, i.adiado_ate, hoje);
  const curto = i.detalhe?.curto || i.titulo;
  // o que veio junto (o mesmo cliente): a OS-00104 do Flávio não pode sumir atrás da conversa dele
  const [primeiro, ...resto] = doMesmoAssunto;
  const tambem = primeiro
    ? ` · também: ${umaLinha(primeiro.detalhe?.rotulo || primeiro.nome, 60)}${resto.length ? ` e mais ${resto.length}` : ""}`
    : "";
  return `${i.letra}. ${curto}${r ? ` (${r})` : ""}${tambem}`;
}

/**
 * *lista* e *lista dinheiro/clientes/obras/contatos*. Sem filtro, os contatos viram uma linha (são muitos e
 * quase nunca pedem o dono); com o filtro "contatos", vêm um a um. Fecha com a situação dos de manhã.
 */
export function textoDaLista(
  itens: ItemGravado[],
  filtro: Secao | null,
  hoje: string,
  extra: { semLetra?: number } = {},
): string {
  const principais = itens.filter((i) => i.principal).sort((a, b) => a.ordem - b.ordem);
  // os outros itens da mesma letra (o pacote já diz quantos são na própria linha)
  const juntos = (i: ItemGravado) => {
    const daLetra = itens.filter((x) => x.letra === i.letra);
    return ehPacote(daLetra) ? [] : daLetra.filter((x) => !x.principal);
  };
  const lista = principais.filter((i) => i.posicao === "lista");
  const manha = principais.filter((i) => i.posicao === "manha");
  const linhas: string[] = [];
  const mostrados: ItemGravado[] = [];
  const secoes = filtro ? [filtro] : SECOES.filter((s) => s !== "contatos");
  for (const s of secoes) {
    const daSecao = lista.filter((i) => i.secao === s);
    if (!daSecao.length) continue;
    if (!filtro) linhas.push(TITULO_DA_SECAO[s]); // com filtro, o cabeçalho já diz a seção
    for (const i of daSecao) {
      linhas.push(linhaDoItem(i, hoje, juntos(i)));
      mostrados.push(i);
    }
  }
  if (!filtro) {
    const contatos = lista.filter((i) => i.secao === "contatos");
    if (contatos.length) {
      const forn = contatos.filter((i) => i.tipo === "fornecedor").length;
      const outros = contatos.length - forn;
      // o contato sem cadastro que parece pedir preço/orçamento (um possível cliente novo) aparece pelo nome
      const pedem = contatos.filter((i) => i.tipo === "contato_pedindo_preco");
      const quem = pedem.length
        ? ` (${pedem.slice(0, 2).map((i) => `${i.letra}. ${umaLinha(i.nome, 24)}`).join(", ")} ${pedem.length === 1 ? "parece pedir" : "parecem pedir"} preço ou orçamento)`
        : "";
      const partes = [outros ? `${outros} sem cadastro${quem}` : "", forn ? `${forn} fornecedor${forn > 1 ? "es" : ""}` : ""]
        .filter(Boolean).join(" e ");
      linhas.push(`Contatos esperando resposta: ${partes}. *lista contatos*`);
    }
    if ((extra.semLetra ?? 0) > 0) linhas.push(`…e mais ${extra.semLetra} sem letra (*tudo* mostra o resumo completo).`);
  }
  if (!linhas.length) {
    linhas.push(filtro ? `Nada guardado em ${TITULO_DA_SECAO[filtro].toLowerCase()} hoje.` : "Nada guardado hoje.");
  }
  const cabecalho = filtro ? `Guardado hoje cedo — ${TITULO_DA_SECAO[filtro].toLowerCase()}:` : "Guardado hoje cedo:";
  const fim: string[] = [];
  if (!filtro && manha.length) {
    fim.push(`De manhã: ${manha.map((i) => `${i.letra} ${rotuloDaAcao(i.acao, i.adiado_ate, hoje) ?? "sem resposta sua"}`).join(" · ")}`);
  }
  const exemplo = mostrados[0]?.letra ?? manha[0]?.letra ?? "D";
  fim.push(`Responda a letra, *${exemplo} feito*, *${exemplo} amanhã* ou *${exemplo} não*. *tudo* mostra o resumo completo antigo.`);
  return [cabecalho, ...linhas, ...fim].join("\n");
}

/**
 * A letra é o pacote dos orçamentos montados e não enviados (2+ no mesmo item, secretario-selecao.ts)? Só
 * esse tipo divide a letra com outro do mesmo tipo: todos eles são um assunto só.
 */
export function ehPacote(itensDaLetra: ItemGravado[]): boolean {
  return itensDaLetra.length > 1 && itensDaLetra.every((i) => i.tipo === "orcamento_nao_enviado");
}

/** O valor de um fato gravado ("Valor" → "R$ 120.020,00"). */
function fato(i: ItemGravado, rotulo: string): string | null {
  return i.detalhe?.fatos?.find(([r]) => r === rotulo)?.[1] ?? null;
}

/**
 * A letra sozinha (e o *detalhe*) do pacote: cada orçamento numa linha, e como pedir o PDF de um deles (o
 * atalho do PDF manda para o dono, nunca ao cliente). Sem modelo e sem nada enviado.
 */
export function textoDoPacote(itensDaLetra: ItemGravado[]): string {
  const ordenados = [...itensDaLetra].sort((a, b) => Number(b.principal) - Number(a.principal) || a.ordem - b.ordem);
  const l = ordenados[0].letra;
  const linhas = [`${l}. ${ordenados.length} orçamentos montados e ainda não enviados:`];
  for (const i of ordenados) {
    const numero = fato(i, "Orçamento") ?? i.nome.split(" ")[0];
    const quem = [fato(i, "Cliente"), fato(i, "Barco")].filter(Boolean).join(", ");
    const montado = fato(i, "Montado em");
    linhas.push(`• ${numero}${quem ? ` (${quem})` : ""}, ${fato(i, "Valor") ?? ""}${montado ? `, montado em ${montado.slice(0, 5)}` : ""}`);
  }
  const exemplo = (fato(ordenados[0], "Orçamento") ?? "").replace(/\D/g, "").replace(/^0+/, "");
  linhas.push(`Para conferir um deles, peça o PDF${exemplo ? ` (ex.: *pdf ${exemplo}*)` : ""}: ele vem para você, não para o cliente.`);
  linhas.push(`*${l} feito* = já enviei · *${l} espera* = até segunda`);
  return linhas.join("\n");
}

/** *detalhe X*: os fatos, quantas manhãs nos últimos 30 dias, a última resposta e a recomendação. */
export function textoDoDetalhe(itensDaLetra: ItemGravado[], anteriores: PassagemAnterior[], hoje: string): string {
  const [p, ...outros] = [...itensDaLetra].sort((a, b) => Number(b.principal) - Number(a.principal) || a.ordem - b.ordem);
  const pacote = ehPacote(itensDaLetra);
  const linhas: string[] = pacote ? textoDoPacote(itensDaLetra).split("\n").slice(0, -2) : [`${p.letra}. ${p.nome}`];
  if (!pacote) {
    for (const [rotulo, valor] of p.detalhe?.fatos ?? []) linhas.push(`${rotulo}: ${valor}`);
    for (const o of outros) linhas.push(`Também: ${o.detalhe?.curto || o.titulo}`);
  }
  const manhas = anteriores.filter((a) => a.posicao === "manha").sort((a, b) => a.dia.localeCompare(b.dia));
  const comAcao = anteriores.filter((a) => a.acao && a.acao !== "ignorado")
    .sort((a, b) => String(a.acao_em ?? a.dia).localeCompare(String(b.acao_em ?? b.dia)));
  if (manhas.length) {
    linhas.push(`De manhã antes: ${manhas.length} ${manhas.length === 1 ? "vez" : "vezes"} em 30 dias (última em ${ddmm(manhas[manhas.length - 1].dia)}).`);
  } else {
    linhas.push("É a primeira vez de manhã (nos últimos 30 dias).");
  }
  const ultima = comAcao[comAcao.length - 1];
  if (ultima) linhas.push(`Sua última resposta: ${rotuloDaAcao(ultima.acao, ultima.adiado_ate, hoje)} em ${ddmm(ultima.dia)}.`);
  const agora = rotuloDaAcao(p.acao, p.adiado_ate, hoje);
  if (agora) linhas.push(`Hoje: ${agora}.`);
  if (p.recomendacao) linhas.push(p.recomendacao);
  if (p.pedido && p.detalhe?.faco) linhas.push(`*${p.letra}* = ${p.detalhe.faco}`);
  return linhas.join("\n");
}

/** *por que o X?* */
export function textoDoPorque(item: ItemGravado): string {
  return `${item.letra}. ${item.motivo}`;
}

/** A confirmação de uma ação (resposta da RPC resumo_item_acao). */
export function textoDaAcao(
  r: { resultado?: string; acao?: string; ate?: string | null; item?: { nome?: string; tipo?: string } } | null,
  letra: string,
  hoje: string,
): string {
  if (!r || r.resultado === "nao_achei") return textoNaoAchei(letra);
  if (r.resultado !== "feito") return "Não consegui anotar agora. Tente de novo em instantes.";
  const quem = r.item?.nome ? ` (${r.item.nome})` : "";
  switch (r.acao) {
    case "feito":
      return ficaTodoDia(String(r.item?.tipo ?? ""))
        ? `Anotei: ${letra} feito${quem}. Como é cobrança grande, volta amanhã cedo se ainda não tiver entrado; *${letra} segunda* adia.`
        : `Anotei: ${letra} feito${quem}. Só volta de manhã se aparecer fato novo.`;
    case "nao":
      return `Anotei: ${letra} não${quem}. Fica na *lista* e só volta de manhã com fato novo. *volta ${letra}* desfaz.`;
    case "tirado":
      return `Tirei ${letra}${quem}. Só volta com fato novo (pagamento, mensagem nova, outro valor ou data). *volta ${letra}* desfaz.`;
    case "adiado":
      return `Anotei: ${letra}${quem} fica para ${r.ate ? quandoEmPalavras(r.ate, hoje) : "depois"}. *volta ${letra}* desfaz.`;
    default:
      return "Anotei.";
  }
}

/** A confirmação do *volta X* (resposta da RPC resumo_item_voltar). */
export function textoDaVolta(
  r: { resultado?: string; desfeita?: string | null; item?: { letra?: string; nome?: string; dia?: string } } | null,
  alvo: { letra: string | null; nome: string | null },
  hoje: string,
): string {
  if (!r) return "Não consegui desfazer agora. Tente de novo em instantes.";
  if (r.resultado === "nao_achei") {
    return alvo.letra ? textoNaoAchei(alvo.letra) : `Não achei nada tirado, adiado ou marcado com "${alvo.nome}" nos últimos 30 dias.`;
  }
  if (r.resultado === "sem_acao") return `O item ${alvo.letra} não tinha nada anotado.`;
  if (r.resultado !== "voltou") return "Não consegui desfazer agora. Tente de novo em instantes.";
  const nome = r.item?.nome ?? alvo.nome ?? "";
  const desfeito = rotuloDaAcao(r.desfeita ?? null, null, hoje);
  return `Desfeito${desfeito ? ` (${desfeito})` : ""}: ${nome} volta a poder subir de manhã.`;
}
