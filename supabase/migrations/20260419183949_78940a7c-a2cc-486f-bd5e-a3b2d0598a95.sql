-- Helper function: check admin without recursion
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'admin' AND active = true
  )
$$;

-- Generic: replace allow_all_* policies on most tables with authenticated-only
DO $$
DECLARE
  t text;
  tbls text[] := ARRAY[
    'bank_transactions','card_installment_fees','clients','exchange_rates',
    'financial_categories','import_sessions','inventory_movements','invoices',
    'marinas','payables','payments','product_categories','product_suppliers',
    'products','receivables','saved_filters','service_order_expenses',
    'service_order_parts','service_order_services','service_order_technicians',
    'service_orders','services','suppliers','time_entries','vessel_contacts','vessels'
  ];
BEGIN
  FOREACH t IN ARRAY tbls LOOP
    EXECUTE format('DROP POLICY IF EXISTS allow_all_%I ON public.%I', t, t);
    EXECUTE format($f$
      CREATE POLICY "authenticated_all_%1$s" ON public.%1$I
      FOR ALL TO authenticated
      USING (auth.uid() IS NOT NULL)
      WITH CHECK (auth.uid() IS NOT NULL)
    $f$, t);
  END LOOP;
END $$;

-- Also handle the historical name variants that don't follow allow_all_<table>
DROP POLICY IF EXISTS allow_all_card_fees ON public.card_installment_fees;
DROP POLICY IF EXISTS allow_all_financial_categories ON public.financial_categories;

-- Sensitive tables: read for any authenticated, write for admins only
-- app_settings
DROP POLICY IF EXISTS allow_all_app_settings ON public.app_settings;
CREATE POLICY "app_settings_select_auth" ON public.app_settings
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_settings_update_admin" ON public.app_settings
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_settings_delete_admin" ON public.app_settings
  FOR DELETE TO authenticated USING (public.is_admin(auth.uid()));

-- audit_log
DROP POLICY IF EXISTS allow_all_audit_log ON public.audit_log;
CREATE POLICY "audit_log_select_auth" ON public.audit_log
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "audit_log_insert_auth" ON public.audit_log
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
-- no update/delete on audit_log

-- app_users
DROP POLICY IF EXISTS allow_all_app_users ON public.app_users;
CREATE POLICY "app_users_select_auth" ON public.app_users
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "app_users_insert_admin" ON public.app_users
  FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_users_update_admin" ON public.app_users
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "app_users_delete_admin" ON public.app_users
  FOR DELETE TO authenticated USING (public.is_admin(auth.uid()));