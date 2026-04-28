import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jr = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const body = await req.json().catch(() => ({}));
    const { identifier } = body;

    if (!identifier || identifier.trim().length < 5) {
      return jr({ error: "Identificador muito curto ou inválido." }, 400);
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { persistSession: false },
    });

    const q = String(identifier).trim();
    
    // Busca cliente por CPF/CNPJ, Telefone, WhatsApp ou Email
    const { data: clients, error: clientErr } = await sb
      .from("clients")
      .select("id, full_name_or_company_name")
      .or(`cpf_cnpj.eq.${q},phone.ilike.%${q}%,whatsapp.ilike.%${q}%,email.ilike.${q}`)
      .eq("active", true)
      .limit(1);

    if (clientErr || !clients || clients.length === 0) {
      return jr({ error: "Nenhum cliente ativo encontrado com este dado." }, 404);
    }

    const clientId = clients[0].id;

    // Busca as OSs do cliente
    const { data: orders, error: orderErr } = await sb
      .from("service_orders")
      .select("id, service_order_number, status, grand_total, scheduled_start_at, created_at, share_token, vessels(boat_name)")
      .eq("client_id", clientId)
      .order("created_at", { ascending: false });

    if (orderErr) throw orderErr;

    return jr({ 
      client: clients[0], 
      orders: orders 
    });

  } catch (e: any) {
    return jr({ error: e.message || "Erro interno do servidor" }, 500);
  }
});
