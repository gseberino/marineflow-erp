DROP POLICY IF EXISTS "allow_all_app_users" ON public.app_users;
DROP POLICY IF EXISTS "allow_read_app_users" ON public.app_users;
DROP POLICY IF EXISTS "allow_update_self" ON public.app_users;

CREATE POLICY "allow_read_app_users" ON public.app_users FOR SELECT TO authenticated USING (true);
CREATE POLICY "allow_update_self" ON public.app_users FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "allow_admin_all" ON public.app_users FOR ALL TO authenticated USING (
  (SELECT role FROM public.app_users WHERE id = auth.uid()) = 'admin'
);
