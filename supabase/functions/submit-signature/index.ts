// Edge Function: submit-signature
// Recebe assinatura (desenho + nome) do cliente via link público,
// valida share_token, cria o PDF final com página de evidências,
// armazena os arquivos e conclui a assinatura somente após arquivamento válido.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import {
  PDFDocument,
  StandardFonts,
  rgb,
  type PDFFont,
  type PDFPage,
} from 'https://esm.sh/pdf-lib@1.17.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface Payload {
  share_token: string;
  accepted_name: string;
  signature_png_base64: string;
  document_hash: string;
  accepted_terms_snapshot?: string | null;
  signed_pdf_base64?: string | null;
}

interface SignatureEvidence {
  signatureId: string;
  serviceOrderNumber: string;
  acceptedName: string;
  signedAt: string;
  ipAddress: string | null;
  userAgent: string | null;
  documentHash: string;
  acceptedTermsSnapshot?: string | null;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function decodeBase64Payload(value: string, dataUrlPrefix: RegExp): Uint8Array {
  const clean = value.replace(dataUrlPrefix, '');
  const bin = atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function formatSignedAtPtBr(iso: string): string {
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      timeZone: 'America/Sao_Paulo',
      dateStyle: 'short',
      timeStyle: 'medium',
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

function cleanText(value: string | null | undefined, fallback = 'Não disponível'): string {
  const clean = String(value || '').replace(/\s+/g, ' ').trim();
  return clean || fallback;
}

function splitLongToken(value: string, size = 56): string[] {
  const clean = cleanText(value);
  const parts: string[] = [];
  for (let i = 0; i < clean.length; i += size) parts.push(clean.slice(i, i + size));
  return parts.length ? parts : ['Não disponível'];
}

function wrapText(text: string, font: PDFFont, fontSize: number, maxWidth: number): string[] {
  const clean = cleanText(text, '');
  if (!clean) return [];

  const lines: string[] = [];
  let current = '';
  for (const rawWord of clean.split(' ')) {
    const word = rawWord.trim();
    if (!word) continue;
    if (font.widthOfTextAtSize(word, fontSize) > maxWidth) {
      if (current) {
        lines.push(current);
        current = '';
      }
      lines.push(...splitLongToken(word, 46));
      continue;
    }
    const candidate = current ? `${current} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, fontSize) <= maxWidth) {
      current = candidate;
    } else {
      if (current) lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines;
}

function drawWrappedText(
  page: PDFPage,
  text: string,
  font: PDFFont,
  fontSize: number,
  x: number,
  y: number,
  maxWidth: number,
  lineHeight: number,
): number {
  let cursorY = y;
  for (const line of wrapText(text, font, fontSize, maxWidth)) {
    page.drawText(line, { x, y: cursorY, size: fontSize, font, color: rgb(0.12, 0.16, 0.23) });
    cursorY -= lineHeight;
  }
  return cursorY;
}

function drawEvidenceRow(
  page: PDFPage,
  label: string,
  value: string,
  font: PDFFont,
  boldFont: PDFFont,
  x: number,
  y: number,
  maxWidth: number,
): number {
  page.drawText(label, { x, y, size: 9, font: boldFont, color: rgb(0.0, 0.17, 0.36) });
  return drawWrappedText(page, value, font, 9, x + 112, y, maxWidth - 112, 12) - 4;
}

async function appendSignatureEvidencePage(
  basePdfBytes: Uint8Array,
  signaturePngBytes: Uint8Array,
  evidence: SignatureEvidence,
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.load(basePdfBytes, { ignoreEncryption: true });
  const page = pdfDoc.addPage([595.28, 841.89]);
  const { width, height } = page.getSize();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const signatureImage = await pdfDoc.embedPng(signaturePngBytes);
  const signatureDims = signatureImage.scaleToFit(380, 120);
  const marginX = 48;
  const rowWidth = width - marginX * 2;
  let y = height - 58;

  page.drawText('ASSINATURA DIGITAL DO CLIENTE', {
    x: marginX, y, size: 17, font: boldFont, color: rgb(0.0, 0.17, 0.36),
  });
  y -= 24;
  page.drawText('Página de evidência adicionada automaticamente no momento do aceite digital.', {
    x: marginX, y, size: 9, font, color: rgb(0.39, 0.45, 0.55),
  });

  y -= 30;
  page.drawRectangle({
    x: marginX, y: y - 155, width: rowWidth, height: 155,
    borderColor: rgb(0.82, 0.88, 0.94), borderWidth: 1, color: rgb(0.98, 0.99, 1),
  });
  const sigX = marginX + (rowWidth - signatureDims.width) / 2;
  page.drawImage(signatureImage, {
    x: sigX, y: y - 122, width: signatureDims.width, height: signatureDims.height,
  });
  page.drawText('Imagem da assinatura coletada no canvas do link público', {
    x: marginX + 14, y: y - 145, size: 8, font, color: rgb(0.39, 0.45, 0.55),
  });

  y -= 190;
  page.drawText('Dados de autenticação', {
    x: marginX, y, size: 12, font: boldFont, color: rgb(0.0, 0.17, 0.36),
  });
  y -= 24;
  y = drawEvidenceRow(page, 'OS:', evidence.serviceOrderNumber, font, boldFont, marginX, y, rowWidth);
  y = drawEvidenceRow(page, 'Assinado por:', evidence.acceptedName, font, boldFont, marginX, y, rowWidth);
  y = drawEvidenceRow(page, 'Data/hora:', `${formatSignedAtPtBr(evidence.signedAt)} (America/Sao_Paulo)`, font, boldFont, marginX, y, rowWidth);
  y = drawEvidenceRow(page, 'IP:', cleanText(evidence.ipAddress), font, boldFont, marginX, y, rowWidth);
  y = drawEvidenceRow(page, 'Dispositivo:', cleanText(evidence.userAgent), font, boldFont, marginX, y, rowWidth);
  y = drawEvidenceRow(page, 'ID assinatura:', evidence.signatureId, font, boldFont, marginX, y, rowWidth);

  y -= 4;
  page.drawText('Hash SHA-256 do conteúdo aprovado da OS:', {
    x: marginX, y, size: 9, font: boldFont, color: rgb(0.0, 0.17, 0.36),
  });
  y -= 14;
  for (const line of splitLongToken(evidence.documentHash, 64)) {
    page.drawText(line, { x: marginX, y, size: 8.5, font, color: rgb(0.12, 0.16, 0.23) });
    y -= 11;
  }

  if (evidence.acceptedTermsSnapshot && y > 176) {
    y -= 10;
    page.drawText('Resumo dos termos aceitos:', {
      x: marginX, y, size: 9, font: boldFont, color: rgb(0.0, 0.17, 0.36),
    });
    y -= 14;
    const termsPreview = evidence.acceptedTermsSnapshot.slice(0, 650);
    const lines = wrapText(termsPreview, font, 7.5, rowWidth).slice(0, Math.max(1, Math.floor((y - 76) / 10)));
    for (const line of lines) {
      page.drawText(line, { x: marginX, y, size: 7.5, font, color: rgb(0.12, 0.16, 0.23) });
      y -= 10;
    }
  }

  page.drawLine({
    start: { x: marginX, y: 54 }, end: { x: width - marginX, y: 54 },
    thickness: 0.5, color: rgb(0.82, 0.88, 0.94),
  });
  page.drawText('MarineFlow ERP - Documento digital arquivado com evidencia de assinatura', {
    x: marginX, y: 36, size: 8, font, color: rgb(0.39, 0.45, 0.55),
  });
  return await pdfDoc.save();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'Método não permitido.' }, 405);

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = (await req.json()) as Payload;

    if (!body?.share_token || !body?.accepted_name?.trim() || !body?.signature_png_base64 || !body?.document_hash) {
      return jsonResponse({ error: 'Campos obrigatórios faltando.' }, 400);
    }
    if (!body.signed_pdf_base64) {
      return jsonResponse({ error: 'Não foi possível preparar o PDF final. Recarregue a página e tente assinar novamente.' }, 400);
    }
    if (body.accepted_name.trim().length < 3) return jsonResponse({ error: 'Nome muito curto.' }, 400);

    const { data: order, error: orderErr } = await admin
      .from('service_orders')
      .select('id, service_order_number, status, signed_at, requires_resignature, share_token')
      .eq('share_token', body.share_token)
      .maybeSingle();
    if (orderErr) return jsonResponse({ error: 'Erro ao buscar OS.', detail: orderErr.message }, 500);
    if (!order) return jsonResponse({ error: 'Link inválido ou expirado.' }, 404);
    if (order.signed_at && !order.requires_resignature) {
      return jsonResponse({ error: 'Este documento já foi assinado.', already_signed: true }, 409);
    }

    let pngBytes: Uint8Array;
    let basePdfBytes: Uint8Array;
    try {
      pngBytes = decodeBase64Payload(body.signature_png_base64, /^data:image\/\w+;base64,/);
      basePdfBytes = decodeBase64Payload(body.signed_pdf_base64, /^data:application\/pdf;base64,/);
      await PDFDocument.load(basePdfBytes, { ignoreEncryption: true });
    } catch {
      return jsonResponse({ error: 'Imagem de assinatura ou PDF base inválido.' }, 400);
    }
    if (pngBytes.length > 2_000_000) return jsonResponse({ error: 'Imagem muito grande (máx 2MB).' }, 413);
    if (basePdfBytes.length > 10_000_000) return jsonResponse({ error: 'PDF muito grande (máx 10MB).' }, 413);

    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      || req.headers.get('cf-connecting-ip') || null;
    const userAgent = req.headers.get('user-agent') || null;
    const timestamp = Date.now();
    const imagePath = `${order.id}/${timestamp}.png`;
    const pdfPath = `${order.id}/signed-${timestamp}.pdf`;
    let signatureId: string | null = null;
    let imageUploaded = false;
    let pdfUploaded = false;

    const cleanupIncompleteSignature = async () => {
      if (signatureId) await admin.from('service_order_signatures').delete().eq('id', signatureId);
      const paths: string[] = [];
      if (imageUploaded) paths.push(imagePath);
      if (pdfUploaded) paths.push(pdfPath);
      if (paths.length) await admin.storage.from('signatures').remove(paths);
    };

    const { error: imageUploadErr } = await admin.storage
      .from('signatures')
      .upload(imagePath, pngBytes, { contentType: 'image/png', upsert: false });
    if (imageUploadErr) return jsonResponse({ error: 'Falha ao salvar imagem.', detail: imageUploadErr.message }, 500);
    imageUploaded = true;
    const { data: imagePublic } = admin.storage.from('signatures').getPublicUrl(imagePath);
    const signatureUrl = imagePublic.publicUrl;

    const { data: sig, error: sigErr } = await admin
      .from('service_order_signatures')
      .insert({
        service_order_id: order.id,
        share_token: body.share_token,
        signature_image_url: signatureUrl,
        signed_pdf_url: null,
        accepted_name: body.accepted_name.trim(),
        accepted_terms_snapshot: body.accepted_terms_snapshot || null,
        document_hash: body.document_hash,
        ip_address: ip,
        user_agent: userAgent,
      })
      .select()
      .single();
    if (sigErr) {
      await cleanupIncompleteSignature();
      return jsonResponse({ error: 'Falha ao registrar assinatura.', detail: sigErr.message }, 500);
    }
    signatureId = sig.id;

    let finalPdfBytes: Uint8Array;
    try {
      finalPdfBytes = await appendSignatureEvidencePage(basePdfBytes, pngBytes, {
        signatureId: sig.id,
        serviceOrderNumber: order.service_order_number,
        acceptedName: body.accepted_name.trim(),
        signedAt: sig.signed_at,
        ipAddress: ip,
        userAgent,
        documentHash: body.document_hash,
        acceptedTermsSnapshot: body.accepted_terms_snapshot || null,
      });
    } catch (pdfBuildError: any) {
      await cleanupIncompleteSignature();
      return jsonResponse({ error: 'Falha ao gerar PDF final assinado.', detail: pdfBuildError?.message || String(pdfBuildError) }, 500);
    }

    const { error: pdfUploadErr } = await admin.storage
      .from('signatures')
      .upload(pdfPath, finalPdfBytes, { contentType: 'application/pdf', upsert: false });
    if (pdfUploadErr) {
      await cleanupIncompleteSignature();
      return jsonResponse({ error: 'Falha ao armazenar PDF final assinado.', detail: pdfUploadErr.message }, 500);
    }
    pdfUploaded = true;
    const { data: pdfPublic } = admin.storage.from('signatures').getPublicUrl(pdfPath);
    const signedPdfUrl = pdfPublic.publicUrl;
    const pdfFileHash = await sha256Hex(finalPdfBytes);

    const { error: sigLinkErr } = await admin
      .from('service_order_signatures')
      .update({ signed_pdf_url: signedPdfUrl })
      .eq('id', sig.id);
    if (sigLinkErr) {
      await cleanupIncompleteSignature();
      return jsonResponse({ error: 'PDF salvo, mas falhou ao vincular à assinatura.', detail: sigLinkErr.message }, 500);
    }

    const { data: settingRow } = await admin.from('app_settings').select('value').eq('key', 'signature_status_after').maybeSingle();
    const newStatus = settingRow?.value || 'completed';
    const { error: updErr } = await admin
      .from('service_orders')
      .update({
        signed_at: sig.signed_at,
        signed_document_hash: body.document_hash,
        signed_by_name: body.accepted_name.trim(),
        client_signature_url: signatureUrl,
        requires_resignature: false,
        resignature_requested_at: null,
        status: newStatus,
      })
      .eq('id', order.id);
    if (updErr) {
      await cleanupIncompleteSignature();
      return jsonResponse({ error: 'Assinatura arquivada, mas falhou ao atualizar OS.', detail: updErr.message }, 500);
    }

    let historyWarning: string | null = null;
    if (order.requires_resignature) {
      const { error: supersedeErr } = await admin
        .from('service_order_signatures')
        .update({ superseded_at: new Date().toISOString(), superseded_reason: 'Reassinatura solicitada' })
        .eq('service_order_id', order.id)
        .neq('id', sig.id)
        .is('superseded_at', null);
      if (supersedeErr) historyWarning = `Falha ao marcar assinatura anterior como superada: ${supersedeErr.message}`;
    }

    await admin.from('audit_log').insert({
      table_name: 'service_orders',
      record_id: order.id,
      action: 'client_signature',
      changed_by: `cliente:${body.accepted_name.trim()}`,
      new_value: {
        signature_id: sig.id,
        signature_url: signatureUrl,
        signed_pdf_url: signedPdfUrl,
        pdf_sha256: pdfFileHash,
        ip,
        user_agent: userAgent,
        document_hash: body.document_hash,
        new_status: newStatus,
        history_warning: historyWarning,
      },
      reason: 'Assinatura digital recebida via link público com PDF final arquivado',
    });

    return jsonResponse({
      ok: true,
      signature_id: sig.id,
      service_order_number: order.service_order_number,
      new_status: newStatus,
      signed_at: sig.signed_at,
      signed_by: body.accepted_name.trim(),
      signature_url: signatureUrl,
      signed_pdf_url: signedPdfUrl,
      pdf_archived: true,
      pdf_sha256: pdfFileHash,
      history_warning: historyWarning,
      ip_address: ip,
      document_hash: body.document_hash,
    });
  } catch (err: any) {
    return jsonResponse({ error: 'Erro inesperado no servidor.', detail: err?.message || String(err) }, 500);
  }
});
