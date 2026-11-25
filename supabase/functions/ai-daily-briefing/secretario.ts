// A manhã nova (secretário, Passo 2, 15/10/2026): junta coleta → candidatos → seleção → texto e grava o
// dia em resumo_manha/resumo_itens. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md
//
// Só é chamada com resumo_formato = 'sombra' ou 'novo'. Quem chama (index.ts) cuida de: com 'novo',
// gravar ANTES de enviar e, se a gravação falhar, mandar o resumo de sempre (as letras do texto têm de
// existir no banco quando o dono responder); com 'sombra', enviar o de sempre e gravar depois.

import { horaBR } from "../_shared/pdf/datas.ts";
import { paraBusca } from "../_shared/secretario/base.ts";
import { feriadoDoDia, type TipoDoDia, tipoDoDia } from "../_shared/secretario/feriados.ts";
import { candidatosDoDia, type ColetaDoSecretario } from "./secretario-candidatos.ts";
import { coletar, type DoResumoDeHoje } from "./secretario-coleta.ts";
import {
  comLetra, type GrupoDoDia, type OpcoesDoHistorico, OPCOES_PADRAO, type PassagemDoHistorico, selecionar, type Selecao, textosDoPacote,
} from "./secretario-selecao.ts";
import {
  type AvisoGuardado, lerGuardado, marcarNaMensagem, planoDoGuardado, type PlanoDoGuardado, quaisSeResolveram,
} from "../_shared/uma-voz/guardado.ts";
import type { ModoDoPortao, RegrasDaVozUnica } from "../_shared/uma-voz/portao.ts";
import { lerPortao, type PortaoDaRodada } from "../_shared/uma-voz/registrar.ts";
import { type DadosDeHoje, type DadosDoEscritorio, linhaDoItem, type NaRua, textoDaManha, textoDoEscritorio } from "./secretario-texto.ts";
import { type ExtraDaManha, lerExtra, lerRetorno, linhasDaManha, type RetornoDaManha } from "./retorno.ts";
import { impressoraNoAr } from "../_shared/impressao/fila.ts";
import { osDaAgendaDoDia } from "../_shared/impressao/agenda.ts";
import { comPagamentos, lerPagamentosDaManha, type PagamentosDaSemana, pagamentosDaManha } from "../_shared/pagamentos/semana.ts";
import { comRecebidosPeloBoleto, lerRecebidosPeloBoleto, linhaDosRecebidosPeloBoleto, type RecebidoPeloBoleto } from "./secretario-boleto.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Um item para a RPC resumo_registrar (as colunas de resumo_itens). */
export interface ItemParaGravar {
  letra: string;
  principal: boolean;
  posicao: "manha" | "lista";
  ordem: number;
  familia: string;
  tipo: string;
  secao: string;
  referencia: string;
  assunto: string;
  nome: string;
  nome_busca: string;
  fato: string;
  valor: number;
  titulo: string;
  recomendacao: string | null;
  motivo: string;
  pedido: string | null;
  // unidade (22/10/2026): "Motorhome Overland Vegini" — quem lê o item acha a unidade por aqui, não pelo
  // rótulo do fato (que agora é o tipo, texto livre). Itens gravados antes não têm: respostas.ts tem reserva.
  detalhe: { fatos: Array<[string, string]>; faco: string | null; curto: string; rotulo: string; unidade?: string | null };
}

export interface ManhaNova {
  texto: string;
  tipoDoDia: TipoDoDia;
  itens: ItemParaGravar[];
  escritorio: string;
  itensManha: number;
  itensLista: number;
  semLetra: number;
  /**
   * (16/10/2026) O que o portão guardou e o texto mostrou (só na sombra: a manhã não sai). Quem grava a manhã marca
   * depois (marcarNaMensagem: os resolvidos somem, os mostrados ficam "incluido" — não "entregue"). null = sem guardado.
   */
  guardado?: { modo: ModoDoPortao; plano: PlanoDoGuardado } | null;
  /**
   * (19/11/2026, agenda, Opção A) As perguntas cliente_aprovar que o texto mostrou (o bloco "Mensagens ao cliente esperando o
   * seu sim"). Quem enfileira a manhã ENVIADA as guarda com o id da linha da fila do dono (guardarAprovacoesDaManha): contam
   * como mostradas quando a fila disser 'sent'. null/ausente = sem o bloco.
   */
  aprovacoes?: { perguntaIds: string[] } | null;
}

