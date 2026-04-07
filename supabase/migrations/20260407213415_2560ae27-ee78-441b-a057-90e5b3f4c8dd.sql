
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'clients', 'vessels', 'marinas', 'products', 'service_orders',
    'service_order_technicians', 'service_order_parts', 'time_entries',
    'inventory_movements', 'invoices', 'receivables', 'payables',
    'exchange_rates', 'app_settings', 'app_users', 'suppliers',
    'product_suppliers'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS "allow_all_%s" ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "Authenticated users can do everything on %s" ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "Authenticated users can do everything on %s" ON %I', regexp_replace(t, '_', ' ', 'g'), t);
    EXECUTE format(
      'CREATE POLICY "allow_all_%s" ON %I AS PERMISSIVE FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)',
      t, t
    );
  END LOOP;
END $$;
