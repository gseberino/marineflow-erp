// Agenda de Produção, Fase 4 (P3, 25/10/2026; spec-fase4.md §5.3, d1): a NF-e que chegou por e-mail vira REMESSA no
// nível da nota (material_remessas: o despacho, o prazo do fornecedor e a previsão). Nada fiscal: a importação continua
// pela tela (process-nfe-xml), e a ligação item da nota ↔ linha da OS é SEMPRE pergunta ao dono (a remessa só guarda a
// data; sem resposta, nenhuma OS muda). Quem decide tudo é o banco (material_remessas_do_email, com o modo_material):
// aqui só se chama a RPC e se relê o XML das notas extraídas antes de 25/10.
//
//   · registrarRemessas(admin, id): depois do update de dados_extraidos (e no ?reextrair=1). NUNCA lança — a leitura do
//     e-mail não pode cair por causa da agenda: o erro vai para app_error_logs (context email-imap, action
//     agenda:remessas). A função ausente (a migration 20261027100300 ainda não aplicada) é silêncio, não erro.
//   · relerRemessas(admin, cnpj): ?remessas=1 — até 15 mensagens dos últimos agenda_config.remessa_dias com NF-e para a
//     HBR que ainda não viraram remessa: a de extração antiga (sem itens) baixa o XML do bucket e troca as NF-e relidas
//     pela chave (a que não baixou fica como estava; os boletos também); depois registra. Repetir até "faltam 0".

import { logEdgeError } from "../_shared/log-error.ts";
import { extrairDados, type NFeDoEmail } from "../_shared/email/dados.ts";
import type { InboundEmail } from "../_shared/email/types.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export const RPC_REMESSAS = "material_remessas_do_email";
/** Mensagens por chamada de ?remessas=1 (cada uma baixa XML do bucket: o teto de CPU da função é 2 s). */
export const LOTE_DA_RELEITURA = 15;
const BUCKET = "email-attachments";

/** A função ou a coluna ainda não existe (a migration da Fase 4 não foi aplicada): como antes, sem erro. */
function semAFase4(error: { code?: string } | null | undefined): boolean {
  return ["PGRST202", "42883", "42703", "PGRST204"].includes(String(error?.code ?? ""));
}

/** Há NF-e para a HBR nos dados do e-mail? (só então a RPC é chamada) */
export function temNotaParaEmpresa(dados: { nfes?: NFeDoEmail[] } | null | undefined): boolean {
  return (dados?.nfes ?? []).some((n) => n.para_empresa);
}

/**
 * A RPC da remessa para um e-mail. Devolve o que ela devolveu ({criadas, ja_existiam, ignoradas, sem_itens} ou
 * {pulado: true}) ou null (função ausente, ou erro registrado). Nunca lança.
 */
export async function registrarRemessas(admin: Db, emailId: string): Promise<Record<string, unknown> | null> {
  try {
    const { data, error } = await admin.rpc(RPC_REMESSAS, { p_email_message_id: emailId });
    if (error) {
      if (semAFase4(error)) return null;
      throw new Error(`${error.code ?? "?"}: ${error.message}`);
    }
    return (data ?? null) as Record<string, unknown> | null;
  } catch (e) {
    await logEdgeError(admin, {
      context: "email-imap", action: "agenda:remessas", level: "error",
      message: `remessa da NF-e do e-mail ${emailId} não registrada: ${(e as Error)?.message ?? e}`,
      details: { email_message_id: emailId }, error: e,
    });
    return null;
  }
}

/** O dia de hoje em Brasília (YYYY-MM-DD) menos n dias: o corte de remessa_dias (o banco usa p_hoje − remessa_dias). */
export function corteDaRemessa(agora: Date, dias: number): string {
  const brt = new Date(agora.getTime() - 3 * 3600_000);
  brt.setUTCDate(brt.getUTCDate() - dias);
  return brt.toISOString().slice(0, 10);
}

interface MensagemComNotas {
  id: string;
  received_at: string;
  subject: string | null;
  body_text: string | null;
  dados_extraidos: { nfes?: NFeDoEmail[]; boletos?: unknown[] } | null;
  email_attachments?: { id: string; filename: string | null; mime_type: string | null; storage_path: string | null }[];
}

/**
 * As NF-e da mensagem que ainda não viraram remessa: para a HBR, dentro do corte (a mesma regra do banco: a nota emitida
 * antes de hoje − remessa_dias é ignorada) e sem remessa. A remessa nasce também sem os itens (o XML que sumiu do
 * bucket): a releitura não fica presa numa mensagem.
 */
export function notasPendentes(m: MensagemComNotas, comRemessa: Set<string>, corte: string): NFeDoEmail[] {
  return (m.dados_extraidos?.nfes ?? []).filter((n) =>
    n.para_empresa && (n.data ?? "9999-12-31") >= corte && !comRemessa.has(n.chave)
  );
}

/**
 * As NF-e da mensagem depois da releitura: cada nota relida troca a de antes com a mesma chave; a que não foi relida (o XML
 * dela não baixou do bucket, ou não leu) FICA como estava; a relida que não estava antes entra no fim. Antes, a releitura
 * regravava só as relidas e apagava as outras calada — as notas que NotasRecebidasPorEmail e a conciliação de comprovantes
 * leem (revisão da Fase 4, C2, R2).
 */
