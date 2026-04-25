INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_public_read' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_public_read"
    ON storage.objects FOR SELECT USING (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_write' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_write"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_update' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_update"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'company-assets');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'company_assets_auth_delete' AND tablename = 'objects' AND schemaname = 'storage') THEN
    CREATE POLICY "company_assets_auth_delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'company-assets');
  END IF;
END $$;