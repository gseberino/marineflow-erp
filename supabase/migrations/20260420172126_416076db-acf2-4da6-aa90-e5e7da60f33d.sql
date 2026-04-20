DROP POLICY IF EXISTS "allow_all_app_settings" ON app_settings;
DROP POLICY IF EXISTS "Enable read access for all users" ON app_settings;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON app_settings;
DROP POLICY IF EXISTS "Enable update for authenticated users only" ON app_settings;
DROP POLICY IF EXISTS "authenticated_full_access" ON app_settings;
DROP POLICY IF EXISTS "app_settings_delete_admin" ON app_settings;
DROP POLICY IF EXISTS "app_settings_select_auth" ON app_settings;
DROP POLICY IF EXISTS "app_settings_update_admin" ON app_settings;
DROP POLICY IF EXISTS "app_settings_write_admin" ON app_settings;
DROP POLICY IF EXISTS "anon_read_app_settings" ON app_settings;

CREATE POLICY "authenticated_full_access" ON app_settings
  AS PERMISSIVE FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "anon_read_app_settings" ON app_settings
  AS PERMISSIVE FOR SELECT
  TO anon
  USING (true);