export function juntarNotasRelidas(antigas: NFeDoEmail[], relidas: NFeDoEmail[]): NFeDoEmail[] {
  const porChave = new Map<string, NFeDoEmail>();
  for (const n of relidas) if (n.chave && !porChave.has(n.chave)) porChave.set(n.chave, n);
  const usadas = new Set<string>();
  const saida = antigas.map((n) => {
    const r = n.chave ? porChave.get(n.chave) : undefined;
    if (!r) return n;
    usadas.add(n.chave);
    return { ...n, ...r };   // o que a releitura leu vale; uma chave que só a de antes tinha fica
  });
  for (const [k, r] of porChave) if (!usadas.has(k)) saida.push(r);
  return saida;
}

/** Relê o XML das NF-e da mensagem (extração de antes de 25/10) e devolve as NF-e novas com o anexo_id; os boletos ficam. */
async function relerNotas(admin: Db, m: MensagemComNotas, cnpjEmpresa: string | null): Promise<NFeDoEmail[] | null> {
  const anexos: InboundEmail["attachments"] = [];
  const idDoIndice: string[] = [];
  for (const a of m.email_attachments ?? []) {
    if (!/xml/i.test(`${a.mime_type ?? ""} ${a.filename ?? ""}`) || !a.storage_path) continue;
    const { data: arq, error } = await admin.storage.from(BUCKET).download(a.storage_path);
    if (error || !arq) continue;
    anexos.push({ filename: a.filename, mimeType: a.mime_type, size: null, content: new Uint8Array(await arq.arrayBuffer()) });
    idDoIndice.push(a.id);
  }
  if (!anexos.length) return null;
  const email: InboundEmail = {
    messageId: null, inReplyTo: null, references: [], from: { name: null, address: "" }, to: [], cc: [],
    subject: m.subject, text: null, html: null, receivedAt: m.received_at, headers: {}, attachments: anexos, rawSize: null,
  };
  const dados = await extrairDados(email, cnpjEmpresa, null);
  if (!dados?.nfes.length) return null;
  return dados.nfes.map((n) => ({ ...n, anexo_id: idDoIndice[n.anexo_indice] ?? null } as NFeDoEmail));
}

/**
 * ?remessas=1: as NF-e dos últimos remessa_dias que ainda não viraram remessa. Com modo_material desligado (ou sem a
 * Fase 4 no banco): {pulado}. Devolve {relidas, registradas, faltam, texto}.
 */
export async function relerRemessas(admin: Db, cnpjEmpresa: string | null, agora = new Date()): Promise<Record<string, unknown>> {
  const { data: cfg, error: cErr } = await admin.from("agenda_config").select("modo_material, remessa_dias").limit(1).maybeSingle();
  if (cErr) {
    if (semAFase4(cErr)) return { pulado: true, motivo: "sem a Fase 4 no banco" };
    throw new Error(`não li agenda_config: ${cErr.message}`);
  }
  if (!cfg || cfg.modo_material === "desligado") return { pulado: true, motivo: "modo_material desligado" };
  const dias = Number(cfg.remessa_dias ?? 30);
  const corte = corteDaRemessa(agora, dias);

  const { data: msgs, error } = await admin.from("email_messages")
    .select("id, received_at, subject, body_text, dados_extraidos, email_attachments(id, filename, mime_type, storage_path)")
    .not("dados_extraidos", "is", null)
    .gte("received_at", new Date(agora.getTime() - (dias + 1) * 86400_000).toISOString())
    .order("received_at", { ascending: true }).limit(500);
  if (error) throw new Error(`não li email_messages: ${error.message}`);
  const comNotas = ((msgs ?? []) as MensagemComNotas[]).filter((m) => temNotaParaEmpresa(m.dados_extraidos));
  const chaves = [...new Set(comNotas.flatMap((m) => (m.dados_extraidos?.nfes ?? []).map((n) => n.chave)))];
  const comRemessa = new Set<string>();
  if (chaves.length) {
    const { data: rem, error: rErr } = await admin.from("material_remessas").select("nfe_chave").in("nfe_chave", chaves);
    if (rErr) throw new Error(`não li material_remessas: ${rErr.message}`);
    for (const r of (rem ?? []) as { nfe_chave: string }[]) comRemessa.add(r.nfe_chave);
  }
  const pendentes = comNotas.filter((m) => notasPendentes(m, comRemessa, corte).length > 0);

  let relidas = 0, registradas = 0;
  for (const m of pendentes.slice(0, LOTE_DA_RELEITURA)) {
    if (notasPendentes(m, comRemessa, corte).some((n) => !("itens" in n))) {
      const novas = await relerNotas(admin, m, cnpjEmpresa);
      if (novas) {
        // Só as relidas mudam: a nota cujo XML não baixou fica como estava (C2, R2).
        const nfes = juntarNotasRelidas(m.dados_extraidos?.nfes ?? [], novas);
        const { error: uErr } = await admin.from("email_messages")
          .update({ dados_extraidos: { ...(m.dados_extraidos ?? {}), nfes } }).eq("id", m.id);
        if (uErr) throw new Error(`não regravei as NF-e de ${m.id}: ${uErr.message}`);
        relidas++;
      }
    }
    if (await registrarRemessas(admin, m.id)) registradas++;
  }
  const faltam = Math.max(0, pendentes.length - LOTE_DA_RELEITURA);
  return { relidas, registradas, faltam, texto: faltam ? `faltam ${faltam} (chame de novo)` : "nada a reler" };
}
