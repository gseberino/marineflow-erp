// Edge Function: submit-signature
// Recebe assinatura (desenho + nome) do cliente via link público,
// valida share_token, faz upload da imagem e registra a assinatura.
// Atualiza status da OS e cria notificação para a equipe.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface Payload {
  share_token: string;
  accepted_name: string;
  signature_png_base64: string; // data URL ou base64 puro
  document_hash: string;
  accepted_terms_snapshot?: string;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = (await req.json()) as Payload;

    // ---- validação básica ----
    if (
      !body?.share_token ||
      !body?.accepted_name?.trim() ||
      !body?.signature_png_base64 ||
      !body?.document_hash
    ) {
      return jsonResponse({ error: 'Campos obrigatórios faltando.' }, 400);
    }
    if (body.accepted_name.trim().length < 3) {
      return jsonResponse({ error: 'Nome muito curto.' }, 400);
    }

    // ---- localizar OS pelo share_token ----
    const { data: order, error: orderErr } = await admin
      .from('service_orders')
      .select('id, service_order_number, status, signed_at, requires_resignature, share_token')
      .eq('share_token', body.share_token)
      .maybeSingle();

    if (orderErr) {
      return jsonResponse({ error: 'Erro ao buscar OS.', detail: orderErr.message }, 500);
    }
    if (!order) {
      return jsonResponse({ error: 'Link inválido ou expirado.' }, 404);
    }

    // ---- bloquear nova assinatura se já assinada e não pediu reassinatura ----
    if (order.signed_at && !order.requires_resignature) {
      return jsonResponse(
        { error: 'Este documento já foi assinado.', already_signed: true },
        409,
      );
    }

    // ---- decodificar PNG base64 ----
    const cleanBase64 = body.signature_png_base64.replace(/^data:image\/\w+;base64,/, '');
    let pngBytes: Uint8Array;
    try {
      const bin = atob(cleanBase64);
      pngBytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) pngBytes[i] = bin.charCodeAt(i);
    } catch {
      return jsonResponse({ error: 'Imagem da assinatura inválida.' }, 400);
    }
    if (pngBytes.length > 2_000_000) {
      return jsonResponse({ error: 'Imagem muito grande (máx 2MB).' }, 413);
    }

    // ---- upload no bucket signatures ----
    const filename = `${order.id}/${Date.now()}.png`;
    const { error: uploadErr } = await admin.storage
      .from('signatures')
      .upload(filename, pngBytes, {
        contentType: 'image/png',
        upsert: false,
      });
    if (uploadErr) {
      return jsonResponse({ error: 'Falha ao salvar imagem.', detail: uploadErr.message }, 500);
    }
    const { data: pub } = admin.storage.from('signatures').getPublicUrl(filename);
    const signatureUrl = pub.publicUrl;

    // ---- IP / user-agent ----
    const ip =
      req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
      req.headers.get('cf-connecting-ip') ||
      null;
    const userAgent = req.headers.get('user-agent') || null;

    // ---- supersede assinaturas anteriores ----
    if (order.requires_resignature) {
      await admin
        .from('service_order_signatures')
        .update({ superseded_at: new Date().toISOString(), superseded_reason: 'Reassinatura solicitada' })
        .eq('service_order_id', order.id)
        .is('superseded_at', null);
    }

    // ---- inserir assinatura ----
    const { data: sig, error: sigErr } = await admin
      .from('service_order_signatures')
      .insert({
        service_order_id: order.id,
        share_token: body.share_token,
        signature_image_url: signatureUrl,
        accepted_name: body.accepted_name.trim(),
        accepted_terms_snapshot: body.accepted_terms_snapshot || null,
        document_hash: body.document_hash,
        ip_address: ip,
        user_agent: userAgent,
      })
      .select()
      .single();

    if (sigErr) {
      return jsonResponse({ error: 'Falha ao registrar assinatura.', detail: sigErr.message }, 500);
    }

    // ---- buscar status configurado para depois de assinar ----
    const { data: settingRow } = await admin
      .from('app_settings')
      .select('value')
      .eq('key', 'signature_status_after')
      .maybeSingle();
    const newStatus = settingRow?.value || 'completed';

    // ---- atualizar OS ----
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
      return jsonResponse({ error: 'Assinatura salva, mas falhou ao atualizar OS.', detail: updErr.message }, 500);
    }

    // ---- audit log ----
    await admin.from('audit_log').insert({
      table_name: 'service_orders',
      record_id: order.id,
      action: 'client_signature',
      changed_by: `cliente:${body.accepted_name.trim()}`,
      new_value: {
        signature_id: sig.id,
        signature_url: signatureUrl,
        ip,
        user_agent: userAgent,
        document_hash: body.document_hash,
        new_status: newStatus,
      },
      reason: 'Assinatura digital recebida via link público',
    });

    return jsonResponse({
      ok: true,
      signature_id: sig.id,
      service_order_number: order.service_order_number,
      new_status: newStatus,
      signed_at: sig.signed_at,
      signed_by: body.accepted_name.trim(),
    });
  } catch (err: any) {
    return jsonResponse(
      { error: 'Erro inesperado no servidor.', detail: err?.message || String(err) },
      500,
    );
  }
});
