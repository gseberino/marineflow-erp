// Edge Function: public-service-order
// Read-only public DTO for service order links. The share_token is the only
// public credential and the function returns only fields required by the page.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SIGNATURE_ASSET_TTL_SECONDS = 15 * 60;
type SupabaseAdmin = ReturnType<typeof createClient>;
type QueryResult = { data: unknown; error: { message: string } | null };

const PUBLIC_SETTING_KEYS = [
  'company_name',
  'company_logo_url',
  'address_line_1',
  'address_number',
  'city',
  'state',
  'postal_code',
  'phone',
  'email',
  'cnpj',
  'bank_name',
  'bank_agency',
  'bank_account',
  'pix_key',
  'payment_instructions',
  'payment_link_url',
  'terms_general',
  'terms_warranty',
  'terms_cancellation',
  'terms_delivery',
  'terms_responsibilities',
  'public_view_show_service_prices',
  'public_view_show_parts_prices',
  'public_view_show_travel_cost',
  'public_view_show_discount',
  'public_view_show_tax',
  'public_view_show_terms',
  'public_view_show_bank_details',
  'public_view_show_payment_instructions',
  'public_view_show_extra_notes',
  'public_view_show_validity',
  'public_view_allow_signature',
];

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

function tokenIsExpired(order: { share_token_expires_at?: string | null }): boolean {
  return !!order.share_token_expires_at && new Date(order.share_token_expires_at).getTime() <= Date.now();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'Metodo nao permitido.' }, 405);

  try {
    const { share_token: shareToken } = await req.json();
    if (!shareToken || typeof shareToken !== 'string') {
      return jsonResponse({ error: 'Token obrigatorio.' }, 400);
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: order, error: orderErr } = await admin
      .from('service_orders')
      .select('*')
      .eq('share_token', shareToken)
      .maybeSingle();
    if (orderErr) return jsonResponse({ error: 'Erro ao buscar documento.', detail: orderErr.message }, 500);
    if (!order || order.share_token_revoked_at || tokenIsExpired(order)) {
      return jsonResponse({ error: 'Documento nao encontrado ou link invalido.' }, 404);
    }

    const [clientRes, vesselRes, partsRes, servicesRes, settingsRes, sigRes, presetRes] = await Promise.all([
      order.client_id
        ? admin.from('clients').select('*').eq('id', order.client_id).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      order.vessel_id
        ? admin.from('vessels').select('*').eq('id', order.vessel_id).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      admin
        .from('service_order_parts')
        .select('*, products(name:product_name, sku)')
        .eq('service_order_id', order.id),
      admin
        .from('service_order_services')
        .select('*')
        .eq('service_order_id', order.id),
      admin.from('app_settings').select('key, value').in('key', PUBLIC_SETTING_KEYS),
      admin
        .from('service_order_signatures')
        .select('id, signature_image_url, signature_image_path, signed_pdf_url, signed_pdf_path, accepted_name, signed_at, superseded_at, document_hash, pdf_sha256')
        .eq('service_order_id', order.id)
        .is('superseded_at', null)
        .order('signed_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
      order.payment_condition_preset_id
        ? admin
            .from('payment_condition_presets')
            .select('label, installments')
            .eq('id', order.payment_condition_preset_id)
            .maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ]);

    const firstError = ([
      clientRes,
      vesselRes,
      partsRes,
      servicesRes,
      settingsRes,
      sigRes,
      presetRes,
    ] as QueryResult[]).find((result) => result.error)?.error;
    if (firstError) return jsonResponse({ error: 'Erro ao montar documento publico.', detail: firstError.message }, 500);

    const company: Record<string, string> = {};
    for (const row of (settingsRes.data || []) as Array<{ key: string; value: string | null }>) {
      if (row.key) company[row.key] = String(row.value || '');
    }

    const signatureRow = sigRes.data as {
      signature_image_path?: string | null;
      signature_image_url?: string | null;
      signed_pdf_path?: string | null;
      signed_pdf_url?: string | null;
    } | null;
    const signature = signatureRow ? {
      ...signatureRow,
      signature_image_url: await createSignedSignatureUrl(admin, signatureRow.signature_image_path || signatureRow.signature_image_url),
      signed_pdf_url: await createSignedSignatureUrl(admin, signatureRow.signed_pdf_path || signatureRow.signed_pdf_url),
    } : null;

    return jsonResponse({
      order,
      client: clientRes.data,
      vessel: vesselRes.data,
      parts: partsRes.data || [],
      services: servicesRes.data || [],
      company,
      signature,
      presetData: presetRes.data || null,
    });
  } catch (err: unknown) {
    const detail = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: 'Erro inesperado no servidor.', detail }, 500);
  }
});