/**
 * (19/11/2026, agenda, Opção A — decisão do dono: "o pedido de aprovação entra no resumo da manhã, com prazo") O bloco pronto
 * do banco (agenda_aprovacoes_da_manha: as mensagens ao cliente esperando o *manda cliente*, a que vence primeiro em cima, o
 * prazo de valida_ate) e as perguntas que ele escreveu.
 */
export interface AprovacoesDaManha {
  texto: string;
  perguntaIds: string[];
}

/** A resposta de agenda_aprovacoes_da_manha → o bloco; sem bloco (nada esperando, modo_cliente fora de ligado) = null. Forma errada LANÇA. */
export function aprovacoesDaResposta(data: unknown): AprovacoesDaManha | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("agenda_aprovacoes_da_manha respondeu fora da forma");
  const d = data as { texto?: unknown; linhas?: unknown };
  if (d.texto === null || d.texto === undefined) return null;
  if (typeof d.texto !== "string" || !Array.isArray(d.linhas)) throw new Error("agenda_aprovacoes_da_manha respondeu fora da forma");
  const perguntaIds = d.linhas.map((l) => {
    const id = (l as { pergunta_id?: unknown })?.pergunta_id;
    if (typeof id !== "string" || !id) throw new Error("agenda_aprovacoes_da_manha respondeu uma linha sem a pergunta");
    return id;
  });
  const texto = d.texto.trim();
  return texto && perguntaIds.length ? { texto, perguntaIds } : null;
}

/** O bloco das aprovações ao cliente no fim da manhã (antes da sugestão de imprimir). Só em dia útil; sem bloco = o texto de antes, byte a byte. */
export function comAprovacoesAoCliente(texto: string, tipo: ReturnType<typeof tipoDoDia>, a: AprovacoesDaManha | null | undefined): string {
  if (tipo !== "util" || !a?.texto) return texto;
  return `${texto}\n\n${a.texto}`;
}

/** Lê o bloco das aprovações. Nunca lança: erro = null (a manhã sai sem o bloco; a pergunta segue no fechamento e em *agenda clientes*). */
export async function lerAprovacoesDaManha(admin: Admin, hoje: string, agora: Date): Promise<AprovacoesDaManha | null> {
  try {
    const { data, error } = await admin.rpc("agenda_aprovacoes_da_manha", { p_hoje: hoje, p_agora: agora.toISOString() });
    if (error) throw error;
    return aprovacoesDaResposta(data);
  } catch (e) {
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", secretario: "aprovacoes_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
    return null;
  }
}

/**
 * Depois de enfileirar a manhã ENVIADA (1ª gravação do dia): as perguntas do bloco vão a agenda_fechamento_guardar (via 'manha')
 * com o id da linha da fila do dono — o mesmo caminho do fechamento: contam (mostrada_vezes, mostrada_em, mostrada_via='manha')
 * só quando a fila disser 'sent' (agora, se já mandou; senão o motor de 15 min confere). Sem o id da fila nada é guardado.
 * Nunca lança.
 */
export async function guardarAprovacoesDaManha(admin: Admin, p: {
  hoje: string;
  perguntaIds: string[];
  filaId: string | null;
  agora: Date;
}): Promise<{ estado: string; perguntas: number } | "sem_fila" | "erro" | null> {
  if (!p.perguntaIds.length) return null;
  if (!p.filaId) return "sem_fila";
  try {
    const { data, error } = await admin.rpc("agenda_fechamento_guardar", {
      p_hoje: p.hoje,
      p_linhas: p.perguntaIds.map((id) => ({ pergunta_id: id, acao_ids: [] })),
      p_fila: p.filaId,
      p_via: "manha",
      p_agora: p.agora.toISOString(),
    });
    if (error) throw error;
    const r = (data ?? {}) as { ok?: unknown; estado?: unknown; motivo?: unknown; perguntas?: unknown };
    if (r.ok !== true) return r.motivo === "sem_fila" ? "sem_fila" : "erro";
    return { estado: String(r.estado ?? "esperando"), perguntas: Number(r.perguntas ?? 0) };
  } catch (e) {
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", secretario: "aprovacoes_guarda_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
    return "erro";
  }
}

/** (16/10/2026) O guardado lido para a manhã (avisos_para_a_mensagem) e o que deixou de ser verdade (D8). */
export interface GuardadoLido {
  modo: ModoDoPortao;
  avisos: AvisoGuardado[];
  resolvidos: Set<string>;
  regras: Pick<RegrasDaVozUnica, "guardado_resolvido">;
}

