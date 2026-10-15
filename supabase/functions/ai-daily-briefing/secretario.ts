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
import { comLetra, type GrupoDoDia, type PassagemDoHistorico, selecionar, type Selecao, textosDoPacote } from "./secretario-selecao.ts";
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
  detalhe: { fatos: Array<[string, string]>; faco: string | null; curto: string; rotulo: string };
}

export interface ManhaNova {
  texto: string;
  tipoDoDia: TipoDoDia;
  itens: ItemParaGravar[];
  escritorio: string;
  itensManha: number;
  itensLista: number;
  semLetra: number;
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
}): ManhaNova {
  const tipo = tipoDoDia(p.hoje);
  // domingo e feriado: nada sobe; os itens do dia ficam todos na lista (a *lista* funciona)
  const selecao = tipo === "util"
    ? selecionar(candidatosDoDia(p.coleta, p.agora, p.hoje), p.historico, p.hoje)
    : selecionar(candidatosDoDia(p.coleta, p.agora, p.hoje), p.historico, p.hoje, 0,
      `Ficou na lista: ${tipo === "domingo" ? "domingo" : "feriado"}, nada sobe de manhã.`);
  const texto = textoDaManha({
    hoje: p.hoje, tipoDoDia: tipo, feriado: feriadoDoDia(p.hoje), selecao, naRua: p.naRua, deHoje: p.deHoje,
  });
  return {
    texto,
    tipoDoDia: tipo,
    itens: itensParaGravar(selecao),
    escritorio: textoDoEscritorio(p.escritorio, horaBR(p.agora)),
    itensManha: selecao.manha.length,
    itensLista: selecao.lista.filter((g) => g.letra).length,
    semLetra: selecao.semLetra,
  };
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
  return montarDosDados({ hoje: p.hoje, agora: p.agora, ...lido, escritorio: p.escritorio });
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
