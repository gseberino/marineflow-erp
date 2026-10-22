// As respostas dos comandos do dono sobre a manhã nova — texto puro, sem banco e sem IA.
// Números, datas e nomes vêm do que a montagem gravou às 07:30 (resumo_itens / resumo_manha).

import { ddmm, quandoEmPalavras, umaLinha } from "./base.ts";
import { ficaTodoDia, SECOES, type Secao, TITULO_DA_SECAO } from "./tipos.ts";
import { grupoDoTipo, TERMO_GERAL, TIPOS_DE_UNIDADE } from "../unidade.ts";

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
  /** a impressão digital do fato (cobrança: "saldo|vencimento|fase") — a revisão do mês lê o vencimento daqui */
  fato?: string;
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
  /**
   * (22/10/2026) a unidade numa linha, com o tipo ("Motorhome Overland Vegini"). Opcional: os itens gravados
   * antes não a têm, e unidadeDoItem acha a unidade pelo fato.
   */
  unidade?: string | null;
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

/** Os rótulos que o fato da unidade já teve: "Barco" até 21/10/2026; o termo geral desde então (sem tipo). */
const ROTULOS_ANTIGOS_DA_UNIDADE = new Set(["Barco", TERMO_GERAL]);

/** O rótulo é um tipo de unidade ("Motorhome", "Lancha", "Equipamento", o "Embarcação" de "Outra embarcação")? */
function ehTipoDeUnidade(rotulo: string): boolean {
  const r = rotulo.trim().toLowerCase();
  return grupoDoTipo(r) !== "outro" || TIPOS_DE_UNIDADE.some((g) => g.tipos.some((t) => t.valor.toLowerCase() === r));
}

/**
 * A unidade de um item gravado, numa linha: "Motorhome Overland Vegini" (ou só o nome, nos itens gravados antes de
 * 22/10/2026). Desde então o fato da unidade tem o TIPO como rótulo ("Motorhome: Overland Vegini"), e procurar pelo
 * rótulo não basta. Nesta ordem: o campo próprio do detalhe; o fato com o rótulo "Barco" (até 21/10) ou o termo
 * geral (sem tipo); o fato cujo rótulo é um tipo de unidade. null = sem unidade.
 */
