// O turno da tarde do resumo (secretário, Passo 3, 15/10/2026): o fechamento das 17:30 (seg–sex), a revisão
// da semana, a revisão do mês e a pergunta da sexta. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md
//
// Chamado por index.ts SÓ quando a URL tem ?turno= (o cron das 17:30 chama ?turno=tarde; ?dry=1&turno=…
// pré-visualiza). Sem o parâmetro — o cron das 07:30 — nada daqui roda.
//
// app_settings.fechamento_formato: 'desligado' (padrão) = nada; 'sombra' = monta e GUARDA (resumo_tarde), sem
// enviar; 'ligado' = envia ao dono, e só nos dias em que a manhã foi a nova (as letras são as que ele recebeu;
// com a manhã-sombra, rebaixa para sombra). A tarde depende da manhã do dia: sem manhã gravada, nada.
//
// Gravar e enfileirar são UMA transação (RPC resumo_tarde_registrar): existir a linha de hoje = "já decidi
// hoje" (os disparos das 17:40 e 17:50 param). Custo de IA zero: a montagem é por regra.

import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { donoDoWhatsApp } from "../_shared/whatsapp/dono.ts";
import { resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";
import {
  ehDiaDaPerguntaDaSemana,
  lerFormatoDoFechamento,
  lerTurnoPedido,
  proximoDiaComManha,
  type TurnoDaTarde,
  turnoDaTarde,
} from "../_shared/secretario/turno.ts";
import { type Candidato, candidatosDoDia, type ColetaDoSecretario } from "./secretario-candidatos.ts";
import { coletar } from "./secretario-coleta.ts";
import type { PassagemDoHistorico } from "./secretario-selecao.ts";
import {
  cobrancasAntigas, ficaramDeHoje, type ItemDaManha, type LinhaComLetra, paradosDaSemana, type QuemEspera, semRespostaDesdeHoje,
} from "./secretario-tarde-regras.ts";
import type { OpcoesDoHistorico } from "./secretario-selecao.ts";
import {
  acordadosDeHoje, type AvisoGuardado, chaveDaFilaDaTarde, idDaFilaPelaChave, lerGuardado, marcarNaMensagem, planoDoGuardado,
  type PlanoDoGuardado, quaisSeResolveram,
} from "../_shared/uma-voz/guardado.ts";
import { type ModoDoPortao, REGRAS_PADRAO, type RegrasDaVozUnica } from "../_shared/uma-voz/portao.ts";
import { lerPortao } from "../_shared/uma-voz/registrar.ts";
import {
  amanhaComAAgenda,
  type ContaDoMes,
  type DiaDeAmanha,
  type LinhaDaAgenda,
  minutosDoEscritorio,
  type Panorama,
  semanaCabe,
  textoDaTarde,
} from "./secretario-tarde-texto.ts";
import {
  contarEscritorio,
  conversaAtiva,
  fornecedoresEsperando,
  lerAgendaDoFechamento,
  lerAmanha,
  lerEsperando,
  lerManhaDeHoje,
  lerMesQueFechou,
  lerPanorama,
} from "./secretario-tarde-coleta.ts";
import { type DadosDoEscritorio, textoDoEscritorio } from "./secretario-texto.ts";
import { tentativasAte } from "./linhas.ts";
import { linhasDoHistorico } from "./historico.ts";
import type { LoteMontado } from "../_shared/papelada/lote.ts";
import { CHAVE_DA_PAPELADA, lerFormatoDaPapelada, linhaDoLote } from "../_shared/papelada/texto.ts";
import { contarRegrasGuardadas, montarLoteDaSemana, registrarLote } from "./secretario-papelada.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** (Passo 5) Quanto tempo o lote da semana vale: até o próximo (7 dias). */
const VALIDADE_DO_LOTE_MS = 7 * 86_400_000;

export interface RespostaDaTarde {
  status: number;
  corpo: Record<string, unknown>;
}

/** 1 = antes de 17:40, 2 = antes de 17:50, 3 = 17:50 ou depois (a última: vai mesmo com conversa). */
export function tentativaDoRelogio(agora: Date): 1 | 2 | 3 {
  const [h, m] = horaBR(agora).split(":").map(Number);
  const desde = h * 60 + m - (17 * 60 + 30);
  return desde < 10 ? 1 : desde < 20 ? 2 : 3;
}

/** A corrida de verdade só monta entre 17:25 e 19:00 de Brasília (um disparo às 10h não vira "fechamento"). */
export function dentroDoHorario(agora: Date): boolean {
  const [h, m] = horaBR(agora).split(":").map(Number);
  const min = h * 60 + m;
  return min >= 17 * 60 + 25 && min < 19 * 60;
}

const NOME_DO_TURNO: Record<TurnoDaTarde, string> = {
  fechamento: "o fechamento das 17:30",
  revisao_semana: "a revisão da semana",
  revisao_mes: "a revisão do mês",
};

/** O que a tarde leu (a coleta da manhã, rodada de novo, e as leituras só da tarde). */
export interface LidoDaTarde {
  coleta: ColetaDoSecretario;
  historico: PassagemDoHistorico[];
  // deno-lint-ignore no-explicit-any
  esperando: any[];
  /**
   * (16/10/2026) as recebidas da semana de quem espera (o F1 acha a 1ª mensagem de hoje sem resposta; o texto tira quem
   * só agradeceu); null = falhou
   */
  recebidas?: Array<{ phone_normalized: string; occurred_at: string; body?: string | null }> | null;
  amanha: DiaDeAmanha | null;
  escritorio: DadosDoEscritorio | null;
  panorama: Panorama | null;
  mesQueFechou: { conta: ContaDoMes; faturamento: string | null } | null;
}

export interface TardeMontada {
  texto: string | null;
  letras: LinhaComLetra[];
  detalhe: Record<string, unknown>;
  escritorio: string | null;
  /**
   * (16/10/2026) o guardado que o texto mostrou (só na sombra) e os ids a marcar depois de gravar: os mostrados (+ os
   * do escritório quando a linha do escritório saiu) e os resolvidos (D8). null = sem guardado.
   */
  guardado?: { modo: ModoDoPortao; mostrados: string[]; resolvidos: string[] } | null;
  /**
   * (24/10/2026, Agenda de Produção Fase 2, P5) As linhas do plano que saíram no texto (só as ligadas). Depois de gravada e
   * ENVIADA a tarde, vão para agenda_fechamento_registrar (a pergunta conta uma vez mostrada; a ação fica contada).
   */
  agendaMostrou?: LinhaDaAgenda[];
}

/** (16/10/2026) O que a tarde-sombra recebe do portão: o guardado, os acordes de hoje e as regras do dono. */
export interface DoPortaoNaTarde {
  modo: ModoDoPortao | null;
  regras: RegrasDaVozUnica;
  /** null = sem guardado (voz única desligada, tarde que sai de verdade, ou erro de leitura) */
  guardado: { avisos: AvisoGuardado[]; resolvidos: Set<string> } | null;
  /** telefone → hora do acorde de hoje (só na sombra) */
  acordados: Map<string, string>;
}

const SEM_PORTAO: DoPortaoNaTarde = { modo: null, regras: { ...REGRAS_PADRAO }, guardado: null, acordados: new Map() };

/** Os telefones que a tarde já mostra com letra (o F1 e o guardado do mesmo contato não repetem). */
function fonesComLetra(...listas: LinhaComLetra[][]): Set<string> {
  const s = new Set<string>();
  for (const l of listas.flat()) {
    // (20/10/2026) a regex tinha perdido a barra (`(d+)` casava "fone:ddd"): nenhum telefone com letra era reconhecido
    const f = /^fone:(\d+)$/.exec(l.referencia)?.[1];
    if (f) s.add(f);
  }
  return s;
}

/** A parte pura: dos dados lidos ao texto, às letras e ao detalhe gravado. */
export function montarTardeDosDados(p: {
  hoje: string;
  agora: Date;
  turno: TurnoDaTarde;
  itens: ItemDaManha[];
  lido: LidoDaTarde;
  pergunta: boolean;
  /** (16/10/2026) o portão (guardado, acordes de hoje, regras do dono); ausente = sem nada disso, as regras-padrão */
  portao?: DoPortaoNaTarde;
  /** (16/10/2026, Passo 5) o lote da semana a mostrar; ausente = a tarde de antes, byte a byte */
  lote?: LoteMontado | null;
}): TardeMontada {
  const { hoje, agora, turno, lido } = p;
  const portao = p.portao ?? SEM_PORTAO;
  const opcoes: OpcoesDoHistorico = { semanaVoltaComFatoNovo: portao.regras.semana_volta_com_fato_novo };
  const candidatos = new Map<string, Candidato>(candidatosDoDia(lido.coleta, agora, hoje).map((c) => [c.referencia, c]));
  const ficaram = turno === "fechamento" ? ficaramDeHoje(p.itens, candidatos) : [];
  const parados = turno === "revisao_semana" ? paradosDaSemana(p.itens, candidatos, lido.historico, hoje, opcoes) : [];
  const antigas = turno === "revisao_mes" ? cobrancasAntigas(p.itens, lido.coleta.cobrancas, candidatos, lido.historico, hoje, 5, opcoes) : null;
  const fornecedores = turno === "fechamento" ? fornecedoresEsperando(lido.esperando, agora) : [];
  // F1 (16/10/2026): quem escreveu hoje e está sem resposta (e quem o portão acordou hoje), fora quem já tem letra
  const comLetra = fonesComLetra(ficaram, parados.slice(0, 5), antigas?.linhas ?? []);
  const semResposta = semRespostaDesdeHoje({
    esperando: lido.esperando as QuemEspera[], recebidas: lido.recebidas ?? null, agora,
    horas: portao.regras.sem_resposta_hoje_horas, comLetra, acordados: portao.acordados,
  });
  // o guardado (só na sombra): o do escritório só no fechamento (a linha do escritório é dele)
  const plano: PlanoDoGuardado | null = portao.guardado && portao.guardado.avisos.length
    ? planoDoGuardado({
      avisos: portao.guardado.avisos, mensagem: "fechamento", hoje, resolvidosAgora: portao.guardado.resolvidos,
      regras: portao.regras, cobertos: comLetra,
    })
    : null;
  const planoDaTarde = plano && turno !== "fechamento" ? { ...plano, escritorio: [], doEscritorio: [] } : plano;
  const t = textoDaTarde({
    hoje, turno, ficaram, amanha: lido.amanha, fornecedores, escritorio: lido.escritorio,
    parados, panorama: lido.panorama, antigas,
    mesQueFechou: lido.mesQueFechou?.conta ?? null, faturamento: lido.mesQueFechou?.faturamento ?? null,
    pergunta: p.pergunta,
    guardado: planoDaTarde, semResposta, semRespostaMax: portao.regras.sem_resposta_hoje_max,
    ...(p.lote ? { lote: p.lote } : {}),
  });
  const e = lido.escritorio;
  const linhaLote = p.lote ? linhaDoLote(p.lote) : null;
  // (24/10/2026, Agenda de Produção Fase 1, P6) o que a agenda diria e o que dela saiu no texto. Na sombra (como nasce),
  // cauda_diria é a linha "Amanhã" que sairia com 'ligado' (null = a agenda não mudaria o "Amanhã") e semana_diria as
  // linhas da semana que vem (só na quinta); semana_cabia = havia vaga (menos de REGRAS.maxManha que ficaram).
  const ag = lido.amanha?.agenda ?? null;
  // (24/10/2026, Fase 2, P5) as linhas do plano: todas as que a agenda diria, com o modo (a sombra compara por aqui), e as
  // que saíram no texto
  const linhasMostradas = t.agenda?.linhas ?? [];
  const agenda = ag
    ? {
      modo: ag.modo,
      cauda_diria: amanhaComAAgenda(hoje, lido.amanha),
      semana_diria: ag.semana,
      semana_cabia: turno === "fechamento" && semanaCabe(ficaram.length, ag),
      mostrou: !!t.agenda && (t.agenda.cauda || t.agenda.semana > 0 || linhasMostradas.length > 0),
      // (30/10/2026, Fase 7a, P7) as vagas garantidas da agenda e, em sombra, as que ela teria (a vaga só no detalhe)
      ...(ag.vagas_garantidas ? { vagas_garantidas: ag.vagas_garantidas } : {}),
      ...(ag.vaga_teria ? { vaga_teria: ag.vaga_teria } : {}),
      ...(ag.linhas
        ? {
          linhas_diria: ag.linhas.map((l) => ({ tipo: l.tipo, perda: l.perda, modo: l.modo, texto: l.texto })),
          linhas_mostrou: linhasMostradas.map((l) => ({ tipo: l.tipo, perda: l.perda, texto: l.texto })),
        }
        : {}),
    }
    : null;
  return {
    guardado: planoDaTarde && portao.modo
      ? {
        modo: portao.modo,
        // calado = nada foi mostrado (fica guardado para a próxima); o resolvido some de qualquer jeito
        mostrados: t.texto ? [...planoDaTarde.mostrados, ...planoDaTarde.doEscritorio] : [],
        resolvidos: planoDaTarde.resolvidos,
      }
      : null,
    texto: t.texto,
    letras: t.letras,
    ...(linhasMostradas.length ? { agendaMostrou: linhasMostradas } : {}),
    detalhe: {
      ficaram: ficaram.length,
      // todos os parados (o texto mostra até 5)
      parados: parados.length,
      ...(antigas ? { antigas: { n: antigas.n, total: antigas.total, sem_letra: antigas.fora.n } } : {}),
      ...(lido.amanha ? { amanha: lido.amanha.itens.length } : {}),
      fornecedores: fornecedores.length,
      ...(e ? { escritorio: { propostas: e.propostas, alertas: e.alertas, regras: e.regras, debitos_sem_loja: e.debitosSemLoja, entradas: e.entradas, minutos: minutosDoEscritorio(e) } } : {}),
      ...(lido.panorama ? { panorama: { mes: lido.panorama.mes, semana: lido.panorama.semana, vigia: !!lido.panorama.vigia } } : {}),
      ...(lido.mesQueFechou ? { mes_que_fechou: lido.mesQueFechou.conta } : {}),
      caracteres: t.texto?.length ?? 0,
      ...(semResposta.length ? { sem_resposta: semResposta.length } : {}),
      ...(planoDaTarde
        ? { guardado: { linhas: planoDaTarde.linhas.length, escritorio: planoDaTarde.escritorio.length, resolvidos: planoDaTarde.resolvidos.length, restantes: planoDaTarde.restantes } }
        : {}),
      ...(p.lote ? { lote: { itens: p.lote.itens.length, fora: p.lote.fora.length, total: p.lote.total, minutos: p.lote.minutos } } : {}),
      ...(agenda ? { agenda } : {}),
    },
    // (Passo 5) no dia do lote, o *escritório* da tarde termina com a linha do lote
    escritorio: e ? `${textoDoEscritorio(e, horaBR(agora))}${linhaLote ? `\n\n${linhaLote}` : ""}`.slice(0, 2000) : null,
  };
}

/** Lê o banco para a tarde. Lança se uma leitura essencial falhar (quem chama não monta). */
export async function lerTudoDaTarde(admin: Admin, p: {
  agora: Date;
  hoje: string;
  turno: TurnoDaTarde;
  dono: { id: string; phone: string };
  modo: "sombra" | "novo";
  cfg: Record<string, string>;
  /** (16/10/2026) as regras do dono (F3, F5); ausente = os padrões */
  regras?: RegrasDaVozUnica;
}): Promise<LidoDaTarde> {
  const regras = p.regras ?? REGRAS_PADRAO;
  const { esperando, recebidas } = await lerEsperando(admin, p.agora);
  const lido = await coletar(admin, { agora: p.agora, hoje: p.hoje, dono: p.dono, modo: p.modo, doResumo: { esperando, recebidas, cfg: p.cfg } });
  // (16/10/2026) a revisão de segunda também traz o "Amanhã" (com o a pagar do F3), como o fechamento
  // (24/10/2026, Fase 2, P5) com a agenda automática ligada, o "Amanhã" lê o plano (as OS e as compras)
  const amanha = p.turno === "fechamento" || p.turno === "revisao_semana"
    ? await lerAmanha(admin, p.dono, p.hoje, proximoDiaComManha(p.hoje), lido.coleta.oss, regras.amanha_a_pagar,
      lido.modos?.proposta === "ligado")
    : null;
  // (24/10/2026, Agenda de Produção Fase 1, P6) o que a agenda diria do mesmo dia; sem ela (desligada, erro, ainda não
  // aplicada), o "Amanhã" é o da Fase 0
  if (amanha) {
    const agenda = await lerAgendaDoFechamento(admin, p.hoje, amanha.dia);
    if (agenda) amanha.agenda = agenda;
  }
  return {
    coleta: lido.coleta,
    historico: lido.historico,
    esperando,
    recebidas,
    amanha,
    escritorio: p.turno === "fechamento" ? await contarEscritorio(admin, p.hoje) : null,
    panorama: p.turno === "revisao_semana" ? await lerPanorama(admin, p.hoje, regras.vigia_so_mes_recente) : null,
    mesQueFechou: p.turno === "revisao_mes" ? await lerMesQueFechou(admin, p.hoje) : null,
  };
}

function ok(corpo: Record<string, unknown>): RespostaDaTarde {
  return { status: 200, corpo: { ok: true, ...corpo } };
}

/**
 * O turno da tarde inteiro. `pedido` = o ?turno= da URL ("tarde" = o do dia; um turno forçado só com dry).
 * Nunca envia na sombra; nunca grava no dry-run.
 */
export async function rodarTurnoDaTarde(admin: Admin, p: { agora: Date; pedido: string | null; dry: boolean }): Promise<RespostaDaTarde> {
  const pedido = lerTurnoPedido(p.pedido);
  if (!pedido) return { status: 400, corpo: { ok: false, erro: "turno_invalido" } };
  if (!p.dry && pedido !== "tarde") return { status: 400, corpo: { ok: false, erro: "turno_forcado_so_no_dry" } };
  const hoje = diaBR(p.agora);

  const { data: cfgRows, error: cfgErr } = await admin.from("app_settings").select("key, value")
    .in("key", ["fechamento_formato", "quote_validity_days", CHAVE_DA_PAPELADA, "finance_review_batch_limit"]);
  const cfg: Record<string, string> = {};
  for (const r of (cfgRows as Array<{ key: string; value: unknown }>) || []) if (r?.key) cfg[String(r.key)] = String(r.value ?? "");
  // sem conseguir ler a chave = desligado (nada sai por engano)
  const formato = cfgErr ? "desligado" : lerFormatoDoFechamento(cfg["fechamento_formato"]);
  if (!p.dry && formato === "desligado") return ok({ motivo: "desligado" });

  const turno = pedido === "tarde" ? turnoDaTarde(hoje) : pedido;
  if (!turno) return ok({ motivo: "sem_tarde_hoje", dia: hoje });
  if (!p.dry && !dentroDoHorario(p.agora)) return ok({ motivo: "fora_do_horario", hora: horaBR(p.agora) });

  const dono = await donoDoWhatsApp(admin);
  if (!dono) return ok({ motivo: "sem_dono" });
  if (!p.dry) {
    const ja = await admin.from("resumo_tarde").select("id, turno, enviado, calado")
      .eq("dia", hoje).eq("phone_normalized", dono.phone).maybeSingle();
    if (ja.error) throw Object.assign(new Error("tarde: leitura de resumo_tarde falhou"), { code: ja.error.code });
    if (ja.data) return ok({ motivo: "ja_feito", turno: ja.data.turno, enviado: ja.data.enviado, calado: ja.data.calado });
  }

  const manha = await lerManhaDeHoje(admin, dono.phone, hoje);
  if (!manha) return ok({ motivo: "sem_manha", turno });
  const enviar = formato === "ligado" && manha.modo === "novo";
  const rebaixado = formato === "ligado" && manha.modo !== "novo";
  const tentativa = tentativaDoRelogio(p.agora);
  const conversa = await conversaAtiva(admin, dono.phone, p.agora);
  // "Se o dono estiver no meio de uma conversa, espera até 20 min": só faz sentido quando vai enviar
  if (!p.dry && enviar && conversa && tentativa < 3) return ok({ motivo: "esperando_conversa", turno, tentativa });

  // (16/10/2026) o portão: as regras do dono (F1, F3, F5, F7) e o guardado + os acordes de hoje:
  //   · tarde que NÃO sai (sombra/rebaixada): os da SOMBRA, só com a voz única em sombra;
  //   · (20/10/2026, P4.5) tarde ENVIADA: os do modo LIGADO — com a voz ligada as fontes seguraram para ela. Lidos com a
  //     chave em 'ligado' ou 'sombra' (voltar atrás é 'sombra': o que ficou guardado enquanto ela estava ligada não se
  //     perde); 'desligado' = nada lido, como antes; sem linha 'ligado' = nada muda. O guardado da sombra nunca vai na
  //     tarde enviada (as fontes já tinham avisado).
  const voz = await lerPortao(admin);
  const lido = await lerTudoDaTarde(admin, { agora: p.agora, hoje, turno, dono, modo: manha.modo, cfg, regras: voz.regras });
  const pergunta = ehDiaDaPerguntaDaSemana(hoje);
  const modoDoGuardado = enviar ? (voz.voz !== "desligado" ? "ligado" : null) : voz.modo === "sombra" ? "sombra" : null;
  const doPortao: DoPortaoNaTarde = { modo: modoDoGuardado, regras: voz.regras, guardado: null, acordados: new Map() };
  if (modoDoGuardado) {
    const avisos = await lerGuardado(admin, { phone: dono.phone, modo: modoDoGuardado, mensagem: "fechamento", agora: p.agora });
    if (avisos) doPortao.guardado = { avisos, resolvidos: avisos.length ? await quaisSeResolveram(admin, avisos) : new Set() };
    doPortao.acordados = await acordadosDeHoje(admin, { phone: dono.phone, modo: modoDoGuardado, dia: hoje });
  }
  // (16/10/2026, Passo 5) o lote semanal da papelada: só com a chave ≠ desligado e no último dia útil da semana (o dia
  // da pergunta). Falhar a leitura = a tarde de sempre, sem lote. A linha só vai no texto que o dono RECEBE com a chave
  // ligada; na tarde que não sai (sombra) ela entra para comparar.
  const papelada = cfgErr ? "desligado" : lerFormatoDaPapelada(cfg[CHAVE_DA_PAPELADA]);
  let lote: LoteMontado | null = null;
  if (papelada !== "desligado" && pergunta) {
    try {
      lote = await montarLoteDaSemana(admin, { cfg });
    } catch (e) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", tarde: "lote_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
    }
  }
  const loteNoTexto = lote && (!enviar || papelada === "ligado") ? lote : null;
  const dados = { hoje, agora: p.agora, turno, itens: manha.itens, lido, pergunta, portao: doPortao };
  let m = montarTardeDosDados(loteNoTexto ? { ...dados, lote: loteNoTexto } : dados);
  const letras = m.letras.map((l) => ({ letra: l.letra, referencia: l.referencia, tipo: l.tipo, parte: l.parte }));

  if (p.dry) {
    return ok({
      dry: true, turno, formato, modo_da_manha: manha.modo, enviaria: enviar && !!m.texto, rebaixado,
      conversa_ativa: conversa, pergunta_semana: pergunta, texto: m.texto, caracteres: m.texto?.length ?? 0, letras,
      detalhe: m.detalhe,
      ...(lote ? { lote: { formato: papelada, linha: linhaDoLote(lote), itens: lote.itens, fora: lote.fora, total: lote.total, minutos: lote.minutos } } : {}),
    });
  }

  // (Passo 5) o lote é guardado ANTES da tarde: a linha só sai se o lote estiver no banco (senão *lote* não o acharia).
  // 'ligado' só com a chave ligada e a tarde saindo de verdade; senão 'sombra' (nunca aplicado: CHECK no banco).
  let loteGravado: string | null = null;
  if (lote) {
    const g = await registrarLote(admin, {
      dia: hoje, phone: dono.phone, appUserId: dono.id,
      formato: papelada === "ligado" && enviar && !!m.texto ? "ligado" : "sombra",
      lote, validoAte: new Date(p.agora.getTime() + VALIDADE_DO_LOTE_MS).toISOString(),
      regrasGuardadas: await contarRegrasGuardadas(admin),
    });
    loteGravado = g.ok ? (g.novo ? "novo" : "ja_existia") : `erro:${g.erro ?? "?"}`;
    if (!g.ok && loteNoTexto) m = montarTardeDosDados(dados);
  }

  const vaiEnviar = enviar && !!m.texto;
  const { data, error } = await admin.rpc("resumo_tarde_registrar", {
    p: {
      dia: hoje,
      phone: dono.phone,
      app_user_id: dono.id,
      turno,
      modo: manha.modo,
      formato: formato === "ligado" ? "ligado" : "sombra",
      texto: m.texto,
      calado: !m.texto,
      enviado: vaiEnviar,
      letras,
      detalhe: m.detalhe,
      escritorio: m.escritorio,
      itens: Math.min(21, m.letras.length),
      pergunta_semana: pergunta && !!m.texto,
      conversa_ativa: conversa,
      tentativa,
      // a fila para de tentar às 19:30 (nada depois das 20h)
      max_attempts: tentativasAte("19:30", p.agora),
    },
  });
  if (error) throw Object.assign(new Error("tarde: resumo_tarde_registrar falhou"), { code: error.code });
  const r = (data ?? {}) as { ok?: boolean; novo?: boolean; enviado?: boolean; calado?: boolean; erro?: string };
  if (!r.ok) return { status: 500, corpo: { ok: false, erro: r.erro ?? "registrar" } };

  // (16/10/2026) o guardado mostrado na tarde-sombra fica "incluido" (nunca "entregue": nada saiu); o resolvido some.
  // Só na 1ª gravação do dia. Nunca lança.
  let guardadoMarcado = 0;
  if (r.novo && !r.enviado && m.guardado?.modo === "sombra" && (m.guardado.mostrados.length || m.guardado.resolvidos.length)) {
    guardadoMarcado = (await marcarNaMensagem(admin, { phone: dono.phone, modo: m.guardado.modo, mostrados: m.guardado.mostrados, resolvidos: m.guardado.resolvidos })).incluidos;
  }
  // (20/10/2026, P4.5) a tarde ENVIADA levou o guardado da voz ligada: "incluido" com o id da linha da FILA (a RPC
  // enfileira na mesma transação e devolve o id da tarde; a linha da fila tem a chave secretario_tarde:<dia>:<telefone>).
  // "entregue" só quando a fila disser 'sent'; sem o id, os mostrados não são marcados e voltam na próxima mensagem.
  let guardadoNaTarde = 0;
  if (r.novo && r.enviado && m.guardado?.modo === "ligado" && (m.guardado.mostrados.length || m.guardado.resolvidos.length)) {
    const filaId = m.guardado.mostrados.length ? await idDaFilaPelaChave(admin, chaveDaFilaDaTarde(hoje, dono.phone)) : null;
    guardadoNaTarde = (await marcarNaMensagem(admin, {
      phone: dono.phone, modo: "ligado", mostrados: m.guardado.mostrados, resolvidos: m.guardado.resolvidos, filaId,
    })).incluidos;
  }

  // (24/10/2026, Fase 2, P5) as linhas do plano que SAÍRAM (tarde enviada, 1ª gravação do dia): a pergunta conta uma vez
  // mostrada e a mudança fica contada (não volta amanhã). Na sombra ou rebaixada, nada (o dono não viu). Nunca lança.
  const agendaRegistrada = r.novo && r.enviado && m.agendaMostrou?.length
    ? await registrarAgendaDoFechamento(admin, hoje, m.agendaMostrou)
    : null;

  // o que foi enviado entra no histórico da conversa do assistente ("e o B?" tem a que se referir); falha só loga
  let historico = false;
  if (r.novo && r.enviado && m.texto) {
    try {
      const sessao = await resolveOrCreateWhatsAppSession(admin, dono.phone, dono.id);
      const agoraHist = new Date();
      const { error: hErr } = await admin.from("ai_operator_messages").insert(linhasDoHistorico(sessao, m.texto, agoraHist, NOME_DO_TURNO[turno]));
      if (hErr) throw hErr;
      await admin.from("ai_operator_sessions").update({ last_activity_at: agoraHist.toISOString() }).eq("id", sessao);
      historico = true;
    } catch (e) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", tarde: "historico_falhou", codigo: String((e as { code?: unknown })?.code ?? "erro") }));
    }
  }
  return ok({
    turno, formato, modo_da_manha: manha.modo, gravado: r.novo === true, enviado: r.enviado === true, calado: r.calado === true,
    rebaixado, conversa_ativa: conversa, tentativa, letras: letras.length, historico,
    ...(m.guardado?.modo === "sombra" ? { guardado_na_sombra: guardadoMarcado } : {}),
    ...(m.guardado?.modo === "ligado" ? { guardado_na_tarde: guardadoNaTarde } : {}),
    ...(loteGravado ? { lote: loteGravado } : {}),
    ...(agendaRegistrada ? { agenda_registrada: agendaRegistrada } : {}),
  });
}

/**
 * (24/10/2026, Agenda de Produção Fase 2, P5) agenda_fechamento_registrar com as linhas do plano que saíram no fechamento
 * enviado ({pergunta_id, acao_ids} de cada uma). Erro = só o aviso no log: o fechamento já saiu, e a linha não registrada
 * volta no próximo (melhor repetir que calar). Nunca lança.
 */
export async function registrarAgendaDoFechamento(
  admin: Admin, hoje: string, linhas: LinhaDaAgenda[],
): Promise<{ perguntas: number; acoes: number } | "erro"> {
  try {
    const { data, error } = await admin.rpc("agenda_fechamento_registrar", {
      p_hoje: hoje,
      p_linhas: linhas.map((l) => ({ pergunta_id: l.pergunta_id, acao_ids: l.acao_ids })),
      p_via: "fechamento",
    });
    if (error) throw error;
    const r = (data ?? {}) as { perguntas?: unknown; acoes?: unknown };
    return { perguntas: Number(r.perguntas ?? 0), acoes: Number(r.acoes ?? 0) };
  } catch (e) {
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", tarde: "agenda_registro_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
    return "erro";
  }
}