/** Os telefones que já são item da manhã com letra (o aviso do mesmo contato vai junto, sem linha própria). */
export function fonesDaManha(sel: Selecao): Set<string> {
  const fones = new Set<string>();
  for (const g of sel.manha) {
    for (const m of g.membros) {
      const f = /^fone:(\d+)$/.exec(m.c.referencia)?.[1];
      if (f) fones.add(f);
    }
  }
  return fones;
}

function corta(s: string | null, max: number): string | null {
  if (s === null) return null;
  return s.length <= max ? s : `${s.slice(0, max - 1)}…`;
}

/** Os itens a gravar: todo grupo com letra; cada membro uma linha (o primeiro é o principal). */
export function itensParaGravar(sel: Selecao): ItemParaGravar[] {
  const itens: ItemParaGravar[] = [];
  const grupos: GrupoDoDia[] = [...sel.manha, ...sel.lista].filter((g) => g.letra);
  grupos.forEach((g, ordem) => {
    // o pacote dos orçamentos não enviados: o principal leva o nome e as linhas do pacote (a *lista*, o
    // "A feito (3 orçamentos…)"); cada membro guarda o seu fato e a sua referência (a repetição é por item)
    const pacote = g.pacote ? textosDoPacote(g.membros) : null;
    g.membros.forEach((m, i) => {
      const principal = i === 0;
      const c = m.c;
      const motivo = principal ? g.motivo
        : comLetra(m.estado.lugar === "manha" ? c.motivo : (m.estado.motivo ?? "Do mesmo assunto."), g.letra);
      const nome = principal && pacote ? pacote.nome : c.nome;
      itens.push({
        letra: g.letra!,
        principal,
        posicao: g.posicao,
        ordem,
        familia: c.familia,
        tipo: c.tipo,
        secao: c.secao,
        referencia: c.referencia,
        assunto: c.assunto,
        nome: corta(nome, 120)!,
        nome_busca: paraBusca(nome),
        fato: corta(c.fato, 300)!,
        valor: Math.round(c.valor * 100) / 100,
        titulo: corta(principal && g.posicao === "manha" ? linhaDoItem(g) : principal && pacote ? pacote.titulo : c.titulo, 600)!,
        recomendacao: corta(principal && pacote ? "Recomendo revisar e enviar, começando pelo maior." : c.recomendacao, 300),
        motivo: corta(motivo, 600)!,
        pedido: corta(c.pedido, 1000),
        detalhe: {
          fatos: c.fatos,
          faco: principal && pacote ? `te mostro os ${g.membros.length}` : c.faco,
          curto: principal && pacote ? pacote.curto : c.curto,
          // o nome curto (o "também" da *lista*)
          rotulo: principal && pacote ? pacote.rotulo : c.rotulo,
          ...(c.unidade ? { unidade: c.unidade } : {}),
        },
      });
    });
  });
  return itens;
}

/**
 * (17/11/2026) A sugestão de imprimir as vias do dia (decisão do dono: nada automático, só a sugestão na hora certa).
 * Uma linha no fim, só em dia útil e só com OS na agenda de hoje; o comando sugerido é lido sem modelo (atalho-pdf.ts).
 */
export function comSugestaoDeImpressao(texto: string, tipo: ReturnType<typeof tipoDoDia>, vias: number): string {
  if (tipo !== "util" || !(vias > 0)) return texto;
  const quantas = vias === 1 ? "a via de hoje" : `as ${vias} vias de hoje`;
  return `${texto}\n🖨️ Quer ${quantas} no papel? Responda: *imprime as vias de hoje*`;
}

/**
 * Quantas OS a agenda de hoje tem, se a impressora do escritório está no ar e a sugestão não foi desligada
 * (app_settings.impressao_sugestao_manha = 'off'). Nunca lança: qualquer erro = 0 (a manhã sai como antes).
 */
export async function viasParaImprimirHoje(admin: Admin, hoje: string): Promise<number> {
  try {
    const { data: chave } = await admin.from("app_settings").select("value").eq("key", "impressao_sugestao_manha").maybeSingle();
    if (String(chave?.value ?? "").trim().toLowerCase() === "off") return 0;
    if (!(await impressoraNoAr(admin)).ok) return 0;
    return (await osDaAgendaDoDia(admin, hoje)).length;
  } catch {
    return 0;
  }
}

