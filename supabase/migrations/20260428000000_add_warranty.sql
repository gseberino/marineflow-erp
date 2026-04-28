-- Adiciona campos de garantia para controle a nível de item e serviço
ALTER TABLE "public"."service_order_parts" ADD COLUMN IF NOT EXISTS "warranty_days" integer DEFAULT 0;
ALTER TABLE "public"."service_order_services" ADD COLUMN IF NOT EXISTS "warranty_days" integer DEFAULT 0;

-- Para produtos novos, podemos também colocar no cadastro base, mas para o controle de OS a nível de item, isso é suficiente.
ALTER TABLE "public"."products" ADD COLUMN IF NOT EXISTS "default_warranty_days" integer DEFAULT 0;
ALTER TABLE "public"."services" ADD COLUMN IF NOT EXISTS "default_warranty_days" integer DEFAULT 0;
