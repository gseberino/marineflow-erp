// Edge Function: fiscal-email
// Envia a NF-e autorizada (DANFE em PDF + XML) ao cliente por e-mail, via SMTP do
// próprio domínio (ex.: GoDaddy → financeiro@hbrmarine.com.br). Admin-only.
//
// Configuração por Secrets do Supabase (o app nunca guarda a senha):
//   SMTP_HOST      ex.: smtpout.secureserver.net (GoDaddy Professional Email)
//                       ou smtp.office365.com (GoDaddy Microsoft 365)
//   SMTP_PORT      465 (SSL, padrão) ou 587 (STARTTLS)
//   SMTP_USER      o e-mail completo (financeiro@hbrmarine.com.br)
//   SMTP_PASS      a senha (ou senha de aplicativo)
//   SMTP_FROM      opcional; remetente (default = SMTP_USER)
//   SMTP_FROM_NAME opcional; nome exibido (default = "HBR Marine")
//
// SMTP via Nodemailer (não denomailer): servidores rígidos como o GoDaddy
// (smtpout.secureserver.net) rejeitam mensagens com "bare LF" (quebras \n sem
// \r) — erro 552 "violating 822.bis section 2.3". O denomailer 1.6.0 deixa o \n
// do corpo passar sem virar \r\n e ainda manda o base64 do anexo numa linha só
// (>998 chars). O Nodemailer normaliza o corpo para CRLF e quebra o base64 em
// linhas de 76 — mensagem conforme a RFC 5322.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider } from "../_shared/fiscal/factory.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import nodemailer from "npm:nodemailer@6.9.10";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
async function requireAdmin(admin: any, req: Request): Promise<{ id: string } | null> {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data: userData, error } = await admin.auth.getUser(jwt);
  if (error || !userData?.user) return null;
  const { data: profile } = await admin
    .from("app_users")
    .select("id, role, active")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!profile || profile.role !== "admin" || profile.active === false) return null;
  return { id: profile.id };
}

// ArrayBuffer → base64 (anexos do denomailer). Faz em blocos para não estourar a
// pilha em arquivos grandes.
function toBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