/** A parte pura: dos dados lidos ao texto e aos itens. */
export function montarDosDados(p: {
  hoje: string;
  agora: Date;
  coleta: ColetaDoSecretario;
  historico: PassagemDoHistorico[];
  naRua: NaRua;
  deHoje: DadosDeHoje;
  escritorio: DadosDoEscritorio;
  /** (16/10/2026) F7 e afins (voz_unica_regras); ausente = os padrões */
  opcoes?: OpcoesDoHistorico;
  /** (16/10/2026) o guardado para a manhã (só na sombra); ausente = o texto de antes */
  guardado?: GuardadoLido | null;
  /** (01/11/2026, retorno F1, P14) retorno_resumo_do_dia da manhã (retorno.ts); ausente ou null = o texto de antes */
  retorno?: RetornoDaManha | null;
  /** (F2, P12) retorno_resumo_extra ('manha'); ausente ou null = o texto de antes */
  retornoExtra?: ExtraDaManha | null;
  /**
   * (17/11/2026, impressão) Quantas OS a agenda de hoje tem com a impressora do escritório no ar: > 0 = a manhã sugere
   * "imprime as vias de hoje" numa linha no fim. Ausente ou 0 = o texto de antes, byte a byte.
   */
  viasParaImprimir?: number;
  /**
   * (19/11/2026, agenda, Opção A) O bloco das mensagens ao cliente esperando o *manda cliente* (lerAprovacoesDaManha). Entra
   * depois do texto da manhã e antes da sugestão de imprimir, só em dia útil. Ausente ou null = o texto de antes, byte a byte.
   */
  aprovacoes?: AprovacoesDaManha | null;
  /**
   * (24/11/2026, pagamentos da semana) A fila do que pagar (lerPagamentosDaManha): no 1º dia útil da semana o bloco
   * inteiro, nos outros dias úteis a linha das vencidas. Entra depois das aprovações e antes da sugestão de imprimir.
   * Ausente, null ou sem conta = o texto de antes, byte a byte.
   */
  pagamentos?: PagamentosDaSemana | null;
  /**
   * (24/11/2026, baixa do recebimento pelo boleto) As contas a receber que o sistema baixou sozinho desde a última manhã
   * (lerRecebidosPeloBoleto): uma linha depois dos pagamentos e antes da sugestão de imprimir, só em dia útil — o dono
   * recebe esta manhã, e sem a linha a conta sumia do "Na rua" sem explicação. Ausente, null ou vazio = o texto de
   * antes, byte a byte.
   */
  recebidosPeloBoleto?: RecebidoPeloBoleto[] | null;
}): ManhaNova {
  const tipo = tipoDoDia(p.hoje);
  const opcoes = p.opcoes ?? OPCOES_PADRAO;
  // domingo e feriado: nada sobe; os itens do dia ficam todos na lista (a *lista* funciona)
  const selecao = tipo === "util"
    ? selecionar(candidatosDoDia(p.coleta, p.agora, p.hoje), p.historico, p.hoje, undefined, undefined, opcoes)
    : selecionar(candidatosDoDia(p.coleta, p.agora, p.hoje), p.historico, p.hoje, 0,
      `Ficou na lista: ${tipo === "domingo" ? "domingo" : "feriado"}, nada sobe de manhã.`, opcoes);
  const plano = p.guardado && p.guardado.avisos.length
    ? planoDoGuardado({
      avisos: p.guardado.avisos, mensagem: "manha", hoje: p.hoje, resolvidosAgora: p.guardado.resolvidos,
      regras: p.guardado.regras, cobertos: fonesDaManha(selecao),
    })
    : null;
  // (P14) "Clientes esperando" e "Para conferir": os sem prazo que já têm letra na manhã não repetem
  const retorno = p.retorno ? linhasDaManha(p.retorno, fonesDaManha(selecao), p.agora, p.retornoExtra ?? null) : null;
  const aprovacoes = tipo === "util" && p.aprovacoes?.texto ? p.aprovacoes : null;
  const texto = comSugestaoDeImpressao(comRecebidosPeloBoleto(comPagamentos(comAprovacoesAoCliente(textoDaManha({
    hoje: p.hoje, tipoDoDia: tipo, feriado: feriadoDoDia(p.hoje), selecao, naRua: p.naRua, deHoje: p.deHoje, guardado: plano, retorno,
  }), tipo, aprovacoes), pagamentosDaManha(p.pagamentos, p.hoje)), tipo, linhaDosRecebidosPeloBoleto(p.recebidosPeloBoleto, p.hoje)),
    tipo, p.viasParaImprimir ?? 0);
  return {
    texto,
    tipoDoDia: tipo,
    itens: itensParaGravar(selecao),
    escritorio: textoDoEscritorio(p.escritorio, horaBR(p.agora)),
    itensManha: selecao.manha.length,
    itensLista: selecao.lista.filter((g) => g.letra).length,
    semLetra: selecao.semLetra,
    guardado: plano && p.guardado ? { modo: p.guardado.modo, plano } : null,
    aprovacoes: aprovacoes ? { perguntaIds: aprovacoes.perguntaIds } : null,
  };
}

