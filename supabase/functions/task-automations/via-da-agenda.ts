// A via do técnico junto da ficha das 19:30 (13/11/2026).
//
// Pedido do dono: o agente da agenda manda a via do técnico em PDF no acompanhamento diário. Decisões dele:
//   · vai na véspera do 1º dia da pessoa naquela OS, e de novo só se a OS mudar (a via DELA: os serviços dela e os
//     sem responsável — impressaoDaVia, que não muda com data, hora ou link de foto, nem com o desenho da folha:
//     v<versão>.d<versão do dado>.<dado>.<papel>, porte da via v2, F0);
//   · ligado direto, sem sombra (a chave app_settings.via_tecnico_na_agenda = 'desligado' é só para parar);
//   · a mesma via que o dono manda à EQUIPE pelo assistente: se ele já mandou esta versão à pessoa, a agenda não repete.
//     A via que o dono pede PARA SI ("me manda a via do Alex") foi para o dono, não para o Alex: não conta
//     (ORIGENS_QUE_ENTREGAM).
//
// Não mexe em nada da agenda: só LÊ a ficha que a rotina registrou (agenda_equipe_mensagens, modo 'ligado': a 'ficha'
// das 19:30, ou o 'como_foi' das 17:00 que leva a ficha de amanhã em `leva_ficha_de`) e espera a fila do WhatsApp
// entregá-la ('sent'). Ficha recusada (sem telefone, fora da janela, veto) ou ainda na fila = nada aqui. Assim a via
// nunca chega sem a ficha, e o modo da equipe (desligado/sombra/ligado) vale para a via também. A ficha sai às 19:30;
// a fila a entrega em até 5 min; a via vai no tique seguinte (19:45).
//
// As OS da ficha (NOVO-via-11, 17/11): a rotina NÃO grava `alocacao_ids` na ficha (até 17/11 a via dependia delas e
// nunca saía). A via acha as OS pelo mesmo critério que monta a ficha (agenda_equipe_ficha): as alocações da pessoa
// no dia, `estado in ('publicada','fixada')`, `tipo <> 'reserva'`, como estão AGORA. A agenda replaneja cancelando e
// recriando a alocação (agenda_alocacoes é imutável): ler o plano de agora não perde a OS num replanejamento entre a
// ficha e a via, e a OS que saiu do dia não recebe via.
//
// O envio é AUTOMÁTICO (whatsapp-send como sistema): para a equipe de campo, que não tem login, o whatsapp-send
// confere o bloqueio do número e a janela das 8h às 20h — fora dela, a via espera o próximo tique na janela.
//
// Nunca lança: devolve o resumo ou { erro } (e grava em app_error_logs).

import { chaveDeEnvio } from "../_shared/whatsapp/idempotencia.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import {
  carregarDadosDaVia,
  hojeEmBrasilia,
  type LeituraDaVia,
  linksDasFotosDaVia,
  motivoSemPapelDaPessoa,
  type PessoaDaOs,
  pessoasDaOs,
  prepararVia,
} from "../_shared/pdf/via-do-tecnico-dados.ts";
import {
  enviarDocumentoComoSistema,
  type EnviarDocumento,
  estadoDoResultado,
  mandarVia,
  registrarEnvioDaVia,
} from "../_shared/pdf/via-do-tecnico-envio.ts";
import { lerImpressao } from "../_shared/pdf/via-do-tecnico.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const CONTEXTO_DA_VIA_DA_AGENDA = "agenda_via_tecnico";
/** Chave que para o envio sozinho (o dono decidiu "ligado direto"; desligar é para emergência). */
export const CHAVE_DA_VIA_NA_AGENDA = "via_tecnico_na_agenda";
/** Cada via passa por um render de PDF (5 a 15 s): poucas por tique, o resto vai no seguinte. */
export const VIAS_POR_TIQUE = 4;
/** Depois de tantas falhas na mesma ficha e OS, desiste (registra "pulado" com o motivo). */
export const FALHAS_ATE_DESISTIR = 3;
/** A janela do envio automático do whatsapp-send (saida-automatica.ts): fora dela nem monta. */
export const JANELA = { inicio: 8, fim: 20 };
/**
 * As origens em que a via chegou à PESSOA (via_tecnico_envios.origem). `para_si` fica de fora: lá o `payee_id` é a
 * pessoa cuja via o dono pediu, mas o PDF foi para o dono. Lista fechada (e não "tudo menos para_si"): origem nova
 * não passa a contar como entregue sem alguém decidir.
 */
