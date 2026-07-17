// Shared status-application logic used by both fiscal-webhook (event-driven)
// and fiscal-reconcile (poll-driven safety net), so the two entry points never
// drift in how they persist a status transition or archive artifacts.
import type { DocumentStatusInfo, DocumentType, FiscalProvider } from "./types.ts";

// Loose row shape (only the fields this module reads/needs) — the callers pass
// rows selected from issued_fiscal_documents. `admin` is the Supabase
// service-role client; typed as `any` to match this codebase's existing
// convention for edge-function Supabase clients (see whatsapp-webhook).
export interface IssuedFiscalDocumentRow {
  id: string;
  document_type: DocumentType | string;
  provider_document_id: string | null;
  environment: string;
  status: string;
  xml_storage_path: string | null;
  pdf_storage_path?: string | null;
  provider_status?: Record<string, unknown> | null;
}

// Applies a fresh status snapshot to an issued_fiscal_documents row: updates
// lifecycle fields and, when newly authorized, downloads xml_authorized/
// pdf_danfe into the fiscal-xml bucket for legal retention (provider URLs may
// expire; the XML must be kept regardless for the 5-year fiscal retention).
export async function applyStatusUpdate(
  // deno-lint-ignore no-explicit-any
  admin: any,
  provider: FiscalProvider,
  doc: IssuedFiscalDocumentRow,
  statusInfo: DocumentStatusInfo,
  extraProviderStatus?: Record<string, unknown>,
): Promise<void> {
  // Mescla sobre o provider_status já salvo (nunca substitui do zero) — assim
  // uma chave interna gravada por uma chamada anterior (ex.: o
  // __last_delivery_id que fiscal-webhook usa para dedup) sobrevive mesmo
  // quando é fiscal-reconcile quem processa a atualização seguinte.
  const mergedProviderStatus = {
    ...(doc.provider_status ?? {}),
    ...(statusInfo.raw as object),
    ...(extraProviderStatus ?? {}),
  };

  const update: Record<string, unknown> = {
    status: statusInfo.status,
    status_code: statusInfo.statusCode ?? null,
    status_message: statusInfo.statusMessage ?? null,
    access_key: statusInfo.accessKey ?? null,
    protocol: statusInfo.protocol ?? null,
    provider_status: mergedProviderStatus,
    updated_at: new Date().toISOString(),
  };

  if (statusInfo.status === "authorized" && statusInfo.authorizedAt) {
    update.authorized_at = statusInfo.authorizedAt;
  }
  if (statusInfo.status === "cancelled") {
    update.cancelled_at = new Date().toISOString();
  }

  // Tenta arquivar o XML autorizado e o DANFE (PDF) sempre que qualquer um dos
  // dois ainda não foi salvo — não é "só uma vez": fiscal-reconcile também
  // reconsulta documentos já autorizados com xml_storage_path/pdf_storage_path
  // nulo, então uma falha transitória aqui tem uma segunda (e terceira...)
  // chance na próxima reconciliação. archiveArtifacts baixa só o que falta.
  if (
    statusInfo.status === "authorized" &&
    (!doc.xml_storage_path || !doc.pdf_storage_path)
  ) {
    Object.assign(update, await archiveArtifacts(admin, provider, doc, statusInfo));
  }

  const { error } = await admin.from("issued_fiscal_documents").update(update).eq("id", doc.id);
  if (error) {
    console.error(`[fiscal] falha ao gravar status do documento ${doc.id}:`, error);
  }
}

async function archiveArtifacts(
  // deno-lint-ignore no-explicit-any
  admin: any,
  provider: FiscalProvider,
  doc: IssuedFiscalDocumentRow,
  statusInfo: DocumentStatusInfo,
): Promise<Record<string, unknown>> {
  const result: Record<string, unknown> = {};
  try {
    const artifacts = await provider.listArtifacts(
      doc.document_type as DocumentType,
      statusInfo.providerDocumentId,
    );
    if (!artifacts.ok) {
      console.error(`[fiscal] falha ao listar artefatos do documento ${doc.id}:`, artifacts.error);
      return result;
    }

    const xmlArtifact = artifacts.data.find(
      (a) => a.type === "xml_authorized" && a.available && a.downloadUrl,
    );
    const pdfArtifact = artifacts.data.find(
      (a) => a.type === "pdf_danfe" && a.available && a.downloadUrl,
    );

    // As download_url da Contora exigem o Bearer token — usar fetchArtifact do
    // provedor (autenticado), não um fetch cru (que retornaria "Bearer token
    // ausente" e nunca arquivaria o artefato, quebrando a guarda legal de 5 anos).
    if (!doc.xml_storage_path && xmlArtifact?.downloadUrl) {
      const xmlRes = await provider.fetchArtifact(xmlArtifact.downloadUrl);
      if (xmlRes.ok) {
        const xmlText = new TextDecoder().decode(xmlRes.data.bytes);
        // Sanity check: uma URL expirada/erro pode devolver HTML com 200 — só
        // arquiva se o conteúdo realmente parece XML.
        if (xmlText.trim().startsWith("<")) {
          const path = `${doc.environment}/${doc.document_type}/${doc.id}.xml`;
          const { error } = await admin.storage
            .from("fiscal-xml")
            .upload(path, new Blob([xmlText], { type: "application/xml" }), {
              contentType: "application/xml",
              upsert: true,
            });
          if (!error) {
            result.xml_storage_path = path;
          } else {
            console.error("[fiscal] falha ao arquivar XML no Storage:", error);
            result.xml_url = xmlArtifact.downloadUrl; // fallback: guarda ao menos a URL do provedor
          }
        } else {
          console.error(`[fiscal] conteúdo baixado para ${doc.id} não parece XML — não arquivado, será retentado.`);
        }
      } else {
        console.error(`[fiscal] download do XML falhou para ${doc.id}: ${xmlRes.error}`);
      }
    }
    // DANFE (PDF): arquiva os bytes no mesmo bucket para poder gerar URL
    // assinada e enviar ao cliente (WhatsApp) sem expor o token da Contora.
    if (!doc.pdf_storage_path && pdfArtifact?.downloadUrl) {
      const pdfRes = await provider.fetchArtifact(pdfArtifact.downloadUrl);
      if (pdfRes.ok) {
        const bytes = new Uint8Array(pdfRes.data.bytes);
        // Sanity check: PDF começa com "%PDF" (0x25 0x50 0x44 0x46). Uma URL
        // expirada/erro pode devolver HTML/JSON com 200 — só arquiva PDF real.
        const isPdf = bytes.length > 4 &&
          bytes[0] === 0x25 && bytes[1] === 0x50 &&
          bytes[2] === 0x44 && bytes[3] === 0x46;
        if (isPdf) {
          const path = `${doc.environment}/${doc.document_type}/${doc.id}.pdf`;
          const { error } = await admin.storage
            .from("fiscal-xml")
            .upload(path, new Blob([bytes], { type: "application/pdf" }), {
              contentType: "application/pdf",
              upsert: true,
            });
          if (!error) {
            result.pdf_storage_path = path;
          } else {
            console.error("[fiscal] falha ao arquivar DANFE no Storage:", error);
            result.pdf_url = pdfArtifact.downloadUrl; // fallback: URL do provedor
          }
        } else {
          console.error(`[fiscal] conteúdo baixado para DANFE de ${doc.id} não parece PDF — não arquivado, será retentado.`);
        }
      } else {
        console.error(`[fiscal] download do DANFE falhou para ${doc.id}: ${pdfRes.error}`);
      }
    }
  } catch (err) {
    console.error("[fiscal] falha ao processar artefatos:", err);
  }
  return result;
}
