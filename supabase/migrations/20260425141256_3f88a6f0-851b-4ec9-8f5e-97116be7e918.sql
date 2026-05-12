INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  public = EXCLUDED.public;

DROP POLICY IF EXISTS "company_assets_public_read" ON storage.objects;
CREATE POLICY "company_assets_public_read"
ON storage.objects FOR SELECT USING (bucket_id = 'company-assets');

DROP POLICY IF EXISTS "company_assets_auth_write" ON storage.objects;
CREATE POLICY "company_assets_auth_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'company-assets');

DROP POLICY IF EXISTS "company_assets_auth_update" ON storage.objects;
CREATE POLICY "company_assets_auth_update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'company-assets');

DROP POLICY IF EXISTS "company_assets_auth_delete" ON storage.objects;
CREATE POLICY "company_assets_auth_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'company-assets');