/**
 * O guardado para a manhã. Nunca lança (erro = null: a manhã sai sem o bloco e o guardado espera a próxima).
 *   · manhã-sombra (o texto novo NÃO sai): o guardado da SOMBRA, só com a voz única em sombra (16/10/2026);
 *   · (20/10/2026, P4.5) manhã nova ENVIADA: o guardado do modo LIGADO — com a voz ligada, as fontes seguraram para ela.
 *     Lido com a chave em 'ligado' OU 'sombra' (voltar atrás é 'sombra': o que ficou guardado enquanto ela estava ligada
 *     ainda sai — nada se perde); com 'desligado' nada é lido (como antes). Sem linha 'ligado' = lista vazia = o texto
 *     de sempre. O guardado da sombra nunca vai na manhã enviada (as fontes já tinham avisado: repetiria).
 */
export async function lerGuardadoDaManha(admin: Admin, p: {
  agora: Date;
  dono: { phone: string };
  modo: "sombra" | "novo";
  portao: PortaoDaRodada;
}): Promise<GuardadoLido | null> {
  const modo = p.modo === "novo"
    ? (p.portao.voz !== "desligado" ? "ligado" : null)
    : p.portao.modo === "sombra" ? "sombra" : null;
  if (!modo) return null;
  const avisos = await lerGuardado(admin, { phone: p.dono.phone, modo, mensagem: "manha", agora: p.agora });
  if (!avisos) return null;
  const resolvidos = avisos.length ? await quaisSeResolveram(admin, avisos) : new Set<string>();
  return { modo, avisos, resolvidos, regras: p.portao.regras };
}

/**
 * Depois de gravar a manhã (só na 1ª gravação do dia): os resolvidos somem e os mostrados ficam "incluido". Na sombra
 * (16/10/2026) sem fila — nunca "entregue", porque nada saiu (migration 20261016120000); (20/10/2026) na manhã enviada,
 * com o id da linha da FILA do dono (entregue só quando ela disser 'sent'; sem o id, nada é marcado e o guardado volta
 * na próxima mensagem). Nunca lança.
 */
export async function marcarGuardadoDaManha(admin: Admin, p: {
  dono: { phone: string };
  manha: ManhaNova;
  novo: boolean;
  filaId?: string | null;
}): Promise<number> {
  const g = p.manha.guardado;
  if (!p.novo || !g) return 0;
  const r = await marcarNaMensagem(admin, {
    phone: p.dono.phone, modo: g.modo, mostrados: g.plano.mostrados, resolvidos: g.plano.resolvidos,
    ...(g.modo === "ligado" ? { filaId: p.filaId ?? null } : {}),
  });
  return r.incluidos;
}

