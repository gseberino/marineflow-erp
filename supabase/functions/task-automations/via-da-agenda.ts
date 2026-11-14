// A via do técnico junto da ficha das 19:30 (13/11/2026).
//
// Pedido do dono: o agente da agenda manda a via do técnico em PDF no acompanhamento diário. Decisões dele:
//   · vai na véspera do 1º dia da pessoa naquela OS, e de novo só se a OS mudar (a via DELA: os serviços dela e os
//     sem responsável — impressaoDaVia, que não muda com data, hora ou link de foto);
//   · ligado direto, sem sombra (a chave app_settings.via_tecnico_na_agenda = 'desligado' é só para parar);
//   · a mesma via que o dono manda pelo assistente: se ele já mandou esta versão, a agenda não repete.
//
// Não mexe em nada da agenda: só LÊ a ficha que a rotina registrou (agenda_equipe_mensagens, tipo 'ficha', modo
// 'ligado') e espera a fila do WhatsApp entregá-la ('sent'). Ficha recusada (sem telefone, fora da janela, veto)
// ou ainda na fila = nada aqui. Assim a via nunca chega sem a ficha, e o modo da equipe (desligado/sombra/ligado)
// vale para a via também. A ficha sai às 19:30; a fila a entrega em até 5 min; a via vai no tique seguinte (19:45).
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
 * ENVIADA a ela desta OS (pela agenda ou pelo assistente). `recortada` = alguma linha da OS tem responsável (a legenda
 * avisa que a via é só a parte dela).
 */
export function decidirAVia(
  ultima: { impressao: string | null; criado_em: string } | null,
  impressao: string,
  dia: string,
  recortada: boolean,
): { acao: "pular"; motivo: string } | { acao: "mandar"; complemento: string } {
  if (ultima?.impressao && ultima.impressao === impressao) {
    return { acao: "pular", motivo: `já recebeu esta via em ${ddmm(ultima.criado_em)}` };
  }
  const recorte = recortada ? " Só os seus serviços e os sem responsável." : "";
  return {
    acao: "mandar",
    complemento: ultima
      ? `A OS mudou desde a via de ${ddmm(ultima.criado_em)}: esta substitui a anterior.${recorte}`
      : `Para ${rotuloDoDia(dia)}, junto da ficha.${recorte}`,
  };
}

type Ficha = { id: string; payee_id: string; dia: string; fila_id: string; alocacao_ids: string[] | null };
type Item = { ficha: Ficha; os: string };

/**
 * O que falta fazer: cada (ficha entregue, OS da ficha) sem via enviada nem pulada. As que já falharam
 * FALHAS_ATE_DESISTIR vezes viram desistência.
 */
export function itensPendentes(
  fichas: Ficha[],
  entregues: Set<string>,
  osDaAlocacao: Map<string, string>,
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
    const oss = [...new Set((f.alocacao_ids ?? []).map((a) => osDaAlocacao.get(a)).filter((o): o is string => !!o))].sort();
    for (const os of oss) {
      const k = `${f.id}:${os}`;
      if (fechados.has(k)) continue;
      if ((falhas.get(k) ?? 0) >= FALHAS_ATE_DESISTIR) desistir.push({ ficha: f, os });
      else fazer.push({ ficha: f, os });
    }
  }
  return { fazer, desistir };
}

