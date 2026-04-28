import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Extracts a single value from XML using a tag name. Searches case-insensitively. */
function tag(xml: string, name: string): string | null {
  const re = new RegExp(`<${name}[^>]*>([^<]*)<\\/${name}>`, "is");
  return xml.match(re)?.[1]?.trim() ?? null;
}

/** Finds all occurrences of a block tag and returns their content. */
function tagAll(xml: string, name: string): string[] {
  const re = new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "ig");
  return [...xml.matchAll(re)].map((m) => m[1]);
}

// ── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const body = await req.json();
    if (!body.xmlBase64) throw new Error("XML não fornecido (xmlBase64 ausente)");

    // ── 1. Decode XML ──────────────────────────────────────────────────────
    let xmlText: string;
    try {
      xmlText = atob(body.xmlBase64);
    } catch {
      throw new Error("Base64 inválido — verifique o encoding do arquivo XML.");
    }

    // ── 2. Validate minimal NFe structure ─────────────────────────────────
    if (!xmlText.includes("<infNFe") && !xmlText.includes("<NFe")) {
      throw new Error("Arquivo não é uma NF-e válida (tag <infNFe> não encontrada).");
    }

    // ── 3. Extract header fields ───────────────────────────────────────────
    const nfeKey    = xmlText.match(/infNFe[^I]*Id="NFe(\d+)"/i)?.[1] ?? null;
    const nfeNumber = tag(xmlText, "nNF");
    const issueDateRaw = tag(xmlText, "dhEmi");
    const issuerName   = xmlText.match(/<emit>[\s\S]*?<xNome>([^<]+)<\/xNome>/i)?.[1]?.trim() ?? null;
    const issuerCNPJ   = xmlText.match(/<emit>[\s\S]*?<CNPJ>([^<]+)<\/CNPJ>/i)?.[1]?.trim() ?? null;

    const totalNF      = parseFloat(tag(xmlText, "vNF") ?? "0");
    const totalICMS    = parseFloat(tag(xmlText, "vICMS") ?? "0");
    const totalIPI     = parseFloat(tag(xmlText, "vIPI") ?? "0");
    const totalPIS     = parseFloat(tag(xmlText, "vPIS") ?? "0");
    const totalCOFINS  = parseFloat(tag(xmlText, "vCOFINS") ?? "0");

    // ── 4. Extract items (det blocks) ─────────────────────────────────────
    const detBlocks = tagAll(xmlText, "det");
    const items = detBlocks.map((det, idx) => {
      const prod = det.match(/<prod>([\s\S]*?)<\/prod>/i)?.[1] ?? det;
      const icmsBlock = det.match(/<ICMS>([\s\S]*?)<\/ICMS>/i)?.[1] ?? "";

      const qty    = parseFloat(tag(prod, "qCom") ?? "0");
      const price  = parseFloat(tag(prod, "vUnCom") ?? "0");
      const total  = parseFloat(tag(prod, "vProd") ?? "0");
      const icmsQty = parseFloat(tag(icmsBlock, "vICMS") ?? "0");

      return {
        index:        idx + 1,
        sku_supplier: tag(prod, "cProd"),
        description:  tag(prod, "xProd"),
        ncm:          tag(prod, "NCM"),
        cfop:         tag(prod, "CFOP"),
        unit:         tag(prod, "uCom"),
        quantity:     qty,
        unit_price:   price,
        total_price:  total,
        icms_value:   icmsQty,
      };
    });

    // ── 5. Duplicate check via NFe key ─────────────────────────────────────
    if (nfeKey) {
      const { data: existing } = await supabase
        .from("fiscal_notes")
        .select("id")
        .eq("nfe_key", nfeKey)
        .maybeSingle();

      if (existing) {
        return new Response(
          JSON.stringify({
            error: `NF-e já importada (chave ${nfeKey.slice(0, 12)}…). Duplicata ignorada.`,
            duplicate: true,
          }),
          {
            status: 409,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    // ── 6. Persist in fiscal_notes (store original XML) ───────────────────
    const { data: noteRow, error: insertErr } = await supabase
      .from("fiscal_notes")
      .insert({
        nfe_key:       nfeKey,
        nfe_number:    nfeNumber,
        issuer_name:   issuerName,
        issuer_cnpj:   issuerCNPJ,
        issued_at:     issueDateRaw ?? new Date().toISOString(),
        total_amount:  totalNF,
        tax_icms:      totalICMS,
        tax_ipi:       totalIPI,
        tax_pis:       totalPIS,
        tax_cofins:    totalCOFINS,
        items:         items,
        xml_content:   xmlText,   // ← Armazena o XML original
        status:        "pending",
      })
      .select("id")
      .single();

    if (insertErr) throw new Error(`Erro ao salvar NF-e: ${insertErr.message}`);

    const noteId = noteRow.id;

    // ── 7. Audit log ───────────────────────────────────────────────────────
    await supabase.from("audit_logs").insert({
      table_name: "fiscal_notes",
      record_id:  noteId,
      action:     "import_xml",
      new_value: {
        nfe_key:    nfeKey,
        nfe_number: nfeNumber,
        items:      items.length,
        total:      totalNF,
      },
      reason: "Importação automática de XML de NF-e",
    });

    // ── 8. Return parsed data (UI will confirm stock update) ──────────────
    return new Response(
      JSON.stringify({
        noteId,
        nfeKey,
        nfeNumber,
        issueDate:  issueDateRaw,
        issuerName,
        issuerCNPJ,
        totalNF,
        totalICMS,
        totalIPI,
        totalPIS,
        totalCOFINS,
        items,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (e: any) {
    console.error("[process-nfe-xml]", e.message);
    return new Response(
      JSON.stringify({ error: e.message }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