/** Lê o banco e monta. Lança se uma leitura essencial falhar (quem chama volta ao resumo de sempre). */
export async function montarManhaNova(admin: Admin, p: {
  agora: Date;
  hoje: string;
  dono: { id: string; phone: string };
  modo: "sombra" | "novo";
  doResumo: DoResumoDeHoje;
  escritorio: DadosDoEscritorio;
}): Promise<ManhaNova> {
  const lido = await coletar(admin, { agora: p.agora, hoje: p.hoje, dono: p.dono, modo: p.modo, doResumo: p.doResumo });
  // (16/10/2026) as regras do dono (F7) e o guardado da manhã-sombra; lerPortao nunca lança (erro = padrões, sem guardado)
  const portao = await lerPortao(admin);
  const guardado = await lerGuardadoDaManha(admin, { agora: p.agora, dono: p.dono, modo: p.modo, portao });
  // (01/11/2026, retorno F1, P14) quem espera resposta do retorno; lerRetorno nunca lança (erro = null = o texto de antes).
  // Domingo e feriado a manhã é uma linha só (nada a ler)
  const retorno = tipoDoDia(p.hoje) === "util" ? await lerRetorno(admin, "manha", p.agora) : null;
  const retornoExtra = tipoDoDia(p.hoje) === "util" ? await lerExtra(admin, "manha", p.agora) : null;
  // (17/11/2026) a sugestão de imprimir as vias de hoje; viasParaImprimirHoje nunca lança (erro = 0 = sem a linha)
  const viasParaImprimir = tipoDoDia(p.hoje) === "util" ? await viasParaImprimirHoje(admin, p.hoje) : 0;
  // (19/11/2026, agenda, Opção A) as mensagens ao cliente esperando o *manda cliente*; lerAprovacoesDaManha nunca lança (erro = sem o bloco)
  const aprovacoes = tipoDoDia(p.hoje) === "util" ? await lerAprovacoesDaManha(admin, p.hoje, p.agora) : null;
  // (24/11/2026) a fila do que pagar; lerPagamentosDaManha nunca lança (erro ou chave desligada = null = sem o bloco)
  const pagamentos = tipoDoDia(p.hoje) === "util" ? await lerPagamentosDaManha(admin, p.hoje) : null;
  // (24/11/2026) o que foi baixado sozinho pelo boleto desde a última manhã ENTREGUE ao dono (por isso o telefone: a janela
  // vem da fila do WhatsApp, não do calendário); lerRecebidosPeloBoleto nunca lança (erro = null = sem a linha)
  const recebidosPeloBoleto = tipoDoDia(p.hoje) === "util" ? await lerRecebidosPeloBoleto(admin, p.hoje, p.dono.phone) : null;
  return montarDosDados({
    hoje: p.hoje, agora: p.agora, ...lido, escritorio: p.escritorio,
    opcoes: { semanaVoltaComFatoNovo: portao.regras.semana_volta_com_fato_novo }, guardado, retorno, retornoExtra, viasParaImprimir, aprovacoes,
    pagamentos, recebidosPeloBoleto,
  });
}

/**
 * Grava o dia (resumo_registrar). Devolve o texto GRAVADO: num segundo disparo do mesmo dia é o da
 * primeira vez (as letras não mudam). Nunca lança: erro = { ok: false } (só o código no log).
 */
export async function registrarManha(admin: Admin, p: {
  hoje: string;
  dono: { id: string; phone: string };
  modo: "sombra" | "novo";
  manha: ManhaNova;
  textoAntigo: string;
}): Promise<{ ok: boolean; novo: boolean; texto: string | null }> {
  try {
    const { data, error } = await admin.rpc("resumo_registrar", {
      p: {
        dia: p.hoje,
        phone: p.dono.phone,
        app_user_id: p.dono.id,
        modo: p.modo,
        tipo_do_dia: p.manha.tipoDoDia,
        texto_novo: p.manha.texto,
        texto_antigo: p.textoAntigo.slice(0, 20000),
        escritorio: p.manha.escritorio.slice(0, 2000),
        enviado: p.modo === "novo",
        itens_manha: p.manha.itensManha,
        itens_lista: p.manha.itensLista,
        sem_letra: p.manha.semLetra,
        itens: p.manha.itens,
      },
    });
    if (error) throw error;
    const d = (data ?? {}) as { ok?: boolean; novo?: boolean; texto_novo?: string; modo?: string };
    // o dia já gravado em outro modo (a chave mudou no meio do dia) não serve para o envio deste
    if (!d.ok || (d.modo && d.modo !== p.modo)) return { ok: false, novo: false, texto: null };
    return { ok: true, novo: d.novo === true, texto: typeof d.texto_novo === "string" ? d.texto_novo : null };
  } catch (e) {
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", secretario: "registrar_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
    return { ok: false, novo: false, texto: null };
  }
}

/** As propostas da fila por tipo (para o *escritório*), da mesma leitura de index.ts:366-372. */
export function contarPropostas(rows: Array<{ kind: string | null }>): NonNullable<DadosDoEscritorio["propostas"]> {
  const r = { saidas: 0, entradas: 0, transferencias: 0, outras: 0 };
  for (const p of rows ?? []) {
    if (p.kind === "anomaly") continue;
    if (p.kind === "create_payable") r.saidas++;
    else if (p.kind === "create_receivable") r.entradas++;
    else if (p.kind === "internal_transfer") r.transferencias++;
    else r.outras++;
  }
  return r;
}
