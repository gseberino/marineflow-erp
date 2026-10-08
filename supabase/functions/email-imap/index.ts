// Edge Function: email-imap — lê as caixas de e-mail da HBR a cada 10 minutos (08/10/2026).
//
// Pedido do dono (07/10): o assistente lê financeiro@ e gustavo@hbrmarine.com.br. Etapas 1+2 do
// plano (plans/marineflow-email-agente.md, agora pela rota IMAP):
//   1. espelho — traz o que chegou desde a última leitura (na primeira vez, os últimos 90 dias),
//      grava em email_messages com os anexos no bucket privado e liga o remetente ao cadastro;
//   2. triagem — só do que chegou nas últimas 48 h (o histórico não gera aviso nem gasta IA):
//      classificador em quarentena (_shared/email/triage.ts) e aviso no WhatsApp dos URGENTES,
//      no máximo 3 por dia.
//
// A caixa do dono não muda: EXAMINE (modo leitura) e BODY.PEEK (não marca como lida) — ver
// _shared/email/imap.ts. A senha vem do segredo cujo NOME está em email_accounts.secret_name.
//
// Chamadores: pg_cron (x-cron-secret). `?diagnostico=1` só conecta e conta, sem gravar nada.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ClienteImap, dataImap, internalDateParaIso } from "../_shared/email/imap.ts";
import { mimeParaInbound } from "../_shared/email/mime.ts";
import { applySenderRules, persistInboundEmail, storagePathFor } from "../_shared/email/store.ts";
import { matchSender, type MatchCandidate } from "../_shared/email/sender-match.ts";
import { triageEmail, type Triage } from "../_shared/email/triage.ts";
import { MAX_URGENTES_PADRAO } from "../_shared/email/digest.ts";
import { displaySender } from "../_shared/email/normalize.ts";
import { extrairDados, fornecedorPelaNota } from "../_shared/email/dados.ts";
import type { InboundEmail } from "../_shared/email/types.ts";
import { extractText, getDocumentProxy } from "npm:unpdf@0.12.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};
const jr = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

/** Por rodada e por caixa: o limite de CPU da função (2 s) não comporta muito mais. */
const LOTE = 20;
/** Tempo total da rodada (o teto da função é 150 s). */
const ORCAMENTO_MS = 100_000;
/** Mensagem acima disso: guarda só o cabeçalho (o corpo estouraria a memória da função). */
const MAX_BYTES_MENSAGEM = 12 * 1024 * 1024;
const MAX_BYTES_ANEXO = 20 * 1024 * 1024;
/** Só o que chegou nesse intervalo é classificado e pode virar aviso. */
const JANELA_DA_TRIAGEM_MS = 48 * 3600_000;
const BUCKET = "email-attachments";
/** PDFs lidos por rodada (boleto): a leitura gasta CPU, e o teto da função é 2 s. */
const MAX_PDFS_POR_RODADA = 4;

async function lerPdf(bytes: Uint8Array): Promise<string> {
  const doc = await getDocumentProxy(bytes);
  const { text } = await extractText(doc, { mergePages: true });
  return Array.isArray(text) ? text.join("\n") : String(text ?? "");
}

// deno-lint-ignore no-explicit-any
type Db = any;

async function candidatos(admin: Db): Promise<MatchCandidate[]> {
  const out: MatchCandidate[] = [];
  for (const [tabela, kind] of [["clients", "client"], ["suppliers", "supplier"]] as const) {
    for (let ini = 0; ini < 20000; ini += 1000) {
      const { data, error } = await admin.from(tabela).select("id, name, email").not("email", "is", null).order("id").range(ini, ini + 999);
      if (error) throw new Error(`não li ${tabela}: ${error.message}`);
      for (const r of data ?? []) out.push({ id: r.id, name: r.name, email: r.email, kind });
      if ((data ?? []).length < 1000) break;
    }
  }
  return out;
}

/** CNPJ (só dígitos) → fornecedor, para ligar o e-mail pela NF-e anexa. */
async function fornecedoresPorCnpj(admin: Db): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  for (let ini = 0; ini < 20000; ini += 1000) {
    const { data, error } = await admin.from("suppliers").select("id, cnpj_cpf").not("cnpj_cpf", "is", null).order("id").range(ini, ini + 999);
    if (error) throw new Error(`não li suppliers: ${error.message}`);
    for (const r of data ?? []) {
      const d = String(r.cnpj_cpf ?? "").replace(/\D/g, "");
      if (d.length === 14) out.set(d, r.id);
    }
    if ((data ?? []).length < 1000) break;
  }
  return out;
}

/** Sem cadastro pelo remetente: liga pelo CNPJ do emitente da NF-e (documento identifica). */
function ligacaoPelaNota(dados: Parameters<typeof fornecedorPelaNota>[0], porCnpj: Map<string, string>) {
  const id = fornecedorPelaNota(dados, porCnpj);
  return id ? { supplier_id: id, match_confidence: 1, match_reason: "nfe_cnpj" } : {};
}

