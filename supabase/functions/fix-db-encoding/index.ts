import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    console.log("Iniciando correção de encoding...");

    const corrections = [
      { from: "Tubar?o", to: "Tubarão" },
      { from: "Can?ado", to: "Cançado" },
      { from: "Jo?o", to: "João" },
      { from: "Jos?", to: "José" },
      { from: "S?o ", to: "São " },
      { from: "Concei??o", to: "Conceição" },
      { from: "Vit?ria", to: "Vitória" },
      { from: "Ant?nio", to: "Antônio" },
      { from: "M?rio", to: "Mário" },
      { from: "Ribeir?o", to: "Ribeirão" },
      { from: "Goi?s", to: "Goiás" },
      { from: "Macei?", to: "Maceió" },
      { from: "Aracaj?", to: "Aracaju" }
    ];

    let totalFixed = 0;

    // 1. Corrigir Clientes
    const { data: clients } = await supabaseAdmin
      .from("clients")
      .select("id, full_name_or_company_name, city")
      .or("full_name_or_company_name.ilike.%?%,city.ilike.%?%");

    if (clients) {
      for (const client of clients) {
        let name = client.full_name_or_company_name || "";
        let city = client.city || "";
        let changed = false;

        for (const corr of corrections) {
          if (name.includes(corr.from)) { name = name.replace(corr.from, corr.to); changed = true; }
          if (city.includes(corr.from)) { city = city.replace(corr.from, corr.to); changed = true; }
        }

        if (changed) {
          await supabaseAdmin.from("clients").update({ full_name_or_company_name: name, city }).eq("id", client.id);
          totalFixed++;
        }
      }
    }

    // 2. Corrigir Leads
    const { data: leads } = await supabaseAdmin.from("whatsapp_leads").select("id, display_name").ilike("display_name", "%?%");
    if (leads) {
      for (const lead of leads) {
        let name = lead.display_name || "";
        let changed = false;
        for (const corr of corrections) {
          if (name.includes(corr.from)) { name = name.replace(corr.from, corr.to); changed = true; }
        }
        if (changed) {
          await supabaseAdmin.from("whatsapp_leads").update({ display_name: name }).eq("id", lead.id);
          totalFixed++;
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, totalFixed }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