export const ORIGENS_QUE_ENTREGAM = ["agenda", "assistente"] as const;

export interface ResumoDaVia {
  rodou: boolean;
  motivo?: string;
  enviadas?: number;
  puladas?: number;
  falhas?: number;
  restantes?: number;
  erro?: string;
}

/** Hora cheia em Brasília. */
export function horaEmBrasilia(agora: Date): number {
  return Number(new Intl.DateTimeFormat("en-GB", { timeZone: "America/Sao_Paulo", hour: "2-digit", hourCycle: "h23" }).format(agora));
}

const DIAS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
/** "qui 26/11" para aaaa-mm-dd. */
export function rotuloDoDia(dia: string): string {
  const [a, m, d] = dia.split("-").map(Number);
  const semana = DIAS[new Date(Date.UTC(a, m - 1, d)).getUTCDay()];
  return `${semana} ${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}`;
}

/** dd/mm de um timestamp, em Brasília. */
function ddmm(ts: string): string {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit" }).format(new Date(ts));
}

/**
 * Manda ou não, para a pessoa e a OS (decisão do dono: no 1º dia e de novo só se a OS mudar). `ultima` = a última via
 * ENTREGUE a ela desta OS (ultimaViaEntregue: pela agenda ou pelo dono à equipe). `recortada` = alguma linha da OS tem
 * responsável (a legenda avisa que a via é só a parte dela).
 *
 * A impressão tem duas partes (porte da via v2, F0; a tabela do m2 §6.7): o `dado` (os campos crus da OS que a via lê)
 * e o `papel` (o que a folha diz). Só o DADO diz se a OS mudou; o papel e a versão do desenho só filtram:
 *   sem última                                         → manda ("Para qui 26/11, junto da ficha.")
 *   última no formato antigo, ou outro contrato do dado → manda ("Esta via substitui a de dd/mm."), nunca "a OS mudou"
 *   dado igual                                         → pula (mesmo com papel ou versão diferentes: mudou só a folha)
 *   dado diferente e (papel ou versão diferentes)      → manda ("A OS mudou desde a via de dd/mm: …")
 *   dado diferente, papel igual, mesma versão          → pula (a OS mudou só no que não vai ao papel)
 */
export function decidirAVia(
  ultima: { impressao: string | null; criado_em: string } | null,
  impressao: string,
  dia: string,
  recortada: boolean,
): { acao: "pular"; motivo: string } | { acao: "mandar"; complemento: string } {
  const recorte = recortada ? " Só os seus serviços e os sem responsável." : "";
  if (!ultima) return { acao: "mandar", complemento: `Para ${rotuloDoDia(dia)}, junto da ficha.${recorte}` };
  const quando = ddmm(ultima.criado_em);
  const antes = lerImpressao(ultima.impressao);
  const agora = lerImpressao(impressao);
  if (!antes || !agora || antes.versaoDoDado !== agora.versaoDoDado) {
    return { acao: "mandar", complemento: `Esta via substitui a de ${quando}.${recorte}` };
  }
  if (antes.dado === agora.dado) {
    if (antes.versao !== agora.versao) return { acao: "pular", motivo: `via em formato novo; a OS não mudou desde ${quando}` };
    if (antes.papel !== agora.papel) return { acao: "pular", motivo: "a regra do papel mudou; a OS não" };
    return { acao: "pular", motivo: `já recebeu esta via em ${quando}` };
  }
  if (antes.versao === agora.versao && antes.papel === agora.papel) {
    return { acao: "pular", motivo: "a OS mudou só no que não vai ao papel" };
  }
  return { acao: "mandar", complemento: `A OS mudou desde a via de ${quando}: esta substitui a anterior.${recorte}` };
}

/**
 * A última via ENTREGUE à pessoa nesta OS (origem agenda ou assistente, estado enviado). O "para si" não conta: o PDF
 * foi para o dono, e contá-lo faria a agenda pular o Alex com "já recebeu" sem ele ter recebido nada.
 */
export async function ultimaViaEntregue(
  db: Db,
  payeeId: string,
  os: string,
): Promise<{ impressao: string | null; criado_em: string } | null> {
  const { data, error } = await db.from("via_tecnico_envios")
    .select("impressao, criado_em").eq("payee_id", payeeId).eq("service_order_id", os)
    .in("origem", [...ORIGENS_QUE_ENTREGAM]).eq("estado", "enviado")
    .order("criado_em", { ascending: false }).limit(1).maybeSingle();
  if (error) throw new Error(`última via: ${error.message}`);
  return data ?? null;
}

