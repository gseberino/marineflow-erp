import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Bytes 0xEF 0xBF 0xBD = U+FFFD (Unicode replacement character).
// Texto antigo importado com codificação errada chega com U+FFFD ou "?" no
// lugar do caractere acentuado original. Não dá para reverter byte-a-byte
// porque a info original foi perdida — mas dá para tratar palavras conhecidas.
const REPLACEMENT = "\uFFFD"; // o "?" preto no diamante / também impresso como "?"

// Substituições conhecidas. Cada padrão é aplicado tanto com U+FFFD
// quanto com "?" (ASCII), em qualquer posição da string.
const KNOWN_PAIRS: Array<[string, string]> = [
  // Cidades
  ["Tubar?o", "Tubarão"],
  ["S?o ", "São "],
  ["Concei??o", "Conceição"],
  ["Vit?ria", "Vitória"],
  ["Ribeir?o", "Ribeirão"],
  ["Goi?s", "Goiás"],
  ["Macei?", "Maceió"],
  ["Aracaj?", "Aracaju"],
  ["Bras?lia", "Brasília"],
  ["Bel?m", "Belém"],
  ["Cuiab?", "Cuiabá"],
  ["Florian?polis", "Florianópolis"],
  ["S?o Paulo", "São Paulo"],
  ["S?o Jos?", "São José"],
  ["Itaja?", "Itajaí"],
  ["Maranh?o", "Maranhão"],

  // Nomes próprios
  ["Jo?o", "João"],
  ["Jos?", "José"],
  ["Ant?nio", "Antônio"],
  ["M?rio", "Mário"],
  ["Can?ado", "Cançado"],
  ["L?cia", "Lúcia"],
  ["L?cio", "Lúcio"],
  ["?lvaro", "Álvaro"],
  ["Vin?cius", "Vinícius"],
  ["F?bio", "Fábio"],
  ["F?tima", "Fátima"],
  ["M?nica", "Mônica"],
  ["Cl?udio", "Cláudio"],
  ["Cl?udia", "Cláudia"],
  ["Get?lio", "Getúlio"],

  // Logradouros / palavras frequentes em endereços
  ["Ara?jo", "Araújo"],
  ["Braz?lio", "Brazílio"],
  ["Bras?lio", "Brasílio"],
  ["Avenida P?blica", "Avenida Pública"],
  ["P?blica", "Pública"],
  ["P?blico", "Público"],
  ["S?tio", "Sítio"],
  ["Trav?ssia", "Travéssia"],
  ["Esta??o", "Estação"],
  ["Confeder?ria", "Confederária"],
  ["Magalh?es", "Magalhães"],
  ["Concei??o", "Conceição"],
  ["S?", "Sé"],

  // Termos comerciais frequentes
  ["Servi?o", "Serviço"],
  ["Servi?os", "Serviços"],
  ["Op??o", "Opção"],
  ["Op??es", "Opções"],
  ["Embarca??o", "Embarcação"],
  ["Manuten??o", "Manutenção"],
  ["Eletr?nica", "Eletrônica"],
  ["Eletr?nico", "Eletrônico"],
];

