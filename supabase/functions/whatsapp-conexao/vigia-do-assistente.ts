// O vigia do assistente dentro do vigia da conexão (pacote 1, V1, 25/11/2026): a parte que lê e grava.
//
// As regras (o que é queda, quando fecha, o que o dono lê) são puras e moram em
// _shared/ai/max/queda-do-assistente.ts. Aqui ficam as leituras e as gravações, chamadas pelo `vigiar` de index.ts na
// mesma rodada de 5 minutos, sem cron novo.
//
// ═══ A REGRA QUE VALE ACIMA DE TODAS ═══
//
// O vigia da conexão do WhatsApp NUNCA quebra por causa disto. Por isso:
//   · olharDoVigia (as leituras de ANTES da decisão do vigia da conexão) nunca lança: chave ausente, tabela que ainda
//     não existe, erro do banco ou exceção = modo "desligado", e o vigia da conexão roda exatamente como antes;
//   · lerCausaDaQuedaDoWhatsApp nunca lança: erro = null, e o texto da volta do WhatsApp é o de sempre;
//   · rodadaDoVigia (o histórico e o aviso) roda DEPOIS de o vigia da conexão ter avisado e gravado, e nunca lança: o
//     que der errado vira uma linha em app_error_logs (whatsapp-conexao / vigiar_assistente) e a rodada termina.
//
// ═══ O QUE CADA MODO FAZ ═══
//
//   · desligado (ou chave ausente): nada disto roda. Nem a leitura dos programas do PC.
//   · sombra: grava o histórico em assistente_quedas (as quedas do assistente e as do WhatsApp). Não manda nada, não
//     toca o sino, não pergunta ao portão e não muda texto nenhum.
//   · ligado: além do histórico, avisa o dono da queda do assistente (sino + portão da voz única) e da volta.
//
// ═══ O QUE NUNCA SE LÊ ═══
//
// O token_hash de ai_gateway_workers (o leitor do C2 pede só id, last_seen_at e estado); texto de mensagem, de pedido ou
// de erro (de ai_jobs só completed_at e requested_by; de app_error_logs só o id).
import { type EstadoDoMax, lerEstadoDoMax, PROVEDOR_DO_MAX, SEM_SINAL_QUEDA_S } from "../_shared/ai/max/causa-da-falha.ts";
import {
  type CausaDoWhatsApp, decidirQuedaDoAssistente, FALHAS_QUE_O_DONO_LEU, jaDaParaAvisar, lerModoDoVigia, MARGEM_DO_JA_SOUBE_MIN,
  MENSAGENS_DO_VIGIA_POR_DIA, type ModoDoVigia, type QuedaAberta, sinoDoAssistente, textoDaQuedaDoAssistente,
  textoDaVoltaDoAssistente,
} from "../_shared/ai/max/queda-do-assistente.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { diaBR } from "../_shared/pdf/datas.ts";
import { avisoDaQuedaDoAssistente } from "../_shared/uma-voz/fontes.ts";
import type { AvisoDaFonte } from "../_shared/uma-voz/portao.ts";
import { enfileirarAcorde, lerDonoDaVoz, lerPortao, registrarNoPortao } from "../_shared/uma-voz/registrar.ts";
import { type Aviso, causaDoWhatsApp, type RegistroDoVigia } from "./conexao.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

const TABELA = "assistente_quedas";
/** A tela do assistente nas configurações (o sino leva para lá). */
export const TELA_DO_ASSISTENTE = "/v2/settings?tab=assistente";

// ─── Antes da decisão do vigia da conexão ────────────────────────────────────────────────────────────────────────────

export interface OlharDoVigia {
  modo: ModoDoVigia;
  /** O estado dos programas do PC com o corte de queda (180 s). null = desligado ou leitura que falhou. */
  pc: EstadoDoMax | null;
}

/**
 * A chave e, se ela não for "desligado", o estado dos programas do PC. Nunca lança: qualquer falha = desligado, e o
 * vigia da conexão segue como antes. Com "desligado", os programas do PC nem são lidos.
 */
export async function olharDoVigia(db: Db, agora: Date): Promise<OlharDoVigia> {
  try {
    const modo = await lerModoDoVigia(db);
    if (modo === "desligado") return { modo, pc: null };
    return { modo, pc: await lerEstadoDoMax(db, SEM_SINAL_QUEDA_S, agora) };
  } catch {
    return { modo: "desligado", pc: null };
  }
}

/**
 * A causa gravada na queda do WhatsApp que está aberta no histórico (para o texto da volta). Nunca lança: sem linha,
 * tabela que não existe ou erro = null (o texto da volta é o de sempre).
 */
