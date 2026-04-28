// process-nfe-xml: recebe { xml_base64 } e extrai cabeçalho + itens da NFe.
// Opcional: cria fiscal_notes / fiscal_note_items, casa por SKU/EAN e gera
// inventory_movements de purchase + payable.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function decodeBase64ToString(b64: string): string {
  const clean = b64.replace(/^data:.*;base64,/, "").replace(/\s+/g, "");
  const bin = atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder("utf-8").decode(bytes);
}

// Extrator XML simples por regex (NFe é estável o bastante para os campos abaixo).
function pick(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"));
  return m ? m[1].trim() : null;
}
function pickAll(xml: string, tag: string): string[] {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "gi");
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) out.push(m[1]);
  return out;
}

function parseNFe(xml: string) {
  // Chave da NFe (Id="NFe...")
  const idMatch = xml.match(/Id="NFe(\d{44})"/);
  const nfe_key = idMatch ? idMatch[1] : pick(xml, "chNFe");

  const ide = pick(xml, "ide") || "";
  const emit = pick(xml, "emit") || "";
  const total = pick(xml, "ICMSTot") || "";

  const nfe_number = pick(ide, "nNF");
  const issue_date = (pick(ide, "dhEmi") || pick(ide, "dEmi") || "").slice(0, 10) || null;

  const issuer_name = pick(emit, "xNome");
  const issuer_cnpj = pick(emit, "CNPJ");
  const total_value = parseFloat(pick(total, "vNF") || "0") || 0;

  const detBlocks = pickAll(xml, "det");
  const items = detBlocks.map((det) => {
    const prod = pick(det, "prod") || "";
    return {
      c_prod: pick(prod, "cProd"),
      x_prod: pick(prod, "xProd"),
      ncm: pick(prod, "NCM"),
      unit: pick(prod, "uCom"),
      q_com: parseFloat(pick(prod, "qCom") || "0") || 0,
      v_un_com: parseFloat(pick(prod, "vUnCom") || "0") || 0,
      v_prod: parseFloat(pick(prod, "vProd") || "0") || 0,
      ean: pick(prod, "cEAN"),
    };
  });

  return {
    nfe_key,
    nfe_number,
    issue_date,
    issuer_name,
    issuer_cnpj,
    total_value,
    items,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "Não autenticado" }, 401);

    const sb = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) return jr({ error: "Não autenticado" }, 401);
    const userId = userData.user.id;

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({}));
    const xmlB64: string | undefined = body.xml_base64;
    const persist: boolean = body.persist !== false; // default true
    const createInventory: boolean = body.create_inventory !== false;
    const createPayable: boolean = body.create_payable !== false;

    if (!xmlB64) return jr({ error: "xml_base64 é obrigatório" }, 400);

    let xmlText: string;
    try {
      xmlText = decodeBase64ToString(xmlB64);
    } catch {
      return jr({ error: "xml_base64 inválido" }, 400);
    }

    const parsed = parseNFe(xmlText);
    if (!parsed.nfe_key) return jr({ error: "Não foi possível identificar a chave da NFe" }, 422);

    if (!persist) {
      return jr({ ok: true, parsed });
    }

    // Idempotência: se já existir nfe_key, retorna existente
    const { data: existing } = await admin
      .from("fiscal_notes")
      .select("id")
      .eq("nfe_key", parsed.nfe_key)
      .maybeSingle();

    if (existing) {
      return jr({ ok: true, fiscal_note_id: existing.id, already_imported: true, parsed });
    }

    // Tenta achar fornecedor pelo CNPJ
    let supplier_id: string | null = null;
    if (parsed.issuer_cnpj) {
      const { data: sup } = await admin
        .from("suppliers")
        .select("id")
        .eq("cnpj_cpf", parsed.issuer_cnpj)
        .maybeSingle();
      if (sup) supplier_id = sup.id;
    }

    // Cria payable
    let payable_id: string | null = null;
    if (createPayable && parsed.total_value > 0) {
      const today = new Date().toISOString().slice(0, 10);
      const { data: pay, error: payErr } = await admin
        .from("payables")
        .insert({
          description: `NFe ${parsed.nfe_number || ""} - ${parsed.issuer_name || ""}`.trim(),
          amount: parsed.total_value,
          balance_amount: parsed.total_value,
          issue_date: parsed.issue_date || today,
          due_date: parsed.issue_date || today,
          supplier_id,
          supplier_name: parsed.issuer_name,
          expense_category: "Compras de Estoque",
          origin: "nfe_import",
          status: "pending",
        })
        .select("id")
        .single();
      if (!payErr && pay) payable_id = pay.id;
    }

    // Insere nota
    const { data: note, error: noteErr } = await admin
      .from("fiscal_notes")
      .insert({
        nfe_key: parsed.nfe_key,
        nfe_number: parsed.nfe_number,
        issuer_name: parsed.issuer_name,
        issuer_cnpj: parsed.issuer_cnpj,
        issue_date: parsed.issue_date,
        total_value: parsed.total_value,
        status: "imported",
        supplier_id,
        payable_id,
        created_by: userId,
      })
      .select("id")
      .single();

    if (noteErr) return jr({ error: noteErr.message }, 500);

    // Itens + casamento por SKU/EAN + entrada de estoque
    const insertedItems: any[] = [];
    for (const it of parsed.items) {
      let matched_product_id: string | null = null;
      if (it.c_prod) {
        const { data: bySku } = await admin
          .from("products")
          .select("id")
          .eq("sku", it.c_prod)
          .maybeSingle();
        if (bySku) matched_product_id = bySku.id;
      }
      if (!matched_product_id && it.ean && it.ean !== "SEM GTIN") {
        const { data: byEan } = await admin
          .from("products")
          .select("id")
          .eq("barcode", it.ean)
          .maybeSingle();
        if (byEan) matched_product_id = byEan.id;
      }

      let inventory_movement_id: string | null = null;
      if (createInventory && matched_product_id && it.q_com > 0) {
        const { data: mov } = await admin
          .from("inventory_movements")
          .insert({
            product_id: matched_product_id,
            movement_type: "purchase",
            quantity_delta: it.q_com,
            reference_type: "fiscal_note",
            reference_id: note.id,
            unit_cost_snapshot: it.v_un_com,
            notes: `NFe ${parsed.nfe_number || ""} - ${it.x_prod || ""}`,
            created_by: userId,
          })
          .select("id")
          .single();
        if (mov) {
          inventory_movement_id = mov.id;
          // Atualiza saldo
          const { data: prod } = await admin
            .from("products")
            .select("stock_quantity, cost_price")
            .eq("id", matched_product_id)
            .single();
          if (prod) {
            await admin
              .from("products")
              .update({
                stock_quantity: Number(prod.stock_quantity || 0) + it.q_com,
                cost_price: it.v_un_com || prod.cost_price,
              })
              .eq("id", matched_product_id);
          }
        }
      }

      const { data: row } = await admin
        .from("fiscal_note_items")
        .insert({
          fiscal_note_id: note.id,
          c_prod: it.c_prod,
          x_prod: it.x_prod,
          ncm: it.ncm,
          unit: it.unit,
          q_com: it.q_com,
          v_un_com: it.v_un_com,
          v_prod: it.v_prod,
          matched_product_id,
          inventory_movement_id,
        })
        .select()
        .single();
      if (row) insertedItems.push(row);
    }

    return jr({
      ok: true,
      fiscal_note_id: note.id,
      payable_id,
      items_count: insertedItems.length,
      matched_count: insertedItems.filter((i) => i.matched_product_id).length,
      parsed,
    });
  } catch (e: any) {
    console.error("process-nfe-xml error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