function applyAll(input: string): { out: string; changed: boolean } {
  if (!input) return { out: input, changed: false };
  let out = input;
  // Primeiro normaliza U+FFFD para "?" para que um único dicionário cubra ambos
  const normalized = out.replace(new RegExp(REPLACEMENT, "g"), "?");
  let working = normalized;
  for (const [from, to] of KNOWN_PAIRS) {
    if (working.includes(from)) {
      working = working.split(from).join(to);
    }
  }
  return { out: working, changed: working !== input };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const report: Record<string, number> = {};
    let totalFixed = 0;

    // ========== CLIENTES ==========
    const { data: clients } = await supabaseAdmin
      .from("clients")
      .select(
        "id, full_name_or_company_name, address_line_1, address_line_2, city, state, notes"
      )
      .or(
        [
          "full_name_or_company_name.ilike.%?%",
          "full_name_or_company_name.ilike.%\uFFFD%",
          "address_line_1.ilike.%?%",
          "address_line_1.ilike.%\uFFFD%",
          "address_line_2.ilike.%?%",
          "address_line_2.ilike.%\uFFFD%",
          "city.ilike.%?%",
          "city.ilike.%\uFFFD%",
          "notes.ilike.%?%",
          "notes.ilike.%\uFFFD%",
        ].join(",")
      );

    if (clients) {
      for (const c of clients) {
        const update: Record<string, string> = {};
        let any = false;

        for (const field of [
          "full_name_or_company_name",
          "address_line_1",
          "address_line_2",
          "city",
          "state",
          "notes",
        ] as const) {
          const v = (c as any)[field] as string | null;
          if (!v) continue;
          const r = applyAll(v);
          if (r.changed) {
            update[field] = r.out;
            any = true;
          }
        }

        if (any) {
          await supabaseAdmin.from("clients").update(update).eq("id", c.id);
          totalFixed++;
          report.clients = (report.clients || 0) + 1;
        }
      }
    }

    // ========== EMBARCAÇÕES ==========
    const { data: vessels } = await supabaseAdmin
      .from("vessels")
      .select("id, boat_name, manufacturer, model, current_marina_name_snapshot")
      .or(
        [
          "boat_name.ilike.%?%",
          "boat_name.ilike.%\uFFFD%",
          "manufacturer.ilike.%?%",
          "manufacturer.ilike.%\uFFFD%",
          "model.ilike.%?%",
          "model.ilike.%\uFFFD%",
        ].join(",")
      );

    if (vessels) {
      for (const v of vessels) {
        const update: Record<string, string> = {};
        let any = false;
        for (const f of ["boat_name", "manufacturer", "model", "current_marina_name_snapshot"] as const) {
          const val = (v as any)[f] as string | null;
          if (!val) continue;
          const r = applyAll(val);
          if (r.changed) {
            update[f] = r.out;
            any = true;
          }
        }
        if (any) {
          await supabaseAdmin.from("vessels").update(update).eq("id", v.id);
          totalFixed++;
          report.vessels = (report.vessels || 0) + 1;
        }
      }
    }

    // ========== LEADS WHATSAPP ==========
    const { data: leads } = await supabaseAdmin
      .from("whatsapp_leads")
      .select("id, display_name")
      .or("display_name.ilike.%?%,display_name.ilike.%\uFFFD%");

    if (leads) {
      for (const l of leads) {
        const r = applyAll(l.display_name || "");
        if (r.changed) {
          await supabaseAdmin
            .from("whatsapp_leads")
            .update({ display_name: r.out })
            .eq("id", l.id);
          totalFixed++;
          report.whatsapp_leads = (report.whatsapp_leads || 0) + 1;
        }
      }
    }

    // ========== ORDENS DE SERVIÇO (campos textuais) ==========
    const { data: orders } = await supabaseAdmin
      .from("service_orders")
      .select(
        "id, problem_description, diagnosis, solution_applied, customer_visible_report, extra_notes, payment_conditions"
      )
      .or(
        [
          "problem_description.ilike.%?%",
          "problem_description.ilike.%\uFFFD%",
          "diagnosis.ilike.%?%",
          "diagnosis.ilike.%\uFFFD%",
          "solution_applied.ilike.%?%",
          "solution_applied.ilike.%\uFFFD%",
          "customer_visible_report.ilike.%?%",
          "customer_visible_report.ilike.%\uFFFD%",
          "extra_notes.ilike.%?%",
          "extra_notes.ilike.%\uFFFD%",
          "payment_conditions.ilike.%?%",
          "payment_conditions.ilike.%\uFFFD%",
        ].join(",")
      );

    if (orders) {
      for (const o of orders) {
        const update: Record<string, string> = {};
        let any = false;
        for (const f of [
          "problem_description",
          "diagnosis",
          "solution_applied",
          "customer_visible_report",
          "extra_notes",
          "payment_conditions",
        ] as const) {
          const v = (o as any)[f] as string | null;
          if (!v) continue;
          const r = applyAll(v);
          if (r.changed) {
            update[f] = r.out;
            any = true;
          }
        }
        if (any) {
          await supabaseAdmin.from("service_orders").update(update).eq("id", o.id);
          totalFixed++;
          report.service_orders = (report.service_orders || 0) + 1;
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, totalFixed, report }, null, 2),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
