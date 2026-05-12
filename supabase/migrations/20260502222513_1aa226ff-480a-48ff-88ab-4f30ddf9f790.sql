CREATE TABLE IF NOT EXISTS public.service_order_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  uploaded_by uuid REFERENCES public.app_users(id),
  storage_path text NOT NULL,
  public_url text NOT NULL,
  caption text,
  photo_type text NOT NULL DEFAULT 'progress'
    CHECK (photo_type IN ('before','progress','after','problem'))
);

CREATE INDEX IF NOT EXISTS idx_so_photos_order ON public.service_order_photos(service_order_id);

ALTER TABLE public.service_order_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "so_photos_auth" ON public.service_order_photos
  FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

INSERT INTO storage.buckets (id, name, public)
VALUES ('service-order-photos', 'service-order-photos', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  public = EXCLUDED.public;

DROP POLICY IF EXISTS "so_photos_bucket_select" ON storage.objects;
CREATE POLICY "so_photos_bucket_select" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'service-order-photos');

DROP POLICY IF EXISTS "so_photos_bucket_insert" ON storage.objects;
CREATE POLICY "so_photos_bucket_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'service-order-photos');

DROP POLICY IF EXISTS "so_photos_bucket_update" ON storage.objects;
CREATE POLICY "so_photos_bucket_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'service-order-photos');

DROP POLICY IF EXISTS "so_photos_bucket_delete" ON storage.objects;
CREATE POLICY "so_photos_bucket_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'service-order-photos');