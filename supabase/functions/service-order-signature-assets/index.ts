// Edge Function: service-order-signature-assets
// Authenticated internal access to signature evidence with temporary Storage URLs.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SIGNATURE_ASSET_TTL_SECONDS = 15 * 60;
type SupabaseAdmin = ReturnType<typeof createClient>;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function extractSignatureStoragePath(value: string | null | undefined): string | null {
  const clean = String(value || '').trim();
  if (!clean) return null;

  const publicMarker = '/storage/v1/object/public/signatures/';
  const signedMarker = '/storage/v1/object/sign/signatures/';
  const marker = clean.includes(publicMarker) ? publicMarker : signedMarker;
  const markerIndex = clean.indexOf(marker);

  if (markerIndex >= 0) {
    const rawPath = clean.slice(markerIndex + marker.length).split('?')[0];
    return decodeURIComponent(rawPath).replace(/^\/+/, '') || null;
  }

  if (/^https?:\/\//i.test(clean)) return null;
  return clean.replace(/^\/+/, '') || null;
}

async function createSignedSignatureUrl(admin: SupabaseAdmin, pathOrUrl: string | null | undefined): Promise<string | null> {
  const path = extractSignatureStoragePath(pathOrUrl);
  if (!path) return null;

  const { data, error } = await admin.storage
    .from('signatures')
    .createSignedUrl(path, SIGNATURE_ASSET_TTL_SECONDS);
  if (error || !data?.signedUrl) throw new Error(error?.message || 'Falha ao criar URL temporaria.');
  return data.signedUrl;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'Metodo nao permitido.' }, 405);

  try {
    const authHeader = req.headers.get('authorization') || '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!jwt) return jsonResponse({ error: 'Autenticacao obrigatoria.' }, 401);

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userRes, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userRes?.user) return jsonResponse({ error: 'Sessao invalida.' }, 401);

    const { service_order_id: serviceOrderId } = await req.json();
    if (!serviceOrderId || typeof serviceOrderId !== 'string') {
      return jsonResponse({ error: 'service_order_id obrigatorio.' }, 400);
    }

    const { data: signatures, error } = await admin
      .from('service_order_signatures')
      .select('id, accepted_name, signed_at, signature_image_url, signature_image_path, signed_pdf_url, signed_pdf_path, document_hash, pdf_sha256, ip_address, user_agent, superseded_at, superseded_reason, accepted_terms_snapshot')
      .eq('service_order_id', serviceOrderId)
      .order('signed_at', { ascending: false });
    if (error) return jsonResponse({ error: 'Erro ao buscar assinaturas.', detail: error.message }, 500);

    const signedRows = await Promise.all((signatures || []).map(async (sig) => ({
      id: sig.id,
      accepted_name: sig.accepted_name,
      signed_at: sig.signed_at,
      signature_image_url: await createSignedSignatureUrl(admin, sig.signature_image_path || sig.signature_image_url),
      signed_pdf_url: await createSignedSignatureUrl(admin, sig.signed_pdf_path || sig.signed_pdf_url),
      document_hash: sig.document_hash,
      pdf_sha256: sig.pdf_sha256,
      ip_address: sig.ip_address,
      user_agent: sig.user_agent,
      superseded_at: sig.superseded_at,
      superseded_reason: sig.superseded_reason,
      accepted_terms_snapshot: sig.accepted_terms_snapshot,
    })));

    return jsonResponse({ signatures: signedRows });
  } catch (err: unknown) {
    const detail = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: 'Erro inesperado no servidor.', detail }, 500);
  }
});
