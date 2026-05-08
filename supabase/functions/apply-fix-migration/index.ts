import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const steps: string[] = [];
  const errors: string[] = [];

  // We run each statement separately to isolate errors.
  const statements = [
    `ALTER TABLE public.inventory_movements DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check`,
    `ALTER TABLE public.inventory_movements ADD CONSTRAINT inventory_movements_movement_type_check CHECK (movement_type IN ('purchase','manual_adjustment','service_usage','service_order_usage','return','transfer','manual_add','manual_remove','import','fiscal_note_entry'))`,
    `DROP TRIGGER IF EXISTS trg_deduct_stock_on_os_complete ON public.service_orders`,
  ];

  for (const sql of statements) {
    // Use pg_sleep as a carrier to piggyback DDL in a DO block via rpc workaround
    // Actually we use the execute endpoint directly
    const { error } = await supabase.rpc("run_sql", { query: sql }).maybeSingle();
    if (error) {
      errors.push(`${sql.substring(0, 40)}... => ${error.message}`);
    } else {
      steps.push(sql.substring(0, 60));
    }
  }

  return new Response(
    JSON.stringify({ ok: errors.length === 0, steps, errors }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
});