export async function lerCausaDaQuedaDoWhatsApp(db: Db): Promise<CausaDoWhatsApp | null> {
  try {
    const { data, error } = await db.from(TABELA).select("causa").eq("tipo", "whatsapp").is("ate", null)
      .order("desde", { ascending: false }).limit(1);
    if (error || !Array.isArray(data)) return null;
    const causa = data[0]?.causa;
    return typeof causa === "string" ? causa as CausaDoWhatsApp : null;
  } catch {
    return null;
  }
}

// ─── A rodada (depois de o vigia da conexão avisar e gravar) ─────────────────────────────────────────────────────────

export interface RodadaDoVigia {
  modo: "sombra" | "ligado";
  pc: EstadoDoMax | null;
  /** O que o vigia da conexão decidiu nesta rodada. */
  aviso: Aviso;
  registro: RegistroDoVigia;
  agora: Date;
}

export interface ResumoDaRodada {
  modo: "sombra" | "ligado";
  /** O que aconteceu com o histórico da queda do WhatsApp. */
  whatsapp: "abriu" | "fechou" | "causa" | null;
  /** O que aconteceu com a queda do assistente. */
  assistente: "nada" | "sem_leitura" | "abriu" | "mantida" | "fechou";
  /** O que saiu para o dono (só no modo ligado). */
  avisou?: string;
  /** Alguma parte falhou (já anotada em app_error_logs). */
  erro?: true;
}

/**
 * O histórico de quedas e, no modo ligado, o aviso. Nunca lança. As duas partes são independentes: a do WhatsApp que
 * falhar não impede a do assistente, e o contrário.
 */
export async function rodadaDoVigia(db: Db, p: RodadaDoVigia): Promise<ResumoDaRodada> {
  const resumo: ResumoDaRodada = { modo: p.modo, whatsapp: null, assistente: "nada" };
  const anotar = async (onde: string, e: unknown) => {
    resumo.erro = true;
    await logEdgeError(db, {
      context: "whatsapp-conexao", action: "vigiar_assistente", message: `${onde}: ${String((e as Error)?.message ?? e)}`, error: e,
    });
  };
  try {
    resumo.whatsapp = await registrarQuedaDoWhatsApp(db, p);
  } catch (e) {
    await anotar("histórico da queda do WhatsApp", e);
  }
  try {
    const r = await vigiarOAssistente(db, { modo: p.modo, pc: p.pc, whatsappAberto: p.registro.estado === "open", agora: p.agora });
    resumo.assistente = r.assistente;
    if (r.avisou) resumo.avisou = r.avisou;
  } catch (e) {
    await anotar("queda do assistente", e);
  }
  return resumo;
}

/**
 * A queda do WhatsApp no histórico: abre no aviso de queda (que o vigia da conexão manda depois de 10 minutos fora),
 * fecha no aviso de volta. No meio da queda, o PC visto vivo troca a causa para "Docker ou túnel". Lança no erro do banco.
 */
export async function registrarQuedaDoWhatsApp(db: Db, p: Pick<RodadaDoVigia, "aviso" | "registro" | "pc" | "agora">): Promise<ResumoDaRodada["whatsapp"]> {
  const agora = p.agora.toISOString();
  if (p.aviso === "caiu") {
    // queda antiga que ficou aberta (a rodada da volta falhou): fecha sem prova, no começo desta
    const { error: erroDaSobra } = await db.from(TABELA).update({ ate: p.registro.desde, fechada_por: "sem_prova" })
      .eq("tipo", "whatsapp").is("ate", null);
    if (erroDaSobra) throw new Error(`fechar a queda antiga do WhatsApp: ${erroDaSobra.message}`);
    const { error } = await db.from(TABELA).insert({
      tipo: "whatsapp", causa: causaDoWhatsApp(p.registro.estado, p.pc), detalhe: `conexao ${p.registro.estado}`,
      desde: p.registro.desde, visto_em: agora, avisado_em: agora, avisado_por: "sino",
    });
    if (error) throw new Error(`abrir a queda do WhatsApp: ${error.message}`);
    return "abriu";
  }
  if (p.aviso === "voltou") {
    const { error } = await db.from(TABELA).update({ ate: agora, fechada_por: "whatsapp_voltou", volta_avisada_em: agora })
      .eq("tipo", "whatsapp").is("ate", null);
    if (error) throw new Error(`fechar a queda do WhatsApp: ${error.message}`);
    return "fechou";
  }
  if (p.registro.estado === "inacessivel" && p.registro.avisado_em && p.pc?.pcComSinal) {
    const { data, error } = await db.from(TABELA).update({ causa: "docker_ou_tunel", visto_em: agora })
      .eq("tipo", "whatsapp").is("ate", null).in("causa", ["pc_fora", "desconhecida"]).select("id");
    if (error) throw new Error(`corrigir a causa da queda do WhatsApp: ${error.message}`);
    return Array.isArray(data) && data.length ? "causa" : null;
  }
  return null;
}