export function unidadeDoItem(i: ItemGravado): string | null {
  const gravada = i.detalhe?.unidade;
  if (typeof gravada === "string" && gravada.trim()) return gravada.trim();
  const fatos = i.detalhe?.fatos ?? [];
  const antigo = fatos.find(([r]) => ROTULOS_ANTIGOS_DA_UNIDADE.has(r));
  if (antigo) return antigo[1] || null;
  const peloTipo = fatos.find(([r]) => ehTipoDeUnidade(r));
  return peloTipo?.[1] ? `${peloTipo[0]} ${peloTipo[1]}` : null;
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
    // A unidade com o tipo ("Motorhome Overland Vegini"); os itens gravados antes trazem só o nome.
    const quem = [fato(i, "Cliente"), unidadeDoItem(i)].filter(Boolean).join(", ");
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

// ─── Passo 3 (15/10/2026): as respostas da tarde ───────────────────────────────────────────────

function emLista(xs: string[]): string {
  return xs.length <= 1 ? xs.join("") : `${xs.slice(0, -1).join(", ")} e ${xs[xs.length - 1]}`;
}

/** A confirmação do lote da revisão (resposta da RPC resumo_itens_acoes). */
export function textoDoLote(
  r: {
    resultado?: string;
    erro?: string;
    letra?: string;
    letras?: string[];
    itens?: Array<{ letra: string; acao: string; ate?: string | null; resposta?: string | null }>;
  } | null,
  hoje: string,
): string {
  if (!r) return "Não consegui anotar agora. Tente de novo em instantes.";
  if (r.resultado === "nao_achei") {
    const ls = r.letras ?? [];
    return `Não achei ${emLista(ls)} de hoje; nada foi anotado. *lista* mostra os de hoje.`;
  }
  if (r.resultado === "invalido") {
    return r.erro === "letra_repetida"
      ? `A letra ${r.letra ?? ""} veio duas vezes; nada foi anotado. Mande uma resposta por letra.`
      : "Não entendi uma das respostas; nada foi anotado. Exemplo: *C semana, B tira, G 15 dias*.";
  }
  if (r.resultado !== "feito" || !r.itens?.length) return "Não consegui anotar agora. Tente de novo em instantes.";
  const partes = r.itens.map((i) => {
    if (i.acao === "feito") return `${i.letra} feito`;
    if (i.acao === "nao") return `${i.letra} não`;
    if (i.acao === "tirado") return `${i.letra} tirado`;
    if (i.resposta === "semana") return `${i.letra} fica com você esta semana`;
    if (i.resposta === "15dias") return `${i.letra} volta em 15 dias (${ddmm(i.ate)})`;
    return `${i.letra} até ${i.ate ? quandoEmPalavras(i.ate, hoje) : "depois"}`;
  });
  const temSemana = r.itens.some((i) => i.resposta === "semana");
  return `Anotei: ${partes.join(" · ")}.` +
    (temSemana ? " O que ficou com você não volta de manhã esta semana; se ainda estiver aberto, entra na próxima revisão." : "") +
    ` *volta ${r.itens[0].letra}* desfaz.`;
}

/** A resposta da pergunta da sexta (RPC resumo_semana_responder). */
export function textoDaRespostaDaSemana(r: { resultado?: string } | null, resposta: "ajudou" | "pouco" | "atrapalhou"): string {
  if (!r || (r.resultado !== "gravado" && r.resultado !== "trocado")) return "Não consegui anotar agora. Tente de novo em instantes.";
  const frase = resposta === "ajudou" ? "a semana ajudou" : resposta === "pouco" ? "ajudou pouco" : "atrapalhou";
  const troca = r.resultado === "trocado" ? " (troquei a resposta anterior)" : "";
  return resposta === "ajudou"
    ? `Anotei: ${frase}${troca}.`
    : `Anotei: ${frase}${troca}. Se quiser, me diga numa frase o que mais atrapalhou que eu ajusto.`;
}

/** O vencimento gravado no fato da cobrança ("saldo|aaaa-mm-dd|fase"), ou null. */
export function vencimentoDoFato(fato: string | null | undefined): string | null {
  const v = String(fato ?? "").split("|")[1] ?? "";
  return /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
}

function fatoDe(i: ItemGravado, rotulo: string): string | null {
  return i.detalhe?.fatos?.find(([r]) => r === rotulo)?.[1] ?? null;
}

/**
 * O turno do assistente para "F cobrar / F negociar / F baixa" (a revisão do mês). Nada sai nem é gravado
 * sem o sim: o pedido termina sempre pedindo o cartão. `antigas` = as cobranças de 30+ dias da letra.
 */
export function pedidoDaCobrancaAntiga(acao: "cobrar" | "negociar" | "baixa", antigas: ItemGravado[]): string {
  if (acao === "cobrar" && antigas.length === 1 && antigas[0].pedido) return antigas[0].pedido;
  const cliente = umaLinha(fatoDe(antigas[0], "Cliente") ?? antigas[0].nome, 60);
  const lista = antigas.map((i) => {
    const desc = fatoDe(i, "Cobrança");
    const saldo = fatoDe(i, "Saldo");
    const venc = fatoDe(i, "Venceu em")?.replace(/\s*\(.*\)$/, "");
    return `${desc ? `"${umaLinha(desc, 60)}"` : "a cobrança"}${saldo || venc ? ` (${[saldo ? `saldo de ${saldo}` : "", venc ? `venceu em ${venc}` : ""].filter(Boolean).join(", ")})` : ""}`;
  }).join("; ");
  if (acao === "cobrar") {
    return `Prepare um lembrete de pagamento para o cliente ${cliente} sobre estas cobranças vencidas: ${lista}. Mostre o texto pronto e peça o meu sim antes de enviar.`;
  }
  if (acao === "negociar") {
    return `Prepare uma proposta de acordo para o cliente ${cliente} sobre ${lista}: ofereça parcelar o saldo ou um desconto para pagar à vista, em tom cordial. Mostre o texto pronto e peça o meu sim antes de enviar.`;
  }
  return `Quero dar baixa em ${lista}, do cliente ${cliente}: não vou mais cobrar. Cancele o lançamento como perda, com o motivo "dado como perda na revisão do mês". Mostre o que muda e peça o meu sim antes de gravar.`;
}