/** Uma ficha registrada: a mensagem (a 'ficha' ou o 'como_foi' que a leva) e o DIA DE TRABALHO que ela anuncia. */
export type Ficha = { id: string; payee_id: string; dia: string; fila_id: string };
type Item = { ficha: Ficha; os: string };

/** Chave do dia de trabalho de uma pessoa (casa a ficha com as alocações). */
export function chaveDoDia(payeeId: string, dia: string): string {
  return `${payeeId}|${dia}`;
}

/**
 * As fichas de hoje em diante que a rotina registrou de verdade (modo 'ligado') e mandou para a fila: a 'ficha' das
 * 19:30 (o dia de trabalho é `dia`) e o 'como_foi' das 17:00 que leva a ficha de amanhã (o dia de trabalho é
 * `leva_ficha_de`; NOVO-via-12). Quem diz se foi ENTREGUE é a fila (viaDaAgenda). Lança se a leitura falhar.
 */
export async function fichasDaEquipe(db: Db, hoje: string): Promise<Ficha[]> {
  const [fichas, comoFoi] = await Promise.all([
    db.from("agenda_equipe_mensagens")
      .select("id, payee_id, dia, fila_id")
      .eq("tipo", "ficha").eq("modo", "ligado").gte("dia", hoje)
      .not("fila_id", "is", null)
      .order("dia", { ascending: true }).limit(60),
    db.from("agenda_equipe_mensagens")
      .select("id, payee_id, leva_ficha_de, fila_id")
      .eq("tipo", "como_foi").eq("modo", "ligado").gte("leva_ficha_de", hoje)
      .not("fila_id", "is", null)
      .order("leva_ficha_de", { ascending: true }).limit(60),
  ]);
  if (fichas.error) throw new Error(`fichas: ${fichas.error.message}`);
  if (comoFoi.error) throw new Error(`fichas no como foi: ${comoFoi.error.message}`);
  const todas: Ficha[] = [
    ...((fichas.data ?? []) as Array<{ id: string; payee_id: string | null; dia: string | null; fila_id: string | null }>)
      .map((f) => ({ id: f.id, payee_id: f.payee_id ?? "", dia: f.dia ?? "", fila_id: f.fila_id ?? "" })),
    ...((comoFoi.data ?? []) as Array<{ id: string; payee_id: string | null; leva_ficha_de: string | null; fila_id: string | null }>)
      .map((f) => ({ id: f.id, payee_id: f.payee_id ?? "", dia: f.leva_ficha_de ?? "", fila_id: f.fila_id ?? "" })),
  ];
  return todas.filter((f) => f.payee_id && f.dia && f.fila_id);
}

/**
 * As OS de cada (pessoa, dia) das fichas, pelo critério da ficha (agenda_equipe_ficha): alocações `publicada`/`fixada`
 * da pessoa no dia, menos as de reserva, como estão agora. Duas alocações na mesma OS (manhã e tarde) = uma OS.
 * Devolve chaveDoDia → OS em ordem. Lança se a leitura falhar.
 */
export async function osDasFichas(db: Db, fichas: Ficha[]): Promise<Map<string, string[]>> {
  const porDia = new Map<string, string[]>();
  if (!fichas.length) return porDia;
  const { data, error } = await db.from("agenda_alocacoes")
    .select("payee_id, dia, service_order_id")
    .in("payee_id", [...new Set(fichas.map((f) => f.payee_id))])
    .in("dia", [...new Set(fichas.map((f) => f.dia))])
    .in("estado", ["publicada", "fixada"])
    .neq("tipo", "reserva");
  if (error) throw new Error(`alocações: ${error.message}`);
  const juntas = new Map<string, Set<string>>();
  for (const a of (data ?? []) as Array<{ payee_id: string | null; dia: string | null; service_order_id: string | null }>) {
    if (!a.payee_id || !a.dia || !a.service_order_id) continue;
    const k = chaveDoDia(a.payee_id, a.dia);
    if (!juntas.has(k)) juntas.set(k, new Set());
    juntas.get(k)!.add(a.service_order_id);
  }
  for (const [k, oss] of juntas) porDia.set(k, [...oss].sort());
  return porDia;
}