/** O pedido ao Claude concluído mais recente depois de `desde` (a prova da volta). Erro = null (sem prova). */
async function ultimoJobBom(db: Db, desde: string): Promise<{ em: string; pedidoPor: string | null } | null> {
  const { data, error } = await db.from("ai_jobs").select("completed_at, requested_by")
    .eq("provider", PROVEDOR_DO_MAX).eq("status", "completed").gt("completed_at", desde)
    .order("completed_at", { ascending: false }).limit(1);
  if (error || !Array.isArray(data) || typeof data[0]?.completed_at !== "string") return null;
  return { em: data[0].completed_at, pedidoPor: typeof data[0].requested_by === "string" ? data[0].requested_by : null };
}

/**
 * O dono já leu a causa numa resposta de falha do assistente desde o início da queda? (só os registros que respondem
 * pelo WhatsApp: FALHAS_QUE_O_DONO_LEU). null = não deu para ler: quem chama não conclui nada e tenta na próxima rodada.
 */
async function donoJaSoube(db: Db, desde: string): Promise<boolean | null> {
  const inicio = Date.parse(desde);
  if (!Number.isFinite(inicio)) return null;
  const { data, error } = await db.from("app_error_logs").select("id")
    .like("context", "ai-agent@%").in("action", [...FALHAS_QUE_O_DONO_LEU]).eq("level", "error")
    .gte("last_seen_at", new Date(inicio - MARGEM_DO_JA_SOUBE_MIN * 60_000).toISOString()).limit(1);
  if (error || !Array.isArray(data)) return null;
  return data.length > 0;
}

/** Quantas mensagens deste vigia já foram ao WhatsApp do dono hoje (dia de Brasília). null = não deu para contar. */
async function mensagensDeHoje(db: Db, agora: Date): Promise<number | null> {
  const inicioDoDia = new Date(`${diaBR(agora)}T00:00:00-03:00`).toISOString();
  const quedas = await db.from(TABELA).select("id", { count: "exact", head: true }).eq("avisado_por", "whatsapp").gte("avisado_em", inicioDoDia);
  if (quedas.error || typeof quedas.count !== "number") return null;
  const voltas = await db.from(TABELA).select("id", { count: "exact", head: true }).in("tipo", ["claude", "gateway"]).gte("volta_avisada_em", inicioDoDia);
  if (voltas.error || typeof voltas.count !== "number") return null;
  return quedas.count + voltas.count;
}

/** O sino dos administradores ativos. Falha aqui não impede o aviso pelo portão (fica só o aviso no log). */
async function tocarOSino(db: Db, momento: "caiu" | "voltou", texto: string): Promise<void> {
  try {
    const sino = sinoDoAssistente(momento, texto);
    const { data: admins, error: erroDosAdmins } = await db.from("app_users").select("id").eq("role", "admin").eq("active", true);
    if (erroDosAdmins) throw erroDosAdmins;
    const linhas = ((admins ?? []) as Array<{ id: string }>).map((a) => ({ user_id: a.id, ...sino, navigate_to: TELA_DO_ASSISTENTE }));
    if (!linhas.length) return;
    const { error } = await db.from("app_notifications").insert(linhas);
    if (error) throw error;
  } catch (e) {
    console.warn("[whatsapp-conexao] sino do assistente falhou (ignorado):", (e as Error)?.message ?? e);
  }
}

type Por = "whatsapp" | "guardado" | "sino";

/**
 * Pergunta ao portão da voz única e, se ele acordar, põe o texto na fila. Só com a voz única ligada de verdade e com o
 * dono conhecido; fora disso (ou com o portão ilegível) fica só o sino, como a volta do WhatsApp. A chave do aviso é
 * por queda: perguntar de novo devolve "repetido", e a fila recusa a segunda linha da mesma chave.
 */
