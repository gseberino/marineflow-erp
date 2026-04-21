ALTER TABLE service_orders 
ADD COLUMN IF NOT EXISTS share_token UUID DEFAULT gen_random_uuid() UNIQUE;

CREATE INDEX IF NOT EXISTS idx_service_orders_share_token ON service_orders(share_token);

CREATE POLICY "Public document viewing via share_token" ON service_orders
  FOR SELECT
  TO anon
  USING (share_token IS NOT NULL);

CREATE POLICY "Public parts viewing via service order" ON service_order_parts
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public services viewing via service order" ON service_order_services
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public company settings viewing" ON app_settings
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public clients viewing via service order" ON clients
  FOR SELECT TO anon USING (TRUE);

CREATE POLICY "Public vessels viewing via service order" ON vessels
  FOR SELECT TO anon USING (TRUE);