/**
 * O que falta fazer: cada (ficha entregue, OS do dia da ficha) sem via enviada nem pulada. As que já falharam
 * FALHAS_ATE_DESISTIR vezes viram desistência.
 */
export function itensPendentes(
  fichas: Ficha[],
  entregues: Set<string>,
  osDoDia: Map<string, string[]>,
  registros: Array<{ ficha_id: string; service_order_id: string; estado: string }>,
): { fazer: Item[]; desistir: Item[] } {
  const fechados = new Set<string>();
  const falhas = new Map<string, number>();
  for (const r of registros) {
    const k = `${r.ficha_id}:${r.service_order_id}`;
    if (r.estado === "enviado" || r.estado === "pulado") fechados.add(k);
    else if (r.estado === "falhou") falhas.set(k, (falhas.get(k) ?? 0) + 1);
  }
  const fazer: Item[] = [];
  const desistir: Item[] = [];
  for (const f of fichas) {
    if (!entregues.has(f.fila_id)) continue;
    for (const os of osDoDia.get(chaveDoDia(f.payee_id, f.dia)) ?? []) {
      const k = `${f.id}:${os}`;
      if (fechados.has(k)) continue;
      if ((falhas.get(k) ?? 0) >= FALHAS_ATE_DESISTIR) desistir.push({ ficha: f, os });
      else fazer.push({ ficha: f, os });
    }
  }
  return { fazer, desistir };
}

/** As peças que montam e mandam a via (os testes trocam por falsas; em produção, as de verdade). */
export interface PecasDaVia {
  carregar: typeof carregarDadosDaVia;
  fotos: typeof linksDasFotosDaVia;
  equipe: typeof pessoasDaOs;
  preparar: typeof prepararVia;
  mandar: typeof mandarVia;
}
const PECAS_DE_VERDADE: PecasDaVia = {
  carregar: carregarDadosDaVia,
  fotos: linksDasFotosDaVia,
  equipe: pessoasDaOs,
  preparar: prepararVia,
  mandar: mandarVia,
};

