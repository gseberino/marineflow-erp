-- Bucket público para PDFs enviados ao cliente
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('documents', 'documents', true, 26214400, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policies (idempotentes)
DROP POLICY IF EXISTS "documents_public_read" ON storage.objects;
CREATE POLICY "documents_public_read"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_insert" ON storage.objects;
CREATE POLICY "documents_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_update" ON storage.objects;
CREATE POLICY "documents_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'documents')
WITH CHECK (bucket_id = 'documents');

DROP POLICY IF EXISTS "documents_authenticated_delete" ON storage.objects;
CREATE POLICY "documents_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'documents');