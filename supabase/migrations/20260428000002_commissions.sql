-- Tabela de Comissões
CREATE TABLE IF NOT EXISTS "public"."commissions" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "service_order_id" uuid REFERENCES "public"."service_orders"("id") ON DELETE CASCADE,
    "user_id" uuid REFERENCES "public"."app_users"("id"), -- Técnico ou Vendedor
    "amount" numeric(12,2) NOT NULL,
    "base_value" numeric(12,2), -- Valor base para o cálculo (ex: lucro ou total)
    "percentage" numeric(5,2),
    "status" text DEFAULT 'pending', -- pending, approved, paid, cancelled
    "paid_at" timestamp with time zone,
    "payable_id" uuid REFERENCES "public"."payables"("id"), -- Vínculo com o financeiro
    "created_at" timestamp with time zone DEFAULT now(),
    "updated_at" timestamp with time zone DEFAULT now()
);

-- Habilitar RLS
ALTER TABLE "public"."commissions" ENABLE ROW LEVEL SECURITY;

-- Política simples: admin vê tudo, técnico vê as suas
CREATE POLICY "Admins can do everything on commissions" ON "public"."commissions"
    FOR ALL TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Users can view own commissions" ON "public"."commissions"
    FOR SELECT TO authenticated USING (auth.uid() = user_id);
