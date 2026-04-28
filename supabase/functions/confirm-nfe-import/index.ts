import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const { p_note_id, p_supplier_id, p_manual_mappings } = await req.json();

    if (!p_note_id) throw new Error("note_id é obrigatório");

    // 1. Buscar a nota fiscal e seus itens
    const { data: note, error: noteErr } = await supabase
      .from("fiscal_notes")
      .select("*")
      .eq("id", p_note_id)
      .single();

    if (noteErr || !note) throw new Error("Nota fiscal não encontrada");
    if (note.status === "confirmed") throw new Error("Esta nota já foi confirmada anteriormente.");

    const items = note.items || [];
    const mappings = p_manual_mappings || []; // Array de { sku_supplier, internal_product_id }

    // 2. Processar cada item
    for (const item of items) {
      const skuSupplier = item.sku_supplier;
      // Tentar encontrar o ID do produto interno (pelo mapeamento manual ou existente)
      let productId = mappings.find((m: any) => m.sku_supplier === skuSupplier)?.internal_product_id;

      if (!productId) {
        const { data: existingMapping } = await supabase
          .from("supplier_product_mappings")
          .select("internal_product_id")
          .eq("supplier_id", p_supplier_id)
          .eq("supplier_sku", skuSupplier)
          .maybeSingle();
        productId = existingMapping?.internal_product_id;
      }

      // Se localizou o produto interno, atualizamos estoque e preços
      if (productId) {
        const { data: product } = await supabase
          .from("products")
          .select("cost_price, stock_quantity, sale_price")
          .eq("id", productId)
          .single();

        if (product) {
          const oldCost = product.cost_price || 0;
          const newCost = item.unit_price;
          
          // Registrar histórico de preço
          await supabase.from("product_price_history").insert({
            product_id: productId,
            old_cost: oldCost,
            new_cost: newCost,
            fiscal_note_id: p_note_id
          });

          // Sugerir atualização de preço de venda se o custo subiu
          if (newCost > oldCost && product.sale_price) {
            const margin = ((product.sale_price - newCost) / newCost) * 100;
            await supabase.from("price_update_suggestions").insert({
              product_id: productId,
              fiscal_note_id: p_note_id,
              current_sale_price: product.sale_price,
              suggested_sale_price: newCost * 1.5, // Sugestão base 50%
              margin_percent: margin
            });
          }

          // Atualizar estoque e custo médio/último custo
          await supabase.from("products").update({
            cost_price: newCost,
            stock_quantity: (product.stock_quantity || 0) + item.quantity,
            last_stock_entry_at: new Date().toISOString()
          }).eq("id", productId);

          // Registrar movimentação de estoque
          await supabase.from("inventory_movements").insert({
            product_id: productId,
            quantity_delta: item.quantity,
            movement_type: "purchase",
            reference_type: "fiscal_note",
            reference_id: p_note_id,
            unit_cost: newCost,
            notes: `Entrada via NF-e ${note.nfe_number}`
          });
        }

        // Garantir que o mapeamento exista para a próxima vez
        await supabase.from("supplier_product_mappings").upsert({
          supplier_id: p_supplier_id,
          supplier_sku: skuSupplier,
          internal_product_id: productId,
          supplier_description: item.description
        }, { onConflict: 'supplier_id, supplier_sku' });
      }
    }

    // 3. Criar o Contas a Pagar (Payable)
    await supabase.from("payables").insert({
      description: `Pagamento NF-e ${note.nfe_number} - ${note.issuer_name}`,
      amount: note.total_amount,
      balance_amount: note.total_amount,
      currency: "BRL",
      issue_date: note.issued_at,
      due_date: note.issued_at, // O usuário pode ajustar depois
      status: "pending",
      supplier_id: p_supplier_id,
      origin: "fiscal_note",
      linked_fiscal_note_id: p_note_id,
      cost_center_id: "0a1e2b3c-4d5e-6f7g-8h9i-0j1k2l3m4n5o" // Categoria padrão: Compras de Mercadoria
    });

    // 4. Finalizar nota
    await supabase.from("fiscal_notes").update({
      status: "confirmed",
      confirmed_at: new Date().toISOString()
    }).eq("id", p_note_id);

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
