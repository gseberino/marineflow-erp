// Edge Function: fiscal-reconcile
// Rede de segurança: reconsulta o status (grátis, não consome cota) de
// documentos ainda não-terminais, para o caso de o webhook ter se perdido.
// Também retenta arquivar o XML e o DANFE (PDF) de documentos já autorizados
// cujo artefato ainda não foi salvo (ex.: falha transitória de download/Storage
// na hora da autorização) — o próprio applyStatusUpdate só baixa o que estiver
// faltando (xml_storage_path/pdf_storage_path nulos), então incluir esses
// documentos aqui é seguro e idempotente.
// Dois caminhos de entrada (mesmo padrão dual-auth já usado em ai-agent):
//   (1) pg_cron — só x-cron-secret, sem Authorization: varredura em lote.
//   (2) painel  — JWT de admin + { document_id }: botão "Atualizar status".
// verify_jwt=false (o caminho do cron não manda Authorization); a
// autenticação do caminho manual é feita aqui dentro.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider } from "../_shared/fiscal/factory.ts";
import { applyStatusUpdate } from "../_shared/fiscal/apply-status.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const NON_TERMINAL = ["draft", "queued", "processing"];
const SELECT_COLS = "id, document_type, provider_document_id, environment, status, xml_storage_path, pdf_storage_path, provider_status";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const cronSecret = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && cronSecret === Deno.env.get("CRON_SECRET");

  let documentId: string | null = null;
  if (!isCron) {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "unauthorized" }, 401);
    const { data: userData, error } = await admin.auth.getUser(jwt);
    if (error || !userData?.user) return jr({ error: "unauthorized" }, 401);

    const { data: profile } = await admin
      .from("app_users")
      .select("role, active")
      .eq("id", userData.user.id)
      .maybeSingle();
    if (!profile || profile.role !== "admin" || profile.active === false) {
      return jr({ error: "forbidden" }, 403);
    }

    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    documentId = (body as Record<string, unknown>).document_id as string ?? null;
    if (!documentId) return jr({ error: "document_id é obrigatório fora do cron" }, 422);
  }

  const provider = createFiscalProvider();

  // Reconcilia documentos ainda não-terminais (webhook pode ter se perdido) E
  // documentos já autorizados cujo XML ainda não foi arquivado (retry de
  // artefato) — ambos os casos são baratos (getStatus não consome cota).
  let query = admin
    .from("issued_fiscal_documents")
    .select(SELECT_COLS)
    .not("provider_document_id", "is", null)
    .or(`status.in.(${NON_TERMINAL.join(",")}),and(status.eq.authorized,xml_storage_path.is.null),and(status.eq.authorized,pdf_storage_path.is.null)`)
    .limit(isCron ? 50 : 1);
  if (documentId) query = query.eq("id", documentId);

  const { data: docs, error: fetchErr } = await query;
  if (fetchErr) return jr({ error: fetchErr.message }, 500);

  let updated = 0;
  for (const doc of docs ?? []) {
    const statusInfo = await provider.getStatus(doc.document_type, doc.provider_document_id!);
    if (statusInfo.ok) {
      await applyStatusUpdate(admin, provider, doc, statusInfo.data);
      updated++;
    } else {
      console.error(`[fiscal-reconcile] falha ao consultar ${doc.id}:`, statusInfo.error);
    }
  }

  return jr({ ok: true, checked: docs?.length ?? 0, updated });
});