export async function viaDaAgenda(
  db: Db,
  settings: Record<string, string>,
  agora: Date = new Date(),
  enviar: EnviarDocumento = enviarDocumentoComoSistema,
): Promise<ResumoDaVia> {
  try {
    if ((settings[CHAVE_DA_VIA_NA_AGENDA] ?? "ligado") === "desligado") return { rodou: false, motivo: "desligada" };
    const hora = horaEmBrasilia(agora);
    if (hora < JANELA.inicio || hora >= JANELA.fim) return { rodou: false, motivo: "fora da janela" };
    const hoje = hojeEmBrasilia(agora);

    // As fichas de hoje em diante que a rotina registrou de verdade e mandou para a fila.
    const { data: fs, error: fErr } = await db.from("agenda_equipe_mensagens")
      .select("id, payee_id, dia, fila_id, alocacao_ids")
      .eq("tipo", "ficha").eq("modo", "ligado").gte("dia", hoje)
      .not("fila_id", "is", null)
      .order("dia", { ascending: true }).limit(60);
    if (fErr) throw new Error(`fichas: ${fErr.message}`);
    const fichas = ((fs ?? []) as Ficha[]).filter((f) => f.payee_id && (f.alocacao_ids ?? []).length);
    if (!fichas.length) return { rodou: true, enviadas: 0, puladas: 0, falhas: 0, restantes: 0 };

    const [fila, regs, alocs] = await Promise.all([
      db.from("whatsapp_send_queue").select("id, status").in("id", fichas.map((f) => f.fila_id)),
      db.from("via_tecnico_envios").select("ficha_id, service_order_id, estado").in("ficha_id", fichas.map((f) => f.id)),
      db.from("agenda_alocacoes").select("id, service_order_id, tipo").in("id", [...new Set(fichas.flatMap((f) => f.alocacao_ids ?? []))]),
    ]);
    if (fila.error) throw new Error(`fila: ${fila.error.message}`);
    if (regs.error) throw new Error(`registro: ${regs.error.message}`);
    if (alocs.error) throw new Error(`alocações: ${alocs.error.message}`);
    const entregues = new Set(((fila.data ?? []) as Array<{ id: string; status: string }>).filter((q) => q.status === "sent").map((q) => q.id));
    const osDaAlocacao = new Map(
      ((alocs.data ?? []) as Array<{ id: string; service_order_id: string; tipo: string }>)
        .filter((a) => a.tipo !== "reserva").map((a) => [a.id, a.service_order_id]),
    );
    const { fazer, desistir } = itensPendentes(fichas, entregues, osDaAlocacao, (regs.data ?? []) as Array<{ ficha_id: string; service_order_id: string; estado: string }>);

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
      if (!leituras.has(os)) leituras.set(os, await carregarDadosDaVia(db, os, settings));
      const lida = leituras.get(os)!;
      if (!lida.ok) {
        await registrarEnvioDaVia(db, { ...base, estado: "falhou", motivo: lida.motivo, destino: pessoa.telefone });
        falhas++;
        continue;
      }
      if (!fotos.has(os)) fotos.set(os, await linksDasFotosDaVia(db, lida.dados));
      if (!equipeDaOs.has(os)) equipeDaOs.set(os, await pessoasDaOs(db, lida.dados, agora));
      const dias = equipeDaOs.get(os)!.find((p) => p.id === ficha.payee_id)?.dias ?? [ficha.dia];
      const quem = { id: ficha.payee_id, nome: pessoa.nome };
      const via = prepararVia(lida.dados, lida.ordem.numero, quem, fotos.get(os)!, dias);
      if (via.semServicoDaPessoa) {
        await registrarEnvioDaVia(db, { ...base, estado: "pulado", motivo: "todos os serviços da OS estão com outra pessoa", destino: pessoa.telefone });
        puladas++;
        continue;
      }
      // Já recebeu ESTA versão (pela agenda ou pelo dono, pelo assistente)? Então não repete.
      const { data: ult, error: uErr } = await db.from("via_tecnico_envios")
        .select("impressao, criado_em").eq("payee_id", ficha.payee_id).eq("service_order_id", os).eq("estado", "enviado")
        .order("criado_em", { ascending: false }).limit(1).maybeSingle();
      if (uErr) throw new Error(`última via: ${uErr.message}`);
      const decisao = decidirAVia(ult ?? null, via.impressao, ficha.dia, lida.dados.linhas.some((l) => l.responsavel_payee_id));
      if (decisao.acao === "pular") {
        await registrarEnvioDaVia(db, { ...base, estado: "pulado", motivo: decisao.motivo, destino: pessoa.telefone, impressao: via.impressao, servicos: via.servicos });
        puladas++;
        continue;
      }
      const complemento = decisao.complemento;
      feitas++;
      const r = await mandarVia({
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