export async function viaDaAgenda(
  db: Db,
  settings: Record<string, string>,
  agora: Date = new Date(),
  enviar: EnviarDocumento = enviarDocumentoComoSistema,
  trocas: Partial<PecasDaVia> = {},
): Promise<ResumoDaVia> {
  const pecas: PecasDaVia = { ...PECAS_DE_VERDADE, ...trocas };
  try {
    if ((settings[CHAVE_DA_VIA_NA_AGENDA] ?? "ligado") === "desligado") return { rodou: false, motivo: "desligada" };
    const hora = horaEmBrasilia(agora);
    if (hora < JANELA.inicio || hora >= JANELA.fim) return { rodou: false, motivo: "fora da janela" };
    const hoje = hojeEmBrasilia(agora);

    // As fichas de hoje em diante que a rotina registrou de verdade e mandou para a fila (a das 19:30 e a do "como foi").
    const fichas = await fichasDaEquipe(db, hoje);
    if (!fichas.length) return { rodou: true, enviadas: 0, puladas: 0, falhas: 0, restantes: 0 };

    const [fila, regs, osDoDia] = await Promise.all([
      db.from("whatsapp_send_queue").select("id, status").in("id", fichas.map((f) => f.fila_id)),
      db.from("via_tecnico_envios").select("ficha_id, service_order_id, estado").in("ficha_id", fichas.map((f) => f.id)),
      osDasFichas(db, fichas),
    ]);
    if (fila.error) throw new Error(`fila: ${fila.error.message}`);
    if (regs.error) throw new Error(`registro: ${regs.error.message}`);
    const entregues = new Set(((fila.data ?? []) as Array<{ id: string; status: string }>).filter((q) => q.status === "sent").map((q) => q.id));
    const { fazer, desistir } = itensPendentes(fichas, entregues, osDoDia, (regs.data ?? []) as Array<{ ficha_id: string; service_order_id: string; estado: string }>);

    let puladas = 0;
    for (const d of desistir) {
      await registrarEnvioDaVia(db, {
        service_order_id: d.os, payee_id: d.ficha.payee_id, origem: "agenda", estado: "pulado", ficha_id: d.ficha.id, dia: d.ficha.dia,
        motivo: `${FALHAS_ATE_DESISTIR} tentativas falharam; desisti desta ficha`,
      });
      puladas++;
    }
    if (!fazer.length) return { rodou: true, enviadas: 0, puladas, falhas: 0, restantes: 0 };

    const ids = [...new Set(fazer.map((i) => i.ficha.payee_id))];
    const { data: ps, error: pErr } = await db.from("payees").select("id, name, phone").in("id", ids);
    if (pErr) throw new Error(`equipe: ${pErr.message}`);
    const pessoas = new Map(((ps ?? []) as Array<{ id: string; name: string; phone: string | null }>)
      .map((p) => [p.id, { nome: p.name, telefone: String(p.phone ?? "").replace(/\D/g, "") }]));

    const leituras = new Map<string, LeituraDaVia>();
    const fotos = new Map<string, Record<string, string>>();
    const equipeDaOs = new Map<string, PessoaDaOs[]>();
    let enviadas = 0, falhas = 0, feitas = 0, vistos = 0;
    for (const item of fazer) {
      if (feitas >= VIAS_POR_TIQUE) break;
      vistos++;
      const { ficha, os } = item;
      const base = { service_order_id: os, payee_id: ficha.payee_id, origem: "agenda" as const, ficha_id: ficha.id, dia: ficha.dia };
      const pessoa = pessoas.get(ficha.payee_id);
      if (!pessoa?.telefone) {
        await registrarEnvioDaVia(db, { ...base, estado: "pulado", motivo: "sem telefone no cadastro" });
        puladas++;
        continue;
      }
      if (!leituras.has(os)) leituras.set(os, await pecas.carregar(db, os, settings));
      const lida = leituras.get(os)!;
      if (!lida.ok) {
        await registrarEnvioDaVia(db, { ...base, estado: "falhou", motivo: lida.motivo, destino: pessoa.telefone });
        falhas++;
        continue;
      }
      if (!fotos.has(os)) fotos.set(os, await pecas.fotos(db, lida.dados));
      if (!equipeDaOs.has(os)) equipeDaOs.set(os, await pecas.equipe(db, lida.dados, agora));
      const dias = equipeDaOs.get(os)!.find((p) => p.id === ficha.payee_id)?.dias ?? [ficha.dia];
      const quem = { id: ficha.payee_id, nome: pessoa.nome };
      const via = pecas.preparar(lida.dados, lida.ordem.numero, quem, fotos.get(os)!, dias);
      if (via.semServicoDaPessoa) {
        await registrarEnvioDaVia(db, { ...base, estado: "pulado", motivo: motivoSemPapelDaPessoa(), destino: pessoa.telefone });
        puladas++;
        continue;
      }
      // Já recebeu ESTA versão (pela agenda ou pelo dono, à equipe)? Então não repete. O "para si" não conta.
      const ult = await ultimaViaEntregue(db, ficha.payee_id, os);
      const decisao = decidirAVia(ult, via.impressao, ficha.dia, lida.dados.linhas.some((l) => l.responsavel_payee_id));
      if (decisao.acao === "pular") {
        await registrarEnvioDaVia(db, { ...base, estado: "pulado", motivo: decisao.motivo, destino: pessoa.telefone, impressao: via.impressao, servicos: via.servicos });
        puladas++;
        continue;
      }
      const complemento = decisao.complemento;
      feitas++;
      const r = await pecas.mandar({
        admin: db, settings, jwt: "", dados: lida.dados, ordem: lida.ordem, pessoa: quem, telefone: pessoa.telefone,
        contexto: CONTEXTO_DA_VIA_DA_AGENDA, enviar, complementoDaLegenda: complemento, linksDasFotos: fotos.get(os)!, diasNaAgenda: dias,
        chave: (impressao) => chaveDeEnvio("agenda-via", ficha.id, os, impressao),
      });
      await registrarEnvioDaVia(db, {
        ...base,
        estado: estadoDoResultado(r),
        motivo: r.ok ? null : r.motivo,
        destino: pessoa.telefone,
        impressao: r.ok ? r.impressao : via.impressao,
        servicos: r.ok ? r.servicos : via.servicos,
      });
      if (r.ok) enviadas++;
      else if (r.pulado) puladas++;
      else falhas++;
    }
    return { rodou: true, enviadas, puladas, falhas, restantes: fazer.length - vistos };
  } catch (e) {
    const mensagem = e instanceof Error ? e.message : String(e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:via-do-tecnico",
      message: `via do técnico com a ficha falhou (nada mais parou): ${mensagem}`,
      error: e,
    }).catch(() => {});
    return { rodou: false, erro: mensagem };
  }
}