function isEmail(s: string): boolean {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // deno-lint-ignore no-explicit-any
  const body = (await req.json().catch(() => null)) as any;
  if (!body) return jr({ error: "invalid_json" }, 400);

  const caller = await requireAdmin(admin, req);
  if (!caller) return jr({ error: "unauthorized" }, 401);

  try {
    const documentId: string | undefined = body.document_id;
    if (!documentId) return jr({ error: "document_id é obrigatório" }, 422);

    const { data: doc, error: docErr } = await admin
      .from("issued_fiscal_documents")
      .select("*")
      .eq("id", documentId)
      .maybeSingle();
    if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
    if (!doc) return jr({ error: "Documento não encontrado" }, 404);
    if (doc.status !== "authorized") {
      return jr({ error: `Só é possível enviar por e-mail uma nota AUTORIZADA (status atual: ${doc.status}).` }, 422);
    }
    if (!doc.provider_document_id) return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);

    // NFS-e e NF-e compartilham este envio; o que muda é o vocabulário (documento, PDF) e o
    // lugar do e-mail no payload (NF-e tem `recipient`, NFS-e tem `taker`).
    const ehNfse = doc.document_type === "nfse";
    const nomeDoc = ehNfse ? "NFS-e" : "NF-e";
    const nomePdf = ehNfse ? "DANFSe" : "DANFE";
    const prefixoArquivo = ehNfse ? "NFSe" : "NFe";
    // NFS-e: o número que o cliente conhece é o NACIONAL (gerado pela Sefin), não o RPS
    // que reservamos. Ele chega via status/webhook e fica no provider_status.
    const ps = (doc.provider_status ?? {}) as Record<string, unknown>;
    const numeroNacional = ehNfse
      ? (String(ps["nfse_number"] ?? ps["display_number"] ?? "").trim() || null)
      : null;
    const numeroArquivo = numeroNacional ?? String(doc.number);

    // Destinatário: e-mail explícito no corpo → e-mail do payload → e-mail do cliente.
    let to = String(body.to ?? "").trim();
    if (!to) {
      to = String(
        doc.request_payload?.recipient?.email ?? doc.request_payload?.taker?.email ?? "",
      ).trim();
    }
    if (!to && doc.client_id) {
      const { data: cli } = await admin.from("clients").select("email").eq("id", doc.client_id).maybeSingle();
      to = String(cli?.email ?? "").trim();
    }
    if (!to || !isEmail(to)) {
      return jr({ error: "E-mail do destinatário não encontrado ou inválido. Informe um e-mail ou preencha no cadastro do cliente." }, 422);
    }

    // Baixa PDF (obrigatório) + XML autorizado (opcional) da Contora, autenticado.
    const provider = createFiscalProvider();
    const arts = await provider.listArtifacts(doc.document_type, doc.provider_document_id);
    if (!arts.ok) return jr({ error: "Falha ao listar artefatos na Contora: " + arts.error }, 502);
    // Tipos por família: NF-e = pdf_danfe/xml_authorized; NFS-e = pdf_nfse/xml_nfse.
    const pdfTipos = ehNfse ? ["pdf_nfse", "pdf_danfe"] : ["pdf_danfe"];
    const xmlTipos = ehNfse ? ["xml_nfse", "xml_authorized"] : ["xml_authorized"];
    const pdfArt = arts.data.find((a) => pdfTipos.includes(a.type) && a.available && a.downloadUrl);
    const xmlArt = arts.data.find((a) => xmlTipos.includes(a.type) && a.available && a.downloadUrl);
    if (!pdfArt?.downloadUrl) {
      return jr({ error: `O ${nomePdf} (PDF) ainda não está disponível para esta nota. Tente 'Atualizar status' e reenvie.` }, 502);
    }

    // deno-lint-ignore no-explicit-any
    const attachments: any[] = [];
    const pdfFetched = await provider.fetchArtifact(pdfArt.downloadUrl);
    if (!pdfFetched.ok) return jr({ error: `Falha ao baixar o ${nomePdf}: ` + pdfFetched.error }, 502);
    attachments.push({
      filename: `${prefixoArquivo}-${numeroArquivo}.pdf`,
      content: toBase64(pdfFetched.data.bytes),
      encoding: "base64",
      contentType: "application/pdf",
    });

    const includeXml = body.include_xml !== false; // default: inclui o XML
    if (includeXml && xmlArt?.downloadUrl) {
      const xmlFetched = await provider.fetchArtifact(xmlArt.downloadUrl);
      if (xmlFetched.ok) {
        attachments.push({
          filename: `${prefixoArquivo}-${numeroArquivo}.xml`,
          content: toBase64(xmlFetched.data.bytes),
          encoding: "base64",
          contentType: "application/xml",
        });
      }
    }

    // Configuração SMTP (Secrets).
    const host = Deno.env.get("SMTP_HOST");
    const user = Deno.env.get("SMTP_USER");
    const pass = Deno.env.get("SMTP_PASS");
    if (!host || !user || !pass) {
      return jr({ error: "Envio por e-mail não configurado: faltam os Secrets SMTP_HOST, SMTP_USER e SMTP_PASS no Supabase." }, 422);
    }
    const port = Number(Deno.env.get("SMTP_PORT") ?? 465);
    const fromEmail = Deno.env.get("SMTP_FROM") || user;
    const fromName = Deno.env.get("SMTP_FROM_NAME") || "HBR Marine";

    const numero = numeroNacional ?? `${doc.number}${doc.series ? `/${doc.series}` : ""}`;
    const extra = String(body.message ?? "").trim();
    const temXml = attachments.some((a) => a.filename.endsWith(".xml"));

    const transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465, // 465 = TLS implícito; 587 = STARTTLS
      auth: { user, pass },
      connectionTimeout: 15000,
      greetingTimeout: 10000,
    });

    try {
      await transporter.sendMail({
        from: `${fromName} <${fromEmail}>`,
        to,
        subject: `${nomeDoc} nº ${numero} — ${fromName}`,
        // \n aqui é seguro: o Nodemailer normaliza para \r\n (CRLF) no MIME.
        text:
          `Olá,\n\nSegue em anexo a ${ehNfse ? "Nota Fiscal de Serviço Eletrônica" : "Nota Fiscal Eletrônica"} nº ${numero} (${nomePdf} em PDF${temXml ? " e o arquivo XML" : ""}).` +
          (extra ? `\n\n${extra}` : "") +
          `\n\nAtenciosamente,\n${fromName}`,
        attachments,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      void logEdgeError(admin, { context: "fiscal-email", action: "send", message: "Falha no envio SMTP: " + msg, error: e, details: { host, port, to } });
      return jr({ error: "Falha ao enviar pelo SMTP (" + host + ":" + port + "): " + msg }, 502);
    } finally {
      try { transporter.close(); } catch { /* ignore */ }
    }

    return jr({ ok: true, to, attachments: attachments.map((a) => a.filename) });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    void logEdgeError(admin, { context: "fiscal-email", message, error: err });
    return jr({ error: message }, 500);
  }
});
