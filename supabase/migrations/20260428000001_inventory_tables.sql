-- Tabelas para suporte a Notas Fiscais e XML
CREATE TABLE IF NOT EXISTS "public"."fiscal_notes" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "company_id" uuid,
    "nfe_key" text UNIQUE,
    "nfe_number" text,
    "issue_date" timestamp with time zone,
    "issuer_name" text,
    "issuer_cnpj" text,
    "total_value" numeric(12,2),
    "xml_url" text,
    "status" text DEFAULT 'pending', -- pending, processed, error
    "created_at" timestamp with time zone DEFAULT now(),
    "updated_at" timestamp with time zone DEFAULT now()
);

-- Relacionar itens da nota fiscal com produtos do sistema
CREATE TABLE IF NOT EXISTS "public"."fiscal_note_items" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "fiscal_note_id" uuid REFERENCES "public"."fiscal_notes"("id") ON DELETE CASCADE,
    "product_id" uuid REFERENCES "public"."products"("id"),
    "item_index" integer,
    "description" text,
    "sku_internal" text,
    "sku_supplier" text,
    "quantity" numeric(12,4),
    "unit_price" numeric(12,2),
    "total_price" numeric(12,2),
    "ncm" text,
    "cfop" text,
    "processed" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT now()
);

-- Adicionar campo para controlar última entrada no produto
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "last_stock_entry_at" timestamp with time zone;
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "supplier_id" uuid REFERENCES "public"."suppliers"("id");
