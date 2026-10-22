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
  const texto = textoDaManha({
    hoje: p.hoje, tipoDoDia: tipo, feriado: feriadoDoDia(p.hoje), selecao, naRua: p.naRua, deHoje: p.deHoje, guardado: plano,
  });
  return {
    texto,
    tipoDoDia: tipo,
    itens: itensParaGravar(selecao),
    escritorio: textoDoEscritorio(p.escritorio, horaBR(p.agora)),
    itensManha: selecao.manha.length,
    itensLista: selecao.lista.filter((g) => g.letra).length,
    semLetra: selecao.semLetra,
    guardado: plano && p.guardado ? { modo: p.guardado.modo, plano } : null,
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
  return montarDosDados({
    hoje: p.hoje, agora: p.agora, ...lido, escritorio: p.escritorio,
    opcoes: { semanaVoltaComFatoNovo: portao.regras.semana_volta_com_fato_novo }, guardado,
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