async function falarPeloPortao(
  db: Db, p: { phone: string | null; aviso: AvisoDaFonte; texto: string; agora: Date; source: string },
): Promise<{ por: Por; avisoId: string | null }> {
  if (!p.phone) return { por: "sino", avisoId: null };
  const r = await registrarNoPortao(db, "ligado", p.phone, p.aviso, p.agora);
  if (!r || r.ok !== true) return { por: "sino", avisoId: null };
  const id = typeof r.id === "string" ? r.id : null;
  const acordou = r.decisao === "acordar" || (r.decisao === "repetido" && r.antes === "acordar" && r.situacao === "acordou");
  if (acordou && id) {
    const naFila = await enfileirarAcorde(db, { phone: p.phone, texto: p.texto, avisoId: id, agora: p.agora, source: p.source });
    // fora da fila = o portão reabriu o aviso: ele volta a guardado e vai na próxima mensagem fixa
    return { por: naFila ? "whatsapp" : "guardado", avisoId: id };
  }
  const guardou = r.decisao === "guardar" || (r.decisao === "repetido" && r.antes === "guardar");
  return { por: guardou ? "guardado" : "sino", avisoId: id };
}

/** O telefone do dono, só com a voz única ligada de verdade (senão ninguém ouve pelo portão), e o id dele. */
async function donoPeloPortao(db: Db): Promise<{ phone: string | null; id: string | null }> {
  const portao = await lerPortao(db);
  if (portao.modo !== "ligado") return { phone: null, id: null };
  const dono = await lerDonoDaVoz(db);
  return { phone: dono?.phone ?? null, id: dono?.id ?? null };
}

/** O aviso que o portão guardou ainda não foi lido pelo dono (continua "guardado")? Erro ou sem id = false. */
async function avisoAindaGuardado(db: Db, avisoId: string | null): Promise<boolean> {
  if (!avisoId) return false;
  const { data, error } = await db.from("avisos_do_dono").select("situacao").eq("id", avisoId).maybeSingle();
  return !error && data?.situacao === "guardado";
}

/**
 * A queda do assistente nesta rodada: lê a aberta, decide (decidirQuedaDoAssistente), grava e, no modo ligado, avisa.
 * Lança no erro do banco (rodadaDoVigia anota e segue). `pc` nulo (a leitura dos programas falhou) = não conclui nada.
 */
export async function vigiarOAssistente(
  db: Db, p: { modo: "sombra" | "ligado"; pc: EstadoDoMax | null; whatsappAberto: boolean; agora: Date },
): Promise<{ assistente: ResumoDaRodada["assistente"]; avisou?: string }> {
  if (!p.pc) return { assistente: "sem_leitura" };
  const agora = p.agora.toISOString();

  const { data, error } = await db.from(TABELA)
    .select("id, tipo, causa, desde, visto_em, criado_em, dono_soube, avisado_por, aviso_id")
    .in("tipo", ["claude", "gateway"]).is("ate", null).order("desde", { ascending: true }).limit(1);
  if (error) throw new Error(`ler a queda aberta: ${error.message}`);
  const aberta = ((data as QuedaAberta[] | null)?.[0] ?? null) as QuedaAberta | null;

  const jobBom = aberta ? await ultimoJobBom(db, aberta.desde) : null;
  const passo = decidirQuedaDoAssistente({ aberta, estado: p.pc, whatsappAberto: p.whatsappAberto, ultimoJobBomEm: jobBom?.em ?? null, agora: p.agora });

  if (passo.acao === "nada") return { assistente: "nada" };

  if (passo.acao === "abrir") {
    const { error: erroAoAbrir } = await db.from(TABELA).insert({
      tipo: passo.tipo, causa: passo.causa, detalhe: passo.detalhe, desde: passo.desde, visto_em: agora,
    });
    // 23505 = já há uma aberta deste tipo (duas rodadas ao mesmo tempo): vale a primeira
    if (erroAoAbrir && (erroAoAbrir as { code?: string }).code !== "23505") throw new Error(`abrir a queda: ${erroAoAbrir.message}`);
    return { assistente: "abriu" };
  }

  // daqui em diante há uma queda aberta
  const queda = aberta as QuedaAberta;

  if (passo.acao === "fechar") {
    const { error: erroAoFechar } = await db.from(TABELA).update({ ate: passo.ate, fechada_por: passo.por }).eq("id", queda.id).is("ate", null);
    if (erroAoFechar) throw new Error(`fechar a queda: ${erroAoFechar.message}`);
    if (p.modo !== "ligado" || !passo.provada || !queda.dono_soube) return { assistente: "fechou" };
    return { assistente: "fechou", avisou: await avisarDaVolta(db, queda, { ate: passo.ate, por: passo.por, pedidoPor: jobBom?.pedidoPor ?? null }, p.agora) };
  }

  // manter
  if (passo.visto) {
    const { error: erroAoManter } = await db.from(TABELA)
      .update({ tipo: passo.tipo, causa: passo.causa, visto_em: agora, ...(passo.detalhe ? { detalhe: passo.detalhe } : {}) })
      .eq("id", queda.id).is("ate", null);
    if (erroAoManter) throw new Error(`manter a queda: ${erroAoManter.message}`);
  }
  if (p.modo !== "ligado" || !p.whatsappAberto || queda.dono_soube || queda.avisado_por || !jaDaParaAvisar(queda, p.agora)) {
    return { assistente: "mantida" };
  }
  const libera = p.pc.pausa?.motivo === "rate_limited" ? p.pc.pausa.ate : null;
  return { assistente: "mantida", avisou: await avisarDaQueda(db, { ...queda, tipo: passo.tipo, causa: passo.causa }, libera, p.agora) };
}