/** Urgentes já avisados hoje (Brasília), para o teto. */
async function avisadosHoje(admin: Db): Promise<number> {
  const inicio = new Date(Date.now() - 3 * 3600_000);
  inicio.setUTCHours(0, 0, 0, 0);
  const desde = new Date(inicio.getTime() + 3 * 3600_000).toISOString();
  const { count } = await admin.from("email_messages").select("id", { count: "exact", head: true }).gte("alerted_at", desde);
  return count ?? 0;
}

async function avisarUrgente(admin: Db, conta: string, remetente: string, assunto: string | null, motivo: string | null, fraude: boolean) {
  const { data: quem } = await admin.from("app_users").select("phone_normalized")
    .eq("active", true).eq("ai_whatsapp_enabled", true).in("role", ["admin"]).not("phone_normalized", "is", null);
  const texto = [
    fraude ? "🚨 *E-mail urgente — possível GOLPE*" : "📧 *E-mail urgente*",
    `De: ${remetente} (para ${conta})`,
    assunto ? `Assunto: ${assunto.slice(0, 120)}` : null,
    motivo ? `Por quê: ${motivo.slice(0, 200)}` : null,
    fraude ? "Não pague nem altere dados bancários antes de confirmar por telefone." : null,
    "Me peça \"lê o último e-mail urgente\" para ver o texto.",
  ].filter(Boolean).join("\n");
  const rows = ((quem ?? []) as { phone_normalized: string }[]).map((u) => ({ phone_normalized: u.phone_normalized, message: texto, source: "email_urgente", priority: 2 }));
  if (rows.length) await admin.from("whatsapp_send_queue").insert(rows);
}

/**
 * `?reextrair=1`: e-mails já guardados com anexo e sem dados extraídos (os que entraram antes da
 * etapa 4) — relê os anexos do bucket, sem ir à caixa de novo. Até 15 por chamada.
 */
