-- RESTRICTIVE policy to prevent anon/authenticated roles from reading or
-- writing internal secret keys stored in app_settings.
--
-- Background: app_settings has several broad PERMISSIVE policies (including
-- staging_open_*) that allow anon/authenticated full CRUD with no row filter.
-- This RESTRICTIVE policy intersects with all of them to block access to any
-- key prefixed 'cron_' or 'internal_'.
--
-- Service role (used by Edge Functions and pg_cron) bypasses RLS entirely,
-- so cron job secret lookups are unaffected.
CREATE POLICY "deny_internal_secrets"
ON public.app_settings
AS RESTRICTIVE
FOR ALL
TO anon, authenticated
USING (key NOT LIKE 'cron_%' AND key NOT LIKE 'internal_%')
WITH CHECK (key NOT LIKE 'cron_%' AND key NOT LIKE 'internal_%');