/**
 * O aviso de queda (só no modo ligado, com o WhatsApp de pé, 15 minutos depois de a queda ser vista, uma vez por queda):
 *   · o dono já leu a causa numa resposta de falha → só anota; não manda (ele já sabe);
 *   · já saíram 2 mensagens deste vigia hoje → só o sino;
 *   · senão: sino e portão (acorda das 08:00 às 19:59; fora disso o portão guarda para a manhã ou o fechamento).
 */
async function avisarDaQueda(db: Db, q: QuedaAberta, libera: string | null, agora: Date): Promise<string> {
  const marcar = async (campos: Record<string, unknown>) => {
    const { error } = await db.from(TABELA).update(campos).eq("id", q.id).is("ate", null);
    if (error) throw new Error(`anotar o aviso da queda: ${error.message}`);
  };
  const soube = await donoJaSoube(db, q.desde);
  if (soube === null) return "sem_leitura";
  if (soube) {
    await marcar({ dono_soube: "resposta_de_falha" });
    return "ja_soube";
  }
  const hoje = await mensagensDeHoje(db, agora);
  if (hoje === null) return "sem_leitura";

  const texto = textoDaQuedaDoAssistente({ causa: q.causa, desde: q.desde, libera }, agora);
  await tocarOSino(db, "caiu", texto);
  if (hoje >= MENSAGENS_DO_VIGIA_POR_DIA) {
    await marcar({ dono_soube: "aviso", avisado_em: agora.toISOString(), avisado_por: "limite" });
    return "limite";
  }
  const dono = await donoPeloPortao(db);
  const fala = await falarPeloPortao(db, {
    phone: dono.phone, aviso: avisoDaQuedaDoAssistente({ id: q.id, desde: q.desde, causa: q.causa }, "caiu", texto), texto, agora,
    source: "assistente_caiu",
  });
  await marcar({ dono_soube: "aviso", avisado_em: agora.toISOString(), avisado_por: fala.por, aviso_id: fala.avisoId });
  return fala.por;
}

/**
 * O aviso de volta (só no modo ligado, volta provada, e só se o dono soube da queda). Sino sempre. Pelo WhatsApp, não:
 *   · quando o pedido que provou a volta foi do próprio dono (ele acabou de receber a resposta: já sabe);
 *   · quando o aviso da queda ainda está guardado, sem ele ter lido (o guardado some: queda e volta não viram notícia);
 *   · quando já saíram 2 mensagens deste vigia hoje.
 */
async function avisarDaVolta(
  db: Db, q: QuedaAberta, volta: { ate: string; por: string; pedidoPor: string | null }, agora: Date,
): Promise<string> {
  const texto = textoDaVoltaDoAssistente({ desde: q.desde, ate: volta.ate }, agora);
  await tocarOSino(db, "voltou", texto);
  const dono = await donoPeloPortao(db);
  if (volta.por === "job_bom" && dono.id && volta.pedidoPor === dono.id) return "dono_viu";
  if (q.avisado_por === "guardado" && await avisoAindaGuardado(db, q.aviso_id)) return "queda_nao_lida";
  const hoje = await mensagensDeHoje(db, agora);
  if (hoje === null || hoje >= MENSAGENS_DO_VIGIA_POR_DIA) return hoje === null ? "sem_leitura" : "limite";
  const fala = await falarPeloPortao(db, {
    phone: dono.phone,
    aviso: avisoDaQuedaDoAssistente({ id: q.id, desde: q.desde, causa: q.causa, ate: volta.ate }, "voltou", texto), texto, agora,
    source: "assistente_voltou",
  });
  if (fala.por !== "sino") {
    const { error } = await db.from(TABELA).update({ volta_avisada_em: agora.toISOString() }).eq("id", q.id);
    if (error) throw new Error(`anotar o aviso da volta: ${error.message}`);
  }
  return fala.por;
}