async function reextrair(admin: Db, cnpjEmpresa: string | null): Promise<Record<string, number>> {
  const porCnpj = await fornecedoresPorCnpj(admin);
  const { data: msgs, error } = await admin.from("email_messages")
    .select("id, subject, body_text, received_at, client_id, supplier_id, email_attachments(id, filename, mime_type, storage_path)")
    .eq("has_attachments", true).is("dados_extraidos", null).order("received_at", { ascending: false }).limit(15);
  if (error) throw new Error(error.message);
  let lidos = 0, comDados = 0, pdfs = 0;
  for (const m of (msgs ?? []) as any[]) {
    const anexos: InboundEmail["attachments"] = [];
    const idDoIndice: string[] = [];
    for (const a of (m.email_attachments ?? []) as any[]) {
      const ehUtil = /xml|pdf/i.test(`${a.mime_type ?? ""} ${a.filename ?? ""}`);
      let content: Uint8Array | null = null;
      if (ehUtil && a.storage_path) {
        const { data: arq } = await admin.storage.from(BUCKET).download(a.storage_path);
        if (arq) content = new Uint8Array(await arq.arrayBuffer());
      }
      anexos.push({ filename: a.filename, mimeType: a.mime_type, size: content?.length ?? null, content });
      idDoIndice.push(a.id);
    }
    const usarPdf = anexos.some((a) => a.content && (a.mimeType ?? "").includes("pdf")) && pdfs < MAX_PDFS_POR_RODADA;
    if (usarPdf) pdfs++;
    const email: InboundEmail = {
      messageId: null, inReplyTo: null, references: [], from: { name: null, address: "" }, to: [], cc: [],
      subject: m.subject, text: m.body_text, html: null, receivedAt: m.received_at, headers: {}, attachments: anexos, rawSize: null,
    };
    const dados = await extrairDados(email, cnpjEmpresa, usarPdf ? lerPdf : null);
    // {} marca "já relido, nada encontrado" (sem isso a mesma mensagem voltaria toda vez).
    const gravar = dados ? { ...dados, nfes: dados.nfes.map((n) => ({ ...n, anexo_id: idDoIndice[n.anexo_indice] ?? null })) } : {};
    const ligar = m.client_id || m.supplier_id ? {} : ligacaoPelaNota(dados, porCnpj);
    await admin.from("email_messages").update({ dados_extraidos: gravar, ...ligar }).eq("id", m.id);
    lidos++;
    if (dados) comDados++;
  }
  return { relidos: lidos, com_dados: comDados };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const negado = verificarCronSecret(req, corsHeaders, "email-imap");
  if (negado) return negado;

  const inicio = Date.now();
  const diagnostico = new URL(req.url).searchParams.get("diagnostico") === "1";
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const { data: contas, error: cErr } = await admin.from("email_accounts")
    .select("id, address, label, imap_host, imap_port, secret_name, history_days, imap_uidvalidity, imap_last_uid")
    .eq("active", true).not("secret_name", "is", null).not("imap_host", "is", null);
  if (cErr) return jr({ error: `não li as caixas: ${cErr.message}` }, 500);

  const { data: regras } = await admin.from("email_sender_rules").select("pattern, action");
  const { data: cfgCnpj } = await admin.from("app_settings").select("value").eq("key", "cnpj").maybeSingle();
  const cnpjEmpresa = cfgCnpj?.value ? String(cfgCnpj.value) : null;
  let pdfsLidos = 0;
  if (new URL(req.url).searchParams.get("reextrair") === "1") {
    try {
      return jr({ ok: true, ...(await reextrair(admin, cnpjEmpresa)), ms: Date.now() - inicio });
    } catch (e) {
      return jr({ error: String((e as Error)?.message ?? e) }, 500);
    }
  }
  let cands: MatchCandidate[] | null = null;
  let porCnpj: Map<string, string> | null = null;
  let jaAvisados = diagnostico ? 0 : await avisadosHoje(admin);
  const resultados: Record<string, unknown>[] = [];

  for (const conta of (contas ?? []) as any[]) {
    const r: Record<string, unknown> = { caixa: conta.address, novos: 0, repetidos: 0, triados: 0, avisados: 0, erros: 0 };
    resultados.push(r);
    const senha = Deno.env.get(String(conta.secret_name));
    if (!senha) {
      r.erro = `segredo ${conta.secret_name} não cadastrado`;
      await admin.from("email_accounts").update({ last_sync_at: new Date().toISOString(), last_sync_status: "error", last_sync_message: String(r.erro) }).eq("id", conta.id);
      continue;
    }
    let cli: ClienteImap | null = null;
    try {
      cli = await ClienteImap.conectar(conta.imap_host, conta.imap_port ?? 993);
      await cli.login(conta.address, senha);
      const caixa = await cli.examinar("INBOX");
      r.na_caixa = caixa.existem;

      // Primeira leitura (ou caixa renumerada): os últimos N dias. Depois: só UIDs novos.
      const renumerada = conta.imap_uidvalidity != null && caixa.uidValidity != null && Number(conta.imap_uidvalidity) !== caixa.uidValidity;
      const ultimo = renumerada ? null : (conta.imap_last_uid != null ? Number(conta.imap_last_uid) : null);
      const uids = ultimo == null
        ? await cli.buscarUids(`SINCE ${dataImap(new Date(Date.now() - (conta.history_days ?? 90) * 86400_000))}`)
        : (await cli.buscarUids(`UID ${ultimo + 1}:*`)).filter((u) => u > ultimo);
      r.pendentes = uids.length;
      if (diagnostico) { r.uidvalidity = caixa.uidValidity; continue; }

      cands ??= await candidatos(admin);
      porCnpj ??= await fornecedoresPorCnpj(admin);
      let cursor = ultimo;
      for (const uid of uids.slice(0, LOTE)) {
        if (Date.now() - inicio > ORCAMENTO_MS) { r.parou = "tempo da rodada"; break; }
        const meta = await cli.tamanho(uid);
        const grande = (meta.tamanho ?? 0) > MAX_BYTES_MENSAGEM;
        const bruto = await cli.baixar(uid, grande);
        if (!bruto) { cursor = uid; continue; }
        const email = await mimeParaInbound(bruto, { recebidoEmFallback: internalDateParaIso(meta.internalDate), tamanho: meta.tamanho });
        if (grande) email.attachments = [];

        const match = matchSender(email.from.address, email.from.name, cands);
        const salvo = await persistInboundEmail(admin, email, conta.id, match);
        if (salvo.status === "duplicate") { r.repetidos = Number(r.repetidos) + 1; cursor = uid; continue; }
        if (salvo.status === "error") throw new Error(`gravar e-mail UID ${uid}: ${salvo.error}`);
        r.novos = Number(r.novos) + 1;
        const id = salvo.messageId!;
        await admin.from("email_messages").update({ imap_uid: uid, imap_uidvalidity: caixa.uidValidity }).eq("id", id);

        // Anexos no bucket privado, no caminho que a linha já registrou.
        for (const [i, a] of email.attachments.entries()) {
          if (!a.content || a.content.length > MAX_BYTES_ANEXO) continue;
          const { error: upErr } = await admin.storage.from(BUCKET)
            .upload(storagePathFor(id, a.filename, i), a.content, { contentType: a.mimeType ?? "application/octet-stream", upsert: true });
          if (upErr) console.warn("[email-imap] anexo não subiu:", upErr.message);
        }

        // Etapa 4 (08/10/2026): NF-e anexa e boleto, conferidos por DV. Só informa — a NF-e aparece
        // em Entrada de Mercadoria › "Notas recebidas por e-mail"; nada vira lançamento sozinho.
        try {
          const temPdf = email.attachments.some((a) => (a.mimeType ?? "").includes("pdf"));
          const usarPdf = temPdf && pdfsLidos < MAX_PDFS_POR_RODADA;
          if (usarPdf) pdfsLidos++;
          const dados = await extrairDados(email, cnpjEmpresa, usarPdf ? lerPdf : null);
          if (dados) {
            const { data: linhas } = await admin.from("email_attachments").select("id, storage_path").eq("message_id", id);
            const idPorCaminho = new Map(((linhas ?? []) as { id: string; storage_path: string }[]).map((l) => [l.storage_path, l.id]));
            const nfes = dados.nfes.map((n) => ({
              ...n,
              anexo_id: idPorCaminho.get(storagePathFor(id, email.attachments[n.anexo_indice]?.filename ?? null, n.anexo_indice)) ?? null,
            }));
            const ligar = match ? {} : ligacaoPelaNota(dados, porCnpj);
            await admin.from("email_messages").update({ dados_extraidos: { ...dados, nfes }, ...ligar }).eq("id", id);
          }
        } catch (e) {
          console.warn("[email-imap] extração de NF-e/boleto falhou:", (e as Error)?.message ?? e);
        }

        // Triagem só do que é recente: o histórico entra calado.
        const recente = Date.now() - new Date(email.receivedAt).getTime() < JANELA_DA_TRIAGEM_MS;
        const regra = applySenderRules(email.from.address, (regras ?? []) as { pattern: string; action: string }[]);
        if (recente || regra) {
          let t: Triage = regra === "ignore_always"
            ? { classe: "ignore", confianca: 1, evidencia: "", motivo: "remetente silenciado", alertaFraude: false, rebaixada: false, deterministica: true }
            : await triageEmail(email);
          if (regra === "always_notify" && t.classe === "ignore") t = { ...t, classe: "notify", motivo: "remetente marcado para sempre avisar" };
          await admin.from("email_messages").update({
            triage_class: t.classe, triage_confidence: t.confianca, triage_evidence: t.evidencia || null,
            triage_reason: t.motivo, triage_fraud_alert: t.alertaFraude, triaged_at: new Date().toISOString(),
            muted: regra === "ignore_always",
          }).eq("id", id);
          r.triados = Number(r.triados) + 1;
          if (recente && t.classe === "urgent" && jaAvisados < MAX_URGENTES_PADRAO) {
            const remetente = match?.name ?? displaySender(email.from);
            await avisarUrgente(admin, conta.address, remetente, email.subject, t.motivo, t.alertaFraude);
            await admin.from("email_messages").update({ alerted_at: new Date().toISOString() }).eq("id", id);
            jaAvisados++;
            r.avisados = Number(r.avisados) + 1;
          }
        }
        cursor = uid;
        // Cursor gravado a cada mensagem: se a rodada cair no meio, a próxima continua daqui.
        await admin.from("email_accounts").update({ imap_last_uid: cursor, imap_uidvalidity: caixa.uidValidity }).eq("id", conta.id);
      }
      if (cursor != null && cursor !== ultimo) {
        await admin.from("email_accounts").update({ imap_last_uid: cursor, imap_uidvalidity: caixa.uidValidity }).eq("id", conta.id);
      } else if (ultimo == null && uids.length === 0) {
        // Primeira leitura sem nada nos últimos dias: o cursor parte do maior UID que existe.
        const todos = await cli.buscarUids("ALL");
        if (todos.length) await admin.from("email_accounts").update({ imap_last_uid: todos[todos.length - 1], imap_uidvalidity: caixa.uidValidity }).eq("id", conta.id);
      }
      r.faltam = Math.max(0, uids.length - LOTE);
      await admin.from("email_accounts").update({
        last_sync_at: new Date().toISOString(), last_sync_status: "ok",
        last_sync_message: `${r.novos} novo(s)${Number(r.faltam) ? ` · faltam ${r.faltam} (continua na próxima rodada)` : ""}`,
      }).eq("id", conta.id);
    } catch (e) {
      r.erros = Number(r.erros) + 1;
      r.erro = String((e as Error)?.message ?? e).slice(0, 300);
      await admin.from("email_accounts").update({ last_sync_at: new Date().toISOString(), last_sync_status: "error", last_sync_message: String(r.erro) }).eq("id", conta.id);
    } finally {
      await cli?.sair();
    }
  }

  const comErro = resultados.filter((x) => x.erro);
  return jr({ ok: comErro.length === 0, diagnostico, resultados, ms: Date.now() - inicio }, comErro.length && comErro.length === resultados.length ? 502 : 200);
});
